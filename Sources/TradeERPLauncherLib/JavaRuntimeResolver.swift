import Darwin
import Foundation

/// Entspricht `JavaRuntimeService` / `JavaRuntime` der Windows-App (mit korrigierter VM-Args-Zuordnung für Java 11 vs. 21).
enum JavaRuntimeResolver {
    struct Resolved: Sendable {
        let javaExecutable: URL
        let vmArguments: [String]
    }

    static func pickJavaVersion(javaVersions: [ApiJavaVersion]?, settings: LauncherSettings) throws -> Int {
        let supported = [8, 11, 21]
        if javaVersions == nil || javaVersions!.isEmpty {
            return 8
        }
        let list = javaVersions!
        let filtered: [ApiJavaVersion]
        switch settings.UseJavaVersion {
        case .Recommended:
            filtered = list.filter { $0.ReleaseState == .Recommended }
        case .Supported:
            filtered = list.filter { $0.ReleaseState == .Recommended || $0.ReleaseState == .Supported }
        case .Experimental:
            filtered = list
        }
        guard let best = filtered
            .filter({ supported.contains($0.Version) })
            .sorted(by: { $0.Version > $1.Version })
            .first else {
            throw LaunchError.noJavaVersion
        }
        return best.Version
    }

    static func resolveRuntime(version: Int, settings: LauncherSettings) throws -> Resolved {
        switch version {
        case 8:
            let java = try findJava8()
            return Resolved(javaExecutable: java, vmArguments: settings.Java8VmArguments)
        case 11:
            let java = try findJDK(version: 11)
            return Resolved(javaExecutable: java, vmArguments: settings.Java11VmArguments)
        case 21:
            let java = try findJDK(version: 21)
            return Resolved(javaExecutable: java, vmArguments: settings.Java21VmArguments)
        default:
            throw LaunchError.noJavaVersion
        }
    }

    // MARK: - Verfügbarkeit (Einstellungen-UI, ohne Start)

    static func isJava8RuntimePresent() -> Bool {
        locateJava8ExecutableIfPresent() != nil
    }

    static func isJava11RuntimePresent() -> Bool {
        locateJDKExecutableIfPresent(version: 11) != nil
    }

    static func isJava21RuntimePresent() -> Bool {
        locateJDKExecutableIfPresent(version: 21) != nil
    }

    private static func rawEnvironmentValue(forKey key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }

    /// Ohne führende/abschließende Leerzeichen und Zeilenumbrüche (häufig bei mehrzeiligem Shell-`export`).
    private static func trimmedEnvironmentValue(forKey key: String) -> String? {
        guard let raw = rawEnvironmentValue(forKey: key) else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// `bin/java` ist oft ein Symlink; `isExecutableFile` reicht auf manchen Layouts nicht — `access(X_OK)` nachziehen.
    private static func isRunnableJavaBinary(at javaURL: URL) -> Bool {
        let fm = FileManager.default
        let resolved = javaURL.resolvingSymlinksInPath()
        let urls = javaURL.path == resolved.path ? [javaURL] : [javaURL, resolved]
        for u in urls {
            let path = u.path
            if fm.isExecutableFile(atPath: path) { return true }
            if fm.fileExists(atPath: path), path.withCString({ Darwin.access($0, X_OK) == 0 }) {
                return true
            }
        }
        return false
    }

    private static func pickJavaInJavaHome(_ home: URL) -> URL? {
        let direct = home.appendingPathComponent("bin/java")
        guard isRunnableJavaBinary(at: direct) else { return nil }
        return direct.resolvingSymlinksInPath()
    }

    private static func locateJava8ExecutableIfPresent() -> URL? {
        if let override = trimmedEnvironmentValue(forKey: "FSCL_JRE8") {
            let root = URL(fileURLWithPath: override, isDirectory: true)
            return pickJavaInJavaHome(root)
        }
        let bundleRoot = AppPaths.launcherRuntimeBaseDirectory.appendingPathComponent("jre8", isDirectory: true)
        if let j = findJava8UnderBundledStyleJre8Root(bundleRoot) { return j }
        let downloadedRoot = AppPaths.downloadedJre8Directory
        return findJava8UnderBundledStyleJre8Root(downloadedRoot)
    }

    /// Sucht unter einem `jre8/`-Wurzelordner: Update-Verzeichnisse, `*.jdk`-Bundles (macOS) und flache Layouts.
    private static func findJava8UnderBundledStyleJre8Root(_ root: URL) -> URL? {
        let fm = FileManager.default
        guard let subs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return findJavaRecursively(under: root)
        }
        for sub in subs where sub.lastPathComponent.lowercased().hasPrefix("update") || sub.lastPathComponent.contains(".") {
            let java = sub.appendingPathComponent("bin/java")
            if isRunnableJavaBinary(at: java) { return java.resolvingSymlinksInPath() }
        }
        return findJavaRecursively(under: root)
    }

