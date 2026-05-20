# Drittanbieter-Hinweise (Kurzfassung)

Diese Datei fasst **mitgelieferte oder zur Laufzeit bezogene** Komponenten und **Build-Werkzeuge** zusammen. Sie ersetzt keine Rechtsberatung.

**Lizenz dieses Projekts (eigener Quellcode):** [GNU General Public License v3.0](LICENSE) (Copyright © 2026 BIZOLUTION GmbH).

**Swift Package Manager:** keine externen Paket-Abhängigkeiten in `Package.swift` — nur Standard-Bibliothek und Apple-Frameworks (AppKit, Foundation, WebKit, …).

## Mitgeliefert oder per Launcher-Download

| Komponente | Kontext | Hinweis |
|------------|---------|---------|
| **Azul Zulu 8 + JavaFX** | Optionaler Download in den Launcher-Daten (`Application Support`), konfigurierbar unter *Java-Laufzeitumgebungen* (Built-in-URLs aus `Java8RuntimeCatalog.json`) | Lizenz- und Drittanbieterinformationen des **jeweiligen JDK-Pakets** liegen im entpackten Ordner; Übersicht u. a. unter [Azul Core — Third-party licenses](https://docs.azul.com/core/tpls/). Die App zeigt vor dem Download einen entsprechenden Hinweis. |
| **Eclipse Temurin** (o. ä.) JDK 11/21 | Optional ins `.app`-Bundle kopiert (`BundledJDKs/`, siehe `Scripts/JDK_BUNDLE.md`) | **Unverändertes** Binärpaket nur mit den **mitgelieferten** Lizenz- und NOTICE-Dateien des Herstellers verteilen. |
| **Apple macOS SDK** | Swift, AppKit, WebKit, … | Nutzung gemäß **Apple Xcode-** bzw. **Plattformlizenz**. |

## Nur zur Build-Zeit (nicht Teil des ausgelieferten Launchers)

| Werkzeug | Typische Lizenz | Hinweis |
|----------|-----------------|--------|
| **`rsvg-convert`** (Paket **librsvg**, z. B. Homebrew **librsvg**) | häufig **LGPL** | Wird nur als **externes** Kommando zum Erzeugen von PNG/Iconset aufgerufen (**kein** Link der LGPL-Bibliothek in die TradeERPLauncher-Binary). |
| **`iconutil`**, **`hdiutil`**, **`swift`/`swiftc`** | Apple / System | Build auf macOS. |
| **`create-dmg`** (optional) | typischerweise **MIT** (Projekt [create-dmg/create-dmg](https://github.com/create-dmg/create-dmg)) | Nur für DMG-Erzeugung; externes Kommandozeilen-Tool, nicht in der Launcher-Binary. |

## Eigene Marken / Grafiken

Bizolution-**SVGs** und **AppIcon** sind Bestandteil dieses Repositories bzw. der Build-Pipeline; Nutzung und Weitergabe richten sich nach **internen Markenrichtlinien** der BIZOLUTION GmbH (nicht durch diese Datei geregelt).
