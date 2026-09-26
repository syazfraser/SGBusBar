import Foundation
import Security

/// Stores the LTA DataMall key in the login keychain.
enum Keychain {
    private static let service = "SGBusBar"
    private static let account = "LTA DataMall AccountKey"

    static func apiKey() -> String? {
        read(service: service)
    }

    @discardableResult
    static func setAPIKey(_ key: String) -> Bool {
        SecItemDelete(query(service: service) as CFDictionary)
        var item = query(service: service)
        item[kSecValueData as String] = Data(key.utf8)
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private static func read(service: String) -> String? {
        var query = query(service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func query(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