    private static func locateJDKExecutableIfPresent(version: Int) -> URL? {
        let envKey = "FSCL_JDK\(version)"
        if let override = trimmedEnvironmentValue(forKey: envKey) {
            let home = URL(fileURLWithPath: override, isDirectory: true)
            return pickJavaInJavaHome(home)
        }
        let root = AppPaths.launcherRuntimeBaseDirectory.appendingPathComponent("jdk\(version)", isDirectory: true)
        return findJavaRecursively(under: root)
    }

    static func readJvmArchitecture(javaExecutable: URL) -> String? {
        let p = Process()
        p.executableURL = javaExecutable
        p.arguments = ["-XshowSettings:properties", "-version"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
        } catch {
            return nil
        }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("os.arch = ") {
                return String(t.dropFirst("os.arch = ".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    static func normalizedBrokerArchitecture(fromJvmOsArch: String?) -> String? {
        guard let r = fromJvmOsArch?.lowercased(), !r.isEmpty else { return nil }
        switch r {
        case "x86_64", "amd64": return "amd64"
        case "x86", "i386": return "x86"
        case "aarch64", "arm64": return "aarch64"
        default: return r
        }
    }

    private static func findJDK(version: Int) throws -> URL {
        let envKey = "FSCL_JDK\(version)"
        let root = AppPaths.launcherRuntimeBaseDirectory.appendingPathComponent("jdk\(version)", isDirectory: true)
        guard let java = locateJDKExecutableIfPresent(version: version) else {
            if trimmedEnvironmentValue(forKey: envKey) != nil {
                throw LaunchError.javaHomeMissing(
                    "Umgebungsvariable \(envKey) zeigt auf kein gültiges JDK (erwartet bin/java)."
                )
            }
            throw LaunchError.javaHomeMissing(
                "Kein eingebettetes JDK \(version) unter \(root.path) gefunden. Legen Sie z. B. ein Temurin-JDK dort ab oder setzen Sie \(envKey)."
            )
        }
        return java
    }

    private static func findJava8() throws -> URL {
        let bundleJre8 = AppPaths.launcherRuntimeBaseDirectory.appendingPathComponent("jre8", isDirectory: true)
        let downloadedJre8 = AppPaths.downloadedJre8Directory
        guard let java = locateJava8ExecutableIfPresent() else {
            if trimmedEnvironmentValue(forKey: "FSCL_JRE8") != nil {
                throw LaunchError.javaHomeMissing(
                    "FSCL_JRE8 ist kein gültiges JAVA_HOME: unter dem Pfad fehlt eine ausführbare Datei `bin/java`."
                )
            }
            throw LaunchError.javaHomeMissing(
                """
                Kein Java 8 gefunden.

                Möglichkeiten: Umgebungsvariable FSCL_JRE8 setzen (JAVA_HOME mit `bin/java`), Ordner jre8/ ins App-Bundle legen (\(bundleJre8.path)), die Laufzeit unter „Java-Laufzeitumgebungen“ herunterladen, oder den Ordner nach einem erfolgreichen Download prüfen (\(downloadedJre8.path)).
                """
            )
        }
        return java
    }

    /// Sucht nur unter **direkten Unterordnern** von `root`: typisches macOS-`.jdk`-Layout (`…/Contents/Home/bin/java`) oder flaches Layout (`…/bin/java`).
    ///
    /// Bewusst **nicht** tief rekursiv: vom Launcher heruntergeladene Zulu-Pakete liegen als ein `*.jdk`-Bundle direkt unter `runtimes/jre8/`; eine breite Verzeichnis-Traversion unter `jre8/` bringt kaum Nutzen, kann aber irreführende Treffer begünstigen.
    private static func findJavaRecursively(under root: URL) -> URL? {
        let fm = FileManager.default
        guard let subs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return nil }
        for sub in subs {
            let macHome = sub.appendingPathComponent("Contents/Home")
            let candidates = [macHome, sub]
            for home in candidates {
                let java = home.appendingPathComponent("bin/java")
                if isRunnableJavaBinary(at: java) { return java.resolvingSymlinksInPath() }
            }
        }
        return nil
    }

    // MARK: - Einstellungen-UI: erkannte Laufzeiten (gleiche Priorität wie zur Laufzeit)

    /// Herkunft der gewählten `java`-Instanz (nur bei `.resolved` relevant).
    enum JavaRuntimeConfiguredOrigin: Equatable, Sendable {
        case environmentVariable
        case appBundleJre8
        case applicationSupportJre8
        case appBundleJdk(major: Int)
    }

    enum JavaRuntimeConfiguredPick: Equatable, Sendable {
        /// Wie beim Start verwendet: `java` + Herkunft.
        case resolved(javaExecutable: URL, origin: JavaRuntimeConfiguredOrigin)
        /// Variable ist gesetzt, aber `…/bin/java` fehlt oder ist nicht ausführbar.
        case environmentInvalid(variable: String, configuredPath: String)
        case notFound
    }

    struct JavaRuntimeConfiguredRow: Identifiable, Equatable, Sendable {
        var id: Int { majorVersion }
        let majorVersion: Int
        let pick: JavaRuntimeConfiguredPick

        /// Typische JAVA_HOME-Wurzel (`…/bin/java` → ein bzw. zwei Ebenen über `bin`).
        var javaHomePath: String? {
            guard case .resolved(let java, _) = pick else { return nil }
            return Self.javaHomeDirectory(for: java).path
        }

        var javaExecutablePath: String? {
            guard case .resolved(let java, _) = pick else { return nil }
            return java.path
        }

        var originDescriptionGerman: String {
            switch pick {
            case .resolved(_, let origin):
                switch origin {
                case .environmentVariable:
                    return "Eigener Ordner (vom Mac übernommen)"
                case .appBundleJre8:
                    return "In der App enthalten"
                case .applicationSupportJre8:
                    return "Heruntergeladen (Launcher-Daten)"
                case .appBundleJdk:
                    return "In der App enthalten"
                }
            case .environmentInvalid:
                return "Eigener Ordner (vom Mac übernommen)"
            case .notFound:
                return "—"
            }
        }

        var statusDescriptionGerman: String {
            switch pick {
            case .resolved:
                return "Bereit"
            case .environmentInvalid:
                return "Pfad prüfen"
            case .notFound:
                return "Nicht verfügbar"
            }
        }

        /// Nur bei `.environmentInvalid`: gesetzter, aber unbrauchbarer Pfad aus der Variable.
        var invalidConfiguredPath: String? {
            if case .environmentInvalid(_, let p) = pick { return p }
            return nil
        }

        static func javaHomeDirectory(for javaExecutable: URL) -> URL {
            let binDir = javaExecutable.deletingLastPathComponent()
            return binDir.deletingLastPathComponent()
        }
    }

    /// Eine Zeile pro unterstützter Hauptversion — Reihenfolge und Logik wie `locateJava8ExecutableIfPresent` / `locateJDKExecutableIfPresent`.
    static func javaRuntimeConfiguredRows() -> [JavaRuntimeConfiguredRow] {
        [probeJava8Row(), probeJdkRow(11), probeJdkRow(21)]
    }

    /// Zeile für die Übersicht „vom Mac übernommene Java-Ordner“ (technische Namen nur in der README).
    struct FsclEnvironmentProcessMirrorLine: Identifiable, Equatable, Sendable {
        var id: String { variableName }
        /// Interner Name (README), nicht in der Nutzeroberfläche als Überschrift.
        let variableName: String
        /// Kurzbezeichnung in der Tabelle, z. B. „Java 8“.
        let rowTitle: String
        let valueDescription: String
    }

    static func fsclEnvironmentProcessMirrorLines() -> [FsclEnvironmentProcessMirrorLine] {
        let items: [(key: String, title: String)] = [
            ("FSCL_JRE8", "Java 8"),
            ("FSCL_JDK11", "Java 11"),
            ("FSCL_JDK21", "Java 21"),
        ]
        return items.map { key, title in
            let desc: String
            if rawEnvironmentValue(forKey: key) == nil {
                desc = "Kein eigener Ordner übernommen"
            } else if let t = trimmedEnvironmentValue(forKey: key) {
                desc = t
            } else {
                desc = "Leer (nur Leerzeichen)"
            }
            return FsclEnvironmentProcessMirrorLine(variableName: key, rowTitle: title, valueDescription: desc)
        }
    }

    private static func probeJava8Row() -> JavaRuntimeConfiguredRow {
        let envName = "FSCL_JRE8"
        if let path = trimmedEnvironmentValue(forKey: envName) {
            let root = URL(fileURLWithPath: path, isDirectory: true)
            if let java = pickJavaInJavaHome(root) {
                return JavaRuntimeConfiguredRow(majorVersion: 8, pick: .resolved(javaExecutable: java, origin: .environmentVariable))
            }
            return JavaRuntimeConfiguredRow(majorVersion: 8, pick: .environmentInvalid(variable: envName, configuredPath: path))
        }
        let bundleRoot = AppPaths.launcherRuntimeBaseDirectory.appendingPathComponent("jre8", isDirectory: true)
        if let java = findJava8UnderBundledStyleJre8Root(bundleRoot) {
            return JavaRuntimeConfiguredRow(majorVersion: 8, pick: .resolved(javaExecutable: java, origin: .appBundleJre8))
        }
        let downloadedRoot = AppPaths.downloadedJre8Directory
        if let java = findJava8UnderBundledStyleJre8Root(downloadedRoot) {
            return JavaRuntimeConfiguredRow(majorVersion: 8, pick: .resolved(javaExecutable: java, origin: .applicationSupportJre8))
        }
        return JavaRuntimeConfiguredRow(majorVersion: 8, pick: .notFound)
    }

    private static func probeJdkRow(_ major: Int) -> JavaRuntimeConfiguredRow {
        let envName = "FSCL_JDK\(major)"
        if let path = trimmedEnvironmentValue(forKey: envName) {
            let home = URL(fileURLWithPath: path, isDirectory: true)
            if let java = pickJavaInJavaHome(home) {
                return JavaRuntimeConfiguredRow(majorVersion: major, pick: .resolved(javaExecutable: java, origin: .environmentVariable))
            }
            return JavaRuntimeConfiguredRow(majorVersion: major, pick: .environmentInvalid(variable: envName, configuredPath: path))
        }
        let root = AppPaths.launcherRuntimeBaseDirectory.appendingPathComponent("jdk\(major)", isDirectory: true)
        if let java = findJavaRecursively(under: root) {
            return JavaRuntimeConfiguredRow(majorVersion: major, pick: .resolved(javaExecutable: java, origin: .appBundleJdk(major: major)))
        }
        return JavaRuntimeConfiguredRow(majorVersion: major, pick: .notFound)
    }
}
