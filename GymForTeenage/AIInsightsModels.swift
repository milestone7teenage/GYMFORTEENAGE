import Foundation

struct AIAnalysisPeriod: Codable, Equatable, Sendable {
    let start: Date
    let endExclusive: Date
    let localCalendarDate: String
    let timeZoneIdentifier: String
}

struct AIComputedMetric: Codable, Equatable, Sendable {
    let key: String
    let value: Double
    let unit: String
    let sampleCount: Int
}

struct AIInsightObservation: Codable, Equatable, Sendable {
    let text: String
    let evidenceKeys: [String]
}

struct AIInsightEvidence: Codable, Equatable, Sendable {
    let key: String
    let metricKeys: [String]
}

struct AIInsights: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let period: AIAnalysisPeriod
    let summary: String
    let observations: [AIInsightObservation]
    let computedMetrics: [AIComputedMetric]
    let limitations: [String]
    let evidence: [AIInsightEvidence]
}

struct AIInsightsNarrative: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let summary: String
    let observations: [AIInsightObservation]
    let limitations: [String]
}

struct AIInsightsCacheEnvelope: Codable, Equatable, Sendable {
    let fingerprint: String
    let contextAlgorithmVersion: Int
    let schemaVersion: Int
    let createdAt: Date
    let insights: AIInsights
}

enum AIInsightsValidationError: Error, Equatable {
    case unsupportedSchema
    case invalidSummary
    case invalidObservation
    case invalidMetric
    case invalidEvidence
    case numericNarrative

    var userMessage: String {
        "Не удалось проверить сводку. Сохранившаяся версия останется доступна."
    }
}

enum AIInsightsValidator {
    static func makeInsights(
        from narrative: AIInsightsNarrative,
        period: AIAnalysisPeriod,
        computedMetrics: [AIComputedMetric],
        localLimitations: [String]
    ) throws -> AIInsights {
        guard narrative.schemaVersion == AIInsights.currentSchemaVersion else {
            throw AIInsightsValidationError.unsupportedSchema
        }
        guard validText(narrative.summary, maximumLength: 500) else {
            throw AIInsightsValidationError.invalidSummary
        }
        guard narrative.observations.count <= 8,
              narrative.observations.allSatisfy({ validText($0.text, maximumLength: 240) && !$0.evidenceKeys.isEmpty }) else {
            throw AIInsightsValidationError.invalidObservation
        }
        guard narrative.limitations.count <= 8,
              narrative.limitations.allSatisfy({ validText($0, maximumLength: 180) }) else {
            throw AIInsightsValidationError.invalidObservation
        }
        guard computedMetrics.count <= 16,
              Set(computedMetrics.map(\.key)).count == computedMetrics.count,
              computedMetrics.allSatisfy({ !$0.key.isEmpty && $0.value.isFinite && $0.sampleCount >= 0 }) else {
            throw AIInsightsValidationError.invalidMetric
        }

        let allowedMetricKeys = Set(computedMetrics.map(\.key))
        guard narrative.observations.allSatisfy({
            !$0.evidenceKeys.isEmpty && Set($0.evidenceKeys).isSubset(of: allowedMetricKeys)
        }) else {
            throw AIInsightsValidationError.invalidEvidence
        }

        let visibleText = [narrative.summary]
            + narrative.observations.map(\.text)
            + narrative.limitations
        guard visibleText.allSatisfy({ !$0.contains(where: \.isNumber) }) else {
            throw AIInsightsValidationError.numericNarrative
        }

        let evidenceKeys = Array(Set(narrative.observations.flatMap(\.evidenceKeys))).sorted()
        let evidence = evidenceKeys.map { key in AIInsightEvidence(key: key, metricKeys: [key]) }
        return AIInsights(
            schemaVersion: AIInsights.currentSchemaVersion,
            period: period,
            summary: narrative.summary,
            observations: narrative.observations,
            computedMetrics: computedMetrics,
            limitations: Array(Set(localLimitations + narrative.limitations)).sorted(),
            evidence: evidence
        )
    }

    static func validateCached(_ insights: AIInsights) -> Bool {
        guard insights.schemaVersion == AIInsights.currentSchemaVersion,
              insights.period.start < insights.period.endExclusive,
              validText(insights.summary, maximumLength: 500),
              insights.limitations.count <= 16,
              insights.limitations.allSatisfy({ validText($0, maximumLength: 180) }),
              insights.computedMetrics.count <= 16,
              Set(insights.computedMetrics.map(\.key)).count == insights.computedMetrics.count,
              insights.computedMetrics.allSatisfy({ !$0.key.isEmpty && $0.value.isFinite && $0.sampleCount >= 0 }),
              insights.evidence.count <= 16,
              Set(insights.evidence.map(\.key)).count == insights.evidence.count else {
            return false
        }
        let metricKeys = Set(insights.computedMetrics.map(\.key))
        let evidenceKeys = Set(insights.evidence.map(\.key))
        guard insights.evidence.allSatisfy({
            !$0.key.isEmpty && !$0.metricKeys.isEmpty && Set($0.metricKeys).isSubset(of: metricKeys)
        }) else { return false }
        return insights.observations.allSatisfy { observation in
            validText(observation.text, maximumLength: 240)
                && !observation.text.contains(where: \.isNumber)
                && !observation.evidenceKeys.isEmpty
                && Set(observation.evidenceKeys).isSubset(of: metricKeys)
                && Set(observation.evidenceKeys).isSubset(of: evidenceKeys)
        } && insights.observations.count <= 8
            && !insights.summary.contains(where: \.isNumber)
            && insights.limitations.allSatisfy { !$0.contains(where: \.isNumber) }
    }

    private static func validText(_ value: String, maximumLength: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= maximumLength
    }
}

enum AIInsightsAvailability: Equatable {
    case disabled
    case missingKey
    case consentRequired
    case loading
    case ready
    case noData
    case failed
}

struct AIInsightsViewState: Equatable {
    let availability: AIInsightsAvailability
    let insights: AIInsights?
    let isStale: Bool
    let message: String?

    static func empty(_ availability: AIInsightsAvailability, message: String? = nil) -> AIInsightsViewState {
        AIInsightsViewState(availability: availability, insights: nil, isStale: false, message: message)
    }
}
