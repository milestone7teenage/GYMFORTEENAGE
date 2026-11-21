import Foundation
import Observation

struct AIChatMessage: Identifiable, Equatable {
    enum Role: String, Equatable { case user, assistant }
    let id: UUID
    let role: Role
    let text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

enum AIChatAvailability: Equatable {
    case idle
    case disabled
    case missingKey
    case consentRequired
    case loading
    case failed(String)
}

private struct AIChatPromptContext: Encodable {
    let question: String
    let categories: [String]
    let selectedData: String?
}

private struct AIChatInsightsContext: Encodable {
    let period: AIAnalysisPeriod
    let summary: String?
    let computedMetrics: [AIComputedMetric]
    let limitations: [String]
}

@MainActor
@Observable
final class AICoachSession {
    private(set) var messages: [AIChatMessage] = []
    private(set) var activeScope: AIContextScope?
    private(set) var availability: AIChatAvailability = .idle
    private(set) var isSending = false
    private(set) var canRetry = false
    private(set) var pendingConsentCategories: Set<AIDataCategory> = []
    private(set) var sessionDataCategories: Set<AIDataCategory> = []

    private let requestCoordinator: AIRequestCoordinator
    private let contextBuilder: AIContextBuilder
    private var startingInsights: AIInsights?
    private var activeRequest: Task<String, Error>?
    private var requestGeneration = UUID()

    init(
        requestCoordinator: AIRequestCoordinator = .shared,
        contextBuilder: AIContextBuilder? = nil
    ) {
        self.requestCoordinator = requestCoordinator
        self.contextBuilder = contextBuilder ?? AIContextBuilder()
    }

    func setStartingInsights(_ insights: AIInsights?) {
        startingInsights = insights
    }

    @discardableResult
    func send(
        _ rawQuestion: String,
        store: Store,
        apiKey: String?,
        isAIEnabled: Bool,
        consentedCategories: Set<AIDataCategory> = []
    ) async -> Bool {
        guard !isSending else { return false }
        let question = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, question.count <= 2_000 else {
            availability = .failed("Сообщение пустое или слишком длинное. Сократи вопрос и попробуй снова.")
            return false
        }
        guard isAIEnabled else {
            availability = .disabled
            return false
        }
        guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            availability = .missingKey
            return false
        }

        let selection = contextBuilder.build(for: question, store: store, activeScope: activeScope)
        if let clarification = selection.clarification {
            activeScope = selection.scope
            messages.append(AIChatMessage(role: .user, text: question))
            messages.append(AIChatMessage(role: .assistant, text: clarification))
            trimHistory()
            availability = .idle
            return true
        }

        let requiredCategories = selection.categories.union(sessionDataCategories).union([.chatMessages])
        guard requiredCategories.isSubset(of: consentedCategories) else {
            pendingConsentCategories = requiredCategories.subtracting(consentedCategories)
            activeScope = selection.scope ?? activeScope
            availability = .consentRequired
            return false
        }
        pendingConsentCategories = []
        sessionDataCategories.formUnion(requiredCategories)

        activeScope = selection.scope ?? activeScope
        let selectedData = try? selectedDataJSON(for: selection, store: store)
        let promptContext = AIChatPromptContext(
            question: question,
            categories: selection.categories.map(\.rawValue).sorted(),
            selectedData: selectedData ?? selection.payloadJSON
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let promptData = try? encoder.encode(promptContext),
              let promptText = String(data: promptData, encoding: .utf8),
              promptText.count <= AIConfiguration.maximumPromptCharacters else {
            availability = .failed("Контекст запроса слишком большой. Уточни вопрос или сократи период.")
            return false
        }

        messages.append(AIChatMessage(role: .user, text: question))
        trimHistory()
        let previousMessages = messages.dropLast().map { message in
            GeminiContent(role: message.role == .user ? "user" : "model", text: message.text)
        }
        let requestMessages = previousMessages + [GeminiContent(role: "user", text: promptText)]
        let request = GeminiGenerateContentRequest(
            contents: Array(requestMessages.suffix(10)),
            systemInstruction: AIConfiguration.chatSystemInstruction,
            generationConfig: GeminiGenerationConfig(temperature: 0.4, maxOutputTokens: 1200)
        )
        let generation = UUID()
        requestGeneration = generation
        isSending = true
        canRetry = false
        availability = .loading
        defer {
            if requestGeneration == generation {
                isSending = false
                activeRequest = nil
            }
        }

        do {
            let operation = Task { try await requestCoordinator.generateChatContent(request, apiKey: apiKey) }
            activeRequest = operation
            let response = try await withTaskCancellationHandler {
                try await operation.value
            } onCancel: {
                operation.cancel()
            }
            guard requestGeneration == generation else { return true }
            guard !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  response.count <= 4_000,
                  !response.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0.value != 10 && $0.value != 9 }) else {
                canRetry = true
                availability = .failed("AI Coach вернул пустой или слишком большой ответ. Попробуй задать вопрос иначе.")
                return true
            }
            messages.append(AIChatMessage(role: .assistant, text: response.trimmingCharacters(in: .whitespacesAndNewlines)))
            trimHistory()
            canRetry = false
            availability = .idle
            return true
        } catch let error as GeminiClientError {
            guard requestGeneration == generation else { return true }
            if Task.isCancelled || error == .cancelled {
                availability = .idle
                return true
            }
            canRetry = true
            availability = .failed(error.userMessage)
            return true
        } catch {
            guard requestGeneration == generation else { return true }
            canRetry = !Task.isCancelled
            availability = Task.isCancelled ? .idle : .failed("Не удалось получить ответ. Предыдущие сообщения останутся только в текущем чате.")
            return true
        }
    }

    @discardableResult
    func retryLast(
        store: Store,
        apiKey: String?,
        isAIEnabled: Bool,
        consentedCategories: Set<AIDataCategory> = []
    ) async -> Bool {
        guard canRetry, !isSending,
              let question = messages.last(where: { $0.role == .user })?.text else { return false }
        if messages.last?.role == .user { messages.removeLast() }
        canRetry = false
        availability = .idle
        return await send(
            question,
            store: store,
            apiKey: apiKey,
            isAIEnabled: isAIEnabled,
            consentedCategories: consentedCategories
        )
    }

    func setLocalError(_ message: String) {
        availability = .failed(message)
    }

    func cancelAndClear() {
        requestGeneration = UUID()
        activeRequest?.cancel()
        activeRequest = nil
        messages.removeAll(keepingCapacity: false)
        activeScope = nil
        pendingConsentCategories = []
        sessionDataCategories = []
        startingInsights = nil
        isSending = false
        canRetry = false
        availability = .idle
    }

    private func selectedDataJSON(for selection: AIContextSelection, store: Store) throws -> String? {
        if selection.categories.contains(.weeklyInsights) {
            if let startingInsights {
                let context = AIChatInsightsContext(
                    period: startingInsights.period,
                    summary: startingInsights.summary,
                    computedMetrics: startingInsights.computedMetrics,
                    limitations: startingInsights.limitations
                )
                let data = try JSONEncoder.sorted.encode(context)
                return String(data: data, encoding: .utf8)
            }
            return AIInsightsEngine().build(from: store).promptJSON
        }
        return selection.payloadJSON
    }

    private func trimHistory() {
        if messages.count > 10 { messages = Array(messages.suffix(10)) }
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
