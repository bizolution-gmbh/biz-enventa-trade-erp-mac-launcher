#!/usr/bin/env bash
# Release: CFBundleShortVersionString / CFBundleVersion in Scripts/Info.plist,
# CHANGELOG [Unreleased] → neuer Eintrag, ./Scripts/build_app.sh (DMG),
# Git-Commit, annotierter Tag v…, optional Push + GitHub-Release inkl. DMG-Upload.
#
# Pro Aufruf werden zwei Commits erzeugt:
#   1) Release-Commit: BizolutionPreReleaseTag entfernt, Version = next_short, Build = NEXT_BUILD
#      (Tag v… zeigt auf diesen Commit; DMG/Notes/Asset gehören dazu).
#   2) Folge-Commit:  Version = next_dev_short, Build = NEXT_DEV_BUILD, BizolutionPreReleaseTag = "dev"
#      (Vorab-Iteration für die kommende Mac-/Hersteller-Version, "Maven-/Gradle-Snapshot-Stil").
#
# Trägt die Plist bereits einen Vorab-Tag (z. B. 4.8.0.2-dev), ist die Plist-Version exakt die
# Release-Version: --mac/--vendor/--set werden für die *nachfolgende* Vorab-Iteration ausgewertet,
# aber nicht erneut auf die Release-Version angewandt.
#
# Voraussetzungen: git, /usr/libexec/PlistBuddy, python3, swift/Xcode (build_app.sh);
# für --push: gh (gh auth login).
#
# Beispiele:
#   ./Scripts/release.sh --mac
#   ./Scripts/release.sh --vendor
#   ./Scripts/release.sh --set 4.8.1.0
#   ./Scripts/release.sh --mac --push
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="${ROOT}/Scripts/Info.plist"
CHANGELOG="${ROOT}/CHANGELOG.md"
PROMOTE_PY="${ROOT}/Scripts/changelog_promote.py"
BUILD_APP="${ROOT}/Scripts/build_app.sh"

MODE=""
SET_VER=""
DRY_RUN=0
DO_PUSH=0
ALLOW_DIRTY=0
DO_BUILD_DMG=1
BRANCH="main"

die() { echo "release.sh: $*" >&2; exit 1; }

