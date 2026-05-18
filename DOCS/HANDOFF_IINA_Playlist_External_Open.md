# HANDOFF - IINA External Open Playlist Restore

## Last State - 2026-05-18

✅ Confirmé:
- Build complet macOS réussi avec `xcodebuild`.
- `git diff --check` OK.
- Parse Swift OK sur les fichiers touchés.

Changements:
- `AppDelegate.swift`: détecte les fichiers/URLs reçus pendant un démarrage froid.
- `AppDelegate.swift`: pour `enqueue=1`, si une playlist active existe mais que la fenêtre n'est pas visible, l'item est ajouté puis joué et la fenêtre est ramenée devant.
- `MainMenuActions.swift`: `KoffPlaylistStore` sait restaurer l'autosave, ajouter des paths, viser le premier nouvel item et reprendre la lecture.
- `PlaylistViewController.swift`: fond noir local sur le panneau playlist et ses tables.

🤔 Probable:
- Ce fix couvre aussi le cas "fenêtre fermée mais app encore en arrière-plan" pour les URLs `enqueue=1` avec playlist active.

Next step:
- Tester manuellement avec une vraie vidéo locale et une vraie URL média, puis vérifier que l'autosave contient bien la playlist étendue après lecture.
