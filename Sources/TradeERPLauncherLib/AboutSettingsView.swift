import AppKit
import SwiftUI

/// Aus `Bundle.main` / `Info.plist` für „Über“ und Support.
enum LauncherBundleMetadata {
    /// Reine Marketing-Version (rein numerisch, für Broker-Versionsvergleiche, vgl. `VersionPolicy.Semantic.parse`).
    static var marketingVersion: String {
        nonEmpty(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
    }

    /// Optionales Vorab-Kennzeichen aus `Info.plist` (Custom-Key `BizolutionPreReleaseTag`),
    /// gesetzt zwischen Releases (`dev`, `beta`, …) und im Release-Commit auf leer zurückgesetzt.
    static var preReleaseTag: String? {
        nonEmpty(Bundle.main.object(forInfoDictionaryKey: "BizolutionPreReleaseTag") as? String)
    }

    /// Anzeigeform für „Über“-Tab und Konsole: numerische Version, ergänzt um `-tag`, falls gesetzt.
    /// Bewusst getrennt von `marketingVersion`, damit `CFBundleShortVersionString` rein numerisch bleibt
    /// und Apple-Konventionen sowie `VersionPolicy.Semantic.parse` weiter erfüllt sind.
    static var displayVersion: String {
        formatDisplayVersion(shortVersion: marketingVersion, preReleaseTag: preReleaseTag)
    }

    /// Reine Logik (testbar) — vereint Version und Vorab-Tag in der Anzeigeform.
    static func formatDisplayVersion(shortVersion: String, preReleaseTag: String?) -> String {
        guard let tag = preReleaseTag?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty else {
            return shortVersion
        }
        return "\(shortVersion)-\(tag)"
    }

    static var buildVersion: String {
        nonEmpty(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "—"
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "—"
    }

    static var humanReadableCopyright: String {
        nonEmpty(Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String) ?? "© 2026 BIZOLUTION GmbH"
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}

/// Tab „Über“: Version, Build, Anbieter, Kurzdisclaimer (ergänzt System-„Über“-Dialog aus dem Tray).
struct AboutSettingsView: View {
    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.title2)
                        .accessibilityHidden(true)
                    Text(LauncherProductNaming.distributionDisclaimer)
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
                .accessibilityLabel("Hinweis: \(LauncherProductNaming.distributionDisclaimer)")
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))

            Section {
                LabeledContent("Version") {
                    Text(LauncherBundleMetadata.displayVersion)
                        .textSelection(.enabled)
                }
                LabeledContent("Build") {
                    Text(LauncherBundleMetadata.buildVersion)
                        .textSelection(.enabled)
                }
                LabeledContent("Bundle-Kennung") {
                    Text(LauncherBundleMetadata.bundleIdentifier)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            } header: {
                Text(LauncherProductNaming.displayName)
            }

            Section("Anbieter") {
                Text("BIZOLUTION GmbH")
                    .font(.body.weight(.semibold))
                Text(LauncherBundleMetadata.humanReadableCopyright)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

enum LauncherAboutPanel {
    /// System-„Über“-Dialog. Ohne Optionen liest macOS `CFBundleShortVersionString` (rein numerisch);
    /// damit der Vorab-Tag (z. B. `-dev`) auch hier sichtbar ist, wird `applicationVersion` mit
    /// `LauncherBundleMetadata.displayVersion` überschrieben — Build (`(3)`) bleibt unverändert.
    @MainActor
    static func present() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: standardPanelOptions(displayVersion: LauncherBundleMetadata.displayVersion))
    }

    /// Reine Logik (testbar) — baut die Optionen für `orderFrontStandardAboutPanel(options:)`.
    static func standardPanelOptions(displayVersion: String) -> [NSApplication.AboutPanelOptionKey: Any] {
        let trimmed = displayVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "—" else { return [:] }
        return [.applicationVersion: trimmed]
    }
}
