import Darwin
import Foundation

extension Notification.Name {
    /// Wird nach dem Speichern von `registered-applications-menu.json` gesendet (Menüleiste neu laden).
    static let registeredApplicationsMenuDidChange = Notification.Name("de.bizolution.trade-erp-launcher.registeredApplicationsMenuDidChange")
}

/// Ein gespeicherter Eintrag für die Menüleiste / Einstellungen.
struct RegisteredApplicationRecord: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    /// Anzeige & logische Quelle: **http(s)-URL** oder lokaler Pfad zur `.fsclient`-Datei (wie vom Nutzer erwartet).
    var path: String
    /// Optional: unter `ImportedLauncherDefinitions` gespeicherte Kopie — beim **Start** nur für **nicht-http(s)**-Kürzel genutzt; bei http(s) zählt immer `path` (erneuter Download).
    var importedFilePath: String?
    var displayName: String
    /// SHA256 (hex) des heruntergeladenen `Icon.png`-Inhalts; Datei `…/RegisteredAppIcons/<hash>.png` (mehrere Apps können dasselbe Icon teilen).
    ///
    /// **Migration:** Fehlt der Schlüssel in älteren `registered-applications-menu.json`, bleibt der Wert `nil` — `enqueueMissingBrokerIconFetches()` lädt Icons beim nächsten Start nach.
    var iconContentHash: String?

    /// Argument für `LaunchConfiguration.load`: Bei **http(s)-Kürzeln** immer die gespeicherte URL (erneuter Download) — eine alte `importedFilePath`-Kopie darf den Start nicht kapern. Sonst: Import-Datei, falls lesbar, sonst `path`.
    var launchSourceForRunner: String {
        let norm = RegisteredApplicationsStore.normalizeShortcutTarget(path)
        let nl = norm.lowercased()
        if nl.hasPrefix("http://") || nl.hasPrefix("https://") {
            return norm
        }
        if let imp = importedFilePath?.trimmingCharacters(in: .whitespacesAndNewlines), !imp.isEmpty {
            let std = (imp as NSString).standardizingPath
            let rewritten = AppPaths.rewriteLegacyUserDataPath(std)
            if FileManager.default.isReadableFile(atPath: rewritten) {
                return rewritten
            }
            if FileManager.default.isReadableFile(atPath: std) {
                return std
            }
        }
        return norm
    }
}

/// Persistiert in `registered-applications-menu.json`.
struct RegisteredApplicationsFile: Codable, Equatable {
    /// Menüleisten-Agent ist Standard (ab erstem Start); Datei wird beim ersten Launch angelegt.
    var menuBarExtraEnabled: Bool = true
    var shortcuts: [RegisteredApplicationRecord] = []
}

@MainActor
final class RegisteredApplicationsStore: ObservableObject {
    static let shared = RegisteredApplicationsStore()

    @Published private(set) var file: RegisteredApplicationsFile = RegisteredApplicationsFile()

    private init() {}

    /// Erster Start / Installation: Datei anlegen oder laden; `menuBarExtraEnabled` immer auf `true` migrieren.
    func bootstrapTrayPersistenceAtLaunch() {
        let url = AppPaths.registeredApplicationsMenuJSONURL
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            fputs("TradeERPLauncher: App-Support-Verzeichnis: \(error.localizedDescription)\n", stderr)
        }

