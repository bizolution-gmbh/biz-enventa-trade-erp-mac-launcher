#!/usr/bin/env bash
# Lädt Azul Zulu 8 JDK **mit JavaFX** für macOS Apple Silicon (aarch64) und legt es unter
# BundledJDKs/jre8/ so ab, dass JavaRuntimeResolver.findJava8() es findet
# (direktes Kind: *.jdk mit Contents/Home/bin/java).
#
# Voraussetzung: curl, python3. Lizenz: Azul Zulu inkl. JavaFX-Komponenten — siehe
# https://docs.azul.com/core/tpls/ und die Dateien im entpackten JDK unter legal/.
#
# Usage:
#   ./Scripts/download_zulu8_fx_jre.sh
# Optional:
#   BUNDLED_JRE8_DIR=/Pfad/zu/jre8 ./Scripts/download_zulu8_fx_jre.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="${BUNDLED_JRE8_DIR:-${ROOT}/BundledJDKs/jre8}"
API='https://api.azul.com/metadata/v1/zulu/packages/?java_version=8&os=macos&arch=arm64&java_package_type=jdk&archive_type=tar.gz&javafx_bundled=true&page_size=1'

echo "==> Azul-Metadaten: neuestes Zulu 8 + JavaFX (macOS aarch64)"
JSON="$(curl -fsSL "$API")"
URL="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d[0]["download_url"])' <<<"$JSON")"
NAME="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d[0]["name"])' <<<"$JSON")"
VER="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(".".join(str(x) for x in d[0]["java_version"]))' <<<"$JSON")"
if [[ -z "$URL" || "$URL" == "None" ]]; then
  echo "Konnte keine Download-URL von der Azul-API lesen." >&2
  exit 1
fi
echo "    Paket: $NAME (Java $VER)"
echo "    URL:   $URL"

TMP_TAR="$(mktemp -t zulu8fx.XXXXXX.tar.gz)"
TMP_STAGE="$(mktemp -d -t zulu8fx-stage.XXXXXX)"
cleanup() { rm -f "$TMP_TAR"; rm -rf "$TMP_STAGE"; }
trap cleanup EXIT

echo "==> Download"
curl -fL --progress-bar -o "$TMP_TAR" "$URL"

echo "==> Entpacken"
tar -xzf "$TMP_TAR" -C "$TMP_STAGE"

# Erstes macOS-.jdk-Bundle unter dem Archiv (Zulu: …/zulu-8.jdk)
JDK_BUNDLE="$(find "$TMP_STAGE" -name '*.jdk' -type d | head -n 1)"
if [[ -z "$JDK_BUNDLE" ]]; then
  echo "Kein *.jdk-Verzeichnis im Archiv gefunden. Inhalt:" >&2
  find "$TMP_STAGE" -maxdepth 3 -type d >&2
  exit 1
fi

JAVA="${JDK_BUNDLE}/Contents/Home/bin/java"
if [[ ! -x "$JAVA" ]]; then
  echo "Erwartet ausführbar: $JAVA" >&2
  exit 1
fi

echo "==> Ziel: $DEST_DIR"
mkdir -p "$DEST_DIR"
echo "    Leere $DEST_DIR (alte jre8-Inhalte werden entfernt)"
rm -rf "${DEST_DIR:?}/"*

BUNDLE_NAME="zulu8-fx-macos-aarch64.jdk"
echo "    Kopiere nach ${DEST_DIR}/${BUNDLE_NAME}"
ditto "$JDK_BUNDLE" "${DEST_DIR}/${BUNDLE_NAME}"

echo "==> Prüfung"
"${DEST_DIR}/${BUNDLE_NAME}/Contents/Home/bin/java" -version

echo
echo "Fertig. Nächster Schritt: ./Scripts/build_app.sh — jre8 wird nach Contents/Resources/jre8 kopiert."
echo "Hinweis: BundledJDKs/ ist in .gitignore; das JDK bleibt lokal bis ihr es versioniert oder separat verteilt."
