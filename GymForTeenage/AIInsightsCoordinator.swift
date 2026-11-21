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
    let measurementCount: Int
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
    let measurements: [AIInsightsMeasurementValue]
    let comparisonWorkouts: [AIInsightsComparisonWorkout]
    let limitations: [String]
}

struct AIInsightsMeasurementValue: Codable, Equatable, Sendable {
    let kind: String
    let date: String
    let value: Double
    let unit: String
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

    struct MeasurementEntry: Encodable {
        let id: String
        let kind: String
        let timestampMilliseconds: Int64
        let value: Double
    }

    let algorithmVersion: Int
    let schemaVersion: Int
    let startMilliseconds: Int64
    let endMilliseconds: Int64
    let localCalendarDate: String
    let timeZoneIdentifier: String
    let records: [RecordEntry]
    let measurements: [MeasurementEntry]
}

@MainActor
struct AIInsightsEngine {
    static let contextAlgorithmVersion = 2

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
        let activeWorkoutID = store.session?.workoutID
        let weekly = store.records
            .filter { $0.date >= weekStart && $0.date < endExclusive }
            .sorted(by: recordOrder)
        let completedSets = weekly.reduce(0) { $0 + Metrics.completedSets($1.exercises) }
        let tonnage = weekly.reduce(0.0) { $0 + Metrics.tonnage($1.exercises) }

