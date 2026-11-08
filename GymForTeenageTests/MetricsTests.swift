import XCTest
@testable import GymForTeenage

final class MetricsTests: XCTestCase {
 func testCatalogHasThreeWorkoutsAndTwentySlots() { XCTAssertEqual(Catalog.workouts.count,3); XCTAssertEqual(Catalog.workouts.map{$0.exercises.count},[7,6,7]); XCTAssertEqual(Set(Catalog.workouts.flatMap{$0.exercises}.map{$0.id}).count,15) }
 func testTonnageAndSkippedSet() { let a=SetLog(weight:"20",reps:"10"); let b=SetLog(weight:"40",reps:"5",skipped:true); XCTAssertEqual(Metrics.tonnage([ExerciseLog(slotID:"a",exerciseID:"butterfly",actualID:"butterfly",sets:[a,b])]),200) }
 func testSkippedExerciseExcludedAndCompletedCount() { let e=ExerciseLog(slotID:"a",exerciseID:"butterfly",actualID:"butterfly",status:"skipped",sets:[SetLog(weight:"10",reps:"8")]);XCTAssertEqual(Metrics.tonnage([e]),0);XCTAssertEqual(Metrics.completedSets([e]),0) }
 func testBackupVersionAndValidation() throws { let b=Backup(records:[],measures:[],water:[WaterDay(day:"2026-11-08",ml:200)],session:nil,instructions:[:],reminders:false);try BackupValidator.validate(b);let data=try JSONEncoder.pretty.encode(b);let decoded=try JSONDecoder.iso.decode(Backup.self,from:data);XCTAssertEqual(decoded.water.first?.ml,200);var bad=decoded;bad.version=77;XCTAssertThrowsError(try BackupValidator.validate(bad)) }
}

extension MetricsTests {
 func testReminderScheduleIsEveryTwoHoursFromNineThroughTwentyThree() { XCTAssertEqual(ReminderSchedule.hours,[9,11,13,15,17,19,21,23]);XCTAssertEqual(ReminderSchedule.hours.count,8) }
}
