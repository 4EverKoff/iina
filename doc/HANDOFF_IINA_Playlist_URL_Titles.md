# HANDOFF - IINA Playlist URL Titles

## Last State - 2026-05-15

Confirmed:
- Playlist display uses `MPVPlaylistItem.filenameForDisplay`.
- `playlist/N/title` is preferred when mpv provides it.
- Network URL fallback previously returned the full raw URL.
- Custom playlist save stored `title`, but restore appended only `path`.

Changed:
- Network URL fallback now shows the decoded URL last path component instead of the full URL.
- Cached metadata `title` can display even when `artist` is missing.
- Custom playlist restore passes saved titles back to mpv using per-file `force-media-title`, including the first item.

Validation:
- `xcrun swiftc -parse ...` passed for modified Swift files.
- `git diff --check` passed.
- Full `xcodebuild` is blocked by unrelated `LanguageTokenField.swift` / `NSAttachmentCharacter` SDK issue.

Next step:
- Fix or confirm the `LanguageTokenField.swift` SDK compatibility issue, then rerun the full app build.
