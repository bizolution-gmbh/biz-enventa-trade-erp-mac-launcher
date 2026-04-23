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
    /// Verhindert, dass die Konfiguration öffnet, bevor z. B. `application(_:openFile:)` nach einem Doppelklick auf `.fsclient` gelaufen ist.
    private var didStartLaunchFlow = false
    private lazy var inboundLaunch = InboundLaunchCoordinator(host: self)

    func applicationWillFinishLaunching(_ notification: Notification) {
        Self.shared = self
        AppPaths.migrateLegacyDirectoriesIfNeeded()
        RegisteredApplicationsStore.shared.bootstrapTrayPersistenceAtLaunch()
        MenuBarExtraController.shared.installIfNeeded()
        Self.installMinimalEditMenuIfNeeded()
        // Kein eigenes `applicationIconImage`: Dock nutzt das Bundle-Icon; Identifikation über Menüleiste (Tray).
        NSApp.applicationIconImage = nil
    }

    /// Ohne Menü „Bearbeiten“ leiten Cmd+V/C/X u. a. nicht zu `NSTextField`/`NSTextView` (Accessory-App) → Systemton beim Einfügen.
    private static func installMinimalEditMenuIfNeeded() {
        if NSApp.mainMenu == nil {
            let main = NSMenu()
            let appName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? ProcessInfo.processInfo.processName
            let appItem = NSMenuItem()
            appItem.submenu = NSMenu()
            appItem.submenu?.addItem(withTitle: "\(appName) beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menüleisten-App: Prozess bleibt aktiv; Beenden nur über „enventa Trade ERP Launcher beenden“ im Tray.
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

    /// Verhindert, dass macOS die LSUIElement-App wegoptimiert, sobald Java läuft und keine eigenen Fenster offen sind.
    private var keepAliveActivity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        keepAliveActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated],
            reason: "enventa Trade ERP Launcher (Menüleiste) bleibt aktiv"
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

    func windowWillClose(_ notification: Notification) {
        guard let win = notification.object as? NSWindow, win === configWindow else { return }
        configWindow = nil
    }

    func showConfigWindowFromMenuBar() {
        showConfigWindow()
    }

    func launchRegisteredApplicationFromMenuBar(path: String) {
        didStartLaunchFlow = true
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let persistShortcut = !trimmed.lowercased().hasPrefix("fsclientlauncher:")
        Task { await inboundLaunch.runLaunchArgument(path, persistShortcutAfterLaunch: persistShortcut) }
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
        win.title = "enventa Trade ERP Launcher"
        win.center()
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        configWindow = win
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
        let name = parsed.parameters.displayNameForShortcutMenu(
            originalArgument: parsed.originalArgument,
            localFilePath: parsed.localFilePath
        )
        do {
            if parsed.openedFromDirectLocalFile, let local = parsed.localFilePath {
                if AppPaths.isEphemeralLauncherDefinitionPath(local), Self.looksLikeHttpOrHttps(parsed.originalArgument) {
                    let saved = try AppPaths.saveImportedDefinitionJson(parsed.jsonData)
                    let displayURL = RegisteredApplicationsStore.normalizeShortcutTarget(parsed.originalArgument)
                    store.upsertAfterSuccessfulLaunch(
                        sourceKey: parsed.originalArgument,
                        displayPath: displayURL,
                        importedFilePath: saved,
                        defaultDisplayName: name
                    )
                } else if AppPaths.isEphemeralLauncherDefinitionPath(local) {
                    let saved = try AppPaths.saveImportedDefinitionJson(parsed.jsonData)
                    store.upsertAfterSuccessfulLaunch(
                        sourceKey: parsed.originalArgument,
                        displayPath: saved,
                        importedFilePath: nil,
                        defaultDisplayName: name
                    )
                } else {
                    store.upsertAfterSuccessfulLaunch(
                        sourceKey: parsed.originalArgument,
                        displayPath: local,
                        importedFilePath: nil,
                        defaultDisplayName: name
                    )
                }
            } else if Self.looksLikeHttpOrHttps(parsed.originalArgument) {
                let saved = try AppPaths.saveImportedDefinitionJson(parsed.jsonData)
                let displayURL = RegisteredApplicationsStore.normalizeShortcutTarget(parsed.originalArgument)
                store.upsertAfterSuccessfulLaunch(
                    sourceKey: parsed.originalArgument,
                    displayPath: displayURL,
                    importedFilePath: saved,
                    defaultDisplayName: name
                )
            } else {
                let saved = try AppPaths.saveImportedDefinitionJson(parsed.jsonData)
                store.upsertAfterSuccessfulLaunch(
                    sourceKey: parsed.originalArgument,
                    displayPath: parsed.originalArgument.trimmingCharacters(in: .whitespacesAndNewlines),
                    importedFilePath: saved,
                    defaultDisplayName: name
                )
            }
        } catch {
            fputs(
                "TradeERPLauncher: .fsclient konnte nicht unter ImportedLauncherDefinitions gespeichert werden: \(error.localizedDescription)\n",
                stderr
            )
            if Self.looksLikeHttpOrHttps(parsed.originalArgument) {
                let displayURL = RegisteredApplicationsStore.normalizeShortcutTarget(parsed.originalArgument)
                store.upsertAfterSuccessfulLaunch(
                    sourceKey: parsed.originalArgument,
                    displayPath: displayURL,
                    importedFilePath: nil,
                    defaultDisplayName: name
                )
            }
        }
        MenuBarExtraController.shared.installIfNeeded()
    }

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
                    alert.messageText = "enventa Trade ERP Launcher aktualisieren?"
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
        alert.messageText = "enventa Trade ERP Launcher"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.runModal()
        ensureTrayAfterLaunchFailure()
    }
}

