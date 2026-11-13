import Foundation
import Security

protocol AIKeyStore: AnyObject {
    func containsKey() throws -> Bool
    func save(key: String) throws
    func retrieveKey() throws -> String?
    func deleteKey() throws
}

enum AIKeychainError: Error, Equatable {
    case emptyKey
    case keyTooLong
    case invalidStoredValue
    case operationFailed(status: OSStatus)

    var userMessage: String {
        switch self {
        case .emptyKey: return "Введите API-ключ."
        case .keyTooLong: return "API-ключ превышает допустимую длину."
        case .invalidStoredValue: return "Сохранённый ключ повреждён. Удалите его и сохраните заново."
        case .operationFailed: return "Не удалось выполнить операцию с защищённым хранилищем."
        }
    }
}

final class AIKeychainStore: AIKeyStore {
    private let service: String
    private let account: String

    init(service: String = Bundle.main.bundleIdentifier ?? "com.gymforteenage.app",
         account: String = "gemini-api-key") {
        self.service = service
        self.account = account
    }

    func containsKey() throws -> Bool {
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess { return true }
        if status == errSecItemNotFound { return false }
        throw AIKeychainError.operationFailed(status: status)
    }

    func save(key: String) throws {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw AIKeychainError.emptyKey }
        guard normalized.count <= AIConfiguration.maximumAPIKeyLength,
              let data = normalized.data(using: .utf8) else { throw AIKeychainError.keyTooLong }

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus == errSecSuccess { return }
        guard addStatus == errSecDuplicateItem else {
            throw AIKeychainError.operationFailed(status: addStatus)
        }

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary)
        guard updateStatus == errSecSuccess else {
            throw AIKeychainError.operationFailed(status: updateStatus)
        }
    }

    func retrieveKey() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AIKeychainError.operationFailed(status: status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw AIKeychainError.invalidStoredValue
        }
        return value
    }

    func deleteKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AIKeychainError.operationFailed(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
