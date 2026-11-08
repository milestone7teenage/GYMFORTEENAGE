import SwiftUI
import Charts
import UserNotifications
import UniformTypeIdentifiers
import UIKit
import Observation

struct SetLog: Codable, Identifiable { var id = UUID(); var weight = ""; var reps = ""; var skipped = false }
struct ExerciseLog: Codable, Identifiable { var id = UUID(); var slotID: String; var exerciseID: String; var actualID: String; var status = "pending"; var sets = [SetLog(), SetLog()] }
struct Session: Codable, Identifiable { var id = UUID(); var workoutID: String; var started = Date(); var current = 0; var exercises: [ExerciseLog] }
struct Record: Codable, Identifiable { var id = UUID(); var workoutID: String; var name: String; var date: Date; var exercises: [ExerciseLog] }
struct Measure: Codable, Identifiable { var id = UUID(); var kind: String; var value: Double; var date = Date() }
struct WaterDay: Codable, Identifiable { var id: String { day }; var day: String; var ml: Int }
struct Backup: Codable { var formatIdentifier: String? = "gymforteenage-backup"; var version = 1; var records: [Record]; var measures: [Measure]; var water: [WaterDay]; var session: Session?; var instructions: [String:String]; var reminders: Bool }

struct Exercise: Identifiable { let id: String; let title: String; let image: String }
struct Training: Identifiable { let id: String; let title: String; let exercises: [Exercise] }
enum Catalog {
 static let all: [Exercise] = [
 .init(id:"butterfly",title:"Бабочка",image:"Бабочка"), .init(id:"tbar",title:"Тяга Т-грифа",image:"Тяга Т-Грифа"), .init(id:"shoulder",title:"Жим плеч",image:"Жим плеч"), .init(id:"curlleg",title:"Сгибание ног",image:"Сгибание ног"), .init(id:"extendleg",title:"Разгибание ног",image:"Разгибание ног"), .init(id:"hammer",title:"Молотки",image:"Молотки"), .init(id:"triceps",title:"Трицепс в блоке",image:"Трицепс в блоке"), .init(id:"hammerpress",title:"Жим груди в Хаммере",image:"Жим груди в Хаммере"), .init(id:"pullup",title:"Подтягивания",image:"Подтягивания"), .init(id:"raises",title:"Махи плечами",image:"Махи плечами"), .init(id:"hack",title:"Жим в гакке",image:"Жим в гакке"), .init(id:"cablebiceps",title:"Бицепс в блоке",image:"Бицепс в блоке"), .init(id:"incline",title:"Жим под наклоном",image:"Жим под наклоном"), .init(id:"pulldown",title:"Тяга вертикального блока",image:"Тяга вертикального блока"), .init(id:"seatedbiceps",title:"Бицепс сидя",image:"Бицепс сидя")]
 static func e(_ id:String)->Exercise { all.first{$0.id == id}! }
 static let workouts: [Training] = [
 .init(id:"w1",title:"Тренировка 1",exercises:["butterfly","tbar","shoulder","curlleg","extendleg","hammer","triceps"].map(e)),
 .init(id:"w2",title:"Тренировка 2",exercises:["hammerpress","pullup","raises","hack","cablebiceps","triceps"].map(e)),
 .init(id:"w3",title:"Тренировка 3",exercises:["incline","pulldown","shoulder","curlleg","extendleg","seatedbiceps","triceps"].map(e))]
}

