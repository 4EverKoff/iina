(function (root, factory) {
  "use strict";

  var api = factory();
  if (typeof module === "object" && module.exports) {
    module.exports = api;
  }
  root.XtreamCore = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  var MAX_CREDENTIAL_LENGTH = 256;
  var MAX_STREAMS = 100000;
  var MAX_RESULTS = 50;
  var MAX_EPISODES = 5000;
  var ALLOWED_ACTIONS = {
    get_live_streams: true,
    get_vod_streams: true,
    get_series: true,
    get_series_info: true
  };
  var MEDIA_KINDS = { live: true, movie: true, series: true };

  function requireSafeText(value, label, maximumLength) {
    if (typeof value !== "string") {
      throw new Error(label + " must be a string");
    }
    var normalized = value.trim();
    if (!normalized || normalized.length > maximumLength || /[\u0000-\u001f\u007f]/.test(normalized)) {
      throw new Error(label + " is invalid");
    }
    return normalized;
  }

  function normalizeServer(value) {
    var input = requireSafeText(value, "Server", 2048);
    var explicitScheme = input.match(/^([a-z][a-z0-9+.-]*):\/\//i);
    if (explicitScheme && !/^https?$/i.test(explicitScheme[1])) {
      throw new Error("Server must use http or https");
    }
    var schemeSeparator = input.indexOf("://");
    var authorityEnd = schemeSeparator >= 0 ? input.indexOf("/", schemeSeparator + 3) : -1;
    var authority = schemeSeparator >= 0
      ? input.slice(schemeSeparator + 3, authorityEnd >= 0 ? authorityEnd : input.length)
      : "";
    if (/[?#]/.test(input) || authority.indexOf("@") >= 0) {
      throw new Error("Server must not contain credentials, a query, or a fragment");
    }
    if (/\s/.test(input)) {
      throw new Error("Server must not contain whitespace");
    }
    var match = input.match(/^(https?):\/\/(\[[0-9a-fA-F:.]+\]|[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?)(?::(\d{1,5}))?(\/.*)?$/);
    if (!match) {
      throw new Error("Server must be a valid URL");
    }
    var port = match[3] ? Number(match[3]) : null;
    if (port !== null && (port < 1 || port > 65535)) {
      throw new Error("Server port is invalid");
    }
    var path = (match[4] || "").replace(/\/+$/, "");
    return match[1].toLowerCase() + "://" + match[2].toLowerCase() +
      (match[3] ? ":" + match[3] : "") + (path === "/" ? "" : path);
  }

  function validateCredential(value, label) {
    return requireSafeText(value, label, MAX_CREDENTIAL_LENGTH);
  }

  function appendPath(server, path) {
    return normalizeServer(server) + "/" + path.replace(/^\/+/, "");
  }

  function buildActionURL(config, action, extraQuery) {
    var server = normalizeServer(config.server);
    var username = validateCredential(config.username, "Username");
    var password = validateCredential(config.password, "Password");
    if (!ALLOWED_ACTIONS[action]) {
      throw new Error("Xtream action is invalid");
    }
    var query = [
      "username=" + encodeURIComponent(username),
      "password=" + encodeURIComponent(password),
      "action=" + action
    ].join("&");
    if (extraQuery) {
      Object.keys(extraQuery).forEach(function (key) {
        var value = requireSafeText(String(extraQuery[key]), "Query parameter", 64);
        if (!/^[a-z_]+$/.test(key)) throw new Error("Query parameter name is invalid");
        query += "&" + key + "=" + encodeURIComponent(value);
      });
    }
    return appendPath(server, "player_api.php") + "?" + query;
  }

  function buildApiURL(config) {
    return buildActionURL(config, "get_live_streams");
  }

  function normalizeExtension(value, fallback) {
    var extension = typeof value === "string" && value ? value.toLowerCase() : (fallback || "ts");
    if (!/^[a-z0-9]{1,8}$/.test(extension)) {
      throw new Error("Stream extension is invalid");
    }
    return extension;
  }

  function normalizeStream(item, defaultExtension) {
    if (!item || typeof item !== "object") return null;
    var id = String(item.stream_id == null ? "" : item.stream_id);
    var name = typeof item.name === "string" ? item.name.trim() : "";
    if (!/^\d+$/.test(id) || !name || name.length > 200 || /[\u0000-\u001f\u007f]/.test(name)) {
      return null;
    }

    var extension;
    try {
      extension = normalizeExtension(item.container_extension, defaultExtension);
    } catch (_) {
      return null;
    }

    return { id: id, name: name, extension: extension };
  }

  function parseStreams(payload, defaultExtension) {
    if (!Array.isArray(payload)) {
      throw new Error("Provider response must be an array");
    }
    if (payload.length > MAX_STREAMS) {
      throw new Error("Provider returned too many streams");
    }

    var seen = Object.create(null);
    var result = [];
    payload.forEach(function (item) {
      var stream = normalizeStream(item, defaultExtension);
      if (stream && !seen[stream.id]) {
        seen[stream.id] = true;
        result.push(stream);
      }
    });
    return result;
  }

  function parseSeries(payload) {
    if (!Array.isArray(payload)) {
      throw new Error("Provider response must be an array");
    }
    if (payload.length > MAX_STREAMS) {
      throw new Error("Provider returned too many series");
    }

    var seen = Object.create(null);
    var result = [];
    payload.forEach(function (item) {
      if (!item || typeof item !== "object") return;
      var id = String(item.series_id == null ? "" : item.series_id);
      var name = typeof item.name === "string" ? item.name.trim() : "";
      if (!/^\d+$/.test(id) || !name || name.length > 200 || /[\u0000-\u001f\u007f]/.test(name) || seen[id]) {
        return;
      }
      seen[id] = true;
      result.push({ id: id, name: name });
    });
    return result;
  }

  function parseEpisodes(payload) {
    var seasons = payload && typeof payload === "object" ? payload.episodes : null;
    if (!seasons || typeof seasons !== "object" || Array.isArray(seasons)) {
      throw new Error("Provider response must contain episodes");
    }

    var result = [];
    Object.keys(seasons).forEach(function (seasonKey) {
      if (!/^\d+$/.test(seasonKey)) return;
      var list = seasons[seasonKey];
      if (!Array.isArray(list)) return;
      list.forEach(function (item) {
        if (result.length >= MAX_EPISODES) return;
        if (!item || typeof item !== "object") return;
        var id = String(item.id == null ? "" : item.id);
        var episodeNumber = Number(item.episode_num);
        var title = typeof item.title === "string" ? item.title.trim() : "";
        if (!/^\d+$/.test(id) || !Number.isInteger(episodeNumber) || episodeNumber < 0 || episodeNumber > 10000) {
          return;
        }
        if (title.length > 200 || /[\u0000-\u001f\u007f]/.test(title)) return;
        var extension;
        try {
          extension = normalizeExtension(item.container_extension, "mp4");
        } catch (_) {
          return;
        }
        var season = Number(seasonKey);
        var label = "S" + String(season).padStart(2, "0") + "E" + String(episodeNumber).padStart(2, "0");
        result.push({
          id: id,
          name: title ? label + " · " + title : label,
          extension: extension,
          season: season,
          episode: episodeNumber
        });
      });
    });
    result.sort(function (left, right) {
      return left.season - right.season || left.episode - right.episode || Number(left.id) - Number(right.id);
    });
    return result;
  }

  function searchStreams(streams, value, limit) {
    var query = requireSafeText(value, "Search", 80).toLocaleLowerCase();
    var maximum = Number.isInteger(limit) && limit > 0 ? Math.min(limit, MAX_RESULTS) : 20;
    return streams
      .map(function (stream, index) {
        var name = stream.name.toLocaleLowerCase();
        var rank = name === query ? 0 : name.indexOf(query) === 0 ? 1 : name.indexOf(query) >= 0 ? 2 : 3;
        return { stream: stream, index: index, rank: rank };
      })
      .filter(function (candidate) { return candidate.rank < 3; })
      .sort(function (left, right) {
        return left.rank - right.rank || left.stream.name.localeCompare(right.stream.name) || left.index - right.index;
      })
      .slice(0, maximum)
      .map(function (candidate) { return candidate.stream; });
  }

  function buildVirtualURL(stream) {
    var normalized = normalizeStream({
      stream_id: stream.id,
      name: stream.name,
      container_extension: stream.extension
    });
    if (!normalized) throw new Error("Stream is invalid");
    return "iina-xtream://play/" + normalized.id +
      "?extension=" + encodeURIComponent(normalized.extension) +
      "&name=" + encodeURIComponent(normalized.name);
  }

  function parseVirtualURL(value) {
    if (typeof value !== "string" || value.indexOf("iina-xtream://") !== 0) return null;
    var match = value.match(/^iina-xtream:\/\/play\/(\d+)\?extension=([a-z0-9]{1,8})&name=([^&]*)$/i);
    if (!match) return null;
    var name;
    try {
      name = decodeURIComponent(match[3]);
    } catch (_) {
      return null;
    }
    var stream = normalizeStream({
      stream_id: match[1],
      name: name || "Live stream",
      container_extension: match[2]
    });
    return stream;
  }

  function buildMediaURL(config, kind, media) {
    var server = normalizeServer(config.server);
    var username = validateCredential(config.username, "Username");
    var password = validateCredential(config.password, "Password");
    if (!MEDIA_KINDS[kind]) {
      throw new Error("Media kind is invalid");
    }
    var normalized = normalizeStream({
      stream_id: media.id,
      name: media.name,
      container_extension: media.extension
    });
    if (!normalized) throw new Error("Stream is invalid");
    return appendPath(server, kind + "/" + encodeURIComponent(username) + "/" + encodeURIComponent(password) +
      "/" + normalized.id + "." + normalized.extension);
  }

  function buildStreamURL(config, stream) {
    return buildMediaURL(config, "live", stream);
  }

  function buildMovieURL(config, movie) {
    return buildMediaURL(config, "movie", movie);
  }

  function buildEpisodeURL(config, episode) {
    return buildMediaURL(config, "series", episode);
  }

  return {
    MAX_RESULTS: MAX_RESULTS,
    normalizeServer: normalizeServer,
    validateCredential: validateCredential,
    buildApiURL: buildApiURL,
    buildActionURL: buildActionURL,
    parseStreams: parseStreams,
    parseSeries: parseSeries,
    parseEpisodes: parseEpisodes,
    searchStreams: searchStreams,
    buildVirtualURL: buildVirtualURL,
    parseVirtualURL: parseVirtualURL,
    buildStreamURL: buildStreamURL,
    buildMovieURL: buildMovieURL,
    buildEpisodeURL: buildEpisodeURL
  };
});
