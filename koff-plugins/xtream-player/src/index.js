(function () {
  "use strict";

  if (typeof iina === "undefined" || typeof XtreamCore === "undefined") return;

  var mpv = iina.mpv;
  var event = iina.event;
  var http = iina.http;
  var utils = iina.utils;
  var preferences = iina.preferences;
  var menu = iina.menu;
  var standaloneWindow = iina.standaloneWindow;
  var pluginConsole = iina.console;
  var KEYCHAIN_SERVICE = "xtream-credentials";
  var CATALOG_CACHE_TTL_MS = 5 * 60 * 1000;
  var windowInitialized = false;
  var streamCache = Object.create(null);
  var episodeCache = Object.create(null);
  var catalogCache = { key: "", expiresAt: 0, live: [], vod: [], series: [] };

  function post(name, data) {
    if (windowInitialized) standaloneWindow.postMessage(name, data || {});
  }

  function readConfig(requirePassword) {
    var server = preferences.get("server") || "";
    var username = preferences.get("username") || "";
    var password = "";
    if (requirePassword && username) {
      var stored = utils.keychainRead(KEYCHAIN_SERVICE, username);
      password = typeof stored === "string" ? stored : "";
    }
    return { server: server, username: username, password: password };
  }

  function publicConfig() {
    var config = readConfig(false);
    return { server: config.server, username: config.username, configured: Boolean(config.server && config.username) };
  }

  function reportError(error) {
    pluginConsole.error("Xtream operation failed without logging credentials");
    var statusCode = error && Number(error.statusCode);
    var message = error && typeof error.message === "string" && error.message
      ? error.message
      : Number.isInteger(statusCode) && statusCode >= 100 && statusCode <= 599
        ? "Provider returned HTTP " + statusCode
        : "Xtream operation failed";
    post("error", { message: message });
  }

  function clearCatalogCache() {
    catalogCache = { key: "", expiresAt: 0, live: [], vod: [], series: [] };
  }

  function saveConfig(payload) {
    try {
      if (!payload || typeof payload !== "object") throw new Error("Configuration is missing");
      var server = XtreamCore.normalizeServer(payload.server);
      var username = XtreamCore.validateCredential(payload.username, "Username");
      var password = XtreamCore.validateCredential(payload.password, "Password");
      if (!utils.keychainWrite(KEYCHAIN_SERVICE, username, password)) {
        throw new Error("The password could not be saved in Keychain");
      }
      preferences.set("server", server);
      preferences.set("username", username);
      preferences.sync();
      clearCatalogCache();
      post("config", publicConfig());
      post("notice", { message: "Configuration saved in Keychain" });
    } catch (error) {
      reportError(error);
    }
  }

  async function loadCatalog(config) {
    var cacheKey = config.server + "|" + config.username;
    if (catalogCache.key === cacheKey && catalogCache.expiresAt > Date.now()) {
      return catalogCache;
    }
    async function fetchList(action) {
      var response = await http.get(XtreamCore.buildActionURL(config, action), { headers: { Accept: "application/json" } });
      return Array.isArray(response.data) ? response.data : JSON.parse(response.text || "null");
    }
    var failures = [];
    async function loadList(action, parser) {
      try {
        return parser(await fetchList(action));
      } catch (error) {
        failures.push(action);
        return [];
      }
    }
    var live = await loadList("get_live_streams", function (data) { return XtreamCore.parseStreams(data, "ts"); });
    var vod = await loadList("get_vod_streams", function (data) { return XtreamCore.parseStreams(data, "mp4"); });
    var series = await loadList("get_series", function (data) { return XtreamCore.parseSeries(data); });
    catalogCache = { key: cacheKey, expiresAt: Date.now() + CATALOG_CACHE_TTL_MS, live: live, vod: vod, series: series };
    post("notice", { message: "Catalog: " + live.length + " TV, " + vod.length + " movies, " + series.length + " series" +
      (failures.length ? " — failed: " + failures.join(", ") : "") });
    return catalogCache;
  }

  async function search(payload) {
    try {
      var query = payload && payload.query;
      var config = readConfig(true);
      post("loading", { active: true });
      var catalog = await loadCatalog(config);
      var limit = 15;
      var results = XtreamCore.searchStreams(catalog.live, query, limit).map(function (stream) {
        return { type: "live", id: stream.id, name: stream.name };
      }).concat(XtreamCore.searchStreams(catalog.vod, query, limit).map(function (movie) {
        return { type: "movie", id: movie.id, name: movie.name };
      })).concat(XtreamCore.searchStreams(catalog.series, query, limit).map(function (show) {
        return { type: "series", id: show.id, name: show.name };
      }));
      streamCache = Object.create(null);
      catalog.live.forEach(function (stream) { streamCache["live:" + stream.id] = stream; });
      catalog.vod.forEach(function (stream) { streamCache["movie:" + stream.id] = stream; });
      post("results", { items: results });
    } catch (error) {
      reportError(error);
    } finally {
      post("loading", { active: false });
    }
  }

  function rememberStream(kind, stream) {
    preferences.set("lastStreamType", kind);
    preferences.set("lastStreamId", stream.id);
    preferences.set("lastStreamName", stream.name);
    preferences.set("lastStreamExtension", stream.extension);
    preferences.sync();
  }

  function playMedia(kind, stream) {
    try {
      if (!stream) throw new Error("The selected stream is unavailable");
      var config = readConfig(true);
      var streamURL = kind === "movie"
        ? XtreamCore.buildMovieURL(config, stream)
        : kind === "series"
          ? XtreamCore.buildEpisodeURL(config, stream)
          : XtreamCore.buildStreamURL(config, stream);
      rememberStream(kind, stream);
      mpv.set("force-media-title", stream.name);
      mpv.command("loadfile", [streamURL]);
      standaloneWindow.close();
    } catch (error) {
      reportError(error);
    }
  }

  function playSelection(payload) {
    var id = payload && String(payload.id || "");
    var type = payload && payload.type === "movie" ? "movie" : "live";
    playMedia(type, streamCache[type + ":" + id]);
  }

  async function openSeries(payload) {
    try {
      var id = payload && String(payload.id || "");
      if (!/^\d+$/.test(id)) throw new Error("The selected series is unavailable");
      var config = readConfig(true);
      post("loading", { active: true });
      var response = await http.get(XtreamCore.buildActionURL(config, "get_series_info", { series_id: id }), { headers: { Accept: "application/json" } });
      var data = response.data && typeof response.data === "object" ? response.data : JSON.parse(response.text || "null");
      var episodes = XtreamCore.parseEpisodes(data);
      episodeCache = Object.create(null);
      episodes.forEach(function (episode) { episodeCache[episode.id] = episode; });
      var seriesName = "";
      catalogCache.series.forEach(function (show) { if (show.id === id) seriesName = show.name; });
      post("episodes", { seriesId: id, seriesName: seriesName, items: episodes });
    } catch (error) {
      reportError(error);
    } finally {
      post("loading", { active: false });
    }
  }

  function playEpisode(payload) {
    var id = payload && String(payload.id || "");
    playMedia("series", episodeCache[id]);
  }

  function lastStream() {
    return {
      type: String(preferences.get("lastStreamType") || "live"),
      id: String(preferences.get("lastStreamId") || ""),
      name: String(preferences.get("lastStreamName") || ""),
      extension: String(preferences.get("lastStreamExtension") || "ts")
    };
  }

  function clearConfig() {
    var config = readConfig(false);
    if (config.username) utils.keychainWrite(KEYCHAIN_SERVICE, config.username, "");
    ["server", "username", "lastStreamType", "lastStreamId", "lastStreamName"].forEach(function (key) {
      preferences.set(key, "");
    });
    preferences.set("lastStreamExtension", "ts");
    preferences.sync();
    streamCache = Object.create(null);
    episodeCache = Object.create(null);
    clearCatalogCache();
    post("config", publicConfig());
    post("results", { items: [] });
    post("notice", { message: "Local Xtream configuration cleared" });
  }

  function registerWindowHandlers() {
    standaloneWindow.onMessage("ready", async function () {
      post("config", publicConfig());
      if (!publicConfig().configured) return;
      try {
        await loadCatalog(readConfig(true));
      } catch (error) {
        reportError(error);
      }
    });
    standaloneWindow.onMessage("save-config", saveConfig);
    standaloneWindow.onMessage("search", search);
    standaloneWindow.onMessage("play", playSelection);
    standaloneWindow.onMessage("open-series", openSeries);
    standaloneWindow.onMessage("play-episode", playEpisode);
    standaloneWindow.onMessage("clear-config", clearConfig);
  }

  function openBrowser() {
    if (!windowInitialized) {
      standaloneWindow.loadFile("ui/index.html");
      standaloneWindow.setProperty({ title: "Xtream Browser", resizable: true });
      standaloneWindow.setFrame(760, 620, null, null);
      registerWindowHandlers();
      windowInitialized = true;
    }
    standaloneWindow.open();
  }

  function rebuildMenu() {
    menu.removeAllItems();
    menu.addItem(menu.item("Open Xtream Browser", openBrowser));
    var previous = lastStream();
    if (/^\d+$/.test(previous.id) && previous.name) {
      menu.addItem(menu.item("Replay " + previous.name, function () {
        playMedia(previous.type === "movie" || previous.type === "series" ? previous.type : "live", previous);
      }));
    }
  }

  event.on("iina.menu-update", rebuildMenu);
  rebuildMenu();
})();
