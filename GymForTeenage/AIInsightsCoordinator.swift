import CryptoKit
import Foundation
import Observation

struct AIInsightsAnalysis: Sendable {
    let fingerprint: String
    let period: AIAnalysisPeriod
    let computedMetrics: [AIComputedMetric]
    let limitations: [String]
    let comparisonWorkouts: [AIInsightsComparisonWorkout]
    let weeklyWorkoutCount: Int
    let promptJSON: String
}

struct AIInsightsComparisonWorkout: Codable, Equatable, Sendable {
    let date: String
    let workout: String
    let completedSets: Int
    let tonnage: Double
}

private struct AIInsightsPromptContext: Encodable {
    let period: AIAnalysisPeriod
    let computedMetrics: [AIComputedMetric]
    let comparisonWorkouts: [AIInsightsComparisonWorkout]
    let limitations: [String]
}

private struct AIInsightsFingerprint: Encodable {
    struct SetEntry: Encodable {
        let index: Int
        let weight: String
        let repetitions: String
        let skipped: Bool
    }

    struct ExerciseEntry: Encodable {
        let slotID: String
        let exerciseID: String
        let actualID: String
        let status: String
        let sets: [SetEntry]
    }

    struct RecordEntry: Encodable {
        let id: String
        let workoutID: String
        let name: String
        let timestampMilliseconds: Int64
        let exercises: [ExerciseEntry]
    }

    let algorithmVersion: Int
    let schemaVersion: Int
    let startMilliseconds: Int64
    let endMilliseconds: Int64
    let localCalendarDate: String
    let timeZoneIdentifier: String
    let records: [RecordEntry]
}

@MainActor
struct AIInsightsEngine {
    static let contextAlgorithmVersion = 1

    private let calendar: Calendar
    private let timeZone: TimeZone

    init(calendar: Calendar = .current, timeZone: TimeZone = .current) {
        var configured = calendar
        configured.timeZone = timeZone
        self.calendar = configured
        self.timeZone = timeZone
    }

    func build(from store: Store, now: Date = Date()) -> AIInsightsAnalysis {
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let comparisonWindowStart = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        let weekly = store.records
            .filter { $0.date >= weekStart && $0.date < endExclusive }
            .sorted(by: recordOrder)
        let comparisons = store.records
            .filter { $0.date >= comparisonWindowStart && $0.date < weekStart }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .prefix(3)
            .map(comparisonSummary)

        let period = AIAnalysisPeriod(
            start: weekStart,
            endExclusive: endExclusive,
            localCalendarDate: dayString(today),
            timeZoneIdentifier: timeZone.identifier
        )
        let completedSets = weekly.reduce(0) { $0 + Metrics.completedSets($1.exercises) }
        let tonnage = weekly.reduce(0.0) { $0 + Metrics.tonnage($1.exercises) }
        let metrics = [
            AIComputedMetric(key: "workouts_7d", value: Double(weekly.count), unit: "тренировки", sampleCount: weekly.count),
            AIComputedMetric(key: "completed_sets_7d", value: Double(completedSets), unit: "подходы", sampleCount: weekly.count),
            AIComputedMetric(key: "tonnage_7d", value: tonnage, unit: "кг·повторения", sampleCount: weekly.count)
        ]
        var limitations = ["Итоги рассчитаны приложением только по завершённым тренировкам периода."]
        limitations.append("Сравнительные тренировки не входят в недельные итоги.")
        if weekly.isEmpty { limitations.append("За выбранные дни завершённых тренировок нет.") }
        if completedSets == 0 && !weekly.isEmpty { limitations.append("Для подходов без числовых повторений нельзя рассчитать часть показателей.") }

        let comparisonRecords = store.records
            .filter { $0.date >= comparisonWindowStart && $0.date < weekStart }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .prefix(3)
            .map { $0 }
        let usedRecords = weekly + comparisonRecords
        let fingerprintInput = AIInsightsFingerprint(
            algorithmVersion: Self.contextAlgorithmVersion,
            schemaVersion: AIInsights.currentSchemaVersion,
            startMilliseconds: milliseconds(weekStart),
            endMilliseconds: milliseconds(endExclusive),
            localCalendarDate: dayString(today),
            timeZoneIdentifier: timeZone.identifier,
            records: usedRecords.map(fingerprintRecord)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let fingerprintData = (try? encoder.encode(fingerprintInput)) ?? Data()
        let fingerprint = SHA256.hash(data: fingerprintData).map { String(format: "%02x", $0) }.joined()

        let promptContext = AIInsightsPromptContext(
            period: period,
            computedMetrics: metrics,
            comparisonWorkouts: Array(comparisons),
            limitations: limitations
        )
        let promptData = (try? encoder.encode(promptContext)) ?? Data()
        return AIInsightsAnalysis(
            fingerprint: fingerprint,
            period: period,
            computedMetrics: metrics,
            limitations: limitations,
            comparisonWorkouts: Array(comparisons),
            weeklyWorkoutCount: weekly.count,
            promptJSON: String(data: promptData, encoding: .utf8) ?? "{}"
        )
    }

    private func comparisonSummary(_ record: Record) -> AIInsightsComparisonWorkout {
        AIInsightsComparisonWorkout(
            date: dayString(record.date),
            workout: record.name,
            completedSets: Metrics.completedSets(record.exercises),
            tonnage: Metrics.tonnage(record.exercises)
        )
    }

    private func fingerprintRecord(_ record: Record) -> AIInsightsFingerprint.RecordEntry {
        let exercises = record.exercises.sorted { $0.slotID < $1.slotID }.map { exercise in
            AIInsightsFingerprint.ExerciseEntry(
                slotID: exercise.slotID,
                exerciseID: exercise.exerciseID,
                actualID: exercise.actualID,
                status: exercise.status,
                sets: exercise.sets.enumerated().map { index, set in
                    AIInsightsFingerprint.SetEntry(index: index, weight: set.weight, repetitions: set.reps, skipped: set.skipped)
                }
            )
        }
        return AIInsightsFingerprint.RecordEntry(
            id: record.id.uuidString,
            workoutID: record.workoutID,
            name: record.name,
            timestampMilliseconds: milliseconds(record.date),
            exercises: exercises
        )
    }

    private func recordOrder(_ lhs: Record, _ rhs: Record) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func milliseconds(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1_000).rounded()) }
}

