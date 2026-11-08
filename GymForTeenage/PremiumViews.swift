import SwiftUI
import Charts
import UniformTypeIdentifiers
import UIKit

struct PremiumRootView: View {
    @Environment(Store.self) private var store
    @State private var selection = 0
    var body: some View {
        ZStack(alignment: .bottom) {
            TeenTheme.ink.ignoresSafeArea()
            Group {
                switch selection {
                case 0: PremiumHomeView()
                case 1: PremiumProgressView()
                case 2: PremiumStatisticsView()
                default: PremiumSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            PremiumTabBar(selection: $selection).padding(.horizontal, 20).padding(.bottom, 8)
        }
        .tint(TeenTheme.lime)
        .preferredColorScheme(.dark)
        .alert("Сообщение", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("ОК") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

private struct PremiumTabBar: View {
    @Binding var selection: Int
    private let items = [("Главная", "house.fill"), ("Прогресс", "chart.line.uptrend.xyaxis"), ("Статистика", "chart.bar.fill"), ("Настройки", "slider.horizontal.3")]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button { selection = index } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.1).font(.subheadline.weight(.semibold))
                        Text(item.0).font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .foregroundStyle(selection == index ? TeenTheme.ink : TeenTheme.muted)
                    .background(selection == index ? TeenTheme.lime : .clear, in: Capsule())
                }.buttonStyle(TeenPressStyle())
            }
        }
        .padding(6).background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(TeenTheme.line, lineWidth: 1))
    }
}

