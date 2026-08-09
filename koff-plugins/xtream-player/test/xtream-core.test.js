const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const core = require("../src/xtream-core.js");

test("normalizes an authorized http server without credentials", () => {
  assert.equal(core.normalizeServer(" https://provider.example:8443/base/ "), "https://provider.example:8443/base");
  assert.throws(() => core.normalizeServer("ftp://provider.example"), /http or https/);
  assert.throws(() => core.normalizeServer("https://user:pass@provider.example"), /must not contain credentials/);
  assert.throws(() => core.normalizeServer("https://provider.example/?token=secret"), /must not contain credentials/);
  assert.throws(() => core.normalizeServer("https://provider.example:70000"), /port is invalid/);
});

test("builds the Xtream API URL with encoded credentials", () => {
  const url = core.buildApiURL({ server: "https://provider.example", username: "user+one", password: "p@ss word" });
  assert.equal(
    url,
    "https://provider.example/player_api.php?username=user%2Bone&password=p%40ss%20word&action=get_live_streams"
  );
});

test("validates, deduplicates and searches provider streams", () => {
  const streams = core.parseStreams([
    { stream_id: 12, name: "Secret Story", container_extension: "TS" },
    { stream_id: "13", name: "Secret Story After", container_extension: "m3u8" },
    { stream_id: "12", name: "Duplicate", container_extension: "ts" },
    { stream_id: "bad", name: "Rejected", container_extension: "ts" },
    { stream_id: "14", name: "Rejected extension", container_extension: "../../x" }
  ]);

  assert.deepEqual(streams, [
    { id: "12", name: "Secret Story", extension: "ts" },
    { id: "13", name: "Secret Story After", extension: "m3u8" }
  ]);
  assert.deepEqual(core.searchStreams(streams, "secret story", 10).map((stream) => stream.id), ["12", "13"]);
});

test("keeps credentials out of the virtual playback URL", () => {
  const stream = { id: "212", name: "Secret Story", extension: "ts" };
  const virtual = core.buildVirtualURL(stream);
  assert.equal(virtual, "iina-xtream://play/212?extension=ts&name=Secret%20Story");
  assert.deepEqual(core.parseVirtualURL(virtual), stream);
  assert.equal(core.parseVirtualURL("https://provider.example/live/user/password/212.ts"), null);
});

test("constructs the real stream URL only at playback time", () => {
  const actual = core.buildStreamURL(
    { server: "http://provider.example:2086", username: "user+one", password: "p@ss word" },
    { id: "212", name: "Secret Story", extension: "ts" }
  );
  assert.equal(actual, "http://provider.example:2086/live/user%2Bone/p%40ss%20word/212.ts");
});

test("rejects oversized or malformed boundary values", () => {
  assert.throws(() => core.searchStreams([], " ", 10), /Search is invalid/);
  assert.throws(() => core.parseStreams({}), /must be an array/);
  assert.equal(core.parseVirtualURL("iina-xtream://play/not-a-number?name=x"), null);
});

test("runs in a JavaScriptCore-like context without the Web URL API", () => {
  const source = fs.readFileSync(require.resolve("../src/xtream-core.js"), "utf8");
  const sandbox = { URL: undefined };
  sandbox.globalThis = sandbox;
  vm.runInNewContext(source, sandbox);
  assert.equal(sandbox.XtreamCore.normalizeServer("https://provider.example/base/"), "https://provider.example/base");
  assert.equal(
    sandbox.XtreamCore.parseVirtualURL("iina-xtream://play/212?extension=ts&name=Secret%20Story").name,
    "Secret Story"
  );
});

test("builds catalog action URLs with an allowlist and safe extra parameters", () => {
  const config = { server: "https://provider.example", username: "alice", password: "secret" };
  assert.equal(
    core.buildActionURL(config, "get_series_info", { series_id: "42" }),
    "https://provider.example/player_api.php?username=alice&password=secret&action=get_series_info&series_id=42"
  );
  assert.throws(() => core.buildActionURL(config, "delete_account"), /action is invalid/);
  assert.throws(() => core.buildActionURL(config, "get_series", { "bad name": "1" }), /name is invalid/);
});

test("parses VOD streams with mp4 fallback and series entries", () => {
  const movies = core.parseStreams([
    { stream_id: 900, name: "A Movie", container_extension: "mkv" },
    { stream_id: 901, name: "No Extension Movie", container_extension: "" }
  ], "mp4");
  assert.deepEqual(movies, [
    { id: "900", name: "A Movie", extension: "mkv" },
    { id: "901", name: "No Extension Movie", extension: "mp4" }
  ]);

  const series = core.parseSeries([
    { series_id: 42, name: "A Show" },
    { series_id: "42", name: "Duplicate" },
    { series_id: "x", name: "Rejected" },
    { series_id: 43, name: "" }
  ]);
  assert.deepEqual(series, [{ id: "42", name: "A Show" }]);
});

test("parses, labels and sorts series episodes", () => {
  const episodes = core.parseEpisodes({
    episodes: {
      "2": [
        { id: "102", episode_num: 2, title: "Finale", container_extension: "mkv" },
        { id: "bad", episode_num: 1, title: "Rejected", container_extension: "mp4" }
      ],
      "1": [
        { id: "100", episode_num: 1, title: "Pilot", container_extension: "" },
        { id: "101", episode_num: 3, title: "", container_extension: "mp4" }
      ]
    }
  });
  assert.deepEqual(
    episodes.map((episode) => [episode.id, episode.name, episode.extension]),
    [
      ["100", "S01E01 · Pilot", "mp4"],
      ["101", "S01E03", "mp4"],
      ["102", "S02E02 · Finale", "mkv"]
    ]
  );
  assert.throws(() => core.parseEpisodes({}), /must contain episodes/);
});

test("constructs movie and episode URLs only at playback time", () => {
  const config = { server: "http://provider.example:2086", username: "user+one", password: "p@ss word" };
  assert.equal(
    core.buildMovieURL(config, { id: "900", name: "A Movie", extension: "mkv" }),
    "http://provider.example:2086/movie/user%2Bone/p%40ss%20word/900.mkv"
  );
  assert.equal(
    core.buildEpisodeURL(config, { id: "100", name: "S01E01 · Pilot", extension: "mp4" }),
    "http://provider.example:2086/series/user%2Bone/p%40ss%20word/100.mp4"
  );
  assert.throws(() => core.buildMovieURL(config, { id: "900", name: "A Movie", extension: "../" }), /invalid/);
});
