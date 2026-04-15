import AppKit
import Darwin
import SwiftUI

@main
struct FSClientLauncherEntry {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var configWindow: NSWindow?
    /// Verhindert, dass die Konfiguration öffnet, bevor z. B. `application(_:openFile:)` nach einem Doppelklick auf `.fsclient` gelaufen ist.
    private var didStartLaunchFlow = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // So früh wie möglich: Dock liest `applicationIconImage` oft vor `applicationDidFinishLaunching`.
        applyBundleApplicationIcon()
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
        AppPaths.migrateLegacyDirectoriesIfNeeded()
        let args = CommandLine.arguments.dropFirst().filter { arg in
            if arg.hasPrefix("-psn_") { return false }
            if arg == "-NSDocumentRevisionsDebugMode" { return false }
            return true
        }
        if let first = args.first {
            didStartLaunchFlow = true
            Task { await runLaunchArgument(first) }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self else { return }
                if !self.didStartLaunchFlow {
                    self.showConfigWindow()
                }
            }
        }
    }

    /// Dock-Symbol aus `AppIcon.icns` (Finder nutzt Bundle-Metadaten; der Dock braucht oft explizit `applicationIconImage`).
    private func applyBundleApplicationIcon() {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              FileManager.default.isReadableFile(atPath: url.path)
        else { return }
        // `contentsOfFile:` kann bei manchen .icns leer ausfallen; `contentsOf:` + explizit kein Template.
        guard let image = NSImage(contentsOf: url), !image.representations.isEmpty else { return }
        image.isTemplate = false
        NSApp.applicationIconImage = image
    }

    private func showConfigWindow() {
        let root = NSHostingController(rootView: ConfigRootView())
        let win = NSWindow(contentViewController: root)
        win.setContentSize(NSSize(width: 540, height: 620))
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.title = "FS Client Launcher"
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        configWindow = win
    }

    private func runLaunchArgument(_ raw: String) async {
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
                if !settings.DisplayConsole {
                    NSApp.terminate(nil)
                }
            }
        } catch is CancellationError {
            await MainActor.run { NSApp.terminate(nil) }
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
                NSApp.terminate(nil)
            }
        }
    }
}

private struct ConfigRootView: View {
    @State private var settings = LauncherSettings.load()
    @State private var javaVmJoined = ""
    @State private var java8Joined = ""
    @State private var java11Joined = ""
    @State private var java21Joined = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EnventaLogoHeader()
                .padding(.top, 8)
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
            Section("Zusätzliche JVM-Argumente (alle Versionen, je Zeile)") {
                TextEditor(text: $javaVmJoined)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 64)
            }
            Section("Java 8") {
                TextEditor(text: $java8Joined)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 48)
            }
            Section("Java 11") {
                TextEditor(text: $java11Joined)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 48)
            }
            Section("Java 21") {
                TextEditor(text: $java21Joined)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 48)
            }
            Section("Pfade") {
                LabeledContent("JAR-Cache") {
                    Text(AppPaths.jarCacheDirectory.path).textSelection(.enabled)
                }
                LabeledContent("Konfiguration") {
                    Text(AppPaths.launcherConfigURL.path).textSelection(.enabled)
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
            Section {
                Button("Speichern") {
                    settings.JavaVmArguments = splitLines(javaVmJoined)
                    settings.Java8VmArguments = splitLines(java8Joined)
                    settings.Java11VmArguments = splitLines(java11Joined)
                    settings.Java21VmArguments = splitLines(java21Joined)
                    settings.save()
                }
            }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            settings = LauncherSettings.load()
            javaVmJoined = settings.JavaVmArguments.joined(separator: "\n")
            java8Joined = settings.Java8VmArguments.joined(separator: "\n")
            java11Joined = settings.Java11VmArguments.joined(separator: "\n")
            java21Joined = settings.Java21VmArguments.joined(separator: "\n")
        }
    }

    private func splitLines(_ s: String) -> [String] {
        s.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
