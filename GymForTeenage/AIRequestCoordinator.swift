import CryptoKit
import Foundation

actor AIRequestCoordinator: GeminiGenerating {
    static let shared = AIRequestCoordinator()

    private struct InsightFlight {
        let id: UUID
        let signature: String
        let task: Task<String, Error>
    }

    private let geminiClient: GeminiGenerating
    private let openRouterClient: GeminiGenerating
    private var insightFlight: InsightFlight?
    private var chatIsActive = false

    init(
        geminiClient: GeminiGenerating = GeminiClient.shared,
        openRouterClient: GeminiGenerating = OpenRouterClient.shared
    ) {
        self.geminiClient = geminiClient
        self.openRouterClient = openRouterClient
    }

    private func getClient(for provider: AIProvider) -> GeminiGenerating {
        switch provider {
        case .openRouter: return openRouterClient
        case .googleGemini: return geminiClient
        }
    }

    func generateContent(_ request: GeminiGenerateContentRequest, apiKey: String) async throws -> String {
        try await generateChatContent(request, apiKey: apiKey)
    }

    func generateChatContent(_ request: GeminiGenerateContentRequest, apiKey: String) async throws -> String {
        guard !chatIsActive else { throw GeminiClientError.cancelled }
        chatIsActive = true
        defer { chatIsActive = false }
        let displaced = insightFlight?.task
        insightFlight = nil
        displaced?.cancel()
        if let displaced { _ = try? await displaced.value }
        guard !Task.isCancelled else { throw GeminiClientError.cancelled }
        let client = getClient(for: AIConfiguration.currentProvider)
        return try await client.generateContent(request, apiKey: apiKey)
    }

    func generateInsightsContent(_ request: GeminiGenerateContentRequest, apiKey: String) async throws -> String {
        guard !chatIsActive, !Task.isCancelled else { throw GeminiClientError.cancelled }
        let signature = requestSignature(request, apiKey: apiKey)
        if let existing = insightFlight, existing.signature == signature {
            return try await existing.task.value
        }
        if let displaced = insightFlight?.task {
            insightFlight = nil
            displaced.cancel()
            _ = try? await displaced.value
        }
        guard !chatIsActive else { throw GeminiClientError.cancelled }

        let id = UUID()
        let client = getClient(for: AIConfiguration.currentProvider)
        let task = Task { try await client.generateContent(request, apiKey: apiKey) }
        insightFlight = InsightFlight(id: id, signature: signature, task: task)
        defer {
            if insightFlight?.id == id { insightFlight = nil }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func cancelInsights() {
        insightFlight?.task.cancel()
        insightFlight = nil
    }

    private func requestSignature(_ request: GeminiGenerateContentRequest, apiKey: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = (try? encoder.encode(request)) ?? Data()
        var input = Data(apiKey.utf8)
        input.append(0)
        input.append(body)
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }
}
