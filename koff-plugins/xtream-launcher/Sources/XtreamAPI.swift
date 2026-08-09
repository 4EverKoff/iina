import Foundation

enum XtreamParser {
    static func live(_ any: Any) -> [MediaItem] { list(any, kind: .tv, idKey: "stream_id", defaultExt: "ts") }
    static func vod(_ any: Any) -> [MediaItem] { list(any, kind: .movie, idKey: "stream_id", defaultExt: "mp4") }
    static func series(_ any: Any) -> [MediaItem] { list(any, kind: .series, idKey: "series_id", defaultExt: nil) }

    static func list(_ any: Any, kind: MediaKind, idKey: String, defaultExt: String?) -> [MediaItem] {
        guard let arr = any as? [Any] else { return [] }
        var out: [MediaItem] = []
        for entry in arr {
            if out.count >= Sanitizer.maxEntriesPerCatalog { break }
            guard let d = entry as? [String: Any],
                  let id = Sanitizer.stringID(d[idKey]),
                  let name = Sanitizer.cleanName(d["name"]) else { continue }
            let ext = Sanitizer.cleanExt(d["container_extension"]) ?? defaultExt
            let icon = Sanitizer.cleanIcon(d["stream_icon"]) ?? Sanitizer.cleanIcon(d["cover"])
            out.append(MediaItem(id: id, name: name, ext: ext, kind: kind, icon: icon))
        }
        return out
    }

    static func seriesInfo(_ any: Any) -> [Int: [EpisodeItem]] {
        guard let d = any as? [String: Any],
              let eps = d["episodes"] as? [String: Any] else { return [:] }
        var out: [Int: [EpisodeItem]] = [:]
        var total = 0
        for (key, value) in eps {
            guard let season = Int(key), let arr = value as? [Any] else { continue }
            var items: [EpisodeItem] = []
            for e in arr {
                if total >= Sanitizer.maxEntriesPerCatalog { break }
                guard let ed = e as? [String: Any],
                      let id = Sanitizer.stringID(ed["id"]),
                      let num = Sanitizer.intValue(ed["episode_num"]) else { continue }
                let title = Sanitizer.cleanName(ed["title"]) ?? "Épisode \(num)"
                let ext = Sanitizer.cleanExt(ed["container_extension"]) ?? "mp4"
                let image = Sanitizer.cleanIcon((ed["info"] as? [String: Any])?["movie_image"])
                items.append(EpisodeItem(id: id, num: num, title: title, ext: ext, image: image))
                total += 1
            }
            out[season] = items.sorted { $0.num < $1.num }
        }
        return out
    }
}

struct XtreamClient {
    let server: String
    let username: String
    let password: String

    enum FetchError: Error { case badURL, http(Int), decoding }

    func api(_ action: String, extra: [String: String] = [:]) async throws -> Any {
        guard var comps = URLComponents(string: server + "/player_api.php") else { throw FetchError.badURL }
        var q = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "action", value: action)
        ]
        for (k, v) in extra { q.append(URLQueryItem(name: k, value: v)) }
        comps.queryItems = q
        guard let url = comps.url else { throw FetchError.badURL }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetchError.http(http.statusCode)
        }
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw FetchError.decoding
        }
    }

    func catalog() async throws -> (live: [MediaItem], vod: [MediaItem], series: [MediaItem]) {
        async let l = api("get_live_streams")
        async let v = api("get_vod_streams")
        async let s = api("get_series")
        let (lj, vj, sj) = try await (l, v, s)
        return (XtreamParser.live(lj), XtreamParser.vod(vj), XtreamParser.series(sj))
    }

    func seriesInfo(id: String) async throws -> [Int: [EpisodeItem]] {
        let json = try await api("get_series_info", extra: ["series_id": id])
        return XtreamParser.seriesInfo(json)
    }
}
