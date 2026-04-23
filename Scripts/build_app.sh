#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="enventa Trade ERP Launcher.app"
DEST="${ROOT}/dist/${APP_NAME}"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
TARGET="arm64-apple-macosx13.0"
BIN="${DEST}/Contents/MacOS/TradeERPLauncher"

echo "==> Release-Binary bauen"
mkdir -p "${ROOT}/dist"
if (cd "$ROOT" && swift build -c release 2>/dev/null); then
  cp "${ROOT}/.build/release/TradeERPLauncher" "${ROOT}/dist/TradeERPLauncher"
else
  echo "(swift build nicht möglich — Fallback: swiftc)"
  swiftc -O "${ROOT}/Sources/TradeERPLauncherLib/"*.swift -o "${ROOT}/dist/TradeERPLauncher" -sdk "$SDK" -target "$TARGET"
fi

echo "==> App-Bundle: ${DEST}"
rm -rf "$DEST"
mkdir -p "${DEST}/Contents/MacOS"
mkdir -p "${DEST}/Contents/Resources"
cp "${ROOT}/Scripts/Info.plist" "${DEST}/Contents/Info.plist"
# Ohne PkgInfo (APPL + Signatur) zeigt Finder mitunter nur das generische Programm-Symbol.
printf 'APPL????' > "${DEST}/Contents/PkgInfo"
cp "${ROOT}/dist/TradeERPLauncher" "$BIN"
chmod +x "$BIN"
if compgen -G "${ROOT}/Sources/TradeERPLauncherLib/Resources/*.svg" > /dev/null; then
  cp "${ROOT}/Sources/TradeERPLauncherLib/Resources/"*.svg "${DEST}/Contents/Resources/" 2>/dev/null || true
fi
RES_ICNS="${ROOT}/Sources/TradeERPLauncherLib/Resources/AppIcon.icns"
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

FS_ICON="${ROOT}/Sources/TradeERPLauncherLib/Resources/Icon.png"
if [[ -f "$FS_ICON" ]]; then
  cp "$FS_ICON" "${DEST}/Contents/Resources/Icon.png"
else
  echo "Warnung: Fehlt ${FS_ICON} — Java-Dock und FS-Client-Kacheln ohne eigenes Symbol (Icon.png ins Repo legen)." >&2
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
# Java 8: Standard = nicht ins Bundle (Erststart-Download nach Application Support).
# Nur kopieren, wenn BUNDLE_JRE8 gesetzt ist — siehe Scripts/JDK_BUNDLE.md.
if [[ -n "${BUNDLE_JRE8:-}" ]]; then
  if [[ -d "${BUNDLE_JDK_ROOT}/jre8" ]]; then
    echo "==> Kopiere eingebettetes JRE 8 aus ${BUNDLE_JDK_ROOT}/jre8 (BUNDLE_JRE8 ist gesetzt)"
    ditto "${BUNDLE_JDK_ROOT}/jre8" "${DEST}/Contents/Resources/jre8"
  else
    echo "Warnung: BUNDLE_JRE8 ist gesetzt, aber ${BUNDLE_JDK_ROOT}/jre8 fehlt — nichts kopiert." >&2
  fi
elif [[ -d "${BUNDLE_JDK_ROOT}/jre8" ]]; then
  echo "==> JRE 8: ${BUNDLE_JDK_ROOT}/jre8 wird nicht ins Bundle kopiert (nur mit BUNDLE_JRE8=1). Erststart-Download oder manuell nach Contents/Resources/jre8/."
fi

echo "Fertig: ${DEST}"
echo "JDKs: optional unter ${BUNDLE_JDK_ROOT}/ (jdk11, jdk21, jre8) — siehe Scripts/JDK_BUNDLE.md"
echo "  JRE 8 ins .app aufnehmen: BUNDLE_JRE8=1 ./Scripts/build_app.sh"
echo "  oder manuell unter Contents/Resources/ ablegen bzw. FSCL_JDK11, FSCL_JDK21, FSCL_JRE8 setzen."

echo "==> DMG (read-only, UDZO)"
# Ohne Zusatztool: `hdiutil` → nacktes Finder-Fenster.
# Mit create-dmg: Layout per AppleScript; `Scripts/dmg_finder_template.applescript` blendet die Finder-Sidebar aus
# (sonst wirkt das Fenster auf macOS 13+ oft deutlich breiter als --window-size).
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${ROOT}/Scripts/Info.plist" 2>/dev/null || echo "0")"
DMG="${ROOT}/dist/enventa-trade-erp-launcher-${VERSION}.dmg"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/fscl-dmg.XXXXXX")"
BG_TMP=""
cleanup_stage() {
  rm -rf "${STAGE}"
  [[ -n "${BG_TMP}" && -f "${BG_TMP}" ]] && rm -f "${BG_TMP}"
}
trap cleanup_stage EXIT
cp -R "${DEST}" "${STAGE}/"
rm -f "${DMG}"