struct PremiumHomeView: View {
    @Environment(Store.self) private var store
    @State private var showMeasure = false
    @State private var kind = "weight"
    @State private var value = ""
    private var waterProgress: Double { Double(store.todayML) / 3000 }
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    header
                    HStack(spacing: 12) { measureCard("Вес", unit: "кг", kind: "weight", icon: "scalemass.fill", tint: TeenTheme.violet); measureCard("Рост", unit: "см", kind: "height", icon: "ruler.fill", tint: TeenTheme.ice) }
                    TeenSectionTitle("тренировки", detail: store.session == nil ? "3 программы" : "есть активная")
                    ForEach(Catalog.workouts) { workout in workoutCard(workout) }
                    TeenSectionTitle("вода сегодня", detail: "цель 3 000 мл")
                    waterCard
                }
                .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 112)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showMeasure) { measureSheet }
        }
    }
    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) { Text("teenage").font(.system(size: 34, weight: .bold, design: .rounded)); Text("Твой темп. Твоя сила.").font(.subheadline).foregroundStyle(TeenTheme.muted) }
            Spacer()
            Button { kind = "weight"; value = ""; showMeasure = true } label: { Image(systemName: "plus").font(.headline).frame(width: 42, height: 42).background(TeenTheme.raised, in: Circle()).overlay(Circle().stroke(TeenTheme.line)) }.buttonStyle(TeenPressStyle())
        }
    }
    private func latest(_ kind: String) -> Measure? { store.measures.filter { $0.kind == kind }.max { $0.date < $1.date } }
    private func measureCard(_ title: String, unit: String, kind: String, icon: String, tint: Color) -> some View {
        Button { self.kind = kind; value = ""; showMeasure = true } label: {
            TeenCard(accent: tint) {
                Image(systemName: icon).foregroundStyle(tint); Spacer(minLength: 18)
                Text(latest(kind).map { "\($0.value.formatted(.number.precision(.fractionLength(0...1))))" } ?? "—").font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit()
                Text("\(title) · \(unit)").font(.caption.weight(.medium)).foregroundStyle(TeenTheme.muted)
            }.frame(maxWidth: .infinity, minHeight: 142)
        }.buttonStyle(TeenPressStyle())
    }
    private func workoutCard(_ workout: Training) -> some View {
        let active = store.session?.workoutID == workout.id
        return NavigationLink { PremiumWorkoutView(workout: workout) } label: {
            TeenCard(accent: active ? TeenTheme.lime : TeenTheme.violet) {
                HStack(spacing: 14) {
                    Text(workout.id.replacingOccurrences(of: "w", with: "0")).font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(active ? TeenTheme.lime : TeenTheme.violet).frame(width: 42, height: 42).background((active ? TeenTheme.lime : TeenTheme.violet).opacity(0.13), in: Circle())
                    VStack(alignment: .leading, spacing: 5) { Text(workout.title).font(.headline); Text(active ? "Продолжить незавершённую тренировку" : "\(workout.exercises.count) упражнений").font(.caption).foregroundStyle(TeenTheme.muted) }
                    Spacer(); Image(systemName: active ? "arrow.clockwise" : "arrow.up.right").font(.headline).foregroundStyle(active ? TeenTheme.lime : .white)
                }
            }
        }.buttonStyle(TeenPressStyle())
    }
    private var waterCard: some View {
        TeenCard(accent: TeenTheme.ice) {
            HStack(spacing: 18) {
                ZStack { Circle().stroke(TeenTheme.raised, lineWidth: 10); Circle().trim(from: 0, to: waterProgress).stroke(TeenTheme.ice, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90)).animation(.easeInOut(duration: 0.35), value: waterProgress); VStack(spacing: 1) { Text("\(store.todayML)").font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit(); Text("мл").font(.caption2).foregroundStyle(TeenTheme.muted) } }.frame(width: 104, height: 104)
                VStack(alignment: .leading, spacing: 9) { Text("Держи ритм").font(.headline); Text("Осталось \(max(0, 3000 - store.todayML)) мл до цели").font(.caption).foregroundStyle(TeenTheme.muted); Button { store.addWater() } label: { Label("+ 200 мл", systemImage: "drop.fill").font(.subheadline.weight(.bold)).foregroundStyle(TeenTheme.ink).padding(.horizontal, 14).padding(.vertical, 10).background(TeenTheme.ice, in: Capsule()) }.disabled(store.todayML >= 3000).buttonStyle(TeenPressStyle()) }
            }
        }
    }
    private var measureSheet: some View {
        NavigationStack { ZStack { TeenTheme.ink.ignoresSafeArea(); VStack(spacing: 18) { Text(kind == "weight" ? "Новый вес" : "Новый рост").font(.title2.bold()); TextField(kind == "weight" ? "кг" : "см", text: $value).keyboardType(.decimalPad).font(.system(.title, design: .rounded)).multilineTextAlignment(.center).padding().background(TeenTheme.surface, in: RoundedRectangle(cornerRadius: 18)); Button("Сохранить") { if let input = Double(value.replacingOccurrences(of: ",", with: ".")), input > 0 { store.measures.append(.init(kind: kind, value: input)); store.save() }; showMeasure = false }.buttonStyle(.borderedProminent).tint(TeenTheme.lime) }.padding(24) }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { showMeasure = false } } } }
    }
}

struct PremiumWorkoutView: View {
    @Environment(Store.self) private var store
    let workout: Training
    var body: some View {
        let session = store.current(workout)
        ScrollView { VStack(spacing: 14) {
            TeenCard(accent: TeenTheme.lime) { HStack { VStack(alignment: .leading, spacing: 5) { Text(workout.title).font(.title2.bold()); Text("\(session.exercises.filter { $0.status == "completed" }.count) из \(session.exercises.count) упражнений").foregroundStyle(TeenTheme.muted).font(.caption) }; Spacer(); ZStack { Circle().stroke(TeenTheme.raised, lineWidth: 6); Circle().trim(from: 0, to: Double(session.exercises.filter { $0.status == "completed" || $0.status == "skipped" }.count) / Double(session.exercises.count)).stroke(TeenTheme.lime, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90)); Text("\(session.current + 1)").font(.headline) }.frame(width: 50, height: 50) } }
            ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, entry in NavigationLink { PremiumExerciseView(workout: workout, index: index) } label: { exerciseRow(entry, index: index) }.buttonStyle(TeenPressStyle()) }
            Button { store.finish() } label: { Text("Завершить тренировку").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15).foregroundStyle(TeenTheme.ink).background(TeenTheme.lime, in: Capsule()) }.buttonStyle(TeenPressStyle())
        }.padding(20).padding(.bottom, 30) }.background(TeenTheme.ink).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .principal) { Text(workout.title.uppercased()).font(.caption.weight(.bold)) } }
    }
    private func exerciseRow(_ entry: ExerciseLog, index: Int) -> some View { TeenCard(accent: entry.status == "completed" ? TeenTheme.lime : nil) { HStack(spacing: 13) { Image(uiImage: exerciseUIImage(Catalog.e(entry.actualID).image)).resizable().scaledToFill().frame(width: 54, height: 54).clipShape(Circle()); VStack(alignment: .leading, spacing: 4) { Text(Catalog.e(entry.actualID).title).font(.subheadline.weight(.semibold)); Text(entry.status == "skipped" ? "Пропущено" : "Упражнение \(index + 1)").font(.caption).foregroundStyle(entry.status == "skipped" ? .red : TeenTheme.muted) }; Spacer(); Image(systemName: entry.status == "completed" ? "checkmark.circle.fill" : "chevron.right").foregroundStyle(entry.status == "completed" ? TeenTheme.lime : TeenTheme.muted) } } }
}

