#!/usr/bin/env bash
# Release: CFBundleShortVersionString / CFBundleVersion in Scripts/Info.plist,
# CHANGELOG [Unreleased] → neuer Eintrag, Git-Commit, annotierter Tag v…,
# optional Push + GitHub-Release (gh).
#
# Voraussetzungen: git, /usr/libexec/PlistBuddy, python3; für Fall B: gh (gh auth login).
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

MODE=""
SET_VER=""
DRY_RUN=0
DO_PUSH=0
ALLOW_DIRTY=0
BRANCH="main"

die() { echo "release.sh: $*" >&2; exit 1; }

usage() {
  cat >&2 <<'EOF'
Usage: ./Scripts/release.sh --mac | --vendor | --set X.Y.Z.W [--push] [--dry-run] [--allow-dirty] [--branch NAME]

  --mac       Vierte Stelle +1 (4.8.0 → 4.8.0.1, 4.8.0.3 → 4.8.0.4).
  --vendor    Dritte Stelle +1, vierte auf 0 (z. B. 4.8.0.7 → 4.8.1.0).
  --set V     Explizite neue CFBundleShortVersionString (vier Segmente empfohlen).

  --push      git push origin <branch> && git push origin v… && gh release create …
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
[[ -n "$CUR_SHORT" ]] || die "CFBundleShortVersionString lesen fehlgeschlagen"
[[ -n "$CUR_BUILD" ]] || die "CFBundleVersion lesen fehlgeschlagen"

if ! [[ "$CUR_BUILD" =~ ^[0-9]+$ ]]; then
  die "CFBundleVersion ist keine Ganzzahl: $CUR_BUILD"
fi

IFS='.' read -ra PARTS <<< "$CUR_SHORT"
n="${#PARTS[@]}"
m="" mi="" p="" r=""

case "$n" in
  2)
    m="${PARTS[0]}"; mi="${PARTS[1]}"; p=0; r=0
    ;;
  3)
    m="${PARTS[0]}"; mi="${PARTS[1]}"; p="${PARTS[2]}"; r=0
    ;;
  4)
    m="${PARTS[0]}"; mi="${PARTS[1]}"; p="${PARTS[2]}"; r="${PARTS[3]}"
    ;;
  *)
    die "Unerwartete Anzahl Segmente in CFBundleShortVersionString: $CUR_SHORT ($n)"
    ;;
esac

[[ "$m" =~ ^[0-9]+$ && "$mi" =~ ^[0-9]+$ && "$p" =~ ^[0-9]+$ && "$r" =~ ^[0-9]+$ ]] || \
  die "Nicht-numerische Segmente in: $CUR_SHORT"

next_short=""
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
TAG="v${next_short}"
DATE_ISO="$(date +%Y-%m-%d)"
NOTES_PRE="${ROOT}/.build/release-notes-${next_short}.md"
mkdir -p "${ROOT}/.build"

echo "==> Aktuell: CFBundleShortVersionString=$CUR_SHORT CFBundleVersion=$CUR_BUILD"
echo "==> Neu:     CFBundleShortVersionString=$next_short CFBundleVersion=$NEXT_BUILD"
echo "==> Tag:     $TAG"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "(dry-run: keine Änderungen)"
  exit 0
fi

python3 "$PROMOTE_PY" promote "$CHANGELOG" "$next_short" "$DATE_ISO" "$NOTES_PRE"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $next_short" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEXT_BUILD" "$PLIST"

git -C "$ROOT" add "$PLIST" "$CHANGELOG"
git -C "$ROOT" commit -m "Release ${TAG}"

git -C "$ROOT" tag -a "$TAG" -m "Release ${TAG}"

REL_TITLE="enventa Trade ERP Launcher ${next_short}"

if [[ "$DO_PUSH" -eq 1 ]]; then
  git -C "$ROOT" push origin "$BRANCH"
  git -C "$ROOT" push origin "$TAG"
  gh_args=(release create "$TAG" --title "$REL_TITLE" --notes-file "$NOTES_PRE" --latest)
  if [[ -n "${GH_REPO:-}" ]]; then
    gh_args+=(--repo "$GH_REPO")
  fi
  gh "${gh_args[@]}"
  rm -f "$NOTES_PRE"
  echo "==> Fertig: Push + GitHub-Release $TAG"
else
  echo "==> Lokal fertig (Commit + Tag). Optional:"
  echo "    git push origin $BRANCH && git push origin $TAG"
  echo "    gh release create $TAG --title \"$REL_TITLE\" --notes-file \"$NOTES_PRE\" --latest"
  echo "    rm -f \"$NOTES_PRE\""
fi
