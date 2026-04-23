import Foundation

/// Erwartete Prüfsumme nach Download (nur bei gesetztem `expectedHash`).
enum Java8RuntimeHashType: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case sha256
    case sha512
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none: "Keine Prüfung"
        case .sha256: "SHA-256"
        case .sha512: "SHA-512"
        }
    }
}

/// Ein Eintrag aus dem **mitgelieferten** Katalog (`Java8RuntimeCatalog.json`) — nicht in der UI editierbar.
struct Java8BuiltinCatalogEntry: Codable, Sendable, Equatable {
    var id: String
    var label: String
    var architecture: String
    var downloadUrl: String
    var hashType: Java8RuntimeHashType
    var expectedHash: String
    var defaultActive: Bool
}

struct Java8RuntimeCatalogFile: Codable, Sendable {
    var catalogVersion: Int
    var entries: [Java8BuiltinCatalogEntry]
}

/// Nutzerdefinierte Java-8-Download-Quelle (editierbar). JSON-Schlüssel wie übrige Launcher-Konfiguration (PascalCase).
struct Java8RuntimeCustomEntry: Codable, Sendable, Equatable, Identifiable {
    var Id: String
    var Label: String
    var Architecture: String
    var DownloadUrl: String
    var HashType: Java8RuntimeHashType
    /// Hex-String; bei `HashType == .none` leer lassen.
    var ExpectedHash: String
    var Active: Bool

    var id: String { Id }
}

/// Gespeichert in `launcherconfig.json` (optional).
struct Java8RuntimePreferences: Codable, Equatable, Sendable {
    /// Überschreibt `defaultActive` aus dem Katalog nur für die angegebenen Built-in-`id`.
    var BuiltInActiveById: [String: Bool]?
    var CustomEntries: [Java8RuntimeCustomEntry]

    static let empty = Java8RuntimePreferences(BuiltInActiveById: nil, CustomEntries: [])

    func effectiveBuiltInActive(catalogEntryId: String, catalogDefault: Bool) -> Bool {
        if let m = BuiltInActiveById, let v = m[catalogEntryId] { return v }
        return catalogDefault
    }
}