struct PremiumExerciseView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let workout: Training
    let index: Int
    @State private var replace = false
    var body: some View {
        let session = store.current(workout); let entry = session.exercises[index]; let exercise = Catalog.e(entry.actualID)
        ScrollView { VStack(spacing: 16) { hero(exercise, session: session); setCard(entry); actionRow(entry); notes(entry); history(entry); Button(index + 1 < session.exercises.count ? "Сохранить и далее" : "К списку") { advance(session) }.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15).foregroundStyle(TeenTheme.ink).background(TeenTheme.lime, in: Capsule()).buttonStyle(TeenPressStyle()); Button("Пропустить упражнение") { skip() }.font(.caption.weight(.medium)).foregroundStyle(.red) }.padding(20).padding(.bottom, 24) }
            .background(TeenTheme.ink)
            .navigationBarTitleDisplayMode(.inline)
            .simultaneousGesture(DragGesture(minimumDistance: 55).onEnded { if $0.translation.width < -60 { skip() } })
            .confirmationDialog("Заменить упражнение", isPresented: $replace) {
                ForEach(Catalog.all.filter { $0.id != entry.exerciseID }) { item in
                    Button(item.title) { store.mutate { $0.exercises[index].actualID = item.id } }
                }
            }
    }
    private func hero(_ exercise: Exercise, session: Session) -> some View { TeenCard(accent: TeenTheme.lime) { VStack(spacing: 12) { ZStack { Circle().stroke(TeenTheme.raised, lineWidth: 6); Circle().trim(from: 0, to: Double(index + 1) / Double(session.exercises.count)).stroke(TeenTheme.lime, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90)); Image(uiImage: exerciseUIImage(exercise.image)).resizable().scaledToFill().frame(width: 92, height: 92).clipShape(Circle()) }.frame(width: 108, height: 108); Text(exercise.title.uppercased()).font(.headline).multilineTextAlignment(.center); Text("Тренировка · упражнение \(index + 1)").font(.caption).foregroundStyle(TeenTheme.muted) } .frame(maxWidth: .infinity) } }
    private func setCard(_ entry: ExerciseLog) -> some View { TeenCard { VStack(alignment: .leading, spacing: 12) { TeenSectionTitle("подходы", detail: "вес · повторы"); ForEach(entry.sets.indices, id: \.self) { row in setRow(entry.sets[row], row: row) }; HStack { Button { store.mutate { $0.exercises[index].sets.append(SetLog()) } } label: { Label("Подход", systemImage: "plus").font(.subheadline.weight(.bold)).foregroundStyle(TeenTheme.lime) }; Spacer(); if entry.sets.count > 2 { Button("Удалить") { store.mutate { $0.exercises[index].sets.removeLast() } }.foregroundStyle(.red).font(.caption) } } } } }
    private func setRow(_ set: SetLog, row: Int) -> some View { HStack(spacing: 8) { Text("\(row + 1)").font(.caption.weight(.bold)).frame(width: 30, height: 30).background(set.skipped ? Color.red.opacity(0.16) : TeenTheme.lime.opacity(0.12), in: Circle()).foregroundStyle(set.skipped ? .red : TeenTheme.lime); TextField("кг", text: Binding(get: { set.weight }, set: { value in store.mutate { s in s.exercises[index].sets[row].weight = value; if row == 0 && s.exercises[index].sets.count > 1 && s.exercises[index].sets[1].weight.isEmpty { s.exercises[index].sets[1].weight = value } } })).keyboardType(.decimalPad).multilineTextAlignment(.center).padding(10).background(TeenTheme.raised, in: Capsule()); TextField("раз", text: Binding(get: { set.reps }, set: { value in store.mutate { $0.exercises[index].sets[row].reps = value } })).keyboardType(.numberPad).multilineTextAlignment(.center).padding(10).background(TeenTheme.raised, in: Capsule()); Button { store.mutate { $0.exercises[index].sets[row].skipped.toggle() } } label: { Image(systemName: set.skipped ? "xmark" : "checkmark").font(.caption.weight(.bold)).frame(width: 34, height: 34).foregroundStyle(set.skipped ? .red : TeenTheme.lime).background((set.skipped ? Color.red : TeenTheme.lime).opacity(0.14), in: Circle()) } } }
    private func actionRow(_ entry: ExerciseLog) -> some View { HStack(spacing: 10) { Button { replace = true } label: { action("Заменить", icon: "arrow.triangle.2.circlepath") }; NavigationLink { PremiumHistoryView(exerciseID: entry.exerciseID) } label: { action("История", icon: "clock.arrow.circlepath") } } }
    private func action(_ text: String, icon: String) -> some View { VStack(spacing: 6) { Image(systemName: icon); Text(text).font(.caption2.weight(.semibold)) }.foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 12).background(TeenTheme.surface, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(TeenTheme.line)) }
    private func notes(_ entry: ExerciseLog) -> some View { TeenCard { VStack(alignment: .leading, spacing: 8) { Text("Заметка и техника").font(.headline); TextEditor(text: Binding(get: { store.instructions[entry.exerciseID] ?? "" }, set: { store.instructions[entry.exerciseID] = $0; store.save() })).scrollContentBackground(.hidden).frame(minHeight: 88).padding(6).background(TeenTheme.raised, in: RoundedRectangle(cornerRadius: 14)) } } }
    private func history(_ entry: ExerciseLog) -> some View { let recent = store.records.filter { $0.exercises.contains { $0.exerciseID == entry.exerciseID } }.prefix(3); return TeenCard { VStack(alignment: .leading, spacing: 8) { Text("Последние выполнения").font(.headline); if recent.isEmpty { Text("История появится после первой тренировки").font(.caption).foregroundStyle(TeenTheme.muted) } else { ForEach(Array(recent)) { Text("\($0.name) · \($0.date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(TeenTheme.muted) } } } }
    private func advance(_ session: Session) { store.mutate { $0.exercises[index].status = "completed"; $0.current = min(index + 1, $0.exercises.count - 1) }; dismiss() }
    private func skip() { store.mutate { $0.exercises[index].status = "skipped"; $0.current = min(index + 1, $0.exercises.count - 1) }; dismiss() }
}

struct PremiumHistoryView: View { @Environment(Store.self) private var store; let exerciseID: String; var body: some View { List(store.records.filter { $0.exercises.contains { $0.exerciseID == exerciseID } }) { record in VStack(alignment: .leading) { Text(record.name).font(.headline); Text(record.date.formatted(date: .long, time: .shortened)).foregroundStyle(.secondary).font(.caption) } }.navigationTitle("История") } }

struct PremiumProgressView: View {
    @Environment(Store.self) private var store
    var body: some View {
        NavigationStack { ScrollView(showsIndicators: false) { VStack(spacing: 16) {
            header
            HStack(spacing: 10) { TeenMetric(title: "тренировок", value: "\(store.records.count)", icon: "figure.strengthtraining.traditional", tint: TeenTheme.lime); TeenMetric(title: "тоннаж", value: short(store.totalTonnage), icon: "scalemass.fill", tint: TeenTheme.violet); TeenMetric(title: "подходов", value: "\(store.completedSets)", icon: "checkmark.circle.fill", tint: TeenTheme.ice) }
            TeenSectionTitle("по программам", detail: "последние 6")
            ForEach(Catalog.workouts) { workout in workoutBlock(workout) }
        }.padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 112) }.toolbar(.hidden, for: .navigationBar) }
    }
    private var header: some View { HStack { VStack(alignment: .leading, spacing: 4) { Text("прогресс").font(.system(.largeTitle, design: .rounded, weight: .bold)); Text("История твоей работы").font(.subheadline).foregroundStyle(TeenTheme.muted) }; Spacer(); Image(systemName: "chart.line.uptrend.xyaxis").font(.title3).foregroundStyle(TeenTheme.lime).frame(width: 42, height: 42).background(TeenTheme.surface, in: Circle()) } }
    private func workoutBlock(_ workout: Training) -> some View {
        let records = Array(store.records.filter { $0.workoutID == workout.id }.prefix(6).reversed())
        return TeenCard(accent: TeenTheme.violet) { VStack(alignment: .leading, spacing: 12) { HStack { VStack(alignment: .leading, spacing: 3) { Text(workout.title).font(.headline); Text("\(records.count) завершений").font(.caption).foregroundStyle(TeenTheme.muted) }; Spacer(); TeenPill(title: records.isEmpty ? "нет данных" : "\(short(records.last.map { Metrics.tonnage($0.exercises) } ?? 0)) кг", tint: TeenTheme.lime) }; if records.isEmpty { TeenEmpty(icon: "chart.line.flattrend.xyaxis", title: "Первое выполнение впереди", detail: "Заверши тренировку, чтобы увидеть динамику тоннажа.") } else { Chart(records) { record in AreaMark(x: .value("Дата", record.date), y: .value("Тоннаж", Metrics.tonnage(record.exercises))).foregroundStyle(LinearGradient(colors: [TeenTheme.lime.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)); LineMark(x: .value("Дата", record.date), y: .value("Тоннаж", Metrics.tonnage(record.exercises))).foregroundStyle(TeenTheme.lime).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round)); PointMark(x: .value("Дата", record.date), y: .value("Тоннаж", Metrics.tonnage(record.exercises))).foregroundStyle(TeenTheme.lime) }.frame(height: 130).chartXAxis(.hidden).chartYAxis(.hidden); ForEach(records.suffix(2)) { record in HStack { Text(record.date.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(TeenTheme.muted); Spacer(); Text("\(short(Metrics.tonnage(record.exercises))) кг·повт.").fontWeight(.semibold) }.font(.caption) } } } }
    }
    private func short(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...0))) }
}

struct PremiumStatisticsView: View {
    @Environment(Store.self) private var store
    @State private var selectedWorkout = "w1"
    var body: some View {
        NavigationStack { ScrollView(showsIndicators: false) { VStack(spacing: 16) {
            HStack { VStack(alignment: .leading, spacing: 4) { Text("статистика").font(.system(.largeTitle, design: .rounded, weight: .bold)); Text("Реальные данные за твой период").font(.subheadline).foregroundStyle(TeenTheme.muted) }; Spacer() }
            frequency
            comparison
            water
            measures(kind: "weight", title: "вес", tint: TeenTheme.violet)
            measures(kind: "height", title: "рост", tint: TeenTheme.ice)
        }.padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 112) }.toolbar(.hidden, for: .navigationBar) }
    }
    private var frequency: some View { TeenCard(accent: TeenTheme.lime) { HStack(spacing: 10) { TeenMetric(title: "неделя", value: "\(count(.weekOfYear))", icon: "calendar", tint: TeenTheme.lime); TeenMetric(title: "месяц", value: "\(count(.month))", icon: "calendar.badge.clock", tint: TeenTheme.violet); VStack(alignment: .leading, spacing: 5) { Text("Лучший день").font(.caption).foregroundStyle(TeenTheme.muted); Text(bestDay ?? "Пока нет").font(.subheadline.weight(.bold)); Text("по тоннажу").font(.caption2).foregroundStyle(TeenTheme.muted) }.frame(maxWidth: .infinity) } } }
    private var comparison: some View { let records = Array(store.records.filter { $0.workoutID == selectedWorkout }.prefix(6).reversed()); return TeenCard(accent: TeenTheme.violet) { VStack(alignment: .leading, spacing: 12) { TeenSectionTitle("сравнение тренировок"); Picker("Тренировка", selection: $selectedWorkout) { ForEach(Catalog.workouts) { Text($0.title).tag($0.id) } }.pickerStyle(.segmented); if records.isEmpty { TeenEmpty(icon: "chart.xyaxis.line", title: "Ещё нет сравнений", detail: "После завершения тренировок здесь появятся реальные линии нагрузки.") } else { Chart(records) { record in LineMark(x: .value("Дата", record.date), y: .value("Тоннаж", Metrics.tonnage(record.exercises))).foregroundStyle(TeenTheme.violet).lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round)); PointMark(x: .value("Дата", record.date), y: .value("Тоннаж", Metrics.tonnage(record.exercises))).foregroundStyle(TeenTheme.lime) }.frame(height: 180).chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }.chartYAxis { AxisMarks(position: .leading) } } } }
    private var water: some View { let days = waterDays(); return TeenCard(accent: TeenTheme.ice) { VStack(alignment: .leading, spacing: 12) { TeenSectionTitle("вода", detail: "7 дней"); Chart(days, id: \.day) { day in BarMark(x: .value("День", String(day.day.suffix(2))), y: .value("Мл", day.ml)).foregroundStyle(day.day == store.today ? TeenTheme.ice : TeenTheme.ice.opacity(0.35)).cornerRadius(5).annotation(position: .top) { if day.ml > 0 { Text("\(day.ml)").font(.caption2).foregroundStyle(TeenTheme.muted) } } }.frame(height: 170).chartYAxis { AxisMarks(position: .leading) } } }
    private func measures(kind: String, title: String, tint: Color) -> some View { let values = store.measures.filter { $0.kind == kind && $0.date >= Calendar.current.date(byAdding: .month, value: -12, to: Date())! }.sorted { $0.date < $1.date }; return TeenCard(accent: tint) { VStack(alignment: .leading, spacing: 12) { TeenSectionTitle(title, detail: "12 месяцев"); if values.isEmpty { TeenEmpty(icon: kind == "weight" ? "scalemass" : "ruler", title: "Нет измерений", detail: "Добавь \(title), чтобы увидеть настоящую динамику.") } else { Chart(values) { value in AreaMark(x: .value("Дата", value.date), y: .value("Значение", value.value)).foregroundStyle(LinearGradient(colors: [tint.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)); LineMark(x: .value("Дата", value.date), y: .value("Значение", value.value)).foregroundStyle(tint).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round)); PointMark(x: .value("Дата", value.date), y: .value("Значение", value.value)).foregroundStyle(tint) }.frame(height: 170).chartYAxis { AxisMarks(position: .leading) } } } }
    private func count(_ component: Calendar.Component) -> Int { let now = Date(); let start = Calendar.current.dateInterval(of: component, for: now)?.start ?? now; return store.records.filter { $0.date >= start }.count }
    private var bestDay: String? { Dictionary(grouping: store.records) { Calendar.current.startOfDay(for: $0.date) }.map { ($0.key, $0.value.reduce(0.0) { $0 + Metrics.tonnage($1.exercises) }) }.filter { $0.1 > 0 }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }.first.map { $0.0.formatted(date: .abbreviated, time: .omitted) } }
    private func waterDays() -> [WaterDay] { (0..<7).compactMap { offset in guard let date = Calendar.current.date(byAdding: .day, value: offset - 6, to: Date()) else { return nil }; let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = .current; let day = formatter.string(from: date); return store.water.first { $0.day == day } ?? WaterDay(day: day, ml: 0) } }
}

