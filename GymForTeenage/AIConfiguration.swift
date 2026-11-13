import Foundation

enum AIConfiguration {
    static let modelID = "gemini-3.1-flash-lite"
    static let apiBaseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!
    static let requestTimeout: TimeInterval = 30
    static let resourceTimeout: TimeInterval = 60
    static let maximumAPIKeyLength = 4096
    static let maximumPromptCharacters = 16_000
    static let maximumResponseBytes = 256_000
    static let maximumRetryAttempts = 2
    static let retryBaseDelay: TimeInterval = 0.4
    static let maximumRetryDelay: TimeInterval = 8
    static let defaultRateLimitDelay: TimeInterval = 30
    static let systemInstruction = """
    Ты — AI-помощник по тренировкам для подростка. Отвечай уважительно и без стыда или давления. Не ставь диагнозы, не назначай лечение, экстремальные диеты или опасные нагрузки. При боли, травме, болезни, нарушениях питания или вопросах лечения советуй обратиться к родителю или опекуну и квалифицированному медицинскому специалисту. Не выдумывай числовые факты и опирайся только на переданные данные.
    """

    static var generateContentURL: URL {
        apiBaseURL.appendingPathComponent("\(modelID):generateContent")
    }
}
