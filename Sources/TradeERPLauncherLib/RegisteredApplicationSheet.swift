import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum RegisteredApplicationSheetState: Identifiable {
    case add
    case edit(UUID)
    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let u): return u.uuidString
        }
    }
}

/// Gemeinsame Maske „Anwendung hinzufügen“ / „Anwendung bearbeiten“ (Einstellungen-Reiter oder Tray-Fenster).
struct RegisteredApplicationSheet: View {
    @ObservedObject var store: RegisteredApplicationsStore
    let sheetState: RegisteredApplicationSheetState
    /// Wenn gesetzt (Tray-Fenster): nach OK/Abbrechen schließen; bei `nil` nur SwiftUI-`dismiss` (Sheet in Einstellungen).
    let onComplete: (() -> Void)?

    init(
        store: RegisteredApplicationsStore,
        sheetState: RegisteredApplicationSheetState,
        onComplete: (() -> Void)? = nil
    ) {
        self.store = store
        self.sheetState = sheetState
        self.onComplete = onComplete
    }

    @Environment(\.dismiss) private var dismiss

    @State private var titleText = ""
    @State private var pathText = ""

    /// Damit nach „Nein“ nicht erneut gefragt wird, bis der Text geändert wird.
    @State private var declinedMacLauncherBridgeForPath: String?

    private var isAddMode: Bool {
        if case .add = sheetState { return true }
        return false
    }

    private var sheetTitle: String {
        switch sheetState {
        case .add: return "Anwendung hinzufügen"
        case .edit: return "Anwendung bearbeiten"
        }
    }

    private var recordId: UUID? {
        if case .edit(let id) = sheetState { return id }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(sheetTitle)
                .font(.headline)

            TextField("Titel", text: $titleText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text("Adresse oder Datei")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(alignment: .center, spacing: 8) {
                    TextField("http…-Adresse einfügen oder Datei wählen", text: $pathText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .default))
                    Button {
                        pickLauncherDefinitionFile()
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.body.weight(.medium))
                            .frame(minWidth: 28, minHeight: 26)
                    }
                    .buttonStyle(.bordered)
                    .help("Datei wählen")
                    .accessibilityLabel("Datei wählen")
                }
                if pathValidationShowsHint {
                    Text("Bitte eine Web-Adresse mit http… oder eine .fsclient-Datei angeben.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Abbrechen") {
                    closeAfterUserAction()
                }
                .keyboardShortcut(.cancelAction)
                Button("OK") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(22)
        .frame(minWidth: 440)
        .onAppear {
            declinedMacLauncherBridgeForPath = nil
            if isAddMode {
                titleText = ""
                pathText = ""
            } else if let id = recordId,
                      let r = store.file.shortcuts.first(where: { $0.id == id }) {
                titleText = r.displayName
                pathText = r.path
            }
        }
        .onChange(of: pathText) { _ in
            declinedMacLauncherBridgeForPath = nil
        }
    }

    private var canSave: Bool {
        RegisteredApplicationsStore.isValidShortcutTarget(pathText)
    }

    /// Eingabe vorhanden, aber noch nicht gültig — kurzer Hinweis statt nur ausgegrautem OK.
    private var pathValidationShowsHint: Bool {
        let t = pathText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && !RegisteredApplicationsStore.isValidShortcutTarget(pathText)
    }

    private func closeAfterUserAction() {
        onComplete?()
        dismiss()
    }

    private func save() {
        let userTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawPath = pathText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RegisteredApplicationsStore.isValidShortcutTarget(rawPath) else { return }

        var path = rawPath
        if rawPath != declinedMacLauncherBridgeForPath,
           LaunchConfiguration.shouldOfferLauncherBridge(forHttpShortcut: rawPath),
           let built = LaunchConfiguration.launcherLaunchURLFromWebDefinitionHTTP(rawPath) {
            let alert = NSAlert()
            alert.messageText = "Adresse für den Mac umwandeln?"
            alert.informativeText =
                "Diese Web-Adresse funktioniert auf dem Mac zuverlässiger, wenn sie umgewandelt wird. Soll das automatisch geschehen?"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Ja")
            alert.addButton(withTitle: "Nein")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                pathText = built
                path = built.trimmingCharacters(in: .whitespacesAndNewlines)
                declinedMacLauncherBridgeForPath = nil
            } else {
                declinedMacLauncherBridgeForPath = rawPath
                path = rawPath
            }
        }

        guard RegisteredApplicationsStore.isValidShortcutTarget(path) else { return }
        let norm = RegisteredApplicationsStore.normalizeShortcutTarget(path)
        let backing = recordId.flatMap { id in store.file.shortcuts.first { $0.id == id }?.importedFilePath }
        let fromFile = RegisteredApplicationsStore.readDefinitionTitleIfPresent(fromShortcutTarget: path, backingFile: backing)
        let defaultFromPath: String
        if norm.lowercased().hasPrefix("http://") || norm.lowercased().hasPrefix("https://") {
            defaultFromPath = URL(string: norm)?.host ?? "FS Client"
        } else {
            defaultFromPath = URL(fileURLWithPath: norm).deletingPathExtension().lastPathComponent
        }
        let finalName: String
        if !userTitle.isEmpty {
            finalName = userTitle
        } else if let f = fromFile, !f.isEmpty {
            finalName = f
        } else {
            finalName = defaultFromPath
        }

        if isAddMode {
            if store.addRecord(path: norm, displayName: finalName) {
                closeAfterUserAction()
            } else {
                let alert = NSAlert()
                alert.messageText = "Schon vorhanden"
                alert.informativeText = "Diese Adresse oder Datei ist bereits eingetragen."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        } else if let id = recordId {
            store.updateRecord(id: id, displayName: finalName, path: norm)
            closeAfterUserAction()
        }
    }

    private func pickLauncherDefinitionFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let ut = UTType(filenameExtension: "fsclient") {
            panel.allowedContentTypes = [ut]
        }
        panel.message = ".fsclient-Datei auswählen"
        let parent = NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible }
        let apply: (URL) -> Void = { url in
            pathText = url.path
        }
        if let win = parent {
            panel.beginSheetModal(for: win) { resp in
                if resp == .OK, let url = panel.url {
                    apply(url)
                }
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            apply(url)
        }
    }
}
