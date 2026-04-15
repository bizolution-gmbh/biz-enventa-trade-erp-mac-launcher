import Foundation

/// Entspricht den Pfaden aus `ConfigService` / `CacheService` der Windows-Variante, auf macOS gemappt.
enum AppPaths {
    private static let vendorFolder = "enventa Group"
    private static let appFolderName = "FS Client Launcher"

    /// `%AppData%\enventa Group\FS Client Launcher`
    static var appDataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(vendorFolder, isDirectory: true)
            .appendingPathComponent(appFolderName, isDirectory: true)
    }

    /// `%LocalAppData%\enventa Group\FS Client Launcher`
    static var localAppDataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches", isDirectory: true)
            .appendingPathComponent(vendorFolder, isDirectory: true)
            .appendingPathComponent(appFolderName, isDirectory: true)
    }

    static var launcherConfigURL: URL {
        appDataDirectory.appendingPathComponent("launcherconfig.json", isDirectory: false)
    }

    /// Gespeicherte `.fsclient`-Kürzel und Schalter für das Menüleisten-Icon.
    static var fsClientShortcutsURL: URL {
        appDataDirectory.appendingPathComponent("menu-fsclients.json", isDirectory: false)
    }

    static var jarCacheDirectory: URL {
        localAppDataDirectory.appendingPathComponent(".jarcache", isDirectory: true)
    }

    static var jarDirectory: URL {
        jarCacheDirectory.appendingPathComponent("jar", isDirectory: true)
    }

    /// Wie unter Windows: `…\FS Client Launcher\Logfiles`
    static var logFilesDirectory: URL {
        appDataDirectory.appendingPathComponent("Logfiles", isDirectory: true)
    }

    /// PNG mit gleicher Dock-Maske wie der Launcher (für `java -Xdock:icon=…`).
    static var javaDockIconPNG: URL {
        localAppDataDirectory.appendingPathComponent("fscl-java-dock-icon.png", isDirectory: false)
    }

    /// Basisverzeichnis neben dem ausführbaren Launcher (JDK-Bundles `jdk11/`, `jdk21/`, `jre8/`).
    static var launcherRuntimeBaseDirectory: URL {
        let execURL = URL(fileURLWithPath: CommandLine.arguments[0], isDirectory: false)
            .resolvingSymlinksInPath()
        let macOSDir = execURL.deletingLastPathComponent()
        if macOSDir.lastPathComponent == "MacOS" {
            return macOSDir.deletingLastPathComponent()
                .appendingPathComponent("Resources", isDirectory: true)
        }
        return macOSDir
    }

    static func migrateLegacyDirectoriesIfNeeded() {
        let fm = FileManager.default
        let legacyHome = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("FSClientLauncher", isDirectory: true)
        if !fm.fileExists(atPath: appDataDirectory.path), fm.fileExists(atPath: legacyHome.path) {
            try? fm.createDirectory(at: appDataDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.moveItem(at: legacyHome, to: appDataDirectory)
        } else {
            try? fm.createDirectory(at: appDataDirectory, withIntermediateDirectories: true)
        }

        let legacyLocal = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/FSClientLauncher", isDirectory: true)
        if !fm.fileExists(atPath: localAppDataDirectory.path), fm.fileExists(atPath: legacyLocal.path) {
            try? fm.createDirectory(at: localAppDataDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.moveItem(at: legacyLocal, to: localAppDataDirectory)
        } else {
            try? fm.createDirectory(at: localAppDataDirectory, withIntermediateDirectories: true)
        }

        let oldCacheInAppData = appDataDirectory.appendingPathComponent(".jarcache", isDirectory: true)
        if fm.fileExists(atPath: oldCacheInAppData.path), !fm.fileExists(atPath: jarCacheDirectory.path) {
            try? fm.createDirectory(at: jarCacheDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.moveItem(at: oldCacheInAppData, to: jarCacheDirectory)
        }
    }
}
