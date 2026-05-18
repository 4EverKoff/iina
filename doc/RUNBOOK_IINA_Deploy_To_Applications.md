# RUNBOOK - IINA Deploy To Applications

## Objectif

Remplacer `/Applications/IINA.app` par le build local `IINA Koff.app`, sans modifier la configuration utilisateur.

## Procedure

CMD1) Lancer le deploy double-clic ou en terminal

```bash
/Users/koff/CODE/IINA/iina/deploy-iina.command
```

Resultat attendu:

- `** BUILD SUCCEEDED **`
- `OK: /Applications/IINA.app a ete remplace.`
- `La configuration utilisateur n'a pas ete modifiee.`

## Validation

CMD2) Verifier le bundle installe

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' /Applications/IINA.app/Contents/Info.plist
```

Resultat attendu:

```text
com.koff.iina.debug
```

CMD3) Verifier la signature locale

```bash
codesign --verify --deep --strict --verbose=2 /Applications/IINA.app
```

Resultat attendu:

```text
/Applications/IINA.app: valid on disk
/Applications/IINA.app: satisfies its Designated Requirement
```

## Notes

- ✅ Confirme: la configuration utilisateur IINA est hors du bundle `.app`; le script ne touche pas a `~/Library/Application Support` ni aux preferences.
- ✅ Confirme: le script build dans `~/Library/Developer/Xcode/DerivedData/IINA-Koff-Deploy`.
- ⚠️ Attention: si IINA reste ouvert, le script stoppe et demande de fermer l'app.
