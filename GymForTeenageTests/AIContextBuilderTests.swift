import Foundation
import XCTest
@testable import GymForTeenage

@MainActor
final class AIContextBuilderTests: XCTestCase {
    private func makeStore() -> (Store, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        return (Store(fileURL: url), url)
    }

    func testGeneralQuestionDoesNotIncludePersonalData() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        store.records = [record(date: Date(), exerciseID: "butterfly")]
        store.measures = [Measure(kind: "weight", value: 60)]

        let selection = AIContextBuilder().build(for: "Как правильно разминаться?", store: store)

        XCTAssertFalse(selection.isPersonal)
        XCTAssertNil(selection.payloadJSON)
        XCTAssertNil(selection.clarification)
    }

    func testExerciseContextIncludesOnlyMatchingExerciseAndNoIdentifiers() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        store.records = [
            record(date: Date(), exerciseID: "butterfly", weight: "25"),
            record(date: Date(), exerciseID: "hammer", weight: "90")
        ]

        let selection = AIContextBuilder().build(for: "Как менялась бабочка за неделю?", store: store)
        let payload = try XCTUnwrap(selection.payloadJSON)

        XCTAssertEqual(selection.categories, [.exerciseHistory])
        XCTAssertTrue(payload.contains("Бабочка"))
        XCTAssertTrue(payload.contains("25"))
        XCTAssertFalse(payload.contains("90"))
        XCTAssertFalse(payload.contains(store.records[0].id.uuidString))
    }

    func testExerciseMatchingCaseInsensitiveExact() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        store.records = [record(date: Date(), exerciseID: "butterfly", weight: "25")]

        let selection = AIContextBuilder().build(for: "БАБОЧКА", store: store)
        let payload = try XCTUnwrap(selection.payloadJSON)

        XCTAssertTrue(payload.contains("Бабочка"))
    }

    func testExerciseMatchingLocalizedContains() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        store.records = [record(date: Date(), exerciseID: "hammerpress", weight: "40")]

        let selection = AIContextBuilder().build(for: "жас родился", store: store)
        let payload = try XCTUnwrap(selection.payloadJSON)

        XCTAssertTrue(payload.contains("Жим груди в Хаммере"))
    }

    func testExerciseMatchingNormalizedStemMin4Chars() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        store.records = [record(date: Date(), exerciseID: "tbar", weight: "60")]

        let selection = AIContextBuilder().build(for: "тяга", store: store)
        let payload = try XCTUnwrap(selection.payloadJSON)

        XCTAssertTrue(payload.contains("Тяга Т-грифа"))
    }

    func testDifferentExercisesNotMixed() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        store.records = [
            record(date: Date(), exerciseID: "butterfly", weight: "25"),
            record(date: Date(), exerciseID: "hammer", weight: "90"),
            record(date: Date(), exerciseID: "tbar", weight: "60")
        ]

        let selection = AIContextBuilder().build(for: "бабочка", store: store)
        let payload = try XCTUnwrap(selection.payloadJSON)

        XCTAssertTrue(payload.contains("25"))
        XCTAssertFalse(payload.contains("90"))
        XCTAssertFalse(payload.contains("60"))
    }

    func testHistoryIncludesMultipleRecordsAndSets() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let date1 = Date().addingTimeInterval(-86400)
        let date2 = Date()
        var log1 = ExerciseLog(slotID: "slot1", exerciseID: "butterfly", actualID: "butterfly", status: "completed")
        log1.sets = [SetLog(weight: "20", reps: "10", skipped: false), SetLog(weight: "22", reps: "8", skipped: false)]
        var log2 = ExerciseLog(slotID: "slot2", exerciseID: "butterfly", actualID: "butterfly", status: "completed")
        log2.sets = [SetLog(weight: "25", reps: "8", skipped: false)]
        store.records = [
            Record(workoutID: Catalog.workouts[0].id, name: "Тренировка 1", date: date1, exercises: [log1]),
            Record(workoutID: Catalog.workouts[0].id, name: "Тренировка 2", date: date2, exercises: [log2])
        ]

        let selection = AIContextBuilder().build(for: "бабочка", store: store)
        let payload = try XCTUnwrap(selection.payloadJSON)

        XCTAssertTrue(payload.contains("20"))
        XCTAssertTrue(payload.contains("22"))
        XCTAssertTrue(payload.contains("25"))
    }

    func testActiveWorkoutIncludedInExerciseHistory() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        store.records = [record(date: Date().addingTimeInterval(-86400), exerciseID: "butterfly", weight: "20")]

        let workout = Catalog.workouts[0]
        _ = store.current(workout)
        store.mutate { session in
            session.exercises[0].sets = [SetLog(weight: "30", reps: "8", skipped: false), SetLog(weight: "30", reps: "6", skipped: false)]
            session.exercises[0].status = "inProgress"
        }

        let selection = AIContextBuilder().build(for: "бабочка", store: store)
        let payload = try XCTUnwrap(selection.payloadJSON)

        XCTAssertTrue(payload.contains("30"))
    }

    func testGeneralWorkoutQuestionReturnsLimitedContext() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        store.records = [
            record(date: Date(), exerciseID: "butterfly", weight: "25"),
            record(date: Date().addingTimeInterval(-86400), exerciseID: "hammer", weight: "90")
        ]

        let selection = AIContextBuilder().build(for: "какой рабочий вес на тренировке?", store: store)
        let payload = try XCTUnwrap(selection.payloadJSON)

        XCTAssertEqual(selection.categories, [.exerciseHistory])
        XCTAssertTrue(payload.contains("Бабочка") || payload.contains("Молотки"))
        XCTAssertTrue(payload.contains("25") || payload.contains("90"))
    }

    func testWaterAndMeasurementQuestionsSelectOnlyRequestedCategory() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        store.water = [WaterDay(day: Store.dayKey(Date()), ml: 800)]
        store.measures = [Measure(kind: "weight", value: 61), Measure(kind: "height", value: 170)]

        let water = AIContextBuilder().build(for: "Сколько воды я пил сегодня?", store: store)
        let weight = AIContextBuilder().build(for: "Как менялся мой вес за 30 дней?", store: store)
        let waterJSON = try XCTUnwrap(water.payloadJSON)
        let weightJSON = try XCTUnwrap(weight.payloadJSON)

        XCTAssertEqual(water.categories, [.waterIntake])
        XCTAssertTrue(waterJSON.contains("800"))
        XCTAssertFalse(waterJSON.contains("61"))
        XCTAssertEqual(weight.categories, [.bodyMeasurements])
        XCTAssertTrue(weightJSON.contains("61"))
        XCTAssertFalse(weightJSON.contains("170"))
    }

    func testAmbiguousExerciseQuestionAsksForClarificationWithoutPayload() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let selection = AIContextBuilder().build(for: "жим", store: store)

        XCTAssertFalse(selection.isPersonal)
        XCTAssertNil(selection.payloadJSON)
        XCTAssertNotNil(selection.clarification)
    }

    func testFollowUpUsesActiveWaterScope() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        store.water = [WaterDay(day: Store.dayKey(Date()), ml: 1200)]
        let scope = AIContextScope(category: .waterIntake, exerciseID: nil, measurementKind: nil, startDate: .distantPast, endDate: .distantFuture)

        let selection = AIContextBuilder().build(for: "А почему?", store: store, activeScope: scope)

        XCTAssertEqual(selection.categories, [.waterIntake])
        XCTAssertTrue(try XCTUnwrap(selection.payloadJSON).contains("1200"))
    }

    private func record(date: Date, exerciseID: String, weight: String = "25") -> Record {
        var log = ExerciseLog(slotID: "slot", exerciseID: exerciseID, actualID: exerciseID, status: "completed")
        log.sets = [SetLog(weight: weight, reps: "8", skipped: false)]
        return Record(workoutID: Catalog.workouts[0].id, name: "Тренировка", date: date, exercises: [log])
    }
}
