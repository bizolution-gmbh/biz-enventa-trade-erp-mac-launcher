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
- **Volllogo** ist eingebettet; **Mark** (`enventa-mark-cropped.svg`) liegt unter `Sources/FSClientLauncher/Resources/` und wird in die `.app` kopiert. **Finder-Icon:** `AppIcon.icns` wird daraus erzeugt (`Scripts/build_app_icon.sh`: `rsvg-convert`, `swift` aus den Xcode Command Line Tools, weißer Rand, PNG-Normalisierung für `iconutil`).

## JDK / JRE mitliefern

Unter **`FS Client Launcher.app/Contents/Resources/`** erwartet der Launcher:

| Verzeichnis | Inhalt |
|-------------|--------|
| `jdk11/` | z. B. entpacktes **Eclipse Temurin 11** für macOS (`*.jdk/Contents/Home`) |
| `jdk21/` | Temurin 21 analog |
| `jre8/` | optional Java 8 (JRE/JDK mit `bin/java`; für JavaFX auf Apple Silicon: **`./Scripts/download_zulu8_fx_jre.sh`**, siehe `Scripts/JDK_BUNDLE.md`) |

**Automatisch beim Build:** Ordner `jdk11`, `jdk21`, `jre8` unter **`BundledJDKs/`** im Projektroot anlegen (von Git ignoriert); `Scripts/build_app.sh` kopiert sie per `ditto` ins Bundle. Anderer Pfad: Umgebungsvariable **`BUNDLE_JDK_ROOT`**. Lizenzhinweise: **`Scripts/JDK_BUNDLE.md`**.

Alternativ Umgebungsvariablen (wie im Original): **`FSCL_JDK11`**, **`FSCL_JDK21`**, **`FSCL_JRE8`** → jeweils **JAVA_HOME** (Ordner mit `bin/java`).

Hilfsskript (lädt Temurin 11/21 von Adoptium; Lizenz beachten):

```bash
./Scripts/download_jdks.sh aarch64 "/Pfad/zu/FS Client Launcher.app/Contents/Resources"
```

**Java 8 + JavaFX (nur Apple Silicon / aarch64):** `./Scripts/download_zulu8_fx_jre.sh` legt Azul Zulu 8 JDK FX unter `BundledJDKs/jre8/` ab.

## Bauen

```bash
swift build -c release
# oder bei Problemen mit SwiftPM:
swiftc -O Sources/FSClientLauncher/*.swift -o FSClientLauncher \
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

## macOS-spezifische Abweichungen vom Windows-Original

- Kein **`-Djavax.net.ssl.trustStoreType=Windows-ROOT`** (nur Windows); der Mac nutzt die Standard-TrustStore-Logik der mitgelieferten JVM.
- **Klassenpfad-Trenner** `:` statt `;`.
- **„ProxyMode = Windows“** steuert die **JVM**: **System-Proxy** (`-Djava.net.useSystemProxies=true`). Broker- und JAR-Downloads des Launchers nutzen die **macOS-Netzwerk-/Proxy-Kette** unabhängig von dieser Einstellung.
- JAR-Filter **`Os`**: Einträge nur für **Windows** werden ignoriert; leeres `Os` oder macOS-/Darwin-/OSX-Bezeichner werden akzeptiert (Broker sollte passende Artefakte liefern).
- **Java-11- vs. Java-21-VM-Argumente** werden getrennt aus der Konfiguration gelesen (im dekompilierten Windows-Code war fälschlich durchgängig `Java21VmArguments` verdrahtet).

## Analyse-Quelle

Windows-ZIP: `~/Downloads/FS Client Launcher.zip` — relevant waren u. a. `FSClientLauncher.exe`, eingebettetes **JDK 11 (Zulu/Windows)** und die per **ILSpy** (`ilspycmd`) erzeugte C#-Referenzimplementierung.
