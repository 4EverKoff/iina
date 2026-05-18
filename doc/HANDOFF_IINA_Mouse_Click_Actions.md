# HANDOFF - IINA Mouse Click Actions

## Last State - 2026-05-15

Confirmed:
- Mouse click preferences use `Preference.MouseClickAction`.
- Right click reads `.rightClickAction`, then calls `performMouseAction`.
- `showPlaylistSidebar()` already toggles the playlist drawer open/closed.

Changed:
- Added `MouseClickAction.togglePlaylist` as raw value `7`.
- Added handling in `MainWindowController.performMouseAction` to call `showPlaylistSidebar()`.
- Added the option to the legacy Control XIB popups.
- Added English/French legacy strings and new Settings localization keys/strings.

Validation:
- `xcrun swiftc -parse iina/Preference.swift iina/MainWindowController.swift iina/SettingsLocalizationKeysControl.swift` passed.
- `xmllint --noout iina/Base.lproj/PrefControlViewController.xib` passed.
- `git diff --check` passed.
- Full `xcodebuild` remains blocked by unrelated `LanguageTokenField.swift` / `NSAttachmentCharacter` SDK issue.

Next step:
- Open Settings > Control and confirm right click can be set to playlist panel toggle.
