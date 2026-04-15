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

    /// Swing-/AWT-Integration auf macOS als `-D`-Systemproperties (entsprechen `System.setProperty` vor UI-Start).
    /// Orientierung: [FlatLaf – macOS](https://www.formdev.com/flatlaf/macos/) (Menüleiste, Anwendungsname, Titelleisten-Erscheinungsbild).
    /// `apple.awt.application.appearance` setzt ab ca. Java 8u322 / 11.0.8 u. a. die Titelleisten an die Systemdarstellung.
    /// `swing.defaultlaf=Aqua` nutzt die mit macOS-JDKs übliche Aqua-Oberfläche; mit FlatLaf im Classpath z. B. durch
    /// `-Dswing.defaultlaf=com.formdev.flatlaf.FlatLightLaf` ersetzbar.
    static let recommendedJava8VmArgumentsForMacOS: [String] = [
        "-Dapple.laf.useScreenMenuBar=true",
        "-Dapple.awt.application.name=FS Client",
        "-Dapple.awt.application.appearance=system",
        "-Dswing.defaultlaf=com.apple.laf.AquaLookAndFeel",
    ]

    static func load() -> LauncherSettings {
        ioQueue.sync {
            let url = AppPaths.launcherConfigURL
            let base: LauncherSettings
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode(LauncherSettings.self, from: data) {
                base = decoded
            } else {
                base = LauncherSettings()
            }
            var s = base
            s.applyRecommendedMacJava8JvmArgumentsIfNeeded()
            return s
        }
    }

    /// Füllt `Java8VmArguments` nur, wenn noch keine Zeilen gespeichert sind (bestehende Konfiguration bleibt unverändert).
    mutating func applyRecommendedMacJava8JvmArgumentsIfNeeded() {
        guard Java8VmArguments.isEmpty else { return }
        Java8VmArguments = Self.recommendedJava8VmArgumentsForMacOS
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
