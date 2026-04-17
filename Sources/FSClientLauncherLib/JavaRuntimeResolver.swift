import Foundation

/// Entspricht `JavaRuntimeService` / `JavaRuntime` der Windows-App (mit korrigierter VM-Args-Zuordnung für Java 11 vs. 21).
enum JavaRuntimeResolver {
    struct Resolved: Sendable {
        let javaExecutable: URL
        let vmArguments: [String]
    }

    static func pickJavaVersion(javaVersions: [ApiJavaVersion]?, settings: LauncherSettings) throws -> Int {
        let supported = [8, 11, 21]
        if javaVersions == nil || javaVersions!.isEmpty {
            return 8
        }
        let list = javaVersions!
        let filtered: [ApiJavaVersion]
        switch settings.UseJavaVersion {
        case .Recommended:
            filtered = list.filter { $0.ReleaseState == .Recommended }
        case .Supported:
            filtered = list.filter { $0.ReleaseState == .Recommended || $0.ReleaseState == .Supported }
        case .Experimental:
            filtered = list
        }
        guard let best = filtered
            .filter({ supported.contains($0.Version) })
            .sorted(by: { $0.Version > $1.Version })
            .first else {
            throw LaunchError.noJavaVersion
        }
        return best.Version
    }

    static func resolveRuntime(version: Int, settings: LauncherSettings) throws -> Resolved {
        switch version {
        case 8:
            let java = try findJava8()
            return Resolved(javaExecutable: java, vmArguments: settings.Java8VmArguments)
        case 11:
            let java = try findJDK(version: 11)
            return Resolved(javaExecutable: java, vmArguments: settings.Java11VmArguments)
        case 21:
            let java = try findJDK(version: 21)
            return Resolved(javaExecutable: java, vmArguments: settings.Java21VmArguments)
        default:
            throw LaunchError.noJavaVersion
        }
    }

    // MARK: - Verfügbarkeit (Einstellungen-UI, ohne Start)

    static func isJava8RuntimePresent() -> Bool {
        locateJava8ExecutableIfPresent() != nil
    }

    static func isJava11RuntimePresent() -> Bool {
        locateJDKExecutableIfPresent(version: 11) != nil
    }

    static func isJava21RuntimePresent() -> Bool {
        locateJDKExecutableIfPresent(version: 21) != nil
    }

    private static func locateJava8ExecutableIfPresent() -> URL? {
        if let override = ProcessInfo.processInfo.environment["FSCL_JRE8"], !override.isEmpty {
            let home = URL(fileURLWithPath: override, isDirectory: true)
            let java = home.appendingPathComponent("bin/java")
            guard FileManager.default.isExecutableFile(atPath: java.path) else { return nil }
            return java
        }
        let root = AppPaths.launcherRuntimeBaseDirectory.appendingPathComponent("jre8", isDirectory: true)
        let fm = FileManager.default
        guard let subs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return findJavaRecursively(under: root)
        }
        for sub in subs where sub.lastPathComponent.lowercased().hasPrefix("update") || sub.lastPathComponent.contains(".") {
            let java = sub.appendingPathComponent("bin/java")
            if fm.isExecutableFile(atPath: java.path) { return java }
        }
        return findJavaRecursively(under: root)
    }

    private static func locateJDKExecutableIfPresent(version: Int) -> URL? {
        let envKey = "FSCL_JDK\(version)"
        if let override = ProcessInfo.processInfo.environment[envKey], !override.isEmpty {
            let home = URL(fileURLWithPath: override, isDirectory: true)
            let java = home.appendingPathComponent("bin/java")
            guard FileManager.default.isExecutableFile(atPath: java.path) else { return nil }
            return java
        }
        let root = AppPaths.launcherRuntimeBaseDirectory.appendingPathComponent("jdk\(version)", isDirectory: true)
        return findJavaRecursively(under: root)
    }

    static func readJvmArchitecture(javaExecutable: URL) -> String? {
        let p = Process()
        p.executableURL = javaExecutable
        p.arguments = ["-XshowSettings:properties", "-version"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
        } catch {
            return nil
        }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("os.arch = ") {
                return String(t.dropFirst("os.arch = ".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    static func normalizedBrokerArchitecture(fromJvmOsArch: String?) -> String? {
        guard let r = fromJvmOsArch?.lowercased(), !r.isEmpty else { return nil }
        switch r {
        case "x86_64", "amd64": return "amd64"
        case "x86", "i386": return "x86"
        case "aarch64", "arm64": return "aarch64"
        default: return r
        }
    }

    private static func findJDK(version: Int) throws -> URL {
        let envKey = "FSCL_JDK\(version)"
        let root = AppPaths.launcherRuntimeBaseDirectory.appendingPathComponent("jdk\(version)", isDirectory: true)
        guard let java = locateJDKExecutableIfPresent(version: version) else {
            if let override = ProcessInfo.processInfo.environment[envKey], !override.isEmpty {
                throw LaunchError.javaHomeMissing(
                    "Umgebungsvariable \(envKey) zeigt auf kein gültiges JDK (erwartet bin/java)."
                )
            }
            throw LaunchError.javaHomeMissing(
                "Kein eingebettetes JDK \(version) unter \(root.path) gefunden. Legen Sie z. B. ein Temurin-JDK dort ab oder setzen Sie \(envKey)."
            )
        }
        return java
    }

    private static func findJava8() throws -> URL {
        let root = AppPaths.launcherRuntimeBaseDirectory.appendingPathComponent("jre8", isDirectory: true)
        guard let java = locateJava8ExecutableIfPresent() else {
            if let override = ProcessInfo.processInfo.environment["FSCL_JRE8"], !override.isEmpty {
                throw LaunchError.javaHomeMissing("FSCL_JRE8 ist kein gültiges JRE 8 (bin/java fehlt).")
            }
            if (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) == nil {
                throw LaunchError.javaHomeMissing("Kein JRE 8 unter \(root.path). Setzen Sie FSCL_JRE8 oder liefern Sie jre8/ mit.")
            }
            throw LaunchError.javaHomeMissing("Kein JRE 8 unter \(root.path) gefunden.")
        }
        return java
    }

    private static func findJavaRecursively(under root: URL) -> URL? {
        let fm = FileManager.default
        guard let subs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return nil }
        for sub in subs {
            let macHome = sub.appendingPathComponent("Contents/Home")
            let candidates = [macHome, sub]
            for home in candidates {
                let java = home.appendingPathComponent("bin/java")
                if fm.isExecutableFile(atPath: java.path) { return java }
            }
        }
        return nil
    }
}
