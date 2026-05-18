# RUNBOOK - IINA External Open Playlist Restore

## Scope
Quand IINA reçoit un fichier ou une URL `enqueue=1` au démarrage, restaurer la dernière playlist autosauvegardée, ajouter le nouvel item en fin de playlist, puis lire cet item directement.

## États
- ✅ Confirmé: `application(_:openFile:)` bufferise les fichiers macOS puis appelle `handleOpenFile()`.
- ✅ Confirmé: `iina://open?...&enqueue=1` passe par `parsePendingURL(_:)`.
- ✅ Confirmé: le panneau playlist utilise maintenant un fond noir local dans `PlaylistViewController`.
- 🤔 Probable: le cas visible par l'utilisateur comme "app fermée" peut aussi être "fenêtre fermée mais process IINA encore lancé".
- ❌ Infirmé: pas besoin de modifier l'asset global `SidebarTableBackground`, partagé avec d'autres panneaux.

## Validation

CMD1)
```bash
cd /Users/koff/CODE/IINA/iina && git diff --check
```
Résultat attendu: sortie vide, code `0`.

CMD2)
```bash
cd /Users/koff/CODE/IINA/iina && xcrun swiftc -parse iina/AppDelegate.swift iina/MainMenuActions.swift iina/PlaylistViewController.swift
```
Résultat attendu: sortie vide, code `0`.

CMD3)
```bash
cd /Users/koff/CODE/IINA/iina && xcodebuild -project iina.xcodeproj -scheme iina -configuration Debug -destination 'platform=macOS' build
```
Résultat attendu: `** BUILD SUCCEEDED **`.

CMD4)
```bash
open 'iina://open?url=https%3A%2F%2Fexample.com%2Fvideo.mp4&enqueue=1'
```
Résultat attendu: si IINA démarre à froid avec une playlist autosauvegardée, la fenêtre lecteur s'ouvre, la playlist est restaurée, l'URL est ajoutée en dernier et lue.

CMD5)
```bash
open -a "IINA Koff" /path/to/video.mp4
```
Résultat attendu: si IINA démarre à froid avec une playlist autosauvegardée, la fenêtre lecteur s'ouvre, le fichier est ajouté en dernier et lu.
