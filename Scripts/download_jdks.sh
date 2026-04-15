#!/usr/bin/env bash
# Lädt Eclipse Temurin für macOS (aarch64) nach Contents/Resources — nur ausführen, wenn die Lizenz passt.
set -euo pipefail
ARCH="${1:-aarch64}"
RES="${2:?Verwendung: $0 [aarch64|x64] <Pfad-zu-Contents/Resources>}"
mkdir -p "$RES"

download_temurin() {
  local version="$1"
  local url
  url="$(curl -fsS "https://api.adoptium.net/v3/binary/latest/${version}/ga/mac/${ARCH}/jdk/hotspot/normal/eclipse" -w '%{url_effective}' -o /dev/null)"
  echo "==> JDK ${version} von ${url}"
  local tmp
  tmp="$(mktemp -t jdk${version}.tar.gz.XXXX)"
  curl -fL "$url" -o "$tmp"
  tar -xzf "$tmp" -C "$RES"
  rm -f "$tmp"
}

download_temurin 11
download_temurin 21
echo "Entpackte Verzeichnisse unter $RES bitte in jdk11/ bzw. jdk21/ sortieren, z. B.:"
echo "  mkdir -p \"$RES/jdk11\" && mv \"$RES\"/jdk-11* \"$RES/jdk11/\""
echo "Für wiederholbare Builds: gleiche Struktur unter Projekt/BundledJDKs/ anlegen; build_app.sh kopiert sie ins Bundle (siehe Scripts/JDK_BUNDLE.md)."
