import AppKit
import Foundation

/// Hinweis auf fehlende Java-8-Laufzeit (Zulu + JavaFX): Erststart und erneut, sobald die JRE fehlt; Download aus den Einstellungen möglich.
@MainActor
enum Jre8FirstLaunchOffer {
    /// Nur für den Fall „Hardware nicht erkennbar“: Hinweis nicht bei jedem Start wiederholen.
    private static let unknownHardwareAcknowledgedKey = "TradeERPLauncherJre8UnknownHardwareAcknowledged"

    private static var noDownloadSourceAlertedThisSession = false

    /// Kurz nach dem Start ausführen, damit argv/`openFile` zuerst abgearbeitet werden können.
    static func scheduleIfNeeded() {
        // Früheres Flag: unterdrückte dauerhaft alle Angebote, auch wenn die JRE später gelöscht wurde.
        UserDefaults.standard.removeObject(forKey: "TradeERPLauncherJre8FirstLaunchOfferHandled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            Task { await runIfNeeded() }
        }
    }

    /// Erststart / **erneut**, wenn die JRE unter dem erwarteten Pfad fehlt (z. B. Ordner gelöscht). Kein dauerhaftes „nie wieder“ nach einmaligem Abbrechen.
    static func runIfNeeded() async {
        if JavaRuntimeResolver.isJava8RuntimePresent() {
            return
        }
        guard let hw = MacHardwareArchitecture.current() else {
            guard !UserDefaults.standard.bool(forKey: unknownHardwareAcknowledgedKey) else { return }
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = "Java 8 (Zulu mit JavaFX)"
            a.informativeText =
                "Für diesen Mac konnte keine unterstützte Hardware-Architektur (Apple Silicon oder Intel) ermittelt werden. Bitte Java 8 manuell bereitstellen (Umgebungsvariable FSCL_JRE8 oder jre8/ im App-Bundle)."
            a.alertStyle = .informational
            a.addButton(withTitle: "OK")
            a.runModal()
            UserDefaults.standard.set(true, forKey: unknownHardwareAcknowledgedKey)
            return
        }

        let disk = LauncherSettings.load()
        guard Java8RuntimeDownloadResolver.resolve(settings: disk, hardware: hw) != nil else {
            if !noDownloadSourceAlertedThisSession {
                noDownloadSourceAlertedThisSession = true
                NSApp.activate(ignoringOtherApps: true)
                let a = NSAlert()
                a.messageText = "Java 8 mit JavaFX fehlt"
                a.informativeText = """
                Es ist keine Java-8-Laufzeit mit JavaFX installiert, und es gibt **keine aktive Download-Quelle** für \(hw.userFacingShortLabel).

                Bitte unter „Java-Laufzeitumgebungen“ den mitgelieferten Eintrag aktivieren oder eine eigene https-Quelle anlegen und mit „Speichern“ sichern — danach können Sie den Download dort starten.
                """
                a.alertStyle = .informational
                a.addButton(withTitle: "OK")
                a.runModal()
            }
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        let consent = NSAlert()
        consent.messageText = "Java 8 (Zulu mit JavaFX) wird benötigt"
        consent.informativeText = """
        Für enventa Trade ERP mit Java 8 ist eine Laufzeitumgebung mit JavaFX nötig. Übliche Java-8-JDKs ohne JavaFX (z. B. Eclipse Temurin) reichen dafür nicht aus.

        Erkannter Mac: \(hw.userFacingShortLabel).

        Der Launcher kann eine passende Java-8-Laufzeit mit JavaFX (gemäß Ihrer Konfiguration unter „Java-Laufzeitumgebungen“) automatisch herunterladen und nur in seinem Datenordner unter Application Support ablegen (keine systemweite Installation in macOS):

        \(AppPaths.downloadedJre8Directory.path)

        Dafür ist eine Internetverbindung zum Download-Server der gewählten Quelle nötig. Für das Paket gelten die Lizenz- und Nutzungsbedingungen des jeweiligen Anbieters sowie die Drittanbieterhinweise im entpackten JDK — bei Zulu z. B. https://docs.azul.com/core/tpls/

        Möchten Sie den Download jetzt ausführen?
        """
        consent.addButton(withTitle: "Herunterladen")
        consent.addButton(withTitle: "Abbrechen")
        consent.alertStyle = .informational
        if consent.runModal() == .alertSecondButtonReturn {
            return
        }

        let progress = Jre8DownloadProgressWindow(
            message: "Java 8 mit JavaFX wird heruntergeladen und im Launcher-Ordner unter Application Support entpackt — keine systemweite Installation."
        )
        defer { progress.close() }

        do {
            try await downloadJava8UsingMergedPreferences(java8RuntimePreferences: disk.Java8RuntimePreferences ?? .empty)
            var s = LauncherSettings.load()
            s.applyRecommendedMacJava8JvmArgumentsIfNeeded()
            s.save()
            let ok = NSAlert()
            ok.messageText = "Download abgeschlossen"
            ok.informativeText = "Die Java-8-Laufzeit liegt nun im Anwendungsordner des Launchers. Es wurde nichts systemweit installiert. Sie können den Client starten, sobald Broker und Java-Version passen."
            ok.addButton(withTitle: "OK")
            ok.runModal()
        } catch {
            let err = NSAlert()
            err.messageText = "Download fehlgeschlagen"
            err.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            err.alertStyle = .warning
            err.addButton(withTitle: "OK")
            err.runModal()
        }
    }

    /// Lädt die JRE gemäß **aktueller** `Java8RuntimePreferences` (z. B. ungespeicherte Werte aus dem Einstellungen-Tab — Aufrufer reicht die gebundenen Prefs durch).
    static func downloadJava8UsingMergedPreferences(java8RuntimePreferences: Java8RuntimePreferences) async throws {
        guard let hw = MacHardwareArchitecture.current() else {
            throw LaunchError.jre8RuntimeDownloadFailed("Keine unterstützte Mac-Hardware-Architektur.")
        }
        var s = LauncherSettings.load()
        s.Java8RuntimePreferences = java8RuntimePreferences
        guard let source = Java8RuntimeDownloadResolver.resolve(settings: s, hardware: hw) else {
            throw LaunchError.jre8RuntimeDownloadFailed(
                "Keine aktive Java-8-Download-Quelle für \(hw.userFacingShortLabel). Unter „Java-Laufzeitumgebungen“ prüfen und mit „Speichern“ sichern."
            )
        }
        try await downloadJava8UsingResolvedSource(java8RuntimePreferences: java8RuntimePreferences, source: source)
    }

    /// Lädt von **einer** gewählten Quelle (Button pro Quelle im Einstellungen-Tab).
    static func downloadJava8UsingResolvedSource(java8RuntimePreferences: Java8RuntimePreferences, source: Java8RuntimeResolvedSource) async throws {
        guard let hw = MacHardwareArchitecture.current() else {
            throw LaunchError.jre8RuntimeDownloadFailed("Keine unterstützte Mac-Hardware-Architektur.")
        }
        try await ZuluJava8FxRuntimeDownloader.downloadRuntimeIntoApplicationSupport(hardware: hw, source: source)
        var saved = LauncherSettings.load()
        saved.Java8RuntimePreferences = java8RuntimePreferences
        saved.applyRecommendedMacJava8JvmArgumentsIfNeeded()
        saved.save()
    }

    private static func sourceDisplayLabel(source: Java8RuntimeResolvedSource, prefs: Java8RuntimePreferences) -> String {
        switch source.kind {
        case .builtin:
            return Java8RuntimeCatalogLoader.builtinEntryForCurrentHost()?.label ?? "Mitgelieferte Katalog-Quelle"
        case .custom(let entryId):
            let raw = prefs.CustomEntries.first { $0.Id == entryId }?.Label.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return raw.isEmpty ? "Eigene Quelle" : raw
        }
    }

    /// Download mit Bestätigungsdialog — **eine** konkrete Quelle (Built-in oder Custom-Zeile).
    static func runDownloadFromResolvedSourceWithConfirmation(
        source: Java8RuntimeResolvedSource,
        java8RuntimePreferences: Java8RuntimePreferences
    ) async {
        guard !JavaRuntimeResolver.isJava8RuntimePresent() else {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = "Java 8 bereits vorhanden"
            a.informativeText = "Eine Java-8-Laufzeit ist bereits erreichbar (Bundle, Download-Ordner oder FSCL_JRE8). Ein erneuter Download ist nicht nötig."
            a.alertStyle = .informational
            a.addButton(withTitle: "OK")
            a.runModal()
            return
        }
        guard MacHardwareArchitecture.current() != nil else {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = "Java 8"
            a.informativeText = "Für diesen Mac konnte keine unterstützte Hardware-Architektur ermittelt werden."
            a.addButton(withTitle: "OK")
            a.runModal()
            return
        }

        let label = sourceDisplayLabel(source: source, prefs: java8RuntimePreferences)
        NSApp.activate(ignoringOtherApps: true)
        let consent = NSAlert()
        consent.messageText = "Java 8 mit JavaFX herunterladen?"
        consent.informativeText = """
        Quelle: \(label)

        Die Laufzeit wird nur unter

        \(AppPaths.downloadedJre8Directory.path)

        abgelegt (keine systemweite Installation). Es ist eine Internetverbindung zum Download-Server nötig.

        Fortfahren?
        """
        consent.addButton(withTitle: "Herunterladen")
        consent.addButton(withTitle: "Abbrechen")
        consent.alertStyle = .informational
        if consent.runModal() == .alertSecondButtonReturn { return }

        let progress = Jre8DownloadProgressWindow(
            message: "Java 8 mit JavaFX wird heruntergeladen und unter Application Support entpackt."
        )
        defer { progress.close() }

        do {
            try await downloadJava8UsingResolvedSource(java8RuntimePreferences: java8RuntimePreferences, source: source)
            NSApp.activate(ignoringOtherApps: true)
            let ok = NSAlert()
            ok.messageText = "Download abgeschlossen"
            ok.informativeText = "Die Java-8-Laufzeit liegt im Launcher-Ordner. Sie können die JVM-Argumente bei Bedarf unter „JVM-Argumente“ anpassen (nach „Speichern“)."
            ok.addButton(withTitle: "OK")
            ok.runModal()
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let err = NSAlert()
            err.messageText = "Download fehlgeschlagen"
            err.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            err.alertStyle = .warning
            err.addButton(withTitle: "OK")
            err.runModal()
        }
    }

    /// Tab „Java-Laufzeitumgebungen“: Download über die **global** gewählte Quelle (wie bisher).
    static func runDownloadFromSettingsWithConfirmation(java8Prefs: Java8RuntimePreferences) async {
        guard !JavaRuntimeResolver.isJava8RuntimePresent() else {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = "Java 8 bereits vorhanden"
            a.informativeText = "Eine Java-8-Laufzeit ist bereits erreichbar (Bundle, Download-Ordner oder FSCL_JRE8). Ein erneuter Download ist nicht nötig."
            a.alertStyle = .informational
            a.addButton(withTitle: "OK")
            a.runModal()
            return
        }
        guard let hw = MacHardwareArchitecture.current() else {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = "Java 8"
            a.informativeText = "Für diesen Mac konnte keine unterstützte Hardware-Architektur ermittelt werden."
            a.addButton(withTitle: "OK")
            a.runModal()
            return
        }
        var probe = LauncherSettings.load()
        probe.Java8RuntimePreferences = java8Prefs
        guard let source = Java8RuntimeDownloadResolver.resolve(settings: probe, hardware: hw) else {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = "Keine Download-Quelle"
            a.informativeText = """
            Für \(hw.userFacingShortLabel) ist keine **aktive** Download-Quelle konfiguriert (mitgelieferten Eintrag aktivieren oder eigene URL anlegen). Ungespeicherte Änderungen ggf. zuerst mit „Speichern“ übernehmen.
            """
            a.alertStyle = .informational
            a.addButton(withTitle: "OK")
            a.runModal()
            return
        }

        await runDownloadFromResolvedSourceWithConfirmation(source: source, java8RuntimePreferences: java8Prefs)
    }
}

@MainActor
private final class Jre8DownloadProgressWindow {
    private let panel: NSPanel

    init(message: String) {
        let rect = NSRect(x: 0, y: 0, width: 440, height: 100)
        panel = NSPanel(
            contentRect: rect,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = "Java 8"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let content = NSView(frame: rect)
        let spin = NSProgressIndicator(frame: NSRect(x: 24, y: 44, width: 24, height: 24))
        spin.style = .spinning
        spin.isIndeterminate = true
        spin.startAnimation(nil)

        let label = NSTextField(wrappingLabelWithString: message)
        label.frame = NSRect(x: 56, y: 16, width: 360, height: 68)

        content.addSubview(spin)
        content.addSubview(label)
        panel.contentView = content
        panel.center()
        panel.level = .floating
        panel.orderFrontRegardless()
    }

    func close() {
        panel.close()
    }
}
