import Foundation

enum AIDataCategory: String, Codable, CaseIterable, Hashable {
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
            let entries = store.records
                .filter { $0.date >= period.start && $0.date < period.end }
                .sorted { $0.date > $1.date }
                .compactMap { record -> AIExerciseContext.Entry? in
                    guard let log = record.exercises.first(where: { $0.exerciseID == exercise.id || $0.actualID == exercise.id }) else { return nil }
                    return AIExerciseContext.Entry(
                        date: dayString(record.date),
                        workout: record.name,
                        exercise: exercise.title,
                        status: log.status,
                        sets: log.sets.map { .init(weight: $0.weight, repetitions: $0.reps, skipped: $0.skipped) }
                    )
                }
                .prefix(8)
            let payload = AIExerciseContext(period: period.label, entries: Array(entries))
            return selection(scope: scope, payload: payload, category: .exerciseHistory, clarification: nil)
        }

        if normalizedQuestion.contains("вода") || normalizedQuestion.contains("пить") || normalizedQuestion.contains("пил") || normalizedQuestion.contains("гидратац") {
            let scope = AIContextScope(category: .waterIntake, exerciseID: nil, measurementKind: nil, startDate: period.start, endDate: period.end)
            let entries = store.water
                .filter { dayDate($0.day).map { $0 >= period.start && $0 < period.end } ?? false }
                .sorted { $0.day < $1.day }
                .suffix(90)
                .map { AIWaterContext.Entry(day: $0.day, milliliters: $0.ml) }
            return selection(scope: scope, payload: AIWaterContext(period: period.label, entries: entries), category: .waterIntake, clarification: nil)
        }

        if normalizedQuestion.contains("вес") || normalizedQuestion.contains("рост") || normalizedQuestion.contains("измерен") {
            let kind = normalizedQuestion.contains("рост") ? "height" : "weight"
            let scope = AIContextScope(category: .bodyMeasurements, exerciseID: nil, measurementKind: kind, startDate: period.start, endDate: period.end)
            let entries = store.measures
                .filter { $0.kind == kind && $0.date >= period.start && $0.date < period.end }
                .sorted { $0.date < $1.date }
                .suffix(50)
                .map { AIMeasurementContext.Entry(date: dayString($0.date), value: $0.value, unit: kind == "weight" ? "kg" : "cm") }
            return selection(scope: scope, payload: AIMeasurementContext(period: period.label, kind: kind, entries: entries), category: .bodyMeasurements, clarification: nil)
        }

        if isFollowUp(normalizedQuestion), let activeScope {
            return build(scope: activeScope, question: normalizedQuestion, store: store, now: now)
        }

        if normalizedQuestion.contains("недел") || normalizedQuestion.contains("сводк") || normalizedQuestion.contains("обзор") || normalizedQuestion.contains("мой прогресс") || normalizedQuestion.contains("мои трениров") {
            let scope = AIContextScope(category: .weeklyInsights, exerciseID: nil, measurementKind: nil, startDate: period.start, endDate: period.end)
            return AIContextSelection(scope: scope, payloadJSON: nil, categories: [.weeklyInsights], clarification: nil)
        }

        return AIContextSelection(scope: nil, payloadJSON: nil, categories: [], clarification: nil)
    }

    private func build(scope: AIContextScope, question: String, store: Store, now: Date) -> AIContextSelection {
        switch scope.category {
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
        let questionWords = Set(question.split(separator: " ").map(String.init))
        let exactMatches = Catalog.all.filter { exercise in
            let title = Self.normalize(exercise.title)
            let id = Self.normalize(exercise.id)
            let titleWords = Set(title.split(separator: " ").map(String.init))
            return question.contains(" \(title) ") || question == title || questionWords.contains(id) || titleWords.isSubset(of: questionWords)
        }
        if !exactMatches.isEmpty { return exactMatches }

        let ignoredWords: Set<String> = ["в", "на", "под", "за", "по", "моей", "моем", "моём", "мой", "моя", "мои", "упражнение"]
        let usefulWords = questionWords.subtracting(ignoredWords)
        guard !usefulWords.isEmpty else { return [] }
        return Catalog.all.filter { exercise in
            let titleWords = Set(Self.normalize(exercise.title).split(separator: " ").map(String.init))
            return !titleWords.isDisjoint(with: usefulWords)
        }
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
