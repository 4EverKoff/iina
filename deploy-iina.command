#!/usr/bin/env bash
set -euo pipefail

SCHEME="iina"
CONFIGURATION="Debug"
PRODUCT_APP_NAME="IINA Koff.app"
TARGET_APP="/Applications/IINA.app"
DERIVED_DATA_PATH="${HOME}/Library/Developer/Xcode/DerivedData/IINA-Koff-Deploy"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="${SCRIPT_DIR}/iina.xcodeproj"
BUILT_APP="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/${PRODUCT_APP_NAME}"

finish() {
  local exit_code=$?
  if [[ -t 0 ]]; then
    if [[ $exit_code -eq 0 ]]; then
      printf "\nTermine. Appuie sur une touche pour fermer cette fenetre."
    else
      printf "\nErreur. Appuie sur une touche pour fermer cette fenetre."
    fi
    read -r -n 1
    printf "\n"
  fi
  exit "$exit_code"
}
trap finish EXIT

echo "Build de ${PRODUCT_APP_NAME}..."
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "platform=macOS" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  build

if [[ ! -d "${BUILT_APP}" ]]; then
  echo "App construite introuvable: ${BUILT_APP}" >&2
  exit 1
fi

if pgrep -x "IINA" >/dev/null || pgrep -x "IINA Koff" >/dev/null; then
  echo "Fermeture de IINA avant remplacement..."
  osascript -e 'tell application "IINA" to quit' >/dev/null 2>&1 || true
  osascript -e 'tell application "IINA Koff" to quit' >/dev/null 2>&1 || true
  for _ in {1..20}; do
    if ! pgrep -x "IINA" >/dev/null && ! pgrep -x "IINA Koff" >/dev/null; then
      break
    fi
    sleep 0.5
  done
fi

if pgrep -x "IINA" >/dev/null || pgrep -x "IINA Koff" >/dev/null; then
  echo "IINA est encore ouvert. Ferme l'app puis relance ce script." >&2
  exit 1
fi

STAGED_APP="/Applications/.IINA.app.deploy.$$"
rm -rf "${STAGED_APP}"

echo "Copie vers ${TARGET_APP}..."
ditto "${BUILT_APP}" "${STAGED_APP}"
rm -rf "${TARGET_APP}"
mv "${STAGED_APP}" "${TARGET_APP}"
xattr -dr com.apple.quarantine "${TARGET_APP}" >/dev/null 2>&1 || true

echo "OK: ${TARGET_APP} a ete remplace."
echo "La configuration utilisateur n'a pas ete modifiee."
