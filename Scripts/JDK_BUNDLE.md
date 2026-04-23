# JDK / JRE in „enventa Trade ERP Launcher.app“ mitliefern

## Java 8 + JavaFX (Azul Zulu) — automatischer Download

**Hintergrund:** Gängige **Java-8-JDKs ohne gebündeltes JavaFX** (z. B. **Eclipse Temurin 8**) reichen für den **JavaFX**-Client nicht aus. Für **Java 8 + JavaFX** unterstützt dieser Launcher deshalb den automatischen Download von **Azul Zulu 8 JDK mit JavaFX** (nicht Temurin) — per **Azul-Metadaten-API**, getrennt für **Apple Silicon** und **Intel**. Die Laufzeit liegt unter Application Support:

`~/Library/Application Support/bizolution/enventa Trade ERP Launcher/runtimes/jre8/`

Es erscheint ein **Hinweisdialog** (Internetverbindung, Speicherort, Lizenzhinweis auf [Azul-Dokumentation](https://docs.azul.com/core/tpls/)); nur nach Zustimmung wird geladen. Technische Umsetzung: `Jre8FirstLaunchOffer`, `ZuluJava8FxRuntimeDownloader`, `JavaRuntimeResolver`.

**Hinweis zum App-Ersetzen (Finder „Ersetzen?“):** Liegt Java 8 **nur** in der **alten** `.app` unter `Contents/Resources/jre8/`, ist diese nach dem Ersetzen **weg**. Die neue App kann die alte Bundle-Laufzeit **nicht** nachträglich auslesen — es bleiben **Erststart-Download**, **`FSCL_JRE8`**, oder ein Build mit **`BUNDLE_JRE8=1`** (siehe unten).

## Ablage im App-Bundle

Der Launcher sucht Java-Laufzeitumgebungen in dieser Reihenfolge:

1. Umgebungsvariablen **`FSCL_JRE8`**, **`FSCL_JDK11`**, **`FSCL_JDK21`** (JAVA_HOME mit `bin/java`)
2. **`…/Contents/Resources/jre8/`** bzw. **`jdk11/`**, **`jdk21/`** im App-Bundle (`AppPaths.launcherRuntimeBaseDirectory`)
3. Für **Java 8** zusätzlich: **`runtimes/jre8/`** unter Application Support (siehe oben)

| Ordner | Erwartung |
|--------|-----------|
| **`jdk11/`** | Ein oder mehrere entpackte macOS-JDKs (z. B. Eclipse Temurin). Erkannt wird u. a. `…/Contents/Home/bin/java` oder `…/bin/java` in Unterordnern. |
| **`jdk21/`** | Entsprechend für Java 21. |
| **`jre8/`** | Optional: manuell mitgeliefertes Java 8; sonst Erststart-Download nach `runtimes/jre8/` (Zulu + JavaFX). |

Typisch nach manuellem Entpacken von **Temurin** ins Bundle:

- `Contents/Resources/jdk11/jdk-11.x.y+build/Contents/Home/bin/java`
- `Contents/Resources/jdk21/jdk-21.x.y+build/Contents/Home/bin/java`

## Beim Build automatisch einbinden

Lege die **gleiche Ordnerstruktur** unter **`BundledJDKs/`** im Projektroot ab (nicht versionieren, siehe `.gitignore`):

```text
BundledJDKs/jdk11/…
BundledJDKs/jdk21/…
BundledJDKs/jre8/…   (optional; nur wenn du Java 8 ins Bundle packen willst — siehe BUNDLE_JRE8)
```

`Scripts/build_app.sh` kopiert **`jdk11/`** und **`jdk21/`** mit **`ditto`** ins App-Bundle, sofern die Verzeichnisse unter `BUNDLE_JDK_ROOT` existieren. **`jre8/`** wird **nur** kopiert, wenn die Umgebungsvariable **`BUNDLE_JRE8`** gesetzt ist (siehe unten).

### Umgebungsvariable `BUNDLE_JRE8` (opt-in)

**Standard:** Es wird **kein** `jre8/` ins `.app` übernommen — auch nicht, wenn `BundledJDKs/jre8/` existiert. Java 8 stellt der Launcher per **Erststart-Download** (Azul Zulu + JavaFX) unter Application Support bereit (`runtimes/jre8/`), sofern weder `FSCL_JRE8` noch ein manuelles Bundle-`jre8` greift.

**Java 8 ins Bundle legen** (z. B. offlinefähige Auslieferung): `BundledJDKs/jre8/` befüllen und bauen mit:

```bash
BUNDLE_JRE8=1 ./Scripts/build_app.sh
```

Jeder **nicht-leere** Wert von `BUNDLE_JRE8` schaltet die Kopie ein (üblich: `BUNDLE_JRE8=1`). Ist `BUNDLE_JRE8` gesetzt, **`jre8/` aber nicht vorhanden**, warnt das Skript und kopiert nichts.

Alternativer Quellpfad (gleiche Regeln: **`jdk11`/`jdk21`** automatisch, **`jre8`** nur mit **`BUNDLE_JRE8=1`**):

```bash
export BUNDLE_JDK_ROOT="/Pfad/zu/meinen/JDKs"
BUNDLE_JRE8=1 ./Scripts/build_app.sh
```

## Lizenz / Weitergabe (Kurzüberblick, keine Rechtsberatung)

- **Eclipse Temurin** (Adoptium): OpenJDK unter **GPL v2 mit Classpath Exception**. Weitergabe eines **unveränderten** Binärpakets ist üblich; die mitgelieferten **Lizenz- und Drittanbieter-Dateien** im JDK-Verzeichnis müssen **mit ausgeliefert** werden.
- **Oracle JDK/JRE 8**: eigene Lizenzbedingungen; nur nutzen, wenn eure Organisation über die passende **Lizenz/Nutzungsvereinbarung** verfügt.
- **Azul Zulu 8 (JDK FX)**: eigene Kombination aus OpenJDK- und JavaFX-/Drittanbieterlizenzen; siehe Azul-Dokumentation und die Ordner **`legal/`** im Bundle.
- In eurer **Softwarestückliste** / **Third-Party-Notices** solltet ihr die mitgelieferte bzw. heruntergeladene JVM dokumentieren.

Details: [Adoptium](https://adoptium.net/) bzw. [Azul](https://www.azul.com/).
