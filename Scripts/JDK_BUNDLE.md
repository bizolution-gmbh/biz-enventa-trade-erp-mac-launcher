# JDK / JRE in „FS Client Launcher.app“ mitliefern

## Ablage im App-Bundle

Der Launcher sucht unter **`FS Client Launcher.app/Contents/Resources/`** (siehe `AppPaths.launcherRuntimeBaseDirectory` und `JavaRuntimeResolver`):

| Ordner | Erwartung |
|--------|-----------|
| **`jdk11/`** | Ein oder mehrere entpackte macOS-JDKs (z. B. Eclipse Temurin). Erkannt wird u. a. `…/Contents/Home/bin/java` oder `…/bin/java` in Unterordnern. |
| **`jdk21/`** | Entsprechend für Java 21. |
| **`jre8/`** | Java 8 (JRE/JDK mit `bin/java`), z. B. entpacktes Temurin 8, **Azul Zulu 8 mit JavaFX** oder Oracle-JRE-Struktur. |

### Java 8 + JavaFX (Apple Silicon, empfohlen für enventa-Client)

Temurin-JRE 8 enthält **kein** JavaFX. Für den FS-Java-Client mit **JavaFX** unter **aarch64** am einfachsten: **Azul Zulu 8 JDK mit gebündeltem JavaFX** automatisch nach `BundledJDKs/jre8/` legen:

```bash
./Scripts/download_zulu8_fx_jre.sh
```

Das Skript fragt die **Azul-Metadaten-API** nach dem aktuellen `ca-fx-jdk8…-macosx_aarch64.tar.gz`, lädt es herunter und kopiert das enthaltene **`*.jdk`**-Bundle nach `BundledJDKs/jre8/zulu8-fx-macos-aarch64.jdk` (von `JavaRuntimeResolver.findJava8()` erkannt). Lizenz-/Third-Party-Hinweise: [Azul-Dokumentation zu Zulu + JavaFX](https://docs.azul.com/core/).

Typisch nach Entpacken eines **Temurin**-Archivs:

- `Contents/Resources/jdk11/jdk-11.x.y+build/Contents/Home/bin/java`
- `Contents/Resources/jdk21/jdk-21.x.y+build/Contents/Home/bin/java`
- `Contents/Resources/jre8/jdk8u…-b…/Contents/Home/bin/java` (Bezeichnung je nach Anbieter)

## Beim Build automatisch einbinden

Lege die **gleiche Ordnerstruktur** unter **`BundledJDKs/`** im Projektroot ab (nicht versionieren, siehe `.gitignore`):

```text
FSClientLauncherMac/BundledJDKs/jdk11/…
FSClientLauncherMac/BundledJDKs/jdk21/…
FSClientLauncherMac/BundledJDKs/jre8/…
```

`Scripts/build_app.sh` kopiert sie mit **`ditto`** nach **`dist/FS Client Launcher.app/Contents/Resources/`**, sofern die Verzeichnisse existieren.

Alternativer Quellpfad:

```bash
export BUNDLE_JDK_ROOT="/Pfad/zu/meinen/JDKs"
./Scripts/build_app.sh
```

## Lizenz / Weitergabe (Kurzüberblick, keine Rechtsberatung)

- **Eclipse Temurin** (Adoptium): OpenJDK unter **GPL v2 mit Classpath Exception**. Weitergabe eines **unveränderten** Binärpakets ist üblich; die mitgelieferten **Lizenz- und Drittanbieter-Dateien** im JDK-Verzeichnis (z. B. `LEGAL`, `NOTICE`, `license` unter `Contents/Home/legal/`) müssen **mit ausgeliefert** werden — bitte **nicht** löschen oder beschneiden.
- **Oracle JDK/JRE 8**: eigene Lizenzbedingungen; nur nutzen, wenn eure Organisation über die passende **Lizenz/Nutzungsvereinbarung** verfügt.
- **Azul Zulu 8 (JDK FX)**: eigene Kombination aus OpenJDK- und JavaFX-/Drittanbieterlizenzen; siehe Azul-Dokumentation und die Ordner **`legal/`** im Bundle.
- In eurer **Softwarestückliste** / **Third-Party-Notices** solltet ihr die mitgelieferte JVM (Hersteller, Version, Lizenzlink) dokumentieren, wie es eure Compliance vorsieht.
- **Code-Signing / Notarisierung** der `.app` betrifft die App selbst; die JVM bleibt eigenständige Software mit eigenen Lizenzen.

Details und Updates: [Adoptium](https://adoptium.net/) bzw. Herstellerdokumentation der gewählten Distribution.