@MainActor @Observable final class Store {
 var records:[Record]=[]; var measures:[Measure]=[]; var water:[WaterDay]=[]; var session:Session?; var instructions:[String:String]=[:]; var reminders=false; var error:String?
 private let url:URL; private var persistenceAvailable=true
 init(fileURL:URL? = nil){ let base=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]; try? FileManager.default.createDirectory(at:base,withIntermediateDirectories:true); url=fileURL ?? base.appendingPathComponent("gym-data.json"); load(); if error == nil { rollWater() } }
 var today:String { let f=DateFormatter(); f.calendar=Calendar.current; f.timeZone = .current; f.dateFormat="yyyy-MM-dd"; return f.string(from:Date()) }
 var todayML:Int { water.first{$0.day==today}?.ml ?? 0 }
 func save(){ guard persistenceAvailable else { self.error="Локальный файл повреждён; сохранение заблокировано, чтобы не затереть исходные данные"; return }; do { let b=Backup(records:records,measures:measures,water:water,session:session,instructions:instructions,reminders:reminders); let data=try JSONEncoder.pretty.encode(b); try data.write(to:url,options:.atomic) } catch { self.error="Не удалось сохранить данные: \(error.localizedDescription)" } }
 func load(){ guard let d=try? Data(contentsOf:url) else{return}; do { let b=try JSONDecoder.iso.decode(Backup.self,from:d); try BackupValidator.validate(b); records=b.records;measures=b.measures;water=b.water;session=b.session;instructions=b.instructions;reminders=b.reminders } catch { persistenceAvailable=false; self.error="Не удалось прочитать локальные данные: \(error.localizedDescription)" } }
 func rollWater(){ let cutoff=Calendar.current.date(byAdding:.day,value:-6,to:Calendar.current.startOfDay(for:Date())) ?? Date(); water=water.filter{ guard let d=Self.parseDay($0.day) else{return false}; return d>=cutoff }; if !water.contains(where:{$0.day==today}){water.append(.init(day:today,ml:0))};save() }
 nonisolated static func parseDay(_ s:String)->Date? { let f=DateFormatter();f.dateFormat="yyyy-MM-dd";f.timeZone = .current;return f.date(from:s) }
 func addWater(){ guard todayML<3000 else{return}; if let i=water.firstIndex(where:{$0.day==today}){water[i].ml=min(3000,water[i].ml+200)}; UIImpactFeedbackGenerator(style:.soft).impactOccurred();save() }
 func current(_ workout:Training)->Session { if let s=session { return s }; let s=Session(workoutID:workout.id,exercises:workout.exercises.enumerated().map{ExerciseLog(slotID:"\(workout.id)-\($0.offset)",exerciseID:$0.element.id,actualID:$0.element.id)});session=s;save();return s }
 func mutate(_ body:(inout Session)->Void){ guard var s=session else{return};body(&s);session=s;save() }
 func finish(){ guard let s=session,let w=Catalog.workouts.first(where:{$0.id==s.workoutID}) else{return};records.insert(.init(workoutID:w.id,name:w.title,date:Date(),exercises:s.exercises),at:0);session=nil;save() }
 var totalTonnage:Double { records.reduce(0){$0+Metrics.tonnage($1.exercises)} }
 var completedSets:Int { records.reduce(0){$0+Metrics.completedSets($1.exercises)} }
 func export()->URL? { let b=Backup(records:records,measures:measures,water:water,session:session,instructions:instructions,reminders:reminders);guard let d=try? JSONEncoder.pretty.encode(b) else{return nil};let u=FileManager.default.temporaryDirectory.appendingPathComponent("GymForTeenage-Backup.json");try? d.write(to:u,options:.atomic);return u }
 func restore(_ data:Data) throws { guard data.count <= 20*1024*1024 else { throw NSError(domain:"GymBackup",code:3,userInfo:[NSLocalizedDescriptionKey:"Файл резервной копии слишком большой"])}; let b=try JSONDecoder.iso.decode(Backup.self,from:data);try BackupValidator.validate(b);let encoded=try JSONEncoder.pretty.encode(b);try encoded.write(to:url,options:.atomic);persistenceAvailable=true;records=b.records;measures=b.measures;water=b.water;session=b.session;instructions=b.instructions;reminders=b.reminders }
 func clear(){records=[];measures=[];water=[];session=nil;instructions=[:];reminders=false;UNUserNotificationCenter.current().removeAllPendingNotificationRequests();save()}
 func schedule() async { if reminders { let center=UNUserNotificationCenter.current();let ok=(try? await center.requestAuthorization(options:[.alert,.sound])) ?? false;guard ok else{return};center.removePendingNotificationRequests(withIdentifiers:(0...7).map{"water-\($0)"});for (n,h) in ReminderSchedule.hours.enumerated(){var c=DateComponents();c.hour=h;let req=UNNotificationRequest(identifier:"water-\(n)",content:{let x=UNMutableNotificationContent();x.title="Время выпить воды";x.body="Небольшая пауза для воды";return x}(),trigger:UNCalendarNotificationTrigger(dateMatching:c,repeats:true));try? await center.add(req)} } else {UNUserNotificationCenter.current().removeAllPendingNotificationRequests()} }
}
enum BackupValidator {
 static func validate(_ b:Backup) throws {
  func fail(_ text:String)->NSError { NSError(domain:"GymBackup",code:1,userInfo:[NSLocalizedDescriptionKey:text]) }
  guard b.formatIdentifier == nil || b.formatIdentifier == "gymforteenage-backup" else { throw fail("Неизвестный формат резервной копии") }
  guard b.version == 1 else { throw fail("Версия резервной копии не поддерживается") }
  guard Set(b.records.map{$0.id}).count == b.records.count, Set(b.measures.map{$0.id}).count == b.measures.count, Set(b.records.flatMap{$0.exercises}.map{$0.id}).count == b.records.flatMap{$0.exercises}.count else { throw fail("Повторяющиеся идентификаторы") }
  guard Set(b.water.map{$0.day}).count == b.water.count, b.water.allSatisfy({(0...3000).contains($0.ml) && Store.parseDay($0.day) != nil}) else { throw fail("Неверные значения истории воды") }
  guard b.measures.allSatisfy({["weight","height"].contains($0.kind) && $0.value.isFinite && $0.value > 0}) else { throw fail("Неверные измерения") }
  for r in b.records { guard Catalog.workouts.contains(where:{$0.id==r.workoutID}),r.exercises.allSatisfy({["pending","inProgress","completed","skipped"].contains($0.status)}) else { throw fail("Неизвестная тренировка") }; for e in r.exercises { guard Catalog.all.contains(where:{$0.id==e.exerciseID}),Catalog.all.contains(where:{$0.id==e.actualID}),["pending","inProgress","completed","skipped"].contains(e.status),e.sets.allSatisfy({($0.weight.isEmpty || Double($0.weight.replacingOccurrences(of:",",with:".")) != nil) && ($0.reps.isEmpty || Int($0.reps) != nil)}) else { throw fail("Повреждена запись упражнения") } } }
  if let s=b.session { guard Catalog.workouts.contains(where:{$0.id==s.workoutID}),!s.exercises.isEmpty,s.current>=0,s.current<s.exercises.count,s.exercises.allSatisfy({ex in Catalog.all.contains(where:{$0.id==ex.exerciseID}) && Catalog.all.contains(where:{$0.id==ex.actualID}) && ex.sets.count>=2}) else { throw fail("Повреждена активная тренировка") } }
 }
}
enum ReminderSchedule { static let hours = [9,11,13,15,17,19,21,23] }
enum Metrics {
 static func setTonnage(_ s:SetLog)->Double { guard !s.skipped,let w=Double(s.weight.replacingOccurrences(of:",",with:".")),let r=Double(s.reps),w>=0,r>0 else{return 0};return w*r }
 static func tonnage(_ exercises:[ExerciseLog])->Double { exercises.filter{$0.status != "skipped"}.flatMap{$0.sets}.reduce(0){$0+setTonnage($1)} }
 static func completedSets(_ exercises:[ExerciseLog])->Int { exercises.filter{$0.status != "skipped"}.flatMap{$0.sets}.filter{!$0.skipped && Int($0.reps) != nil}.count }
}
extension JSONEncoder { static var pretty:JSONEncoder {let e=JSONEncoder();e.outputFormatting=[.prettyPrinted,.sortedKeys];e.dateEncodingStrategy = .iso8601;return e} }
extension JSONDecoder { static var iso:JSONDecoder {let d=JSONDecoder();d.dateDecodingStrategy = .iso8601;return d} }

