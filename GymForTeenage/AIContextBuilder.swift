import Foundation

enum AIDataCategory: String, Codable, CaseIterable, Hashable {
    case chatMessages
    case exerciseHistory
    case waterIntake
    case bodyMeasurements
    case weeklyInsights
}

struct AIContextScope: Equatable {
    let category: AIDataCategory
    let exerciseID: String?
    let measurementKind: String?
    let startDate: Date
    let endDate: Date
}

struct AIContextSelection: Equatable {
    let scope: AIContextScope?
    let payloadJSON: String?
    let categories: Set<AIDataCategory>
    let clarification: String?

    var isPersonal: Bool { !categories.isEmpty }
}

private struct AIExerciseContext: Encodable {
    struct Entry: Encodable {
        struct Set: Encodable {
            let weight: String
            let repetitions: String
            let skipped: Bool
        }

        let date: String
        let workout: String
        let exercise: String
        let status: String
        let sets: [Set]
    }

    let category = "exercise_history"
    let period: String
    let entries: [Entry]
}

private struct AIWaterContext: Encodable {
    struct Entry: Encodable { let day: String; let milliliters: Int }
    let category = "water_intake"
    let period: String
    let entries: [Entry]
}

private struct AIMeasurementContext: Encodable {
    struct Entry: Encodable { let date: String; let value: Double; let unit: String }
    let category = "body_measurement"
    let period: String
    let kind: String
    let entries: [Entry]
}

private struct AIGeneralWorkoutContext: Encodable {
    struct Entry: Encodable {
        let date: String
        let workout: String
        let exercises: [ExerciseEntry]
        struct ExerciseEntry: Encodable {
            let name: String
            let sets: [Set]
            struct Set: Encodable {
                let weight: String
                let repetitions: String
                let skipped: Bool
            }
        }
    }
    let category = "workout_history"
    let period: String
    let entries: [Entry]
}

@MainActor
struct AIContextBuilder {
    private let calendar: Calendar
    private let timeZone: TimeZone

    init(calendar: Calendar = .current, timeZone: TimeZone = .current) {
        var configuredCalendar = calendar
        configuredCalendar.timeZone = timeZone
        self.calendar = configuredCalendar
        self.timeZone = timeZone
    }

