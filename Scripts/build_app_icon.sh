#!/usr/bin/env bash
# Erzeugt AppIcon.icns aus Bildmarke + Play-Symbol: `bizolution-mark-farbe-rgb.svg` + `app-icon-play.svg`
# werden per rsvg gerendert und mit `composite_app_icon_png.swift` zusammengefügt (Play separat austauschbar/justierbar).
# Anschließend weißer Rand, abgerundete transparente Außenkanten (normalize_iconset_png.swift).
# Neuaufbau nur bei fehlender .icns oder neueren Eingaben (SVG + Icon-Skripte), damit unnötige Byte-Drifts beim Build entfallen.
# Voraussetzung: rsvg-convert (z. B. brew install librsvg), swift (Xcode Command Line Tools).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Mark mit weißem Rand: rsvg platziert skaliertes Mark auf größerer Seite (-b none), Swift normalisiert zu RGBA für iconutil.
MARK_SVG="${ROOT}/Sources/TradeERPLauncherLib/Resources/bizolution-mark-farbe-rgb.svg"
PLAY_SVG="${ROOT}/Sources/TradeERPLauncherLib/Resources/app-icon-play.svg"
NORM_SWIFT="${ROOT}/Scripts/normalize_iconset_png.swift"
COMPOSITE_SWIFT="${ROOT}/Scripts/composite_app_icon_png.swift"
PACK_SWIFT="${ROOT}/Scripts/pack_iconset_to_icns.swift"
ICONSET="${ROOT}/Sources/TradeERPLauncherLib/Resources/AppIcon.iconset"
ICNS="${ROOT}/Sources/TradeERPLauncherLib/Resources/AppIcon.icns"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "rsvg-convert nicht gefunden — AppIcon.icns wird nicht neu erzeugt." >&2
  echo "  brew install librsvg" >&2
  echo "  $0" >&2
  exit 1
fi
if ! command -v swift >/dev/null 2>&1; then
  echo "swift nicht gefunden — bitte Xcode Command Line Tools installieren (xcode-select --install)." >&2
  exit 1
fi

[[ -f "$MARK_SVG" ]] || { echo "Fehlt: $MARK_SVG" >&2; exit 1; }
[[ -f "$PLAY_SVG" ]] || { echo "Fehlt: $PLAY_SVG" >&2; exit 1; }
[[ -f "$NORM_SWIFT" ]] || { echo "Fehlt: $NORM_SWIFT" >&2; exit 1; }
[[ -f "$COMPOSITE_SWIFT" ]] || { echo "Fehlt: $COMPOSITE_SWIFT" >&2; exit 1; }
[[ -f "$PACK_SWIFT" ]] || { echo "Fehlt: $PACK_SWIFT" >&2; exit 1; }

# Neuaufbau nur, wenn .icns fehlt oder Quelle/Skripte neuer sind (vermeidet bei jedem Build andere PNG-/Encoder-Bytes).
ICON_DEPS=(
  "$MARK_SVG"
  "$PLAY_SVG"
  "$NORM_SWIFT"
  "$COMPOSITE_SWIFT"
  "$PACK_SWIFT"
  "${ROOT}/Scripts/build_app_icon.sh"
)
if [[ -f "$ICNS" ]]; then
  skip=true
  for f in "${ICON_DEPS[@]}"; do
    if [[ "$f" -nt "$ICNS" ]]; then
      skip=false
      break
    fi
  done
  if [[ "$skip" == true ]]; then
    echo "==> $ICNS ist aktuell (SVG und Icon-Skripte nicht neuer) — überspringe Neuaufbau."
    exit 0
  fi
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

render() {
  local px="$1" name="$2"
  local tmp_mark tmp_play tmp_comp inner pad
  tmp_mark="$(mktemp -t fscl-mark.XXXXXX.png)"
  tmp_play="$(mktemp -t fscl-play.XXXXXX.png)"
  tmp_comp="$(mktemp -t fscl-icon.XXXXXX.png)"
  # ~12,5 % Rand: Inhalt ca. 7/8 der Ausgabeseite (896/1024), Marke wirkt größer in der Squircle.
  inner=$(( (px * 7 + 4) / 8 ))
  if [[ "$inner" -lt 1 ]]; then inner=1; fi
  pad=$(( (px - inner) / 2 ))
  if [[ "$pad" -lt 0 ]]; then pad=0; fi
  rsvg-convert -w "$inner" -h "$inner" --page-width "$px" --page-height "$px" --left "$pad" --top "$pad" -b none "$MARK_SVG" -o "$tmp_mark"
  # Play: gleiches viewBox/Raster wie Marke (quadratisch), Dreieck liegt nur im SVG im unteren rechten Quadranten.
  rsvg-convert -w "$inner" -h "$inner" --page-width "$px" --page-height "$px" --left "$pad" --top "$pad" -b none "$PLAY_SVG" -o "$tmp_play"
  swift "$COMPOSITE_SWIFT" "$tmp_mark" "$tmp_play" 0 0 "$tmp_comp"
  rm -f "$tmp_mark" "$tmp_play"
  swift "$NORM_SWIFT" "$tmp_comp"
  mv "$tmp_comp" "$ICONSET/$name"
}

render 16 icon_16x16.png
render 32 icon_16x16@2x.png
render 32 icon_32x32.png
render 64 icon_32x32@2x.png
render 128 icon_128x128.png
render 256 icon_128x128@2x.png
render 256 icon_256x256.png
render 512 icon_256x256@2x.png
render 512 icon_512x512.png
render 1024 icon_512x512@2x.png

# iconutil lehnt u. a. bei com.apple.provenance-xattr auf (Swift/mktemp).
xattr -cr "$ICONSET"

# Nie direkt nach $ICNS schreiben: bei Fehler kann iconutil die Datei leeren/zerstören.
# iconutil verlangt für --output / -o eine Pfadendung ".icns" (sonst nur „Invalid arguments“).
ICNS_PART="${ICNS%.icns}.particon.$$.$RANDOM.icns"
rm -f "$ICNS_PART"
iconutil_ok=0
iconutil_err="$(mktemp -t fscl-iconutil.XXXXXX.err)"
if iconutil -c icns "$ICONSET" -o "$ICNS_PART" 2>"$iconutil_err"; then
  iconutil_ok=1
fi
if [[ "$iconutil_ok" != "1" ]] || [[ ! -s "$ICNS_PART" ]]; then
  rm -f "$ICNS_PART"
  if [[ -s "$iconutil_err" ]]; then
    echo "iconutil meldet:" >&2
    sort -u "$iconutil_err" | sed 's/^/  /' >&2 || true
  fi
  rm -f "$iconutil_err"
  echo "iconutil fehlgeschlagen — versuche Fallback (Swift-Packer) …" >&2
  if ! swift "$PACK_SWIFT" "$ICONSET" "$ICNS_PART"; then
    echo "Auch Fallback fehlgeschlagen — $ICNS bleibt unverändert (falls vorhanden)." >&2
    exit 1
  fi
else
  rm -f "$iconutil_err"
fi
if ! file "$ICNS_PART" | grep -q 'Mac OS X icon'; then
  rm -f "$ICNS_PART"
  echo "Die erzeugte Datei ist keine gültige .icns — $ICNS bleibt unverändert." >&2
  exit 1
fi
mv -f "$ICNS_PART" "$ICNS"
echo "==> $ICNS erzeugt."