struct PremiumSettingsView: View {
    @Environment(Store.self) private var store
    @State private var importing = false
    @State private var shareURL: URL?
    @State private var confirmClear = false
    @State private var message: String?
    var body: some View {
        NavigationStack { ScrollView(showsIndicators: false) { VStack(spacing: 16) {
            HStack { VStack(alignment: .leading, spacing: 4) { Text("настройки").font(.system(.largeTitle, design: .rounded, weight: .bold)); Text("Данные остаются на устройстве").font(.subheadline).foregroundStyle(TeenTheme.muted) }; Spacer() }
            TeenSectionTitle("данные")
            TeenCard(accent: TeenTheme.ice) { VStack(spacing: 2) { settingButton("Экспорт JSON", detail: "Создать полную резервную копию", icon: "square.and.arrow.up", tint: TeenTheme.ice) { shareURL = store.export(); if shareURL == nil { message = "Не удалось создать копию" } }; divider; settingButton("Импорт копии", detail: "Заменить данные из проверенного JSON", icon: "square.and.arrow.down", tint: TeenTheme.violet) { importing = true }; divider; settingButton("Очистить все данные", detail: "История, вода и незавершённая тренировка", icon: "trash", tint: .red) { confirmClear = true } } }
            TeenSectionTitle("напоминания")
            TeenCard(accent: TeenTheme.lime) { HStack(spacing: 13) { Image(systemName: "drop.badge.clock").foregroundStyle(TeenTheme.lime).font(.title3).frame(width: 38, height: 38).background(TeenTheme.lime.opacity(0.12), in: Circle()); VStack(alignment: .leading, spacing: 4) { Text("Вода").font(.headline); Text("Каждые 2 часа · 09:00–23:00").font(.caption).foregroundStyle(TeenTheme.muted) }; Spacer(); Toggle("Вода", isOn: Binding(get: { store.reminders }, set: { store.reminders = $0; store.save(); Task { await store.schedule() } })).labelsHidden().tint(TeenTheme.lime) } }
            TeenSectionTitle("информация")
            TeenCard { VStack(alignment: .leading, spacing: 10) { Label("Только локальное хранение", systemImage: "lock.fill").font(.headline); Text("Тренировки, измерения и резервные копии не отправляются на сервер. JSON-копия нужна, чтобы перенести или восстановить свои данные.").font(.caption).foregroundStyle(TeenTheme.muted); Link(destination: URL(string: "https://t.me/sellyou4ss")!) { Label("Telegram разработчика", systemImage: "paperplane.fill").font(.subheadline.weight(.semibold)).foregroundStyle(TeenTheme.ice) } } }
        }.padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 112) }.toolbar(.hidden, for: .navigationBar)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do { let url = try result.get(); let accessed = url.startAccessingSecurityScopedResource(); defer { if accessed { url.stopAccessingSecurityScopedResource() } }; try store.restore(Data(contentsOf: url)); message = "Копия импортирована"; Task { await store.schedule() } } catch { message = "Не удалось импортировать: \(error.localizedDescription)" }
            }
            .confirmationDialog("Удалить все пользовательские данные?", isPresented: $confirmClear, titleVisibility: .visible) { Button("Удалить данные", role: .destructive) { store.clear() }; Button("Отмена", role: .cancel) { } } message: { Text("История тренировок, измерения, вода, инструкции и активная тренировка будут удалены.") }
            .sheet(item: Binding(get: { shareURL.map { ShareItem(url: $0) } }, set: { shareURL = $0?.url })) { ActivityView(url: $0.url) }
            .alert("Информация", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("ОК") { message = nil } } message: { Text(message ?? "") }
        }
    }
    private var divider: some View { Rectangle().fill(TeenTheme.line).frame(height: 1).padding(.leading, 52) }
    private func settingButton(_ title: String, detail: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View { Button(action: action) { HStack(spacing: 13) { Image(systemName: icon).foregroundStyle(tint).frame(width: 38, height: 38).background(tint.opacity(0.13), in: Circle()); VStack(alignment: .leading, spacing: 3) { Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white); Text(detail).font(.caption).foregroundStyle(TeenTheme.muted) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(TeenTheme.muted) }.padding(.vertical, 5) }.buttonStyle(TeenPressStyle()) }
}
