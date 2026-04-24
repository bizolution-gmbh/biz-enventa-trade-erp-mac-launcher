# Changelog

Alle nennenswerten Änderungen an diesem Projekt werden hier dokumentiert (Bizolution **Mac**-Launcher für enventa Trade ERP).

Das Format orientiert sich an [Keep a Changelog](https://keepachangelog.com/de/1.1.0/).

**Versionszeile:** `CFBundleShortVersionString` = **Major.Minor.Herstellerzeile.Mac-Iteration** (z. B. `4.8.0.1` solange die Hersteller-Linie `4.8.0` aktuell ist; nach Hersteller-Update z. B. `4.8.1.0`).  
**Build:** `CFBundleVersion` steigt **monoton** unabhängig davon (siehe `Scripts/release.sh`).

## [Unreleased]

### Added

- Registrierte Anwendungen: Eintragstyp **Weblink** — beliebige **http(s)-URL** wird unverändert im **Standardbrowser** geöffnet; **Globus**-Symbol in Menüleiste und Einstellungen; JSON-Feld `targetKind` (`launcher` oder `web`).
- `Scripts/release.sh` (u. a. `--mac`, `--vendor`, `--set`, optional `--push` mit `gh release create`) und `Scripts/changelog_promote.py`; Projekt-`CHANGELOG.md`.
- Cursor-Regel: vor Release den Abschnitt `[Unreleased]` mit Stichpunkten füllen.

### Changed

### Fixed

### Removed

<!-- Vor `./Scripts/release.sh`: [Unreleased] wie oben pflegen (mindestens ein „- …“). -->
