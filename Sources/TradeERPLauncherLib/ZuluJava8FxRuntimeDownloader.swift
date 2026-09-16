import CryptoKit
import Foundation

extension Notification.Name {
    /// Nach Bereitstellung einer JRE/JDK unter Application Support (nur Launcher-Ordner) — Einstellungen-UI aktualisiert JVM-Sichtbarkeit.
    static let tradeERPLauncherJavaRuntimesChanged = Notification.Name("de.bizolution.trade-erp-launcher.JavaRuntimesChanged")
}

/// Lädt **Java 8 JDK mit JavaFX** aus der in den Einstellungen aufgelösten Quelle (eigene URL oder mitgeliefertes Zulu-8-Katalogpaket) und legt es unter `AppPaths.downloadedJre8Directory` ab (Download + Entpacken, keine systemweite Installation).
enum ZuluJava8FxRuntimeDownloader {
    /// Download gemäß `LauncherSettings.Java8RuntimePreferences` (aktive Custom-Quelle vor Built-in).
    static func downloadRuntimeIntoApplicationSupport(hardware: MacHardwareArchitecture, settings: LauncherSettings) async throws {
        guard let source = Java8RuntimeDownloadResolver.resolve(settings: settings, hardware: hardware) else {
            throw LaunchError.jre8RuntimeDownloadFailed(
                "Keine aktive Java-8-Download-Quelle für \(hardware.userFacingShortLabel). Unter „Java-Laufzeitumgebungen“ den mitgelieferten Eintrag aktivieren oder eine eigene https-URL anlegen."
            )
        }
        try await downloadRuntimeIntoApplicationSupport(hardware: hardware, source: source)
    }

    /// Download von **einer** konkret gewählten Quelle (Einstellungen-Tab: Button pro Zeile).
    static func downloadRuntimeIntoApplicationSupport(hardware: MacHardwareArchitecture, source: Java8RuntimeResolvedSource) async throws {
        guard BrokerFetcher.isPermittedOutboundDownloadURL(source.downloadURL) else {
            throw LaunchError.jre8RuntimeDownloadFailed("Download-URL nicht erlaubt.")
        }

        let fm = FileManager.default
        let tmpTar = fm.temporaryDirectory.appendingPathComponent("zulu8fx-\(UUID().uuidString).tar.gz", isDirectory: false)
        let tmpStage = fm.temporaryDirectory.appendingPathComponent("zulu8fx-stage-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fm.removeItem(at: tmpTar)
            try? fm.removeItem(at: tmpStage)
        }

        var dlReq = URLRequest(url: source.downloadURL)
        dlReq.setValue("application/gzip, */*", forHTTPHeaderField: "Accept")
        let (tarData, tarResp) = try await BrokerFetcher.sharedOutboundURLSession().data(for: dlReq)
        guard let tarHttp = tarResp as? HTTPURLResponse, (200 ... 299).contains(tarHttp.statusCode) else {
            throw LaunchError.jre8RuntimeDownloadFailed("Download: HTTP \((tarResp as? HTTPURLResponse)?.statusCode ?? -1).")
        }
        try verifyDownloadedArchive(data: tarData, hashType: source.hashType, expectedHex: source.expectedHashHex)
        try tarData.write(to: tmpTar, options: .atomic)

        try fm.createDirectory(at: tmpStage, withIntermediateDirectories: true)
        try extractTarGz(archive: tmpTar, destination: tmpStage)

        // Defense in depth: `/usr/bin/tar` extrahiert `..`-Pfade und nach außen zeigende Symlinks ohne
        // Warnung. Bei einem manipulierten Archiv (oder einer Custom-Quelle ohne Hash) verhindern wir,
        // dass irgendetwas außerhalb des Staging-Verzeichnisses landet.
        do {
            try ArchiveExtractionGuard.verifyContainedExtraction(stagingDirectory: tmpStage, fileManager: fm)
        } catch {
            throw LaunchError.jre8RuntimeDownloadFailed(
                "Archiv enthält Pfade außerhalb des Entpack-Verzeichnisses: \(error.localizedDescription)"
            )
        }

        guard let jdkBundle = findFirstJdkBundle(under: tmpStage) else {
            throw LaunchError.jre8RuntimeDownloadFailed(
                "Im Archiv wurde kein macOS-JDK-Bundle gefunden (erwartet Contents/Home/bin/java)."
            )
        }
        let javaCandidate = jdkBundle.appendingPathComponent("Contents/Home/bin/java", isDirectory: false)
        guard fm.isExecutableFile(atPath: javaCandidate.path) else {
            throw LaunchError.jre8RuntimeDownloadFailed("Erwartet ausführbar: \(javaCandidate.path)")
        }

        let destRoot = AppPaths.downloadedJre8Directory
        try fm.createDirectory(at: destRoot, withIntermediateDirectories: true)
        let destBundle = destRoot.appendingPathComponent(hardware.downloadedJdkBundleFolderName, isDirectory: true)
        if fm.fileExists(atPath: destBundle.path) {
            try fm.removeItem(at: destBundle)
        }
        try fm.copyItem(at: jdkBundle, to: destBundle)

        NotificationCenter.default.post(name: .tradeERPLauncherJavaRuntimesChanged, object: nil)
    }

