# Changelog

Alle nennenswerten Änderungen an diesem Projekt werden hier dokumentiert (Bizolution **Mac**-Launcher für enventa Trade ERP).

Das Format orientiert sich an [Keep a Changelog](https://keepachangelog.com/de/1.1.0/).

**Versionszeile:** `CFBundleShortVersionString` = **Major.Minor.Herstellerzeile.Mac-Iteration** (z. B. `4.8.0.1` solange die Hersteller-Linie `4.8.0` aktuell ist; nach Hersteller-Update z. B. `4.8.1.0`).  
**Build:** `CFBundleVersion` steigt **monoton** unabhängig davon (siehe `Scripts/release.sh`).

## [Unreleased]

### Added

### Changed

### Fixed

### Removed


## [4.8.0.3] - 2026-09-16

### Added

### Changed

- Mitgelieferte Java-8-Quelle: Azul Zulu **8u504** (zulu8.96.0.205, CA + JavaFX) statt 8u482; SHA-256 aus der Azul-Metadaten-API, Eintrags-IDs unverändert.

### Fixed

- Gepackte `.app` stürzte beim Öffnen der Einstellungen ab (`fatalError` in `Bundle.module`): das SPM-Resource-Bundle wurde nicht mit ins Bundle kopiert. Ressourcen werden jetzt ohne diesen Accessor geladen, `build_app.sh` legt `TradeERPLauncher_TradeERPLauncherLib.bundle` in die `.app`.

### Removed

## [4.8.0.2] - 2026-09-16

### Added

### Changed

### Fixed

- Java-8-Download erkennt Azul-Zulu-8-tar.gz seit April 2026 (Top-Level-Ordner ohne `.jdk`, `Contents/Home` direkt darunter); zuvor scheiterte das Entpacken mit „kein \*.jdk-Bundle“.
- DMG-Erzeugung: Finder-AppleScript an die aktuelle create-dmg-Signatur (Datenträgername + Mount-Pfad) angepasst.

### Removed

## [4.8.0.1] - 2026-05-20

### Added

- **Erstes Release** des **enventa Trade ERP Launcher** für macOS — inoffizielles Pendant zum Windows-**FS Client Launcher**, bereitgestellt von der **BIZOLUTION GmbH** (kein offizielles Produkt der enventa Group). Auslieferung als **DMG** (nicht signiert/notarisiert); Installation siehe [README.md](README.md).
- Start des ERP-Java-Clients über **Broker-URLs**, **`.fsclient`**-JSON, URL-Schema **`fsclientlauncher:…`** sowie gespeicherte **registrierte Anwendungen** in der **Menüleiste**.
- Registrierte Anwendungen: Typ **Client-Anwendung** (Broker-/Definitions-URL, z. B. per „Download Jnlp“-Link aus dem Browser) und Typ **Weblink** (beliebige http(s)-URL im **Standardbrowser**); optional **Broker-Icons** in Menüleiste und Einstellungen.
- **Java 8 / 11 / 21** je nach Broker; bei Bedarf **Download von Java 8 mit JavaFX** (Azul Zulu) in die Launcher-Daten unter Application Support.
- **Einstellungen:** JVM-Argumente (pro erkannter Java-Version), Java-Laufzeitumgebungen, registrierte Anwendungen, Tab **Über** mit Versions- und Anbieterhinweis.
- Einmalige **Migration** älterer Launcher-Daten nach `~/Library/Application Support/bizolution/enventa Trade ERP Launcher/` (und Caches unter `bizolution/`).
- Dokumentation: [README.md](README.md) (Installation inkl. Quarantäne, Nutzung, ERP-Voraussetzungen), [docs/Entwicklung.md](docs/Entwicklung.md), [NOTICE](NOTICE), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- Lizenz des Quellcodes: **GNU GPL v3.0** ([LICENSE](LICENSE)).
- GitHub Actions: Workflow **Swift** (Release-Build und Tests auf `macos-latest`).

### Changed

- Launcher-Produkt und Datenpfade: **enventa Trade ERP Launcher**, Ablage unter **bizolution**; Bizolution-Branding in der Oberfläche (ERP-Client behält eigene Dock-Icons).
- Release-Prozess: `Scripts/release.sh` erzeugt Version/CHANGELOG/Git-Tag, baut per `Scripts/build_app.sh` eine **DMG** und lädt sie bei `--push` auf **GitHub Releases** hoch (`--no-dmg` zum Überspringen).

