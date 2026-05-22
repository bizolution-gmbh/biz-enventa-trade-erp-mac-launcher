import AppKit
import SwiftUI

/// Hauptfenster der Einstellungen — Tab-View, gemeinsamer „Speichern“-Knopf, lädt `LauncherSettings` einmal pro Anzeige.
struct ConfigRootView: View {
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
            BizolutionLogoHeader()
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
                AboutSettingsView()
                    .tabItem {
                        Label("Über", systemImage: "info.circle")
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
            "Eine Zeile pro JVM-Argument (z. B. -D…). Änderungen mit „Speichern“ oder ⌘S übernehmen."
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
