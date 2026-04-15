#!/usr/bin/env bash
# Erzeugt AppIcon.icns aus enventa-mark-cropped.svg (weißer Rand, Finder-Bundle-Icon).
# Voraussetzung: rsvg-convert (z. B. brew install librsvg), swift (Xcode Command Line Tools).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Mark mit weißem Rand: rsvg platziert skaliertes Mark auf größerer Seite (-b none), Swift normalisiert zu RGBA für iconutil.
MARK_SVG="${ROOT}/Sources/FSClientLauncher/Resources/enventa-mark-cropped.svg"
NORM_SWIFT="${ROOT}/Scripts/normalize_iconset_png.swift"
PACK_SWIFT="${ROOT}/Scripts/pack_iconset_to_icns.swift"
ICONSET="${ROOT}/Sources/FSClientLauncher/Resources/AppIcon.iconset"
ICNS="${ROOT}/Sources/FSClientLauncher/Resources/AppIcon.icns"

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
[[ -f "$NORM_SWIFT" ]] || { echo "Fehlt: $NORM_SWIFT" >&2; exit 1; }
[[ -f "$PACK_SWIFT" ]] || { echo "Fehlt: $PACK_SWIFT" >&2; exit 1; }

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

render() {
  local px="$1" name="$2"
  local tmp inner pad
  tmp="$(mktemp -t fscl-icon.XXXXXX.png)"
  # ~20 % Rand: Inhalt ca. 5/8 der Ausgabeseite (entspricht 640/1024).
  inner=$(( (px * 5 + 7) / 8 ))
  if [[ "$inner" -lt 1 ]]; then inner=1; fi
  # Ohne --left/--top legt rsvg das Motiv oben links; der Rest der Seite bleibt nur rechts/unten leer.
  pad=$(( (px - inner) / 2 ))
  if [[ "$pad" -lt 0 ]]; then pad=0; fi
  rsvg-convert -w "$inner" -h "$inner" --page-width "$px" --page-height "$px" --left "$pad" --top "$pad" -b none "$MARK_SVG" -o "$tmp"
  swift "$NORM_SWIFT" "$tmp"
  mv "$tmp" "$ICONSET/$name"
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
