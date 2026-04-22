import Foundation

// MARK: - Launch-Parameter (LaunchParameterKey)

enum LaunchParameterKey {
    static let title = "title"
    static let broker = "broker"
    static let language = "language"
    static let theme = "theme"
    static let noDomainAuth = "noDomainAuth"
    static let support = "support"
    static let devBroker = "devBroker"
    static let lookAndFeel = "lookAndFeel"
    static let splashImage = "splashImage"
    /// Wie in der Windows-`launcherconfig.json` (PascalCase, Wert `True`/`False`).
    static let displayConsole = "DisplayConsole"
}

struct LaunchParameters: Sendable {
    var args: [String: String]
    let broker: String

    init(args: [String: String]) throws {
        self.args = args
        guard let b = args[LaunchParameterKey.broker]?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty else {
            throw LaunchError.missingBroker
        }
        self.broker = b
    }

    var language: String {
        args[LaunchParameterKey.language] ?? "de"
    }

    var theme: String {
        args[LaunchParameterKey.theme] ?? "DefaultID"
    }

    var lookAndFeel: String {
        args[LaunchParameterKey.lookAndFeel] ?? "1"
    }

    var noDomainAuth: Bool {
        guard let v = args[LaunchParameterKey.noDomainAuth] else { return false }
        return (v as NSString).boolValue
    }

    var support: Bool {
        guard let v = args[LaunchParameterKey.support] else { return false }
        return (v as NSString).boolValue
    }

    /// Nicht-leerer Anwendungstitel aus der `.fsclient`-JSON (`title`).
    var configurationTitle: String? {
        let t = args[LaunchParameterKey.title]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    /// Anzeigename für Menüleiste/Kachel: zuerst `title` aus der Konfiguration, sonst Broker-Host, Dateiname oder URL-Host.
    func displayNameForShortcutMenu(originalArgument: String, localFilePath: String?) -> String {
        if let t = configurationTitle { return t }
        if let host = URL(string: broker)?.host, !host.isEmpty { return host }
        if let p = localFilePath {
            return URL(fileURLWithPath: p).deletingPathExtension().lastPathComponent
        }
        if let u = URL(string: originalArgument), let h = u.host, !h.isEmpty { return h }
        return "FS Client"
    }
}

// MARK: - Broker-Antwort (ApiJarDownload)

enum JavaReleaseState: String, Codable, Sendable {
    case Recommended
    case Supported
    case Experimental
}

struct ApiJavaVersion: Sendable, Hashable {
    var Version: Int
    var ReleaseState: JavaReleaseState
}

struct ApiJarFile: Sendable, Hashable {
    var Href: String
    var Sha1: String
    /// JSON-Feld laut Server (häufig `"1"` / `1`).
    fileprivate var Main: String?
    var Os: String?
    var Architecture: String?
    fileprivate var NativeLib: String?
    var Size: Int64?

    init(Href: String, Sha1: String, main: String?, Os: String?, Architecture: String?, nativeLib: String?, Size: Int64?) {
        self.Href = Href
        self.Sha1 = Sha1
        self.Main = main
        self.Os = Os
        self.Architecture = Architecture
        self.NativeLib = nativeLib
        self.Size = Size
    }

    var isMainJar: Bool {
        if let m = Main?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            return m == "1" || m == "true"
        }
        return false
    }

    var isNativeLib: Bool {
        if let n = NativeLib?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            return n == "1" || n == "true"
        }
        return false
    }
}

struct ApiJarDownload: Sendable {
    var FsVersion: String?
    var LauncherMinVersion: String?
    var JavaVersions: [ApiJavaVersion]?
    var DevBroker: Bool?
    var MainClass: String?
    var SplashImage: String?
    var JarFiles: [ApiJarFile]?
    var JavaProperties: [String]?

    init(
        FsVersion: String?,
        LauncherMinVersion: String?,
        JavaVersions: [ApiJavaVersion]?,
        DevBroker: Bool?,
        MainClass: String?,
        SplashImage: String?,
        JarFiles: [ApiJarFile]?,
        JavaProperties: [String]?
    ) {
        self.FsVersion = FsVersion
        self.LauncherMinVersion = LauncherMinVersion
        self.JavaVersions = JavaVersions
        self.DevBroker = DevBroker
        self.MainClass = MainClass
        self.SplashImage = SplashImage
        self.JarFiles = JarFiles
        self.JavaProperties = JavaProperties
    }
}
