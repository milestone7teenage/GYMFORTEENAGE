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
        let exercise = Catalog.e(exerciseID)
        var log = ExerciseLog(slotID: "slot", exerciseID: exerciseID, actualID: exerciseID, status: "completed")
        log.sets = [SetLog(weight: weight, reps: "8", skipped: false)]
        return Record(workoutID: Catalog.workouts[0].id, name: "Тренировка", date: date, exercises: [log])
    }
}
