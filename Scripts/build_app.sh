#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FS Client Launcher.app"
DEST="${ROOT}/dist/${APP_NAME}"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
TARGET="arm64-apple-macosx13.0"
BIN="${DEST}/Contents/MacOS/FSClientLauncher"

echo "==> Release-Binary bauen"
mkdir -p "${ROOT}/dist"
if (cd "$ROOT" && swift build -c release 2>/dev/null); then
  cp "${ROOT}/.build/release/FSClientLauncher" "${ROOT}/dist/FSClientLauncher"
else
  echo "(swift build nicht möglich — Fallback: swiftc)"
  swiftc -O "${ROOT}/Sources/FSClientLauncher/"*.swift -o "${ROOT}/dist/FSClientLauncher" -sdk "$SDK" -target "$TARGET"
fi

echo "==> App-Bundle: ${DEST}"
rm -rf "$DEST"
mkdir -p "${DEST}/Contents/MacOS"
mkdir -p "${DEST}/Contents/Resources"
cp "${ROOT}/Scripts/Info.plist" "${DEST}/Contents/Info.plist"
# Ohne PkgInfo (APPL + Signatur) zeigt Finder mitunter nur das generische Programm-Symbol.
printf 'APPL????' > "${DEST}/Contents/PkgInfo"
cp "${ROOT}/dist/FSClientLauncher" "$BIN"
chmod +x "$BIN"
if compgen -G "${ROOT}/Sources/FSClientLauncher/Resources/*.svg" > /dev/null; then
  cp "${ROOT}/Sources/FSClientLauncher/Resources/"*.svg "${DEST}/Contents/Resources/" 2>/dev/null || true
fi

RES_ICNS="${ROOT}/Sources/FSClientLauncher/Resources/AppIcon.icns"
echo "==> App-Icon (AppIcon.icns)"
# Neu erzeugen nur mit rsvg; scheitert iconutil, bleibt die bestehende .icns durch atomares Schreiben im Skript erhalten.
if command -v rsvg-convert >/dev/null 2>&1; then
  if ! bash "${ROOT}/Scripts/build_app_icon.sh"; then
    echo "Warnung: AppIcon.icns wurde nicht neu erzeugt (iconutil/rsvg). Es wird die vorhandene Datei im Repo kopiert." >&2
  fi
elif [[ -f "$RES_ICNS" ]]; then
  echo "(rsvg-convert fehlt — vorhandenes AppIcon.icns wird übernommen)"
else
  echo "Hinweis: Kein AppIcon.icns — für Finder-Icon: brew install librsvg && ./Scripts/build_app_icon.sh" >&2
fi
if [[ -f "$RES_ICNS" ]]; then
  if ! file "$RES_ICNS" | grep -q 'Mac OS X icon'; then
    echo "Warnung: Unerwarteter Dateityp für AppIcon.icns — kopiere trotzdem." >&2
  fi
  cp "$RES_ICNS" "${DEST}/Contents/Resources/AppIcon.icns"
else
  echo "Warnung: Kein ${RES_ICNS} — Bundle nutzt das generische App-Symbol." >&2
fi
# Finder/Dock-Caches anstoßen (Bundle-Zeitstempel).
touch "${DEST}"

BUNDLE_JDK_ROOT="${BUNDLE_JDK_ROOT:-${ROOT}/BundledJDKs}"
if [[ -d "${BUNDLE_JDK_ROOT}/jdk11" ]]; then
  echo "==> Kopiere eingebettetes JDK 11 aus ${BUNDLE_JDK_ROOT}/jdk11"
  ditto "${BUNDLE_JDK_ROOT}/jdk11" "${DEST}/Contents/Resources/jdk11"
fi
if [[ -d "${BUNDLE_JDK_ROOT}/jdk21" ]]; then
  echo "==> Kopiere eingebettetes JDK 21 aus ${BUNDLE_JDK_ROOT}/jdk21"
  ditto "${BUNDLE_JDK_ROOT}/jdk21" "${DEST}/Contents/Resources/jdk21"
fi
if [[ -d "${BUNDLE_JDK_ROOT}/jre8" ]]; then
  echo "==> Kopiere eingebettetes JRE 8 aus ${BUNDLE_JDK_ROOT}/jre8"
  ditto "${BUNDLE_JDK_ROOT}/jre8" "${DEST}/Contents/Resources/jre8"
fi

echo "Fertig: ${DEST}"
echo "JDKs: optional unter ${BUNDLE_JDK_ROOT}/ (jdk11, jdk21, jre8) — siehe Scripts/JDK_BUNDLE.md"
echo "  oder manuell unter Contents/Resources/ ablegen bzw. FSCL_JDK11, FSCL_JDK21, FSCL_JRE8 setzen."
