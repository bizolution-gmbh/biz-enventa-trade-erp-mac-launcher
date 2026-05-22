import AppKit
import SwiftUI

// MARK: - Java-Laufzeitumgebungen (Übersicht + Download-Quellen)

/// Zwei Tabellen in `Form`-Abschnitten: zuerst übernommene Pfade, dann erkannte Installationen
/// (HIG: klare Abschnitte, kurze Begleittexte).
struct JavaRuntimeSettingsOverviewFormSections: View {
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

struct JavaRuntimePathTableCell: View {
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

struct Java8RuntimesSettingsView: View {
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
struct Java8CustomSourceListRow: View {
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
                HStack(spacing: 6) {
                    Text(entry.Label.isEmpty ? "(ohne Bezeichnung)" : entry.Label)
                        .font(.body.weight(.medium))
                    if entry.HashType == .none {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help("Ohne Prüfsumme keine Integritätsprüfung — empfohlen nur in geschützten Netzen.")
                            .accessibilityLabel("Ohne Prüfsumme")
                    }
                }
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

struct Java8BuiltinSourceRow: View {
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

struct Java8CustomEntryEditor: View {
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
            if entry.HashType == .none {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text("Ohne Prüfsumme wird die heruntergeladene Datei nicht auf Echtheit geprüft. Empfohlen nur in **geschützten Netzen** mit vertrauenswürdiger Quelle. Für öffentliche URLs SHA-256 oder SHA-512 verwenden.")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.orange.opacity(0.14))
                    }
                }
            }
            Section {
                Button("Eintrag entfernen", role: .destructive, action: onDelete)
            }
        }
        .formStyle(.grouped)
    }
}
