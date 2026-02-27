import Foundation
import Security

enum KeychainService: Sendable {
    private static let serviceName = "com.ledgeit.app"
    private static let accountName = "credentials"

    // In-memory cache to avoid repeated Keychain reads (and repeated auth prompts)
    private static let cache = CredentialCache()

    enum Key: String, Sendable, CaseIterable {
        case openRouterAPIKey = "openrouter_api_key"
        case googleClientID = "google_client_id"
        case googleClientSecret = "google_client_secret"
        case googleAccessToken = "google_access_token"
        case googleRefreshToken = "google_refresh_token"
        case supabaseURL = "supabase_url"
        case supabaseAnonKey = "supabase_anon_key"
    }

    static func save(key: Key, value: String) throws {
        var all = loadAll()
        all[key.rawValue] = value
        try saveAll(all)
        cache.set(key: key, value: value)
    }

    static func load(key: Key) -> String? {
        // Return from cache if available
        if let cached = cache.get(key: key) {
            return cached
        }
        // Single Keychain read loads all keys into cache
        let all = loadAll()
        for (k, v) in all {
            if let enumKey = Key(rawValue: k) {
                cache.set(key: enumKey, value: v)
            }
        }
        return all[key.rawValue]
    }

    static func delete(key: Key) {
        var all = loadAll()
        all.removeValue(forKey: key.rawValue)
        try? saveAll(all)
        cache.remove(key: key)
    }

    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
        ]
        SecItemDelete(query as CFDictionary)
        cache.clear()

        // Also clean up legacy per-key items from old format
        for key in Key.allCases {
            let legacyQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: key.rawValue,
            ]
            SecItemDelete(legacyQuery as CFDictionary)
        }
    }

    // MARK: - Private (single Keychain entry as JSON)

    private static func loadAll() -> [String: String] {
        // Try new consolidated format first
        if let dict = loadRawDict(account: accountName) {
            return dict
        }

        // Migrate from legacy per-key format
        var migrated: [String: String] = [:]
        for key in Key.allCases {
            if let val = loadLegacy(key: key) {
                migrated[key.rawValue] = val
            }
        }
        if !migrated.isEmpty {
            try? saveAll(migrated)
            // Clean up legacy items
            for key in Key.allCases {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: serviceName,
                    kSecAttrAccount as String: key.rawValue,
                ]
                SecItemDelete(query as CFDictionary)
            }
        }
        return migrated
    }

    private static func saveAll(_ dict: [String: String]) throws {
        guard let data = try? JSONEncoder().encode(dict) else {
            throw KeychainError.saveFailed(errSecParam)
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
        ]

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private static func loadRawDict(account: String) -> [String: String]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return dict
    }

    private static func loadLegacy(key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

// Thread-safe in-memory cache using actor-like manual locking
private final class CredentialCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    func get(key: KeychainService.Key) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key.rawValue]
    }

    func set(key: KeychainService.Key, value: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[key.rawValue] = value
    }

    func remove(key: KeychainService.Key) {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key.rawValue)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Keychain save failed with status: \(status)"
        }
    }
}