@main struct GymForTeenageApp:App { @State private var store=Store(); var body:some Scene { WindowGroup { RootView().environment(store).task { while !Task.isCancelled { try? await Task.sleep(for:.seconds(60)); if !store.water.contains(where:{$0.day==store.today}) { store.rollWater() } } } } }
}
struct RootView:View { @Environment(Store.self) var store; var body:some View { TabView { HomeView().tabItem{Label("Главная",systemImage:"house.fill")}; ProgressView().tabItem{Label("Прогресс",systemImage:"chart.line.uptrend.xyaxis")}; StatsView().tabItem{Label("Статистика",systemImage:"chart.bar.xaxis")}; SettingsView().tabItem{Label("Настройки",systemImage:"gearshape")} }.tint(.indigo).alert("Сообщение",isPresented:Binding(get:{store.error != nil},set:{if !$0{store.error=nil}})){Button("OK"){store.error=nil}} message:{Text(store.error ?? "")} } }
struct Card<Content:View>:View { @ViewBuilder var content:Content; var body:some View {content.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(.background, in:RoundedRectangle(cornerRadius:22,style:.continuous)).overlay(RoundedRectangle(cornerRadius:22).stroke(.quaternary,lineWidth:1)).shadow(color:.black.opacity(0.04),radius:12,y:4)} }
struct HomeView:View { @Environment(Store.self) var store; @State private var showMeasure=false; @State private var kind="weight"; @State private var value=""; var body:some View { NavigationStack { ScrollView { VStack(spacing:14) { HStack { measureCard("Вес","kg");measureCard("Рост","см") }; section("Тренировки");ForEach(Catalog.workouts){w in NavigationLink { WorkoutView(workout:store.session.flatMap{s in Catalog.workouts.first(where:{$0.id==s.workoutID})} ?? w) } label:{Card{HStack{VStack(alignment:.leading,spacing:6){Text(w.title).font(.headline);Text("\(w.exercises.count) упражнений").font(.subheadline).foregroundStyle(.secondary)};Spacer();Image(systemName:store.session?.workoutID==w.id ? "arrow.clockwise.circle.fill":"arrow.right.circle.fill").font(.title2).foregroundStyle(.indigo)}}.contentShape(Rectangle())}.buttonStyle(.plain)};section("Вода сегодня");Card{VStack(alignment:.leading,spacing:12){HStack{Text("\(store.todayML) мл").font(.title2.bold());Spacer();Text("Осталось \(3000-store.todayML) мл").foregroundStyle(.secondary)};LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:5),spacing:12){ForEach(0..<15,id:\.self){i in Button{store.addWater()} label:{Circle().fill(i<store.todayML/200 ? .cyan : Color.secondary.opacity(0.15)).frame(width:32,height:32).overlay(Circle().stroke(.cyan.opacity(0.35),lineWidth:1))}.buttonStyle(.plain).disabled(store.todayML>=3000).accessibilityLabel("Порция \(i+1), 200 миллилитров")}};Text("Цель 3000 мл · порция 200 мл").font(.caption).foregroundStyle(.secondary)}} }.padding() }.background(Color(uiColor:.secondarySystemGroupedBackground)).navigationTitle("Gym for Teenage").toolbar{ToolbarItem(placement:.topBarTrailing){Button{kind="weight";value="";showMeasure=true} label: {Image(systemName:"plus")}}}.sheet(isPresented:$showMeasure){NavigationStack{Form{Picker("Показатель",selection:$kind){Text("Вес").tag("weight");Text("Рост").tag("height")};TextField(kind=="weight" ? "Вес, кг":"Рост, см",text:$value).keyboardType(.decimalPad)}.navigationTitle("Новое измерение").toolbar{ToolbarItem(placement:.confirmationAction){Button("Сохранить"){if let x=Double(value.replacingOccurrences(of:",",with:".")),x>0{store.measures.append(.init(kind:kind,value:x));store.save()};showMeasure=false}};ToolbarItem(placement:.cancellationAction){Button("Отмена"){showMeasure=false}}}}} } }
 @ViewBuilder func measureCard(_ title:String,_ unit:String)->some View {let k=title=="Вес" ? "weight":"height";let latest=store.measures.filter{$0.kind==k}.max{$0.date<$1.date};Card{VStack(alignment:.leading){Text(title).foregroundStyle(.secondary);Text(latest.map{"\($0.value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"} ?? "Добавить").font(.title3.bold());Button("Изменить"){kind=k;value="";showMeasure=true}.font(.caption)}} }
 func section(_ name:String)->some View{HStack{Text(name).font(.title3.bold());Spacer()}.padding(.top,6)} }
