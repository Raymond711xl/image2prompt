import Foundation
import Security

/// API key 存 Keychain，不存 UserDefaults。
///
/// UserDefaults 是明文 plist，任何进程都能读。key 是能花钱的凭证，必须进 Keychain。
public enum Keychain {
    public static let service = AppIdentity.bundleID

    public static func set(_ value: String?, for account: String) {
        // 先删后写：SecItemUpdate 在条目不存在时会失败，两步走最省事
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(insert as CFDictionary, nil)
    }

    public static func get(_ account: String) -> String? {
        if let value = read(account, from: service) { return value }

        // 改名前存的 key 还在老 service 名下。读到就顺手挪到新的，下次不必再回头找。
        guard let legacy = read(account, from: AppIdentity.legacyBundleID) else { return nil }
        set(legacy, for: account)
        return legacy
    }

    private static func read(_ account: String, from service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
            let data = out as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
