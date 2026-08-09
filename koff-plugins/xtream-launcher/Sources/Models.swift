import Foundation

enum MediaKind: String, Codable {
    case tv, movie, series, episode

    var badge: String {
        switch self {
        case .tv: return "TV"
        case .movie: return "FILM"
        case .series: return "SÉRIE"
        case .episode: return "ÉP"
        }
    }
}

struct MediaItem: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let ext: String?
    let kind: MediaKind
    let icon: String?
}

struct EpisodeItem: Identifiable, Hashable, Codable {
    let id: String
    let num: Int
    let title: String
    let ext: String
    let image: String?
}

enum Sanitizer {
    static let maxEntriesPerCatalog = 50_000

    /// Retire les caractères de contrôle/illégaux ; rejette (nil) si le nom devient vide.
    static func cleanName(_ raw: Any?) -> String? {
        guard let s = raw as? String else { return nil }
        let filtered = String(s.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && !CharacterSet.illegalCharacters.contains($0)
        })
        let t = filtered.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static func cleanExt(_ raw: Any?) -> String? {
        guard let s = raw as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty, t.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return t
    }

    /// URL de vignette http(s) uniquement, jamais d'identifiants embarqués
    /// (l'URL est persistée dans le cache disque).
    static func cleanIcon(_ raw: Any?) -> String? {
        guard let s = raw as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > 8, t.count <= 2048 else { return nil }
        let l = t.lowercased()
        guard l.hasPrefix("http://") || l.hasPrefix("https://") else { return nil }
        guard !l.contains("username=") && !l.contains("password=") else { return nil }
        return t
    }

    static func stringID(_ raw: Any?) -> String? {
        if let n = raw as? NSNumber { return n.stringValue }
        if let s = raw as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        return nil
    }

    static func intValue(_ raw: Any?) -> Int? {
        if let n = raw as? NSNumber { return n.intValue }
        if let s = raw as? String { return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }
}
