# RUNBOOK - IINA Mouse Click Actions

## Scope
Expose playlist panel toggle as a selectable mouse click action in Control settings.

## Validation

CMD1)
```bash
cd /Users/koff/CODE/IINA/iina && xcrun swiftc -parse iina/Preference.swift iina/MainWindowController.swift iina/SettingsLocalizationKeysControl.swift
```
Expected: exits `0`.

CMD2)
```bash
cd /Users/koff/CODE/IINA/iina && xmllint --noout iina/Base.lproj/PrefControlViewController.xib
```
Expected: exits `0`.

CMD3)
```bash
cd /Users/koff/CODE/IINA/iina && git diff --check
```
Expected: exits `0`.

CMD4)
```bash
cd /Users/koff/CODE/IINA/iina && xcodebuild -project iina.xcodeproj -scheme iina -configuration Debug -destination 'platform=macOS' build
```
Expected: full app build succeeds.

Known blocker on 2026-05-15: full build stops on `iina/LanguageTokenField.swift` because `NSAttachmentCharacter` is obsolete with the installed Xcode/SDK.
