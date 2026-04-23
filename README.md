# enventa Trade ERP Launcher (macOS)

**Bizolution Launcher für enventa Trade ERP (macOS)** — entwickelt von der **BIZOLUTION GmbH** (demnächst **bizolution GmbH**) für **enventa Trade ERP** der enventa Group.

Native macOS-Implementierung der Funktionalität des Windows-Programms **FS Client Launcher** (.NET / WPF), angelehnt an die dekompilierte Logik (`LaunchService`, `JavaRuntimeService`, `CacheService`, `ConfigService`, `FS.Hosting.Broker.Model`).

## Funktion

- Start über **`fsclientlauncher:launch?…`** (URL-Schema) oder eine **JSON-Datei** mit denselben Schlüsseln wie unter Windows (`broker`, `language`, …).
- Abruf der Broker-Metadaten von **`{broker}/api/jardownload`**, Fallback **`JarDownload.ashx`** (HTTP 404).
- Paralleler Download der JARs aus **`{broker}/javaclient/`**, SHA-1-Prüfung, optional Entpacken nativer Bibliotheken (ZIP).
- Auswahl der **Java-Version (8 / 11 / 21)** gemäß Broker-Angaben und Einstellung *Recommended / Supported / Experimental* (wie `UseJavaVersion`).
- Start von **`bin/java`** mit korrektem **Klassenpfad** (`:` unter macOS), Arbeitsverzeichnis = JAR-Cache, **PATH**-Präfix für native Bibliotheken (wie unter Windows).
- Konfiguration (macOS) in **`~/Library/Application Support/bizolution/enventa Trade ERP Launcher/launcherconfig.json`** (gleiche **Schlüsselnamen** wie in der Windows-`.NET`-App; unter Windows liegt die Datei weiter unter *enventa Group* / *FS Client Launcher*).
- JAR-Cache unter **`~/Library/Caches/bizolution/enventa Trade ERP Launcher/.jarcache/`** (Trennung Roaming vs. Local analog Windows).
- Logdateien unter **`~/Library/Application Support/bizolution/enventa Trade ERP Launcher/Logfiles/`** (wie `Logfiles` unter Windows).
- **Cache-Bereinigung** wie `CacheService.CleanupCache` inkl. Logdatei-Bereinigung; in der Konfiguration steuerbar und nach dem Java-Lauf parallel ausgeführt.
- **Volllogo** ist eingebettet; **Mark** (`enventa-mark-cropped.svg`) liegt unter `Sources/TradeERPLauncherLib/Resources/` und wird in die `.app` kopiert. **Finder-Icon / DMG-Volumen-Icon:** `AppIcon.icns` wird daraus erzeugt (`Scripts/build_app_icon.sh`: `rsvg-convert`, `Scripts/normalize_iconset_png.swift` mit **transparenten Außenbereichen** und **abgerundeter Maske** ~22,3 % Eckenradius — typische macOS-Icon-Optik, `iconutil`).
- **Java-Dock & Kacheln:** `Sources/TradeERPLauncherLib/Resources/Icon.png` (gebündelt, getrennt vom Launcher-`AppIcon.icns` mit den grünen Balken). Der Launcher maskiert dieses PNG für `-Xdock:icon` und die FS-Client-Kacheln wie ein macOS-App-Symbol.

## JDK / JRE

Unter **`enventa Trade ERP Launcher.app/Contents/Resources/`** kann der Launcher **JDK 11/21** und optional **JRE 8** aus dem Bundle nutzen:

| Verzeichnis | Inhalt |
|-------------|--------|
| `jdk11/` | z. B. entpacktes **Eclipse Temurin 11** für macOS (`*.jdk/Contents/Home`) |
| `jdk21/` | Temurin 21 analog |
| `jre8/` | optional mitgeliefertes Java 8 |

**Java 8 + JavaFX:** Viele übliche Java-8-JDKs (z. B. Eclipse Temurin) liefern **kein** JavaFX; der Launcher lädt deshalb bei Bedarf **Azul Zulu 8 mit JavaFX** (Apple Silicon oder Intel) nach Application Support `…/runtimes/jre8/`. Nach **Ersetzen der `.app`** ist ein früheres **nur-im-Bundle** liegendes `jre8/` nicht mehr verfügbar — siehe **`Scripts/JDK_BUNDLE.md`**. Lizenzen und Optionen (`FSCL_JRE8`, `BUNDLE_JRE8=1`) dort ebenfalls.

