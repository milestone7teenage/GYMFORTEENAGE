import Foundation

enum AIConfiguration {
    static let modelID = "gemini-3.1-flash-lite"
    static let apiBaseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!
    static let requestTimeout: TimeInterval = 30
    static let resourceTimeout: TimeInterval = 60
    static let maximumAPIKeyLength = 4096
    static let maximumPromptCharacters = 16_000
    static let maximumResponseBytes = 256_000

    static var generateContentURL: URL {
        apiBaseURL.appendingPathComponent("\(modelID):generateContent")
    }
}
