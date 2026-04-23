import Foundation

/// Ergebnis von `Java8RuntimeDownloadResolver.resolve` — direkter Download (ohne Azul-Metadaten-API).
struct Java8RuntimeResolvedSource: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case builtin(catalogId: String)
        case custom(entryId: String)
    }

    var kind: Kind
    var downloadURL: URL
    var hashType: Java8RuntimeHashType
    /// Bereinigter Hex-String (Kleinbuchstaben, ohne Leerzeichen); bei `hashType == .none` leer.
    var expectedHashHex: String
}

enum Java8RuntimeDownloadResolver {
    private static func archString(for hardware: MacHardwareArchitecture) -> String {
        switch hardware {
        case .appleSiliconArm64: return "arm64"
        case .intelX86_64: return "x86_64"
        }
    }

    private static func normalizeHex(_ s: String) -> String {
        s.lowercased().filter { !$0.isWhitespace }
    }

    private static func normalizedDownloadURL(_ raw: String) -> URL? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: t), BrokerFetcher.isPermittedOutboundDownloadURL(u) else { return nil }
        return u
    }

    private static func isValidHashConfiguration(_ type: Java8RuntimeHashType, hex: String) -> Bool {
        switch type {
        case .none: return true
        case .sha256, .sha512: return !normalizeHex(hex).isEmpty
        }
    }

    /// Aktive **Custom**-Einträge (Reihenfolge), sonst aktiver **Built-in**-Katalogeintrag für `hardware`.
    static func resolve(settings: LauncherSettings, hardware: MacHardwareArchitecture) -> Java8RuntimeResolvedSource? {
        let arch = archString(for: hardware)
        let prefs = settings.Java8RuntimePreferences ?? .empty

        for e in prefs.CustomEntries where e.Active && e.Architecture == arch {
            guard let u = normalizedDownloadURL(e.DownloadUrl) else { continue }
            guard isValidHashConfiguration(e.HashType, hex: e.ExpectedHash) else { continue }
            return Java8RuntimeResolvedSource(
                kind: .custom(entryId: e.Id),
                downloadURL: u,
                hashType: e.HashType,
                expectedHashHex: normalizeHex(e.ExpectedHash)
            )
        }

        guard let built = Java8RuntimeCatalogLoader.loadCatalogFile()?.entries.first(where: { $0.architecture == arch }) else {
            return nil
        }
        guard prefs.effectiveBuiltInActive(catalogEntryId: built.id, catalogDefault: built.defaultActive) else { return nil }
        guard let u = normalizedDownloadURL(built.downloadUrl) else { return nil }
        guard isValidHashConfiguration(built.hashType, hex: built.expectedHash) else { return nil }
        return Java8RuntimeResolvedSource(
            kind: .builtin(catalogId: built.id),
            downloadURL: u,
            hashType: built.hashType,
            expectedHashHex: normalizeHex(built.expectedHash)
        )
    }

    /// Nur **mitgelieferte** Katalog-Quelle für diese Hardware (aktiv laut `prefs`, technisch gültig) — unabhängig von Custom-Einträgen.
    static func resolveBuiltinOnly(java8Preferences: Java8RuntimePreferences, hardware: MacHardwareArchitecture) -> Java8RuntimeResolvedSource? {
        let arch = archString(for: hardware)
        guard let built = Java8RuntimeCatalogLoader.loadCatalogFile()?.entries.first(where: { $0.architecture == arch }) else {
            return nil
        }
        guard java8Preferences.effectiveBuiltInActive(catalogEntryId: built.id, catalogDefault: built.defaultActive) else { return nil }
        guard let u = normalizedDownloadURL(built.downloadUrl) else { return nil }
        guard isValidHashConfiguration(built.hashType, hex: built.expectedHash) else { return nil }
        return Java8RuntimeResolvedSource(
            kind: .builtin(catalogId: built.id),
            downloadURL: u,
            hashType: built.hashType,
            expectedHashHex: normalizeHex(built.expectedHash)
        )
    }

    /// Nur **dieser** Custom-Eintrag, sofern aktiv, Architektur passt und URL/Hash gültig sind.
    static func resolveSingleCustom(entry: Java8RuntimeCustomEntry, hardware: MacHardwareArchitecture) -> Java8RuntimeResolvedSource? {
        let arch = archString(for: hardware)
        guard entry.Active && entry.Architecture == arch else { return nil }
        guard let u = normalizedDownloadURL(entry.DownloadUrl) else { return nil }
        guard isValidHashConfiguration(entry.HashType, hex: entry.ExpectedHash) else { return nil }
        return Java8RuntimeResolvedSource(
            kind: .custom(entryId: entry.Id),
            downloadURL: u,
            hashType: entry.HashType,
            expectedHashHex: normalizeHex(entry.ExpectedHash)
        )
    }
}
