import Foundation
import XCTest
@testable import GymForTeenage

private actor InsightsGeminiStub: GeminiGenerating {
    private(set) var requestCount = 0
    var response: String
    var shouldFail = false

    init(response: String) { self.response = response }

    func generateContent(_ request: GeminiGenerateContentRequest, apiKey: String) async throws -> String {
        requestCount += 1
        if shouldFail { throw GeminiClientError.transport }
        return response
    }

    func count() -> Int { requestCount }
    func setFailure(_ value: Bool) { shouldFail = value }
    func setResponse(_ value: String) { response = value }
}

@MainActor
final class AIInsightsCoordinatorTests: XCTestCase {
    private func fixture() -> (Store, URL, URL) {
        let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        return (Store(fileURL: storeURL), storeURL, cacheURL)
    }

    func testLocalMetricsAreCalculatedFromWeeklyRecords() {
        let (store, storeURL, cacheURL) = fixture()
        defer { try? FileManager.default.removeItem(at: storeURL); try? FileManager.default.removeItem(at: cacheURL) }
        let now = Date()
        store.records = [record(date: now, weight: "20", reps: "10"), record(date: now.addingTimeInterval(-3600), weight: "30", reps: "5")]

        let analysis = AIInsightsEngine().build(from: store, now: now)

        XCTAssertEqual(analysis.weeklyWorkoutCount, 2)
        XCTAssertEqual(analysis.computedMetrics.first(where: { $0.key == "completed_sets_7d" })?.value, 2)
        XCTAssertEqual(analysis.computedMetrics.first(where: { $0.key == "tonnage_7d" })?.value, 350)
    }

    func testFingerprintChangesWhenParticipatingOldWorkoutChangesOrIsDeleted() {
        let (store, storeURL, cacheURL) = fixture()
        defer { try? FileManager.default.removeItem(at: storeURL); try? FileManager.default.removeItem(at: cacheURL) }
        let now = Date()
        store.records = [record(date: now.addingTimeInterval(-10 * 86_400), weight: "20", reps: "10")]
        let engine = AIInsightsEngine()
        let initial = engine.build(from: store, now: now).fingerprint
        store.records[0].exercises[0].sets[0].weight = "21"
        let changed = engine.build(from: store, now: now).fingerprint
        store.records.removeAll()
        let removed = engine.build(from: store, now: now).fingerprint

        XCTAssertNotEqual(initial, changed)
        XCTAssertNotEqual(changed, removed)
    }

    func testFingerprintIncludesLocalDateAndTimeZone() {
        let (store, storeURL, cacheURL) = fixture()
        defer { try? FileManager.default.removeItem(at: storeURL); try? FileManager.default.removeItem(at: cacheURL) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let utc = TimeZone(secondsFromGMT: 0)!
        let honolulu = TimeZone(identifier: "Pacific/Honolulu")!
        let utcEngine = AIInsightsEngine(calendar: Calendar(identifier: .gregorian), timeZone: utc)
        let honoluluEngine = AIInsightsEngine(calendar: Calendar(identifier: .gregorian), timeZone: honolulu)

        XCTAssertNotEqual(utcEngine.build(from: store, now: now).fingerprint, honoluluEngine.build(from: store, now: now).fingerprint)
    }

    func testDisabledAIAndMissingConsentDoNotCallGemini() async {
        let (store, storeURL, cacheURL) = fixture()
        defer { try? FileManager.default.removeItem(at: storeURL); try? FileManager.default.removeItem(at: cacheURL) }
        store.records = [record(date: Date())]
        let client = InsightsGeminiStub(response: Self.validResponse)
        let coordinator = AIInsightsCoordinator(cache: AIInsightsCache(fileURL: cacheURL), client: client)

        await coordinator.refresh(store: store, isAIEnabled: false, apiKey: "test-key", allowsPersonalData: true)
        XCTAssertEqual(coordinator.state.availability, .disabled)
        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: "test-key", allowsPersonalData: true, allowGeneration: false)
        XCTAssertEqual(coordinator.state.availability, .consentRequired)
        let disabledRequestCount = await client.count()
        XCTAssertEqual(disabledRequestCount, 0)
    }

    func testSecondRefreshUsesCurrentCacheWithoutAnotherRequest() async {
        let (store, storeURL, cacheURL) = fixture()
        defer { try? FileManager.default.removeItem(at: storeURL); try? FileManager.default.removeItem(at: cacheURL) }
        store.records = [record(date: Date())]
        let client = InsightsGeminiStub(response: Self.validResponse)
        let coordinator = AIInsightsCoordinator(cache: AIInsightsCache(fileURL: cacheURL), client: client)

        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: "test-key", allowsPersonalData: true)
        XCTAssertEqual(coordinator.state.availability, .ready)
        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: "test-key", allowsPersonalData: true)

        let cachedRequestCount = await client.count()
        XCTAssertEqual(cachedRequestCount, 1)
    }

    func testRepeatedOpenAfterFailureDoesNotRetryUntilExplicitRefresh() async {
        let (store, storeURL, cacheURL) = fixture()
        defer { try? FileManager.default.removeItem(at: storeURL); try? FileManager.default.removeItem(at: cacheURL) }
        store.records = [record(date: Date())]
        let client = InsightsGeminiStub(response: Self.validResponse)
        await client.setFailure(true)
        let coordinator = AIInsightsCoordinator(cache: AIInsightsCache(fileURL: cacheURL), client: client)

        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: "test-key", allowsPersonalData: true)
        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: "test-key", allowsPersonalData: true)
        let cachedRequestCount = await client.count()
        XCTAssertEqual(cachedRequestCount, 1)
        await client.setFailure(false)
        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: "test-key", allowsPersonalData: true, forceRefresh: true)

        let retriedRequestCount = await client.count()
        XCTAssertEqual(retriedRequestCount, 2)
        XCTAssertEqual(coordinator.state.availability, .ready)
    }

    func testNumericNarrativeIsRejected() throws {
        let narrative = AIInsightsNarrative(schemaVersion: 1, summary: "Выполнено 4 тренировки", observations: [], limitations: [])
        XCTAssertThrowsError(try AIInsightsValidator.makeInsights(
            from: narrative,
            period: AIAnalysisPeriod(start: Date(timeIntervalSince1970: 0), endExclusive: Date(timeIntervalSince1970: 1), localCalendarDate: "2026-01-01", timeZoneIdentifier: "UTC"),
            computedMetrics: [],
            localLimitations: []
        ))
    }

    private static let validResponse = #"{"schemaVersion":1,"summary":"Продолжай постепенно и сохраняй комфортный ритм","observations":[],"limitations":[]}"#

    private func record(date: Date, weight: String = "20", reps: String = "10") -> Record {
        var exercise = ExerciseLog(slotID: "slot", exerciseID: "butterfly", actualID: "butterfly", status: "completed")
        exercise.sets = [SetLog(weight: weight, reps: reps, skipped: false)]
        return Record(workoutID: Catalog.workouts[0].id, name: "Тренировка 1", date: date, exercises: [exercise])
    }
}
