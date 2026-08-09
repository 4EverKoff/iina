import Foundation
import AppKit
import Combine

struct RowData: Identifiable {
    let flatIndex: Int
    let label: String
    let kind: MediaKind
    let media: MediaItem?
    let episode: EpisodeItem?
    let season: Int?
    /// Identité basée sur le contenu : deux requêtes différentes réutilisent les
    /// mêmes flatIndex, ce qui figeait l'affichage des lignes (données correctes).
    var id: String {
        if let m = media { return "m-\(m.kind.rawValue)-\(m.id)" }
        if let e = episode { return "e-\(e.id)" }
        if let s = season { return "s-\(s)" }
        return "x-\(flatIndex)"
    }
}

struct SectionData: Identifiable {
    let title: String
    let rows: [RowData]
    var id: String { title }
}

struct DiskCache: Codable {
    var fetchedAt: TimeInterval = 0
    var live: [MediaItem] = []
    var vod: [MediaItem] = []
    var series: [MediaItem] = []
    var seriesInfo: [String: SeriesInfoCache] = [:]
}

struct SeriesInfoCache: Codable {
    var fetchedAt: TimeInterval
    var seasons: [String: [EpisodeItem]]
}

final class CatalogStore: ObservableObject {
    static let cacheTTL: TimeInterval = 300
    static let displayCapPerSection = 100

    @Published var query = "" { didSet { selectionIndex = 0 } }
    @Published var selectionIndex = 0
    @Published var status = "Chargement…"
    @Published var credentialsReady = false
    @Published var needsSetup = false
    @Published var setupServer = ""
    @Published var setupUsername = ""
    @Published private(set) var live: [MediaItem] = []
    @Published private(set) var vod: [MediaItem] = []
    @Published private(set) var series: [MediaItem] = []
    @Published private(set) var drilledSeries: MediaItem?
    @Published private(set) var drilledSeason: Int?
    @Published private(set) var drilledSeasons: [Int: [EpisodeItem]] = [:]

    private var cache = DiskCache()
    private var client: XtreamClient?
    private var server = ""
    private var username = ""
    private var password = ""

    // MARK: Cache disque (ids/noms/extensions uniquement, jamais d'URL ni d'identifiants)

