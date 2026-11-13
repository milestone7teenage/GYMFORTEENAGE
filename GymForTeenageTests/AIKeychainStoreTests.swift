import XCTest
@testable import GymForTeenage

final class AIKeychainStoreTests: XCTestCase {
    func testMissingKeyAndSaveRetrieveReplaceDelete() throws {
        let store = AIKeychainStore(service: "com.gymforteenage.tests.\(UUID().uuidString)")
        defer { try? store.deleteKey() }

        XCTAssertFalse(try store.containsKey())
        XCTAssertNil(try store.retrieveKey())

        try store.save(key: "test-key-one")
        XCTAssertTrue(try store.containsKey())
        XCTAssertEqual(try store.retrieveKey(), "test-key-one")

        try store.save(key: "test-key-two")
        XCTAssertEqual(try store.retrieveKey(), "test-key-two")

        try store.deleteKey()
        XCTAssertFalse(try store.containsKey())
        XCTAssertNil(try store.retrieveKey())
    }

    func testEmptyKeyIsRejected() {
        let store = AIKeychainStore(service: "com.gymforteenage.tests.\(UUID().uuidString)")
        XCTAssertThrowsError(try store.save(key: "  \n")) { error in
            XCTAssertEqual(error as? AIKeychainError, .emptyKey)
        }
    }

    func testKeychainFailureCanBePresentedWithoutSecret() {
        let store = FailingAIKeyStore()
        XCTAssertThrowsError(try store.save(key: "never-log-this")) { error in
            XCTAssertEqual(error as? AIKeychainError, .operationFailed(status: -1))
            XCTAssertFalse((error as? AIKeychainError)?.userMessage.contains("never-log-this") ?? true)
        }
    }

    @MainActor
    func testBackupDoesNotContainKeyOrAISettings() throws {
        let secret = "isolated-test-secret-\(UUID().uuidString)"
        let keyStore = AIKeychainStore(service: "com.gymforteenage.tests.backup.\(UUID().uuidString)")
        try keyStore.save(key: secret)
        defer {
            do {
                try keyStore.deleteKey()
            } catch {
                XCTFail("Failed to remove isolated Keychain test item: \(error)")
            }
        }

        let localURL = FileManager.default.temporaryDirectory.appendingPathComponent("ai-backup-store-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: localURL) }
        let store = Store(fileURL: localURL)
        let exportedURL = try XCTUnwrap(store.export())
        defer { try? FileManager.default.removeItem(at: exportedURL) }
        let data = try Data(contentsOf: exportedURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let decodedBackup = try JSONDecoder.iso.decode(Backup.self, from: data)
        let requiredBackupFields: Set<String> = [
            "formatIdentifier", "version", "records", "measures", "water",
            "instructions", "reminders", "creatineLog", "creatineReminder", "creatineHour"
        ]
        let serializedFields = Set(json.keys)
        let optionalBackupFields: Set<String> = ["session"]
        XCTAssertTrue(requiredBackupFields.isSubset(of: serializedFields))
        XCTAssertTrue(serializedFields.isSubset(of: requiredBackupFields.union(optionalBackupFields)))
        XCTAssertEqual(decodedBackup.version, 1)
        XCTAssertEqual(recursivelyForbiddenJSONPaths(in: json, secret: secret), [])
        XCTAssertEqual(try keyStore.retrieveKey(), secret)
    }

    func testRecursiveBackupFieldCheckFindsForbiddenNamesInNestedObjectsAndArrays() {
        let artificialJSON: [String: Any] = [
            "outer": [
                "aiCoachEnabled": true,
                "test-secret-as-key": "placeholder",
                "items": [
                    ["AI_Consent": true],
                    ["api-key": "fake-key", "GeminiModel": "test-model"]
                ]
            ]
        ]

        let violations = recursivelyForbiddenJSONPaths(in: artificialJSON, secret: "test-secret")
        XCTAssertEqual(Set(violations), [
            "$.outer.aiCoachEnabled",
            "$.outer.[redacted-key]",
            "$.outer.items[0].AI_Consent",
            "$.outer.items[1].api-key",
            "$.outer.items[1].GeminiModel"
        ])
    }

    private func recursivelyForbiddenJSONPaths(in value: Any, path: String = "$", secret: String) -> [String] {
        if let dictionary = value as? [String: Any] {
            return dictionary.flatMap { entry -> [String] in
                let key = entry.key
                let nestedValue = entry.value
                let childPath = "\(path).\(key)"
                let keyContainsSecret = key.localizedCaseInsensitiveContains(secret)
                let safeChildPath = keyContainsSecret ? "\(path).[redacted-key]" : childPath
                let normalizedKey = key.lowercased().filter { $0.isLetter || $0.isNumber }
                let forbiddenName = normalizedKey.hasPrefix("ai")
                    || ["apikey", "gemini", "keychain"]
                    .contains { normalizedKey.contains($0) }
                return ((forbiddenName || keyContainsSecret) ? [safeChildPath] : [])
                    + recursivelyForbiddenJSONPaths(in: nestedValue, path: safeChildPath, secret: secret)
            }
        }
        if let array = value as? [Any] {
            return array.enumerated().flatMap { entry in
                recursivelyForbiddenJSONPaths(in: entry.element, path: "\(path)[\(entry.offset)]", secret: secret)
            }
        }
        if let string = value as? String, string.contains(secret) {
            return [path]
        }
        return []
    }
}

private final class FailingAIKeyStore: AIKeyStore {
    func containsKey() throws -> Bool { throw AIKeychainError.operationFailed(status: -1) }
    func save(key: String) throws { throw AIKeychainError.operationFailed(status: -1) }
    func retrieveKey() throws -> String? { throw AIKeychainError.operationFailed(status: -1) }
    func deleteKey() throws { throw AIKeychainError.operationFailed(status: -1) }
}
