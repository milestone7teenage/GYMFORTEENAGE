import XCTest
@testable import GymForTeenage

@MainActor final class StoreIntegrationTests:XCTestCase {
 private func tempURL()->URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".json") }
 func testActiveWorkoutPersistsAndRestoresAllFields() throws {
  let url=tempURL();defer{try? FileManager.default.removeItem(at:url)}
  let first=Store(fileURL:url);let workout=Catalog.workouts[0];first.current(workout)
  first.mutate{$0.current=2;$0.exercises[0].sets[0].weight="42.5";$0.exercises[0].sets[0].reps="9";$0.exercises[1].status="skipped"}
  let reopened=Store(fileURL:url);XCTAssertEqual(reopened.session?.current,2);XCTAssertEqual(reopened.session?.exercises[0].sets[0].weight,"42.5");XCTAssertEqual(reopened.session?.exercises[0].sets[0].reps,"9");XCTAssertEqual(reopened.session?.exercises[1].status,"skipped")
 }
 func testMeasurementsAndWaterRoundTrip() throws {
  let url=tempURL();defer{try? FileManager.default.removeItem(at:url)};let s=Store(fileURL:url)
  s.measures=[Measure(kind:"weight",value:61),Measure(kind:"height",value:171)];s.water=[WaterDay(day:s.today,ml:800)];s.save()
  let restored=Store(fileURL:url);XCTAssertEqual(restored.measures.count,2);XCTAssertEqual(restored.water.first(where:{$0.day==restored.today})?.ml,800)
 }
 func testImportRejectsMalformedAndLeavesExistingStateUntouched() throws {
  let url=tempURL();defer{try? FileManager.default.removeItem(at:url)};let s=Store(fileURL:url);s.measures=[Measure(kind:"weight",value:70)];s.save();let before=try Data(contentsOf:url)
  XCTAssertThrowsError(try s.restore(Data("{bad".utf8)));XCTAssertEqual(s.measures.first?.value,70);XCTAssertEqual(try Data(contentsOf:url),before)
 }
 func testImportAtomicallyReplacesData() throws {
  let url=tempURL();defer{try? FileManager.default.removeItem(at:url)};let s=Store(fileURL:url);s.measures=[Measure(kind:"height",value:160)];s.save()
  let incoming=Backup(records:[],measures:[Measure(kind:"weight",value:50)],water:[],session:nil,instructions:[:],reminders:false);let data=try JSONEncoder.pretty.encode(incoming);try s.restore(data);XCTAssertEqual(s.measures.count,1);XCTAssertEqual(s.measures.first?.kind,"weight");let reopened=Store(fileURL:url);XCTAssertEqual(reopened.measures.first?.value,50)
 }
 func testWaterHistoryRetentionAndClear() {
  let url=tempURL();defer{try? FileManager.default.removeItem(at:url)};let s=Store(fileURL:url);let old=Calendar.current.date(byAdding:.day,value:-9,to:Date())!;let f=DateFormatter();f.dateFormat="yyyy-MM-dd";s.water=[WaterDay(day:f.string(from:old),ml:100),WaterDay(day:s.today,ml:400)];s.rollWater();XCTAssertNil(s.water.first(where:{$0.day==f.string(from:old)}));XCTAssertEqual(s.water.first(where:{$0.day==s.today})?.ml,400);s.clear();XCTAssertTrue(s.records.isEmpty && s.measures.isEmpty && s.session==nil)
 }

 func testCorruptLocalStoreIsNotOverwrittenOnLaunch() throws {
  let url=tempURL();defer{try? FileManager.default.removeItem(at:url)};let original=Data("not-json".utf8);try original.write(to:url)
  let opened=Store(fileURL:url);XCTAssertNotNil(opened.error);XCTAssertEqual(try Data(contentsOf:url),original)
 }
 func testExportProducesVersionedJSONAndClearPersists() throws {
  let url=tempURL();defer{try? FileManager.default.removeItem(at:url)};let s=Store(fileURL:url);s.measures=[Measure(kind:"weight",value:55),Measure(kind:"height",value:168)];s.save()
  let exported=try XCTUnwrap(s.export());let backup=try JSONDecoder.iso.decode(Backup.self,from:Data(contentsOf:exported));XCTAssertEqual(backup.version,1);XCTAssertEqual(backup.measures.count,2);try? FileManager.default.removeItem(at:exported)
  s.clear();let restored=Store(fileURL:url);XCTAssertTrue(restored.measures.isEmpty);XCTAssertTrue(restored.water.count<=7)
 }