private struct ConfigRootView: View {
    @EnvironmentObject private var shortcutsStore: RegisteredApplicationsStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings = LauncherSettings.load()
    @State private var javaVmJoined = ""
    @State private var java8Joined = ""
    @State private var java11Joined = ""
    @State private var java21Joined = ""
    @State private var java8RuntimePresent = false
    @State private var java11RuntimePresent = false
    @State private var java21RuntimePresent = false
    @State private var java8RuntimePrefs = Java8RuntimePreferences.empty

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EnventaLogoHeader()
                .padding(.top, 8)
            TabView {
                generalTab
                    .tabItem {
                        Label("Allgemein", systemImage: "gearshape")
                    }
                jvmArgumentsTab
                    .tabItem {
                        Label("JVM-Argumente", systemImage: "doc.plaintext")
                    }
                Java8RuntimesSettingsView(prefs: $java8RuntimePrefs)
                    .tabItem {
                        Label("Java-Laufzeitumgebungen", systemImage: "arrow.down.doc")
                    }
                RegisteredApplicationsSettingsView(store: shortcutsStore)
                    .tabItem {
                        Label("Anwendungen", systemImage: "square.grid.2x2")
                    }
            }
            .padding(.horizontal, 12)
            Divider()
            HStack {
                Spacer()
                Button("Speichern") {
                    persistSettings()
                }
                .keyboardShortcut("s", modifiers: [.command])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar.opacity(0.35))

