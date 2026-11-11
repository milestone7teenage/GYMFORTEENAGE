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
                    TeenSectionTitle("креатин сегодня", detail: "ежедневная отметка")
                    creatineCard
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
                HStack(spacing: 12) {
                    Image(systemName: icon).foregroundStyle(tint).font(.title3)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(latest(kind).map { "\($0.value.formatted(.number.precision(.fractionLength(0...1))))" } ?? "—").font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
                        Text("\(title) · \(unit)").font(.caption2.weight(.medium)).foregroundStyle(TeenTheme.muted)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity).frame(height: 72, alignment: .leading)
            }.frame(maxWidth: .infinity)
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
    private var creatineCard: some View {
        TeenCard(accent: store.todayCreatine ? TeenTheme.lime : TeenTheme.raised) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(store.todayCreatine ? TeenTheme.lime : TeenTheme.raised, lineWidth: 2)
                    Image(systemName: store.todayCreatine ? "checkmark" : "pill")
                        .foregroundStyle(store.todayCreatine ? TeenTheme.ink : TeenTheme.muted)
                        .font(.title3)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Принять креатин").font(.subheadline.weight(.semibold))
                    Text(store.todayCreatine ? "Сегодня отмечено" : "Не отмечено").font(.caption2).foregroundStyle(TeenTheme.muted)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        store.creatineToggle()
                    }
                } label: {
                    Image(systemName: store.todayCreatine ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(store.todayCreatine ? TeenTheme.lime : TeenTheme.muted)
                        .font(.title2)
                }
                .buttonStyle(TeenPressStyle())
            }
            .padding(.vertical, 4)
        }
    }
    private var measureSheet: some View {
        NavigationStack { ZStack { TeenTheme.ink.ignoresSafeArea(); VStack(spacing: 18) { Text(kind == "weight" ? "Новый вес" : "Новый рост").font(.title2.bold()); TextField(kind == "weight" ? "кг" : "см", text: $value).keyboardType(.decimalPad).font(.system(.title, design: .rounded)).multilineTextAlignment(.center).padding().background(TeenTheme.surface, in: RoundedRectangle(cornerRadius: 18)); Button("Сохранить") { if let input = Double(value.replacingOccurrences(of: ",", with: ".")), input > 0 { store.measures.append(.init(kind: kind, value: input)); store.save() }; showMeasure = false }.buttonStyle(.borderedProminent).tint(TeenTheme.lime) }.padding(24) }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { showMeasure = false } } } }
    }
}

