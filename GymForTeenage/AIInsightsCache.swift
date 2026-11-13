import Foundation

struct AIInsightsCache {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = support
                .appendingPathComponent("AIInsights", isDirectory: true)
                .appendingPathComponent("insights-cache-v1.json", isDirectory: false)
        }
    }

    func load() -> AIInsightsCacheEnvelope? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(AIInsightsCacheEnvelope.self, from: data),
              envelope.schemaVersion == AIInsights.currentSchemaVersion,
              envelope.insights.schemaVersion == AIInsights.currentSchemaVersion,
              AIInsightsValidator.validateCached(envelope.insights) else { return nil }
        return envelope
    }

    func save(_ envelope: AIInsightsCacheEnvelope) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var excludedURL = directory
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        try? excludedURL.setResourceValues(excluded)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)
        try data.write(to: fileURL, options: .atomic)
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}
