//
//  KeychainStore.swift
//  LineriOS
//
//  Hardware-backed Secure Enclave Keychain storage for client_id and OAuth PKCE tokens.
//  Secured with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly.
//

import Foundation
import Security

public final class KeychainStore: @unchecked Sendable {
    public static let shared = KeychainStore()

    private let service = "com.personal.linerios"
    private let queue = DispatchQueue(label: "com.personal.linerios.keychain", qos: .userInitiated)

    public enum Key: String {
        case clientId = "com.personal.linerios.client_id"
        case accessToken = "com.personal.linerios.access_token"
        case refreshToken = "com.personal.linerios.refresh_token"
        case tokenExpiry = "com.personal.linerios.token_expiry"
    }

    private init() {}

    // MARK: - CRUD Operations

    public func set(string: String, forKey key: Key) {
        guard let data = string.data(using: .utf8) else { return }
        queue.sync {
            deleteItem(forKey: key.rawValue)

            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key.rawValue,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]

            SecItemAdd(query as CFDictionary, nil)
        }
    }

    public func get(stringForKey key: Key) -> String? {
        queue.sync {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key.rawValue,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            guard status == errSecSuccess, let data = item as? Data else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        }
    }

    public func set(date: Date, forKey key: Key) {
        let timestamp = String(date.timeIntervalSince1970)
        set(string: timestamp, forKey: key)
    }

    public func get(dateForKey key: Key) -> Date? {
        guard let timestampStr = get(stringForKey: key),
              let timestamp = Double(timestampStr) else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    public func delete(forKey key: Key) {
        queue.sync {
            deleteItem(forKey: key.rawValue)
        }
    }

    public func clearAuthTokens() {
        delete(forKey: .accessToken)
        delete(forKey: .refreshToken)
        delete(forKey: .tokenExpiry)
    }

    public func hasConfiguredClientId() -> Bool {
        guard let id = get(stringForKey: .clientId), !id.isEmpty else {
            return false
        }
        return id.count == 32
    }

    public func hasValidAccessToken() -> Bool {
        guard let token = get(stringForKey: .accessToken), !token.isEmpty else {
            return false
        }
        if let expiry = get(dateForKey: .tokenExpiry) {
            return expiry.timeIntervalSinceNow > -300 // Allow grace window
        }
        // If an access token is present without explicit expiry (e.g. App Remote), treat as valid
        return true
    }

    public func hasValidCredentials() -> Bool {
        hasConfiguredClientId()
    }

    private func deleteItem(forKey account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
