import SwiftUI
import Charts
import UniformTypeIdentifiers
import UIKit
import Foundation

struct PremiumRootView: View {
    @Environment(Store.self) private var store
    @State private var selection = 0
    @State private var aiInsightsCoordinator = AIInsightsCoordinator()
    @State private var aiConsentStore = AIConsentStore()
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
        .environment(aiInsightsCoordinator)
        .environment(aiConsentStore)
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
    @State private var selectedWorkoutIndex = 0
    @GestureState private var dragOffset: CGFloat = 0
    private let swipeThreshold: CGFloat = 80
    private var waterProgress: Double { Double(store.todayML) / 3000 }
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    header
                    HStack(spacing: 12) { measureCard("Вес", unit: "кг", kind: "weight", icon: "scalemass.fill", tint: TeenTheme.violet); measureCard("Рост", unit: "см", kind: "height", icon: "ruler.fill", tint: TeenTheme.ice) }
                    workoutCarousel
                    waterCard
                    creatineCard
                }
                .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 112)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showMeasure) { measureSheet }
        }
    }
    private var workoutCarousel: some View {
        VStack(spacing: 10) {
            HStack {
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if selectedWorkoutIndex > 0 { selectedWorkoutIndex -= 1 }
                } } label: {
                    Image(systemName: "arrow.left")
                        .font(.title3)
                        .foregroundStyle(selectedWorkoutIndex == 0 ? TeenTheme.muted : TeenTheme.lime)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Предыдущая тренировка")
                Spacer()
                workoutCard(Catalog.workouts[selectedWorkoutIndex], isSelected: true)
                    .offset(x: dragOffset)
                    .gesture(workoutSwipeGesture)
                Spacer()
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if selectedWorkoutIndex < Catalog.workouts.count - 1 { selectedWorkoutIndex += 1 }
                } } label: {
                    Image(systemName: "arrow.right")
                        .font(.title3)
                        .foregroundStyle(selectedWorkoutIndex == Catalog.workouts.count - 1 ? TeenTheme.muted : TeenTheme.lime)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Следующая тренировка")
            }
            HStack(spacing: 6) {
                ForEach(Catalog.workouts.indices, id: \.self) { i in
                    Capsule().fill(i == selectedWorkoutIndex ? TeenTheme.violet : TeenTheme.line).frame(width: i == selectedWorkoutIndex ? 22 : 8, height: 6)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedWorkoutIndex)
                }
            }
        }
    }
    private var workoutSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .updating($dragOffset) { value, state, _ in
                if abs(value.translation.width) > abs(value.translation.height) && abs(value.translation.width) > 10 {
                    state = value.translation.width * 0.5
                }
            }
            .onEnded { value in
                let t = value.translation.width
                guard abs(t) > abs(value.translation.height) else { return }
                if t < 0 && selectedWorkoutIndex < Catalog.workouts.count - 1 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedWorkoutIndex += 1 }
                } else if t > 0 && selectedWorkoutIndex > 0 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedWorkoutIndex -= 1 }
                }
            }
    }
    private var header: some View {
        HStack(alignment: .bottom) {
            Text("teenage").font(.system(size: 34, weight: .bold, design: .rounded))
            Spacer()
        }
    }
    private func latest(_ kind: String) -> Measure? { store.measures.filter { $0.kind == kind }.max { $0.date < $1.date } }
    private func measureCard(_ title: String, unit: String, kind: String, icon: String, tint: Color) -> some View {
        Button { self.kind = kind; value = ""; showMeasure = true } label: {
            TeenCard {
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
    private func workoutCard(_ workout: Training, isSelected: Bool = false) -> some View {
        let active = store.hasRealActiveWorkout && store.session?.workoutID == workout.id
        return NavigationLink { PremiumWorkoutView(workout: workout) } label: {
            TeenCard {
                HStack(spacing: 14) {
                    Text(workout.id.replacingOccurrences(of: "w", with: "0")).font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(active ? TeenTheme.lime : (isSelected ? TeenTheme.violet : .white)).frame(width: 42, height: 42).background((active ? TeenTheme.lime : (isSelected ? TeenTheme.violet : .white)).opacity(0.13), in: Circle())
                    Text(workout.title).font(.headline)
                    Spacer(); Image(systemName: active ? "arrow.clockwise" : "arrow.up.right").font(.headline).foregroundStyle(active ? TeenTheme.lime : .white)
                }
            }
        }.buttonStyle(TeenPressStyle())
    }
    private var waterCard: some View {
        TeenCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(TeenTheme.raised, lineWidth: 10)
                    Circle().trim(from: 0, to: waterProgress).stroke(TeenTheme.ice, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90)).animation(.easeInOut(duration: 0.35), value: waterProgress)
                    VStack(spacing: 1) {
                        Text("\(store.todayML)").font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
                        Text("мл").font(.caption2).foregroundStyle(TeenTheme.muted)
                    }
                }.frame(width: 80, height: 80)
                Spacer()
                Button { store.addWater() } label: { Label("+ 200 мл", systemImage: "drop.fill").font(.subheadline.weight(.bold)).foregroundStyle(TeenTheme.ink).padding(.horizontal, 16).padding(.vertical, 10).background(TeenTheme.ice, in: Capsule()) }.disabled(store.todayML >= 3000).buttonStyle(TeenPressStyle())
            }
        }
    }
    private var creatineCard: some View {
        TeenCard {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(TeenTheme.ice, lineWidth: 2)
                    Image(systemName: store.todayCreatine ? "checkmark.circle.fill" : "drop.circle.fill")
                        .foregroundStyle(store.todayCreatine ? TeenTheme.ice : TeenTheme.muted)
                        .font(.title3)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Креатин").font(.subheadline.weight(.semibold))
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        store.creatineToggle()
                    }
                } label: {
                    Image(systemName: store.todayCreatine ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(store.todayCreatine ? TeenTheme.ice : TeenTheme.muted)
                        .font(.title2)
                }
                .buttonStyle(TeenPressStyle())
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
    @State private var showRecovery = false
    var body: some View {
        let session = store.current(workout)
        ScrollView { VStack(spacing: 14) {
            TeenCard { HStack { VStack(alignment: .leading, spacing: 5) { Text(workout.title).font(.title2.bold()); Text("\(session.exercises.filter { $0.status == "completed" }.count) из \(session.exercises.count) упражнений").foregroundStyle(TeenTheme.muted).font(.caption) }; Spacer(); ZStack { Circle().stroke(TeenTheme.raised, lineWidth: 6); Circle().trim(from: 0, to: Double(session.exercises.filter { $0.status == "completed" || $0.status == "skipped" }.count) / Double(session.exercises.count)).stroke(TeenTheme.ice, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90)); Text("\(session.current + 1)").font(.headline) }.frame(width: 50, height: 50) } }
            if session.exercises.contains(where: { $0.status == "skipped" }) {
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
    private func exerciseRow(_ entry: ExerciseLog, index: Int) -> some View { TeenCard { HStack(spacing: 13) { Image(uiImage: exerciseUIImage(Catalog.e(entry.actualID).image)).resizable().scaledToFill().frame(width: 54, height: 54).clipShape(Circle()); VStack(alignment: .leading, spacing: 4) { Text(Catalog.e(entry.actualID).title).font(.subheadline.weight(.semibold)); Text(entry.status == "skipped" ? "Пропущено" : "Упражнение \(index + 1)").font(.caption).foregroundStyle(entry.status == "skipped" ? .red : TeenTheme.muted) }; Spacer(); Image(systemName: entry.status == "completed" ? "checkmark.circle.fill" : "chevron.right").foregroundStyle(entry.status == "completed" ? TeenTheme.ice : TeenTheme.muted) } } }
}

struct PremiumExerciseView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let workout: Training
    let index: Int
    @State private var replace = false
    @State private var dragOffset: CGFloat = 0
    @State private var showingSkipUndo = false
    @State private var isExpandedNotes = false
    @State private var isExpandedHistory = true
    private let skipThreshold: CGFloat = -80
    private let minimumDrag: CGFloat = 55
    var body: some View {
        let session = store.current(workout); let entry = session.exercises[index]; let exercise = Catalog.e(entry.actualID)
        ScrollView { VStack(spacing: 16) { hero(exercise, session: session); setCard(entry); actionRow(entry); history(entry); notes(entry); Button(index + 1 < session.exercises.count ? "Сохранить и далее" : "К списку") { advance(session) }.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15).foregroundStyle(TeenTheme.ink).background(TeenTheme.lime, in: Capsule()).buttonStyle(TeenPressStyle()); Button(entry.status == "skipped" ? "Вернуть упражнение" : "Пропустить упражнение") { if entry.status == "skipped" { recover() } else { skip() } }.font(.caption.weight(.medium)).foregroundStyle(entry.status == "skipped" ? TeenTheme.lime : .red) }.padding(20).padding(.bottom, 120) }
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
    private func hero(_ exercise: Exercise, session: Session) -> some View { TeenCard { VStack(spacing: 12) { ZStack { Circle().stroke(TeenTheme.raised, lineWidth: 6); Circle().trim(from: 0, to: Double(index + 1) / Double(session.exercises.count)).stroke(TeenTheme.ice, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90)); Image(uiImage: exerciseUIImage(exercise.image)).resizable().scaledToFill().frame(width: 92, height: 92).clipShape(Circle()) }.frame(width: 108, height: 108); Text(exercise.title.uppercased()).font(.headline).multilineTextAlignment(.center); Text("Тренировка · упражнение \(index + 1)").font(.caption).foregroundStyle(TeenTheme.muted) } .frame(maxWidth: .infinity) } }
    private func setCard(_ entry: ExerciseLog) -> some View { TeenCard { VStack(alignment: .leading, spacing: 12) { TeenSectionTitle("подходы", detail: "вес · повторы"); ForEach(entry.sets.indices, id: \.self) { row in setRow(entry.sets[row], row: row, totalCount: entry.sets.count) }; HStack { Button { store.mutate { $0.exercises[index].sets.append(SetLog()) } } label: { Label("Подход", systemImage: "plus").font(.subheadline.weight(.bold)).foregroundStyle(TeenTheme.lime) }; Spacer(); if entry.sets.count > 2 { Button("Удалить") { store.mutate { $0.exercises[index].sets.removeLast() } }.foregroundStyle(.red).font(.caption) } } } } }
    private func setRow(_ set: SetLog, row: Int, totalCount: Int) -> some View {
        return HStack(spacing: 8) {
            Text("\(row + 1)").font(.caption.weight(.bold)).frame(width: 30, height: 30).background(set.skipped ? Color.red.opacity(0.16) : TeenTheme.lime.opacity(0.12), in: Circle()).foregroundStyle(set.skipped ? .red : TeenTheme.lime)
            TextField("кг", text: Binding(get: { set.weight }, set: { value in store.mutate { s in s.exercises[index].sets[row].weight = value } })).keyboardType(.decimalPad).multilineTextAlignment(.center).padding(10).background(TeenTheme.raised, in: Capsule()).contentShape(Rectangle())
            TextField("раз", text: Binding(get: { set.reps }, set: { value in store.mutate { $0.exercises[index].sets[row].reps = value } })).keyboardType(.numberPad).multilineTextAlignment(.center).padding(10).background(TeenTheme.raised, in: Capsule()).contentShape(Rectangle())
            if totalCount > 1 {
                Button { store.mutate { $0.exercises[index].sets.remove(at: row) } } label: {
                    Image(systemName: "minus.circle.fill").font(.caption.weight(.bold)).frame(width: 34, height: 34).foregroundStyle(.red).background(Color.red.opacity(0.14), in: Circle())
                }.buttonStyle(PlainButtonStyle())
            } else if set.skipped {
                Button { store.mutate { $0.exercises[index].sets[row].skipped.toggle() } } label: {
                    Image(systemName: set.skipped ? "xmark" : "checkmark").font(.caption.weight(.bold)).frame(width: 34, height: 34).foregroundStyle(set.skipped ? .red : TeenTheme.lime).background((set.skipped ? Color.red : TeenTheme.lime).opacity(0.14), in: Circle())
                }.buttonStyle(PlainButtonStyle())
            }
        }
    }
    private func actionRow(_ entry: ExerciseLog) -> some View { HStack(spacing: 10) { Button { replace = true } label: { action("Заменить", icon: "arrow.triangle.2.circlepath") }; NavigationLink { PremiumHistoryView(exerciseID: entry.exerciseID) } label: { action("История", icon: "clock.arrow.circlepath") } } }
    private func action(_ text: String, icon: String) -> some View { VStack(spacing: 6) { Image(systemName: icon); Text(text).font(.caption2.weight(.semibold)) }.foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 12).background(TeenTheme.surface, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(TeenTheme.line)) }
    private func notes(_ entry: ExerciseLog) -> some View {
        return TeenCard { VStack(alignment: .leading, spacing: 4) {
            Button {
                isExpandedNotes.toggle()
            } label: {
                HStack {
                    Text("Техника выполнения").font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: isExpandedNotes ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(TeenTheme.muted)
                }
            }
            if isExpandedNotes {
                TextEditor(text: Binding(get: { store.instructions[entry.exerciseID] ?? TechniqueGuide.instruction(for: entry.exerciseID) }, set: { store.instructions[entry.exerciseID] = $0; store.save() })).scrollContentBackground(.hidden).frame(minHeight: 100).padding(6).background(TeenTheme.raised, in: RoundedRectangle(cornerRadius: 10))
                Text("Подсказка для безопасного выполнения. Выбирай комфортный вес и диапазон движения.").font(.caption2).foregroundStyle(TeenTheme.muted)
            }
        } }
    }
    private func history(_ entry: ExerciseLog) -> some View {
        let latest = store.exerciseHistory(for: entry.exerciseID).first
        return TeenCard {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    isExpandedHistory.toggle()
                } label: {
                    HStack {
                        Text("Предыдущая тренировка").font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: isExpandedHistory ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(TeenTheme.muted)
                    }
                }
                if isExpandedHistory {
                    if let latest {
                        ForEach(Array(latest.log.sets.enumerated()), id: \.offset) { i, set in
                            HStack(spacing: 6) {
                                Text("подход \(i + 1)").font(.system(size: 9, weight: .bold)).foregroundStyle(TeenTheme.muted)
                                Spacer()
                                Text("\(set.weight) кг").font(.caption.weight(.semibold)).monospacedDigit()
                                Text("\(set.reps) повт.").font(.caption.weight(.semibold)).monospacedDigit()
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(TeenTheme.raised, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                } else {
                    Text("Показать подходы").font(.caption2).foregroundStyle(TeenTheme.muted)
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
    var body: some View {
        NavigationStack { ScrollView(showsIndicators: false) { VStack(spacing: 16) {
            header
            if store.records.isEmpty {
                TeenCard { TeenEmpty(icon: "list.bullet.rectangle", title: "Пока нет тренировок", detail: "Заверши тренировку — она появится здесь с полным списком подходов.") }
            } else {
                ForEach(store.records) { record in
                    NavigationLink { PremiumWorkoutDetailScreen(record: record) } label: { workoutHistoryCard(record) }.buttonStyle(TeenPressStyle())
                }
            }
        }.frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 112) }.toolbar(.hidden, for: .navigationBar) }
    }
    private var header: some View { Text("прогресс").font(.system(.largeTitle, design: .rounded, weight: .bold)).multilineTextAlignment(.center) }
    private func workoutHistoryCard(_ record: Record) -> some View {
        let nonSkippedExercises = record.exercises.filter { $0.status != "skipped" }
        _ = nonSkippedExercises.filter { exercise in
            exercise.sets.contains { !$0.skipped && !$0.weight.isEmpty && !$0.reps.isEmpty }
        }
        _ = record.exercises.filter { $0.status == "skipped" }
        return TeenCard { HStack(spacing: 14) {
            Image(systemName: "figure.strengthtraining.traditional").font(.title2).foregroundStyle(TeenTheme.violet).frame(width: 48, height: 48).background(TeenTheme.violet.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(record.name).font(.headline)
                Text(record.date.ruLong).font(.caption).foregroundStyle(TeenTheme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(TeenTheme.muted)
        } }
    }
}

struct PremiumWorkoutDetailScreen: View {
    @Environment(Store.self) private var store
    let record: Record
    @State private var showingDeleteConfirmation = false
    var body: some View {
        ScrollView(showsIndicators: false) { VStack(spacing: 16) {
            headerCard
            TeenSectionTitle("выполненные упражнения")
            if completedExercises.isEmpty { TeenCard { TeenEmpty(icon: "dumbbell", title: "Упражнений не было", detail: "В этой тренировке все упражнения были пропущены.") } }
            ForEach(completedExercises) { log in exerciseDetail(log) }
            if !skipped.isEmpty {
                TeenSectionTitle("пропущенные упражнения")
                ForEach(skipped) { log in skippedCard(log) }
            }
            TeenSectionTitle("действия")
            HStack(spacing: 12) {
                Button("Удалить тренировку") { showingDeleteConfirmation = true }.foregroundStyle(.red).font(.headline)
                Spacer()
            }
            .confirmationDialog("Удалить тренировку", isPresented: $showingDeleteConfirmation) {
                Button("Удалить", role: .destructive) { deleteRecord() }
                Button("Отмена", role: .cancel) { }
            } message: { Text("Тренировка будет безвозвратно удалена из истории.") }
        }.padding(20).padding(.bottom, 112) }.background(TeenTheme.ink).navigationTitle(record.name).navigationBarTitleDisplayMode(.inline)
    }
    private func deleteRecord() {
        store.records.removeAll { $0.id == record.id }
        store.save()
    }
    private var completedExercises: [ExerciseLog] {
        record.exercises.filter { exercise in
            exercise.status != "skipped" &&
            exercise.sets.contains { !$0.skipped && !$0.weight.isEmpty && !$0.reps.isEmpty }
        }
    }
    private var skipped: [ExerciseLog] { record.exercises.filter { $0.status == "skipped" } }
    private var totalSets: Int { completedExercises.reduce(0) { $0 + $1.sets.filter { !$0.skipped && !$0.weight.isEmpty && !$0.reps.isEmpty }.count } }
    private var headerCard: some View {
        TeenCard { VStack(alignment: .leading, spacing: 6) {
            Text(record.name).font(.title2.bold())
            Text(record.date.ruLong).font(.subheadline).foregroundStyle(TeenTheme.muted)
        } }
    }
    private func exerciseDetail(_ log: ExerciseLog) -> some View {
        let working = log.sets.enumerated().filter { !$0.element.skipped }
        return TeenCard { VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(uiImage: exerciseUIImage(Catalog.e(log.actualID).image)).resizable().scaledToFill().frame(width: 40, height: 40).clipShape(Circle())
                Text(Catalog.e(log.actualID).title).font(.headline)
            }
            ForEach(working, id: \.offset) { i, set in
                HStack(spacing: 8) {
                    Text("\(i + 1)").font(.caption.weight(.bold)).frame(width: 26, height: 26).background(TeenTheme.lime.opacity(0.12), in: Circle()).foregroundStyle(TeenTheme.lime)
                    Text("\(set.weight) кг").font(.subheadline.weight(.semibold)).monospacedDigit()
                    Spacer()
                    Text("\(set.reps) повторений").font(.caption).foregroundStyle(TeenTheme.muted)
                }
                .padding(6).background(TeenTheme.raised, in: RoundedRectangle(cornerRadius: 10))
            }
        } }
    }
    private func skippedCard(_ log: ExerciseLog) -> some View {
        TeenCard { HStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 3) {
                Text(Catalog.e(log.actualID).title).font(.subheadline.weight(.semibold))
                Text("Пропущено в этой тренировке").font(.caption).foregroundStyle(TeenTheme.muted)
            }
            Spacer()
        } }
    }
}

struct PremiumStatisticsView: View {
    @Environment(Store.self) private var store
    @State private var selectedExercise: Exercise?
    @State private var selectedMetric: MetricType = .weight
    @State private var showExerciseSheet = false
    @State private var searchQuery = ""
    enum MetricType: String, CaseIterable { case weight = "Вес", tonnage = "Тоннаж", sets = "Подходы" }
    var body: some View {
        NavigationStack { ScrollView(showsIndicators: false) { VStack(spacing: 16) {
            header
            AIInsightsSection()
            exerciseSelector
            if let ex = selectedExercise {
                metricPicker
                if hasData(for: ex) { chartSection(for: ex) } else { noDataSection() }
                summaryCards(for: ex)
            } else {
                TeenCard { TeenEmpty(icon: "dumbbell", title: "Выбери упражнение", detail: "Здесь появится график прогрессии веса, тоннажа и подходов.") }
            }
            waterSection
            measureChart(kind: "weight", title: "вес", tint: TeenTheme.violet)
            measureChart(kind: "height", title: "рост", tint: TeenTheme.ice)
        }.frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 112) }.toolbar(.hidden, for: .navigationBar) }
    }
    private var header: some View { Text("статистика").font(.system(.largeTitle, design: .rounded, weight: .bold)).multilineTextAlignment(.center) }
    private var exerciseSelector: some View {
        let currentTitle = selectedExercise.map { $0.title } ?? "Все упражнения"
        return TeenCard { VStack(alignment: .leading, spacing: 10) {
            TeenSectionTitle("упражнение")
            Button {
                showExerciseSheet = true
            } label: {
                HStack {
                    Text(currentTitle).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption).foregroundStyle(TeenTheme.muted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(TeenTheme.ink.opacity(0.5), in: Capsule())
            }.buttonStyle(TeenPressStyle())
        } }
        .sheet(isPresented: $showExerciseSheet) {
            exerciseSelectionSheet
        }
    }
    private var exerciseSelectionSheet: some View {
        NavigationStack {
            List {
                allExercisesSection
                exercisesListSection
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Упражнение")
            .searchable(text: $searchQuery, prompt: "Найти упражнение")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { showExerciseSheet = false } } }
        }
    }
    
    private var allExercisesSection: some View {
        Section("Все упражнения") {
            Button { selectedExercise = nil; showExerciseSheet = false } label: {
                HStack {
                    Text("Все упражнения").foregroundStyle(.primary)
                    Spacer()
                    if selectedExercise == nil { Image(systemName: "checkmark").foregroundStyle(TeenTheme.lime) }
                }
            }
        }
    }
    
    private var exercisesListSection: some View {
        Section {
            ForEach(Catalog.all.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) }) { ex in
                Button { selectedExercise = ex; showExerciseSheet = false } label: {
                    HStack {
                        Text(ex.title).foregroundStyle(.primary)
                        Spacer()
                        if selectedExercise?.id == ex.id { Image(systemName: "checkmark").foregroundStyle(TeenTheme.lime) }
                    }
                }
            }
        }
    }
    
    private var metricPicker: some View {
        Picker("Показатель", selection: $selectedMetric) {
            ForEach(MetricType.allCases, id: \.self) { m in Text(m.rawValue).tag(m) }
        }.pickerStyle(.segmented)
    }
    private func hasData(for exercise: Exercise) -> Bool {
        store.exerciseHistory(for: exercise.id).count > 1
    }
    private func noDataSection() -> some View {
        TeenCard { TeenEmpty(icon: "chart.line.flattrend.xyaxis", title: "Мало данных", detail: "Нужно минимум 2 тренировки с этим упражнением для построения графика.") }
    }
    private func chartSection(for exercise: Exercise) -> some View {
        let history = store.exerciseHistory(for: exercise.id)
        return TeenCard { VStack(alignment: .leading, spacing: 12) {
            TeenSectionTitle("прогрессия", detail: selectedMetric.rawValue.lowercased())
            if history.isEmpty {
                Text("Нет выполнений").font(.caption).foregroundStyle(TeenTheme.muted)
            } else {
                Chart {
                    ForEach(history, id: \.record.id) { item in
                        let y = metricValue(for: item.log, type: selectedMetric)
                        LineMark(x: .value("Дата", item.record.date), y: .value(selectedMetric.rawValue, y))
                            .foregroundStyle(TeenTheme.violet).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        PointMark(x: .value("Дата", item.record.date), y: .value(selectedMetric.rawValue, y))
                            .foregroundStyle(TeenTheme.lime)
                    }
                }
                .frame(height: 180)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        if let date = value.as(Date.self) { AxisValueLabel { Text(date.ruShort) } }
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
            }
        } }
    }
    private func metricValue(for log: ExerciseLog, type: MetricType) -> Double {
        let working = log.sets.filter { !$0.skipped && !$0.weight.isEmpty && !$0.reps.isEmpty && Int($0.reps) != nil }
        switch type {
        case .weight:
            return working.compactMap { Double($0.weight.replacingOccurrences(of: ",", with: ".")) }.max() ?? 0
        case .tonnage:
            return working.reduce(0) { $0 + (Double($1.weight.replacingOccurrences(of: ",", with: ".")) ?? 0) * (Double($1.reps) ?? 0) }
        case .sets:
            return Double(working.count)
        }
    }
    private func summaryCards(for exercise: Exercise) -> some View {
        let history = store.exerciseHistory(for: exercise.id)
        let latestWeight = history.first.map { metricValue(for: $0.log, type: .weight) }
        let bestTonnage = history.map { metricValue(for: $0.log, type: .tonnage) }.max()
        return HStack(spacing: 8) {
            CompactMetric(title: "последний вес", value: latestWeight.map { "\($0.formatted(.number.precision(.fractionLength(0...0)))) кг" } ?? "—", icon: "dumbbell", tint: TeenTheme.lime)
            CompactMetric(title: "лучший тоннаж", value: bestTonnage.map { "\($0.formatted(.number.precision(.fractionLength(0...0)))) кг·повт." } ?? "—", icon: "trophy", tint: TeenTheme.violet)
        }
    }
    private func waterDays() -> [WaterDay] {
        (0..<7).compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .day, value: offset - 6, to: Date()) else { return nil }
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = .current
            let day = formatter.string(from: date)
            return store.water.first { $0.day == day } ?? WaterDay(day: day, ml: 0)
        }
    }
    private var waterSection: some View {
        let days = waterDays()
        return TeenCard { VStack(alignment: .leading, spacing: 12) { TeenSectionTitle("вода", detail: "7 дней"); Chart(days, id: \.day) { day in BarMark(x: .value("День", String(day.day.suffix(2))), y: .value("Мл", day.ml)).foregroundStyle(day.day == store.today ? TeenTheme.ice : TeenTheme.ice.opacity(0.35)).cornerRadius(5).annotation(position: .top) { if day.ml > 0 { Text("\(day.ml)").font(.caption2).foregroundStyle(TeenTheme.muted) } } }.frame(maxWidth: .infinity).frame(height: 170).chartYAxis { AxisMarks(position: .leading) } } }
    }
    private func measureChart(kind: String, title: String, tint: Color) -> some View {
        let values = store.measures.filter { $0.kind == kind && $0.date >= Calendar.current.date(byAdding: .month, value: -12, to: Date())! }.sorted { $0.date < $1.date }
        return TeenCard { VStack(alignment: .leading, spacing: 12) { TeenSectionTitle(title, detail: "12 месяцев"); if values.isEmpty { TeenEmpty(icon: kind == "weight" ? "scalemass" : "ruler", title: "Нет измерений", detail: "Добавь \(title), чтобы увидеть настоящую динамику.") } else { Chart(values) { value in AreaMark(x: .value("Дата", value.date), y: .value("Значение", value.value)).foregroundStyle(LinearGradient(colors: [tint.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)); LineMark(x: .value("Дата", value.date), y: .value("Значение", value.value)).foregroundStyle(tint).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round)); PointMark(x: .value("Дата", value.date), y: .value("Значение", value.value)).foregroundStyle(tint) }.frame(maxWidth: .infinity).frame(height: 170).chartXAxis { AxisMarks { value in if let date = value.as(Date.self) { AxisValueLabel { Text(date.ruShort) } } } }.chartYAxis { AxisMarks(position: .leading) } } } }
    }
}

