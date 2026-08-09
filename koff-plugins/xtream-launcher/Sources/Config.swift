import Foundation
import Security

struct XtreamConfig {
    let server: String
    let username: String

    enum LoadError: Error { case plistUnreadable, missingKeys }

    /// Préférences du plugin IINA si présentes (machine principale).
    static var defaultPlistPath: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.koff.iina.debug/plugins/.preferences/com.koff.iina.xtream-player.plist").path
    }

    /// Config propre au lanceur (machine sans plugin IINA). Jamais de mot de passe ici.
    static var ownConfigURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.koff.iina.xtream-launcher/config.json")
    }

    init?(dict: [String: Any]) {
        guard let serverRaw = dict["server"] as? String,
              let usernameRaw = dict["username"] as? String else { return nil }
        var server = serverRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        while server.hasSuffix("/") { server.removeLast() }
        let username = usernameRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty,
              server.lowercased().hasPrefix("http://") || server.lowercased().hasPrefix("https://") else { return nil }
        self.server = server
        self.username = username
    }

    static func load(path: String = defaultPlistPath) throws -> XtreamConfig {
        if let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let cfg = XtreamConfig(dict: dict) { return cfg }
        if let cfg = readJSON(from: ownConfigURL) { return cfg }
        throw LoadError.plistUnreadable
    }

    static func readJSON(from url: URL) -> XtreamConfig? {
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return XtreamConfig(dict: dict)
    }

    static func writeJSON(server: String, username: String, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: ["server": server, "username": username],
                                              options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    static func save(server: String, username: String) throws {
        try writeJSON(server: server, username: username, to: ownConfigURL)
    }
}

enum KeychainStore {
    enum KError: Error { case notFound, unexpected(OSStatus) }

    /// Jamais de log du secret : seul l'appelant garde le mot de passe en mémoire.
    static func loadPassword(username: String) throws -> String {
        if let p = try find(service: "com.koff.iina.xtream-player - xtream-credentials", account: username) { return p }
        if let p = try find(service: "xtream-credentials", account: username) { return p }
        if let p = try find(service: "xtream-credentials", account: nil) { return p }
        throw KError.notFound
    }

    /// Écrit le mot de passe sous le service partagé avec le plugin IINA.
    /// Jamais de log du secret.
    static func save(username: String, password: String) throws {
        let service = "com.koff.iina.xtream-player - xtream-credentials"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username,
        ]
        let data = Data(password.utf8)
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        let final: OSStatus
        if status == errSecSuccess {
            final = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            final = SecItemAdd(add as CFDictionary, nil)
        } else {
            final = status
        }
        guard final == errSecSuccess else { throw KError.unexpected(final) }
    }

    private static func find(service: String, account: String?) throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let account { query[kSecAttrAccount as String] = account }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KError.unexpected(status) }
        guard let data = item as? Data,
              let s = String(data: data, encoding: .utf8),
              !s.isEmpty else { throw KError.unexpected(errSecDecode) }
        return s
    }
}
