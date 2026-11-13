import Foundation
import XCTest
@testable import GymForTeenage

private actor RequestCoordinatorStub: GeminiGenerating {
    private(set) var requestCount = 0
    private(set) var activeCount = 0
    private(set) var maximumActiveCount = 0
    private(set) var lastRequest: GeminiGenerateContentRequest?
    var response = "Держи спокойный темп и ориентируйся на комфорт."
    var shouldFail = false

    func generateContent(_ request: GeminiGenerateContentRequest, apiKey: String) async throws -> String {
        requestCount += 1
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        lastRequest = request
        defer { activeCount -= 1 }
        if shouldFail {
            shouldFail = false
            throw GeminiClientError.transport
        }
        if request.contents.first?.parts.first?.text == "background" {
            try await Task.sleep(for: .seconds(30))
            return "background result"
        }
        return response
    }

    func counts() -> (requests: Int, maximumConcurrent: Int) { (requestCount, maximumActiveCount) }
    func capturedRequest() -> GeminiGenerateContentRequest? { lastRequest }
    func failNextRequest() { shouldFail = true }
}

@MainActor
final class AIRequestCoordinatorTests: XCTestCase {
    func testChatCancelsBackgroundInsightsAndUsesOnlyOneNetworkSlot() async throws {
        let client = RequestCoordinatorStub()
        let coordinator = AIRequestCoordinator(client: client)
        let insights = request("background")
        let chat = request("chat")
        let backgroundTask = Task { try await coordinator.generateInsightsContent(insights, apiKey: "test-key") }
        try await Task.sleep(for: .milliseconds(100))

        let response = try await coordinator.generateChatContent(chat, apiKey: "test-key")

        XCTAssertEqual(response, "Держи спокойный темп и ориентируйся на комфорт.")
        do {
            _ = try await backgroundTask.value
            XCTFail("The background Insights request should be cancelled by chat")
        } catch let error as GeminiClientError {
            XCTAssertEqual(error, .cancelled)
        } catch is CancellationError {
            // Cancellation may surface from the injected transport before error mapping.
        } catch {
            XCTFail("Unexpected background result: \(error)")
        }
        let counts = await client.counts()
        XCTAssertEqual(counts.requests, 2)
        XCTAssertEqual(counts.maximumConcurrent, 1)
    }

    func testIdenticalInsightsCallsShareTheSameOperation() async throws {
        let client = RequestCoordinatorStub()
        let coordinator = AIRequestCoordinator(client: client)
        let request = self.request("same")

        async let first = coordinator.generateInsightsContent(request, apiKey: "test-key")
        async let second = coordinator.generateInsightsContent(request, apiKey: "test-key")
        _ = try await [first, second]

        let counts = await client.counts()
        XCTAssertEqual(counts.requests, 1)
        XCTAssertEqual(counts.maximumConcurrent, 1)
    }

    func testChatSessionBlocksAllOutboundTextWithoutConsentAndClearsOnClose() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = Store(fileURL: fileURL)
        store.records = [record(date: Date())]
        let client = RequestCoordinatorStub()
        let session = AICoachSession(requestCoordinator: AIRequestCoordinator(client: client))

        let consumed = await session.send(
            "Как прошла моя неделя?",
            store: store,
            apiKey: "test-key",
            isAIEnabled: true,
            consentedCategories: []
        )

        XCTAssertFalse(consumed)
        XCTAssertEqual(session.availability, .consentRequired)
        XCTAssertTrue(session.messages.isEmpty)
        XCTAssertNotNil(session.activeScope)
        let counts = await client.counts()
        XCTAssertEqual(counts.requests, 0)