struct PremiumSettingsView: View {
    private enum AIKeyAvailability: Equatable {
        case missing
        case present
        case unknown
    }
    private enum AIKeyMutation: Equatable {
        case overwrite
        case delete
    }
    @Environment(Store.self) private var store
    @Environment(AIConsentStore.self) private var aiConsentStore
    @AppStorage("aiCoachEnabled") private var aiCoachEnabled = false
    @State private var aiKeyStore: any AIKeyStore = AIKeychainStore()
    @State private var aiKeyInput = ""
    @State private var aiKeyAvailability: AIKeyAvailability = .unknown
    @State private var aiKeyStatus = "Проверка локального состояния не выполнена"
    @State private var aiKeyStatusIsError = false
    @State private var pendingAIKeyMutation: AIKeyMutation?
    @State private var importing = false
    @State private var shareURL: URL?
    @State private var confirmClear = false
    @State private var message: String?
    @State private var presentsAIConsent = false
    @State private var isAISettingsExpanded = true
    @State private var customModel = ""
    private var providerBinding: Binding<AIProvider> {
        Binding(get: { AIConfiguration.currentProvider },
                set: { AIConfiguration.currentProvider = $0 })
    }
    var body: some View {
        NavigationStack { ScrollView(showsIndicators: false) { VStack(spacing: 16) {
            HStack { VStack(alignment: .leading, spacing: 4) { Text("настройки").font(.system(.largeTitle, design: .rounded, weight: .bold)); Text("Данные остаются на устройстве").font(.subheadline).foregroundStyle(TeenTheme.muted) }; Spacer() }
            Button {
                withAnimation { isAISettingsExpanded.toggle() }
            } label: {
                HStack {
                    TeenSectionTitle("Teenage Coach")
                    Spacer()
                    Image(systemName: isAISettingsExpanded ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(TeenTheme.muted)
                }
            }.buttonStyle(TeenPressStyle())
            if isAISettingsExpanded { aiSettingsCard }
            TeenSectionTitle("данные")
            TeenCard { VStack(spacing: 2) { settingButton("Экспорт JSON", detail: "Создать полную резервную копию", icon: "square.and.arrow.up", tint: TeenTheme.ice) { shareURL = store.export(); if shareURL == nil { message = "Не удалось создать копию" } }; divider; settingButton("Импорт копии", detail: "Выбрать JSON-файл", icon: "square.and.arrow.down", tint: TeenTheme.violet) { importing = true }; divider; settingButton("Вставить копию из буфера", detail: "Импортировать скопированный JSON", icon: "doc.on.clipboard", tint: TeenTheme.lime) { importClipboard() }; divider; settingButton("Очистить все данные", detail: "История, вода и незавершённая тренировка", icon: "trash", tint: .red) { confirmClear = true } } }
            TeenSectionTitle("напоминания")
            TeenCard { HStack(spacing: 13) { Image(systemName: "drop.badge.clock").foregroundStyle(TeenTheme.ice).font(.title3).frame(width: 38, height: 38).background(TeenTheme.ice.opacity(0.12), in: Circle()); VStack(alignment: .leading, spacing: 4) { Text("Вода").font(.headline); Text("Каждые 2 часа · 09:00–23:00").font(.caption).foregroundStyle(TeenTheme.muted) }; Spacer(); Toggle("Вода", isOn: Binding(get: { store.reminders }, set: { store.reminders = $0; store.save(); Task { await store.schedule() } })).labelsHidden().tint(TeenTheme.ice) } }
            TeenCard { HStack(spacing: 13) { Image(systemName: "pills.fill").foregroundStyle(TeenTheme.violet).font(.title3).frame(width: 38, height: 38).background(TeenTheme.violet.opacity(0.12), in: Circle()); VStack(alignment: .leading, spacing: 4) { Text("Креатин").font(.headline); Text("Напоминание в \(store.creatineHour):00").font(.caption).foregroundStyle(TeenTheme.muted) }; Spacer(); Toggle("Напоминание", isOn: Binding(get: { store.creatineReminder }, set: { store.creatineReminder = $0; store.save(); Task { await store.scheduleCreatine() } })).labelsHidden().tint(TeenTheme.violet) } }
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
            TeenCard { VStack(spacing: 8) { Text("GymForTeenage").font(.headline).multilineTextAlignment(.center); Text("Версия 1.0").font(.subheadline).foregroundStyle(TeenTheme.muted).multilineTextAlignment(.center); Divider().padding(.vertical, 4); Text("Данные приложения остаются на устройстве. Выбранный контекст Teenage Coach отправляется только после отдельного согласия.").font(.caption).foregroundStyle(TeenTheme.muted).multilineTextAlignment(.center); Link(destination: URL(string: "https://t.me/sellyou4ss")!) { Label("Telegram разработчика", systemImage: "paperplane.fill").font(.subheadline.weight(.semibold)).foregroundStyle(TeenTheme.ice).multilineTextAlignment(.center) } } }
        }.frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 112) }.toolbar(.hidden, for: .navigationBar)
            .task { refreshAIKeyStatus() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do { let url = try result.get(); let accessed = url.startAccessingSecurityScopedResource(); defer { if accessed { url.stopAccessingSecurityScopedResource() } }; try store.restore(Data(contentsOf: url)); message = "Копия импортирована"; Task { await store.scheduleAll() } } catch { message = "Не удалось импортировать: \(error.localizedDescription)" }
            }
            .confirmationDialog("Удалить все пользовательские данные?", isPresented: $confirmClear, titleVisibility: .visible) { Button("Удалить данные", role: .destructive) { store.clear() }; Button("Отмена", role: .cancel) { } } message: { Text("История тренировок, измерения, вода, инструкции и активная тренировка будут удалены.") }
            .sheet(item: Binding(get: { shareURL.map { ShareItem(url: $0) } }, set: { shareURL = $0?.url })) { ActivityView(url: $0.url) }
            .alert("Информация", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("ОК") { message = nil } } message: { Text(message ?? "") }
            .sheet(isPresented: $presentsAIConsent) {
                AIConsentSheet(requiredCategories: [], initialCategories: aiConsentStore.consentedCategories)
                    .environment(aiConsentStore)
            }
        }
    }
    private var aiSettingsCard: some View {
        TeenCard {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Включить Teenage Coach", isOn: $aiCoachEnabled).tint(TeenTheme.violet)
                Button("Изменить категории") { presentsAIConsent = true }
                    .font(.caption.weight(.semibold)).foregroundStyle(TeenTheme.lime)
                
                Picker("Провайдер", selection: providerBinding) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Text(provider.name).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                
                if providerBinding.wrappedValue == .openRouter {
                    TextField("Модель (например, openrouter/free)", text: $customModel)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(TeenTheme.raised, in: RoundedRectangle(cornerRadius: 12))
                }
                
                SecureField(aiKeyAvailability == .present ? "Новый ключ для замены" : "API-ключ", text: $aiKeyInput)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(TeenTheme.raised, in: RoundedRectangle(cornerRadius: 12))
                if aiKeyAvailability == .unknown {
                    Text("Неизвестно, сохранён ли ключ. Повторите проверку или подтвердите действие с предупреждением.")
                        .font(.caption).foregroundStyle(TeenTheme.muted)
                    HStack {
                        Button("Перезаписать…") { pendingAIKeyMutation = .overwrite }
                            .buttonStyle(.borderedProminent).tint(TeenTheme.violet)
                            .disabled(aiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Удалить ключ…", role: .destructive) { pendingAIKeyMutation = .delete }
                    }
                } else {
                    HStack {
                        Button(aiKeyAvailability == .present ? "Заменить ключ" : "Сохранить ключ") { saveAIKey() }
                            .buttonStyle(.borderedProminent).tint(TeenTheme.violet)
                            .disabled(aiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if aiKeyAvailability == .present {
                            Button("Удалить", role: .destructive) { pendingAIKeyMutation = .delete }
                        }
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: aiKeyStatusIsError ? "exclamationmark.circle.fill" : (aiKeyAvailability == .present ? "checkmark.circle.fill" : (aiKeyAvailability == .missing ? "key.slash" : "questionmark.circle.fill")))
                        .foregroundStyle(aiKeyStatusIsError ? .red : (aiKeyAvailability == .present ? TeenTheme.lime : TeenTheme.muted))
                    Text(aiKeyStatus).font(.caption).foregroundStyle(aiKeyStatusIsError ? .red : TeenTheme.muted)
                    Spacer()
                }
            }
        }
        .confirmationDialog(
            pendingAIKeyMutation == .overwrite ? "Перезаписать API-ключ?" : "Удалить API-ключ?",
            isPresented: Binding(get: { pendingAIKeyMutation != nil }, set: { if !$0 { pendingAIKeyMutation = nil } }),
            titleVisibility: .visible
        ) {
            if pendingAIKeyMutation == .overwrite {
                Button("Перезаписать ключ", role: .destructive) { saveAIKey() }
                    .disabled(aiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else if pendingAIKeyMutation == .delete {
                Button("Удалить ключ", role: .destructive) { deleteAIKey() }
            }
            Button("Отмена", role: .cancel) { pendingAIKeyMutation = nil }
        } message: {
            Text("Состояние Keychain неизвестно из-за ошибки. Перезапись заменит возможный сохранённый ключ; удаление безвозвратно удалит его, если он существует.")
        }
    }
    private func refreshAIKeyStatus() {
        do {
            aiKeyAvailability = try aiKeyStore.containsKey() ? .present : .missing
            aiKeyStatus = aiKeyAvailability == .present ? "API-ключ сохранён в Keychain" : "API-ключ отсутствует"
            aiKeyStatusIsError = false
        } catch {
            aiKeyAvailability = .unknown
            aiKeyStatus = errorMessage(for: error)
            aiKeyStatusIsError = true
        }
    }
    private func saveAIKey() {
        do {
            try aiKeyStore.save(key: aiKeyInput)
            aiKeyInput = ""
            pendingAIKeyMutation = nil
            refreshAIKeyStatus()
        } catch {
            aiKeyAvailability = .unknown
            aiKeyStatus = errorMessage(for: error)
            aiKeyStatusIsError = true
        }
    }
    private func deleteAIKey() {
        do {
            try aiKeyStore.deleteKey()
            aiKeyInput = ""
            pendingAIKeyMutation = nil
            refreshAIKeyStatus()
        } catch {
            aiKeyAvailability = .unknown
            aiKeyStatus = errorMessage(for: error)
            aiKeyStatusIsError = true
        }
    }
    private func errorMessage(for error: Error) -> String {
        (error as? AIKeychainError)?.userMessage ?? "Не удалось проверить защищённое хранилище."
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