    static var cacheURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("com.koff.iina.xtream-launcher/catalog.json")
    }()

    func loadCacheFromDisk() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let c = try? JSONDecoder().decode(DiskCache.self, from: data) else { return }
        cache = c
        live = c.live
        vod = c.vod
        series = c.series
        xlog("[xtream-launcher] cache disque : tv=\(c.live.count) films=\(c.vod.count) séries=\(c.series.count)")
    }

    func saveCacheToDisk() {
        do {
            let dir = Self.cacheURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(cache)
            try data.write(to: Self.cacheURL, options: .atomic)
        } catch {
            xlog("[xtream-launcher] écriture cache impossible (\(type(of: error)))")
        }
    }

    // MARK: Bootstrap

    func bootstrap(server: String, username: String, password: String) {
        self.server = server
        self.username = username
        self.password = password
        self.client = XtreamClient(server: server, username: username, password: password)
        credentialsReady = true
        loadCacheFromDisk()
        let fresh = Date().timeIntervalSince1970 - cache.fetchedAt < Self.cacheTTL
        if fresh {
            status = ""
        } else {
            status = cache.fetchedAt > 0 ? "" : "Chargement du catalogue…"
            Task { await refreshCatalog() }
        }
    }

    func refreshCatalog() async {
        guard let client else { return }
        do {
            let (l, v, s) = try await client.catalog()
            await MainActor.run {
                live = l
                vod = v
                series = s
                cache.live = l
                cache.vod = v
                cache.series = s
                cache.fetchedAt = Date().timeIntervalSince1970
                saveCacheToDisk()
                status = ""
                xlog("[xtream-launcher] catalogue chargé : tv=\(l.count) films=\(v.count) séries=\(s.count)")
            }
        } catch {
            await MainActor.run { status = "Catalogue indisponible (réseau)" }
            let nserr = error as NSError
            xlog("[xtream-launcher] échec chargement catalogue : \(nserr.domain) code=\(nserr.code)")
        }
    }

    // MARK: Recherche

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private func match(_ item: MediaItem, _ q: String) -> Bool {
        q.isEmpty || Self.fold(item.name).contains(q)
    }

    func sections() -> [SectionData] {
        let q = Self.fold(query)
        let groups: [(String, [MediaItem])] = [("TV", live), ("Films", vod), ("Séries", series)]
        var out: [SectionData] = []
        var idx = 0
        for (title, items) in groups {
            let filtered = items.filter { match($0, q) }.prefix(Self.displayCapPerSection)
            guard !filtered.isEmpty else { continue }
            var rows: [RowData] = []
            for it in filtered {
                rows.append(RowData(flatIndex: idx, label: it.name, kind: it.kind, media: it, episode: nil, season: nil))
                idx += 1
            }
            out.append(SectionData(title: title, rows: rows))
        }
        return out
    }

    /// Niveau intermédiaire : les saisons de la série forée.
    func seasonSections() -> [SectionData] {
        var rows: [RowData] = []
        var idx = 0
        for season in drilledSeasons.keys.sorted() {
            let count = drilledSeasons[season]?.count ?? 0
            guard count > 0 else { continue }
            rows.append(RowData(flatIndex: idx, label: "Saison \(season) — \(count) épisode\(count > 1 ? "s" : "")",
                                kind: .series, media: nil, episode: nil, season: season))
            idx += 1
        }
        return rows.isEmpty ? [] : [SectionData(title: "Saisons", rows: rows)]
    }

    func episodeSections() -> [SectionData] {
        guard let wanted = drilledSeason, let eps = drilledSeasons[wanted], !eps.isEmpty else { return [] }
        var rows: [RowData] = []
        for (idx, ep) in eps.enumerated() {
            rows.append(RowData(flatIndex: idx, label: "Épisode \(ep.num) — \(ep.title)", kind: .episode, media: nil, episode: ep, season: nil))
        }
        return [SectionData(title: "Saison \(wanted)", rows: rows)]
    }

    func completeSetup(server: String, username: String, password: String) {
        guard let cfg = XtreamConfig(dict: ["server": server, "username": username]) else {
            status = "Serveur ou identifiant invalide"
            return
        }
        let pw = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pw.isEmpty else {
            status = "Mot de passe vide"
            return
        }
        do {
            try XtreamConfig.save(server: cfg.server, username: cfg.username)
        } catch {
            xlog("[xtream-launcher] écriture config impossible (\(type(of: error)))")
        }
        do {
            try KeychainStore.save(username: cfg.username, password: pw)
        } catch {
            xlog("[xtream-launcher] écriture trousseau impossible (\(type(of: error)))")
        }
        needsSetup = false
        bootstrap(server: cfg.server, username: cfg.username, password: pw)
    }

    private var currentRows: [RowData] {
        if drilledSeries == nil { return sections().flatMap { $0.rows } }
        if drilledSeason == nil { return seasonSections().flatMap { $0.rows } }
        return episodeSections().flatMap { $0.rows }
    }

    // MARK: Navigation

    func move(_ delta: Int) {
        let n = currentRows.count
        guard n > 0 else { return }
        selectionIndex = max(0, min(n - 1, selectionIndex + delta))
    }

    func back() {
        if drilledSeason != nil {
            drilledSeason = nil
        } else {
            drilledSeries = nil
            drilledSeasons = [:]
        }
        selectionIndex = 0
    }

    func drill(_ item: MediaItem) {
        drilledSeries = item
        drilledSeason = nil
        drilledSeasons = [:]
        selectionIndex = 0
        status = "Chargement des épisodes…"
        if let c = cache.seriesInfo[item.id],
           Date().timeIntervalSince1970 - c.fetchedAt < Self.cacheTTL {
            var m: [Int: [EpisodeItem]] = [:]
            for (k, v) in c.seasons { if let s = Int(k) { m[s] = v } }
            drilledSeasons = m
            status = ""
            xlog("[xtream-launcher] épisodes depuis cache : \(m.values.reduce(0) { $0 + $1.count }) épisodes")
            return
        }
        Task { await loadSeriesInfo(id: item.id) }
    }

    func loadSeriesInfo(id: String) async {
        guard let client else { return }
        do {
            let m = try await client.seriesInfo(id: id)
            let total = m.values.reduce(0) { $0 + $1.count }
            let seasonCount = m.count
            await MainActor.run {
                guard drilledSeries?.id == id else { return }
                drilledSeasons = m
                status = ""
                var sc: [String: [EpisodeItem]] = [:]
                for (k, v) in m { sc[String(k)] = v }
                cache.seriesInfo[id] = SeriesInfoCache(fetchedAt: Date().timeIntervalSince1970, seasons: sc)
                saveCacheToDisk()
                xlog("[xtream-launcher] épisodes chargés : \(total) épisodes, \(seasonCount) saisons")
            }
        } catch {
            await MainActor.run {
                if drilledSeries?.id == id { status = "Épisodes indisponibles (réseau)" }
            }
            let nserr = error as NSError
            xlog("[xtream-launcher] échec épisodes : \(nserr.domain) code=\(nserr.code)")
        }
    }

    // MARK: Ouverture

    func openRow(_ row: RowData) {
        if drilledSeries == nil, let media = row.media, media.kind == .series {
            drill(media)
            return
        }
        if let season = row.season {
            drilledSeason = season
            selectionIndex = 0
            return
        }
        guard client != nil else { return }
        guard let id = row.media?.id ?? row.episode?.id else { return }
        let ext = row.media?.ext ?? row.episode?.ext ?? nil
        let url = URLBuilder.playback(server: server, username: username, password: password,
                                      kind: row.kind, id: id, ext: ext)
        guard let iina = URLBuilder.iina(playbackURL: url) else {
            status = "URL invalide"
            return
        }
        xlog("[xtream-launcher] ouverture dans IINA demandée (type=\(row.kind.rawValue))")
        NSWorkspace.shared.open(iina)
        status = "Envoyé vers IINA — le lanceur reste ouvert"
    }

    func openSelected() {
        let rows = currentRows
        guard selectionIndex >= 0, selectionIndex < rows.count else { return }
        openRow(rows[selectionIndex])
    }

    /// true = événement consommé
    func handleKey(_ keyCode: UInt16) -> Bool {
        if needsSetup { return false } // les champs du formulaire gardent le clavier
        switch keyCode {
        case 126: move(-1); return true          // flèche haut
        case 125: move(1); return true           // flèche bas
        case 36, 76: openSelected(); return true // entrée / pavé num
        case 53:                                 // échap
            if drilledSeason != nil { back(); return true }
            if drilledSeries != nil { back(); return true }
            NSApp.terminate(nil); return true
        default: return false
        }
    }
}
