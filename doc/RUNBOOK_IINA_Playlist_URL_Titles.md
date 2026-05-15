# RUNBOOK - IINA Playlist URL Titles

## Scope
Keep readable names for HTTP/IPTV playlist entries instead of showing raw URLs whenever IINA/mpv has a title or filename-like fallback.

## Validation

CMD1)
```bash
cd /Users/koff/CODE/IINA/iina && xcrun swiftc -parse iina/MPVPlaylistItem.swift iina/MPVCommandWrappers.swift iina/MPVController.swift iina/PlayerCore.swift iina/MainMenuActions.swift iina/PlaylistViewController.swift
```
Expected: exits `0`.

CMD2)
```bash
cd /Users/koff/CODE/IINA/iina && git diff --check
```
Expected: exits `0`.

CMD3)
```bash
cd /Users/koff/CODE/IINA/iina && xcodebuild -project iina.xcodeproj -scheme iina -configuration Debug -destination 'platform=macOS' build
```
Expected: full app build succeeds.

Known blocker on 2026-05-15: full build stops on `iina/LanguageTokenField.swift` because `NSAttachmentCharacter` is obsolete with the installed Xcode/SDK.
