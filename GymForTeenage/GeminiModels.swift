import Foundation

struct GeminiPart: Codable, Equatable, Sendable {
    let text: String
}

struct GeminiContent: Codable, Equatable, Sendable {
    let role: String?
    let parts: [GeminiPart]

    init(role: String? = nil, text: String) {
        self.role = role
        self.parts = [GeminiPart(text: text)]
    }

    init(role: String? = nil, parts: [GeminiPart]) {
        self.role = role
        self.parts = parts
    }
}

struct GeminiGenerationConfig: Codable, Equatable, Sendable {
    var temperature: Double? = 0.2
    var maxOutputTokens: Int? = 2048
    var responseMimeType: String?
}

struct GeminiGenerateContentRequest: Codable, Equatable, Sendable {
    var systemInstruction: GeminiContent?
    var contents: [GeminiContent]
    var generationConfig: GeminiGenerationConfig?

    init(
        contents: [GeminiContent],
        systemInstruction: String? = nil,
        generationConfig: GeminiGenerationConfig? = GeminiGenerationConfig()
    ) {
        self.contents = contents
        self.systemInstruction = systemInstruction.map { GeminiContent(text: $0) }
        self.generationConfig = generationConfig
    }
}

struct GeminiGenerateContentResponse: Decodable, Equatable, Sendable {
    struct Candidate: Decodable, Equatable, Sendable {
        let content: GeminiContent?
        let finishReason: String?
    }

    let candidates: [Candidate]?

    var firstText: String? {
        guard let candidate = candidates?.first else { return nil }
        return candidate.content?.parts.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var firstFinishReason: String? { candidates?.first?.finishReason }
}

enum GeminiClientError: Error, Equatable {
    case missingAPIKey
    case invalidRequest
    case requestTooLarge
    case responseTooLarge
    case timedOut
    case cancelled
    case transport
    case unauthorized
    case forbidden
    case rateLimited(retryAfter: Int)
    case server(status: Int)
    case rejected(status: Int)
    case invalidResponse
    case blockedResponse
    case emptyResponse

    var userMessage: String {
        switch self {
        case .missingAPIKey: return "Сначала сохраните API-ключ Gemini в настройках."
        case .invalidRequest: return "Не удалось подготовить запрос."
        case .requestTooLarge: return "Запрос слишком большой. Уточните вопрос."
        case .responseTooLarge: return "Ответ превышает допустимый размер."
        case .timedOut: return "Gemini не ответил вовремя. Попробуйте ещё раз."
        case .cancelled: return "Запрос отменён."
        case .transport: return "Не удалось подключиться к Gemini. Проверьте сеть и повторите попытку."
        case .unauthorized: return "Gemini не принял API-ключ. Проверьте или замените его в настройках."
        case .forbidden: return "Gemini отклонил запрос. Проверьте доступность API и настройки проекта Google."
        case .rateLimited: return "Слишком много запросов к Gemini. Подождите и повторите попытку."
        case .server: return "Сервис Gemini временно недоступен. Попробуйте позже."
        case .rejected: return "Gemini не смог обработать запрос. Попробуйте изменить формулировку."
        case .invalidResponse: return "Gemini вернул ответ в неизвестном формате."
        case .blockedResponse: return "Gemini не смог ответить на этот запрос. Попробуйте безопасно переформулировать его."
        case .emptyResponse: return "Gemini вернул пустой ответ. Попробуйте ещё раз."
        }
    }
}
