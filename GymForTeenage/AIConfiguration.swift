import Foundation

enum AIConfiguration {
    static let modelID = "gemini-3.5-flash-lite"
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
    Ты — фитнес-аналитик для подростка. Отвечай кратко и по фактам: даты, веса, повторения. Не выдумывай числа.
    """
    static let chatSystemInstruction = """
    Ты — фитнес-аналитик для подростка. Отвечай кратко и по фактам: даты, веса, повторения из истории. Не выдумывай числа.
    """

    static var generateContentURL: URL {
        apiBaseURL.appendingPathComponent("\(modelID):generateContent")
    }
}
