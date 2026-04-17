import Foundation

/// Dekodiert Broker-JSON unabhängig von PascalCase / camelCase (häufig bei ASP.NET / Newtonsoft).
enum JSONFlexible {
    private static func normalizeKey(_ key: String) -> String {
        key.lowercased()
    }

    private static func pick(_ dict: [String: Any], _ names: [String]) -> Any? {
        let map = Dictionary(uniqueKeysWithValues: dict.map { (normalizeKey($0.key), $0.value) })
        for n in names {
            if let v = map[normalizeKey(n)] { return v }
        }
        return nil
    }

    /// Newtonsoft serialisiert C#-Enums oft als **Zahl** (`0`/`1`/`2`); Strings können abweichende Groß-/Kleinschreibung haben.
    private static func decodeJavaReleaseState(from raw: Any?) -> JavaReleaseState {
        if let s = raw as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if let exact = JavaReleaseState(rawValue: t) { return exact }
            if let cap = JavaReleaseState(rawValue: t.capitalized) { return cap }
            switch t.lowercased() {
            case "supported": return .Supported
            case "experimental": return .Experimental
            case "recommended": return .Recommended
            default: break
            }
        }
        if let n = raw as? NSNumber {
            switch n.intValue {
            case 1: return .Supported
            case 2: return .Experimental
            default: return .Recommended
            }
        }
        return .Recommended
    }

    static func decodeJarDownload(data: Data) throws -> ApiJarDownload {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let fsVersion = pick(root, ["FsVersion", "fsVersion"]) as? String
        let launcherMin = pick(root, ["LauncherMinVersion", "launcherMinVersion"]) as? String
        let devBroker: Bool? = {
            if let b = pick(root, ["DevBroker", "devBroker"]) as? Bool { return b }
            if let s = pick(root, ["DevBroker", "devBroker"]) as? String {
                return (s as NSString).boolValue
            }
            return nil
        }()
        let mainClass = pick(root, ["MainClass", "mainClass"]) as? String
        let splash = pick(root, ["SplashImage", "splashImage"]) as? String
        let javaProps = pick(root, ["JavaProperties", "javaProperties"]) as? [String] ?? []
        let javaVersionsArr = pick(root, ["JavaVersions", "javaVersions"]) as? [[String: Any]] ?? []
        let jarArr = pick(root, ["JarFiles", "jarFiles"]) as? [[String: Any]] ?? []

        let javaVersions: [ApiJavaVersion] = javaVersionsArr.compactMap { j in
            guard let v = pick(j, ["Version", "version"]) as? Int
                ?? (pick(j, ["Version", "version"]) as? NSNumber)?.intValue else { return nil }
            let state = decodeJavaReleaseState(from: pick(j, ["ReleaseState", "releaseState"]))
            return ApiJavaVersion(Version: v, ReleaseState: state)
        }

        let jarFiles: [ApiJarFile] = jarArr.map { decodeJarFile(dict: $0) }

        return ApiJarDownload(
            FsVersion: fsVersion,
            LauncherMinVersion: launcherMin,
            JavaVersions: javaVersions.isEmpty ? nil : javaVersions,
            DevBroker: devBroker,
            MainClass: mainClass,
            SplashImage: splash,
            JarFiles: jarFiles.isEmpty ? nil : jarFiles,
            JavaProperties: javaProps.isEmpty ? nil : javaProps
        )
    }

    private static func decodeJarFile(dict: [String: Any]) -> ApiJarFile {
        let href = (pick(dict, ["Href", "href"]) as? String) ?? ""
        let sha1 = (pick(dict, ["Sha1", "sha1"]) as? String) ?? ""
        let mainVal: String?
        if let s = pick(dict, ["Main", "main"]) as? String {
            mainVal = s
        } else if let n = pick(dict, ["Main", "main"]) as? NSNumber {
            mainVal = n.stringValue
        } else {
            mainVal = nil
        }
        let os = pick(dict, ["Os", "os"]) as? String
        let arch = pick(dict, ["Architecture", "architecture"]) as? String
        let nativeVal: String?
        if let s = pick(dict, ["NativeLib", "nativeLib"]) as? String {
            nativeVal = s
        } else if let n = pick(dict, ["NativeLib", "nativeLib"]) as? NSNumber {
            nativeVal = n.stringValue
        } else {
            nativeVal = nil
        }
        let size = (pick(dict, ["Size", "size"]) as? NSNumber)?.int64Value
        return ApiJarFile(
            Href: href,
            Sha1: sha1,
            main: mainVal,
            Os: os,
            Architecture: arch,
            nativeLib: nativeVal,
            Size: size
        )
    }
}
