# HANDOFF - IINA Deploy To Applications

## Dernier etat

- ✅ Confirme: `/Applications/IINA.app` a ete remplace le 2026-05-15 par le build local `IINA Koff.app`.
- ✅ Confirme: `CFBundleIdentifier` installe = `com.koff.iina.debug`.
- ✅ Confirme: `codesign --verify --deep --strict --verbose=2 /Applications/IINA.app` passe.
- ✅ Confirme: un lanceur double-clic existe: `/Users/koff/CODE/IINA/iina/deploy-iina.command`.

## Reprise rapide

CMD1) Redeployer

```bash
/Users/koff/CODE/IINA/iina/deploy-iina.command
```

CMD2) Verifier l'app installee

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' /Applications/IINA.app/Contents/Info.plist
```

Resultat attendu:

```text
com.koff.iina.debug
```
