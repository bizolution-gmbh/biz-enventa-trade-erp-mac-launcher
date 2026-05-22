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
    /// Download-Quellen für die mitgelieferte bzw. eigene Java-8-Laufzeit (Zulu + JavaFX); optional, Standard wie `Java8RuntimePreferences.empty`.
    var Java8RuntimePreferences: Java8RuntimePreferences?

    private static let ioQueue = DispatchQueue(label: "de.bizolution.trade-erp-launcher.settings")

    /// Mitgelieferte Standard-`-D`-Properties für **Java 8** auf macOS (Menüleiste, Anwendungsname, Darstellung, Kantenglättung).
    static let recommendedJava8VmArgumentsForMacOS: [String] = [
        "-Dapple.laf.useScreenMenuBar=true",
        "-Dapple.awt.application.name=\(LauncherProductNaming.javaAwtApplicationMenuBarName)",
        "-Dapple.awt.application.appearance=system",
        "-Dapple.awt.antialiasing=true",
        "-Dapple.awt.textantialiasing=true",
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
            if JavaRuntimeResolver.isJava8RuntimePresent() {
                s.applyRecommendedMacJava8JvmArgumentsIfNeeded()
            }
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
            // Verzeichnis-Anlage darf scheitern, wenn das Verzeichnis bereits existiert (häufiger Fall) —
            // wir werfen den Fehler bewusst nur an stderr, falls die spätere Schreib-/Encode-Phase scheitert
            // (sonst würde jeder Programmstart fälschlich eine harmlose „File exists“-Meldung zeigen).
            let directoryError: Error?
            do {
                try FileManager.default.createDirectory(
                    at: AppPaths.appDataDirectory,
                    withIntermediateDirectories: true
                )
                directoryError = nil
            } catch {
                directoryError = error
            }
            do {
                let data = try JSONEncoder().encode(self)
                try data.write(to: AppPaths.launcherConfigURL, options: .atomic)
            } catch {
                let url = AppPaths.launcherConfigURL.path
                if let directoryError {
                    fputs(
                        "TradeERPLauncher: launcherconfig.json konnte nicht gespeichert werden (\(error.localizedDescription)). Verzeichnisanlage zuvor: \(directoryError.localizedDescription). Pfad: \(url).\n",
                        stderr
                    )
                } else {
                    fputs(
                        "TradeERPLauncher: launcherconfig.json konnte nicht gespeichert werden (\(error.localizedDescription)). Pfad: \(url).\n",
                        stderr
                    )
                }
            }
        }
    }
}
