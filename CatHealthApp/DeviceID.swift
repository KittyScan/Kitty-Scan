import Foundation
import Security

/// Stable, anonymous device ID used by the Worker proxy for rate limiting.
/// Persists in Keychain (survives app reinstall on some devices, but not a fresh iCloud restore on a new device — which is fine).
enum DeviceID {
    private static let service = "app.carmel.cathealth"
    private static let account = "device-id"

    /// Lazy-computed singleton: first access generates (or loads) the UUID.
    static let current: String = {
        if let existing = Keychain.load(service: service, account: account), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString.lowercased()
        Keychain.save(value: generated, service: service, account: account)
        return generated
    }()
}

/// Minimal Keychain wrapper for string values.
enum Keychain {
    @discardableResult
    static func save(value: String, service: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let baseQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(baseQuery as CFDictionary)

        var addQuery = baseQuery
        addQuery[kSecValueData as String]       = data
        addQuery[kSecAttrAccessible as String]  = kSecAttrAccessibleAfterFirstUnlock

        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    static func load(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    @discardableResult
    static func delete(service: String, account: String) -> Bool {
        let q: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(q as CFDictionary) == errSecSuccess
    }
}
