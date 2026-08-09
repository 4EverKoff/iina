import Foundation

enum SelfTest {
    static func run() -> Int32 {
        var pass = 0
        var fail = 0
        func check(_ cond: Bool, _ name: String) {
            if cond { pass += 1; print("[selftest] PASS \(name)") }
            else { fail += 1; print("[selftest] FAIL \(name)") }
        }
        func parse(_ json: String) -> Any {
            (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as Any
        }

        // MARK: Parsing live

        let live = XtreamParser.live(parse("""
        [
          {"stream_id": 101, "name": "FR| Chaîne Test"},
          {"stream_id": "102", "name": "UK| Other"},
          {"stream_id": 103, "name": "Bad\\u0007Name"},
          {"name": "Sans id"},
          {"stream_id": 104, "name": "\\u0001"},
          {"stream_id": 105}
        ]
        """))
        check(live.count == 3, "live: valides conservés, invalides rejetés")
        check(live.count > 1 && live[0].id == "101" && live[1].id == "102", "live: id int et string normalisés")
        check(live.last?.name == "BadName", "live: caractères de contrôle retirés")
        check(live.first?.ext == "ts", "live: extension par défaut ts")

        // MARK: Parsing vod

        let vod = XtreamParser.vod(parse("""
        [
          {"stream_id": 77, "name": "Film MKV", "container_extension": "mkv"},
          {"stream_id": "78", "name": "Film Sans Ext"},
          {"stream_id": 79, "name": "Film Ext Sale", "container_extension": "m p4!"}
        ]
        """))
        check(vod.count == 3, "vod: 3 entrées parsées")
        check(vod.first?.ext == "mkv", "vod: container_extension respectée")
        check(vod.count > 1 && vod[1].ext == "mp4", "vod: extension par défaut mp4")
        check(vod.last?.ext == "mp4", "vod: extension invalide rejetée vers mp4")

        // MARK: Parsing séries

        let series = XtreamParser.series(parse("""
        [
          {"series_id": 501, "name": "Série A"},
          {"series_id": "502", "name": "Série B"},
          {"series_id": 503}
        ]
        """))
        check(series.count == 2 && series[0].id == "501" && series[1].id == "502", "series: parsing ids")

        // MARK: Parsing series_info (épisodes par saison)

        let info = XtreamParser.seriesInfo(parse("""
        {"seasons": [{"season_number": 1}, {"season_number": 2}],
         "episodes": {
           "1": [
             {"id": "9002", "episode_num": "2"},
             {"id": "9001", "episode_num": 1, "title": "Pilot\\u0002X", "container_extension": "mkv"}
           ],
           "2": [
             {"id": "9010", "episode_num": 1, "title": "Retour", "container_extension": "avi"}
           ]
        }}
        """))
        check(info.count == 2, "series_info: 2 saisons")
        let s1 = info[1] ?? []
        check(s1.count == 2 && s1[0].num == 1 && s1[1].num == 2, "series_info: tri par numéro")
        check(s1.first?.id == "9001" && s1.first?.ext == "mkv", "series_info: épisode 1 id/ext")
        check(s1.first?.title == "PilotX", "series_info: titre nettoyé")
        check(s1.last?.title == "Épisode 2" && s1.last?.ext == "mp4", "series_info: défauts titre/ext")
        check(info[2]?.first?.ext == "avi", "series_info: saison 2 ext avi")

        // MARK: Borne 50000 entrées

        var big: [[String: Any]] = []
        for i in 0..<(Sanitizer.maxEntriesPerCatalog + 10) {
            big.append(["stream_id": i, "name": "n\(i)"])
        }
        check(XtreamParser.live(big).count == Sanitizer.maxEntriesPerCatalog, "borne 50000 entrées par catalogue")

        // MARK: Construction des URLs de lecture (identifiants factices)

        let srv = "http://srv.test:8080"
        let pbLive = URLBuilder.playback(server: srv, username: "user", password: "pass", kind: .tv, id: "55", ext: nil)
        check(pbLive == "http://srv.test:8080/live/user/pass/55.ts", "url live exacte")
        let pbMov = URLBuilder.playback(server: srv, username: "user", password: "pass", kind: .movie, id: "77", ext: "mkv")
        check(pbMov == "http://srv.test:8080/movie/user/pass/77.mkv", "url film exacte")
        let pbMovDef = URLBuilder.playback(server: srv, username: "user", password: "pass", kind: .movie, id: "77", ext: nil)
        check(pbMovDef == "http://srv.test:8080/movie/user/pass/77.mp4", "url film ext par défaut")
        let pbEp = URLBuilder.playback(server: srv, username: "user", password: "pass", kind: .episode, id: "9001", ext: "avi")
        check(pbEp == "http://srv.test:8080/series/user/pass/9001.avi", "url épisode exacte")
        let pbEnc = URLBuilder.playback(server: srv, username: "u@x.com", password: "p w&1", kind: .tv, id: "1", ext: nil)
        check(pbEnc == "http://srv.test:8080/live/u%40x.com/p%20w%261/1.ts", "url: identifiants percent-encodés")

        // MARK: URL iina://

        if let iina = URLBuilder.iina(playbackURL: pbMov) {
            check(iina.scheme == "iina" && iina.host == "open", "iina: scheme/host")
            check(iina.absoluteString.hasPrefix("iina://open?url="), "iina: préfixe attendu")
            let comps = URLComponents(url: iina, resolvingAgainstBaseURL: false)
            var q: [String: String] = [:]
            for item in comps?.queryItems ?? [] { q[item.name] = item.value }
            check(q["url"] == pbMov, "iina: param url décodé exact")
            check(q["new_window"] == "0", "iina: new_window=0")
        } else {
            check(false, "iina: construction URL")
        }

        // MARK: Cache disque : aucun secret ni URL

        let cache = DiskCache(
            fetchedAt: 1,
            live: [MediaItem(id: "1", name: "Chaîne", ext: "ts", kind: .tv, icon: nil)],
            vod: [MediaItem(id: "2", name: "Film", ext: "mkv", kind: .movie, icon: nil)],
            series: [MediaItem(id: "3", name: "Série", ext: nil, kind: .series, icon: nil)],
            seriesInfo: ["3": SeriesInfoCache(fetchedAt: 1, seasons: ["1": [EpisodeItem(id: "9", num: 1, title: "Ep", ext: "mp4", image: nil)]])]
        )
        if let data = try? JSONEncoder().encode(cache),
           let s = String(data: data, encoding: .utf8) {
            check(!s.contains("FAKEPASSWORD123") && !s.contains("fakeuser"), "cache: aucun identifiant")
            check(!s.contains("http://") && !s.contains("https://"), "cache: aucune URL")
            if let back = try? JSONDecoder().decode(DiskCache.self, from: data) {
                check(back.live.count == 1 && back.vod.count == 1 && back.series.count == 1
                      && back.seriesInfo["3"]?.seasons["1"]?.count == 1, "cache: aller-retour JSON")
            } else {
                check(false, "cache: décodage")
            }
        } else {
            check(false, "cache: encodage")
        }

        // MARK: Config plist

        if let cfg = XtreamConfig(dict: ["server": "http://x.test/", "username": "u"]) {
            check(cfg.server == "http://x.test" && cfg.username == "u", "config: slash final retiré")
        } else {
            check(false, "config: parsing")
        }
        check(XtreamConfig(dict: ["server": "ftp://x", "username": "u"]) == nil, "config: scheme invalide rejeté")
        check(XtreamConfig(dict: ["server": "http://x"]) == nil, "config: username manquant rejeté")

        // MARK: Vignettes (stream_icon / cover / info.movie_image)

        let withIcons = XtreamParser.live(parse("""
        [
          {"stream_id": 1, "name": "A", "stream_icon": "http://img.example/a.png"},
          {"stream_id": 2, "name": "B", "stream_icon": "javascript:alert(1)"},
          {"stream_id": 3, "name": "C", "stream_icon": "http://x/p.png?username=u&password=p"},
          {"stream_id": 4, "name": "D", "stream_icon": ""}
        ]
        """))
        check(withIcons.count == 4 && withIcons[0].icon == "http://img.example/a.png", "vignette: http conservée")
        check(withIcons[1].icon == nil && withIcons[2].icon == nil && withIcons[3].icon == nil,
              "vignette: scheme dangereux, identifiants et vide rejetés")
        let seriesIcons = XtreamParser.series(parse("""
        [{"series_id": 5, "name": "S", "cover": "https://img.example/cover.jpg"}]
        """))
        check(seriesIcons.first?.icon == "https://img.example/cover.jpg", "vignette: cover série")
        let epIcons = XtreamParser.seriesInfo(parse("""
        {"episodes": {"1": [{"id": "9", "episode_num": 1, "title": "E", "container_extension": "mkv",
                             "info": {"movie_image": "http://img.example/e.jpg"}}]}}
        """))
        check(epIcons[1]?.first?.image == "http://img.example/e.jpg", "vignette: movie_image épisode")

        // MARK: Config JSON propre au lanceur

        let tmpCfg = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xtream-launcher-selftest-\(UUID().uuidString).json")
        do {
            try XtreamConfig.writeJSON(server: "http://srv.example:8080/", username: "user test", to: tmpCfg)
            if let back = XtreamConfig.readJSON(from: tmpCfg) {
                check(back.server == "http://srv.example:8080" && back.username == "user test",
                      "config JSON: aller-retour et normalisation serveur")
            } else {
                check(false, "config JSON: relecture")
            }
            if let raw = try? String(contentsOf: tmpCfg, encoding: .utf8) {
                check(!raw.contains("password"), "config JSON: aucun champ mot de passe")
            }
            try? FileManager.default.removeItem(at: tmpCfg)
        } catch {
            check(false, "config JSON: écriture")
        }
        check(XtreamConfig.readJSON(from: tmpCfg) == nil, "config JSON: fichier absent → nil")

        // MARK: Recherche insensible casse/accents

        check(CatalogStore.fold("Café Été").contains(CatalogStore.fold("cafe ete")), "recherche: fold casse+accents")

        print("[selftest] résultat : \(pass) réussis, \(fail) échoués")
        return fail == 0 ? 0 : 1
    }
}
