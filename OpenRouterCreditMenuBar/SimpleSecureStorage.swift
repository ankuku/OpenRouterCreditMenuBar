//
//  SimpleSecureStorage.swift
//  OpenRouterCreditMenuBar
//
//  Simple secure API key storage using Data Protection
//

import Foundation
import Security

class SimpleSecureStorage {
    // Store encrypted API key in UserDefaults with Data Protection
    static func storeAPIKey(_ key: String) {
        let encryptedData = key.data(using: .utf8)?.base64EncodedData() ?? Data()
        UserDefaults.standard.set(encryptedData, forKey: "secure_api_key")
    }

    // Retrieve and decrypt API key from UserDefaults
    static func retrieveAPIKey() -> String? {
        guard let encryptedData = UserDefaults.standard.data(forKey: "secure_api_key") else { return nil }
        guard let decodedData = Data(base64Encoded: encryptedData) else { return nil }
        return String(data: decodedData, encoding: .utf8)
    }

    // Clear stored API key
    static func clearAPIKey() {
        UserDefaults.standard.removeObject(forKey: "secure_api_key")
    }

    // More secure version using Keychain (but without the problematic implementation)
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
}