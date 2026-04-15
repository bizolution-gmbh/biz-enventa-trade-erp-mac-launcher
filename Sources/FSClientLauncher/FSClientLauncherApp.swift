import AppKit
import Darwin
import SwiftUI

@main
struct FSClientLauncherEntry {
    static func main() {
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
    static weak var shared: AppDelegate?

    private var configWindow: NSWindow?
    /// Verhindert, dass die Konfiguration öffnet, bevor z. B. `application(_:openFile:)` nach einem Doppelklick auf `.fsclient` gelaufen ist.
    private var didStartLaunchFlow = false
    /// Verhindert parallele Doppelstarts desselben Pfads (Finder: `argv` + `openFile`/`openURLs`).
    private var inFlightLaunchKeys: Set<String> = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        Self.shared = self
        AppPaths.migrateLegacyDirectoriesIfNeeded()
        FsClientShortcutsStore.shared.bootstrapTrayPersistenceAtLaunch()
        MenuBarExtraController.shared.installIfNeeded()
        // Kein eigenes `applicationIconImage`: Dock nutzt das Bundle-Icon; Identifikation über Menüleiste (Tray).
        NSApp.applicationIconImage = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menüleisten-App: Prozess bleibt aktiv; Beenden nur über „FS Client Launcher beenden“ im Tray.
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
            let raw = url.isFileURL ? url.path : url.absoluteString
            Task { await self.runLaunchArgument(raw) }
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        didStartLaunchFlow = true
        Task { await runLaunchArgument(filename) }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    guard let self else { return }
                    if !self.didStartLaunchFlow {
                        self.didStartLaunchFlow = true
                        Task { await self.runLaunchArgument(first) }
                    }
                }
            } else {
                didStartLaunchFlow = true
                Task { await runLaunchArgument(first) }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self else { return }
                if !self.didStartLaunchFlow {
                    self.showConfigWindow()
                }
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let win = notification.object as? NSWindow, win === configWindow else { return }
        configWindow = nil
    }

    func showConfigWindowFromMenuBar() {
        showConfigWindow()
    }

    func launchFsClientFromMenuBar(path: String) {
        didStartLaunchFlow = true
        Task { await runLaunchArgument(path) }
    }

    private func showConfigWindow() {
        if let w = configWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = NSHostingController(
            rootView: ConfigRootView().environmentObject(FsClientShortcutsStore.shared)
        )
        let win = NSWindow(contentViewController: root)
        win.setContentSize(NSSize(width: 620, height: 640))
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.title = "FS Client Launcher"
        win.center()
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        configWindow = win
    }

    /// Nur echte `.fsclient`-Pfade (kein `fsclientlauncher:`-URI).
    static func normalizedFsClientPathIfAny(from raw: String) -> String? {
        if raw.lowercased().hasPrefix("fsclientlauncher:") { return nil }
        let path: String
        if raw.hasPrefix("file:"), let u = URL(string: raw) {
            path = u.path
        } else {
            path = raw
        }
        let std = (path as NSString).standardizingPath
        guard std.lowercased().hasSuffix(".fsclient") else { return nil }
        return std
    }

    private func handleSuccessfulClientLaunch(settings: LauncherSettings, sourceRaw: String) {
        let store = FsClientShortcutsStore.shared
        if let path = Self.normalizedFsClientPathIfAny(from: sourceRaw) {
            let def = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            store.upsertAfterLaunch(filePath: path, defaultDisplayName: def)
        }
        MenuBarExtraController.shared.installIfNeeded()
    }

    /// Nach Fehler/Abbruch: Tray sichtbar halten, kein automatisches Beenden (Nutzer: „… beenden“).
    private func ensureTrayAfterLaunchFailure() {
        MenuBarExtraController.shared.installIfNeeded()
    }

    private func runLaunchArgument(_ raw: String) async {
        let dedupeKey = Self.normalizedFsClientPathIfAny(from: raw)?.lowercased() ?? raw.lowercased()
        if inFlightLaunchKeys.contains(dedupeKey) { return }
        inFlightLaunchKeys.insert(dedupeKey)
        defer { inFlightLaunchKeys.remove(dedupeKey) }
        do {
            let launch = try LaunchConfiguration.parse(firstArgument: raw)
            let settings = LauncherSettings.load()
            if settings.DisplayConsole {
                await MainActor.run {
                    JavaProcessOutputWindow.shared.present()
                }
            }
            try await LaunchCoordinator.run(
                launch: launch,
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
                        alert.messageText = "FS Client Launcher aktualisieren?"
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
                handleSuccessfulClientLaunch(settings: settings, sourceRaw: raw)
            }
        } catch is CancellationError {
            await MainActor.run { ensureTrayAfterLaunchFailure() }
        } catch {
            await MainActor.run {
                let settings = LauncherSettings.load()
                if settings.DisplayConsole {
                    JavaProcessOutputWindow.shared.present()
                    JavaProcessOutputWindow.shared.append("\n—— Fehler: \(error.localizedDescription) ——\n")
                }
                let alert = NSAlert()
                alert.messageText = "FS Client Launcher"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.runModal()
                ensureTrayAfterLaunchFailure()
            }
        }
    }
}

private struct ConfigRootView: View {
    @EnvironmentObject private var shortcutsStore: FsClientShortcutsStore
    @State private var settings = LauncherSettings.load()
    @State private var javaVmJoined = ""
    @State private var java8Joined = ""
    @State private var java11Joined = ""
    @State private var java21Joined = ""

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
                FsClientShortcutsSettingsView(store: shortcutsStore)
                    .tabItem {
                        Label("FS-Client-Dateien", systemImage: "doc.text")
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
        }
        .onAppear {
            shortcutsStore.loadFromDisk()
            reloadSettingsState()
        }
    }

    private func reloadSettingsState() {
        settings = LauncherSettings.load()
        javaVmJoined = settings.JavaVmArguments.joined(separator: "\n")
        java8Joined = settings.Java8VmArguments.joined(separator: "\n")
        java11Joined = settings.Java11VmArguments.joined(separator: "\n")
        java21Joined = settings.Java21VmArguments.joined(separator: "\n")
    }

    private func persistSettings() {
        settings.JavaVmArguments = splitLines(javaVmJoined)
        settings.Java8VmArguments = splitLines(java8Joined)
        settings.Java11VmArguments = splitLines(java11Joined)
        settings.Java21VmArguments = splitLines(java21Joined)
        settings.save()
    }

    @ViewBuilder
    private var generalTab: some View {
        Form {
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
                LabeledContent("Menüleiste / FS-Client-Liste") {
                    Text(AppPaths.fsClientShortcutsURL.path).textSelection(.enabled)
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
                Text(
                    "Eine Zeile pro JVM-Argument (z. B. -D…). Änderungen mit „Speichern“ oder ⌘S übernehmen."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Section("Zusätzliche JVM-Argumente (alle Versionen, je Zeile)") {
                TextEditor(text: $javaVmJoined)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 72)
            }
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
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        "Ist die Java-8-Liste leer, trägt der Launcher macOS-Swing-Standards ein (Menüleiste oben, Anwendungsname, Titelleisten-Erscheinungsbild, Aqua-LAF)."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    Link(
                        "FlatLaf – Hinweise für macOS",
                        destination: URL(string: "https://www.formdev.com/flatlaf/macos/")!
                    )
                    .font(.footnote)
                }
            }
            Section("Java 11") {
                TextEditor(text: $java11Joined)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 56)
            }
            Section("Java 21") {
                TextEditor(text: $java21Joined)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 56)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func splitLines(_ s: String) -> [String] {
        s.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
