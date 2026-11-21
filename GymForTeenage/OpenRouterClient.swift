import CryptoKit
import Foundation

// OpenRouterClient реализует OpenAI-совместимый API для OpenRouter
// Он использует POST /chat/completions с заголовком Authorization: Bearer <apiKey>
// и заголовками HTTP-Referer и X-Title

struct OpenAIChatMessage: Codable {
    let role: String
    let content: String
}

struct OpenAIChatCompletionRequest: Codable {
    let model: String
    let messages: [OpenAIChatMessage]
    let temperature: Double?
    let max_tokens: Int?
}

struct OpenAIChatCompletionChoice: Codable {
    let message: OpenAIChatMessage?
    let finish_reason: String?
}

struct OpenAIChatCompletionResponse: Codable {
    let choices: [OpenAIChatCompletionChoice]?
    
    var firstText: String? {
        guard let choice = choices?.first else { return nil }
        return choice.message?.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

actor OpenRouterClient: GeminiGenerating {
    static let shared = OpenRouterClient()
    
    private let session: URLSession
    private let requestTimeout: TimeInterval
    private let resourceTimeout: TimeInterval
    private let maximumResponseBytes: Int
    private let maximumRetryAttempts: Int
    private let retryBaseDelay: TimeInterval
    private let maximumRetryDelay: TimeInterval
    private let defaultRateLimitDelay: TimeInterval
    private let modelID: String
    private let referer: String?
    private let title: String?
    
    init(
        session: URLSession? = nil,
        modelID: String = "openrouter/free",
        referer: String? = "https://github.com/GYMFORTEENAGE",
        title: String? = "GYMFORTEENAGE",
        requestTimeout: TimeInterval = 30,
        resourceTimeout: TimeInterval = 60,
        maximumResponseBytes: Int = 256_000,
        maximumRetryAttempts: Int = 2,
        retryBaseDelay: TimeInterval = 0.4,
        maximumRetryDelay: TimeInterval = 8,
        defaultRateLimitDelay: TimeInterval = 30
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
        self.modelID = modelID
        self.referer = referer
        self.title = title
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
        self.maximumResponseBytes = maximumResponseBytes
        self.maximumRetryAttempts = maximumRetryAttempts
        self.retryBaseDelay = retryBaseDelay
        self.maximumRetryDelay = maximumRetryDelay
        self.defaultRateLimitDelay = defaultRateLimitDelay
    }
    
    func generateContent(_ request: GeminiGenerateContentRequest, apiKey: String) async throws -> String {
        try await generateChatContent(request, apiKey: apiKey)
    }
    
    func generateChatContent(_ request: GeminiGenerateContentRequest, apiKey: String) async throws -> String {
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        
        var messages: [OpenAIChatMessage] = []
        
        // Добавляем системную инструкцию
        if let systemInstruction = request.systemInstruction,
           let text = systemInstruction.parts.first?.text {
            messages.append(OpenAIChatMessage(role: "system", content: text))
        }
        
        // Добавляем сообщения пользователя и ассистента
        for geminiContent in request.contents {
            let role = geminiContent.role == "user" ? "user" : "assistant"
            let content = geminiContent.parts.map { $0.text }.joined()
            messages.append(OpenAIChatMessage(role: role, content: content))
        }
        
        let openAIRequest = OpenAIChatCompletionRequest(
            model: modelID,
            messages: messages,
            temperature: request.generationConfig?.temperature,
            max_tokens: request.generationConfig?.maxOutputTokens
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let body = try? encoder.encode(openAIRequest) else {
            throw GeminiClientError.invalidRequest
        }
        
        var urlRequest = URLRequest(url: url, timeoutInterval: min(requestTimeout, resourceTimeout))
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        if let referer = referer {
            urlRequest.setValue(referer, forHTTPHeaderField: "HTTP-Referer")
        }
        if let title = title {
            urlRequest.setValue(title, forHTTPHeaderField: "X-Title")
        }
        
        var retryIndex = 0
        while true {
            if Task.isCancelled { throw GeminiClientError.cancelled }
            do {
                return try await performOnce(urlRequest: urlRequest, apiKey: apiKey, endpoint: url)
            } catch let error as GeminiClientError {
                guard retryIndex < maximumRetryAttempts, isTransient(error) else { throw error }
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
    
    func generateInsightsContent(_ request: GeminiGenerateContentRequest, apiKey: String) async throws -> String {
        try await generateContent(request, apiKey: apiKey)
    }
    
    private func performOnce(urlRequest: URLRequest, apiKey: String, endpoint: URL) async throws -> String {
        let (data, response) = try await session.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiClientError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 { throw GeminiClientError.unauthorized }
        if httpResponse.statusCode == 403 { throw GeminiClientError.forbidden }
        if httpResponse.statusCode == 429 {
            throw GeminiClientError.rateLimited(retryAfter: 30)
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if (500..<600).contains(httpResponse.statusCode) {
                throw GeminiClientError.server(status: httpResponse.statusCode)
            }
            let serverMessage = safeServerMessage(from: data, redacting: apiKey)
            throw GeminiClientError.rejected(status: httpResponse.statusCode, message: serverMessage)
        }
        
        guard data.count <= maximumResponseBytes else { throw GeminiClientError.responseTooLarge }
        
        let decoded: OpenAIChatCompletionResponse
        do {
            decoded = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
        } catch {
            throw GeminiClientError.invalidResponse
        }
        
        guard let text = decoded.firstText, !text.isEmpty else {
            throw GeminiClientError.emptyResponse
        }
        
        return text
    }
    
    private func isTransient(_ error: GeminiClientError) -> Bool {
        switch error {
        case .timedOut, .transport: return true
        case .server(status: 500), .server(status: 502), .server(status: 503), .server(status: 504): return true
        default: return false
        }
    }
    
    private func safeServerMessage(from data: Data, redacting secret: String) -> String? {
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
}