**Automatisch beim Build:** Ordner `jdk11` und `jdk21` unter **`BundledJDKs/`** (von Git ignoriert) werden von `Scripts/build_app.sh` ins Bundle kopiert, sofern vorhanden. **`jre8/`** wird **nur** kopiert, wenn du explizit **`BUNDLE_JRE8=1`** setzt und `BundledJDKs/jre8/` existiert (sonst Java 8 per Erststart-Download). Anderer Pfad: **`BUNDLE_JDK_ROOT`**.

Alternativ Umgebungsvariablen (wie im Original): **`FSCL_JDK11`**, **`FSCL_JDK21`**, **`FSCL_JRE8`** → jeweils **JAVA_HOME** (Ordner mit `bin/java`).

In **Einstellungen › JVM-Argumente** erscheinen die **zusätzlichen** Felder für Java 8, 11 bzw. 21 nur, wenn die passende Laufzeit erkannt wird (nach App-Rückkehr in den Vordergrund oder beim Öffnen des Reiters erneut geprüft). Die **gemeinsamen** JVM-Argumente (alle Versionen) bleiben immer sichtbar. Zusammenhang mit den Tabellen im Reiter **Java-Laufzeitumgebungen**: siehe unten *Java-Laufzeiten im Einstellungen-Fenster (Referenz)*.

### Java-Laufzeiten im Einstellungen-Fenster (Referenz)

Der Reiter **Java-Laufzeitumgebungen** enthält zwei **Tabellen** (gruppiertes Formular nach Apple HIG):

1. **Vom Computer übernommene Ordner** — zeigt, welche Werte die Umgebungsvariablen **`FSCL_JRE8`**, **`FSCL_JDK11`** und **`FSCL_JDK21`** im **aktuellen Launcher-Prozess** haben (Auslesen über `ProcessInfo.processInfo.environment`; führende/abschließende Leerzeichen und Zeilenumbrüche im Wert werden entfernt). Jede Variable ist ein **JAVA_HOME** (Ordner mit lauffähigem **`bin/java`**; Symlinks und `access(…, X_OK)` werden wie in `JavaRuntimeResolver` berücksichtigt). Steht dort **„Kein eigener Ordner übernommen“**, enthält dieser Prozess die Variable nicht (typisch: Launcher lief noch und wurde nur erneut aktiviert, Start über **`open -a`** ohne `--env`, oder anderer Start ohne diese Umgebung).

   **Sicherheit:** `FSCL_*` ist eine bewusste Administrator-Option: Der Launcher führt **`bin/java`** unter dem angegebenen Ordner aus, ohne zusätzliche Signatur- oder Herstellerprüfung. Nur vertrauenswürdige Pfade setzen; in den Einstellungen sind die Pfade einsehbar (ggf. interne Verzeichnisse).

2. **Erkannte Installationen** — ob aus den übernommenen Pfaden, aus dem **App-Bundle** (`Contents/Resources/jre8` bzw. `jdk11` / `jdk21`) oder (nur Java 8) aus dem **unter Application Support heruntergeladenen** `runtimes/jre8/`-Layout ein nutzbares Java ermittelt wurde.

**Spaltenbedeutung (UI → technisch):**

| UI (Einstellungen) | Technisch |
|--------------------|-----------|
| Installationsordner | JAVA_HOME |
| Startprogramm | `bin/java` (ggf. aufgelöster Symlink) |
| Versionsinfo | erste Zeile von `java -version` (stderr/stdout) |

**Priorität** wie beim Programmstart: zuerst `FSCL_*`, sonst eingebettete Ordner im Bundle, bei Java 8 zusätzlich der Download-Ordner unter Application Support.

**Beispiel Terminal** (Launcher zuvor in der Menüleiste beenden), JAVA_HOME von Java 8 gesetzt:

```bash
FSCL_JRE8="$HOME/Library/Application Support/bizolution/enventa Trade ERP Launcher/runtimes/jre8/zulu8-fx-macos-aarch64.jdk/Contents/Home" \
"/Applications/enventa Trade ERP Launcher.app/Contents/MacOS/TradeERPLauncher"
```

**Neue App-Instanz mit Variable**, ohne Shell-Umgebung des Elternprozesses:

```bash
open -n --env FSCL_JRE8=/pfad/zum/JAVA_HOME -a "enventa Trade ERP Launcher"
```

Weitere Bundle- und Lizenzoptionen: **`Scripts/JDK_BUNDLE.md`**.

**Standard Java 8** (nur wenn `Java8VmArguments` in `launcherconfig.json` noch leer ist und JRE 8 erkannt wird — siehe `LauncherSettings.recommendedJava8VmArgumentsForMacOS`):

```
-Dapple.laf.useScreenMenuBar=true
-Dapple.awt.application.name=enventa Trade ERP
-Dapple.awt.application.appearance=system
-Dapple.awt.antialiasing=true
-Dapple.awt.textantialiasing=true
```

## Bauen

```bash
swift build -c release
swift test
# Wenn `swift test` mit „no such module XCTest“ scheitert: aktives Developer-Dir auf **Xcode.app** setzen
# (`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`) — reine CLT-Umgebungen liefern XCTest mitunter nicht zuverlässig für SPM-Tests.
# oder bei Problemen mit SwiftPM:
swiftc -O Sources/TradeERPLauncherLib/*.swift -o TradeERPLauncher \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" -target arm64-apple-macosx13.0
```

**.app-Bundle:**

```bash
./Scripts/build_app.sh
```

Optional: JDKs unter `BundledJDKs/` bereitlegen, damit `build_app.sh` sie ins Bundle übernimmt; sonst manuell nach `dist/…/Contents/Resources/` kopieren. App signieren/notarisieren, falls ausgeliefert wird.

## Installation

1. **App bauen** (siehe oben): z. B. `./Scripts/build_app.sh` → Ergebnis: `dist/enventa Trade ERP Launcher.app`.
2. **JDKs** entweder beim Build über `BundledJDKs/` mitliefern lassen oder unter `…/Contents/Resources/` (`jdk11/`, `jdk21/`, optional `jre8/` nur mit **`BUNDLE_JRE8=1`**) legen bzw. `FSCL_JDK11` / `FSCL_JDK21` / `FSCL_JRE8` setzen.
3. Die **`.app`** nach **`/Applications`** ziehen (oder wo du Programme ablegst).
4. Beim **ersten Start** ggf. Rechtsklick → **„Öffnen“** wählen (Gatekeeper), falls die App nicht signiert/notarisiert ist.
5. Optional: **Code-Signing / Notarisierung** für reibungslosen Start ohne Gatekeeper-Hinweis (Apple-Entwicklerkonto).

## Eine `.fsclient`-Datei ausführen

Die Datei muss dasselbe **JSON** enthalten wie unter Windows (Schlüssel wie `broker`, `language`, …) — der Launcher liest sie wie eine normale JSON-Startdatei.

- **Doppelklick**: Wenn die App die Standard-App für `.fsclient` ist (nach Installation ggf. unter *Informationen → „Öffnen mit“* einmal **enventa Trade ERP Launcher** wählen), startet der Client direkt.
- **Über das Terminal** (Pfad anpassen):

  ```bash
  open -a "enventa Trade ERP Launcher" /Pfad/zur/datei.fsclient
  ```

  oder mit dem gebauten Binary:

  ```bash
  "/Pfad/zu/enventa Trade ERP Launcher.app/Contents/MacOS/TradeERPLauncher" /Pfad/zur/datei.fsclient
  ```

- **URL-Schema** (wie unter Windows): Links im Stil `fsclientlauncher:launch?broker=…` öffnen die App mit dem passenden Handler.

Registrierte Anwendungen: optional wird unter dem **Broker-Stamm** (aus `broker` bzw. der Web-Definitions-URL) **`Icon.png`** geladen, als **SHA256-Dateiname** unter `~/Library/Application Support/bizolution/enventa Trade ERP Launcher/RegisteredAppIcons/` gespeichert (gleiche Grafik = eine Datei) und in **Menüleiste** sowie **Einstellungen › Anwendungen** angezeigt. **Bestehende Konfigurationen:** ältere `registered-applications-menu.json` ohne Feld `iconContentHash` bleiben gültig (`nil`); der Launcher versucht die Icons beim nächsten Start automatisch nachzuladen — kein manuelles Editieren der JSON nötig.