@MainActor
@Observable
final class AIInsightsCoordinator {
    private(set) var state = AIInsightsViewState.empty(.noData)
    private let engine: AIInsightsEngine
    private let cache: AIInsightsCache
    private let client: any GeminiGenerating
    private var lastAttemptFingerprint: String?
    private var activeRequestFingerprint: String?
    private var requestGeneration = UUID()
    private var activeTask: Task<String, Error>?

    init(
        engine: AIInsightsEngine? = nil,
        cache: AIInsightsCache = AIInsightsCache(),
        client: any GeminiGenerating = GeminiClient.shared
    ) {
        self.engine = engine ?? AIInsightsEngine()
        self.cache = cache
        self.client = client
    }

    func refresh(
        store: Store,
        isAIEnabled: Bool,
        apiKey: String?,
        allowsPersonalData: Bool = false,
        forceRefresh: Bool = false,
        now: Date = Date()
    ) async {
        let analysis = engine.build(from: store, now: now)
        let previous = cache.load()
        let previousInsights = previous?.insights
        let isCurrent = previous?.fingerprint == analysis.fingerprint
            && previous?.contextAlgorithmVersion == AIInsightsEngine.contextAlgorithmVersion
            && previous?.schemaVersion == AIInsights.currentSchemaVersion

        guard isAIEnabled else {
            state = AIInsightsViewState(availability: .disabled, insights: previousInsights, isStale: previousInsights != nil && !isCurrent, message: "Включи AI-помощника в настройках, чтобы обновить Insights.")
            return
        }
        if analysis.weeklyWorkoutCount == 0 {
            if previousInsights != nil && !isCurrent { try? cache.clear() }
            state = .empty(.noData, message: "За последние семь дней нет завершённых тренировок для анализа.")
            return
        }
        if isCurrent, let previousInsights {
            state = AIInsightsViewState(availability: .ready, insights: previousInsights, isStale: false, message: nil)
            return
        }
        if !forceRefresh, lastAttemptFingerprint == analysis.fingerprint {
            return
        }
        guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = AIInsightsViewState(availability: .missingKey, insights: previousInsights, isStale: previousInsights != nil, message: "Сохрани API-ключ Gemini в настройках.")
            return
        }
        guard allowsPersonalData else {
            state = AIInsightsViewState(availability: .consentRequired, insights: previousInsights, isStale: previousInsights != nil, message: "Перед анализом нужно разрешить отправку недельных показателей в Google Gemini.")
            return
        }

