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
        case anthropicAPIKey = "anthropic_api_key"
        case googleAIAPIKey = "google_ai_api_key"
        case licenseKey = "license_key"
        case licenseValidatedAt = "license_validated_at"
        case trialStartDate = "trial_start_date"
    }

    /// Call once at app startup to load all Keychain entries with a single prompt.
    static func preload() {
        cache.ensureLoaded {
            var result: [String: String] = [:]
            // Load main credentials
            let all = loadAllFromKeychain()
            for (k, v) in all {
                result[k] = v
            }
            return result
        }
        // Also pre-warm raw account cache (e.g. statement passwords)
        _ = loadRaw(account: StatementPassword.keychainAccount)
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
        // Single Keychain read loads all keys into cache (locked to prevent concurrent reads)
        cache.ensureLoaded {
            loadAllFromKeychain()
        }
        return cache.get(key: key)
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
        // Check cache first
        let cached = cache.getAllCredentials()
        if !cached.isEmpty { return cached }

        // Fall through to Keychain
        let all = loadAllFromKeychain()
        for (k, v) in all {
            if let enumKey = Key(rawValue: k) {
                cache.set(key: enumKey, value: v)
            }
        }
        return all
    }

    /// Direct Keychain read without cache — only call from preload/ensureLoaded.
    private static func loadAllFromKeychain() -> [String: String] {
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

    // MARK: - Raw Account Storage

    static func loadRaw(account: String) -> String? {
        // Check raw cache first
        if let cached = cache.getRaw(account: account) {
            return cached
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else {
            cache.setRaw(account: account, value: "")
            return nil
        }
        cache.setRaw(account: account, value: str)
        return str
    }

    static func saveRaw(account: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { return }
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "KeychainService", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Keychain save failed: \(status)"])
        }
        cache.setRaw(account: account, value: value)
    }

    static func deleteRaw(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        cache.removeRaw(account: account)
    }

    // MARK: - Per-Endpoint API Key Storage

    static func saveEndpointAPIKey(endpointId: UUID, value: String) throws {
        try saveRaw(account: "endpoint_\(endpointId.uuidString)", value: value)
    }

    static func loadEndpointAPIKey(endpointId: UUID) -> String? {
        loadRaw(account: "endpoint_\(endpointId.uuidString)")
    }

    static func deleteEndpointAPIKey(endpointId: UUID) {
        deleteRaw(account: "endpoint_\(endpointId.uuidString)")
    }
}

// Thread-safe in-memory cache using manual locking
private final class CredentialCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]
    private var rawStorage: [String: String] = [:]
    private var credentialsLoaded = false

    /// Load credentials exactly once. Concurrent callers block until the first finishes.
    func ensureLoaded(_ loader: () -> [String: String]) {
        lock.lock()
        if credentialsLoaded {
            lock.unlock()
            return
        }
        // Release lock during Keychain I/O would allow races, so keep it held.
        // Keychain reads are fast; the prompt is the slow part but only happens once.
        let all = loader()
        for (k, v) in all {
            storage[k] = v
        }
        credentialsLoaded = true
        lock.unlock()
    }

    func get(key: KeychainService.Key) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key.rawValue]
    }

    func getAllCredentials() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        guard credentialsLoaded else { return [:] }
        return storage
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

    func getRaw(account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let val = rawStorage[account] else { return nil }
        return val.isEmpty ? nil : val
    }

    func setRaw(account: String, value: String) {
        lock.lock()
        defer { lock.unlock() }
        rawStorage[account] = value
    }

    func removeRaw(account: String) {
        lock.lock()
        defer { lock.unlock() }
        rawStorage.removeValue(forKey: account)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
        rawStorage.removeAll()
        credentialsLoaded = false
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