usage() {
  cat >&2 <<'EOF'
Usage: ./Scripts/release.sh --mac | --vendor | --set X.Y.Z.W [--push] [--dry-run] [--allow-dirty] [--branch NAME] [--no-dmg]

  --mac       Vierte Stelle +1 (4.8.0 → 4.8.0.1, 4.8.0.3 → 4.8.0.4).
  --vendor    Dritte Stelle +1, vierte auf 0 (z. B. 4.8.0.7 → 4.8.1.0).
  --set V     Explizite neue CFBundleShortVersionString (vier Segmente empfohlen).

  --push      git push, Tag, gh release create + DMG-Upload (dist/enventa-trade-erp-launcher-<Version>.dmg)
  --no-dmg    Kein build_app.sh und kein DMG-Upload (nur Version/CHANGELOG/Git).
  --dry-run   Nur anzeigen, nichts schreiben.
  --allow-dirty  Commit trotz dirty working tree (Vorsicht).
  --branch    Zielbranch für Push (Default: main).

Umgebung:
  GH_REPO     optional owner/repo, falls gh nicht aus dem Remote erraten soll.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mac) MODE=mac ;;
    --vendor) MODE=vendor ;;
    --set)
      shift
      [[ $# -gt 0 ]] || die "--set erwartet eine Version"
      SET_VER="$1"
      MODE=set
      ;;
    --dry-run) DRY_RUN=1 ;;
    --push) DO_PUSH=1 ;;
    --no-dmg) DO_BUILD_DMG=0 ;;
    --allow-dirty) ALLOW_DIRTY=1 ;;
    --branch)
      shift
      [[ $# -gt 0 ]] || die "--branch erwartet einen Namen"
      BRANCH="$1"
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unbekannte Option: $1" ;;
  esac
  shift
done

[[ -n "$MODE" ]] || { usage; exit 1; }

[[ -f "$PLIST" ]] || die "Fehlt: $PLIST"
[[ -f "$CHANGELOG" ]] || die "Fehlt: $CHANGELOG"
[[ -f "$PROMOTE_PY" ]] || die "Fehlt: $PROMOTE_PY"
[[ -f "$BUILD_APP" ]] || die "Fehlt: $BUILD_APP"

command -v /usr/libexec/PlistBuddy >/dev/null || die "PlistBuddy nicht gefunden"
command -v python3 >/dev/null || die "python3 nicht gefunden"

if [[ "$DO_PUSH" -eq 1 ]]; then
  command -v gh >/dev/null || die "gh nicht im PATH (für --push mit GitHub-Release nötig)"
  gh auth status >/dev/null 2>&1 || die "gh nicht angemeldet: gh auth login"
fi

if [[ "$ALLOW_DIRTY" -eq 0 ]]; then
  if ! git -C "$ROOT" diff --quiet || ! git -C "$ROOT" diff --cached --quiet; then
    die "Working Tree nicht leer. Änderungen committen/stashen oder --allow-dirty."
  fi
fi

CUR_BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [[ "$CUR_BRANCH" != "$BRANCH" ]]; then
  die "Aktueller Git-Branch ist '$CUR_BRANCH', erwartet '$BRANCH' (Anpassung: --branch $CUR_BRANCH)."
fi

CUR_SHORT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null || true)"
CUR_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST" 2>/dev/null || true)"
CUR_DEV_TAG="$(/usr/libexec/PlistBuddy -c 'Print :BizolutionPreReleaseTag' "$PLIST" 2>/dev/null || true)"
[[ -n "$CUR_SHORT" ]] || die "CFBundleShortVersionString lesen fehlgeschlagen"
[[ -n "$CUR_BUILD" ]] || die "CFBundleVersion lesen fehlgeschlagen"

if ! [[ "$CUR_BUILD" =~ ^[0-9]+$ ]]; then
  die "CFBundleVersion ist keine Ganzzahl: $CUR_BUILD"
fi

# Hilfsfunktion: vier Segmente aus einer Versionszeichenkette lesen.
# Nutzung: parse_version "4.8.0.1" → setzt PV_M, PV_MI, PV_P, PV_R
parse_version() {
  local raw="$1"
  IFS='.' read -ra PARTS <<< "$raw"
  local n="${#PARTS[@]}"
  case "$n" in
    2) PV_M="${PARTS[0]}"; PV_MI="${PARTS[1]}"; PV_P=0; PV_R=0 ;;
    3) PV_M="${PARTS[0]}"; PV_MI="${PARTS[1]}"; PV_P="${PARTS[2]}"; PV_R=0 ;;
    4) PV_M="${PARTS[0]}"; PV_MI="${PARTS[1]}"; PV_P="${PARTS[2]}"; PV_R="${PARTS[3]}" ;;
    *) die "Unerwartete Anzahl Segmente in Version: $raw ($n)" ;;
  esac
  [[ "$PV_M" =~ ^[0-9]+$ && "$PV_MI" =~ ^[0-9]+$ && "$PV_P" =~ ^[0-9]+$ && "$PV_R" =~ ^[0-9]+$ ]] || \
    die "Nicht-numerische Segmente in: $raw"
}

# Vorab-Iteration nach einer Release-Version berechnen (gleiche Regel wie der gewählte Mode für die
# Release-Bestimmung; --set verhält sich wie --mac für die Vorab-Iteration).
compute_next_dev_short() {
  local mode="$1" m="$2" mi="$3" p="$4" r="$5"
  case "$mode" in
    mac|set) echo "${m}.${mi}.${p}.$((r + 1))" ;;
    vendor)  echo "${m}.${mi}.$((p + 1)).0" ;;
    *) die "Unbekannter Mode: $mode" ;;
  esac
}

