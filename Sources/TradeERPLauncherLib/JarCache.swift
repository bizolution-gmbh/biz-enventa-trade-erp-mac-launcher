import CryptoKit
import Foundation

/// JAR-Cache — angelehnt an `CacheService`.
enum JarCache {
    static func escapeBrokerName(_ brokerUrl: String) -> String {
        let s = brokerUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return s
            .replacingOccurrences(of: "/", with: ".")
            .replacingOccurrences(of: ":", with: ".")
    }

    /// SHA-1 als reiner Hex-String (40 Zeichen, `[0-9A-Fa-f]`). Wird vor jeder Pfad-Bildung
    /// mit `jar.Sha1` aufgerufen — `URL.appendingPathComponent` normalisiert keine `../`-Sequenzen,
    /// und der Wert stammt aus einer **unsignierten** Broker-Antwort.
    static func isValidSha1Hex(_ raw: String) -> Bool {
        guard raw.count == 40 else { return false }
        for c in raw.unicodeScalars {
            switch c {
            case "0" ... "9", "a" ... "f", "A" ... "F":
                continue
            default:
                return false
            }
        }
        return true
    }

    static func saveBrokerJson(brokerUrl: String, json: String) throws {
        let name = escapeBrokerName(brokerUrl) + ".json"
        let dir = AppPaths.jarCacheDirectory.appendingPathComponent("broker", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name)
        try json.data(using: .utf8)?.write(to: file)
        try FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: file.path
        )
    }

    static func sha1File(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var sha = Insecure.SHA1()
        while true {
            let chunk = (try handle.read(upToCount: 1024 * 1024)) ?? Data()
            if chunk.isEmpty { break }
            sha.update(data: chunk)
        }
        return sha.finalize().map { String(format: "%02X", $0) }.joined()
    }

    static func downloadJar(
        baseJarUri: URL,
        jar: ApiJarFile
    ) async throws {
        // Ungültige Sha1-Werte (Pfad-Traversal, NUL, falsche Länge) **vor** jeder Pfad-Bildung
        // ablehnen. Sonst landet ein manipulierter String z. B. als Verzeichnisname im Cache.
        guard isValidSha1Hex(jar.Sha1) else {
            throw LaunchError.invalidJarSha1Format(href: jar.Href, sha1: jar.Sha1)
        }
        let jarRoot = AppPaths.jarDirectory
        let finalJar = jarRoot.appendingPathComponent(jar.Sha1 + ".jar", isDirectory: false)
        let finalNative = jarRoot.appendingPathComponent(jar.Sha1, isDirectory: true)
        if jar.isNativeLib, FileManager.default.fileExists(atPath: finalNative.path) { return }
        if !jar.isNativeLib, FileManager.default.fileExists(atPath: finalJar.path) { return }

        let lockURL = AppPaths.jarCacheDirectory.appendingPathComponent("locks/\(jar.Sha1).lock", isDirectory: false)
        let lock = try FileLock(lockFile: lockURL)
        defer { _ = lock }

        if jar.isNativeLib, FileManager.default.fileExists(atPath: finalNative.path) { return }
        if !jar.isNativeLib, FileManager.default.fileExists(atPath: finalJar.path) { return }

        let resolved = URL(string: jar.Href, relativeTo: baseJarUri)?.absoluteURL ?? baseJarUri.appendingPathComponent(jar.Href)
        guard BrokerFetcher.isPermittedOutboundDownloadURL(resolved) else {
            throw LaunchError.disallowedOutboundURL(jar.Href)
        }
        let tempDir = AppPaths.jarCacheDirectory.appendingPathComponent("temp", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".download", isDirectory: false)

        do {
            let req = URLRequest(url: resolved)
            let session = BrokerFetcher.sharedOutboundURLSession()
            let (localURL, response) = try await session.download(for: req)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                throw LaunchError.brokerHTTP((response as? HTTPURLResponse)?.statusCode ?? -1)
            }
            try? FileManager.default.removeItem(at: tempFile)
            try FileManager.default.moveItem(at: localURL, to: tempFile)
            let hash = try sha1File(at: tempFile)
            guard hash.caseInsensitiveCompare(jar.Sha1) == .orderedSame else {
                throw LaunchError.jarShaMismatch(jar.Href)
            }
            if jar.isNativeLib {
                try unzipNativeLib(tempZip: tempFile, destinationDir: finalNative)
            } else {
                try FileManager.default.createDirectory(at: jarRoot, withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: finalJar)
                try FileManager.default.moveItem(at: tempFile, to: finalJar)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempFile)
            throw error
        }
    }

    private static func unzipNativeLib(tempZip: URL, destinationDir: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationDir.path) { return }
        let staging = AppPaths.jarCacheDirectory
            .appendingPathComponent("temp", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-q", "-o", tempZip.path, "-d", staging.path]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            try? fm.removeItem(at: staging)
            throw LaunchError.jarDownload("unzip", NSError(domain: "unzip", code: Int(proc.terminationStatus)))
        }
        // Defense in depth: `/usr/bin/unzip` lehnt `..`-Pfade und nach außen zeigende Symlinks
        // nicht ab. Bei Verstoß komplettes Staging-Verzeichnis verwerfen.
        do {
            try ArchiveExtractionGuard.verifyContainedExtraction(stagingDirectory: staging, fileManager: fm)
        } catch {
            try? fm.removeItem(at: staging)
            throw LaunchError.jarDownload("unzip-extraction", error)
        }
        try removeAllMetaInfDirectories(under: staging)
        try fm.createDirectory(at: destinationDir.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: staging, to: destinationDir)
        try? fm.removeItem(at: tempZip)
    }

    private static func removeAllMetaInfDirectories(under root: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        var metaDirs: [URL] = []
        for case let url as URL in enumerator {
            if url.lastPathComponent == "META-INF",
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                metaDirs.append(url)
            }
        }
        for u in metaDirs.sorted(by: { $0.path.count > $1.path.count }) {
            try? fm.removeItem(at: u)
        }
    }
}
