//
//  SimpleSecureStorage.swift
//  OpenRouterCreditMenuBar
//
//  Simple secure API key storage using Data Protection
//

import Foundation
import Security

class SimpleSecureStorage {
    // More secure version using Keychain
    static func storeAPIKeySecurely(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "OpenRouterCreditMenuBar",
            kSecAttrAccount as String: "api_key",
            kSecValueData as String: key.data(using: .utf8) as Any,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func retrieveAPIKeySecurely() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "OpenRouterCreditMenuBar",
            kSecAttrAccount as String: "api_key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func clearAPIKeySecurely() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "OpenRouterCreditMenuBar",
            kSecAttrAccount as String: "api_key"
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Multiple Keys Support

    static func storeAPIKeyEntriesSecurely(_ entries: [APIKeyEntry]) -> Bool {
        guard let data = try? JSONEncoder().encode(entries) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "OpenRouterCreditMenuBar",
            kSecAttrAccount as String: "api_key_entries",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func retrieveAPIKeyEntriesSecurely() -> [APIKeyEntry] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "OpenRouterCreditMenuBar",
            kSecAttrAccount as String: "api_key_entries",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data,
              let entries = try? JSONDecoder().decode([APIKeyEntry].self, from: data) else {
            return []
        }
        return entries
    }
}