struct WorkoutView:View { @Environment(Store.self) var store; let workout:Training; @State private var resumed=false; var body:some View {let s=store.current(workout);List{ForEach(Array(s.exercises.enumerated()),id:\.element.id){i,log in NavigationLink{ExerciseView(workout:workout,index:i)} label:{HStack{Image(uiImage: exerciseUIImage(Catalog.e(log.actualID).image)).resizable().scaledToFit().frame(width:52,height:52).clipShape(RoundedRectangle(cornerRadius:10));VStack(alignment:.leading){Text(Catalog.e(log.actualID).title);Text(log.status=="skipped" ? "Пропущено":"Упражнение \(i+1)").font(.caption).foregroundStyle(.secondary)};Spacer();if log.status=="completed"{Image(systemName:"checkmark.circle.fill").foregroundStyle(.green)}}}};Button("Завершить тренировку"){store.finish()}.buttonStyle(.borderedProminent)}.navigationTitle(workout.title).navigationDestination(isPresented:$resumed){ExerciseView(workout:workout,index:min(store.session?.current ?? 0,workout.exercises.count-1))}.onAppear{if store.session?.workoutID==workout.id && !resumed {resumed=true}}.onChange(of:s.current){_,newValue in if newValue>0 && newValue<workout.exercises.count {resumed=true}}.animation(.snappy, value:s.current) } }
struct ExerciseView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let workout: Training
    let index: Int
    @State private var showReplacement = false
    @State private var showNext = false
    var body: some View {
        let session = store.current(workout)
        let entry = session.exercises[index]
        let exercise = Catalog.e(entry.actualID)
        ScrollView { VStack(spacing: 16) {
            exerciseImage(exercise)
            setsCard(entry)
            instructionCard(entry)
            historyCard(entry)
            navigationButtons(session)
        }.padding() }
        .navigationTitle(exercise.title)
        .navigationDestination(isPresented: $showNext) { ExerciseView(workout: workout,index: min(index + 1,session.exercises.count - 1)) }
        .simultaneousGesture(DragGesture(minimumDistance:55).onEnded { value in if value.translation.width < -60 { skipCurrent() } })
        .confirmationDialog("Выберите замену",isPresented:$showReplacement,titleVisibility:.visible) {
            ForEach(Catalog.all.filter { $0.id != entry.exerciseID }) { replacement in
                Button(replacement.title) { store.mutate { $0.exercises[index].actualID = replacement.id } }
            }
        }
    }
    private func exerciseImage(_ exercise:Exercise)->some View {
        Image(uiImage:exerciseUIImage(exercise.image)).resizable().scaledToFit().frame(maxHeight:240).frame(maxWidth:.infinity).background(.background,in:RoundedRectangle(cornerRadius:20))
    }
    private func setsCard(_ entry:ExerciseLog)->some View {
        Card { VStack(alignment:.leading,spacing:12) {
            Text("Подходы").font(.headline)
            ForEach(entry.sets.indices,id:\.self) { row in setRow(entry.sets[row],row:row) }
            HStack { Button("+ Подход") { store.mutate { $0.exercises[index].sets.append(SetLog()) } }; if entry.sets.count > 2 { Button("− последний") { store.mutate { $0.exercises[index].sets.removeLast() } } } }
        } }
    }
    private func setRow(_ set:SetLog,row:Int)->some View {
        HStack {
            Text("\(row+1)").frame(width:24)
            TextField("кг",text:Binding(get:{set.weight},set:{value in store.mutate { state in state.exercises[index].sets[row].weight=value; if row==0 && state.exercises[index].sets.count>1 && state.exercises[index].sets[1].weight.isEmpty { state.exercises[index].sets[1].weight=value } }})).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
            TextField("повторы",text:Binding(get:{set.reps},set:{value in store.mutate { $0.exercises[index].sets[row].reps=value }})).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
            Button { store.mutate { $0.exercises[index].sets[row].skipped.toggle() } } label: { Image(systemName:set.skipped ? "xmark.circle.fill":"checkmark.circle") }.tint(set.skipped ? .red:.green)
        }
    }
    private func instructionCard(_ entry:ExerciseLog)->some View {
        Card { VStack(alignment:.leading) { Text("Техника").font(.headline); TextEditor(text:Binding(get:{store.instructions[entry.exerciseID] ?? ""},set:{value in store.instructions[entry.exerciseID]=value;store.save()})).frame(minHeight:100) } }
    }
    private func historyCard(_ entry:ExerciseLog)->some View {
        Card { VStack(alignment:.leading) { Text("Последние выполнения").font(.headline); ForEach(Array(store.records.flatMap(\.exercises).filter{$0.exerciseID==entry.exerciseID}.prefix(3))) { record in Text("\(record.name) · \(record.date.formatted(date:.abbreviated,time:.omitted))") } } }
    }
    private func navigationButtons(_ session:Session)->some View {
        VStack(spacing:10) {
            Button("Заменить упражнение") { showReplacement=true }.buttonStyle(.bordered)
            Button(index+1<session.exercises.count ? "Далее":"К списку") { store.mutate { $0.exercises[index].status="completed";$0.current=min(index+1,$0.exercises.count-1) }; if index+1<session.exercises.count { showNext=true } else { dismiss() } }.buttonStyle(.borderedProminent)
            Button("Пропустить") { skipCurrent() }.font(.caption)
        }
    }
    private func skipCurrent() { store.mutate { $0.exercises[index].status="skipped";$0.current=min(index+1,$0.exercises.count-1) }; dismiss() }
}
struct ProgressView:View { @Environment(Store.self) var store; var body:some View {NavigationStack{List{Section("Итоги"){LabeledContent("Завершено тренировок",value:"\(store.records.count)");LabeledContent("Тоннаж",value:"\(store.totalTonnage.formatted(.number.precision(.fractionLength(0...1)))) кг·повт.");LabeledContent("Подходов",value:"\(store.completedSets)")};ForEach(Catalog.workouts){w in Section(w.title){let rec=store.records.filter{$0.workoutID==w.id};if rec.isEmpty{Text("Пока нет выполнений").foregroundStyle(.secondary)};ForEach(rec){r in VStack(alignment:.leading,spacing:8){HStack{Text(r.date.formatted(date:.abbreviated,time:.shortened)).font(.headline);Spacer();Text("\(tonnage(r).formatted(.number.precision(.fractionLength(0...1)))) кг·повт.").foregroundStyle(.secondary)};ForEach(r.exercises){e in VStack(alignment:.leading){Text(Catalog.e(e.actualID).title).font(.subheadline);Text(e.sets.map{"\($0.weight) кг × \($0.reps)"}.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)}}}}}}}.navigationTitle("Прогресс")}}
 func tonnage(_ r:Record)->Double{Metrics.tonnage(r.exercises)} }
