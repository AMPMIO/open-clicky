//
//  KeychainHelper.swift
//  leanring-buddy
//
//  Small wrapper around the macOS Keychain for storing user-provided secrets
//  (like a bring-your-own OpenRouter API key). We use the Keychain rather than
//  UserDefaults so the key isn't written to a plist in plaintext on disk.
//

import Foundation
import Security

/// Stores and retrieves small string secrets in the login Keychain.
/// Each secret is keyed by an account string scoped to this app's service.
final class KeychainHelper {
    static let shared = KeychainHelper()

    /// Service identifier used to namespace all Open Clicky secrets in the Keychain.
    private let keychainServiceName = "com.openclicky.secrets"

    private init() {}

    /// Stores a string secret under the given account key, replacing any existing value.
    /// Passing an empty string deletes the stored secret instead.
    func setString(_ secretValue: String, forKey accountKey: String) {
        let trimmedSecretValue = secretValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSecretValue.isEmpty else {
            deleteString(forKey: accountKey)
            return
        }

        guard let secretData = trimmedSecretValue.data(using: .utf8) else { return }

        // Delete any existing item first so we always write a fresh value.
        deleteString(forKey: accountKey)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: accountKey,
            kSecValueData as String: secretData,
            // Only readable while the device is unlocked; never synced to iCloud.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        SecItemAdd(addQuery as CFDictionary, nil)
    }

    /// Reads the string secret stored under the given account key, or nil if none exists.
    func readString(forKey accountKey: String) -> String? {
        let readQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: accountKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var matchedItem: CFTypeRef?
        let readStatus = SecItemCopyMatching(readQuery as CFDictionary, &matchedItem)

        guard readStatus == errSecSuccess,
              let secretData = matchedItem as? Data,
              let secretValue = String(data: secretData, encoding: .utf8) else {
            return nil
        }

        return secretValue
    }

    /// Removes the secret stored under the given account key, if present.
    func deleteString(forKey accountKey: String) {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: accountKey
        ]

        SecItemDelete(deleteQuery as CFDictionary)
    }
}
