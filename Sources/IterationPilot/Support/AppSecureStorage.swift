import Foundation
import Security

enum AppSecureStorage {
    enum PersistenceError: LocalizedError {
        case writeFailed(service: String, account: String)

        var errorDescription: String? {
            switch self {
            case .writeFailed(let service, let account):
                return "无法将凭据写入钥匙串（service: \(service), account: \(account)）"
            }
        }
    }

    private static let fallbackLock = NSLock()
    private static var fallbackPasswords: [String: String] = [:]

    @discardableResult
    static func storePassword(_ password: String, service: String, account: String) -> Bool {
        let normalized = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return deletePassword(service: service, account: account)
        }

        let data = Data(normalized.utf8)
        let query = baseQuery(service: service, account: account)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess {
            removeFallback(service: service, account: account)
            return true
        }

        guard updateStatus == errSecItemNotFound else {
            setFallback(normalized, service: service, account: account)
            return false
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            removeFallback(service: service, account: account)
            return true
        }
        setFallback(normalized, service: service, account: account)
        return false
    }

    static func password(service: String, account: String) -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = kCFBooleanTrue

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess,
           let data = item as? Data,
           let password = String(data: data, encoding: .utf8),
           !password.isEmpty {
            return password
        }
        return fallbackPassword(service: service, account: account)
    }

    static func persistPassword(_ password: String, service: String, account: String) throws {
        guard storePassword(password, service: service, account: account) else {
            throw PersistenceError.writeFailed(service: service, account: account)
        }
    }

    @discardableResult
    static func deletePassword(service: String, account: String) -> Bool {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        removeFallback(service: service, account: account)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static func secret(legacyPlaintext: String, service: String, account: String) throws -> String {
        let trimmed = legacyPlaintext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            try persistPassword(trimmed, service: service, account: account)
            return legacyPlaintext
        }
        return password(service: service, account: account) ?? ""
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: effectiveService(service),
            kSecAttrAccount as String: account
        ]
    }

    private static func effectiveService(_ service: String) -> String {
        guard let namespace = ProcessInfo.processInfo.environment["NEXAFLOW_SECURE_STORAGE_NAMESPACE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !namespace.isEmpty else {
            return service
        }
        return "\(service).\(namespace)"
    }

    private static func fallbackKey(service: String, account: String) -> String {
        "\(effectiveService(service))\u{1f}\(account)"
    }

    private static func setFallback(_ password: String, service: String, account: String) {
        fallbackLock.lock()
        fallbackPasswords[fallbackKey(service: service, account: account)] = password
        fallbackLock.unlock()
    }

    private static func removeFallback(service: String, account: String) {
        fallbackLock.lock()
        fallbackPasswords.removeValue(forKey: fallbackKey(service: service, account: account))
        fallbackLock.unlock()
    }

    private static func fallbackPassword(service: String, account: String) -> String? {
        fallbackLock.lock()
        let password = fallbackPasswords[fallbackKey(service: service, account: account)]
        fallbackLock.unlock()
        return password
    }
}
