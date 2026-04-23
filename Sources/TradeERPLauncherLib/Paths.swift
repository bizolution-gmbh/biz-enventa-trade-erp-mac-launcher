import CryptoKit
import Foundation

/// macOS-Ablage für Launcher-Daten unter **bizolution** (Hersteller dieser Software).
///
/// **Einmalige Migration:** Beim ersten Start mit diesem Layout wird von älteren Pfaden
/// (`enventa Group/FS Client Launcher`, `~/FSClientLauncher`, …) nach `bizolution/…` migriert.
/// Danach existiert eine Marker-Datei (`.storage-layout-v1.migrated`); solange sie besteht,
/// werden **keine** Alt-Pfade mehr eingelesen oder zusammengeführt — nachträglich angelegte
/// Verzeichnisse unter alten Pfaden werden **ignoriert** (Schutz vor Manipulation / Verwechslung).
enum AppPaths {
    private static let vendorFolder = "bizolution"
    private static let appFolderName = "enventa Trade ERP Launcher"

    /// `~/Library/Application Support/bizolution/enventa Trade ERP Launcher`
    static var appDataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(vendorFolder, isDirectory: true)
            .appendingPathComponent(appFolderName, isDirectory: true)
    }

    /// `~/Library/Caches/bizolution/enventa Trade ERP Launcher`
    static var localAppDataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches", isDirectory: true)
            .appendingPathComponent(vendorFolder, isDirectory: true)
            .appendingPathComponent(appFolderName, isDirectory: true)
    }

    static var launcherConfigURL: URL {
        appDataDirectory.appendingPathComponent("launcherconfig.json", isDirectory: false)
    }

    /// Heruntergeladene **Java-8**-Laufzeit (Azul Zulu + JavaFX), siehe `ZuluJava8FxRuntimeDownloader`.
    /// `JavaRuntimeResolver` prüft dieses Verzeichnis nach dem App-Bundle-`jre8/`.
    static var downloadedJre8Directory: URL {
        appDataDirectory.appendingPathComponent("runtimes/jre8", isDirectory: true)
    }

    /// Gespeicherte Kürzel (Tray/Einstellungen) und Schalter für das Menüleisten-Icon.
    static var registeredApplicationsMenuJSONURL: URL {
        appDataDirectory.appendingPathComponent("registered-applications-menu.json", isDirectory: false)
    }

    /// Importierte `.fsclient`-Dateien (Browser-Download, HTTP-Start, temporäre Pfade).
    static var importedApplicationDefinitionsDirectory: URL {
        appDataDirectory.appendingPathComponent("ImportedLauncherDefinitions", isDirectory: true)
    }

    /// Temporäre / kurzlebige Speicherorte (z. B. Browser-„Öffnen mit“): Inhalt nach erfolgreichem Start nach `importedApplicationDefinitionsDirectory` kopieren.
    static func isEphemeralLauncherDefinitionPath(_ path: String) -> Bool {
        let std = (path as NSString).standardizingPath
        let tmp = (NSTemporaryDirectory() as NSString).standardizingPath
        if std.hasPrefix(tmp) { return true }
        if std.contains("/var/folders/") || std.contains("/private/var/folders/") { return true }
        let lower = std.lowercased()
        if lower.hasPrefix("/tmp/") || lower.hasPrefix("/private/tmp/") { return true }
        return false
    }

    /// Schreibt JSON-Bytes deterministisch benannt (`application-<SHA256>.fsclient`); gleicher Inhalt → gleicher Pfad.
    static func saveImportedDefinitionJson(_ data: Data) throws -> String {
        try FileManager.default.createDirectory(at: importedApplicationDefinitionsDirectory, withIntermediateDirectories: true)
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let dest = importedApplicationDefinitionsDirectory.appendingPathComponent("application-\(hex).fsclient", isDirectory: false)
        if FileManager.default.fileExists(atPath: dest.path) {
            return dest.path
        }
        try data.write(to: dest, options: .atomic)
        return dest.path
    }

    static var jarCacheDirectory: URL {
        localAppDataDirectory.appendingPathComponent(".jarcache", isDirectory: true)
    }

    static var jarDirectory: URL {
        jarCacheDirectory.appendingPathComponent("jar", isDirectory: true)
    }

    static var logFilesDirectory: URL {
        appDataDirectory.appendingPathComponent("Logfiles", isDirectory: true)
    }

    /// PNG mit gleicher Dock-Maske wie der Launcher (für `java -Xdock:icon=…`).
    static var javaDockIconPNG: URL {
        localAppDataDirectory.appendingPathComponent("trade-erp-launcher-java-dock-icon.png", isDirectory: false)
    }

    /// Basisverzeichnis neben dem ausführbaren Launcher (JDK-Bundles `jdk11/`, `jdk21/`, `jre8/`).
    static var launcherRuntimeBaseDirectory: URL {
        let execURL = URL(fileURLWithPath: CommandLine.arguments[0], isDirectory: false)
            .resolvingSymlinksInPath()
        let macOSDir = execURL.deletingLastPathComponent()
        if macOSDir.lastPathComponent == "MacOS" {
            return macOSDir.deletingLastPathComponent()
                .appendingPathComponent("Resources", isDirectory: true)
        }
        return macOSDir
    }

    // MARK: - Migration (einmalig, Version 1)

    /// Marker: Layout-Migration v1 abgeschlossen — solange vorhanden, keine erneute Auswertung alter Pfade.
    private static var storageLayoutMigrationMarkerURL: URL {
        appDataDirectory.appendingPathComponent(".storage-layout-v1.migrated", isDirectory: false)
    }

    /// Bekannte Alt-App-Support-Wurzeln (nur für die einmalige Migration).
    private static func legacyAppSupportMigrationRoots(home: URL) -> [URL] {
        [
            home.appendingPathComponent("FSClientLauncher", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/enventa Group/FS Client Launcher", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/TradeERPLauncher", isDirectory: true),
        ]
    }

    /// Bekannte Alt-Cache-Wurzeln (nur für die einmalige Migration).
    private static func legacyCacheMigrationRoots(home: URL) -> [URL] {
        [
            home.appendingPathComponent("Library/Caches/FSClientLauncher", isDirectory: true),
            home.appendingPathComponent("Library/Caches/enventa Group/FS Client Launcher", isDirectory: true),
            home.appendingPathComponent("Library/Caches/TradeERPLauncher", isDirectory: true),
        ]
    }

    static func migrateLegacyDirectoriesIfNeeded() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        try? fm.createDirectory(at: appDataDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)

        if fm.fileExists(atPath: storageLayoutMigrationMarkerURL.path) {
            return
        }

        try? fm.createDirectory(at: localAppDataDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)

        for legacy in legacyAppSupportMigrationRoots(home: home) where legacy.path != appDataDirectory.path {
            migrateWholeDirectoryIfPossible(from: legacy, to: appDataDirectory, fm: fm)
        }

        try? fm.createDirectory(at: appDataDirectory, withIntermediateDirectories: true)
        migrateAppSupportFilenamesIfNeeded(fm: fm)

        for legacy in legacyCacheMigrationRoots(home: home) where legacy.path != localAppDataDirectory.path {
            migrateWholeDirectoryIfPossible(from: legacy, to: localAppDataDirectory, fm: fm)
        }

        try? fm.createDirectory(at: localAppDataDirectory, withIntermediateDirectories: true)
        migrateLocalCacheFilenamesIfNeeded(fm: fm)

        let oldCacheInAppData = appDataDirectory.appendingPathComponent(".jarcache", isDirectory: true)
        if fm.fileExists(atPath: oldCacheInAppData.path), !fm.fileExists(atPath: jarCacheDirectory.path) {
            try? fm.createDirectory(at: jarCacheDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.moveItem(at: oldCacheInAppData, to: jarCacheDirectory)
        }

        removeEmptyLegacyMigrationRootsIfPresent(fm: fm, home: home)
        writeStorageLayoutMigrationMarker(fm: fm)
    }

    /// Entfernt nur **leere** bekannte Alt-Wurzeln (kein Löschen bei verbleibenden Dateien nach Merge-Konflikten).
    private static func removeEmptyLegacyMigrationRootsIfPresent(fm: FileManager, home: URL) {
        let roots = legacyAppSupportMigrationRoots(home: home) + legacyCacheMigrationRoots(home: home)
        for url in roots where url.path != appDataDirectory.path && url.path != localAppDataDirectory.path {
            removeDirectoryIfEffectivelyEmpty(at: url, fm: fm)
        }
    }

    private static func removeDirectoryIfEffectivelyEmpty(at url: URL, fm: FileManager) {
        guard fm.fileExists(atPath: url.path) else { return }
        guard let names = try? fm.contentsOfDirectory(atPath: url.path) else { return }
        let meaningful = names.filter { $0 != ".DS_Store" }
        guard meaningful.isEmpty else { return }
        try? fm.removeItem(at: url)
    }

    private static func writeStorageLayoutMigrationMarker(fm: FileManager) {
        try? fm.createDirectory(at: appDataDirectory, withIntermediateDirectories: true)
        let marker = storageLayoutMigrationMarkerURL
        let payload = "storage-layout-v1\n".data(using: .utf8) ?? Data()
        try? payload.write(to: marker, options: .atomic)
    }

    /// Verschiebt `from` nach `to`, wenn `from` existiert. Wenn `to` schon existiert: Inhalte zusammenführen (ohne Überschreiben).
    private static func migrateWholeDirectoryIfPossible(from: URL, to: URL, fm: FileManager) {
        guard fm.fileExists(atPath: from.path) else { return }
        if from.path == to.path { return }
        if !fm.fileExists(atPath: to.path) {
            do {
                try fm.moveItem(at: from, to: to)
            } catch {
                try? fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.createDirectory(at: to, withIntermediateDirectories: true)
                try? mergeDirectoryContents(from: from, into: to, fm: fm)
            }
            return
        }
        try? mergeDirectoryContents(from: from, into: to, fm: fm)
    }

    private static func mergeDirectoryContents(from src: URL, into dst: URL, fm: FileManager) throws {
        guard fm.fileExists(atPath: src.path) else { return }
        let children = try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        for child in children {
            let name = child.lastPathComponent
            let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            let target = dst.appendingPathComponent(name, isDirectory: isDir)
            if fm.fileExists(atPath: target.path) { continue }
            try fm.moveItem(at: child, to: target)
        }
        if let remaining = try? fm.contentsOfDirectory(atPath: src.path), remaining.isEmpty {
            try? fm.removeItem(at: src)
        }
    }

    /// Nach Verzeichnis-Migration: alte Datei- und Ordnernamen im App-Support-Ziel umbenennen.
    private static func migrateAppSupportFilenamesIfNeeded(fm: FileManager) {
        guard fm.fileExists(atPath: appDataDirectory.path) else { return }

        let oldMenu = appDataDirectory.appendingPathComponent("menu-fsclients.json", isDirectory: false)
        let newMenu = registeredApplicationsMenuJSONURL
        if fm.fileExists(atPath: oldMenu.path), !fm.fileExists(atPath: newMenu.path) {
            try? fm.moveItem(at: oldMenu, to: newMenu)
        }

        let oldImported = appDataDirectory.appendingPathComponent("ImportedFsClients", isDirectory: true)
        let newImported = importedApplicationDefinitionsDirectory
        if fm.fileExists(atPath: oldImported.path), !fm.fileExists(atPath: newImported.path) {
            try? fm.moveItem(at: oldImported, to: newImported)
        }

        // Ältere Import-Dateinamen → `application-<SHA256>.fsclient` (Inhalt unverändert)
        if fm.fileExists(atPath: newImported.path) {
            if let names = try? fm.contentsOfDirectory(atPath: newImported.path) {
                for name in names where name.hasSuffix(".fsclient") {
                    let oldFile = newImported.appendingPathComponent(name, isDirectory: false)
                    let newName: String?
                    if name.hasPrefix("fsclient-") {
                        newName = "application-\(String(name.dropFirst("fsclient-".count)))"
                    } else if name.hasPrefix("definition-") {
                        newName = "application-\(String(name.dropFirst("definition-".count)))"
                    } else {
                        newName = nil
                    }
                    if let newName, newName != name {
                        let newFile = newImported.appendingPathComponent(newName, isDirectory: false)
                        if !fm.fileExists(atPath: newFile.path) {
                            try? fm.moveItem(at: oldFile, to: newFile)
                        }
                    }
                }
            }
        }
    }

    private static func migrateLocalCacheFilenamesIfNeeded(fm: FileManager) {
        guard fm.fileExists(atPath: localAppDataDirectory.path) else { return }
        let oldIcon = localAppDataDirectory.appendingPathComponent("fscl-java-dock-icon.png", isDirectory: false)
        let newIcon = javaDockIconPNG
        if fm.fileExists(atPath: oldIcon.path), !fm.fileExists(atPath: newIcon.path) {
            try? fm.moveItem(at: oldIcon, to: newIcon)
        }
    }

    /// Passt in einem gespeicherten **lokalen** Nutzerpfad frühere Ablage-Ort- und Import-Dateinamen an (keine http(s)- oder `fsclientlauncher:`-URLs).
    static func rewriteLegacyUserDataPath(_ path: String) -> String {
        let t = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = t.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("fsclientlauncher:") {
            return path
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var o = t
        let replacements: [(String, String)] = [
            ("\(home)/FSClientLauncher/", "\(home)/Library/Application Support/bizolution/enventa Trade ERP Launcher/"),
            ("\(home)/Library/Application Support/enventa Group/FS Client Launcher/", "\(home)/Library/Application Support/bizolution/enventa Trade ERP Launcher/"),
            ("\(home)/Library/Application Support/TradeERPLauncher/", "\(home)/Library/Application Support/bizolution/enventa Trade ERP Launcher/"),
            ("/ImportedFsClients/", "/ImportedLauncherDefinitions/"),
        ]
        for (old, new) in replacements {
            o = o.replacingOccurrences(of: old, with: new)
        }
        // Nur Import-Dateinamen unter unserem Import-Ordner (kein blindes `/fsclient-` in beliebigen Pfaden).
        o = o.replacingOccurrences(of: "ImportedLauncherDefinitions/fsclient-", with: "ImportedLauncherDefinitions/application-")
        o = o.replacingOccurrences(of: "ImportedLauncherDefinitions/definition-", with: "ImportedLauncherDefinitions/application-")
        o = o.replacingOccurrences(of: "ImportedFsClients/fsclient-", with: "ImportedLauncherDefinitions/application-")
        o = o.replacingOccurrences(of: "ImportedFsClients/definition-", with: "ImportedLauncherDefinitions/application-")
        return o
    }
}
