import CryptoKit
import Foundation
import os

protocol GeminiGenerating: Sendable {
    func generateContent(_ request: GeminiGenerateContentRequest, apiKey: String) async throws -> String
    func generateInsightsContent(_ request: GeminiGenerateContentRequest, apiKey: String) async throws -> String
    func generateChatContent(_ request: GeminiGenerateContentRequest, apiKey: String) async throws -> String
}

extension GeminiGenerating {
    func generateInsightsContent(_ request: GeminiGenerateContentRequest, apiKey: String) async throws -> String {
        try await generateContent(request, apiKey: apiKey)
    }

    func generateChatContent(_ request: GeminiGenerateContentRequest, apiKey: String) async throws -> String {
        try await generateContent(request, apiKey: apiKey)
    }
}

actor GeminiClient: GeminiGenerating {
    static let shared = GeminiClient()
    private struct Flight {
        let token: UUID
        let task: Task<String, Error>
        var waiters: Set<UUID>
    }

    private let session: URLSession
    private let endpoint: URL
    private let requestTimeout: TimeInterval
    private let resourceTimeout: TimeInterval
    private let maximumResponseBytes: Int
    private let maximumRetryAttempts: Int
    private let retryBaseDelay: TimeInterval
    private let maximumRetryDelay: TimeInterval
    private let defaultRateLimitDelay: TimeInterval
    private var flights: [String: Flight] = [:]
    private var rateLimitedUntil: Date?

    init(
        session: URLSession? = nil,
        endpoint: URL = AIConfiguration.generateContentURL,
        requestTimeout: TimeInterval = AIConfiguration.requestTimeout,
        resourceTimeout: TimeInterval = AIConfiguration.resourceTimeout,
        maximumResponseBytes: Int = AIConfiguration.maximumResponseBytes,
        maximumRetryAttempts: Int = AIConfiguration.maximumRetryAttempts,
        retryBaseDelay: TimeInterval = AIConfiguration.retryBaseDelay,
        maximumRetryDelay: TimeInterval = AIConfiguration.maximumRetryDelay,
        defaultRateLimitDelay: TimeInterval = AIConfiguration.defaultRateLimitDelay
    ) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = requestTimeout
            configuration.timeoutIntervalForResource = resourceTimeout
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            self.session = URLSession(configuration: configuration)
        }
        self.endpoint = endpoint
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
        self.maximumResponseBytes = maximumResponseBytes
        self.maximumRetryAttempts = maximumRetryAttempts
        self.retryBaseDelay = retryBaseDelay
        self.maximumRetryDelay = maximumRetryDelay
        self.defaultRateLimitDelay = defaultRateLimitDelay
    }

    func generateContent(
        _ request: GeminiGenerateContentRequest,
        apiKey: String
    ) async throws -> String {
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else { throw GeminiClientError.missingAPIKey }
        guard endpoint.scheme?.lowercased() == "https", endpoint.host != nil else {
            throw GeminiClientError.invalidRequest
        }
        guard !request.contents.isEmpty,
              request.contents.allSatisfy({ !$0.parts.isEmpty }),
              request.contents.flatMap(\.parts).allSatisfy({ !$0.text.isEmpty }) else {
            throw GeminiClientError.invalidRequest
        }
        let characterCount = request.contents.flatMap(\.parts).reduce(0) { $0 + $1.text.count }
        guard characterCount <= AIConfiguration.maximumPromptCharacters else {
            throw GeminiClientError.requestTooLarge
        }

        if let rateLimitedUntil, rateLimitedUntil > Date() {
            throw GeminiClientError.rateLimited(retryAfter: max(1, Int(ceil(rateLimitedUntil.timeIntervalSinceNow))))
        }
        rateLimitedUntil = nil

        var effectiveRequest = request
        if effectiveRequest.systemInstruction == nil {
            effectiveRequest.systemInstruction = GeminiContent(text: AIConfiguration.systemInstruction)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let body = try? encoder.encode(effectiveRequest) else { throw GeminiClientError.invalidRequest }
        var fingerprintInput = Data(normalizedKey.utf8)
        fingerprintInput.append(0)
        fingerprintInput.append(body)
        fingerprintInput.append(Data(endpoint.absoluteString.utf8))
        let requestID = SHA256.hash(data: fingerprintInput).map { String(format: "%02x", $0) }.joined()
        let waiterID = UUID()

        let flight: Flight
        if var existing = flights[requestID] {
            existing.waiters.insert(waiterID)
            flights[requestID] = existing
            flight = existing
        } else {
            let token = UUID()
            let session = self.session
            let endpoint = self.endpoint
            let timeout = self.requestTimeout
            let resourceTimeout = self.resourceTimeout
            let responseLimit = self.maximumResponseBytes
            let retryCount = self.maximumRetryAttempts
            let baseDelay = self.retryBaseDelay
            let delayLimit = self.maximumRetryDelay
            let rateLimitDelay = self.defaultRateLimitDelay
            let task = Task {
                try await Self.perform(
                    body: body,
                    apiKey: normalizedKey,
                    endpoint: endpoint,
                    session: session,
                    timeout: timeout,
                    resourceTimeout: resourceTimeout,
                    responseLimit: responseLimit,
                    maximumRetries: retryCount,
                    retryBaseDelay: baseDelay,
                    maximumRetryDelay: delayLimit,
                    defaultRateLimitDelay: rateLimitDelay
                )
            }
            flight = Flight(token: token, task: task, waiters: [waiterID])
            flights[requestID] = flight
        }

        do {
            let text = try await withTaskCancellationHandler {
                try await flight.task.value
            } onCancel: {
                Task { await self.releaseWaiter(requestID, token: flight.token, waiterID: waiterID, cancelled: true) }
            }
            releaseWaiter(requestID, token: flight.token, waiterID: waiterID, cancelled: false)
            return text
        } catch {
            releaseWaiter(requestID, token: flight.token, waiterID: waiterID, cancelled: Task.isCancelled)
            if let clientError = error as? GeminiClientError {
                if case .rateLimited(let seconds) = clientError {
                    rateLimitedUntil = Date().addingTimeInterval(TimeInterval(seconds))
                }
                throw clientError
            }
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw GeminiClientError.cancelled
            }
            throw GeminiClientError.transport
        }
    }

    private func releaseWaiter(_ requestID: String, token: UUID, waiterID: UUID, cancelled: Bool) {
        guard var flight = flights[requestID], flight.token == token,
              flight.waiters.remove(waiterID) != nil else { return }
        if cancelled {
            flight.task.cancel()
            flights.removeValue(forKey: requestID)
            return
        }
        if flight.waiters.isEmpty { flights.removeValue(forKey: requestID) }
        else { flights[requestID] = flight }
    }

    private static func perform(
        body: Data,
        apiKey: String,
        endpoint: URL,
        session: URLSession,
        timeout: TimeInterval,
        resourceTimeout: TimeInterval,
        responseLimit: Int,
        maximumRetries: Int,
        retryBaseDelay: TimeInterval,
        maximumRetryDelay: TimeInterval,
        defaultRateLimitDelay: TimeInterval,
        provider: AIProvider = .googleGemini,
        referer: String? = nil,
        title: String? = nil
    ) async throws -> String {
        var retryIndex = 0
        while true {
            if Task.isCancelled { throw GeminiClientError.cancelled }
            do {
                return try await performOnce(
                    body: body,
                    apiKey: apiKey,
                    endpoint: endpoint,
                    session: session,
                    timeout: timeout,
                    resourceTimeout: resourceTimeout,
                    responseLimit: responseLimit,
                    defaultRateLimitDelay: defaultRateLimitDelay,
                    provider: currentProvider,
                    referer: referer,
                    title: title
                )
            } catch let error as GeminiClientError {
                guard retryIndex < maximumRetries, isTransient(error) else { throw error }
                let delay = min(maximumRetryDelay, retryBaseDelay * pow(2, Double(retryIndex)))
                retryIndex += 1
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    throw GeminiClientError.cancelled
                }
            }
        }
    }

    private static func performOnce(
        body: Data,
        apiKey: String,
        endpoint: URL,
        session: URLSession,
        timeout: TimeInterval,
        resourceTimeout: TimeInterval,
        responseLimit: Int,
        defaultRateLimitDelay: TimeInterval,
        provider: AIProvider = .googleGemini,
        referer: String? = nil,
        title: String? = nil
    ) async throws -> String {
        let urlRequest = GeminiURLRequestFactory.make(
            body: body,
            apiKey: apiKey,
            endpoint: endpoint,
            timeoutInterval: min(timeout, resourceTimeout),
            provider: provider,
            referer: referer,
            title: title
        )

        var data = Data()
        data.reserveCapacity(min(responseLimit, 4096))
        let httpResponse: HTTPURLResponse
        do {
            let (bytes, response) = try await session.bytes(for: urlRequest)
            guard let receivedHTTPResponse = response as? HTTPURLResponse else {
                throw GeminiClientError.invalidResponse
            }
            httpResponse = receivedHTTPResponse
            for try await byte in bytes {
                guard data.count < responseLimit else { throw GeminiClientError.responseTooLarge }
                data.append(byte)
            }
            if httpResponse.statusCode == 401 { throw GeminiClientError.unauthorized }
            if httpResponse.statusCode == 403 { throw GeminiClientError.forbidden }
            if httpResponse.statusCode == 429 {
                let delay = retryAfter(from: httpResponse, fallback: defaultRateLimitDelay)
                throw GeminiClientError.rateLimited(retryAfter: max(1, Int(ceil(delay))))
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                if (500..<600).contains(httpResponse.statusCode) {
                    logHTTPFailure(status: httpResponse.statusCode, endpoint: endpoint)
                    throw GeminiClientError.server(status: httpResponse.statusCode)
                }
                let serverMessage = safeServerMessage(from: data, redacting: apiKey)
                logHTTPFailure(status: httpResponse.statusCode, endpoint: endpoint, message: serverMessage)
                throw GeminiClientError.rejected(status: httpResponse.statusCode, message: serverMessage)
            }
        } catch let error as URLError {
            if Task.isCancelled || error.code == .cancelled { throw GeminiClientError.cancelled }
            if error.code == .timedOut { throw GeminiClientError.timedOut }
            throw GeminiClientError.transport
        } catch {
            if let clientError = error as? GeminiClientError { throw clientError }
            if Task.isCancelled { throw GeminiClientError.cancelled }
            throw GeminiClientError.transport
        }

        guard data.count <= responseLimit else { throw GeminiClientError.responseTooLarge }
        let decoded: GeminiGenerateContentResponse
        do {
            decoded = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
        } catch {
            throw GeminiClientError.invalidResponse
        }
        if decoded.firstFinishReason == "SAFETY" { throw GeminiClientError.blockedResponse }
        guard let text = decoded.firstText, !text.isEmpty else { throw GeminiClientError.emptyResponse }
        return text
    }

    private static func isTransient(_ error: GeminiClientError) -> Bool {
        switch error {
        case .timedOut, .transport: return true
        case .server(status: 500), .server(status: 502), .server(status: 503), .server(status: 504): return true
        default: return false
        }
    }

    private static func safeServerMessage(from data: Data, redacting secret: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        var safe = message
        if secret.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8 {
            safe = safe.replacingOccurrences(of: secret.trimmingCharacters(in: .whitespacesAndNewlines), with: "[REDACTED]")
        }
        let trimmed = safe.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(500))
    }

    private static func logHTTPFailure(status: Int, endpoint: URL, message: String? = nil) {
        let endpointSafe = endpoint.host ?? endpoint.absoluteString
        let safeMessage = message.map { $0.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ") } ?? ""
        os_log("Gemini request failed: status=%{public}d endpoint=%{public}s detail=%{public}s",
               log: OSLog(subsystem: "com.gymforteenage.ai", category: "GeminiClient"),
               type: .error, status, endpointSafe, safeMessage)
    }

    private static func retryAfter(from response: HTTPURLResponse, fallback: TimeInterval) -> TimeInterval {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return fallback
        }
        if let seconds = TimeInterval(value), seconds.isFinite { return max(1, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        if let date = formatter.date(from: value) { return max(1, date.timeIntervalSinceNow) }
        return fallback
    }
}

enum GeminiURLRequestFactory {
    static func make(body: Data, apiKey: String, endpoint: URL, timeoutInterval: TimeInterval, provider: AIProvider = .googleGemini, referer: String? = nil, title: String? = nil) -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        if provider.requiresAuthorizationHeader {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        }
        
        if provider.requiresRefererAndTitleHeaders {
            if let referer = referer {
                request.setValue(referer, forHTTPHeaderField: "HTTP-Referer")
            }
            if let title = title {
                request.setValue(title, forHTTPHeaderField: "X-Title")
            }
        }
        
        return request
    }
}
