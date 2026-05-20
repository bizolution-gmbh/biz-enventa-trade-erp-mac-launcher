# enventa Trade ERP Launcher (macOS)

[![License: GPL v3.0](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

**Lizenz:** [GNU General Public License v3.0](LICENSE) (GPL-3.0) — Copyright © 2026 BIZOLUTION GmbH. Zusätzliche Hinweise: [NOTICE](NOTICE).

**enventa Trade ERP Launcher** für macOS ist ein Launcher für das ERP **enventa Trade ERP** des Herstellers **enventa Technical Trade Solutions GmbH**. Bereitgestellt und entwickelt wird er von der **BIZOLUTION GmbH** als **Vertriebs- und Technologiepartner** der **enventa Technical Trade Solutions GmbH**, damit **enventa Trade ERP** auf dem Mac gestartet werden kann. Der Launcher ist **kein** offizielles Produkt des ERP-Herstellers — siehe Hinweis in der App.

Der Launcher startet den **Java-ERP-Client** über Broker-URLs oder gespeicherte Konfigurationen — vergleichbar mit dem Windows-Programm **FS Client Launcher**.

## Dokumentation

| Thema | Datei |
|--------|--------|
| **Lizenz** (eigener Quellcode) | [GNU GPL v3.0](LICENSE), [NOTICE](NOTICE) |
| Entwicklung, Build, JDK, `.fsclient`, Sicherheit | [docs/Entwicklung.md](docs/Entwicklung.md) |
| Drittanbieter & Lizenzen | [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) |
| Änderungshistorie / Release | [CHANGELOG.md](CHANGELOG.md) |

## Lizenz

Der Quellcode dieses Launchers steht unter der **[GNU General Public License v3.0](LICENSE)** (Copyright © 2026 BIZOLUTION GmbH). Die Software wird **freiwillig** bereitgestellt (Download/Installation **ohne Kauf**, **ohne Nutzungspflicht**). Es wird **keine Gewährleistung** und **kein Support** zugesagt, sofern nicht gesondert vereinbart — siehe auch die Haftungs- und Gewährleistungsregelungen in der GPL. Mitgelieferte oder nachgeladene **Drittanbieter** (z. B. Java-Laufzeiten) haben **eigene** Lizenzen: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Voraussetzungen (enventa Trade ERP auf dem Mac)

Damit der ERP-Client auf dem Mac nutzbar ist, gelten **zusätzlich** zu diesem Launcher folgende Vorgaben in **enventa Trade ERP**:

- **Office-Integration:** In den **Berechtigungen** des Benutzers muss die **Office-Integration deaktiviert** sein. Ist sie aktiv, sind Start oder Funktionen des Clients auf dem Mac oft beeinträchtigt.
- **Einschränkungen:** Alles, was im ERP **Browser-Control** (eingebetteter Browser) voraussetzt, steht auf dem Mac **nicht** zur Verfügung. Nutzbar ist, was über den **Java-Client** läuft.

Der Mac-Launcher ersetzt **kein** vollständiges Windows-ERP; er ermöglicht den **gesteuerten Client-Start** unter macOS.

## Installation

1. **DMG** öffnen und **`enventa Trade ERP Launcher.app`** nach **`/Applications`** ziehen (oder in einen anderen Programme-Ordner).
2. **Quarantäne entfernen:** Die ausgelieferte App ist **nicht** code-signiert/notarisiert. Nach dem Kopieren setzt macOS oft das Quarantäne-Attribut — der Start schlägt dann fehl oder macOS blockiert die App. Entfernen Sie die Quarantäne einmalig im Terminal (Pfad anpassen, falls die App woanders liegt):

   ```bash
   sudo xattr -dr com.apple.quarantine "/Applications/enventa Trade ERP Launcher.app"
   ```

3. Beim **ersten Start** ggf. zusätzlich Rechtsklick auf die App → **„Öffnen“** (Gatekeeper), falls sie weiterhin blockiert wird.
4. **Java:** Für viele Umgebungen reicht der **Java-8-Download** des Launchers beim ersten Start (Dialog in der App). Sind JDKs bereits im App-Bundle mitgeliefert, werden diese genutzt.

## Nutzung

### Launcher starten

- App aus **Programme** oder per **Spotlight** mit **„enventa Trade ERP Launcher“** öffnen (siehe [Installation](#installation)).
- Der Launcher erscheint in der **Menüleiste** (rechts oben). Von dort: **Einstellungen**, registrierte Anwendungen, Beenden.

### Anwendung registrieren (ERP-Client)

1. Im **Browser** (z. B. Safari) die **Broker-Startseite** öffnen und die gewünschte **Konfiguration** setzen.
2. Am Button **„Download Jnlp“** (oder vergleichbar) **Rechtsklick → Link-Adresse kopieren** — **nicht** die heruntergeladene `.jnlp`-Datei verwenden (der Launcher liest **keine** lokalen `.jnlp`-Dateien).
3. Im Launcher: **Menüleisten-Menü → „Anwendung hinzufügen …“** oder **Einstellungen → Reiter „Anwendungen“ → „Anwendung hinzufügen“**.
4. Eintragstyp **Client-Anwendung (Broker / .fsclient)** wählen, die kopierte **URL einfügen**, einen **Titel** vergeben, mit **OK** speichern.
5. Den Client über das **Menüleisten-Menü** oder die **Kachel** unter **Anwendungen** starten.

Manche Broker liefern **`…/api/fsclient?…`** statt `jnlp` — dieselbe Vorgehensweise (Definitions-URL einfügen). URLs mit **`…/api/jnlp?…`** werden intern wie **`…/api/fsclient?…`** behandelt.

### Weblink (nur Browser)

Eintragstyp **Weblink (im Browser öffnen)** speichert eine beliebige **http(s)-URL** und öffnet sie beim Start **unverändert** im **Standardbrowser** — ohne ERP-Java-Client.

### Alternative Starts

- **`.fsclient`-Datei** per Doppelklick oder Terminal (wenn die App als Standard-App für `.fsclient` eingetragen ist).
- **URL-Schema** `fsclientlauncher:launch?…` wie unter Windows.

## Kurzüberblick Launcher

- Start des ERP-Java-Clients über Broker, gespeicherte URLs oder `.fsclient`-JSON.
- **Registrierte Anwendungen** in Menüleiste und Einstellungen (Client und Weblink).
- Java **8 / 11 / 21** je nach Broker und verfügbarer Laufzeit; optional **Java 8 mit JavaFX** nachladen.
- Konfiguration und Cache unter `~/Library/Application Support/bizolution/enventa Trade ERP Launcher/` bzw. `~/Library/Caches/bizolution/…`.
