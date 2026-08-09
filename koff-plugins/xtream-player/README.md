# Xtream Player for IINA

Personal IINA plugin for browsing and playing an authorized Xtream live TV
playlist without modifying IINA or NexTv.

## Security model

- The server URL and username are stored in IINA plugin preferences.
- The password is stored in the macOS Keychain through IINA's plugin API.
- Passwords and credential-bearing stream URLs are never logged or sent to the
  plugin web view.
- Playback starts from a non-sensitive virtual URL. An MPV `on_load` hook
  replaces it in memory with the Xtream stream URL.
- The plugin accepts only `http` and `https` servers and validates all API data
  before using it.
- IINA requires `allowedDomains: ["*"]` for a user-configurable provider. The
  plugin itself only calls the exact server saved by the user.

### Accepted security tradeoff

Koff accepted the broad `allowedDomains: ["*"]` permission on 2026-08-08 so
the personal plugin can remain provider-configurable. The runtime validation
and exact-server request boundary above remain mandatory.

## Build and test

```bash
cd /Users/koff/CODE/IINA/iina/koff-plugins/xtream-player
npm run check
npm run package
```

Expected artifact:

```text
build/Xtream-Player-0.1.0.iinaplgz
```

## Use after installation

1. Open an IINA player window.
2. Open the **Xtream Player** plugin menu.
3. Choose **Open Xtream Browser**.
4. Save the provider server URL, username, and password.
5. Search for a live channel and press **Play in IINA**.

Installation and live-account testing are intentionally separate operations.
