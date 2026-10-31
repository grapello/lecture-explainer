//
//  KeychainStore.swift
//  Lexia
//

import Foundation
import Security

/// Stores small secrets (the Anthropic API key) in the iOS Keychain.
///
/// Why not UserDefaults or SwiftData: those are plain files inside the app's
/// container and end up in backups as-is. The Keychain is encrypted by the system,
/// and with `…ThisDeviceOnly` the key never leaves this device: not in iCloud
/// Keychain, not in a backup restored to another phone.
///
/// The Keychain API is an old C-style API: you describe an item with a dictionary
/// of kSec… keys and get back an OSStatus code (errSecSuccess = 0 means OK).
enum KeychainStore {
    // The app's old name. Kept after the rename to Lexia: a different service name
    // would no longer find keys that are already saved.
    static let service = "Lecture-Explainer"
    static let apiKeyAccount = "anthropic-api-key"

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "Keychain error \(status): " + (SecCopyErrorMessageString(status, nil) as String? ?? "unknown")
        }
    }

    /// The dictionary that identifies one item: a "generic password" for this app and account.
    private static func query(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// Saves (or replaces) a value.
    static func save(_ value: String, account: String = apiKeyAccount) throws {
        // Delete first so saving twice replaces the value instead of failing
        // with errSecDuplicateItem.
        SecItemDelete(query(account: account) as CFDictionary)
        var item = query(account: account)
        item[kSecValueData as String] = Data(value.utf8)
        // Readable once the phone has been unlocked after a restart; never synced or migrated.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    /// The saved value, or nil if there is none.
    static func read(account: String = apiKeyAccount) -> String? {
        var request = query(account: account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String = apiKeyAccount) throws {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        // "Not found" counts as success: afterwards there is no key either way.
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
