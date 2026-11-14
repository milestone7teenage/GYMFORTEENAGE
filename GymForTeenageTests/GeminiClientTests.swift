import Foundation
import XCTest
@testable import GymForTeenage

final class GeminiClientTests: XCTestCase {
    func testRequestIsCodableAndKeepsAPIKeyOutOfBody() throws {
        let request = GeminiGenerateContentRequest(
            contents: [GeminiContent(role: "user", text: "How did my workout go?")],
            systemInstruction: AIConfiguration.systemInstruction
        )
        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["systemInstruction"])
        XCTAssertNotNil(object["generationConfig"])
        XCTAssertNotNil(object["contents"])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("test-api-key"))
    }

    func testSuccessUsesKeyHeaderAndDecodesText() async throws {
        let host = UUID().uuidString + ".test"
        let response = try Self.jsonResponse(text: "Keep a steady pace.")
        GeminiURLProtocolStub.configure(host: host, replies: [response])
        defer { GeminiURLProtocolStub.remove(host: host) }
        let (client, session, endpoint) = Self.makeClient(host: host)
        defer { session.invalidateAndCancel() }

        let outbound = GeminiGenerateContentRequest(
            contents: Self.request.contents,
            systemInstruction: AIConfiguration.systemInstruction,
            generationConfig: Self.request.generationConfig
        )
        let body = try JSONEncoder().encode(outbound)
        let urlRequest = GeminiURLRequestFactory.make(
            body: body,
            apiKey: "test-api-key",
            endpoint: endpoint,
            timeoutInterval: 2
        )
        XCTAssertFalse(String(decoding: try XCTUnwrap(urlRequest.httpBody), as: UTF8.self).contains("test-api-key"))
        XCTAssertNil(URLComponents(url: try XCTUnwrap(urlRequest.url), resolvingAgainstBaseURL: false)?.query)
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "x-goog-api-key"), "test-api-key")

        let text = try await client.generateContent(Self.request, apiKey: "test-api-key")

        XCTAssertEqual(text, "Keep a steady pace.")
        let captured = try XCTUnwrap(GeminiURLProtocolStub.requests(for: host).first)
        XCTAssertEqual(captured.value(forHTTPHeaderField: "x-goog-api-key"), "test-api-key")
        XCTAssertEqual(captured.httpMethod, "POST")
        XCTAssertFalse(String(decoding: try XCTUnwrap(urlRequest.httpBody), as: UTF8.self).localizedCaseInsensitiveContains("googleSearch"))
        XCTAssertTrue(endpoint.absoluteString.hasPrefix("https://"))
    }

    @MainActor
    func testChatIsReadOnlyAndNeverSendsKeyOrStoreUUIDInURLOrBody() async throws {
        let host = UUID().uuidString + ".test"
        GeminiURLProtocolStub.configure(host: host, replies: [try Self.jsonResponse(text: "Сохраняй спокойный темп.")])
        defer { GeminiURLProtocolStub.remove(host: host) }
        let (client, session, _) = Self.makeClient(host: host)
        defer { session.invalidateAndCancel() }
        let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let store = Store(fileURL: storeURL)
        var exercise = ExerciseLog(slotID: "sensitive-slot", exerciseID: "butterfly", actualID: "butterfly", status: "completed")
        exercise.sets = [SetLog(weight: "25", reps: "8", skipped: false)]
        let record = Record(workoutID: Catalog.workouts[0].id, name: "Тренировка", date: Date(), exercises: [exercise])
        store.records = [record]
        let measurement = Measure(kind: "weight", value: 62)
        store.measures = [measurement]
        let before = try JSONEncoder.pretty.encode(Backup(
            records: store.records,
            measures: store.measures,
            water: store.water,
            session: store.session,
            instructions: store.instructions,
            reminders: store.reminders
        ))
        let markerKey = "isolated-urlprotocol-test-key-\(UUID().uuidString)"
        let coach = AICoachSession(requestCoordinator: AIRequestCoordinator(client: client))

        let sent = await coach.send(
            "Как менялась бабочка за неделю?",
            store: store,
            apiKey: markerKey,
            isAIEnabled: true,
            consentedCategories: [.chatMessages, .exerciseHistory]
        )

        XCTAssertTrue(sent)
        let after = try JSONEncoder.pretty.encode(Backup(
            records: store.records,
            measures: store.measures,
            water: store.water,
            session: store.session,
            instructions: store.instructions,
            reminders: store.reminders
        ))
        XCTAssertEqual(after, before, "AI processing must not mutate the user's Store.")
        let captured = try XCTUnwrap(GeminiURLProtocolStub.requests(for: host).first)
        let body = String(decoding: try XCTUnwrap(captured.httpBody), as: UTF8.self)
        let requestURL = try XCTUnwrap(captured.url).absoluteString
        XCTAssertFalse(body.contains(markerKey), "The API key must not be serialized into the request body.")
        XCTAssertEqual(captured.value(forHTTPHeaderField: "x-goog-api-key"), markerKey)
        XCTAssertFalse(requestURL.contains(markerKey))
        XCTAssertFalse(body.contains(record.id.uuidString), "Local record UUIDs must not be sent.")
        XCTAssertFalse(body.contains(measurement.id.uuidString), "Local measurement UUIDs must not be sent.")
        XCTAssertFalse(requestURL.contains(record.id.uuidString))
        coach.cancelAndClear()
    }

    func testUnauthorizedMapsToSafeTypedError() async {
        let host = UUID().uuidString + ".test"
        GeminiURLProtocolStub.configure(host: host, replies: [.init(status: 401, data: Data("secret server body".utf8))])
        defer { GeminiURLProtocolStub.remove(host: host) }
        let (client, session, _) = Self.makeClient(host: host)
        defer { session.invalidateAndCancel() }

        do {
            _ = try await client.generateContent(Self.request, apiKey: "test-api-key")
            XCTFail("Expected an unauthorized error")
        } catch let error as GeminiClientError {
            XCTAssertEqual(error, .unauthorized)
            XCTAssertFalse(error.userMessage.contains("secret server body"))
            XCTAssertFalse(error.userMessage.contains("test-api-key"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testMalformedAndEmptyResponsesAreRejected() async {
        for (status, data, expected) in [
            (200, Data("not-json".utf8), GeminiClientError.invalidResponse),
            (200, Data("{\"candidates\":[]}".utf8), GeminiClientError.emptyResponse)
        ] {
            let host = UUID().uuidString + ".test"
            GeminiURLProtocolStub.configure(host: host, replies: [.init(status: status, data: data)])
            let (client, session, _) = Self.makeClient(host: host, maximumRetries: 2)
            defer { GeminiURLProtocolStub.remove(host: host); session.invalidateAndCancel() }
            do {
                _ = try await client.generateContent(Self.request, apiKey: "test-api-key")
                XCTFail("Expected response validation to fail")
            } catch let error as GeminiClientError {
                XCTAssertEqual(error, expected)
                XCTAssertEqual(GeminiURLProtocolStub.requestCount(for: host), 1)
            } catch {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }

    func testBadRequestAndForbiddenResponsesAreTypedWithoutBodyLeak() async {
        for (status, expected) in [(400, GeminiClientError.rejected(status: 400)), (403, .forbidden)] {
            let host = UUID().uuidString + ".test"
            GeminiURLProtocolStub.configure(host: host, replies: [.init(status: status, data: Data("private server details".utf8))])
            let (client, session, _) = Self.makeClient(host: host, maximumRetries: 2)
            defer { GeminiURLProtocolStub.remove(host: host); session.invalidateAndCancel() }
            do {
                _ = try await client.generateContent(Self.request, apiKey: "test-api-key")
                XCTFail("Expected HTTP \(status) to fail")
            } catch let error as GeminiClientError {
                XCTAssertEqual(error, expected)
                XCTAssertFalse(error.userMessage.contains("private server details"))
                XCTAssertEqual(GeminiURLProtocolStub.requestCount(for: host), 1)
            } catch {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }

    func testServerFailureRetriesWithinConfiguredLimit() async throws {
        let host = UUID().uuidString + ".test"
        let success = try Self.jsonResponse(text: "Recovered")
        GeminiURLProtocolStub.configure(host: host, replies: [
            .init(status: 503, data: Data()),
            success
        ])
        defer { GeminiURLProtocolStub.remove(host: host) }
        let (client, session, _) = Self.makeClient(host: host, maximumRetries: 1)
        defer { session.invalidateAndCancel() }

        let responseText = try await client.generateContent(Self.request, apiKey: "test-api-key")
        XCTAssertEqual(responseText, "Recovered")
        XCTAssertEqual(GeminiURLProtocolStub.requestCount(for: host), 2)
    }

    func testRateLimitRetryAfterBlocksFurtherRequests() async {
        let host = UUID().uuidString + ".test"
        GeminiURLProtocolStub.configure(host: host, replies: [
            .init(status: 429, headers: ["Retry-After": "60"], data: Data())
        ])
        defer { GeminiURLProtocolStub.remove(host: host) }
        let (client, session, _) = Self.makeClient(host: host)
        defer { session.invalidateAndCancel() }

        for _ in 0..<2 {
            do {
                _ = try await client.generateContent(Self.request, apiKey: "test-api-key")
                XCTFail("Expected a rate-limit error")
            } catch let error as GeminiClientError {
                guard case .rateLimited(let seconds) = error else {
                    XCTFail("Unexpected error: \(error)")
                    continue
                }
                XCTAssertGreaterThan(seconds, 0)
            } catch {
                XCTFail("Unexpected error type: \(error)")
            }
        }
        XCTAssertEqual(GeminiURLProtocolStub.requestCount(for: host), 1)
    }

    func testIdenticalConcurrentRequestsShareOneNetworkOperation() async throws {
        let host = UUID().uuidString + ".test"
        let response = try Self.jsonResponse(text: "One response", delay: 0.2)
        GeminiURLProtocolStub.configure(host: host, replies: [response])
        defer { GeminiURLProtocolStub.remove(host: host) }
        let (client, session, _) = Self.makeClient(host: host)
        defer { session.invalidateAndCancel() }

        async let first = client.generateContent(Self.request, apiKey: "test-api-key")
        async let second = client.generateContent(Self.request, apiKey: "test-api-key")
        let results = try await [first, second]

        XCTAssertEqual(results, ["One response", "One response"])
        XCTAssertEqual(GeminiURLProtocolStub.requestCount(for: host), 1)
    }

    func testCancellingLastWaiterCancelsUnderlyingRequest() async throws {
        let host = UUID().uuidString + ".test"
        let response = try Self.jsonResponse(text: "Late", delay: 5)
        GeminiURLProtocolStub.configure(host: host, replies: [response])
        defer { GeminiURLProtocolStub.remove(host: host) }
        let (client, session, _) = Self.makeClient(host: host)
        defer { session.invalidateAndCancel() }

        let task = Task { try await client.generateContent(Self.request, apiKey: "test-api-key") }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch let error as GeminiClientError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testResponseSizeLimitAndMissingKeyAreEnforced() async throws {
        let host = UUID().uuidString + ".test"
        let response = try Self.jsonResponse(text: "A response longer than the configured limit")
        GeminiURLProtocolStub.configure(host: host, replies: [response])
        defer { GeminiURLProtocolStub.remove(host: host) }
        let (client, session, _) = Self.makeClient(host: host, maximumResponseBytes: 10)
        defer { session.invalidateAndCancel() }

        do {
            _ = try await client.generateContent(Self.request, apiKey: "  ")
            XCTFail("Expected a missing-key error")
        } catch let error as GeminiClientError {
            XCTAssertEqual(error, .missingAPIKey)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
        XCTAssertEqual(GeminiURLProtocolStub.requestCount(for: host), 0)

        do {
            _ = try await client.generateContent(Self.request, apiKey: "test-api-key")
            XCTFail("Expected a response-size error")
        } catch let error as GeminiClientError {
            XCTAssertEqual(error, .responseTooLarge)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testTimeoutMapsToTypedErrorWithoutRetryWhenDisabled() async throws {
        let host = UUID().uuidString + ".test"
        let response = try Self.jsonResponse(text: "Late", delay: 1)
        GeminiURLProtocolStub.configure(host: host, replies: [response])
        defer { GeminiURLProtocolStub.remove(host: host) }
        let (client, session, _) = Self.makeClient(host: host, timeout: 0.05, maximumRetries: 0)
        defer { session.invalidateAndCancel() }

        do {
            _ = try await client.generateContent(Self.request, apiKey: "test-api-key")
            XCTFail("Expected a timeout")
        } catch let error as GeminiClientError {
            XCTAssertEqual(error, .timedOut)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    private static let request = GeminiGenerateContentRequest(
        contents: [GeminiContent(role: "user", text: "Summarize this workout.")]
    )

    private static func makeClient(
        host: String,
        timeout: TimeInterval = 2,
        maximumResponseBytes: Int = 16_384,
        maximumRetries: Int = 0
    ) -> (GeminiClient, URLSession, URL) {
        let endpoint = URL(string: "https://\(host)/v1beta/models/gemini-3.1-flash-lite:generateContent")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GeminiURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let client = GeminiClient(
            session: session,
            endpoint: endpoint,
            requestTimeout: timeout,
            maximumResponseBytes: maximumResponseBytes,
            maximumRetryAttempts: maximumRetries,
            retryBaseDelay: 0,
            maximumRetryDelay: 0
        )
        return (client, session, endpoint)
    }

    private static func jsonResponse(text: String, delay: TimeInterval = 0) throws -> GeminiURLProtocolStub.Reply {
        let data = try JSONSerialization.data(withJSONObject: [
            "candidates": [["content": ["parts": [["text": text]]], "finishReason": "STOP"]]
        ])
        return .init(status: 200, data: data, delay: delay)
    }
}

private final class GeminiURLProtocolStub: URLProtocol {
    struct Reply {
        let status: Int
        var headers: [String: String] = [:]
        let data: Data
        var delay: TimeInterval = 0
    }

    private static let lock = NSLock()
    private static var repliesByHost: [String: [Reply]] = [:]
    private static var requestsByHost: [String: [URLRequest]] = [:]
    private static var countsByHost: [String: Int] = [:]
    private let stateLock = NSLock()
    private var stopped = false

    static func configure(host: String, replies: [Reply]) {
        lock.lock()
        defer { lock.unlock() }
        repliesByHost[host] = replies
        requestsByHost[host] = []
        countsByHost[host] = 0
    }

    static func remove(host: String) {
        lock.lock()
        defer { lock.unlock() }
        repliesByHost.removeValue(forKey: host)
        requestsByHost.removeValue(forKey: host)
        countsByHost.removeValue(forKey: host)
    }

    static func requestCount(for host: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return countsByHost[host, default: 0]
    }

    static func requests(for host: String) -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requestsByHost[host, default: []]
    }

    private static func takeReply(for host: String, request: URLRequest) -> Reply? {
        lock.lock()
        defer { lock.unlock() }
        requestsByHost[host, default: []].append(request)
        countsByHost[host, default: 0] += 1
        guard var replies = repliesByHost[host], !replies.isEmpty else { return nil }
        let first = replies.removeFirst()
        repliesByHost[host] = replies
        return first
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix(".test") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let host = request.url?.host,
              let reply = Self.takeReply(for: host, request: request),
              let response = HTTPURLResponse(
                url: request.url!,
                statusCode: reply.status,
                httpVersion: "HTTP/1.1",
                headerFields: reply.headers
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { [weak self] in
            guard let self, !self.isStopped else { return }
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: reply.data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        stateLock.lock()
        stopped = true
        stateLock.unlock()
    }

    private var isStopped: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stopped
    }
}
