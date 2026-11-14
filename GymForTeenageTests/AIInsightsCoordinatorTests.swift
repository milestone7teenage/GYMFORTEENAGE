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
        XCTAssertNil(analysis.computedMetrics.first(where: { $0.key == "active_sets" }))
        XCTAssertNil(analysis.computedMetrics.first(where: { $0.key == "active_tonnage" }))
    }

    func testActiveWorkoutMetricsAreAddedSeparately() {
        let (store, storeURL, cacheURL) = fixture()
        defer { try? FileManager.default.removeItem(at: storeURL); try? FileManager.default.removeItem(at: cacheURL) }
        let now = Date()
        store.records = [record(date: now.addingTimeInterval(-86400), weight: "20", reps: "10")]

        let workout = Catalog.workouts[0]
        let session = store.current(workout)
        session.exercises[0].sets = [SetLog(weight: "30", reps: "8", skipped: false), SetLog(weight: "30", reps: "6", skipped: false)]
        session.exercises[0].status = "inProgress"

        let analysis = AIInsightsEngine().build(from: store, now: now)

        XCTAssertEqual(analysis.weeklyWorkoutCount, 1)
        XCTAssertEqual(analysis.computedMetrics.first(where: { $0.key == "completed_sets_7d" })?.value, 1)
        XCTAssertEqual(analysis.computedMetrics.first(where: { $0.key == "tonnage_7d" })?.value, 200)
        XCTAssertEqual(analysis.computedMetrics.first(where: { $0.key == "active_sets" })?.value, 2)
        XCTAssertEqual(analysis.computedMetrics.first(where: { $0.key == "active_tonnage" })?.value, 420)
    }

    func testActiveWorkoutNotDoubleCountedInWeekly() {
        let (store, storeURL, cacheURL) = fixture()
        defer { try? FileManager.default.removeItem(at: storeURL); try? FileManager.default.removeItem(at: cacheURL) }
        let now = Date()
        store.records = [record(date: now, weight: "20", reps: "10")]

        let workout = Catalog.workouts[0]
        let session = store.current(workout)
        session.exercises[0].sets = [SetLog(weight: "30", reps: "8", skipped: false)]

        let analysis = AIInsightsEngine().build(from: store, now: now)

        XCTAssertEqual(analysis.weeklyWorkoutCount, 1)
        XCTAssertEqual(analysis.computedMetrics.first(where: { $0.key == "completed_sets_7d" })?.value, 1)
        XCTAssertEqual(analysis.computedMetrics.first(where: { $0.key == "tonnage_7d" })?.value, 200)
        XCTAssertEqual(analysis.computedMetrics.first(where: { $0.key == "active_sets" })?.value, 1)
        XCTAssertEqual(analysis.computedMetrics.first(where: { $0.key == "active_tonnage" })?.value, 240)
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

        await coordinator.refresh(store: store, isAIEnabled: false, apiKey: "test-key", consentedCategories: [.weeklyInsights])
        XCTAssertEqual(coordinator.state.availability, .disabled)
        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: "test-key", consentedCategories: [], allowGeneration: false)
        XCTAssertEqual(coordinator.state.availability, .consentRequired)
        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: "test-key", consentedCategories: [])
        XCTAssertEqual(coordinator.state.availability, .consentRequired)
        let disabledRequestCount = await client.count()
        XCTAssertEqual(disabledRequestCount, 0)
    }

    func testFirstInsightsConsentBlocksUntilGrantedAndDeclineKeepsConsentRequired() async {
        let (store, storeURL, cacheURL) = fixture()
        defer { try? FileManager.default.removeItem(at: storeURL); try? FileManager.default.removeItem(at: cacheURL) }
        store.records = [record(date: Date())]
        store.measures = [Measure(kind: "weight", value: 62, date: Date())]
        let client = InsightsGeminiStub(response: Self.validResponse)
        let coordinator = AIInsightsCoordinator(cache: AIInsightsCache(fileURL: cacheURL), client: client)

        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: "test-key", consentedCategories: [])
        XCTAssertEqual(coordinator.state.availability, .consentRequired)
        XCTAssertEqual(coordinator.requiredConsentCategories, [.weeklyInsights, .bodyMeasurements])
        let declinedRequestCount = await client.count()
        XCTAssertEqual(declinedRequestCount, 0)

        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: "test-key", consentedCategories: [.weeklyInsights])
        XCTAssertEqual(coordinator.state.availability, .consentRequired)
        let partialRequestCount = await client.count()
        XCTAssertEqual(partialRequestCount, 0)

        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: "test-key", consentedCategories: [.weeklyInsights, .bodyMeasurements])
        XCTAssertEqual(coordinator.state.availability, .ready)
        let grantedRequestCount = await client.count()
        XCTAssertEqual(grantedRequestCount, 1)
    }

    func testRevokingConsentPhysicallyDeletesInsightsCache() async throws {
        let (store, storeURL, cacheURL) = fixture()
        defer { try? FileManager.default.removeItem(at: storeURL); try? FileManager.default.removeItem(at: cacheURL) }
        store.records = [record(date: Date())]
        let suiteName = "AIInsightsRevokeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let consent = AIConsentStore(defaults: defaults)
        consent.grant([.weeklyInsights])
        let coordinator = AIInsightsCoordinator(cache: AIInsightsCache(fileURL: cacheURL), client: InsightsGeminiStub(response: Self.validResponse))
        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: "test-key", consentedCategories: consent.consentedCategories)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))

        coordinator.revokeConsent(using: consent)

        XCTAssertFalse(consent.hasConsent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
        XCTAssertNil(AIInsightsCache(fileURL: cacheURL).load())
    }

    func testRemovingInsightsConsentPhysicallyDeletesInsightsCache() async throws {
        let (store, storeURL, cacheURL) = fixture()
        defer { try? FileManager.default.removeItem(at: storeURL); try? FileManager.default.removeItem(at: cacheURL) }
        store.records = [record(date: Date())]
        let client = InsightsGeminiStub(response: Self.validResponse)
        let coordinator = AIInsightsCoordinator(cache: AIInsightsCache(fileURL: cacheURL), client: client)
        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: "test-key", consentedCategories: [.weeklyInsights])
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))

        coordinator.consentCategoriesChanged(from: [.weeklyInsights], to: [])

        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
        XCTAssertNil(AIInsightsCache(fileURL: cacheURL).load())
    }

    func testRestoreAndRealStoreMutationsInvalidateInsightsAndStoreClearPreservesKey() async throws {
        let (store, storeURL, cacheURL) = fixture()
        defer { try? FileManager.default.removeItem(at: storeURL); try? FileManager.default.removeItem(at: cacheURL) }
        let now = Date()
        store.records = [record(date: now)]
        store.measures = [Measure(kind: "weight", value: 62, date: now)]
        let client = InsightsGeminiStub(response: Self.validResponse)
        let coordinator = AIInsightsCoordinator(cache: AIInsightsCache(fileURL: cacheURL), client: client)
        let consent: Set<AIDataCategory> = [.weeklyInsights, .bodyMeasurements]
        let keyStore = AIKeychainStore(service: "com.gymforteenage.tests.clear.\(UUID().uuidString)")
        let testKey = "isolated-clear-test-key-\(UUID().uuidString)"
        try keyStore.save(key: testKey)
        defer {
            do { try keyStore.deleteKey() }
            catch { XCTFail("Failed to delete isolated test Keychain item: \(error)") }
        }

        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: testKey, consentedCategories: consent, now: now)
        var requestCount = await client.count()
        XCTAssertEqual(requestCount, 1)

        store.records[0].exercises[0].sets[0].weight = "21"
        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: testKey, consentedCategories: consent, now: now)
        requestCount = await client.count()
        XCTAssertEqual(requestCount, 2)

        store.records.removeAll()
        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: testKey, consentedCategories: consent, now: now)
        requestCount = await client.count()
        XCTAssertEqual(requestCount, 3)

        let restoredRecord = record(date: now, weight: "24")
        let restoredMeasure = Measure(kind: "weight", value: 63, date: now)
        let backup = Backup(records: [restoredRecord], measures: [restoredMeasure], water: [], session: nil, instructions: [:], reminders: false)
        try store.restore(JSONEncoder.pretty.encode(backup))
        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: testKey, consentedCategories: consent, now: now)
        requestCount = await client.count()
        XCTAssertEqual(requestCount, 4)

        store.measures[0].value = 64
        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: testKey, consentedCategories: consent, now: now)
        requestCount = await client.count()
        XCTAssertEqual(requestCount, 5)

        store.measures.removeAll()
        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: testKey, consentedCategories: consent, now: now)
        requestCount = await client.count()
        XCTAssertEqual(requestCount, 6)

        store.clear()
        await coordinator.refresh(store: store, isAIEnabled: false, apiKey: testKey, consentedCategories: consent, now: now)
        XCTAssertEqual(coordinator.state.availability, .disabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
        XCTAssertEqual(try keyStore.retrieveKey(), testKey)
    }

    func testCoordinatorInvalidatesCacheOnCalendarDateAndTimeZoneChanges() async {
        let (store, storeURL, cacheURL) = fixture()
        defer { try? FileManager.default.removeItem(at: storeURL); try? FileManager.default.removeItem(at: cacheURL) }
        let utc = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        store.records = [record(date: now)]
        let client = InsightsGeminiStub(response: Self.validResponse)
        let coordinator = AIInsightsCoordinator(
            engine: AIInsightsEngine(calendar: calendar, timeZone: utc),
            cache: AIInsightsCache(fileURL: cacheURL),
            client: client
        )
        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: "test-key", consentedCategories: [.weeklyInsights], now: now)
        let firstCount = await client.count()
        XCTAssertEqual(firstCount, 1)

        let nextDay = now.addingTimeInterval(86_400)
        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: "test-key", consentedCategories: [.weeklyInsights], now: nextDay)
        let nextDayCount = await client.count()
        XCTAssertEqual(nextDayCount, 2)

        let honolulu = TimeZone(identifier: "Pacific/Honolulu")!
        var honoluluCalendar = Calendar(identifier: .gregorian)
        honoluluCalendar.timeZone = honolulu
        coordinator.updateCalendarContext(calendar: honoluluCalendar, timeZone: honolulu)
        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: "test-key", consentedCategories: [.weeklyInsights], now: nextDay)
        let timezoneCount = await client.count()
        XCTAssertEqual(timezoneCount, 3)
    }

    func testSecondRefreshUsesCurrentCacheWithoutAnotherRequest() async {
        let (store, storeURL, cacheURL) = fixture()
        defer { try? FileManager.default.removeItem(at: storeURL); try? FileManager.default.removeItem(at: cacheURL) }
        store.records = [record(date: Date())]
        let client = InsightsGeminiStub(response: Self.validResponse)
        let coordinator = AIInsightsCoordinator(cache: AIInsightsCache(fileURL: cacheURL), client: client)

        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: "test-key", consentedCategories: [.weeklyInsights])
        XCTAssertEqual(coordinator.state.availability, .ready)
        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: "test-key", consentedCategories: [.weeklyInsights])

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

        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: "test-key", consentedCategories: [.weeklyInsights])
        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: "test-key", consentedCategories: [.weeklyInsights])
        let cachedRequestCount = await client.count()
        XCTAssertEqual(cachedRequestCount, 1)
        await client.setFailure(false)
        await coordinator.refresh(store: store, isAIEnabled: true, apiKey: "test-key", consentedCategories: [.weeklyInsights], forceRefresh: true)

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
