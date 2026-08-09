import Foundation

enum URLBuilder {
    /// Encodage strict (unreserved) pour les segments de chemin.
    static func pathEnc(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    static func playback(server: String, username: String, password: String, kind: MediaKind, id: String, ext: String?) -> String {
        let u = pathEnc(username)
        let p = pathEnc(password)
        let i = pathEnc(id)
        switch kind {
        case .tv:
            return "\(server)/live/\(u)/\(p)/\(i).ts"
        case .movie:
            return "\(server)/movie/\(u)/\(p)/\(i).\(ext ?? "mp4")"
        case .series, .episode:
            return "\(server)/series/\(u)/\(p)/\(i).\(ext ?? "mp4")"
        }
    }

    static func iina(playbackURL: String) -> URL? {
        var c = URLComponents()
        c.scheme = "iina"
        c.host = "open"
        c.queryItems = [
            URLQueryItem(name: "url", value: playbackURL),
            URLQueryItem(name: "new_window", value: "0")
        ]
        return c.url
    }
}
