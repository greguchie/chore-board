import Foundation
import Security

@MainActor
final class KeychainTokenStore: TokenStore {
    private let service: String
    private let account = "auth-tokens"

    nonisolated init(service: String = Bundle.main.bundleIdentifier ?? "com.greguchie.ChoreBoard") {        self.service = service
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func load() -> StoredTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(StoredTokens.self, from: data)
    }

    func save(_ tokens: StoredTokens) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(tokens),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        // Update the existing item; if there isn't one yet, add it.
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let addStatus = SecItemAdd(baseQuery.merging(attributes) { $1 } as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    func clear() {
        _ = SecItemDelete(baseQuery as CFDictionary)
    }

    /// iOS keeps Keychain items even after the app is deleted. Without this,
    /// reinstalling the app would silently log back in to the old account.
    static func clearIfFreshInstall(defaults: UserDefaults = .standard) {
        let key = "hasLaunchedBefore"
        guard !defaults.bool(forKey: key) else { return }
        KeychainTokenStore().clear()
        defaults.set(true, forKey: key)
    }
}

nonisolated struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "Couldn't save your login securely (Keychain error \(status))." }
}