    func build(
        for question: String,
        store: Store,
        activeScope: AIContextScope? = nil,
        now: Date = Date()
    ) -> AIContextSelection {
        let normalizedQuestion = Self.normalize(question)
        let matches = matchingExercises(in: normalizedQuestion)
        if matches.count > 1 {
            return AIContextSelection(
                scope: nil,
                payloadJSON: nil,
                categories: [],
                clarification: "Уточни, пожалуйста, какое именно упражнение ты имеешь в виду."
            )
        }

        let days = periodLength(in: normalizedQuestion, default: 30)
        let period = makePeriod(days: days, endingAt: now)
        if let exercise = matches.first {
            let scope = AIContextScope(category: .exerciseHistory, exerciseID: exercise.id, measurementKind: nil, startDate: period.start, endDate: period.end)
            let entries = buildExerciseHistory(for: exercise, store: store, period: period)
            let payload = AIExerciseContext(period: period.label, entries: entries)
            return selection(scope: scope, payload: payload, category: .exerciseHistory, clarification: nil)
        }

        // 1. Follow-up with activeScope has HIGHEST priority (before category detection)
        if isFollowUp(normalizedQuestion), let activeScope {
            return build(scope: activeScope, question: normalizedQuestion, store: store, now: now)
        }

        // 2. Water/hydration questions (contains water-related keywords)
        if normalizedQuestion.contains("вода") || normalizedQuestion.contains("пить") || normalizedQuestion.contains("пил") || normalizedQuestion.contains("выпил") || normalizedQuestion.contains("гидратац") || normalizedQuestion.contains("мл") || normalizedQuestion.contains("литр") {
            let scope = AIContextScope(category: .waterIntake, exerciseID: nil, measurementKind: nil, startDate: period.start, endDate: period.end)
            let entries = store.water
                .filter { dayDate($0.day).map { $0 >= period.start && $0 < period.end } ?? false }
                .sorted { $0.day < $1.day }
                .suffix(90)
                .map { AIWaterContext.Entry(day: $0.day, milliliters: $0.ml) }
            return selection(scope: scope, payload: AIWaterContext(period: period.label, entries: entries), category: .waterIntake, clarification: nil)
        }

        // 3. Body measurement specific questions
        if normalizedQuestion.contains("рост") || normalizedQuestion.contains("масса тела") || normalizedQuestion.contains("вес тела") || normalizedQuestion.contains("похудел") || normalizedQuestion.contains("набрал вес") {
            let kind = normalizedQuestion.contains("рост") ? "height" : "weight"
            let scope = AIContextScope(category: .bodyMeasurements, exerciseID: nil, measurementKind: kind, startDate: period.start, endDate: period.end)
            let entries = store.measures
                .filter { $0.kind == kind && $0.date >= period.start && $0.date < period.end }
                .sorted { $0.date < $1.date }
                .suffix(50)
                .map { AIMeasurementContext.Entry(date: dayString($0.date), value: $0.value, unit: kind == "weight" ? "kg" : "cm") }
            return selection(scope: scope, payload: AIMeasurementContext(period: period.label, kind: kind, entries: entries), category: .bodyMeasurements, clarification: nil)
        }

        // 4. General workout question (explicit workout/weight/program keywords, but NOT water/body)
        if isGeneralWorkoutQuestion(normalizedQuestion) {
            let scope = AIContextScope(category: .exerciseHistory, exerciseID: nil, measurementKind: nil, startDate: period.start, endDate: period.end)
            let entries = buildGeneralWorkoutHistory(store: store, period: period)
            let payload = AIGeneralWorkoutContext(period: period.label, entries: entries)
            return selection(scope: scope, payload: payload, category: .exerciseHistory, clarification: nil)
        }

        // 5. Generic body measurement (just "вес" or "измерен")
        if normalizedQuestion.contains("вес") || normalizedQuestion.contains("измерен") {
            let kind = normalizedQuestion.contains("рост") ? "height" : "weight"
            let scope = AIContextScope(category: .bodyMeasurements, exerciseID: nil, measurementKind: kind, startDate: period.start, endDate: period.end)
            let entries = store.measures
                .filter { $0.kind == kind && $0.date >= period.start && $0.date < period.end }
                .sorted { $0.date < $1.date }
                .suffix(50)
                .map { AIMeasurementContext.Entry(date: dayString($0.date), value: $0.value, unit: kind == "weight" ? "kg" : "cm") }
            return selection(scope: scope, payload: AIMeasurementContext(period: period.label, kind: kind, entries: entries), category: .bodyMeasurements, clarification: nil)
        }

        // 6. Weekly insights
        if normalizedQuestion.contains("недел") || normalizedQuestion.contains("сводк") || normalizedQuestion.contains("обзор") || normalizedQuestion.contains("мой прогресс") || normalizedQuestion.contains("мои трениров") {
            let scope = AIContextScope(category: .weeklyInsights, exerciseID: nil, measurementKind: nil, startDate: period.start, endDate: period.end)
            return AIContextSelection(scope: scope, payloadJSON: nil, categories: [.weeklyInsights], clarification: nil)
        }

        return AIContextSelection(scope: nil, payloadJSON: nil, categories: [], clarification: nil)
    }

