# Xtream Launcher

Lanceur style Spotlight pour le catalogue Xtream de Koff : champ de recherche,
résultats groupés TV / Films / Séries, forage dans les épisodes d'une série,
ouverture directe du flux dans IINA via `iina://open?url=…&new_window=0`.
Aucune URL à copier-coller.

## Build

```zsh
./build.sh
```

Produit `Xtream-Launcher.app` (arm64, macOS 13+, ad-hoc signé, aucune dépendance).

## Utilisation

- Lancer `Xtream-Launcher.app`.
- Taper pour filtrer, flèches haut/bas pour naviguer, Entrée (ou clic) pour ouvrir.
- Sur une série : Entrée affiche les épisodes (Saison X, Épisode Y), Échap ou « Retour » revient.
- Échap à la racine quitte l'app ; elle quitte aussi quand la fenêtre perd le focus.

## Configuration

- Serveur + identifiant lus depuis le plist du plugin IINA :
  `~/Library/Application Support/com.koff.iina.debug/plugins/.preferences/com.koff.iina.xtream-player.plist`
  (clés `server`, `username`).
- Mot de passe lu dans le Trousseau (service
  `com.koff.iina.xtream-player - xtream-credentials`, account = username ;
  fallback service `xtream-credentials`). Une demande Trousseau au premier
  lancement est attendue.
- Le mot de passe reste en mémoire uniquement : jamais dans les logs, le cache,
  UserDefaults ou un fichier.

## Cache

`~/Library/Application Support/com.koff.iina.xtream-launcher/catalog.json` —
ids, noms et extensions uniquement (jamais d'URL ni d'identifiants). TTL 5 min,
rafraîchissement en tâche de fond.

## Modes de test

```zsh
# Selftest hors réseau : parsing (live/vod/séries/épisodes) + construction des URLs
./Xtream-Launcher.app/Contents/MacOS/Xtream-Launcher --selftest

# Debug : mot de passe lu sur stdin (pipe uniquement, jamais affiché ni stocké)
security find-generic-password -s "com.koff.iina.xtream-player - xtream-credentials" -a "<username>" -w \
  | ./Xtream-Launcher.app/Contents/MacOS/Xtream-Launcher --password-stdin
```

Les logs ne contiennent que des compteurs sanitizés (ex. `catalogue chargé : tv=X films=Y séries=Z`).
