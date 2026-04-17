# FS Client Launcher (macOS)

Native macOS-Implementierung der Funktionalität des Windows-Programms **FS Client Launcher** (.NET / WPF), angelehnt an die dekompilierte Logik (`LaunchService`, `JavaRuntimeService`, `CacheService`, `ConfigService`, `FS.Hosting.Broker.Model`).

## Funktion

- Start über **`fsclientlauncher:launch?…`** (URL-Schema) oder eine **JSON-Datei** mit denselben Schlüsseln wie unter Windows (`broker`, `language`, …).
- Abruf der Broker-Metadaten von **`{broker}/api/jardownload`**, Fallback **`JarDownload.ashx`** (HTTP 404).
- Paralleler Download der JARs aus **`{broker}/javaclient/`**, SHA-1-Prüfung, optional Entpacken nativer Bibliotheken (ZIP).
- Auswahl der **Java-Version (8 / 11 / 21)** gemäß Broker-Angaben und Einstellung *Recommended / Supported / Experimental* (wie `UseJavaVersion`).
- Start von **`bin/java`** mit korrektem **Klassenpfad** (`:` unter macOS), Arbeitsverzeichnis = JAR-Cache, **PATH**-Präfix für native Bibliotheken (wie unter Windows).
- Konfiguration in **`~/Library/Application Support/enventa Group/FS Client Launcher/launcherconfig.json`** (gleiche Schlüsselnamen wie in der .NET-App).
- JAR-Cache unter **`~/Library/Caches/enventa Group/FS Client Launcher/.jarcache/`** (Trennung Roaming vs. Local wie unter Windows).
- Logdateien unter **`~/Library/Application Support/enventa Group/FS Client Launcher/Logfiles/`** (wie `Logfiles` unter Windows).
- **Cache-Bereinigung** wie `CacheService.CleanupCache` inkl. Logdatei-Bereinigung; in der Konfiguration steuerbar und nach dem Java-Lauf parallel ausgeführt.
- **Volllogo** ist eingebettet; **Mark** (`enventa-mark-cropped.svg`) liegt unter `Sources/FSClientLauncherLib/Resources/` und wird in die `.app` kopiert. **Finder-Icon / DMG-Volumen-Icon:** `AppIcon.icns` wird daraus erzeugt (`Scripts/build_app_icon.sh`: `rsvg-convert`, `Scripts/normalize_iconset_png.swift` mit **transparenten Außenbereichen** und **abgerundeter Maske** ~22,3 % Eckenradius — typische macOS-Icon-Optik, `iconutil`).
- **Java-Dock & Kacheln:** `Sources/FSClientLauncherLib/Resources/Icon.png` (gebündelt, getrennt vom Launcher-`AppIcon.icns` mit den grünen Balken). Der Launcher maskiert dieses PNG für `-Xdock:icon` und die FS-Client-Kacheln wie ein macOS-App-Symbol.

## JDK / JRE mitliefern

Unter **`FS Client Launcher.app/Contents/Resources/`** erwartet der Launcher:

| Verzeichnis | Inhalt |
|-------------|--------|
| `jdk11/` | z. B. entpacktes **Eclipse Temurin 11** für macOS (`*.jdk/Contents/Home`) |
| `jdk21/` | Temurin 21 analog |
| `jre8/` | optional Java 8 (JRE/JDK mit `bin/java`; für JavaFX auf Apple Silicon: **`./Scripts/download_zulu8_fx_jre.sh`**, siehe `Scripts/JDK_BUNDLE.md`) |

**Automatisch beim Build:** Ordner `jdk11`, `jdk21`, `jre8` unter **`BundledJDKs/`** im Projektroot anlegen (von Git ignoriert); `Scripts/build_app.sh` kopiert sie per `ditto` ins Bundle. Anderer Pfad: Umgebungsvariable **`BUNDLE_JDK_ROOT`**. Lizenzhinweise: **`Scripts/JDK_BUNDLE.md`**.

Alternativ Umgebungsvariablen (wie im Original): **`FSCL_JDK11`**, **`FSCL_JDK21`**, **`FSCL_JRE8`** → jeweils **JAVA_HOME** (Ordner mit `bin/java`).

