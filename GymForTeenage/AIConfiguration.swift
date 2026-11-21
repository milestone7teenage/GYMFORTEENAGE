import Foundation
import SwiftUI

enum AIProvider: String, CaseIterable, Identifiable {
    case openRouter
    case googleGemini
    
    var id: String { rawValue }
    
    var name: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .googleGemini: return "Google Gemini"
        }
    }
    
    var url: URL {
        switch self {
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        case .googleGemini: return URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!
        }
    }
    
    var defaultModel: String {
        switch self {
        case .openRouter: return "openrouter/free"
        case .googleGemini: return "gemini-3.5-flash-lite"
        }
    }
    
    var requiresAuthorizationHeader: Bool {
        return self == .openRouter
    }
    
    var requiresRefererAndTitleHeaders: Bool {
        return self == .openRouter
    }
}

enum AIConfiguration {
    @AppStorage("AIConfiguration.currentProvider") private static var storedProvider: String = "googleGemini"
    
    static var currentProvider: AIProvider {
        get {
            guard let rawValue = storedProvider, let provider = AIProvider(rawValue: rawValue) else { return .googleGemini }
            return provider
        }
        set {
            storedProvider = newValue.rawValue
            currentModelID = newValue.defaultModel
        }
    }
    static var currentModelID = "gemini-3.5-flash-lite"
    
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
        currentProvider.url.appendingPathComponent(currentProvider == .googleGemini ? "\(currentModelID):generateContent" : "")
    }
    
    static var chatContentURL: URL {
        generateContentURL
    }
}
