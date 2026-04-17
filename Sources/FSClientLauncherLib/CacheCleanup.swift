import Foundation

/// Port von `CacheService.CleanupCache` und `ConsoleService.CleanupLogFiles`.
enum CacheCleanup {
    /// - Parameter days: `nil` = Wert aus `cacheCleanDays` (Konfiguration), `0` = vollständige Bereinigung wie „Cache leeren“ unter Windows.
    static func cleanupCache(days: Int? = nil, cacheCleanDays: Int = LauncherSettings.load().CacheCleanDays) {
        let fm = FileManager.default
        let cacheRoot = AppPaths.jarCacheDirectory
        guard fm.fileExists(atPath: cacheRoot.path) else { return }

        let num = days ?? cacheCleanDays
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let threshold: Date? = num > 0 ? calendar.date(byAdding: .day, value: -num, to: todayStart) : nil

        var keepSha1 = Set<String>()
        var brokerListKeep = Set<String>()

        let brokerDir = cacheRoot.appendingPathComponent("broker", isDirectory: true)
        if fm.fileExists(atPath: brokerDir.path),
            let brokerFiles = try? fm.contentsOfDirectory(at: brokerDir, includingPropertiesForKeys: [.contentAccessDateKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) {
            for fileURL in brokerFiles where fileURL.pathExtension.lowercased() == "json" {
                let refDay = startOfReferenceDay(for: fileURL) ?? todayStart
                let shouldDelete: Bool
                if num <= 0 {
                    shouldDelete = true
                } else if let t = threshold {
                    shouldDelete = refDay <= t
                } else {
                    shouldDelete = true
                }
                if shouldDelete {
                    try? fm.removeItem(at: fileURL)
                    continue
                }
                let brokerKey = fileURL.deletingPathExtension().lastPathComponent
                brokerListKeep.insert(brokerKey)
                if let data = try? Data(contentsOf: fileURL),
                    let dl = try? JSONFlexible.decodeJarDownload(data: data) {
                    for j in dl.JarFiles ?? [] {
                        keepSha1.insert(j.Sha1.uppercased())
                    }
                } else {
                    try? fm.removeItem(at: fileURL)
                }
            }
        }

        let jarDir = cacheRoot.appendingPathComponent("jar", isDirectory: true)
        if fm.fileExists(atPath: jarDir.path),
            let jarEntries = try? fm.contentsOfDirectory(at: jarDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for entry in jarEntries {
                let isJar = entry.pathExtension.lowercased() == "jar"
                if isJar {
                    let jarBase = entry.deletingPathExtension().lastPathComponent
                    if !keepSha1.contains(jarBase.uppercased()) {
                        try? fm.removeItem(at: entry)
                    }
                    continue
                }
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue else { continue }
                if !keepSha1.contains(entry.lastPathComponent.uppercased()) {
                    let staging = jarDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    do {
                        try fm.moveItem(at: entry, to: staging)
                        try fm.removeItem(at: staging)
                    } catch {
                        try? fm.removeItem(at: entry)
                    }
                }
            }
        }

        let filesRoot = cacheRoot.appendingPathComponent("files", isDirectory: true)
        if fm.fileExists(atPath: filesRoot.path),
            let subdirs = try? fm.contentsOfDirectory(at: filesRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for dir in subdirs {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
                if !brokerListKeep.contains(dir.lastPathComponent) {
                    try? fm.removeItem(at: dir)
                }
            }
        }

        cleanupLogFiles(daysValue: num)
    }

    /// Entspricht `ConsoleService.CleanupLogFiles`.
    static func cleanupLogFiles(daysValue: Int) {
        let fm = FileManager.default
        let logDir = AppPaths.logFilesDirectory
        guard fm.fileExists(atPath: logDir.path),
            let files = try? fm.contentsOfDirectory(at: logDir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]) else {
            return
        }
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let threshold: Date? = daysValue > 0 ? calendar.date(byAdding: .day, value: -daysValue, to: todayStart) : nil
        for fileURL in files {
            let created = (try? fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate).map { calendar.startOfDay(for: $0) } ?? todayStart
            let shouldDelete: Bool
            if daysValue <= 0 {
                shouldDelete = true
            } else if let t = threshold {
                shouldDelete = created <= t
            } else {
                shouldDelete = true
            }
            if shouldDelete {
                try? fm.removeItem(at: fileURL)
            }
        }
    }

    private static func startOfReferenceDay(for fileURL: URL) -> Date? {
        let calendar = Calendar.current
        let rv = try? fileURL.resourceValues(forKeys: [.contentAccessDateKey, .contentModificationDateKey])
        let d = rv?.contentAccessDate ?? rv?.contentModificationDate
        return d.map { calendar.startOfDay(for: $0) }
    }
}
