import Foundation

enum UseJavaVersion: String, Codable, CaseIterable, Identifiable {
    case Recommended
    case Supported
    case Experimental
    var id: String { rawValue }
}

enum ProxyMode: String, Codable, CaseIterable, Identifiable {
    case Direct
    case Windows
    var id: String { rawValue }

    /// Steuert die **JVM** (`-Djava.net.useSystemProxies`). Native Broker-/JAR-Downloads nutzen immer die macOS-Netzwerk-/Proxy-Kette.
    var label: String {
        switch self {
        case .Direct: "Direkt (kein Proxy für Java)"
        case .Windows: "System (Proxy für Java)"
        }
    }
}

enum TraceLevel: String, Codable, CaseIterable, Identifiable {
    case Error
    case Warning
    case Information
    case Verbose
    var id: String { rawValue }
}

/// `launcherconfig.json` — Property-Namen wie in `ConfigService` der .NET-App (`CallerMemberName`).
struct LauncherSettings: Codable, Equatable {
    var DisplayConsole: Bool = false
    var CacheCleanDays: Int = 30
    var UseJavaVersion: UseJavaVersion = .Recommended
    var JavaVmArguments: [String] = []
    var Java8VmArguments: [String] = []
    var Java11VmArguments: [String] = []
    var Java21VmArguments: [String] = []
    var TraceLevel: TraceLevel = .Error
    var ProxyMode: ProxyMode = .Direct

    private static let ioQueue = DispatchQueue(label: "de.frameworksystems.FSClientLauncher.settings")

    static func load() -> LauncherSettings {
        ioQueue.sync {
            let url = AppPaths.launcherConfigURL
            guard let data = try? Data(contentsOf: url),
                let obj = try? JSONDecoder().decode(LauncherSettings.self, from: data) else {
                return LauncherSettings()
            }
            return obj
        }
    }

    func save() {
        Self.ioQueue.async {
            try? FileManager.default.createDirectory(
                at: AppPaths.appDataDirectory,
                withIntermediateDirectories: true
            )
            if let data = try? JSONEncoder().encode(self) {
                try? data.write(to: AppPaths.launcherConfigURL, options: .atomic)
            }
        }
    }
}