# PlistBuddy: String-Key (re-)setzen — alten Wert löschen, neuen Wert anlegen (auch Migrationsfall).
plist_set_string() {
  local key="$1" value="$2"
  if /usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Delete :$key" "$PLIST"
  fi
  /usr/libexec/PlistBuddy -c "Add :$key string $value" "$PLIST"
}

# PlistBuddy: String-Key löschen (kein Fehler, wenn nicht vorhanden).
plist_delete_key() {
  local key="$1"
  if /usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Delete :$key" "$PLIST"
  fi
}

parse_version "$CUR_SHORT"
m="$PV_M"; mi="$PV_MI"; p="$PV_P"; r="$PV_R"

next_short=""
if [[ -n "$CUR_DEV_TAG" ]]; then
  # Plist trägt bereits eine Vorab-Version: das ist die geplante Release-Version,
  # --mac/--vendor/--set bleiben relevant für die *folgende* Vorab-Iteration.
  next_short="$CUR_SHORT"
  NEXT_BUILD="$CUR_BUILD"
  if [[ "$MODE" == "set" && "$SET_VER" != "$CUR_SHORT" ]]; then
    die "--set $SET_VER widerspricht der bereits vorbereiteten Vorab-Version $CUR_SHORT (BizolutionPreReleaseTag=$CUR_DEV_TAG). Erst Vorab-Tag entfernen oder Version anpassen."
  fi
else
  case "$MODE" in
    mac)
      next_short="${m}.${mi}.${p}.$((r + 1))"
      ;;
    vendor)
      next_short="${m}.${mi}.$((p + 1)).0"
      ;;
    set)
      next_short="$SET_VER"
      IFS='.' read -ra Q <<< "$next_short"
      [[ "${#Q[@]}" -eq 4 ]] || die "--set erwartet vier Segmente (z. B. 4.8.1.0), ist: $next_short"
      for seg in "${Q[@]}"; do
        [[ "$seg" =~ ^[0-9]+$ ]] || die "--set: Segment nicht numerisch: $seg"
      done
      ;;
  esac
  NEXT_BUILD=$((CUR_BUILD + 1))
fi

# Vorab-Iteration nach dem Release: erneuter Bump auf Basis der eben festgelegten Release-Version.
parse_version "$next_short"
NEXT_DEV_SHORT="$(compute_next_dev_short "$MODE" "$PV_M" "$PV_MI" "$PV_P" "$PV_R")"
NEXT_DEV_BUILD=$((NEXT_BUILD + 1))
NEXT_DEV_TAG="dev"

TAG="v${next_short}"
DATE_ISO="$(date +%Y-%m-%d)"
NOTES_PRE="${ROOT}/.build/release-notes-${next_short}.md"
mkdir -p "${ROOT}/.build"

if [[ -n "$CUR_DEV_TAG" ]]; then
  echo "==> Aktuell: CFBundleShortVersionString=$CUR_SHORT CFBundleVersion=$CUR_BUILD BizolutionPreReleaseTag=$CUR_DEV_TAG"
else
  echo "==> Aktuell: CFBundleShortVersionString=$CUR_SHORT CFBundleVersion=$CUR_BUILD (kein Vorab-Tag)"
fi
echo "==> Release: CFBundleShortVersionString=$next_short CFBundleVersion=$NEXT_BUILD BizolutionPreReleaseTag=(leer)"
echo "==> Folge:   CFBundleShortVersionString=$NEXT_DEV_SHORT CFBundleVersion=$NEXT_DEV_BUILD BizolutionPreReleaseTag=$NEXT_DEV_TAG"
DMG="${ROOT}/dist/enventa-trade-erp-launcher-${next_short}.dmg"

echo "==> Tag:     $TAG"
if [[ "$DO_BUILD_DMG" -eq 1 ]]; then
  echo "==> DMG:    $DMG (via build_app.sh)"
else
  echo "==> DMG:    übersprungen (--no-dmg)"
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "(dry-run: keine Änderungen)"
  if [[ "$DO_BUILD_DMG" -eq 1 && "$DO_PUSH" -eq 1 ]]; then
    echo "  Mit --push: build_app.sh, gh release create, gh release upload → $DMG"
  fi
  exit 0