if command -v create-dmg >/dev/null 2>&1; then
  echo "    → create-dmg (kompaktes Zwei-Icon-Layout; Sidebar-Template)"
  DMG_BG="${ROOT}/Scripts/dmg_install_background.png"
  DMG_BG_SWIFT="${ROOT}/Scripts/RenderDMGBackground.swift"
  # Optional: PNG bei jedem DMG-Bau neu erzeugen (gleiche Quelle wie manuell: .build/render-dmg-bg).
  if [[ -f "${DMG_BG_SWIFT}" ]] && command -v swiftc >/dev/null 2>&1; then
    mkdir -p "${ROOT}/.build"
    RDBG="${ROOT}/.build/render-dmg-bg"
    if [[ ! -x "${RDBG}" ]] || [[ "${DMG_BG_SWIFT}" -nt "${RDBG}" ]]; then
      echo "    → DMG-Hintergrund: Renderer kompilieren"
      swiftc -O "${DMG_BG_SWIFT}" -o "${RDBG}"
    fi
    echo "    → DMG-Hintergrund: PNG aus Renderer (${DMG_BG})"
    "${RDBG}" "${ROOT}"
  fi
  # Ca. „5 Icon-Breiten“ breit (wie gängige Hersteller-DMGs), App links / Programme rechts, vertikal mittig.
  ICON_SZ=88
  WIN_W=$((ICON_SZ * 5 + 96))
  WIN_H=248
  # Mit Hintergrundbild: gleiche Regeln wie Scripts/RenderDMGBackground.swift (Finder: Ecke oben links, Y ab oben).
  ICON_X=$((WIN_W * 17 / 100))
  ICON_Y=$(( (WIN_H - ICON_SZ) / 2 ))
  DROP_X=$((WIN_W * 74 / 100))
  DROP_Y="${ICON_Y}"
  CREATE_ARGS=(
    --volname "enventa Trade ERP Launcher"
    --window-pos 200 120
    --window-size "${WIN_W}" "${WIN_H}"
    --icon-size "${ICON_SZ}"
    --text-size 11
    --icon "${APP_NAME}" "${ICON_X}" "${ICON_Y}"
    --hide-extension "${APP_NAME}"
    --app-drop-link "${DROP_X}" "${DROP_Y}"
  )
  if [[ -f "${DMG_BG}" ]]; then
    # Hintergrund **außerhalb** von STAGE — sonst landet die PNG als dritte Datei im DMG-Root.
    # mktemp: die sechs X müssen am Ende der Vorlage stehen (nicht „…XXXXXX.png“).
    BG_TMP="$(mktemp "${TMPDIR:-/tmp}/fscl-dmg-bg.XXXXXX")"
    cp "${DMG_BG}" "${BG_TMP}"
    sips --setProperty dpiWidth 72 --setProperty dpiHeight 72 "${BG_TMP}" >/dev/null 2>&1 || true
    W="$(sips -g pixelWidth "${BG_TMP}" 2>/dev/null | awk '/pixelWidth/ {print $2}')"
    H="$(sips -g pixelHeight "${BG_TMP}" 2>/dev/null | awk '/pixelHeight/ {print $2}')"
    # Mindestmaße niedrig genug für festes 400×200-Hintergrund-PNG (siehe dmg_layout_constants.sh / RenderDMGBackground.swift).
    if [[ -n "${W:-}" && -n "${H:-}" ]] && [[ "$W" =~ ^[0-9]+$ && "$H" =~ ^[0-9]+$ ]] && (( W >= 200 && H >= 160 )); then
      echo "    → zusätzlich Hintergrundbild: ${DMG_BG} (${W}×${H} px)"
      # Festes Raster für 1:1-Layout — Werte aus `dmg_layout_constants.sh` (mit Render synchron halten).
      # shellcheck disable=SC1091
      if [[ -f "${ROOT}/Scripts/dmg_layout_constants.sh" ]]; then
        source "${ROOT}/Scripts/dmg_layout_constants.sh"
      fi
      if [[ "${W}" -eq "${DMG_BG_LAYOUT_W:-0}" && "${H}" -eq "${DMG_BG_LAYOUT_H:-0}" ]]; then
        ICON_X="${DMG_ICON_X}"
        ICON_Y="${DMG_ICON_Y}"
        DROP_X="${DMG_DROP_X}"
        DROP_Y="${ICON_Y}"
        WIN_OUT_W="${DMG_WINDOW_W}"
        WIN_OUT_H="${DMG_WINDOW_H}"
        echo "    → DMG-Icon-Layout: Kalibrierung PNG ${W}×${H} px, Fenster-Außenmaß ${WIN_OUT_W}×${WIN_OUT_H} (dmg_layout_constants.sh)"
      else
        ICON_X=$((W * 17 / 100))
        ICON_Y=$(( (H - ICON_SZ) / 2 ))
        DROP_X=$((W * 74 / 100))
        DROP_Y="${ICON_Y}"
        WIN_OUT_W="${W}"
        WIN_OUT_H="${H}"
        echo "    → DMG-Icon-Layout: proportional; Fenster = PNG ${W}×${H} (≠ Kalibrierung — ggf. dmg_layout_constants.sh anpassen)" >&2
      fi
      CREATE_ARGS=(
        --volname "enventa Trade ERP Launcher"
        --window-pos 200 120
        --window-size "${WIN_OUT_W}" "${WIN_OUT_H}"
        --icon-size "${ICON_SZ}"
        --text-size 11
        --background "${BG_TMP}"
        --icon "${APP_NAME}" "${ICON_X}" "${ICON_Y}"
        --hide-extension "${APP_NAME}"
        --app-drop-link "${DROP_X}" "${DROP_Y}"
      )
    else
      echo "Warnung: ${DMG_BG} — sips konnte keine gültigen Maße lesen, Standard-Layout ohne Bild." >&2
    fi
  else
    echo "    → optional: ${DMG_BG} für Motiv wie Edge/Bambu (siehe Scripts/DMG_HINTERGRUND.txt)" >&2
  fi
  FIN_W="${WIN_OUT_W:-$WIN_W}"
  FIN_H="${WIN_OUT_H:-$WIN_H}"
  echo "    → DMG-Fenster ${FIN_W}×${FIN_H} pt, Icon ${ICON_SZ} pt, App @(${ICON_X},${ICON_Y}) Programme @(${DROP_X},${DROP_Y})"
  if [[ -f "${DEST}/Contents/Resources/AppIcon.icns" ]]; then
    CREATE_ARGS+=(--volicon "${DEST}/Contents/Resources/AppIcon.icns")
  fi
  CREATE_DMG_BIN="$(command -v create-dmg)"
  if command -v brew >/dev/null 2>&1; then
    SUPPORT_SRC="$(brew --prefix)/share/create-dmg/support"
  else
    SUPPORT_SRC="$(dirname "$(dirname "${CREATE_DMG_BIN}")")/share/create-dmg/support"
  fi
  if [[ -d "$SUPPORT_SRC" && -f "${ROOT}/Scripts/dmg_finder_template.applescript" ]]; then
    SHIM="${ROOT}/.build/fscl-create-dmg"
    rm -rf "${SHIM}"
    mkdir -p "${SHIM}/support"
    touch "${SHIM}/.this-is-the-create-dmg-repo"
    echo "    → create-dmg-Shim: Finder-Template mit Sidebar-Ausblendung"
    cp "${SUPPORT_SRC}/"* "${SHIM}/support/"
    cp "${ROOT}/Scripts/dmg_finder_template.applescript" "${SHIM}/support/template.applescript"
    cp "${CREATE_DMG_BIN}" "${SHIM}/create-dmg"
    chmod +x "${SHIM}/create-dmg"
    "${SHIM}/create-dmg" "${CREATE_ARGS[@]}" "${DMG}" "${STAGE}"
  else
    create-dmg "${CREATE_ARGS[@]}" "${DMG}" "${STAGE}"
  fi
else
  echo "    → hdiutil (einfaches Finder-Fenster — für klassisches DMG: brew install create-dmg)" >&2
  ln -sf /Applications "${STAGE}/Applications"
  if hdiutil create \
    -volname "enventa Trade ERP Launcher" \
    -srcfolder "${STAGE}" \
    -ov \
    -format UDZO \
    -o "${DMG}"; then
    :
  else
    echo "Hinweis: hdiutil UDZO direkt nicht möglich — Fallback UDRW → UDZO" >&2
    RW="${ROOT}/dist/.fscl-dmg-rw-$$.dmg"
    rm -f "${RW}"
    hdiutil create \
      -volname "enventa Trade ERP Launcher" \
      -srcfolder "${STAGE}" \
      -ov \
      -format UDRW \
      -fs HFS+ \
      "${RW}"
    hdiutil convert "${RW}" -format UDZO -o "${DMG}"
    rm -f "${RW}"
  fi
fi

trap - EXIT
rm -rf "${STAGE}"
echo "DMG: ${DMG}"
echo "Hinweis: Beim geöffneten DMG zeigt die Menüleiste weiter „Finder“ — es ist ein normales Finder-Fenster (kein eigenes Mini-Programm)."