## Einstellungen › Anwendungen (technisch)

Die Oberfläche nutzt kurze Alltagstexte; hier die gültigen Kürzel laut Code:

- **Lokaler Pfad** zu einer **`.fsclient`**-JSON-Datei.
- **http(s)-URL** zu einer Server-Definitionsseite (`…/api/fsclient?…` oder `…/api/jnlp?…`; `jnlp`-Pfade werden intern auf `fsclient` umgeschrieben).
- **`fsclientlauncher:launch?…`** sowie die Brücke **`fsclientlauncher:jnlp?url=…`** (kodierte http(s)-Zieladresse).
- Beim Speichern einer passenden http(s)-Definitions-URL kann der Launcher anbieten, sie in **`fsclientlauncher:launch?…`** umzuwandeln (analog zu typischen Server-Weiterleitungen).

## macOS-spezifische Abweichungen vom Windows-Original

- Kein **`-Djavax.net.ssl.trustStoreType=Windows-ROOT`** (nur Windows); der Mac nutzt die Standard-TrustStore-Logik der mitgelieferten JVM.
- **Klassenpfad-Trenner** `:` statt `;`.
- **„ProxyMode = Windows“** steuert die **JVM**: **System-Proxy** (`-Djava.net.useSystemProxies=true`). Broker- und JAR-Downloads des Launchers nutzen die **macOS-Netzwerk-/Proxy-Kette** unabhängig von dieser Einstellung.
- JAR-Filter **`Os`**: Einträge nur für **Windows** werden ignoriert; leeres `Os` oder macOS-/Darwin-/OSX-Bezeichner werden akzeptiert (Broker sollte passende Artefakte liefern).
- **Java-11- vs. Java-21-VM-Argumente** werden getrennt aus der Konfiguration gelesen (im dekompilierten Windows-Code war fälschlich durchgängig `Java21VmArguments` verdrahtet).

## Analyse-Quelle

Windows-ZIP: `~/Downloads/FS Client Launcher.zip` — relevant waren u. a. `FSClientLauncher.exe`, eingebettetes **JDK 11 (Zulu/Windows)** und die per **ILSpy** (`ilspycmd`) erzeugte C#-Referenzimplementierung.

## Cursor / KI-Agenten

Projektübergreifende Arbeits- und Qualitätsstandards für den Cursor-Agenten liegen **zentral** unter **`~/.cursor/rules/entwicklungsstandards.mdc`** (nicht im Repository); dort ist `alwaysApply: true` gesetzt. Ergänzend zentral: **`~/.cursor/rules/macos-apple-icons.mdc`** (Kopie wie im Repo, gleicher Inhalt).

Im **Repository** liegt **`.cursor/rules/macos-apple-icons.mdc`** (Icons & HIG); übriges `.cursor/*` bleibt per `.gitignore` lokal und wird nicht committed.

## Sicherheit (Kurz)

- **Broker-Daten:** JAR-`href` und Splash-Bild werden nur geladen, wenn die aufgelöste URL **`http`/`https`** mit Host ist (kein `file:` usw. aus manipuliertem Broker-JSON). **HTTP-Weiterleitungen** bei Broker-, JAR- und Splash-Downloads folgen nur **http(s)** mit Host; **`fsclientlauncher:`**-Redirects werden nicht per HTTP nachverfolgt (gleiche Policy wie beim `.fsclient`-Definitions-Download).
- **App Transport Security:** In `Scripts/Info.plist` ist **`NSAllowsArbitraryLoads`** gesetzt, damit **http**-Broker und Firmen-Umgebungen funktionieren; das schwächt TLS-Striktheit zugunsten Kompatibilität — bei ausschließlich **https**-Betrieb könnte man das später einschränken (Ausnahmen pro Domain).
- **Keine Geheimnisse im Code:** Broker-URLs und Konfiguration kommen vom Nutzer/Server, nicht aus dem Repository.