func testUnsupportedVersionImportDoesNotReplaceCurrentData() throws {
   let url=tempURL();defer{try? FileManager.default.removeItem(at:url)};let s=Store(fileURL:url);s.measures=[Measure(kind:"weight",value:72)];s.save();let before=try Data(contentsOf:url)
   var b=Backup(records:[],measures:[],water:[],session:nil,instructions:[:],reminders:false);b.version=99;let data=try JSONEncoder.pretty.encode(b)
   XCTAssertThrowsError(try s.restore(data));XCTAssertEqual(s.measures.first?.value,72);XCTAssertEqual(try Data(contentsOf:url),before)
  }
  func testRecoverExerciseRestoresSkippedAndPreservesSets() throws {
   let url=tempURL();defer{try? FileManager.default.removeItem(at:url)};let s=Store(fileURL:url);let workout=Catalog.workouts[0];s.current(workout)
   s.mutate { state in state.exercises[0].status="skipped"; state.exercises[0].sets[0].weight="50"; state.exercises[0].sets[0].reps="5" }
   s.recoverExercise(at: 0)
   XCTAssertEqual(s.session?.exercises[0].status,"pending")
   XCTAssertEqual(s.session?.exercises[0].sets[0].weight,"50")
   XCTAssertEqual(s.session?.exercises[0].sets[0].reps,"5")
   XCTAssertEqual(s.session?.current,0)
  }
  func testRecoverExerciseDoesNotDuplicate() throws {
   let url=tempURL();defer{try? FileManager.default.removeItem(at:url)};let s=Store(fileURL:url);let workout=Catalog.workouts[0];s.current(workout)
   s.mutate { state in state.exercises[0].status="skipped" }
   s.recoverExercise(at: 0)
   s.recoverExercise(at: 0)
   XCTAssertEqual(s.session?.exercises.count,workout.exercises.count)
   XCTAssertEqual(s.session?.exercises[0].status,"pending")
  }
  func testCreatineTogglePersistsAndResetsOnNewDay() throws {
   let url=tempURL();defer{try? FileManager.default.removeItem(at:url)};let s=Store(fileURL:url)
   s.creatineToggle()
   XCTAssertTrue(s.todayCreatine)
   let reopened=Store(fileURL:url)
   XCTAssertTrue(reopened.todayCreatine)
   let yesterday=Calendar.current.date(byAdding:.day,value:-1,to:Date())!
   let yesterdayKey=Store.dayKey(yesterday)
   reopened.creatineLog[yesterdayKey]=false
   reopened.creatineLog[reopened.today]=true
   reopened.save()
   let next=Store(fileURL:url)
   XCTAssertEqual(next.todayCreatine,true)
   XCTAssertEqual(next.creatineLog[yesterdayKey],false)
  }
  func testCreatineHistorySurvivesRestart() throws {
   let url=tempURL();defer{try? FileManager.default.removeItem(at:url)};let s=Store(fileURL:url)
   let yesterday=Calendar.current.date(byAdding:.day,value:-1,to:Date())!
   let yk=Store.dayKey(yesterday)
   s.creatineLog[yk]=true
   s.creatineLog[s.today]=false
   s.save()
   let reopened=Store(fileURL:url)
   XCTAssertEqual(reopened.creatineLog[yk],true)
   XCTAssertEqual(reopened.creatineLog[s.today],false)
  }
  func testSkippedExerciseStatusPersists() throws {
   let url=tempURL();defer{try? FileManager.default.removeItem(at:url)};let s=Store(fileURL:url);let workout=Catalog.workouts[0];s.current(workout)
   s.mutate { state in state.exercises[0].status="skipped"; state.exercises[0].sets[0].weight="30" }
   let reopened=Store(fileURL:url)
   XCTAssertEqual(reopened.session?.exercises[0].status,"skipped")
   XCTAssertEqual(reopened.session?.exercises[0].sets[0].weight,"30")
  }
}