    private func buildExerciseHistory(for exercise: Exercise, store: Store, period: (start: Date, end: Date, label: String)) -> [AIExerciseContext.Entry] {
        var entries: [AIExerciseContext.Entry] = []

        let historyRecords = store.records
            .filter { $0.date >= period.start && $0.date < period.end }
            .sorted { $0.date > $1.date }

        for record in historyRecords {
            guard let log = record.exercises.first(where: { $0.exerciseID == exercise.id || $0.actualID == exercise.id }),
                  log.status != "skipped" else { continue }
            let workingSets = log.sets.filter { !$0.skipped && !$0.weight.isEmpty && !$0.reps.isEmpty }
            guard !workingSets.isEmpty else { continue }
            entries.append(AIExerciseContext.Entry(
                date: dayString(record.date),
                workout: record.name,
                exercise: exercise.title,
                status: log.status,
                sets: workingSets.map { .init(weight: $0.weight, repetitions: $0.reps, skipped: $0.skipped) }
            ))
            if entries.count >= 8 { break }
        }

        if let session = store.session {
            guard let log = session.exercises.first(where: { $0.exerciseID == exercise.id || $0.actualID == exercise.id }),
                  log.status != "skipped" else { return Array(entries.prefix(8)) }
            let workingSets = log.sets.filter { !$0.skipped && !$0.weight.isEmpty && !$0.reps.isEmpty }
            guard !workingSets.isEmpty else { return Array(entries.prefix(8)) }
            let todayString = dayString(Date())
            if !entries.contains(where: { $0.date == todayString && $0.workout == session.workoutID }) {
                entries.insert(AIExerciseContext.Entry(
                    date: todayString,
                    workout: "Активная тренировка",
                    exercise: exercise.title,
                    status: log.status,
                    sets: workingSets.map { .init(weight: $0.weight, repetitions: $0.reps, skipped: $0.skipped) }
                ), at: 0)
            }
        }

        return Array(entries.prefix(8))
    }

    private func buildGeneralWorkoutHistory(store: Store, period: (start: Date, end: Date, label: String)) -> [AIGeneralWorkoutContext.Entry] {
        let recentRecords = store.records
            .filter { $0.date >= period.start && $0.date < period.end }
            .sorted { $0.date > $1.date }
            .prefix(5)

        var entries: [AIGeneralWorkoutContext.Entry] = []

        for record in recentRecords {
            let exerciseEntries = record.exercises.compactMap { log -> AIGeneralWorkoutContext.Entry.ExerciseEntry? in
                guard log.status != "skipped" else { return nil }
                let workingSets = log.sets.filter { !$0.skipped && !$0.weight.isEmpty && !$0.reps.isEmpty }
                guard !workingSets.isEmpty else { return nil }
                if let exercise = Catalog.all.first(where: { $0.id == log.exerciseID || $0.id == log.actualID }) {
                    return AIGeneralWorkoutContext.Entry.ExerciseEntry(
                        name: exercise.title,
                        sets: workingSets.map { .init(weight: $0.weight, repetitions: $0.reps, skipped: $0.skipped) }
                    )
                }
                return nil
            }
            if !exerciseEntries.isEmpty {
                entries.append(AIGeneralWorkoutContext.Entry(
                    date: dayString(record.date),
                    workout: record.name,
                    exercises: exerciseEntries
                ))
            }
        }

        if let session = store.session {
            let todayString = dayString(Date())
            if !entries.contains(where: { $0.date == todayString }) {
                let exerciseEntries = session.exercises.compactMap { log -> AIGeneralWorkoutContext.Entry.ExerciseEntry? in
                    guard log.status != "skipped" else { return nil }
                    let workingSets = log.sets.filter { !$0.skipped && !$0.weight.isEmpty && !$0.reps.isEmpty }
                    guard !workingSets.isEmpty else { return nil }
                    if let exercise = Catalog.all.first(where: { $0.id == log.exerciseID || $0.id == log.actualID }) {
                        return AIGeneralWorkoutContext.Entry.ExerciseEntry(
                            name: exercise.title,
                            sets: workingSets.map { .init(weight: $0.weight, repetitions: $0.reps, skipped: $0.skipped) }
                        )
                    }
                    return nil
                }
                if !exerciseEntries.isEmpty {
                    entries.insert(AIGeneralWorkoutContext.Entry(
                        date: todayString,
                        workout: "Активная тренировка",
                        exercises: exerciseEntries
                    ), at: 0)
                }
            }
        }

        return entries
    }

