#!/usr/bin/env python3
"""Promoviert CHANGELOG.md: ## [Unreleased] → neuer Release-Eintrag; schreibt Notizen für gh release."""
from __future__ import annotations

import re
import sys
from pathlib import Path


def _strip_noise(lines: list[str]) -> list[str]:
    out: list[str] = []
    for line in lines:
        s = line.strip()
        if not s or s.startswith("<!--"):
            continue
        out.append(line)
    return out


def _has_release_notes(body: str) -> bool:
    """Mindestens ein Markdown-Aufzählungspunkt unter [Unreleased]."""
    for line in body.splitlines():
        if re.match(r"^\s*-\s+\S", line):
            return True
    return False


def promote(changelog_path: Path, new_version: str, iso_date: str, notes_out: Path) -> None:
    text = changelog_path.read_text(encoding="utf-8")
    marker = "## [Unreleased]"
    idx = text.find(marker)
    if idx == -1:
        sys.exit(f"CHANGELOG: Abschnitt `{marker}` fehlt in {changelog_path}")

    after_marker = idx + len(marker)
    nl = text.find("\n", after_marker)
    body_start = nl + 1 if nl != -1 else len(text)

    rest = text[body_start:]
    m = re.search(r"^## \[", rest, flags=re.MULTILINE)
    if m:
        body = rest[: m.start()]
        tail = rest[m.start() :]
    else:
        body = rest
        tail = ""

    body_stripped = body.strip()
    if not _has_release_notes(body_stripped):
        sys.exit(
            "CHANGELOG: Unter ## [Unreleased] mindestens einen Stichpunkt "
            "(`- …`) eintragen, bevor du das Release-Skript ausführst."
        )

    unreleased_template = """## [Unreleased]

### Added

### Changed

### Fixed

### Removed


"""

    new_block = f"## [{new_version}] - {iso_date}\n\n{body_stripped}\n\n"
    new_text = text[:idx] + unreleased_template + new_block + tail.lstrip("\n")
    if not new_text.endswith("\n"):
        new_text += "\n"

    changelog_path.write_text(new_text, encoding="utf-8")
    gh_notes_lines = [
        ln.rstrip()
        for ln in body_stripped.splitlines()
        if not ln.strip().startswith("<!--")
    ]
    while gh_notes_lines and not gh_notes_lines[-1].strip():
        gh_notes_lines.pop()
    notes_out.write_text("\n".join(gh_notes_lines) + "\n", encoding="utf-8")


def main() -> None:
    if len(sys.argv) != 6 or sys.argv[1] != "promote":
        prog = Path(sys.argv[0]).name
        sys.exit(
            f"Usage: {prog} promote <CHANGELOG.md> <new_version> <YYYY-MM-DD> <notes_out.txt>\n"
            "  Beispiel: changelog_promote.py promote CHANGELOG.md 4.8.0.1 2026-04-23 /tmp/notes.md"
        )
    _, _, ch_path, ver, date_s, notes_path = sys.argv
    promote(Path(ch_path), ver, date_s, Path(notes_path))


if __name__ == "__main__":
    main()
