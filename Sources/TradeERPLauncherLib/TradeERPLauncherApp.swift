import AppKit
import Darwin
import SwiftUI

/// Einstiegspunkt für das ausführbare Ziel; wird von `Sources/TradeERPLauncher/Main.swift` aufgerufen.
public enum TradeERPLauncherEntry {
    @MainActor
    public static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Kein Dock-Symbol für den Launcher (Menüleiste/Tray); Fenster und Alerts bleiben nutzbar.
        app.setActivationPolicy(.accessory)
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// Verzögerungen rund um Finder/Startargumente (argv vs. `openFile`/`openURLs`).
    private enum LaunchTiming {
        /// `.fsclient` kommt oft parallel in `argv` und über `openFile` — kurz warten, damit nicht doppelt gestartet wird.
        static let argvFsclientFallbackDelay: TimeInterval = 0.35
        /// Ohne argv: Einstellungsfenster erst nach kurzer Pause, falls noch ein Datei-/URL-Start folgt.
        static let openConfigIfNoLaunchAfter: TimeInterval = 0.15
    }

    static weak var shared: AppDelegate?

    private var configWindow: NSWindow?
    /// Verhindert, dass die Konfiguration öffnet, bevor z. B. `application(_:openFile:)` nach einem Doppelklick auf `.fsclient` gelaufen ist.
    private var didStartLaunchFlow = false
    private lazy var inboundLaunch = InboundLaunchCoordinator(host: self)

    // MARK: - NSApplicationDelegate

    func applicationWillFinishLaunching(_ notification: Notification) {
        Self.shared = self
        AppPaths.migrateLegacyDirectoriesIfNeeded()
        RegisteredApplicationsStore.shared.bootstrapTrayPersistenceAtLaunch()
        MenuBarExtraController.shared.installIfNeeded()
        Self.installMinimalEditMenuIfNeeded()
        // Kein eigenes `applicationIconImage`: Dock nutzt das Bundle-Icon; Identifikation über Menüleiste (Tray).
        NSApp.applicationIconImage = nil
    }