        var activeSets = 0
        var activeTonnage = 0.0
        if let session = store.session {
            activeSets = Metrics.completedSets(session.exercises)
            activeTonnage = Metrics.tonnage(session.exercises)
        }

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
        let measurements = latestMeasurements(in: store.measures, start: weekStart, end: endExclusive)
        var metrics = [
            AIComputedMetric(key: "workouts_7d", value: Double(weekly.count), unit: "тренировки", sampleCount: weekly.count),
            AIComputedMetric(key: "completed_sets_7d", value: Double(completedSets), unit: "подходы", sampleCount: weekly.count),
            AIComputedMetric(key: "tonnage_7d", value: tonnage, unit: "кг·повторения", sampleCount: weekly.count)
        ]
        if activeSets > 0 {
            metrics.append(AIComputedMetric(key: "active_sets", value: Double(activeSets), unit: "подходы", sampleCount: 1))
        }
        if activeTonnage > 0 {
            metrics.append(AIComputedMetric(key: "active_tonnage", value: activeTonnage, unit: "кг·повторения", sampleCount: 1))
        }
        for measurement in measurements {
            metrics.append(AIComputedMetric(
                key: measurement.kind == "weight" ? "latest_weight_kg" : "latest_height_cm",
                value: measurement.value,
                unit: measurement.kind == "weight" ? "kg" : "cm",
                sampleCount: 1
            ))
        }
        var limitations = ["Итоги рассчитаны приложением только по завершённым тренировкам периода."]
        limitations.append("Сравнительные тренировки не входят в недельные итоги.")
        if activeSets > 0 { limitations.append("Активная тренировка учитывается отдельно (подходы и тоннаж не входят в недельные итоги).") }
        if weekly.isEmpty { limitations.append("За выбранные дни завершённых тренировок нет.") }
        if measurements.isEmpty { limitations.append("За выбранные дни подходящих измерений нет.") }
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
            records: usedRecords.map(fingerprintRecord),
            measurements: measurements.map { measurement in
                return AIInsightsFingerprint.MeasurementEntry(
                    id: measurement.id.uuidString,
                    kind: measurement.kind,
                    timestampMilliseconds: milliseconds(measurement.date),
                    value: measurement.value
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let fingerprintData = (try? encoder.encode(fingerprintInput)) ?? Data()
        let fingerprint = SHA256.hash(data: fingerprintData).map { String(format: "%02x", $0) }.joined()

        let promptContext = AIInsightsPromptContext(
            period: period,
            computedMetrics: metrics,
            measurements: measurements.map { measurement in
                AIInsightsMeasurementValue(
                    kind: measurement.kind,
                    date: dayString(measurement.date),
                    value: measurement.value,
                    unit: measurement.kind == "weight" ? "kg" : "cm"
                )
            },
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
            measurementCount: measurements.count,
            promptJSON: String(data: promptData, encoding: .utf8) ?? "{}"
        )
    }

    private func latestMeasurements(in values: [Measure], start: Date, end: Date) -> [Measure] {
        let relevant = values.filter { ($0.kind == "weight" || $0.kind == "height") && $0.value.isFinite && $0.date >= start && $0.date < end }
        let latest = Dictionary(grouping: relevant, by: \.kind).compactMap { _, entries in
            entries.sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.id.uuidString < rhs.id.uuidString
            }.first
        }.sorted { $0.kind < $1.kind }
        return latest
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
    private var engine: AIInsightsEngine
    private let cache: AIInsightsCache
    private let client: any GeminiGenerating
    private var lastAttemptFingerprint: String?
    private var activeRequestFingerprint: String?
    private var requestGeneration = UUID()
    private var activeTask: Task<String, Error>?
    private(set) var requiredConsentCategories: Set<AIDataCategory> = [.weeklyInsights]

    init(
        engine: AIInsightsEngine? = nil,
        cache: AIInsightsCache = AIInsightsCache(),
        client: any GeminiGenerating = AIRequestCoordinator.shared
    ) {
        self.engine = engine ?? AIInsightsEngine()
        self.cache = cache
        self.client = client
    }

    func refresh(
        store: Store,
        isAIEnabled: Bool,
        apiKey: String?,
        consentedCategories: Set<AIDataCategory> = [],
        allowGeneration: Bool = true,
        forceRefresh: Bool = false,
        now: Date = Date()
    ) async {
        let analysis = engine.build(from: store, now: now)
        requiredConsentCategories = analysis.measurementCount > 0 ? [.weeklyInsights, .bodyMeasurements] : [.weeklyInsights]
        
        // Генерация локальной сводки
        let localInsights = generateLocalInsights(from: analysis)
        let previous = cache.load()
        let previousInsights = previous?.insights
        let isCurrent = previous?.fingerprint == analysis.fingerprint
            && previous?.contextAlgorithmVersion == AIInsightsEngine.contextAlgorithmVersion
            && previous?.schemaVersion == AIInsights.currentSchemaVersion

        if analysis.weeklyWorkoutCount == 0 && analysis.measurementCount == 0 {
            if previousInsights != nil { try? cache.clear() }
            state = isAIEnabled
                ? .empty(.noData, message: "За последние семь дней нет завершённых тренировок для анализа.")
                : .empty(.disabled, message: "Включи Teenage Coach в настройках, чтобы обновить Insights.")
            return
        }
        guard isAIEnabled else {
            state = AIInsightsViewState(availability: .disabled, insights: previousInsights, isStale: previousInsights != nil && !isCurrent, message: "Включи Teenage Coach в настройках, чтобы обновить Insights.")
            return
        }
        if isCurrent, let previousInsights {
            state = AIInsightsViewState(availability: .ready, insights: previousInsights, isStale: false, message: nil)
            return
        }
        if !allowGeneration {
            let hasKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            let hasConsent = requiredConsentCategories.isSubset(of: consentedCategories)
            state = AIInsightsViewState(
                availability: hasKey ? (hasConsent ? .ready : .consentRequired) : .missingKey,
                insights: previousInsights,
                isStale: previousInsights != nil,
                message: !hasKey ? "Сохрани API-ключ в настройках, чтобы запросить Insights." : (hasConsent ? "Сводка не обновляется автоматически. Нажми кнопку, когда захочешь отправить показатели." : "Перед анализом нужно отдельно подтвердить отправку недельных показателей.")
            )
            return
        }
        if !forceRefresh, lastAttemptFingerprint == analysis.fingerprint {
            return
        }
        guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // При отсутствии ключа показываем локально рассчитанную сводку
            state = AIInsightsViewState(availability: .ready, insights: localInsights, isStale: false, message: "Локально рассчитанная сводка по тренировкам за 7 дней.")
            return
        }
        guard requiredConsentCategories.isSubset(of: consentedCategories) else {
            // При отсутствии согласия не запрашиваем API и не перезаписываем состояние локальной сводкой
            state = AIInsightsViewState(availability: .consentRequired, insights: previousInsights, isStale: previousInsights != nil, message: "Перед анализом нужно отдельно подтвердить отправку недельных показателей.")
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
            let operation = Task { try await client.generateInsightsContent(request, apiKey: apiKey) }
            activeTask = operation
            let responseText = try await withTaskCancellationHandler {
                try await operation.value
            } onCancel: {
                operation.cancel()
            }
            guard requestGeneration == generation else { return }
            guard engine.build(from: store, now: now).fingerprint == analysis.fingerprint else {
                state = AIInsightsViewState(availability: .ready, insights: localInsights, isStale: false, message: "Локально рассчитанная сводка (данные изменились во время анализа).")
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
                state = AIInsightsViewState(availability: .ready, insights: localInsights, isStale: false, message: "Локально рассчитанная сводка (запрос отменён).")
                return
            }
            state = AIInsightsViewState(availability: .ready, insights: localInsights, isStale: false, message: "Локально рассчитанная сводка (сетевая ошибка: \(error.userMessage)).")
        } catch let error as AIInsightsValidationError {
            guard requestGeneration == generation else { return }
            state = AIInsightsViewState(availability: .ready, insights: localInsights, isStale: false, message: "Локально рассчитанная сводка (сетевая ошибка: \(error.userMessage)).")
        } catch {
            guard requestGeneration == generation else { return }
            let providerName = AIConfiguration.currentProvider == .openRouter ? "OpenRouter" : "Gemini"
            state = AIInsightsViewState(availability: .ready, insights: localInsights, isStale: false, message: "Локально рассчитанная сводка (\(providerName) вернул неподдерживаемые данные).")
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

    func revokeConsent(using consentStore: AIConsentStore) {
        consentStore.revoke()
        clearCache()
    }

    func consentCategoriesChanged(from old: Set<AIDataCategory>, to new: Set<AIDataCategory>) {
        if old.subtracting(new).contains(.weeklyInsights) || old.subtracting(new).contains(.bodyMeasurements) {
            clearCache()
        }
    }

    func updateCalendarContext(calendar: Calendar = .current, timeZone: TimeZone = .current) {
        engine = AIInsightsEngine(calendar: calendar, timeZone: timeZone)
        cancelCurrentRequest()
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
    Проанализируй только переданные приложением локально рассчитанные показатели и сравнительные примеры. Верни JSON с полями schemaVersion (1), summary, observations (элементы с text и evidenceKeys) и limitations. Числа, даты, проценты и новые количественные утверждения в текстовых полях запрещены: числовые факты уже рассчитаны приложением. В evidenceKeys используй только переданные ключи показателей. Не выдумывай наблюдения, если оснований недостаточно.
    """
    
    private func generateLocalInsights(from analysis: AIInsightsAnalysis) -> AIInsights? {
        guard analysis.weeklyWorkoutCount > 0 || analysis.measurementCount > 0 else {
            return nil
        }
        
        let summary: String
        if analysis.weeklyWorkoutCount == 0 {
            summary = "За последние 7 дней завершённых тренировок не было."
        } else {
            let workoutsText = analysis.weeklyWorkoutCount == 1 ? "1 тренировку" : "\(analysis.weeklyWorkoutCount) тренировки"
            let sets = analysis.computedMetrics.first(where: { $0.key == "completed_sets_7d" })?.value ?? 0
            let tonnage = analysis.computedMetrics.first(where: { $0.key == "tonnage_7d" })?.value ?? 0
            
            if analysis.measurementCount > 0 {
                summary = "За неделю выполнено \(workoutsText)."
            } else {
                summary = "За неделю выполнено \(workoutsText), \(Int(sets)) подходов, общий тоннаж \(Int(tonnage)) кг·повторений."
            }
        }
        
        var observations: [AIInsightObservation] = []
        
        // Наблюдения на основе метрик
        for metric in analysis.computedMetrics {
            switch metric.key {
            case "workouts_7d" where metric.value > 0:
                let count = Int(metric.value)
                observations.append(AIInsightObservation(
                    text: count == 1 ? "Выполнена тренировка за неделю." : "Выполнены тренировки за неделю.",
                    evidenceKeys: ["workouts_7d"]
                ))
            case "completed_sets_7d" where metric.value > 0:
                observations.append(AIInsightObservation(
                    text: "Подходы выполнены за неделю.",
                    evidenceKeys: ["completed_sets_7d"]
                ))
            case "tonnage_7d" where metric.value > 0:
                observations.append(AIInsightObservation(
                    text: "Тоннаж набран за неделю.",
                    evidenceKeys: ["tonnage_7d"]
                ))
            case "active_sets" where metric.value > 0:
                observations.append(AIInsightObservation(
                    text: "Идёт активная тренировка.",
                    evidenceKeys: ["active_sets"]
                ))
            case "active_tonnage" where metric.value > 0:
                observations.append(AIInsightObservation(
                    text: "Тоннаж в активной тренировке.",
                    evidenceKeys: ["active_tonnage"]
                ))
            case "latest_weight_kg":
                observations.append(AIInsightObservation(
                    text: "Последнее измерение веса.",
                    evidenceKeys: ["latest_weight_kg"]
                ))
            case "latest_height_cm":
                observations.append(AIInsightObservation(
                    text: "Последнее измерение роста.",
                    evidenceKeys: ["latest_height_cm"]
                ))
            default:
                break
            }
        }
        
        // Ограничиваем количество наблюдений
        let limitedObservations = Array(observations.prefix(4))
        
        return AIInsights(
            schemaVersion: AIInsights.currentSchemaVersion,
            period: analysis.period,
            summary: summary,
            observations: limitedObservations,
            computedMetrics: analysis.computedMetrics,
            limitations: analysis.limitations,
            evidence: limitedObservations.map { observation in
                AIInsightEvidence(key: observation.evidenceKeys.first ?? "", metricKeys: observation.evidenceKeys)
            }
        )
    }
}
