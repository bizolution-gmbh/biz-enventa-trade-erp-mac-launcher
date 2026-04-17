import Darwin
import Foundation

extension Notification.Name {
    static let fsclShortcutsChanged = Notification.Name("de.frameworksystems.fscl.shortcutsChanged")
}

/// Ein gespeicherter Eintrag für die Menüleiste / Einstellungen.
struct FsClientShortcutRecord: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    /// Anzeige & logische Quelle: **http(s)-URL** oder lokaler Pfad zur `.fsclient`-Datei (wie vom Nutzer erwartet).
    var path: String
    /// Optional: unter `ImportedFsClients` gespeicherte Kopie — beim **Start** nur für **nicht-http(s)**-Kürzel genutzt; bei http(s) zählt immer `path` (erneuter Download).
    var importedFilePath: String?
    var displayName: String

    /// Argument für `LaunchConfiguration.load`: Bei **http(s)-Kürzeln** immer die gespeicherte URL (erneuter Download) — eine alte `importedFilePath`-Kopie darf den Start nicht kapern. Sonst: Import-Datei, falls lesbar, sonst `path`.
    var launchSourceForRunner: String {
        let norm = FsClientShortcutsStore.normalizeShortcutTarget(path)
        let nl = norm.lowercased()
        if nl.hasPrefix("http://") || nl.hasPrefix("https://") {
            return norm
        }
        if let imp = importedFilePath?.trimmingCharacters(in: .whitespacesAndNewlines), !imp.isEmpty,
           FileManager.default.isReadableFile(atPath: imp) {
            return (imp as NSString).standardizingPath
        }
        return norm
    }
}

/// Persistiert in `menu-fsclients.json`.
struct FsClientShortcutsFile: Codable, Equatable {
    /// Menüleisten-Agent ist Standard (ab erstem Start); Datei wird beim ersten Launch angelegt.
    var menuBarExtraEnabled: Bool = true
    var shortcuts: [FsClientShortcutRecord] = []
}

@MainActor
final class FsClientShortcutsStore: ObservableObject {
    static let shared = FsClientShortcutsStore()

    @Published private(set) var file: FsClientShortcutsFile = FsClientShortcutsFile()

    private init() {}

    /// Erster Start / Installation: Datei anlegen oder laden; `menuBarExtraEnabled` immer auf `true` migrieren.
    func bootstrapTrayPersistenceAtLaunch() {
        let url = AppPaths.fsClientShortcutsURL
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            fputs("FSClientLauncher: App-Support-Verzeichnis: \(error.localizedDescription)\n", stderr)
        }