    private func isGeneralWorkoutQuestion(_ question: String) -> Bool {
        let workoutKeywords = ["трен", "упражнен", "подход", "рабочий вес", "программ", "план тренировок"]
        let excludeKeywords = ["вод", "пил", "выпил", "мл", "литр", "гидратац", "рост", "масса тела", "вес тела", "похудел", "набрал вес", "измерен"]
        let hasWorkoutKeyword = workoutKeywords.contains { question.contains($0) }
        let hasExcludeKeyword = excludeKeywords.contains { question.contains($0) }
        return hasWorkoutKeyword && !hasExcludeKeyword
    }

    private func build(scope: AIContextScope, question: String, store: Store, now: Date) -> AIContextSelection {
        switch scope.category {
        case .chatMessages:
            return AIContextSelection(scope: scope, payloadJSON: nil, categories: [.chatMessages], clarification: nil)
        case .exerciseHistory:
            guard let id = scope.exerciseID, let exercise = Catalog.all.first(where: { $0.id == id }) else {
                return AIContextSelection(scope: nil, payloadJSON: nil, categories: [], clarification: "Уточни, пожалуйста, упражнение.")
            }
            return build(for: exercise.title, store: store, now: now)
        case .waterIntake:
            return build(for: "вода за \(periodLength(in: question, default: 30)) дней", store: store, now: now)
        case .bodyMeasurements:
            let term = scope.measurementKind == "height" ? "рост" : "вес"
            return build(for: "\(term) за \(periodLength(in: question, default: 30)) дней", store: store, now: now)
        case .weeklyInsights:
            return build(for: "сводка за неделю", store: store, now: now)
        }
    }

    private func matchingExercises(in question: String) -> [Exercise] {
        let normalizedTitle = { (exercise: Exercise) -> String in
            Self.normalize(exercise.title)
        }
        let normalizedID = { (exercise: Exercise) -> String in
            Self.normalize(exercise.id)
        }

        let questionLower = question.lowercased()

        // Step 1: Exact matches (full title or ID)
        let exactMatches = Catalog.all.filter { exercise in
            let title = normalizedTitle(exercise)
            let id = normalizedID(exercise)
            let titleLower = title.lowercased()
            return questionLower == titleLower
                || questionLower.contains(" \(titleLower) ")
                || questionLower.hasPrefix(titleLower + " ")
                || questionLower.hasSuffix(" " + titleLower)
                || questionLower.contains(id.lowercased())
        }
        if !exactMatches.isEmpty { return exactMatches }

        // Step 2: Substring match - check if any query word (>=3 chars) is contained in exercise title
        let queryWords = questionLower.split(separator: " ").map(String.init)
        let containsMatches = Catalog.all.filter { exercise in
            let titleLower = exercise.title.lowercased()
            return queryWords.contains { qWord in
                qWord.count >= 3 && titleLower.contains(qWord)
            }
        }
        if !containsMatches.isEmpty { return containsMatches }

        // Step 3: Stem-based fuzzy matching with Levenshtein for short words
        let ignoredWords: Set<String> = ["в", "на", "под", "за", "по", "моей", "моем", "моём", "мой", "моя", "мои", "упражнение", "как", "менялась", "менялся", "история", "прогресс", "рабочий", "вес", "подход", "за", "неделю", "месяц", "дня", "дней", "делать", "делаю", "сколько", "на", "как", "менялась", "менялся", "родился", "родилась", "родилось", "а", "и", "о", "у", "ы", "э", "ю", "я"]
        let questionWords = question.split(separator: " ").map(String.init)
        let usefulWords = questionWords
            .map { stemRussian($0) }
            .filter { !ignoredWords.contains($0) && $0.count >= 2 }
        guard !usefulWords.isEmpty else { return [] }

        return Catalog.all.filter { exercise in
            let title = normalizedTitle(exercise)
            let titleWords = title.split(separator: " ").map { stemRussian(String($0)) }
            return usefulWords.contains { qStem in
                titleWords.contains { tStem in
                    tStem.hasPrefix(qStem) || qStem.hasPrefix(tStem) || tStem == qStem ||
                    (tStem.count <= 4 && qStem.count <= 4 && levenshteinDistance(tStem, qStem) <= 1)
                }
            }
        }
    }

