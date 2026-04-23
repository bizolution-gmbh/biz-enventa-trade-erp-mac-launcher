import Darwin
import Foundation

/// Physische Mac-Hardware (nicht die Architektur des laufenden Prozesses — relevant für Zulu-JDK-Auswahl).
enum MacHardwareArchitecture: String, Sendable {
    case appleSiliconArm64
    case intelX86_64

    /// `hw.machine`: typischerweise `arm64` bzw. `x86_64`.
    static func current() -> MacHardwareArchitecture? {
        let name = hwMachineString().lowercased()
        if name == "arm64" { return .appleSiliconArm64 }
        if name == "x86_64" { return .intelX86_64 }
        return nil
    }

    private static func hwMachineString() -> String {
        var size: Int = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 1 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        let st = sysctlbyname("hw.machine", &buf, &size, nil, 0)
        guard st == 0 else { return "" }
        return String(cString: buf)
    }

    var userFacingShortLabel: String {
        switch self {
        case .appleSiliconArm64: "Apple Silicon (arm64)"
        case .intelX86_64: "Intel (x86_64)"
        }
    }

    /// Azul-Metadaten-API: `arch`-Parameter (siehe api.azul.com).
    var azulMetadataArchParameter: String {
        switch self {
        case .appleSiliconArm64: "arm64"
        case .intelX86_64: "x86"
        }
    }

    /// Zielordnername unter `…/runtimes/jre8/` (analog zu früherem Skript).
    var downloadedJdkBundleFolderName: String {
        switch self {
        case .appleSiliconArm64: "zulu8-fx-macos-aarch64.jdk"
        case .intelX86_64: "zulu8-fx-macos-x64.jdk"
        }
    }
}