        if !fm.fileExists(atPath: url.path) {
            file = FsClientShortcutsFile(menuBarExtraEnabled: true, shortcuts: [])
            saveToDisk()
            return
        }
        guard let data = try? Data(contentsOf: url) else {
            file = FsClientShortcutsFile(menuBarExtraEnabled: true, shortcuts: [])
            saveToDisk()
            return
        }
        guard var decoded = try? JSONDecoder().decode(FsClientShortcutsFile.self, from: data) else {
            file = FsClientShortcutsFile(menuBarExtraEnabled: true, shortcuts: [])
            saveToDisk()
            return
        }
        if !decoded.menuBarExtraEnabled {
            decoded.menuBarExtraEnabled = true
            file = decoded
            saveToDisk()
        } else {
            file = decoded
        }
    }

    func loadFromDisk() {
        let url = AppPaths.fsClientShortcutsURL
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(FsClientShortcutsFile.self, from: data) else {
            file = FsClientShortcutsFile(menuBarExtraEnabled: true, shortcuts: [])
            return
        }
        file = decoded
    }

    func saveToDisk() {
        let url = AppPaths.fsClientShortcutsURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(file)
            let tmp = url.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
            try FileManager.default.moveItem(at: tmp, to: url)
            NotificationCenter.default.post(name: .fsclShortcutsChanged, object: nil)
        } catch {
            fputs("FSClientLauncher: menu-fsclients.json konnte nicht gespeichert werden: \(error.localizedDescription)\n", stderr)
        }
    }

    /// Gleicher Schlüssel für Duplikate: lokale Pfade standardisiert, URLs getrimmt.
    nonisolated static func normalizeShortcutTarget(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = t.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return t
        }
        if lower.hasPrefix("fsclientlauncher:") {
            return t
        }
        return (t as NSString).standardizingPath
    }

    /// Liest `title` aus einer lokalen `.fsclient`-Datei. Bei URL in `raw` optional `backingFile` (Import-Kopie).
    nonisolated static func readFsClientTitleIfPresent(fromShortcutTarget raw: String, backingFile: String? = nil) -> String? {
        let candidates: [String] = {
            var list: [String] = []
            if let b = backingFile?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty {
                list.append((b as NSString).standardizingPath)
            }
            let norm = normalizeShortcutTarget(raw)
            if !norm.lowercased().hasPrefix("http://"), !norm.lowercased().hasPrefix("https://") {
                list.append(norm)
            }
            return list
        }()
        for p in candidates {
            guard p.lowercased().hasSuffix(".fsclient"), FileManager.default.isReadableFile(atPath: p) else { continue }
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: p, isDirectory: false)),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let title = obj[ApiFsClientKeys.title] as? String
            else { continue }
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return nil
    }

    /// Gültiges Kürzel: lokale `.fsclient`-Datei oder per **Definition-API** `…/api/fsclient…` / `jnlpRemoteAPIURL` / weiteren **fsclient**-URLs.
    nonisolated static func isValidShortcutTarget(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        let lower = t.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return remoteFsClientDefinitionApiURL(from: t) != nil
                || jnlpRemoteAPIURL(from: t) != nil
                || fsclientRemoteAPIURL(from: t) != nil
        }
        if lower.hasPrefix("fsclientlauncher:") {
            if LaunchConfiguration.embeddedHttpURLFromFsClientLauncherJnlpBridge(t) != nil { return true }
            return LaunchConfiguration.isParsableFsClientLauncherLaunchURI(t)
        }
        return lower.hasSuffix(".fsclient") || lower.hasSuffix(".jnlp")
    }

    var menuBarExtraEnabled: Bool {
        file.menuBarExtraEnabled
    }

    func setMenuBarExtraEnabled(_ on: Bool) {
        var f = file
        f.menuBarExtraEnabled = on
        file = f
        saveToDisk()
    }

    /// Nach erfolgreichem Start: Anzeige-`path` (i. d. R. URL), optional `importedFilePath` für den Start.
    func upsertAfterSuccessfulLaunch(
        sourceKey: String,
        displayPath: String,
        importedFilePath: String?,
        defaultDisplayName: String
    ) {
        let openedNorm = Self.normalizeShortcutTarget(sourceKey)
        let display = Self.normalizeShortcutTarget(displayPath)
        let importStd = importedFilePath.map { ($0 as NSString).standardizingPath }
        var f = file
        let idx = f.shortcuts.firstIndex { r in
            if Self.normalizeShortcutTarget(r.path) == openedNorm { return true }
            if let imp = importStd,
               let rawImp = r.importedFilePath,
               (rawImp as NSString).standardizingPath == imp {
                return true
            }
            if let imp = importStd,
               !r.path.lowercased().hasPrefix("http://"),
               !r.path.lowercased().hasPrefix("https://"),
               (r.path as NSString).standardizingPath == imp {
                return true
            }
            return false
        }
        if let idx {
            f.shortcuts[idx].path = display
            f.shortcuts[idx].importedFilePath = importStd
            f.shortcuts[idx].displayName = defaultDisplayName
        } else {
            f.shortcuts.append(
                FsClientShortcutRecord(id: UUID(), path: display, importedFilePath: importStd, displayName: defaultDisplayName)
            )
        }
        file = f
        saveToDisk()
    }

    func updateRecord(id: UUID, displayName: String, path: String? = nil) {
        var f = file
        guard let idx = f.shortcuts.firstIndex(where: { $0.id == id }) else { return }
        let old = f.shortcuts[idx]
        f.shortcuts[idx].displayName = displayName
        if let path {
            let norm = Self.normalizeShortcutTarget(path)
            if norm != Self.normalizeShortcutTarget(old.path) {
                Self.deleteImportedFileIfOwned(old.importedFilePath)
                f.shortcuts[idx].importedFilePath = nil
            }
            f.shortcuts[idx].path = norm
        }
        file = f
        saveToDisk()
    }

    func deleteRecord(id: UUID) {
        var f = file
        guard let rec = f.shortcuts.first(where: { $0.id == id }) else { return }
        Self.deleteImportedFileIfOwned(rec.importedFilePath)
        f.shortcuts.removeAll { $0.id == id }
        file = f
        saveToDisk()
    }

    /// Legt einen **neuen** Eintrag an. `upsertAfterSuccessfulLaunch` ist nur für „nach erfolgreichem Start“ gedacht —
    /// bei gleicher URL/Pfad wie ein bestehender Eintrag passiert hier **kein** Überschreiben.
    @discardableResult
    func addRecord(path: String, displayName: String) -> Bool {
        let norm = Self.normalizeShortcutTarget(path)
        if file.shortcuts.contains(where: { Self.normalizeShortcutTarget($0.path) == norm }) {
            return false
        }
        var f = file
        f.shortcuts.append(FsClientShortcutRecord(id: UUID(), path: norm, importedFilePath: nil, displayName: displayName))
        file = f
        saveToDisk()
        return true
    }

    /// Entfernt nur Dateien unter unserem `ImportedFsClients`-Verzeichnis.
    nonisolated private static func deleteImportedFileIfOwned(_ path: String?) {
        guard let raw = path?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }
        let std = (raw as NSString).standardizingPath
        let root = AppPaths.importedFsClientsDirectory.path
        guard std.hasPrefix(root + "/") || std == root else { return }
        try? FileManager.default.removeItem(atPath: std)
    }

    func replaceAllShortcuts(_ list: [FsClientShortcutRecord]) {
        var f = file
        f.shortcuts = list
        file = f
        saveToDisk()
    }
}