        session.cancelAndClear()
        XCTAssertNil(session.activeScope)
        XCTAssertTrue(session.messages.isEmpty)
    }

    func testExerciseChatSendsOnlySelectedCategoryContext() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = Store(fileURL: fileURL)
        store.records = [record(date: Date(), weight: "25"), record(date: Date(), exerciseID: "hammer", weight: "95")]
        store.measures = [Measure(kind: "weight", value: 62)]
        let client = RequestCoordinatorStub()
        let session = AICoachSession(requestCoordinator: AIRequestCoordinator(client: client))

        let consumed = await session.send(
            "Как менялась бабочка за неделю?",
            store: store,
            apiKey: "test-key",
            isAIEnabled: true,
            consentedCategories: [.chatMessages, .exerciseHistory]
        )

        XCTAssertTrue(consumed)
        XCTAssertEqual(session.messages.last?.text, "Держи спокойный темп и ориентируйся на комфорт.")
        let captured = await client.capturedRequest()
        let request = try XCTUnwrap(captured)
        let payload = request.contents.flatMap(\.parts).map(\.text).joined(separator: "\n")
        XCTAssertTrue(payload.contains("Бабочка"))
        XCTAssertFalse(payload.contains("95"))
        XCTAssertFalse(payload.contains("62"))
        XCTAssertFalse(payload.contains(store.records[0].id.uuidString))

        session.cancelAndClear()
        XCTAssertTrue(session.messages.isEmpty)
    }

    func testChatRequiresConsentForEveryCategoryBeforeSending() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = Store(fileURL: fileURL)
        store.records = [record(date: Date())]
        let client = RequestCoordinatorStub()
        let session = AICoachSession(requestCoordinator: AIRequestCoordinator(client: client))

        let consumed = await session.send(
            "Как менялась бабочка за неделю?",
            store: store,
            apiKey: "test-key",
            isAIEnabled: true,
            consentedCategories: [.chatMessages]
        )

        XCTAssertFalse(consumed)
        XCTAssertEqual(session.availability, .consentRequired)
        XCTAssertTrue(session.pendingConsentCategories.contains(.exerciseHistory))
        let counts = await client.counts()
        XCTAssertEqual(counts.requests, 0)
    }

    func testChatRequiresConsentForCategoriesAlreadyInSessionHistory() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = Store(fileURL: fileURL)
        store.records = [record(date: Date())]
        let client = RequestCoordinatorStub()
        let session = AICoachSession(requestCoordinator: AIRequestCoordinator(client: client))

        let firstConsumed = await session.send(
            "Как менялась бабочка за неделю?",
            store: store,
            apiKey: "test-key",
            isAIEnabled: true,
            consentedCategories: [.chatMessages, .exerciseHistory]
        )
        XCTAssertTrue(firstConsumed)

        let secondConsumed = await session.send(
            "Сколько воды я пил за неделю?",
            store: store,
            apiKey: "test-key",
            isAIEnabled: true,
            consentedCategories: [.chatMessages, .waterIntake]
        )

        XCTAssertFalse(secondConsumed)
        XCTAssertTrue(session.pendingConsentCategories.contains(.exerciseHistory))
        let counts = await client.counts()
        XCTAssertEqual(counts.requests, 1)
    }

    func testFailedChatCanBeRetriedWithoutDuplicatingTheUserMessage() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = Store(fileURL: fileURL)
        store.records = [record(date: Date())]
        let client = RequestCoordinatorStub()
        await client.failNextRequest()
        let session = AICoachSession(requestCoordinator: AIRequestCoordinator(client: client))
        let question = "Как менялась бабочка за неделю?"

        _ = await session.send(question, store: store, apiKey: "test-key", isAIEnabled: true, consentedCategories: [.chatMessages, .exerciseHistory])
        XCTAssertTrue(session.canRetry)
        XCTAssertEqual(session.messages.filter { $0.role == .user }.count, 1)

        _ = await session.retryLast(store: store, apiKey: "test-key", isAIEnabled: true, consentedCategories: [.chatMessages, .exerciseHistory])

        XCTAssertFalse(session.canRetry)
        XCTAssertEqual(session.messages.filter { $0.role == .user }.count, 1)
        XCTAssertEqual(session.messages.last?.role, .assistant)
        let counts = await client.counts()
        XCTAssertEqual(counts.requests, 2)
    }

    private func request(_ text: String) -> GeminiGenerateContentRequest {
        GeminiGenerateContentRequest(contents: [GeminiContent(role: "user", text: text)])
    }

    private func record(date: Date, exerciseID: String = "butterfly", weight: String = "25") -> Record {
        var exercise = ExerciseLog(slotID: "slot-\(exerciseID)", exerciseID: exerciseID, actualID: exerciseID, status: "completed")
        exercise.sets = [SetLog(weight: weight, reps: "8", skipped: false)]
        return Record(workoutID: Catalog.workouts[0].id, name: "Тренировка", date: date, exercises: [exercise])
    }
}
