const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

test("search covers live, movies and series; playback builds the right URL per kind", async () => {
  const commandCalls = [];
  const posted = [];
  const handlers = {};
  const menuItems = [];
  const values = { server: "http://provider.example:2086", username: "alice" };
  const catalogs = {
    get_series_info: {
      episodes: { "1": [{ id: "100", episode_num: 1, title: "Pilot", container_extension: "mkv" }] }
    },
    get_live_streams: [{ stream_id: 12, name: "Revenant TV", container_extension: "ts" }],
    get_vod_streams: [{ stream_id: 900, name: "The Revenant", container_extension: "mkv" }],
    get_series: [{ series_id: 42, name: "Ippon Again" }]
  };

  const sandbox = {
    URL: undefined,
    iina: {
      core: { open() {}, osd() {} },
      mpv: {
        addHook() { throw new Error("hooks are not used"); },
        command(name, args) { commandCalls.push([name, args]); },
        getString() { return ""; },
        set() {}
      },
      event: { on() {} },
      http: {
        async get(url) {
          for (const action of Object.keys(catalogs)) {
            if (url.includes("action=" + action)) return { data: catalogs[action] };
          }
          throw new Error("unexpected URL");
        }
      },
      utils: { keychainRead() { return "secret"; }, keychainWrite() { return true; } },
      preferences: {
        get(key) { return values[key]; },
        set(key, value) { values[key] = value; },
        sync() {}
      },
      menu: {
        removeAllItems() {},
        addItem(item) { menuItems.push(item); },
        item(title, action) { return { title, action }; }
      },
      standaloneWindow: {
        postMessage(name, data) { posted.push([name, data]); },
        close() {},
        loadFile() {},
        setProperty() {},
        setFrame() {},
        onMessage(name, callback) { handlers[name] = callback; },
        open() {}
      },
      console: { error() {} }
    }
  };
  sandbox.globalThis = sandbox;

  const root = path.resolve(__dirname, "..");
  const source = ["src/xtream-core.js", "src/index.js"]
    .map((file) => fs.readFileSync(path.join(root, file), "utf8"))
    .join("\n");
  vm.runInNewContext(source, sandbox);

  const openItem = menuItems.find((item) => item.title === "Open Xtream Browser");
  openItem.action();

  await handlers.search({ query: "revenant" });
  const results = posted.find(([name]) => name === "results");
  assert.equal(
    JSON.stringify(results[1].items.map((item) => [item.type, item.id])),
    JSON.stringify([["live", "12"], ["movie", "900"]])
  );

  handlers.play({ type: "movie", id: "900" });
  assert.equal(commandCalls.at(-1)[1][0], "http://provider.example:2086/live/alice/secret/12.ts".replace("/live/", "/movie/").replace("12.ts", "900.mkv"));

  await handlers["open-series"]({ id: "42" });
  const episodes = posted.find(([name]) => name === "episodes");
  assert.equal(episodes[1].items.length, 1);
  assert.equal(episodes[1].items[0].name, "S01E01 · Pilot");

  handlers["play-episode"]({ id: "100" });
  assert.equal(commandCalls.at(-1)[1][0], "http://provider.example:2086/series/alice/secret/100.mkv");

  assert.equal(values.lastStreamType, "series");
});