struct StatsView:View { @Environment(Store.self) var store; @State private var selectedWorkout="w1"; var body:some View {NavigationStack{ScrollView{VStack(spacing:14){Card{VStack(alignment:.leading,spacing:12){Text("Частота").font(.headline);LabeledContent("За неделю",value:"\(count(.weekOfYear))");LabeledContent("За месяц",value:"\(count(.month))");LabeledContent("Последняя тренировка",value:store.records.first?.date.formatted(date:.abbreviated,time:.omitted) ?? "—")}};Card{VStack(alignment:.leading,spacing:8){Text("Самый продуктивный день").font(.headline);let best=Dictionary(grouping:store.records){Calendar.current.startOfDay(for:$0.date)}.mapValues{rs in rs.reduce(0.0){$0+Metrics.tonnage($1.exercises)}}.max{$0.value<$1.value};Text(best.map{"\($0.key.formatted(date:.long,time:.omitted)) · \($0.value.formatted()) кг·повт."} ?? "Пока нет данных")};};Card{VStack(alignment:.leading){Text("Тренировки одного типа").font(.headline);Picker("Тренировка",selection:$selectedWorkout){ForEach(Catalog.workouts){w in Text(w.title).tag(w.id)}}.pickerStyle(.segmented);let recent=store.records.filter{$0.workoutID==selectedWorkout}.prefix(6);Chart { ForEach(Catalog.workouts.first(where:{$0.id==selectedWorkout})?.exercises ?? []) { ex in ForEach(Array(recent)){r in if let saved=r.exercises.first(where:{$0.exerciseID==ex.id}) { LineMark(x:.value("Дата",r.date),y:.value("Тоннаж",Metrics.tonnage([saved])),series:.value("Упражнение",ex.title)).foregroundStyle(by:.value("Упражнение",ex.title));PointMark(x:.value("Дата",r.date),y:.value("Тоннаж",Metrics.tonnage([saved]))).foregroundStyle(by:.value("Упражнение",ex.title)) } } } }.frame(height:220);Text("Тоннаж показан отдельно для каждого упражнения").font(.caption).foregroundStyle(.secondary)}};Card{VStack(alignment:.leading){Text("Вода · 7 дней").font(.headline);Chart { ForEach(lastWaterWeek(),id:\.day){d in BarMark(x:.value("День",d.day),y:.value("Мл",d.ml)).foregroundStyle(.cyan)} }.frame(height:170);ForEach(lastWaterWeek(),id:\.day){d in HStack{Text(d.day);Spacer();Text("\(d.ml) мл")}}}};Card{VStack(alignment:.leading){Text("Динамика измерений · 12 месяцев").font(.headline);ForEach(["weight","height"],id:\.self){k in let vals=store.measures.filter{$0.kind==k && $0.date>=Calendar.current.date(byAdding:.month,value:-12,to:Date())!}.sorted{$0.date<$1.date};if !vals.isEmpty{Text(k=="weight" ? "Вес, кг":"Рост, см").font(.subheadline);Chart(vals){m in LineMark(x:.value("Дата",m.date),y:.value("Значение",m.value)).foregroundStyle(.indigo)}.frame(height:150)}}}}}.padding()}.background(Color(uiColor:.secondarySystemGroupedBackground)).navigationTitle("Статистика")}}; func count(_ component:Calendar.Component)->Int{let now=Date();let start=Calendar.current.dateInterval(of:component,for:now)?.start ?? now;return store.records.filter{$0.date>=start}.count}; func lastWaterWeek()->[WaterDay]{(0..<7).compactMap{offset in guard let day=Calendar.current.date(byAdding:.day,value:offset-6,to:Date()) else{return nil};let f=DateFormatter();f.dateFormat="yyyy-MM-dd";f.timeZone = .current;let key=f.string(from:day);return store.water.first(where:{$0.day==key}) ?? WaterDay(day:key,ml:0)}} }
struct SettingsView:View { @Environment(Store.self) var store; @State private var importing=false; @State private var shareURL:URL?; @State private var confirmClear=false; @State private var message:String?; var body:some View {NavigationStack{List{Section("Данные"){Button{shareURL=store.export()} label: {Label("Экспорт JSON",systemImage:"square.and.arrow.up")};Button{importing=true} label: {Label("Импорт копии",systemImage:"square.and.arrow.down")};Button(role:.destructive){confirmClear=true} label: {Label("Очистить все данные",systemImage:"trash")}};Section("Напоминания"){Toggle("Вода · 09:00–23:00",isOn:Binding(get:{store.reminders},set:{store.reminders=$0;store.save();Task{await store.schedule()}}))};Section("Разработчик"){Link("Открыть Telegram",destination:URL(string:"https://t.me/sellyou4ss")!)};Section{Text("Данные хранятся только на этом устройстве.").foregroundStyle(.secondary)}}.navigationTitle("Настройки").fileImporter(isPresented:$importing,allowedContentTypes:[.json]){result in do{let url=try result.get();let accessed=url.startAccessingSecurityScopedResource();defer{if accessed{url.stopAccessingSecurityScopedResource()}};try store.restore(Data(contentsOf:url));message="Копия импортирована";Task{await store.schedule()}}catch{message="Не удалось импортировать: \(error.localizedDescription)"}}.confirmationDialog("Удалить все пользовательские данные?",isPresented:$confirmClear,titleVisibility:.visible){Button("Удалить данные",role:.destructive){store.clear()};Button("Отмена",role:.cancel){}} message:{Text("История тренировок, измерения, вода, инструкции и активная тренировка будут удалены.")}.sheet(item:Binding(get:{shareURL.map{ShareItem(url:$0)}},set:{shareURL=$0?.url})){item in ActivityView(url:item.url)}.alert("Информация",isPresented:Binding(get:{message != nil},set:{if !$0{message=nil}})){Button("OK"){message=nil}}message:{Text(message ?? "")}}}}
struct ShareItem:Identifiable{let id=UUID();let url:URL}
struct ActivityView:UIViewControllerRepresentable{let url:URL;func makeUIViewController(context:Context)->UIActivityViewController{UIActivityViewController(activityItems:[url],applicationActivities:nil)};func updateUIViewController(_ controller:UIActivityViewController,context:Context){}}


func exerciseUIImage(_ name:String)->UIImage {
 if let path=Bundle.main.path(forResource:name,ofType:"png"), let image=UIImage(contentsOfFile:path) { return image }
 return UIImage(systemName:"figure.strengthtraining.traditional") ?? UIImage()
}


