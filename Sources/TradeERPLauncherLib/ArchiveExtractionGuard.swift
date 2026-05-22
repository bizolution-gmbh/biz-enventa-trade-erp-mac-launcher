import Foundation

/// Schutz gegen **Zip-Slip / Tar-Slip**: nach dem Entpacken eines fremden Archivs prüfen,
/// dass kein Eintrag aus dem Staging-Verzeichnis ausbricht — weder über `..`-Pfade noch
/// über Symlinks, die nach außen zeigen.
///
/// `/usr/bin/unzip` und `/usr/bin/tar` schreiben relative Pfade, ohne `..`-Sequenzen
/// abzulehnen; Symlinks werden ohne Ziel-Auflösung angelegt. Wir verifizieren deshalb
/// **post-extraction** über `FileManager`.
enum ArchiveExtractionGuard {
    enum ExtractionError: Error, LocalizedError, Equatable {
        case stagingDirectoryNotEnumerable(path: String)
        case pathOutsideStaging(path: String)
        case symlinkEscapesStaging(linkPath: String, target: String)
        case symlinkUnreadable(linkPath: String)

        var errorDescription: String? {
            switch self {
            case .stagingDirectoryNotEnumerable(let path):
                return "Staging-Verzeichnis nicht durchsuchbar: \(path)"
            case .pathOutsideStaging(let path):
                return "Archiv-Eintrag liegt außerhalb des Staging-Verzeichnisses: \(path)"
            case .symlinkEscapesStaging(let link, let target):
                return "Symlink \(link) zeigt aus dem Staging-Verzeichnis hinaus auf \(target)."
            case .symlinkUnreadable(let link):
                return "Symlink konnte nicht gelesen werden: \(link)"
            }
        }
    }

    /// Prüft, dass alle Einträge unter `stagingDirectory` tatsächlich physisch innerhalb davon liegen.
    /// Bricht beim **ersten** Verstoß ab, damit der Aufrufer das Staging-Verzeichnis komplett verwerfen
    /// kann.
    static func verifyContainedExtraction(stagingDirectory: URL, fileManager fm: FileManager = .default) throws {
        let stagePathPrefix = canonicalPathPrefix(forDirectory: stagingDirectory)
        guard let enumerator = fm.enumerator(
            at: stagingDirectory,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ) else {
            throw ExtractionError.stagingDirectoryNotEnumerable(path: stagingDirectory.path)
        }
        for case let item as URL in enumerator {
            try verifyEntryContained(item: item, stagePathPrefix: stagePathPrefix, fm: fm)
        }
    }

    /// Reine Pfadlogik — testbar ohne Datei-IO. Liefert das mit `/` abgeschlossene Präfix, gegen das
    /// alle Einträge geprüft werden (`standardizedFileURL` löst `..`/`.`/Doppel-Slashes auf).
    static func canonicalPathPrefix(forDirectory directory: URL) -> String {
        let standardized = directory.resolvingSymlinksInPath().standardizedFileURL.path
        return standardized.hasSuffix("/") ? standardized : standardized + "/"
    }

    /// Reine Pfadlogik — testbar ohne Datei-IO: liegt `candidatePath` (bereits standardisiert) **unter**
    /// dem mit `/` abgeschlossenen `stagePathPrefix`?
    static func isPathContained(candidatePath: String, stagePathPrefix: String) -> Bool {
        let stripped = stagePathPrefix.hasSuffix("/") ? String(stagePathPrefix.dropLast()) : stagePathPrefix
        if candidatePath == stripped { return true }
        return candidatePath.hasPrefix(stagePathPrefix)
    }

    private static func verifyEntryContained(item: URL, stagePathPrefix: String, fm: FileManager) throws {
        // 1. Den absoluten, standardisierten Pfad **mit aufgelösten Symlinks im Eltern-Pfad**: damit
        //    erkennen wir auch Items, deren übergeordneter Pfad bereits aus dem Staging hinausführt.
        let parentResolved = item.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let candidate = parentResolved.appendingPathComponent(item.lastPathComponent).standardizedFileURL.path
        guard isPathContained(candidatePath: candidate, stagePathPrefix: stagePathPrefix) else {
            throw ExtractionError.pathOutsideStaging(path: candidate)
        }

        // 2. Symlinks separat prüfen: Ziel kann **relativ** zum Symlink-Verzeichnis sein und auf einen
        //    Pfad außerhalb des Staging-Verzeichnisses zeigen, ohne dass der Symlink-Eintrag selbst es
        //    tut. `unzip`/`tar` lehnen das nicht ab.
        let isSymlink = (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
        guard isSymlink else { return }
        guard let raw = try? fm.destinationOfSymbolicLink(atPath: item.path) else {
            throw ExtractionError.symlinkUnreadable(linkPath: item.path)
        }
        let targetURL: URL
        if (raw as NSString).isAbsolutePath {
            targetURL = URL(fileURLWithPath: raw).standardizedFileURL
        } else {
            targetURL = URL(fileURLWithPath: raw, relativeTo: item.deletingLastPathComponent()).standardizedFileURL
        }
        guard isPathContained(candidatePath: targetURL.path, stagePathPrefix: stagePathPrefix) else {
            throw ExtractionError.symlinkEscapesStaging(linkPath: item.path, target: targetURL.path)
        }
    }
}
