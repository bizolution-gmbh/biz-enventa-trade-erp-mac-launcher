import Foundation

enum VersionGate {
    case ok
    case mustUpdate(required: String, installed: String)
    case shouldAskToContinue(required: String, installed: String)
}

/// Mindest-Launcher-Version (`LauncherMinVersion`) — wie `LaunchService.ValidateBrokerInfo`.
enum VersionPolicy {
    struct Semantic: Comparable {
        var major: Int
        var minor: Int
        var build: Int
        var revision: Int

        static func parse(_ s: String) -> Semantic? {
            let parts = s.split(separator: ".").map { String($0) }.compactMap { Int($0) }
            guard parts.count >= 2 else { return nil }
            return Semantic(
                major: parts[0],
                minor: parts[1],
                build: parts.count > 2 ? parts[2] : -1,
                revision: parts.count > 3 ? parts[3] : -1
            )
        }

        func padded() -> Semantic {
            if build < 0, revision < 0 { return Semantic(major: major, minor: minor, build: 0, revision: 0) }
            if revision < 0 { return Semantic(major: major, minor: minor, build: build, revision: 0) }
            return self
        }

        static func < (lhs: Semantic, rhs: Semantic) -> Bool {
            if lhs.major != rhs.major { return lhs.major < rhs.major }
            if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
            if lhs.build != rhs.build { return lhs.build < rhs.build }
            return lhs.revision < rhs.revision
        }
    }

    /// `CFBundleShortVersionString` der gebauten macOS-App bzw. Fallback wie die Windows-FileVersion.
    static func installedLauncherSemantic() -> Semantic {
        if let s = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            let v = Semantic.parse(s) {
            return v
        }
        return Semantic(major: 4, minor: 8, build: 0, revision: 0)
    }

    static func evaluateLauncherMinVersion(_ minVersionString: String?) -> VersionGate {
        evaluateLauncherMinVersion(minVersionString, installed: installedLauncherSemantic())
    }

    /// Für Unit-Tests: installierte Version explizit setzen (Produktion nutzt `installedLauncherSemantic()`).
    static func evaluateLauncherMinVersion(_ minVersionString: String?, installed installedFile: Semantic) -> VersionGate {
        guard let raw = minVersionString?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
            let required = Semantic.parse(raw) else { return .ok }
        let installedMM = Semantic(major: installedFile.major, minor: installedFile.minor, build: -1, revision: -1)
        let requiredMM = Semantic(major: required.major, minor: required.minor, build: -1, revision: -1)
        if installedMM < requiredMM {
            return .mustUpdate(required: raw, installed: format(installedFile))
        }
        if installedFile.padded() < required.padded() {
            return .shouldAskToContinue(required: raw, installed: format(installedFile))
        }
        return .ok
    }

    private static func format(_ v: Semantic) -> String {
        if v.build < 0 { return "\(v.major).\(v.minor)" }
        if v.revision < 0 { return "\(v.major).\(v.minor).\(v.build)" }
        return "\(v.major).\(v.minor).\(v.build).\(v.revision)"
    }
}