        if !fm.fileExists(atPath: url.path) {
            file = RegisteredApplicationsFile(menuBarExtraEnabled: true, shortcuts: [])
            saveToDisk()
            return
        }
        guard let data = try? Data(contentsOf: url) else {
            file = RegisteredApplicationsFile(menuBarExtraEnabled: true, shortcuts: [])
            saveToDisk()
            return
        }
        guard var decoded = try? JSONDecoder().decode(RegisteredApplicationsFile.self, from: data) else {
            file = RegisteredApplicationsFile(menuBarExtraEnabled: true, shortcuts: [])
            saveToDisk()
            return
        }
        var changed = Self.applyLegacyPathRewrites(to: &decoded)
        if !decoded.menuBarExtraEnabled {
            decoded.menuBarExtraEnabled = true
            changed = true
        }
        file = decoded
        if changed {
            saveToDisk()
        }
        enqueueMissingBrokerIconFetches()
    }

    func loadFromDisk() {
        let url = AppPaths.registeredApplicationsMenuJSONURL
        guard let data = try? Data(contentsOf: url),
              var decoded = try? JSONDecoder().decode(RegisteredApplicationsFile.self, from: data) else {
            file = RegisteredApplicationsFile(menuBarExtraEnabled: true, shortcuts: [])
            return
        }
        let changed = Self.applyLegacyPathRewrites(to: &decoded)
        file = decoded
        if changed {
            saveToDisk()
        }
        enqueueMissingBrokerIconFetches()
    }

    func saveToDisk() {
        let url = AppPaths.registeredApplicationsMenuJSONURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(file)
            let tmp = url.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
            try FileManager.default.moveItem(at: tmp, to: url)
            NotificationCenter.default.post(name: .registeredApplicationsMenuDidChange, object: nil)
        } catch {
            fputs("TradeERPLauncher: registered-applications-menu.json konnte nicht gespeichert werden: \(error.localizedDescription)\n", stderr)
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
    nonisolated static func readDefinitionTitleIfPresent(fromShortcutTarget raw: String, backingFile: String? = nil) -> String? {
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
                  let title = obj[LaunchParameterKey.title] as? String
            else { continue }
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return nil
    }

    /// Gültiges Kürzel: lokale `.fsclient`-Datei oder per **Definition-API** `…/api/fsclient…` / `…/api/jnlp…` / weiteren **fsclient**-http(s)-URLs.
    nonisolated static func isValidShortcutTarget(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        let lower = t.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return remoteClientDefinitionApiURL(from: t) != nil
                || jnlpRemoteAPIURL(from: t) != nil
                || remoteDefinitionDocumentURL(from: t) != nil
        }
        if lower.hasPrefix("fsclientlauncher:") {
            if LaunchConfiguration.embeddedHttpURLFromLauncherJnlpBridge(t) != nil { return true }
            return LaunchConfiguration.isParsableLauncherLaunchURI(t)
        }
        return lower.hasSuffix(".fsclient")
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
            let oldNorm = Self.normalizeShortcutTarget(f.shortcuts[idx].path)
            let newNorm = Self.normalizeShortcutTarget(display)
            if oldNorm != newNorm {
                f.shortcuts[idx].iconContentHash = nil
            }
            f.shortcuts[idx].path = display
            f.shortcuts[idx].importedFilePath = importStd
            f.shortcuts[idx].displayName = defaultDisplayName
            let id = f.shortcuts[idx].id
            file = f
            saveToDisk()
            if Self.recordNeedsBrokerIconFetch(f.shortcuts.first(where: { $0.id == id })) {
                enqueueBrokerIconFetch(for: id)
            }
        } else {
            let newId = UUID()
            f.shortcuts.append(
                RegisteredApplicationRecord(
                    id: newId,
                    path: display,
                    importedFilePath: importStd,
                    displayName: defaultDisplayName,
                    iconContentHash: nil
                )
            )
            file = f
            saveToDisk()
            if Self.recordNeedsBrokerIconFetch(f.shortcuts.first(where: { $0.id == newId })) {
                enqueueBrokerIconFetch(for: newId)
            }
        }
    }

    func updateRecord(id: UUID, displayName: String, path: String? = nil) {
        var f = file
        guard let idx = f.shortcuts.firstIndex(where: { $0.id == id }) else { return }
        let old = f.shortcuts[idx]
        f.shortcuts[idx].displayName = displayName
        var pathChanged = false
        if let path {
            let norm = Self.normalizeShortcutTarget(path)
            if norm != Self.normalizeShortcutTarget(old.path) {
                pathChanged = true
                Self.deleteImportedFileIfOwned(old.importedFilePath)
                f.shortcuts[idx].importedFilePath = nil
                f.shortcuts[idx].iconContentHash = nil
            }
            f.shortcuts[idx].path = norm
        }
        file = f
        saveToDisk()
        if pathChanged, Self.recordNeedsBrokerIconFetch(f.shortcuts.first(where: { $0.id == id })) {
            enqueueBrokerIconFetch(for: id)
        }
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
        let newId = UUID()
        var f = file
        f.shortcuts.append(
            RegisteredApplicationRecord(id: newId, path: norm, importedFilePath: nil, displayName: displayName, iconContentHash: nil)
        )
        file = f
        saveToDisk()
        if Self.recordNeedsBrokerIconFetch(f.shortcuts.first(where: { $0.id == newId })) {
            enqueueBrokerIconFetch(for: newId)
        }
        return true
    }

    /// Entfernt nur Dateien unter unserem Import-Verzeichnis (inkl. erkanntem Legacy-Pfad nach Rewrite).
    nonisolated private static func deleteImportedFileIfOwned(_ path: String?) {
        guard let raw = path?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }
        let std = AppPaths.rewriteLegacyUserDataPath((raw as NSString).standardizingPath)
        let root = AppPaths.importedApplicationDefinitionsDirectory.path
        guard std.hasPrefix(root + "/") || std == root else { return }
        try? FileManager.default.removeItem(atPath: std)
    }

    @discardableResult
    private static func applyLegacyPathRewrites(to file: inout RegisteredApplicationsFile) -> Bool {
        var changed = false
        for i in file.shortcuts.indices {
            let newPath = AppPaths.rewriteLegacyUserDataPath(file.shortcuts[i].path)
            if newPath != file.shortcuts[i].path {
                file.shortcuts[i].path = newPath
                changed = true
            }
            if let imp = file.shortcuts[i].importedFilePath {
                let newI = AppPaths.rewriteLegacyUserDataPath(imp)
                if newI != imp {
                    file.shortcuts[i].importedFilePath = newI
                    changed = true
                }
            }
        }
        return changed
    }

    func replaceAllShortcuts(_ list: [RegisteredApplicationRecord]) {
        var f = file
        f.shortcuts = list
        file = f
        saveToDisk()
        enqueueMissingBrokerIconFetches()
    }

    private func enqueueMissingBrokerIconFetches() {
        for rec in file.shortcuts where Self.recordNeedsBrokerIconFetch(rec) {
            enqueueBrokerIconFetch(for: rec.id)
        }
    }

    /// `true`, wenn ein Broker-Stamm ermittelbar ist und noch kein gültiges Icon im Cache liegt.
    private static func recordNeedsBrokerIconFetch(_ rec: RegisteredApplicationRecord?) -> Bool {
        guard let rec else { return false }
        guard LaunchConfiguration.brokerBaseStringForApplicationIcon(
            shortcutTarget: rec.path,
            backingFilePath: rec.importedFilePath
        ) != nil else {
            return false
        }
        if let h = rec.iconContentHash, !h.isEmpty,
           FileManager.default.isReadableFile(atPath: RegisteredApplicationIconCache.fileURL(contentHashHex: h).path) {
            return false
        }
        return true
    }

    private func enqueueBrokerIconFetch(for recordId: UUID) {
        Task { @MainActor in
            await fetchBrokerIconForRegisteredApplication(recordId: recordId)
        }
    }

    private func fetchBrokerIconForRegisteredApplication(recordId: UUID) async {
        guard let rec = file.shortcuts.first(where: { $0.id == recordId }),
              Self.recordNeedsBrokerIconFetch(rec) else { return }
        guard let brokerStr = LaunchConfiguration.brokerBaseStringForApplicationIcon(
            shortcutTarget: rec.path,
            backingFilePath: rec.importedFilePath
        ) else { return }
        guard let brokerURL = URL(string: brokerStr) else { return }
        guard let hash = await RegisteredApplicationIconCache.downloadAndStorePngIfMissing(brokerRoot: brokerURL) else { return }
        var f = file
        guard let idx = f.shortcuts.firstIndex(where: { $0.id == recordId }) else { return }
        if f.shortcuts[idx].iconContentHash == hash { return }
        f.shortcuts[idx].iconContentHash = hash
        file = f
        saveToDisk()
    }
}
