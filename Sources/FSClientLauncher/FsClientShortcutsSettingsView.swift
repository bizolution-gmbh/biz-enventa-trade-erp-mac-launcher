import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Reiter „FS-Client-Dateien“: kompakte scrollbare Liste, Kacheln mit gebündeltem `Icon.png` (nicht das Launcher-`AppIcon`), Doppelklick bearbeitet Titel + Pfad.
struct FsClientShortcutsSettingsView: View {
    @ObservedObject var store: FsClientShortcutsStore

    /// `sheet(item:)` braucht ein stabiles Identifiable; der Eintrag selbst kann sich während des Editierens ändern.
    private struct EditingShortcut: Identifiable {
        let id: UUID
    }

    @State private var editing: EditingShortcut?

    private var gridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 148, maximum: 280), spacing: 10, alignment: .top),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    "Einträge erscheinen hier und im Tray unter „FS-Client-Dateien“. Doppelklick auf eine Kachel bearbeitet Titel und Pfad."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Divider()

                Text("Gespeicherte Dateien")
                    .font(.headline)

                if store.file.shortcuts.isEmpty {
                    Text("Noch keine Einträge.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(store.file.shortcuts) { rec in
                            shortcutTile(rec)
                        }
                    }
                }

                Button("Datei hinzufügen …") {
                    presentAddPanel()
                }

                Text("„Datei hinzufügen …“ wählt eine .fsclient-Datei; bekannte Pfade werden aktualisiert.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(height: 300)
        .frame(maxWidth: .infinity)
        .sheet(item: $editing) { box in
            FsClientShortcutEditSheet(store: store, recordId: box.id)
        }
    }

    @ViewBuilder
    private func shortcutTile(_ rec: FsClientShortcutRecord) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if let ns = LauncherBrandingImages.shortcutsTileIcon() {
                        Image(nsImage: ns)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    } else {
                        Image(systemName: "app.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(width: 40, height: 40)
                    }
                }
                Text(rec.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Ohne Titel" : rec.displayName)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(rec.displayName)
                Text(rec.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .help(rec.path)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.background)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.separator.opacity(0.65), lineWidth: 1)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                editing = EditingShortcut(id: rec.id)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Doppeltippen zum Bearbeiten")

            Button {
                store.deleteRecord(id: rec.id)
            } label: {
                Image(systemName: "trash")
                    .font(.body)
                    .foregroundStyle(.red)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Eintrag löschen")
            .accessibilityLabel("Löschen")
        }
    }

    private func presentAddPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let ut = UTType(filenameExtension: "fsclient") {
            panel.allowedContentTypes = [ut]
        }
        panel.message = ".fsclient-Datei auswählen"
        let parent = NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible }
        let finishNameEntry: (String, String) -> Void = { path, suggested in
            let alert = NSAlert()
            alert.messageText = "Anzeigename"
            alert.informativeText = "Name in der Menüleiste und in der Liste:"
            let field = NSTextField(string: suggested)
            field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
            alert.accessoryView = field
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Abbrechen")
            if alert.runModal() == .alertFirstButtonReturn {
                let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalName = name.isEmpty ? suggested : name
                store.addRecord(path: path, displayName: finalName)
            }
        }
        if let win = parent {
            panel.beginSheetModal(for: win) { resp in
                if resp == .OK, let url = panel.url {
                    let path = url.path
                    let sug = url.deletingPathExtension().lastPathComponent
                    finishNameEntry(path, sug)
                }
            }
        } else {
            if panel.runModal() == .OK, let url = panel.url {
                let path = url.path
                let sug = url.deletingPathExtension().lastPathComponent
                finishNameEntry(path, sug)
            }
        }
    }
}

// MARK: - Bearbeiten (Doppelklick)

private struct FsClientShortcutEditSheet: View {
    @ObservedObject var store: FsClientShortcutsStore
    let recordId: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var titleText = ""
    @State private var pathText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Eintrag bearbeiten")
                .font(.headline)

            TextField("Titel", text: $titleText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text(".fsclient-Datei")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(alignment: .center, spacing: 8) {
                    TextField("Pfad zur .fsclient-Datei", text: $pathText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .default))
                    Button {
                        pickFsClientFile()
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.body.weight(.medium))
                            .frame(minWidth: 28, minHeight: 26)
                    }
                    .buttonStyle(.bordered)
                    .help("Datei auswählen …")
                    .accessibilityLabel("Datei auswählen")
                }
            }

            HStack {
                Spacer()
                Button("Abbrechen") {
                    dismiss()
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
            syncFromStore()
        }
    }

    private var canSave: Bool {
        let p = pathText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return false }
        return p.lowercased().hasSuffix(".fsclient")
    }

    private func syncFromStore() {
        guard let r = store.file.shortcuts.first(where: { $0.id == recordId }) else { return }
        titleText = r.displayName
        pathText = r.path
    }

    private func save() {
        let name = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = pathText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, path.lowercased().hasSuffix(".fsclient") else { return }
        let std = (path as NSString).standardizingPath
        let finalName = name.isEmpty ? URL(fileURLWithPath: std).deletingPathExtension().lastPathComponent : name
        store.updateRecord(id: recordId, displayName: finalName, path: std)
        dismiss()
    }

    private func pickFsClientFile() {
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