    private static func verifyDownloadedArchive(data: Data, hashType: Java8RuntimeHashType, expectedHex: String) throws {
        switch hashType {
        case .none:
            return
        case .sha256:
            let got = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard got == expectedHex.lowercased() else {
                throw LaunchError.jre8RuntimeDownloadFailed(
                    "SHA-256-Prüfsumme stimmt nicht überein (Datei beschädigt, abgebrochen oder URL liefert anderes Paket)."
                )
            }
        case .sha512:
            let got = SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard got == expectedHex.lowercased() else {
                throw LaunchError.jre8RuntimeDownloadFailed(
                    "SHA-512-Prüfsumme stimmt nicht überein (Datei beschädigt, abgebrochen oder URL liefert anderes Paket)."
                )
            }
        }
    }

    private static func extractTarGz(archive: URL, destination: URL) throws {
        let tar = URL(fileURLWithPath: "/usr/bin/tar")
        guard FileManager.default.isExecutableFile(atPath: tar.path) else {
            throw LaunchError.jre8RuntimeDownloadFailed("/usr/bin/tar fehlt.")
        }
        let p = Process()
        p.executableURL = tar
        p.arguments = ["-xzf", archive.path, "-C", destination.path]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw LaunchError.jre8RuntimeDownloadFailed("Entpacken mit tar fehlgeschlagen (Code \(p.terminationStatus)).")
        }
    }

    /// Findet das macOS-JDK-Bundle im entpackten Archiv: Ordner mit `Contents/Home/bin/java`.
    ///
    /// Azul Zulu 8 (tar.gz) seit April 2026: Top-Level-Ordner **ohne** `.jdk`-Suffix, `Contents/` direkt darunter.
    /// Ältere Pakete hatten zusätzlich ein `*.jdk`-Verzeichnis — beides wird erkannt.
    static func findFirstJdkBundle(under root: URL, fileManager fm: FileManager = .default) -> URL? {
        if isMacOsJdkBundleRoot(root, fileManager: fm) { return root }
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        for case let item as URL in enumerator {
            guard isMacOsJdkBundleRoot(item, fileManager: fm) else { continue }
            return item
        }
        return nil
    }

    private static func isMacOsJdkBundleRoot(_ directory: URL, fileManager fm: FileManager) -> Bool {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else { return false }
        let java = directory.appendingPathComponent("Contents/Home/bin/java", isDirectory: false)
        var javaIsDir: ObjCBool = false
        return fm.fileExists(atPath: java.path, isDirectory: &javaIsDir) && !javaIsDir.boolValue
    }
}