fi

python3 "$PROMOTE_PY" promote "$CHANGELOG" "$next_short" "$DATE_ISO" "$NOTES_PRE"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $next_short" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEXT_BUILD" "$PLIST"
plist_delete_key "BizolutionPreReleaseTag"

if [[ "$DO_BUILD_DMG" -eq 1 ]]; then
  echo "==> DMG bauen (build_app.sh)"
  bash "$BUILD_APP"
  [[ -f "$DMG" ]] || die "DMG fehlt nach build_app.sh: $DMG"
  [[ -s "$DMG" ]] || die "DMG ist leer: $DMG"
  echo "==> DMG bereit: $DMG ($(du -h "$DMG" | awk '{print $1}'))"
fi

git -C "$ROOT" add "$PLIST" "$CHANGELOG"
git -C "$ROOT" commit -m "Release ${TAG}"

git -C "$ROOT" tag -a "$TAG" -m "Release ${TAG}"

# Folge-Commit: Vorab-Iteration (Maven-/Gradle-Snapshot-Stil) — markiert alle weiteren Builds
# bis zum nächsten Release als „<NEXT_DEV_SHORT>-<NEXT_DEV_TAG>“ (z. B. 4.8.0.3-dev).
echo "==> Folge-Commit: Vorab-Iteration ${NEXT_DEV_SHORT}-${NEXT_DEV_TAG} (Build ${NEXT_DEV_BUILD})"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEXT_DEV_SHORT" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEXT_DEV_BUILD" "$PLIST"
plist_set_string "BizolutionPreReleaseTag" "$NEXT_DEV_TAG"
git -C "$ROOT" add "$PLIST"
git -C "$ROOT" commit -m "chore(version): Vorab-Iteration ${NEXT_DEV_SHORT}-${NEXT_DEV_TAG}"

REL_TITLE="enventa Trade ERP Launcher ${next_short}"

if [[ "$DO_PUSH" -eq 1 ]]; then
  # Reihenfolge: erst Branch (Release-Commit + Folge-Commit), dann Tag (zeigt auf Release-Commit).
  git -C "$ROOT" push origin "$BRANCH"
  git -C "$ROOT" push origin "$TAG"
  # Kein leeres Array unter "${arr[@]}" mit set -u (macOS-/bin/bash 3.2).
  if [[ -n "${GH_REPO:-}" ]]; then
    gh release create "$TAG" --title "$REL_TITLE" --notes-file "$NOTES_PRE" --latest --repo "$GH_REPO"
    if [[ "$DO_BUILD_DMG" -eq 1 ]]; then
      echo "==> DMG zu GitHub-Release hochladen"
      gh release upload "$TAG" "$DMG" --clobber --repo "$GH_REPO"
    fi
  else
    gh release create "$TAG" --title "$REL_TITLE" --notes-file "$NOTES_PRE" --latest
    if [[ "$DO_BUILD_DMG" -eq 1 ]]; then
      echo "==> DMG zu GitHub-Release hochladen"
      gh release upload "$TAG" "$DMG" --clobber
    fi
  fi
  rm -f "$NOTES_PRE"
  echo "==> Fertig: Push + GitHub-Release $TAG"
  if [[ "$DO_BUILD_DMG" -eq 1 ]]; then
    echo "    Asset: $DMG"
  fi
else
  echo "==> Lokal fertig (Release-Commit + Tag + Folge-Commit). Optional:"
  echo "    git push origin $BRANCH && git push origin $TAG"
  echo "    gh release create $TAG --title \"$REL_TITLE\" --notes-file \"$NOTES_PRE\" --latest"
  if [[ "$DO_BUILD_DMG" -eq 1 ]]; then
    echo "    gh release upload $TAG \"$DMG\" --clobber"
  fi
  echo "    rm -f \"$NOTES_PRE\""
fi
