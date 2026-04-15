import Darwin
import Foundation

extension Notification.Name {
    static let fsclShortcutsChanged = Notification.Name("de.frameworksystems.fscl.shortcutsChanged")
}

/// Ein gespeicherter Eintrag für die Menüleiste / Einstellungen.
struct FsClientShortcutRecord: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    /// Standardisierter absoluter Pfad.
    var path: String
    var displayName: String
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

    var menuBarExtraEnabled: Bool {
        file.menuBarExtraEnabled
    }

    func setMenuBarExtraEnabled(_ on: Bool) {
        var f = file
        f.menuBarExtraEnabled = on
        file = f
        saveToDisk()
    }

    /// Nach erfolgreichem Start: in die Liste aufnehmen oder Anzeigenamen beibehalten, falls schon bekannt.
    func upsertAfterLaunch(filePath: String, defaultDisplayName: String) {
        let std = (filePath as NSString).standardizingPath
        var f = file
        if let idx = f.shortcuts.firstIndex(where: { ($0.path as NSString).standardizingPath == std }) {
            f.shortcuts[idx].path = std
            if f.shortcuts[idx].displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                f.shortcuts[idx].displayName = defaultDisplayName
            }
        } else {
            f.shortcuts.append(
                FsClientShortcutRecord(id: UUID(), path: std, displayName: defaultDisplayName)
            )
        }
        file = f
        saveToDisk()
    }

    func updateRecord(id: UUID, displayName: String, path: String? = nil) {
        var f = file
        guard let idx = f.shortcuts.firstIndex(where: { $0.id == id }) else { return }
        f.shortcuts[idx].displayName = displayName
        if let path {
            f.shortcuts[idx].path = (path as NSString).standardizingPath
        }
        file = f
        saveToDisk()
    }

    func deleteRecord(id: UUID) {
        var f = file
        f.shortcuts.removeAll { $0.id == id }
        file = f
        saveToDisk()
    }

    func addRecord(path: String, displayName: String) {
        let std = (path as NSString).standardizingPath
        if file.shortcuts.contains(where: { ($0.path as NSString).standardizingPath == std }) {
            upsertAfterLaunch(filePath: std, defaultDisplayName: displayName)
            return
        }
        var f = file
        f.shortcuts.append(FsClientShortcutRecord(id: UUID(), path: std, displayName: displayName))
        file = f
        saveToDisk()
    }

    func replaceAllShortcuts(_ list: [FsClientShortcutRecord]) {
        var f = file
        f.shortcuts = list
        file = f
        saveToDisk()
    }
}