struct PremiumWorkoutView: View {
    @Environment(Store.self) private var store
    let workout: Training
    @State private var showRecovery = false
    var body: some View {
        let session = store.current(workout)
        ScrollView { VStack(spacing: 14) {
            TeenCard(accent: TeenTheme.lime) { HStack { VStack(alignment: .leading, spacing: 5) { Text(workout.title).font(.title2.bold()); Text("\(session.exercises.filter { $0.status == "completed" }.count) из \(session.exercises.count) упражнений").foregroundStyle(TeenTheme.muted).font(.caption) }; Spacer(); ZStack { Circle().stroke(TeenTheme.raised, lineWidth: 6); Circle().trim(from: 0, to: Double(session.exercises.filter { $0.status == "completed" || $0.status == "skipped" }.count) / Double(session.exercises.count)).stroke(TeenTheme.lime, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90)); Text("\(session.current + 1)").font(.headline) }.frame(width: 50, height: 50) } }
            if let skipped = session.exercises.enumerated().filter({ $0.element.status == "skipped" }).first {
                Button { showRecovery = true } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Вернуть пропущенное")
                    }.font(.subheadline.weight(.semibold)).foregroundStyle(TeenTheme.lime)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(TeenTheme.lime.opacity(0.12), in: Capsule())
                }.buttonStyle(TeenPressStyle())
            }
            ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, entry in NavigationLink { PremiumExerciseView(workout: workout, index: index) } label: { exerciseRow(entry, index: index) }.buttonStyle(TeenPressStyle()) }
            Button { store.finish() } label: { Text("Завершить тренировку").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15).foregroundStyle(TeenTheme.ink).background(TeenTheme.lime, in: Capsule()) }.buttonStyle(TeenPressStyle())
        }.padding(20).padding(.bottom, 120) }.background(TeenTheme.ink).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .principal) { Text(workout.title.uppercased()).font(.caption.weight(.bold)) } }
        .confirmationDialog("Восстановить пропущенное упражнение?", isPresented: $showRecovery, titleVisibility: .visible) {
            ForEach(Array(session.exercises.enumerated()), id: \.element.id) { idx, entry in
                if entry.status == "skipped" {
                    Button("Вернуть \"\(Catalog.e(entry.actualID).title)\"") {
                        store.recoverExercise(at: idx)
                    }
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Упражнение вернётся на своё место в тренировке, все значения сохранятся.") }
    }
    private func exerciseRow(_ entry: ExerciseLog, index: Int) -> some View { TeenCard(accent: entry.status == "completed" ? TeenTheme.lime : nil) { HStack(spacing: 13) { Image(uiImage: exerciseUIImage(Catalog.e(entry.actualID).image)).resizable().scaledToFill().frame(width: 54, height: 54).clipShape(Circle()); VStack(alignment: .leading, spacing: 4) { Text(Catalog.e(entry.actualID).title).font(.subheadline.weight(.semibold)); Text(entry.status == "skipped" ? "Пропущено" : "Упражнение \(index + 1)").font(.caption).foregroundStyle(entry.status == "skipped" ? .red : TeenTheme.muted) }; Spacer(); Image(systemName: entry.status == "completed" ? "checkmark.circle.fill" : "chevron.right").foregroundStyle(entry.status == "completed" ? TeenTheme.lime : TeenTheme.muted) } } }
}

struct PremiumExerciseView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let workout: Training
    let index: Int
    @State private var replace = false
    @State private var dragOffset: CGFloat = 0
    @State private var showingSkipUndo = false
    private let skipThreshold: CGFloat = -80
    private let minimumDrag: CGFloat = 55
    var body: some View {
        let session = store.current(workout); let entry = session.exercises[index]; let exercise = Catalog.e(entry.actualID)
        ScrollView { VStack(spacing: 16) { hero(exercise, session: session); setCard(entry); actionRow(entry); notes(entry); history(entry); Button(index + 1 < session.exercises.count ? "Сохранить и далее" : "К списку") { advance(session) }.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15).foregroundStyle(TeenTheme.ink).background(TeenTheme.lime, in: Capsule()).buttonStyle(TeenPressStyle()); Button(entry.status == "skipped" ? "Вернуть упражнение" : "Пропустить упражнение") { if entry.status == "skipped" { recover() } else { skip() } }.font(.caption.weight(.medium)).foregroundStyle(entry.status == "skipped" ? TeenTheme.lime : .red) }.padding(20).padding(.bottom, 120) }
            .background(TeenTheme.ink)
            .navigationBarTitleDisplayMode(.inline)
            .offset(x: dragOffset)
            .simultaneousGesture(
                DragGesture(minimumDistance: minimumDrag)
                    .onChanged { value in
                        let translation = value.translation.width
                        if translation < 0 && abs(translation) > 10 {
                            dragOffset = max(translation, skipThreshold)
                        }
                    }
                    .onEnded { value in
                        if value.translation.width < skipThreshold {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                dragOffset = 0
                            }
                            skip()
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
            .overlay(
                HStack {
                    Spacer()
                    if dragOffset < -20 {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.title2)
                            .padding(.trailing, 20)
                    }
                }
            )
            .confirmationDialog("Заменить упражнение", isPresented: $replace) {
                ForEach(Catalog.all.filter { $0.id != entry.exerciseID }) { item in
                    Button(item.title) { store.mutate { $0.exercises[index].actualID = item.id } }
                }
            }
            .alert("Упражнение пропущено", isPresented: $showingSkipUndo) {
                Button("Отменить пропуск") {
                    store.recoverExercise(at: index)
                    showingSkipUndo = false
                }
                Button("ОК", role: .cancel) {}
            } message: { Text("Вы можете вернуть это упражнение позже в списке тренировки") }
    }
    private func hero(_ exercise: Exercise, session: Session) -> some View { TeenCard(accent: TeenTheme.lime) { VStack(spacing: 12) { ZStack { Circle().stroke(TeenTheme.raised, lineWidth: 6); Circle().trim(from: 0, to: Double(index + 1) / Double(session.exercises.count)).stroke(TeenTheme.lime, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90)); Image(uiImage: exerciseUIImage(exercise.image)).resizable().scaledToFill().frame(width: 92, height: 92).clipShape(Circle()) }.frame(width: 108, height: 108); Text(exercise.title.uppercased()).font(.headline).multilineTextAlignment(.center); Text("Тренировка · упражнение \(index + 1)").font(.caption).foregroundStyle(TeenTheme.muted) } .frame(maxWidth: .infinity) } }
    private func setCard(_ entry: ExerciseLog) -> some View { TeenCard { VStack(alignment: .leading, spacing: 12) { TeenSectionTitle("подходы", detail: "вес · повторы"); ForEach(entry.sets.indices, id: \.self) { row in setRow(entry.sets[row], row: row) }; HStack { Button { store.mutate { $0.exercises[index].sets.append(SetLog()) } } label: { Label("Подход", systemImage: "plus").font(.subheadline.weight(.bold)).foregroundStyle(TeenTheme.lime) }; Spacer(); if entry.sets.count > 2 { Button("Удалить") { store.mutate { $0.exercises[index].sets.removeLast() } }.foregroundStyle(.red).font(.caption) } } } } }
    private func setRow(_ set: SetLog, row: Int) -> some View { HStack(spacing: 8) { Text("\(row + 1)").font(.caption.weight(.bold)).frame(width: 30, height: 30).background(set.skipped ? Color.red.opacity(0.16) : TeenTheme.lime.opacity(0.12), in: Circle()).foregroundStyle(set.skipped ? .red : TeenTheme.lime); TextField("кг", text: Binding(get: { set.weight }, set: { value in store.mutate { s in s.exercises[index].sets[row].weight = value; if row == 0 && s.exercises[index].sets.count > 1 && s.exercises[index].sets[1].weight.isEmpty { s.exercises[index].sets[1].weight = value } } })).keyboardType(.decimalPad).multilineTextAlignment(.center).padding(10).background(TeenTheme.raised, in: Capsule()); TextField("раз", text: Binding(get: { set.reps }, set: { value in store.mutate { $0.exercises[index].sets[row].reps = value } })).keyboardType(.numberPad).multilineTextAlignment(.center).padding(10).background(TeenTheme.raised, in: Capsule()); Button { store.mutate { $0.exercises[index].sets[row].skipped.toggle() } } label: { Image(systemName: set.skipped ? "xmark" : "checkmark").font(.caption.weight(.bold)).frame(width: 34, height: 34).foregroundStyle(set.skipped ? .red : TeenTheme.lime).background((set.skipped ? Color.red : TeenTheme.lime).opacity(0.14), in: Circle()) } } }
    private func actionRow(_ entry: ExerciseLog) -> some View { HStack(spacing: 10) { Button { replace = true } label: { action("Заменить", icon: "arrow.triangle.2.circlepath") }; NavigationLink { PremiumHistoryView(exerciseID: entry.exerciseID) } label: { action("История", icon: "clock.arrow.circlepath") } } }
    private func action(_ text: String, icon: String) -> some View { VStack(spacing: 6) { Image(systemName: icon); Text(text).font(.caption2.weight(.semibold)) }.foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 12).background(TeenTheme.surface, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(TeenTheme.line)) }
    private func notes(_ entry: ExerciseLog) -> some View { TeenCard(accent: TeenTheme.lime) { VStack(alignment: .leading, spacing: 8) { Text("Техника выполнения").font(.headline); TextEditor(text: Binding(get: { store.instructions[entry.exerciseID] ?? TechniqueGuide.instruction(for: entry.exerciseID) }, set: { store.instructions[entry.exerciseID] = $0; store.save() })).scrollContentBackground(.hidden).frame(minHeight: 150).padding(6).background(TeenTheme.raised, in: RoundedRectangle(cornerRadius: 14)); Text("Подсказка для безопасного выполнения. Выбирай комфортный вес и диапазон движения.").font(.caption2).foregroundStyle(TeenTheme.muted) } } }
    private func history(_ entry: ExerciseLog) -> some View {
        let latest = store.exerciseHistory(for: entry.exerciseID).first
        return TeenCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Предыдущая тренировка").font(.headline)
                    Spacer()
                    if let latest { Text(latest.record.date.ruLong).font(.caption2).foregroundStyle(TeenTheme.muted) }
                }
                if let latest {
                    ForEach(Array(latest.log.sets.enumerated()), id: \.offset) { i, set in
                        HStack(spacing: 6) {
                            Text("подход \(i + 1)").font(.system(size: 9, weight: .bold)).foregroundStyle(TeenTheme.muted)
                            Spacer()
                            Text("\(set.weight) кг").font(.caption.weight(.semibold)).monospacedDigit()
                            Text("\(set.reps) повт.").font(.caption.weight(.semibold)).monospacedDigit()
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(TeenTheme.raised, in: RoundedRectangle(cornerRadius: 8))
                    }
                } else {
                    Text("Пока нет истории — заверши тренировку, чтобы увидеть результат").font(.caption).foregroundStyle(TeenTheme.muted)
                }
            }
        }
    }
    private func advance(_ session: Session) { store.mutate { $0.exercises[index].status = "completed"; $0.current = min(index + 1, $0.exercises.count - 1) }; dismiss() }
    private func skip() {
        store.mutate { $0.exercises[index].status = "skipped"; $0.current = min(index + 1, $0.exercises.count - 1) }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        showingSkipUndo = true
    }
    private func recover() {
        store.recoverExercise(at: index)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

struct PremiumHistoryView: View { @Environment(Store.self) private var store; let exerciseID: String; var body: some View { List(store.records.filter { $0.exercises.contains { $0.exerciseID == exerciseID } }) { record in VStack(alignment: .leading) { Text(record.name).font(.headline); Text(record.date.ruLong).foregroundStyle(.secondary).font(.caption) } }.navigationTitle("История") } }

struct PremiumProgressView: View {
    @Environment(Store.self) private var store
    @State private var expandedWorkout: String?
    var body: some View {
        NavigationStack { ScrollView(showsIndicators: false) { VStack(spacing: 16) {
            header
            HStack(spacing: 8) { CompactMetric(title: "тренировок", value: "\(store.records.count)", icon: "figure.strengthtraining.traditional", tint: TeenTheme.lime); CompactMetric(title: "тоннаж", value: short(store.totalTonnage), icon: "scalemass.fill", tint: TeenTheme.violet); CompactMetric(title: "подходов", value: "\(store.completedSets)", icon: "checkmark.circle.fill", tint: TeenTheme.ice) }
            TeenSectionTitle("по программам", detail: "прогрессия нагрузки")
            ForEach(Catalog.workouts) { workout in workoutBlock(workout) }
        }.frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 112) }.toolbar(.hidden, for: .navigationBar) }
    }
    private var header: some View { HStack { VStack(alignment: .leading, spacing: 4) { Text("прогресс").font(.system(.largeTitle, design: .rounded, weight: .bold)); Text("История твоей работы").font(.subheadline).foregroundStyle(TeenTheme.muted) }; Spacer(); Image(systemName: "chart.line.uptrend.xyaxis").font(.title3).foregroundStyle(TeenTheme.lime).frame(width: 42, height: 42).background(TeenTheme.surface, in: Circle()) } }
    private func workoutBlock(_ workout: Training) -> some View {
        let records = Array(store.records.filter { $0.workoutID == workout.id }.prefix(6).reversed())
        let isExpanded = expandedWorkout == workout.id
        return TeenCard(accent: TeenTheme.violet) { VStack(alignment: .leading, spacing: 12) { HStack { VStack(alignment: .leading, spacing: 3) { Text(workout.title).font(.headline); Text("\(records.count) завершений").font(.caption).foregroundStyle(TeenTheme.muted) }; Spacer(); Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { expandedWorkout = isExpanded ? nil : workout.id } } label: { TeenPill(title: records.isEmpty ? "нет данных" : "\(short(records.last.map { Metrics.tonnage($0.exercises) } ?? 0)) кг", tint: TeenTheme.lime) }.buttonStyle(TeenPressStyle()) }; if records.isEmpty { TeenEmpty(icon: "chart.line.flattrend.xyaxis", title: "Первое выполнение впереди", detail: "Заверши тренировку, чтобы увидеть динамику тоннажа.") } else { Chart(records) { record in AreaMark(x: .value("Дата", record.date), y: .value("Тоннаж", Metrics.tonnage(record.exercises))).foregroundStyle(LinearGradient(colors: [TeenTheme.lime.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)); LineMark(x: .value("Дата", record.date), y: .value("Тоннаж", Metrics.tonnage(record.exercises))).foregroundStyle(TeenTheme.lime).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round)); PointMark(x: .value("Дата", record.date), y: .value("Тоннаж", Metrics.tonnage(record.exercises))).foregroundStyle(TeenTheme.lime) }.frame(maxWidth: .infinity).frame(height: 110).chartXAxis(.hidden).chartYAxis(.hidden); ForEach(records.suffix(2)) { record in HStack { Text(record.date.ruShort).foregroundStyle(TeenTheme.muted); Spacer(); Text("\(short(Metrics.tonnage(record.exercises))) кг·повт.").fontWeight(.semibold) }.font(.caption) }; if isExpanded { exerciseProgression(workout: workout, records: records) } } } }
    }
    private func exerciseProgression(workout: Training, records: [Record]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TeenSectionTitle("упражнения", detail: "вес · повторы")
            ForEach(workout.exercises.prefix(3)) { exercise in
                let exerciseHistory = store.exerciseHistory(for: exercise.id).prefix(2)
                if !exerciseHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.title).font(.caption2.weight(.semibold)).foregroundStyle(TeenTheme.muted)
                        ForEach(Array(exerciseHistory), id: \.record.id) { item in
                            HStack(spacing: 6) {
                                Text(item.record.date.ruShort)
                                Text(item.log.sets.map { "\($0.weight)×\($0.reps)" }.joined(separator: " ")).font(.caption2).monospacedDigit()
                                Spacer()
                                Text("\(item.log.sets.count) подх.").font(.system(size: 8)).foregroundStyle(TeenTheme.muted)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(TeenTheme.raised, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
    }
    private func short(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...0))) }
}