In **Einstellungen › JVM-Argumente** erscheinen die **zusätzlichen** Felder für Java 8, 11 bzw. 21 nur, wenn die passende Laufzeit im App-Bundle oder per `FSCL_*` erkannt wird (nach App-Rückkehr in den Vordergrund oder beim Öffnen des Reiters erneut geprüft). Die **gemeinsamen** JVM-Argumente (alle Versionen) bleiben immer sichtbar.

**Standard Java 8** (nur wenn `Java8VmArguments` in `launcherconfig.json` noch leer ist und JRE 8 erkannt wird — siehe `LauncherSettings.recommendedJava8VmArgumentsForMacOS`):

```
-Dapple.laf.useScreenMenuBar=true
-Dapple.awt.application.name=enventa Trade ERP
-Dapple.awt.application.appearance=system
-Dapple.awt.antialiasing=true
-Dapple.awt.textantialiasing=true
```

Hilfsskript (lädt Temurin 11/21 von Adoptium; Lizenz beachten):

```bash
./Scripts/download_jdks.sh aarch64 "/Pfad/zu/FS Client Launcher.app/Contents/Resources"
```

**Java 8 + JavaFX (nur Apple Silicon / aarch64):** `./Scripts/download_zulu8_fx_jre.sh` legt Azul Zulu 8 JDK FX unter `BundledJDKs/jre8/` ab.

## Bauen

```bash
swift build -c release
swift test
# Wenn `swift test` mit „no such module XCTest“ scheitert: aktives Developer-Dir auf **Xcode.app** setzen
# (`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`) — reine CLT-Umgebungen liefern XCTest mitunter nicht zuverlässig für SPM-Tests.
# oder bei Problemen mit SwiftPM:
swiftc -O Sources/FSClientLauncherLib/*.swift -o FSClientLauncher \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" -target arm64-apple-macosx13.0
```

**.app-Bundle:**

```bash
./Scripts/build_app.sh
```

Optional: JDKs unter `BundledJDKs/` bereitlegen, damit `build_app.sh` sie ins Bundle übernimmt; sonst manuell nach `dist/…/Contents/Resources/` kopieren. App signieren/notarisieren, falls ausgeliefert wird.

## Installation

1. **App bauen** (siehe oben): z. B. `./Scripts/build_app.sh` → Ergebnis: `dist/FS Client Launcher.app`.
2. **JDKs** entweder beim Build über `BundledJDKs/` mitliefern lassen oder unter `…/Contents/Resources/` (`jdk11/`, `jdk21/`, optional `jre8/`) legen bzw. `FSCL_JDK11` / `FSCL_JDK21` / `FSCL_JRE8` setzen.
3. Die **`.app`** nach **`/Applications`** ziehen (oder wo du Programme ablegst).
4. Beim **ersten Start** ggf. Rechtsklick → **„Öffnen“** wählen (Gatekeeper), falls die App nicht signiert/notarisiert ist.
5. Optional: **Code-Signing / Notarisierung** für reibungslosen Start ohne Gatekeeper-Hinweis (Apple-Entwicklerkonto).

## Eine `.fsclient`-Datei ausführen

Die Datei muss dasselbe **JSON** enthalten wie unter Windows (Schlüssel wie `broker`, `language`, …) — der Launcher liest sie wie eine normale JSON-Startdatei.

- **Doppelklick**: Wenn die App die Standard-App für `.fsclient` ist (nach Installation ggf. unter *Informationen → „Öffnen mit“* einmal **FS Client Launcher** wählen), startet der Client direkt.
- **Über das Terminal** (Pfad anpassen):

  ```bash
  open -a "FS Client Launcher" /Pfad/zur/datei.fsclient
  ```

  oder mit dem gebauten Binary:

  ```bash
  "/Pfad/zu/FS Client Launcher.app/Contents/MacOS/FSClientLauncher" /Pfad/zur/datei.fsclient
  ```

- **URL-Schema** (wie unter Windows): Links im Stil `fsclientlauncher:launch?broker=…` öffnen die App mit dem passenden Handler.

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
