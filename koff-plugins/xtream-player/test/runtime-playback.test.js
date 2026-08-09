const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

test("playback loads the credentialed stream directly through MPV without header overrides", () => {
  const setCalls = [];
  const commandCalls = [];
  const coreOpenCalls = [];
  const menuItems = [];
  const eventCallbacks = {};
  let hookRegistered = false;
  const values = {
    server: "http://provider.example:2086",
    username: "alice",
    lastStreamId: "212",
    lastStreamName: "Secret Story",
    lastStreamExtension: "ts"
  };

  const sandbox = {
    URL: undefined,
    iina: {
      core: { open(value) { coreOpenCalls.push(value); }, osd() {} },
      mpv: {
        addHook() { hookRegistered = true; },
        command(name, args) { commandCalls.push([name, args]); },
        getString() { return ""; },
        set(name, value) { setCalls.push([name, value]); }
      },
      event: { on(name, callback) { eventCallbacks[name] = callback; } },
      http: { get() { throw new Error("not used"); } },
      utils: {
        keychainRead() { return "secret"; },
        keychainWrite() { return true; }
      },
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
        postMessage() {},
        close() {},
        loadFile() {},
        setProperty() {},
        setFrame() {},
        onMessage() {},
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

  const replay = menuItems.find((item) => item.title === "Replay Secret Story");
  assert.equal(typeof replay.action, "function");
  replay.action();
  assert.deepEqual(setCalls, [["force-media-title", "Secret Story"]]);
  assert.equal(commandCalls.length, 1);
  assert.equal(commandCalls[0][0], "loadfile");
  assert.equal(commandCalls[0][1].length, 1);
  assert.equal(commandCalls[0][1][0], "http://provider.example:2086/live/alice/secret/212.ts");
  assert.deepEqual(coreOpenCalls, []);
  assert.equal(hookRegistered, false);
  assert.equal(setCalls.some(([name]) => name === "user-agent"), false);
});
