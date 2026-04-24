import SwiftUI

/// Reiter „Anwendungen“: gleiche `Form`-Struktur wie die anderen Einstellungen-Reiter.
struct RegisteredApplicationsSettingsView: View {
    @ObservedObject var store: RegisteredApplicationsStore

    @State private var sheet: RegisteredApplicationSheetState?

    /// Gleich breite Spalten — Kacheln füllen jeweils eine Zelle (`maxWidth: .infinity`).
    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 120), spacing: 10),
            GridItem(.flexible(minimum: 120), spacing: 10),
            GridItem(.flexible(minimum: 120), spacing: 10),
        ]
    }

    /// Feste Kachelhöhe: Titel (max. 2 Zeilen) + URL-Zeile + Icon — alle Kacheln gleich groß.
    private static let shortcutTileHeight: CGFloat = 134

    var body: some View {
        Form {
            Section {
                Text("Einträge erscheinen hier und im Menü oben. Zum Bearbeiten doppelt auf eine Kachel tippen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Registrierte Anwendungen") {
                if store.file.shortcuts.isEmpty {
                    Text("Noch keine Einträge.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(store.file.shortcuts) { rec in
                                shortcutTile(rec)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(minHeight: 200, maxHeight: 320)
                }

                Button("Anwendung hinzufügen") {
                    sheet = .add
                }
            }

            Section {
                Text(
                    "Neue Einträge: Typ „Client-Anwendung“ für Broker- oder Definitions-URLs bzw. .fsclient-Datei — „Weblink“ für eine beliebige http(s)-Adresse, die unverändert im Standardbrowser geöffnet wird. Der Titel kann frei vergeben werden."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(item: $sheet) { item in
            RegisteredApplicationSheet(store: store, sheetState: item)
        }
    }

    @ViewBuilder
    private func shortcutTile(_ rec: RegisteredApplicationRecord) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if rec.targetKind == .webBookmark {
                        Image(systemName: "globe")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                            .frame(width: 40, height: 40)
                            .accessibilityLabel("Weblink")
                    } else if let h = rec.iconContentHash,
                              let ns = RegisteredApplicationIconCache.nsImage(contentHashHex: h, pixelSide: 40) {
                        Image(nsImage: ns)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    } else if let ns = LauncherBrandingImages.shortcutsTileIcon() {
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
                    .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44, alignment: .topLeading)
                    .help(rec.displayName)
                Text(rec.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14, alignment: .leading)
                    .textSelection(.enabled)
                    .help(rec.path)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: Self.shortcutTileHeight, maxHeight: Self.shortcutTileHeight, alignment: .topLeading)
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
                sheet = .edit(rec.id)
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
        .frame(maxWidth: .infinity)
    }
}