            Text("© 2026 BIZOLUTION GmbH")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 8)
        }
        .onAppear {
            shortcutsStore.loadFromDisk()
            reloadSettingsState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tradeERPLauncherJavaRuntimesChanged)) { _ in
            reloadSettingsState()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                refreshJavaRuntimePresence()
            }
        }
    }

    private func reloadSettingsState() {
        settings = LauncherSettings.load()
        javaVmJoined = settings.JavaVmArguments.joined(separator: "\n")
        java8Joined = settings.Java8VmArguments.joined(separator: "\n")
        java11Joined = settings.Java11VmArguments.joined(separator: "\n")
        java21Joined = settings.Java21VmArguments.joined(separator: "\n")
        java8RuntimePrefs = settings.Java8RuntimePreferences ?? .empty
        refreshJavaRuntimePresence()
    }

    private func refreshJavaRuntimePresence() {
        let was8 = java8RuntimePresent
        let was11 = java11RuntimePresent
        let was21 = java21RuntimePresent
        java8RuntimePresent = JavaRuntimeResolver.isJava8RuntimePresent()
        java11RuntimePresent = JavaRuntimeResolver.isJava11RuntimePresent()
        java21RuntimePresent = JavaRuntimeResolver.isJava21RuntimePresent()
        let anyNewlyPresent =
            (java8RuntimePresent && !was8) || (java11RuntimePresent && !was11) || (java21RuntimePresent && !was21)
        guard anyNewlyPresent else { return }
        let disk = LauncherSettings.load()
        if java8RuntimePresent && !was8 {
            java8Joined = disk.Java8VmArguments.joined(separator: "\n")
            settings.Java8VmArguments = disk.Java8VmArguments
        }
        if java11RuntimePresent && !was11 {
            java11Joined = disk.Java11VmArguments.joined(separator: "\n")
            settings.Java11VmArguments = disk.Java11VmArguments
        }
        if java21RuntimePresent && !was21 {
            java21Joined = disk.Java21VmArguments.joined(separator: "\n")
            settings.Java21VmArguments = disk.Java21VmArguments
        }
    }

    private func persistSettings() {
        settings.JavaVmArguments = splitLines(javaVmJoined)
        settings.Java8VmArguments = splitLines(java8Joined)
        settings.Java11VmArguments = splitLines(java11Joined)
        settings.Java21VmArguments = splitLines(java21Joined)
        settings.Java8RuntimePreferences = java8RuntimePrefs
        settings.save()
    }

    @ViewBuilder
    private var generalTab: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.title2)
                        .accessibilityHidden(true)
                    Text(
                        "Dieser Launcher ist kein offizielles Produkt der enventa group GmbH. enventa Trade ERP lässt sich auf dem Mac nur sehr eingeschränkt nutzen."
                    )
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.14))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "Hinweis: Dieser Launcher ist kein offizielles Produkt der enventa group GmbH. enventa Trade ERP lässt sich auf dem Mac nur sehr eingeschränkt nutzen."
                )
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))

            Section("Allgemein") {
                Toggle(
                    "Konsole: Java-Flags (DisplayConsole, -DDisplayConsole) und Ausgabefenster (Stdout/Stderr)",
                    isOn: $settings.DisplayConsole
                )
                Stepper("Cache-Bereinigung nach \(settings.CacheCleanDays) Tagen", value: $settings.CacheCleanDays, in: 0 ... 365)
                Picker("Trace-Level", selection: $settings.TraceLevel) {
                    ForEach(TraceLevel.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                Picker("Java-Version nutzen", selection: $settings.UseJavaVersion) {
                    ForEach(UseJavaVersion.allCases) { u in
                        Text(u.rawValue).tag(u)
                    }
                }
                Picker("Proxy", selection: $settings.ProxyMode) {
                    ForEach(ProxyMode.allCases) { p in
                        Text(p.label).tag(p)
                    }
                }
            }
            Section("Pfade") {
                LabeledContent("JAR-Cache") {
                    Text(AppPaths.jarCacheDirectory.path).textSelection(.enabled)
                }
                LabeledContent("Konfiguration") {
                    Text(AppPaths.launcherConfigURL.path).textSelection(.enabled)
                }
                LabeledContent("Menüleiste / Anwendungen") {
                    Text(AppPaths.registeredApplicationsMenuJSONURL.path).textSelection(.enabled)
                }
                LabeledContent("Logdateien") {
                    Text(AppPaths.logFilesDirectory.path).textSelection(.enabled)
                }
            }
            Section("Cache") {
                Button("Cache gemäß Aufbewahrungsfrist bereinigen") {
                    CacheCleanup.cleanupCache(days: nil, cacheCleanDays: settings.CacheCleanDays)
                }
                Button("Gesamten Cache leeren …") {
                    let alert = NSAlert()
                    alert.messageText = "Gesamten Cache leeren?"
                    alert.informativeText = "Alle zwischengespeicherten Broker-JSONs, JARs und zugehörige Dateien werden gelöscht. Logdateien werden ebenfalls entfernt."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Leeren")
                    alert.addButton(withTitle: "Abbrechen")
                    if alert.runModal() == .alertFirstButtonReturn {
                        CacheCleanup.cleanupCache(days: 0, cacheCleanDays: settings.CacheCleanDays)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private var jvmArgumentsTab: some View {
        Form {
            Section {
                Text(jvmArgumentsTabIntro)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Zusätzliche JVM-Argumente (alle Versionen, je Zeile)") {
                TextEditor(text: $javaVmJoined)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 72)
            }
            if java8RuntimePresent {
                Section {
                    TextEditor(text: $java8Joined)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 56)
                    Button("Auf macOS-Standard zurücksetzen") {
                        java8Joined = LauncherSettings.recommendedJava8VmArgumentsForMacOS.joined(separator: "\n")
                    }
                } header: {
                    Text("Java 8")
                } footer: {
                    Text(
                        "Ist die Liste leer, trägt der Launcher beim nächsten Laden die mitgelieferten Standard-Argumente ein (wenn Java 8 verfügbar ist)."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            if java11RuntimePresent {
                Section("Java 11") {
                    TextEditor(text: $java11Joined)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 56)
                }
            }
            if java21RuntimePresent {
                Section("Java 21") {
                    TextEditor(text: $java21Joined)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 56)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            refreshJavaRuntimePresence()
        }
    }

    private var jvmArgumentsTabIntro: String {
        var parts: [String] = [
            "Eine Zeile pro JVM-Argument (z. B. -D…). Änderungen mit „Speichern“ oder ⌘S übernehmen."
        ]
        if !java8RuntimePresent || !java11RuntimePresent || !java21RuntimePresent {
            parts.append(
                "Zusätzliche Felder für Java 8, 11 oder 21 erscheinen automatisch, sobald die passende Laufzeit erkannt wird (Übersicht im Tab „Java-Laufzeitumgebungen“)."
            )
        }
        if !java8RuntimePresent {
            parts.append(
                "Fehlt Java 8 mit JavaFX: Tab „Java-Laufzeitumgebungen“ — dort können Sie die Laufzeit herunterladen oder beim nächsten App-Start den Hinweisdialog nutzen."
            )
        }
        return parts.joined(separator: " ")
    }

    private func splitLines(_ s: String) -> [String] {
        s.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Java-Laufzeitumgebungen (Übersicht + Download-Quellen)

/// Erste Zeile von `java -version` (stderr/stdout) — außerhalb des MainActor, damit `Task.detached` Swift-6-konform bleibt.
private enum JavaRuntimeVersionQuery {
    static func firstLine(javaExecutable: URL) -> String? {
        let p = Process()
        p.executableURL = javaExecutable
        p.arguments = ["-version"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
        } catch {
            return nil
        }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let first = raw.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? raw
        return String(first.prefix(200))
    }
}

/// Zwei Tabellen in `Form`-Abschnitten: zuerst übernommene Pfade, dann erkannte Installationen (HIG: klare Abschnitte, kurze Begleittexte).
private struct JavaRuntimeSettingsOverviewFormSections: View {
    let rows: [JavaRuntimeResolver.JavaRuntimeConfiguredRow]
    let fsclMirror: [JavaRuntimeResolver.FsclEnvironmentProcessMirrorLine]
    @Binding var javaVersionFirstLines: [Int: String]

    var body: some View {
        Group {
            Section {
                Text("Welche Java-Versionen gefunden wurden und ob ein am Computer vorgegebener Ordner genutzt werden kann.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Table(fsclMirror) {
                    TableColumn("Version") { line in
                        Text(line.rowTitle)
                            .monospacedDigit()
                    }
                    .width(min: 56, ideal: 72)
                    TableColumn("Übernommener Ordner") { line in
                        Text(line.valueDescription)
                            .font(.body)
                            .textSelection(.enabled)
                            .lineLimit(4)
                    }
                    .width(min: 200, ideal: 400)
                }
                .tableStyle(.inset)
            } header: {
                Text("Vom Computer übernommene Ordner")
            } footer: {
                Text("Nur der jeweilige App-Start zählt: Wenn Sie etwas testweise geändert haben, beenden Sie den Launcher in der Menüleiste vollständig und starten Sie neu.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Table(rows) {
                    TableColumn("Version") { r in
                        Text("\(r.majorVersion)")
                            .monospacedDigit()
                            .frame(minWidth: 32, alignment: .leading)
                    }
                    .width(min: 56, ideal: 72)
                    TableColumn("Status") { r in
                        Text(r.statusDescriptionGerman)
                    }
                    .width(ideal: 110)
                    TableColumn("Quelle") { r in
                        Text(r.originDescriptionGerman)
                            .lineLimit(3)
                    }
                    .width(min: 140, ideal: 220)
                    TableColumn("Installationsordner") { r in
                        JavaRuntimePathTableCell(primary: r.javaHomePath, invalidFallback: r.invalidConfiguredPath)
                    }
                    .width(min: 160, ideal: 260)
                    TableColumn("Startprogramm") { r in
                        JavaRuntimePathTableCell(primary: r.javaExecutablePath, invalidFallback: nil)
                    }
                    .width(min: 160, ideal: 260)
                    TableColumn("Versionsinfo") { r in
                        Text(javaVersionFirstLines[r.majorVersion] ?? "…")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .foregroundStyle(javaVersionFirstLines[r.majorVersion] == nil ? .secondary : .primary)
                    }
                    .width(min: 120, ideal: 280)
                }
                .tableStyle(.inset)
            } header: {
                Text("Erkannte Installationen")
            } footer: {
                Text("„Bereit“ heißt: Diese Version kann zum Start des Handelsprogramms verwendet werden. Technische Hintergründe und Variablennamen stehen in der README.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct JavaRuntimePathTableCell: View {
    let primary: String?
    let invalidFallback: String?

    var body: some View {
        Group {
            if let primary, !primary.isEmpty {
                Text(primary)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            } else if let invalidFallback, !invalidFallback.isEmpty {
                Text(invalidFallback)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            } else {
                Text("—")
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct Java8RuntimesSettingsView: View {
    @Binding var prefs: Java8RuntimePreferences
    @State private var jre8DownloadBusy = false
    @State private var configuredRows: [JavaRuntimeResolver.JavaRuntimeConfiguredRow] = JavaRuntimeResolver.javaRuntimeConfiguredRows()
    @State private var fsclMirror: [JavaRuntimeResolver.FsclEnvironmentProcessMirrorLine] = JavaRuntimeResolver.fsclEnvironmentProcessMirrorLines()
    @State private var javaVersionFirstLines: [Int: String] = [:]
    @State private var editingCustomEntryId: String?
    @State private var showCustomEntrySheet = false

    private func canAttemptJava8Download() -> Bool {
        guard let hw = MacHardwareArchitecture.current() else { return false }
        var s = LauncherSettings.load()
        s.Java8RuntimePreferences = prefs
        return Java8RuntimeDownloadResolver.resolve(settings: s, hardware: hw) != nil
    }

    private func refreshConfiguredRows() {
        configuredRows = JavaRuntimeResolver.javaRuntimeConfiguredRows()
        fsclMirror = JavaRuntimeResolver.fsclEnvironmentProcessMirrorLines()
    }

    private func rowsSignature(_ rows: [JavaRuntimeResolver.JavaRuntimeConfiguredRow]) -> String {
        rows.map { row in
            switch row.pick {
            case .resolved(let java, _):
                return "\(row.majorVersion)=\(java.path)"
            case .environmentInvalid(_, let p):
                return "\(row.majorVersion)=inv:\(p)"
            case .notFound:
                return "\(row.majorVersion)=none"
            }
        }.joined(separator: "|")
    }

    var body: some View {
        let jre8Missing = !JavaRuntimeResolver.isJava8RuntimePresent()
        ScrollView {
            Form {
                JavaRuntimeSettingsOverviewFormSections(rows: configuredRows, fsclMirror: fsclMirror, javaVersionFirstLines: $javaVersionFirstLines)

                Section {
                    Text(
                        "Java 8 mit Bildschirm-Oberflächen (JavaFX) kann bei Bedarf automatisch bezogen werden und landet in den Launcher-Daten. Eigene Quellen haben Vorrang vor dem mitgelieferten Angebot. Änderungen speichern Sie mit „Speichern“ oder ⌘S."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                if jre8Missing {
                    Section {
                        if canAttemptJava8Download() {
                            Text(
                                "Für Java 8 ist noch nichts installiert. Wählen Sie unten bei einer Quelle „Herunterladen …“. Starten Sie den Launcher nach Änderungen am Computer am besten neu (Menüsymbol: Beenden, dann erneut öffnen)."
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(
                                "Für Java 8 ist keine aktive Bezugsquelle eingetragen. Schalten Sie die mitgelieferte Quelle ein oder fügen Sie eine eigene hinzu (Prüfsumme nicht leer lassen)."
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    } header: {
                        Text("Hinweis")
                    }
                }
                if let built = Java8RuntimeCatalogLoader.builtinEntryForCurrentHost() {
                    Section {
                        Java8BuiltinSourceRow(
                            built: built,
                            isActive: builtinActiveBinding(catalogId: built.id, catalogDefault: built.defaultActive),
                            java8Missing: jre8Missing,
                            java8Prefs: prefs,
                            jre8DownloadBusy: $jre8DownloadBusy
                        )
                    } header: {
                        Text("Mitgelieferte Quelle (\(Java8RuntimeCatalogLoader.hostArchitectureString()))")
                    } footer: {
                        Text("Diese Angaben kommen aus dem mitgelieferten Katalog und lassen sich hier nicht bearbeiten.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Text("Der mitgelieferte Katalog „Java8RuntimeCatalog.json“ konnte nicht geladen werden.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    if prefs.CustomEntries.isEmpty {
                        Text("Keine eigenen Quellen — nur der mitgelieferte Katalog (falls aktiv) wird verwendet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach($prefs.CustomEntries) { $entry in
                        Java8CustomSourceListRow(
                            entry: $entry,
                            java8Missing: jre8Missing,
                            java8Prefs: prefs,
                            jre8DownloadBusy: $jre8DownloadBusy,
                            onEdit: {
                                editingCustomEntryId = entry.Id
                                showCustomEntrySheet = true
                            }
                        )
                    }
                    Button("Eigenen Eintrag hinzufügen …") {
                        let draft = Java8RuntimeCustomEntry.newDraft()
                        prefs.CustomEntries.append(draft)
                        editingCustomEntryId = draft.Id
                        showCustomEntrySheet = true
                    }
                } header: {
                    Text("Eigene Quellen")
                } footer: {
                    Text("„Bearbeiten …“ öffnet ein separates Fenster. Adresse zur Archivdatei (https), passende Mac-Art und optional Prüfsummen — siehe README für Details.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .onAppear {
            refreshConfiguredRows()
        }
        .onChange(of: prefs) { _ in
            refreshConfiguredRows()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tradeERPLauncherJavaRuntimesChanged)) { _ in
            refreshConfiguredRows()
        }
        .task(id: rowsSignature(configuredRows)) {
            var next: [Int: String] = [:]
            await Task.yield()
            for row in configuredRows {
                switch row.pick {
                case .resolved(let java, _):
                    let line = await Task.detached { JavaRuntimeVersionQuery.firstLine(javaExecutable: java) }.value
                    next[row.majorVersion] = line ?? "—"
                case .environmentInvalid, .notFound:
                    next[row.majorVersion] = "—"
                }
            }
            await MainActor.run {
                javaVersionFirstLines = next
            }
        }
        .sheet(isPresented: $showCustomEntrySheet) {
            NavigationStack {
                Group {
                    if let id = editingCustomEntryId, prefs.CustomEntries.contains(where: { $0.Id == id }) {
                        Java8CustomEntryEditor(
                            entry: bindingForEntry(id: id),
                            onDelete: {
                                deleteEntry(id: id)
                                showCustomEntrySheet = false
                            }
                        )
                        .padding()
                    } else {
                        Text("Eintrag nicht gefunden.")
                            .padding()
                    }
                }
                .frame(minWidth: 480, minHeight: 360)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Schließen") {
                            showCustomEntrySheet = false
                        }
                    }
                }
            }
        }
    }

    private func builtinActiveBinding(catalogId: String, catalogDefault: Bool) -> Binding<Bool> {
        Binding(
            get: { prefs.effectiveBuiltInActive(catalogEntryId: catalogId, catalogDefault: catalogDefault) },
            set: { newVal in
                var m = prefs.BuiltInActiveById ?? [:]
                m[catalogId] = newVal
                prefs.BuiltInActiveById = m
            }
        )
    }

    private func bindingForEntry(id: String) -> Binding<Java8RuntimeCustomEntry> {
        Binding(
            get: {
                prefs.CustomEntries.first(where: { $0.Id == id })!
            },
            set: { newVal in
                guard let i = prefs.CustomEntries.firstIndex(where: { $0.Id == id }) else { return }
                prefs.CustomEntries[i] = newVal
            }
        )
    }

    private func deleteEntry(id: String) {
        prefs.CustomEntries.removeAll { $0.Id == id }
    }
}

/// Kompakte Zeile in der Quellen-Liste (HIG: Liste + separates Bearbeitungsfenster statt vieler gleichzeitiger Formulare).
private struct Java8CustomSourceListRow: View {
    @Binding var entry: Java8RuntimeCustomEntry
    let java8Missing: Bool
    let java8Prefs: Java8RuntimePreferences
    @Binding var jre8DownloadBusy: Bool
    let onEdit: () -> Void

    private var singleDownloadSource: Java8RuntimeResolvedSource? {
        guard let hw = MacHardwareArchitecture.current() else { return nil }
        return Java8RuntimeDownloadResolver.resolveSingleCustom(entry: entry, hardware: hw)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.Label.isEmpty ? "(ohne Bezeichnung)" : entry.Label)
                    .font(.body.weight(.medium))
                Text(entry.DownloadUrl)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(entry.Architecture)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            if java8Missing, let src = singleDownloadSource {
                Button("Herunterladen …") {
                    Task { @MainActor in
                        jre8DownloadBusy = true
                        defer { jre8DownloadBusy = false }
                        await Jre8FirstLaunchOffer.runDownloadFromResolvedSourceWithConfirmation(
                            source: src,
                            java8RuntimePreferences: java8Prefs
                        )
                    }
                }
                .disabled(jre8DownloadBusy)
            }
            Toggle("Aktiv", isOn: $entry.Active)
                .labelsHidden()
                .help("Quelle für passende Architektur ein- oder ausschalten")
            Button("Bearbeiten …") {
                onEdit()
            }
        }
        .padding(.vertical, 4)
    }
}

private struct Java8BuiltinSourceRow: View {
    let built: Java8BuiltinCatalogEntry
    let isActive: Binding<Bool>
    let java8Missing: Bool
    let java8Prefs: Java8RuntimePreferences
    @Binding var jre8DownloadBusy: Bool

    private var builtinDownloadSource: Java8RuntimeResolvedSource? {
        guard let hw = MacHardwareArchitecture.current() else { return nil }
        return Java8RuntimeDownloadResolver.resolveBuiltinOnly(java8Preferences: java8Prefs, hardware: hw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(built.label)
                    .font(.body.weight(.medium))
                Spacer()
                if java8Missing, let src = builtinDownloadSource {
                    Button("Herunterladen …") {
                        Task { @MainActor in
                            jre8DownloadBusy = true
                            defer { jre8DownloadBusy = false }
                            await Jre8FirstLaunchOffer.runDownloadFromResolvedSourceWithConfirmation(
                                source: src,
                                java8RuntimePreferences: java8Prefs
                            )
                        }
                    }
                    .disabled(jre8DownloadBusy)
                }
                Toggle("Aktiv", isOn: isActive)
            }
            LabeledContent("Architektur") {
                Text(built.architecture)
            }
            LabeledContent("URL") {
                Text(built.downloadUrl)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            LabeledContent("Prüfsumme") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(built.hashType.displayName)
                    Text(built.expectedHash)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct Java8CustomEntryEditor: View {
    @Binding var entry: Java8RuntimeCustomEntry
    let onDelete: () -> Void

    var body: some View {
        Form {
            Section {
                TextField("Kurzbezeichnung", text: $entry.Label)
                Toggle("Aktiv", isOn: $entry.Active)
                Picker("Architektur", selection: $entry.Architecture) {
                    Text("Apple Silicon (arm64)").tag("arm64")
                    Text("Intel (x86_64)").tag("x86_64")
                }
                TextField("Download-URL (https … .tar.gz)", text: $entry.DownloadUrl)
                    .font(.system(.body, design: .monospaced))
                Picker("Hash-Typ", selection: $entry.HashType) {
                    ForEach(Java8RuntimeHashType.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                if entry.HashType != .none {
                    TextField("Erwarteter Hash (Hex)", text: $entry.ExpectedHash)
                        .font(.system(.body, design: .monospaced))
                }
            }
            Section {
                Button("Eintrag entfernen", role: .destructive, action: onDelete)
            }
        }
        .formStyle(.grouped)
    }
}