    /// Verhindert, dass macOS die LSUIElement-App wegoptimiert, sobald Java läuft und keine eigenen Fenster offen sind.
    private var keepAliveActivity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        keepAliveActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated],
            reason: "\(LauncherProductNaming.displayName) (Menüleiste) bleibt aktiv"
        )
        MenuBarExtraController.shared.installIfNeeded()

        let args = CommandLine.arguments.dropFirst().filter { arg in
            if arg.hasPrefix("-psn_") { return false }
            if arg == "-NSDocumentRevisionsDebugMode" { return false }
            return true
        }
        if let first = args.first {
            // Doppelstart: macOS übergibt .fsclient oft in argv UND über openFile/openURLs.
            // Zwei parallele LaunchCoordinator-Läufe können fehlschlagen und NSApp.terminate auslösen.
            if first.lowercased().hasSuffix(".fsclient") {
                DispatchQueue.main.asyncAfter(deadline: .now() + LaunchTiming.argvFsclientFallbackDelay) { [weak self] in
                    guard let self else { return }
                    if !self.didStartLaunchFlow {
                        self.didStartLaunchFlow = true
                        Task { await self.inboundLaunch.runLaunchArgument(first) }
                    }
                }
            } else {
                didStartLaunchFlow = true
                Task { await inboundLaunch.runLaunchArgument(first) }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + LaunchTiming.openConfigIfNoLaunchAfter) { [weak self] in
                guard let self else { return }
                if !self.didStartLaunchFlow {
                    self.showConfigWindow()
                }
            }
        }
        Jre8FirstLaunchOffer.scheduleIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menüleisten-App: Prozess bleibt aktiv; Beenden nur über „… beenden“ im Tray-Menü.
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return false }
        showConfigWindowFromMenuBar()
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        didStartLaunchFlow = true
        for url in urls {
            Task { await self.inboundLaunch.runLaunchArgument(url) }
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        didStartLaunchFlow = true
        Task { await inboundLaunch.runLaunchArgument(filename) }
        return true
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let win = notification.object as? NSWindow, win === configWindow else { return }
        configWindow = nil
    }

    // MARK: - Edit-Menü (Cmd+C/V/X für TextField/TextEditor)

    /// Ohne Menü „Bearbeiten“ leiten Cmd+V/C/X u. a. nicht zu `NSTextField`/`NSTextView` (Accessory-App) → Systemton beim Einfügen.
    private static func installMinimalEditMenuIfNeeded() {
        if NSApp.mainMenu == nil {
            let main = NSMenu()
            let appName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? ProcessInfo.processInfo.processName
            let appItem = NSMenuItem()
            let appSub = NSMenu()
            let aboutItem = NSMenuItem(
                title: "Über \(appName)",
                action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                keyEquivalent: ""
            )
            aboutItem.target = NSApp
            appSub.addItem(aboutItem)
            appSub.addItem(.separator())
            appSub.addItem(withTitle: "\(appName) beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            appItem.submenu = appSub
            appItem.title = appName
            main.addItem(appItem)
            NSApp.mainMenu = main
        }
        guard let main = NSApp.mainMenu else { return }
        let hasEdit = main.items.contains { item in
            let t = item.title
            return t == "Bearbeiten" || t == "Edit"
        }
        if hasEdit { return }
        let editMenuItem = NSMenuItem()
        editMenuItem.title = "Bearbeiten"
        let editMenu = NSMenu(title: "Bearbeiten")
        editMenuItem.submenu = editMenu
        addStandardEditMenuItems(to: editMenu)
        if main.items.isEmpty {
            main.addItem(editMenuItem)
        } else {
            main.insertItem(editMenuItem, at: 1)
        }
    }

    private static func addStandardEditMenuItems(to menu: NSMenu) {
        func add(_ title: String, _ action: Selector, _ key: String, _ mask: NSEvent.ModifierFlags = .command) {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mask
            i.target = nil
            menu.addItem(i)
        }
        add("Widerrufen", Selector(("undo:")), "z")
        add("Wiederholen", Selector(("redo:")), "Z", [.command, .shift])
        menu.addItem(.separator())
        add("Ausschneiden", #selector(NSText.cut(_:)), "x")
        add("Kopieren", #selector(NSText.copy(_:)), "c")
        add("Einfügen", #selector(NSText.paste(_:)), "v")
        add("Alles auswählen", #selector(NSText.selectAll(_:)), "a")
    }

    // MARK: - Einstellungsfenster

    func showConfigWindowFromMenuBar() {
        showConfigWindow()
    }

    private func showConfigWindow() {
        if let w = configWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = NSHostingController(
            rootView: ConfigRootView().environmentObject(RegisteredApplicationsStore.shared)
        )
        let win = NSWindow(contentViewController: root)
        win.setContentSize(NSSize(width: 620, height: 640))
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.title = LauncherProductNaming.displayName
        win.center()
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        configWindow = win
    }

    // MARK: - Tray / registrierte Anwendungen

    func launchRegisteredApplicationFromMenuBar(path: String) {
        didStartLaunchFlow = true
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let persistShortcut = !trimmed.lowercased().hasPrefix("fsclientlauncher:")
        Task { await inboundLaunch.runLaunchArgument(path, persistShortcutAfterLaunch: persistShortcut) }
    }

    /// Tray / registrierte Anwendungen: je nach Eintrag Java-Client oder Weblink im Standardbrowser.
    func launchRegisteredApplication(recordId: UUID) {
        didStartLaunchFlow = true
        guard let rec = RegisteredApplicationsStore.shared.file.shortcuts.first(where: { $0.id == recordId }) else { return }
        if rec.targetKind == .webBookmark {
            openWebBookmark(rawTarget: rec.path)
            return
        }
        launchRegisteredApplicationFromMenuBar(path: rec.launchSourceForRunner)
    }

    /// Öffnet einen Weblink im Standardbrowser, mit präzisen Fehlerdialogen für die häufigen Stolperstellen.
    private func openWebBookmark(rawTarget: String) {
        let normalized = RegisteredApplicationsStore.normalizeShortcutTarget(rawTarget)
        guard RegisteredApplicationsStore.isValidWebBookmarkURL(normalized) else {
            presentSimpleAlert(
                title: "Ungültige Adresse",
                message: "Der gespeicherte Weblink ist keine gültige http(s)-URL."
            )
            return
        }
        guard let url = URL(string: normalized) else {
            presentSimpleAlert(
                title: "Ungültige Adresse",
                message: "Die URL konnte nicht interpretiert werden."
            )
            return
        }
        guard NSWorkspace.shared.open(url) else {
            presentSimpleAlert(
                title: "Link konnte nicht geöffnet werden",
                message: "macOS hat keinen Standardbrowser für diese Adresse geöffnet."
            )
            return
        }
    }

    private func presentSimpleAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Launch-Coordinator

    /// Nach Fehler/Abbruch: Tray sichtbar halten, kein automatisches Beenden (Nutzer: „… beenden“).
    func ensureTrayAfterLaunchFailure() {
        MenuBarExtraController.shared.installIfNeeded()
    }

    func runLaunchCoordinator(parsed: ParsedLaunchInput) async throws {
        let settings = LauncherSettings.load()
        if settings.DisplayConsole {
            await MainActor.run {
                JavaProcessOutputWindow.shared.present()
            }
        }
        try await LaunchCoordinator.run(
            launch: parsed.parameters,
            settings: settings,
            log: { line in
                if isatty(STDOUT_FILENO) != 0 {
                    fputs(line, stdout)
                    fflush(stdout)
                }
                if settings.DisplayConsole {
                    JavaProcessOutputWindow.shared.append(line)
                }
            },
            versionContinue: { required, installed in
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "\(LauncherProductNaming.displayName) aktualisieren?"
                    alert.informativeText =
                        "Der Broker verlangt mindestens Version \(required). Installiert ist \(installed).\n\nMit alter Version fortfahren?"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Fortfahren")
                    alert.addButton(withTitle: "Abbrechen")
                    return alert.runModal() == .alertFirstButtonReturn
                }
            }
        )
        await MainActor.run {
            handleSuccessfulClientLaunch(parsed: parsed)
        }
    }

    func presentLaunchError(_ error: Error) {
        let settings = LauncherSettings.load()
        if settings.DisplayConsole {
            JavaProcessOutputWindow.shared.present()
            JavaProcessOutputWindow.shared.append("\n—— Fehler: \(error.localizedDescription) ——\n")
        }
        let alert = NSAlert()
        alert.messageText = LauncherProductNaming.displayName
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.runModal()
        ensureTrayAfterLaunchFailure()
    }

    // MARK: - Persistierung nach erfolgreichem Start

    /// Wie eine `.fsclient`-Definition nach erfolgreichem Start abgelegt und im Tray verankert wird —
    /// abgeleitet aus `parsed`, damit `handleSuccessfulClientLaunch` nur **eine** Verzweigung braucht.
    private enum SuccessfulLaunchPersistenceMode: Equatable {
        /// Lokal geöffnete `.fsclient` an einem persistenten Pfad; `path` zeigt direkt darauf.
        case openedLocalFile(path: String)
        /// Lokal geöffnete `.fsclient`, aber unter einem **temporären** Pfad — Inhalt landet zusätzlich
        /// dedupliziert unter `ImportedLauncherDefinitions`.
        case openedEphemeralLocalFile
        /// Lokal geöffnete temporäre Datei, deren Inhalt **eigentlich** von einer http(s)-Definitions-URL kam.
        case openedEphemeralLocalFileFromHttpDefinition
        /// Start kam direkt von einer http(s)-Definitions-URL.
        case startedFromHttpDefinition
        /// Start kam von einer `fsclientlauncher:`-URI o. Ä.
        case startedFromInlineLauncherURI
    }

    private static func persistenceMode(for parsed: ParsedLaunchInput) -> SuccessfulLaunchPersistenceMode {
        if parsed.openedFromDirectLocalFile, let local = parsed.localFilePath {
            if AppPaths.isEphemeralLauncherDefinitionPath(local) {
                if looksLikeHttpOrHttps(parsed.originalArgument) {
                    return .openedEphemeralLocalFileFromHttpDefinition
                }
                return .openedEphemeralLocalFile
            }
            return .openedLocalFile(path: local)
        }
        if looksLikeHttpOrHttps(parsed.originalArgument) {
            return .startedFromHttpDefinition
        }
        return .startedFromInlineLauncherURI
    }

    private static func looksLikeHttpOrHttps(_ s: String) -> Bool {
        let l = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return l.hasPrefix("http://") || l.hasPrefix("https://")
    }

    private func handleSuccessfulClientLaunch(parsed: ParsedLaunchInput) {
        guard parsed.persistShortcutAfterLaunch else {
            MenuBarExtraController.shared.installIfNeeded()
            return
        }
        let store = RegisteredApplicationsStore.shared
        let displayName = parsed.parameters.displayNameForShortcutMenu(
            originalArgument: parsed.originalArgument,
            localFilePath: parsed.localFilePath
        )
        let mode = Self.persistenceMode(for: parsed)
        do {
            switch mode {
            case .openedLocalFile(let path):
                store.upsertAfterSuccessfulLaunch(
                    sourceKey: parsed.originalArgument,
                    displayPath: path,
                    importedFilePath: nil,
                    defaultDisplayName: displayName
                )
            case .openedEphemeralLocalFile:
                let saved = try AppPaths.saveImportedDefinitionJson(parsed.jsonData)
                store.upsertAfterSuccessfulLaunch(
                    sourceKey: parsed.originalArgument,
                    displayPath: saved,
                    importedFilePath: nil,
                    defaultDisplayName: displayName
                )
            case .openedEphemeralLocalFileFromHttpDefinition, .startedFromHttpDefinition:
                let saved = try AppPaths.saveImportedDefinitionJson(parsed.jsonData)
                let displayURL = RegisteredApplicationsStore.normalizeShortcutTarget(parsed.originalArgument)
                store.upsertAfterSuccessfulLaunch(
                    sourceKey: parsed.originalArgument,
                    displayPath: displayURL,
                    importedFilePath: saved,
                    defaultDisplayName: displayName
                )
            case .startedFromInlineLauncherURI:
                let saved = try AppPaths.saveImportedDefinitionJson(parsed.jsonData)
                store.upsertAfterSuccessfulLaunch(
                    sourceKey: parsed.originalArgument,
                    displayPath: parsed.originalArgument.trimmingCharacters(in: .whitespacesAndNewlines),
                    importedFilePath: saved,
                    defaultDisplayName: displayName
                )
            }
        } catch {
            fputs(
                "TradeERPLauncher: .fsclient konnte nicht unter ImportedLauncherDefinitions gespeichert werden: \(error.localizedDescription)\n",
                stderr
            )
            // Fallback ohne Import-Datei: für http(s)-Quellen zumindest den Display-Eintrag persistieren,
            // damit der Tray-Eintrag nach einem erfolgreichen Start auftaucht.
            if Self.looksLikeHttpOrHttps(parsed.originalArgument) {
                let displayURL = RegisteredApplicationsStore.normalizeShortcutTarget(parsed.originalArgument)
                store.upsertAfterSuccessfulLaunch(
                    sourceKey: parsed.originalArgument,
                    displayPath: displayURL,
                    importedFilePath: nil,
                    defaultDisplayName: displayName
                )
            }
        }
        MenuBarExtraController.shared.installIfNeeded()
    }
}