        if activeRequestFingerprint == analysis.fingerprint { return }
        activeRequestFingerprint = analysis.fingerprint
        lastAttemptFingerprint = analysis.fingerprint
        let generation = UUID()
        requestGeneration = generation
        state = AIInsightsViewState(availability: .loading, insights: previousInsights, isStale: previousInsights != nil, message: nil)
        let request = GeminiGenerateContentRequest(
            contents: [GeminiContent(role: "user", text: analysis.promptJSON)],
            systemInstruction: Self.insightsSystemInstruction,
            generationConfig: GeminiGenerationConfig(temperature: 0.2, maxOutputTokens: 1200, responseMimeType: "application/json")
        )
        defer {
            if activeRequestFingerprint == analysis.fingerprint {
                activeRequestFingerprint = nil
                activeTask = nil
            }
        }
        do {
            let operation = Task { try await client.generateContent(request, apiKey: apiKey) }
            activeTask = operation
            let responseText = try await withTaskCancellationHandler {
                try await operation.value
            } onCancel: {
                operation.cancel()
            }
            guard requestGeneration == generation else { return }
            guard engine.build(from: store, now: now).fingerprint == analysis.fingerprint else {
                state = AIInsightsViewState(availability: .failed, insights: previousInsights, isStale: previousInsights != nil, message: "Данные изменились во время анализа. Открой статистику ещё раз, чтобы обновить сводку.")
                return
            }
            guard responseText.utf8.count <= AIConfiguration.maximumResponseBytes,
                  let data = responseText.data(using: .utf8) else {
                throw GeminiClientError.responseTooLarge
            }
            let narrative = try JSONDecoder().decode(AIInsightsNarrative.self, from: data)
            let insights = try AIInsightsValidator.makeInsights(
                from: narrative,
                period: analysis.period,
                computedMetrics: analysis.computedMetrics,
                localLimitations: analysis.limitations
            )
            let envelope = AIInsightsCacheEnvelope(
                fingerprint: analysis.fingerprint,
                contextAlgorithmVersion: AIInsightsEngine.contextAlgorithmVersion,
                schemaVersion: AIInsights.currentSchemaVersion,
                createdAt: now,
                insights: insights
            )
            do {
                try cache.save(envelope)
                state = AIInsightsViewState(availability: .ready, insights: insights, isStale: false, message: nil)
            } catch {
                state = AIInsightsViewState(availability: .ready, insights: insights, isStale: false, message: "Сводка готова, но локальный кэш не удалось обновить.")
            }
        } catch let error as GeminiClientError {
            guard requestGeneration == generation else { return }
            if Task.isCancelled || error == .cancelled {
                lastAttemptFingerprint = nil
                state = AIInsightsViewState(availability: previousInsights == nil ? .noData : .ready, insights: previousInsights, isStale: previousInsights != nil && !isCurrent, message: nil)
                return
            }
            state = AIInsightsViewState(availability: .failed, insights: previousInsights, isStale: previousInsights != nil, message: error.userMessage)
        } catch let error as AIInsightsValidationError {
            guard requestGeneration == generation else { return }
            state = AIInsightsViewState(availability: .failed, insights: previousInsights, isStale: previousInsights != nil, message: error.userMessage)
        } catch {
            guard requestGeneration == generation else { return }
            state = AIInsightsViewState(availability: .failed, insights: previousInsights, isStale: previousInsights != nil, message: "Gemini вернул данные, которые приложение не смогло проверить.")
        }
    }

    func clearCache() {
        requestGeneration = UUID()
        activeTask?.cancel()
        activeTask = nil
        activeRequestFingerprint = nil
        lastAttemptFingerprint = nil
        try? cache.clear()
        state = .empty(.noData)
    }

    func cancelCurrentRequest() {
        requestGeneration = UUID()
        activeTask?.cancel()
        activeTask = nil
        activeRequestFingerprint = nil
        state = AIInsightsViewState(
            availability: state.insights == nil ? .noData : .ready,
            insights: state.insights,
            isStale: state.isStale,
            message: nil
        )
    }

    private static let insightsSystemInstruction = """
    Проанализируй только переданные приложением локально рассчитанные показатели и сравнительные примеры. Верни JSON с полями schemaVersion (1), summary, observations (элементы с text и evidenceKeys) и limitations. Числа, даты, проценты и новые количественные утверждения в текстовых полях запрещены: числовые факты уже рассчитаны приложением. В evidenceKeys используй только переданные ключи показателей. Не выдумывай наблюдения, если оснований недостаточно. Не давай медицинских назначений, экстремальных диет или рискованных советов подростку; при боли, травме или вопросах лечения советуй обратиться к родителю или опекуну и квалифицированному специалисту.
    """
}