struct PremiumStatisticsView: View {
    @Environment(Store.self) private var store
    @State private var selectedWorkout = "w1"
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    HStack { VStack(alignment: .leading, spacing: 4) { Text("статистика").font(.system(.largeTitle, design: .rounded, weight: .bold)); Text("Реальные данные за твой период").font(.subheadline).foregroundStyle(TeenTheme.muted) }; Spacer() }
                    frequency
                    comparison
                    water
                    measureChart(kind: "weight", title: "вес", tint: TeenTheme.violet)
                    measureChart(kind: "height", title: "рост", tint: TeenTheme.ice)
                }.frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 112)
            }.toolbar(.hidden, for: .navigationBar)
        }
    }
private var frequency: some View {
        HStack(spacing: 8) { CompactMetric(title: "неделя", value: "\(count(.weekOfYear))", icon: "calendar", tint: TeenTheme.lime); CompactMetric(title: "месяц", value: "\(count(.month))", icon: "calendar.badge.clock", tint: TeenTheme.violet); CompactMetric(title: "лучший день", value: bestDay ?? "—", icon: "star.fill", tint: TeenTheme.ice) }
    }
    private var comparison: some View {
        let records = Array(store.records.filter { $0.workoutID == selectedWorkout }.prefix(6).reversed())
        let workout = Catalog.workouts.first { $0.id == selectedWorkout }
        return TeenCard(accent: TeenTheme.violet) { VStack(alignment: .leading, spacing: 12) { TeenSectionTitle("прогрессия нагрузки", detail: "по упражнениям"); Picker("Тренировка", selection: $selectedWorkout) { ForEach(Catalog.workouts) { Text($0.title).tag($0.id) } }.pickerStyle(.segmented); if records.isEmpty { TeenEmpty(icon: "chart.xyaxis.line", title: "Ещё нет сравнений", detail: "После завершения тренировок здесь появятся реальные линии нагрузки.") } else { exerciseLoadChart(records: records, workout: workout) } } } }
    private func exerciseLoadChart(records: [Record], workout: Training?) -> some View {
        let exercises = workout?.exercises ?? []
        let palette: [Color] = [TeenTheme.lime, TeenTheme.ice, TeenTheme.violet, Color(red: 1.0, green: 0.6, blue: 0.2), Color(red: 0.4, green: 0.9, blue: 0.6)]
        return Chart {
            ForEach(Array(exercises.enumerated()), id: \.offset) { idx, exercise in
                ForEach(records) { record in
                    if let log = record.exercises.first(where: { $0.exerciseID == exercise.id || $0.actualID == exercise.id }),
                       log.status != "skipped" {
                        let working = log.sets.filter { !$0.skipped && !$0.weight.isEmpty && !$0.reps.isEmpty && Int($0.reps) != nil }
                        if let maxWeight = working.compactMap { Double($0.weight.replacingOccurrences(of: ",", with: ".")) }.max() {
                            LineMark(x: .value("Дата", record.date), y: .value("Вес", maxWeight))
                                .foregroundStyle(palette[idx % palette.count])
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            PointMark(x: .value("Дата", record.date), y: .value("Вес", maxWeight))
                                .foregroundStyle(palette[idx % palette.count])
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .chartXAxis {
        AxisMarks(values: .automatic(desiredCount: 4)) { value in
            if let date = value.as(Date.self) {
                AxisValueLabel {
                    Text(date.ruShort)
                }
            }
        }
    }
    .chartYAxis { AxisMarks(position: .leading) }
    .chartLegend(.visible)
}
    private var water: some View {
        let days = waterDays()
        return TeenCard(accent: TeenTheme.ice) { VStack(alignment: .leading, spacing: 12) { TeenSectionTitle("вода", detail: "7 дней"); Chart(days, id: \.day) { day in BarMark(x: .value("День", String(day.day.suffix(2))), y: .value("Мл", day.ml)).foregroundStyle(day.day == store.today ? TeenTheme.ice : TeenTheme.ice.opacity(0.35)).cornerRadius(5).annotation(position: .top) { if day.ml > 0 { Text("\(day.ml)").font(.caption2).foregroundStyle(TeenTheme.muted) } } }.frame(maxWidth: .infinity).frame(height: 170).chartYAxis { AxisMarks(position: .leading) } } }
    }
    private func measureChart(kind: String, title: String, tint: Color) -> some View {
        let values = store.measures.filter { $0.kind == kind && $0.date >= Calendar.current.date(byAdding: .month, value: -12, to: Date())! }.sorted { $0.date < $1.date }
        return TeenCard(accent: tint) { VStack(alignment: .leading, spacing: 12) { TeenSectionTitle(title, detail: "12 месяцев"); if values.isEmpty { TeenEmpty(icon: kind == "weight" ? "scalemass" : "ruler", title: "Нет измерений", detail: "Добавь \(title), чтобы увидеть настоящую динамику.") } else { Chart(values) { value in AreaMark(x: .value("Дата", value.date), y: .value("Значение", value.value)).foregroundStyle(LinearGradient(colors: [tint.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)); LineMark(x: .value("Дата", value.date), y: .value("Значение", value.value)).foregroundStyle(tint).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round)); PointMark(x: .value("Дата", value.date), y: .value("Значение", value.value)).foregroundStyle(tint) }.frame(maxWidth: .infinity).frame(height: 170).chartXAxis { AxisMarks { value in if let date = value.as(Date.self) { AxisValueLabel { Text(date.ruShort) } } } }.chartYAxis { AxisMarks(position: .leading) } } } }
    }
    private func count(_ component: Calendar.Component) -> Int { let now = Date(); let start = Calendar.current.dateInterval(of: component, for: now)?.start ?? now; return store.records.filter { $0.date >= start }.count }
    private var bestDay: String? {
        let grouped = Dictionary(grouping: store.records) { Calendar.current.startOfDay(for: $0.date) }
        let totals: [(date: Date, load: Double)] = grouped.map { date, records in
            let load = records.reduce(0.0) { partial, record in partial + Metrics.tonnage(record.exercises) }
            return (date, load)
        }
        let ranked = totals.filter { $0.load > 0 }.sorted { left, right in
            left.load == right.load ? left.date < right.date : left.load > right.load
        }
        return ranked.first?.date.formatted(date: .abbreviated, time: .omitted)
    }
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
            TeenCard(accent: TeenTheme.ice) { VStack(spacing: 2) { settingButton("Экспорт JSON", detail: "Создать полную резервную копию", icon: "square.and.arrow.up", tint: TeenTheme.ice) { shareURL = store.export(); if shareURL == nil { message = "Не удалось создать копию" } }; divider; settingButton("Импорт копии", detail: "Выбрать JSON-файл", icon: "square.and.arrow.down", tint: TeenTheme.violet) { importing = true }; divider; settingButton("Вставить копию из буфера", detail: "Импортировать скопированный JSON", icon: "doc.on.clipboard", tint: TeenTheme.lime) { importClipboard() }; divider; settingButton("Очистить все данные", detail: "История, вода и незавершённая тренировка", icon: "trash", tint: .red) { confirmClear = true } } }
            TeenSectionTitle("напоминания")
            TeenCard(accent: TeenTheme.lime) { HStack(spacing: 13) { Image(systemName: "drop.badge.clock").foregroundStyle(TeenTheme.lime).font(.title3).frame(width: 38, height: 38).background(TeenTheme.lime.opacity(0.12), in: Circle()); VStack(alignment: .leading, spacing: 4) { Text("Вода").font(.headline); Text("Каждые 2 часа · 09:00–23:00").font(.caption).foregroundStyle(TeenTheme.muted) }; Spacer(); Toggle("Вода", isOn: Binding(get: { store.reminders }, set: { store.reminders = $0; store.save(); Task { await store.schedule() } })).labelsHidden().tint(TeenTheme.lime) } }
            TeenCard(accent: TeenTheme.violet) { HStack(spacing: 13) { Image(systemName: "pills.fill").foregroundStyle(TeenTheme.violet).font(.title3).frame(width: 38, height: 38).background(TeenTheme.violet.opacity(0.12), in: Circle()); VStack(alignment: .leading, spacing: 4) { Text("Креатин").font(.headline); Text("Напоминание в \(store.creatineHour):00").font(.caption).foregroundStyle(TeenTheme.muted) }; Spacer(); Toggle("Напоминание", isOn: Binding(get: { store.creatineReminder }, set: { store.creatineReminder = $0; store.save(); Task { await store.scheduleCreatine() } })).labelsHidden().tint(TeenTheme.violet) } }
            if store.creatineReminder {
                Picker("Время", selection: Binding(get: { store.creatineHour }, set: { store.creatineHour = $0; store.save(); Task { await store.scheduleCreatine() } })) {
                    ForEach(6...22, id: \.self) { h in Text("\(h):00").tag(h) }
                }
                .pickerStyle(.wheel)
                .frame(maxHeight: 120)
                .background(TeenTheme.raised, in: RoundedRectangle(cornerRadius: 14))
                .padding(.top, 8)
            }
            TeenSectionTitle("информация")
            TeenCard { VStack(alignment: .leading, spacing: 10) { Label("Только локальное хранение", systemImage: "lock.fill").font(.headline); Text("Тренировки, измерения и резервные копии не отправляются на сервер. JSON-копия нужна, чтобы перенести или восстановить свои данные.").font(.caption).foregroundStyle(TeenTheme.muted); Link(destination: URL(string: "https://t.me/sellyou4ss")!) { Label("Telegram разработчика", systemImage: "paperplane.fill").font(.subheadline.weight(.semibold)).foregroundStyle(TeenTheme.ice) } } }
        }.frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 112) }.toolbar(.hidden, for: .navigationBar)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do { let url = try result.get(); let accessed = url.startAccessingSecurityScopedResource(); defer { if accessed { url.stopAccessingSecurityScopedResource() } }; try store.restore(Data(contentsOf: url)); message = "Копия импортирована"; Task { await store.scheduleAll() } } catch { message = "Не удалось импортировать: \(error.localizedDescription)" }
            }
            .confirmationDialog("Удалить все пользовательские данные?", isPresented: $confirmClear, titleVisibility: .visible) { Button("Удалить данные", role: .destructive) { store.clear() }; Button("Отмена", role: .cancel) { } } message: { Text("История тренировок, измерения, вода, инструкции и активная тренировка будут удалены.") }
            .sheet(item: Binding(get: { shareURL.map { ShareItem(url: $0) } }, set: { shareURL = $0?.url })) { ActivityView(url: $0.url) }
            .alert("Информация", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("ОК") { message = nil } } message: { Text(message ?? "") }
        }
    }
    private var divider: some View { Rectangle().fill(TeenTheme.line).frame(height: 1).padding(.leading, 52) }
    private func importClipboard() {
        guard let text = UIPasteboard.general.string, let data = text.data(using: .utf8) else {
            message = "В буфере обмена нет JSON-текста резервной копии"
            return
        }
        do {
            try store.restore(data)
            message = "Копия импортирована из буфера обмена"
            Task { await store.schedule() }
        } catch {
            message = "Не удалось импортировать: \(error.localizedDescription)"
        }
    }
    private func settingButton(_ title: String, detail: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View { Button(action: action) { HStack(spacing: 13) { Image(systemName: icon).foregroundStyle(tint).frame(width: 38, height: 38).background(tint.opacity(0.13), in: Circle()); VStack(alignment: .leading, spacing: 3) { Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white); Text(detail).font(.caption).foregroundStyle(TeenTheme.muted) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(TeenTheme.muted) }.padding(.vertical, 5) }.buttonStyle(TeenPressStyle()) }
}