    private func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        var dp = [[Int]](repeating: [Int](repeating: 0, count: bChars.count + 1), count: aChars.count + 1)
        for i in 0...aChars.count { dp[i][0] = i }
        for j in 0...bChars.count { dp[0][j] = j }
        for i in 1...aChars.count {
            for j in 1...bChars.count {
                let cost = aChars[i-1] == bChars[j-1] ? 0 : 1
                dp[i][j] = min(
                    dp[i-1][j] + 1,      // deletion
                    dp[i][j-1] + 1,      // insertion
                    dp[i-1][j-1] + cost  // substitution
                )
            }
        }
        return dp[aChars.count][bChars.count]
    }

    private func stemRussian(_ word: String) -> String {
        let lower = word.lowercased()
        if lower.hasSuffix("ие") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ия") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ье") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ья") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ой") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ей") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ые") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ие") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ию") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ии") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ие") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ая") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ое") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ее") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ой") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ый") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ий") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ую") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ию") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ия") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ям") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ья") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ье") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ие") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ов") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ев") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ам") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ем") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ом") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ах") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ях") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ой") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ей") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ую") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("юю") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ая") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("яя") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ой") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ее") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("ую") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("юю") { return String(lower.dropLast(2)) }
        if lower.hasSuffix("а") { return String(lower.dropLast(1)) }
        if lower.hasSuffix("я") { return String(lower.dropLast(1)) }
        if lower.hasSuffix("о") { return String(lower.dropLast(1)) }
        if lower.hasSuffix("е") { return String(lower.dropLast(1)) }
        if lower.hasSuffix("и") { return String(lower.dropLast(1)) }
        if lower.hasSuffix("ы") { return String(lower.dropLast(1)) }
        if lower.hasSuffix("у") { return String(lower.dropLast(1)) }
        if lower.hasSuffix("ю") { return String(lower.dropLast(1)) }
        if lower.hasSuffix("ь") { return String(lower.dropLast(1)) }
        if lower.hasSuffix("ъ") { return String(lower.dropLast(1)) }
        return lower
    }

    private func selection<T: Encodable>(scope: AIContextScope, payload: T, category: AIDataCategory, clarification: String?) -> AIContextSelection {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload), data.count <= AIConfiguration.maximumPromptCharacters * 4,
              let text = String(data: data, encoding: .utf8) else {
            return AIContextSelection(scope: scope, payloadJSON: nil, categories: [category], clarification: "Эти данные пока не помещаются в безопасный размер запроса. Уточни период.")
        }
        return AIContextSelection(scope: scope, payloadJSON: text, categories: [category], clarification: clarification)
    }

    private func periodLength(in question: String, default defaultValue: Int) -> Int {
        if question.contains("недел") || question.contains("7 дн") { return 7 }
        if question.contains("месяц") || question.contains("30 дн") { return 30 }
        let pattern = #"(?:за|последние)\s+(\d{1,2})\s+дн"#
        if let range = question.range(of: pattern, options: .regularExpression),
           let digits = question[range].split(whereSeparator: { !$0.isNumber }).last,
           let value = Int(digits) {
            return min(90, max(1, value))
        }
        return defaultValue
    }

    private func makePeriod(days: Int, endingAt now: Date) -> (start: Date, end: Date, label: String) {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        return (start, end, "\(dayString(start))–\(dayString(calendar.date(byAdding: .day, value: -1, to: end) ?? today))")
    }

    private func dayDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func normalize(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
        return folded.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }

    private func isFollowUp(_ question: String) -> Bool {
        ["почему", "подробнее", "подробней", "а если", "сравни", "и что", "а что"].contains(where: question.contains)
    }
}
