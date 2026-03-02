import Foundation

struct StatementPassword: Codable, Identifiable, Sendable {
    var id: String = UUID().uuidString
    var bankName: String
    var cardLabel: String
    var password: String

    static let keychainAccount = "statement_passwords"

    static func loadAll() -> [StatementPassword] {
        guard let json = KeychainService.loadRaw(account: StatementPassword.keychainAccount),
              let data = json.data(using: .utf8),
              let passwords = try? JSONDecoder().decode([StatementPassword].self, from: data) else {
            return []
        }
        return passwords
    }

    static func saveAll(_ passwords: [StatementPassword]) throws {
        let data = try JSONEncoder().encode(passwords)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "StatementPassword", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode passwords"])
        }
        try KeychainService.saveRaw(account: StatementPassword.keychainAccount, value: json)
    }
}
