import Foundation

enum Java8RuntimeCatalogLoader {
    private static var cachedFile: Java8RuntimeCatalogFile?
    private static let lock = NSLock()

    /// `arm64` bzw. `x86_64` (wie `hw.machine`).
    static func hostArchitectureString() -> String {
        switch MacHardwareArchitecture.current() {
        case .appleSiliconArm64: return "arm64"
        case .intelX86_64: return "x86_64"
        case .none: return "arm64"
        }
    }

    static func loadCatalogFile() -> Java8RuntimeCatalogFile? {
        lock.lock()
        defer { lock.unlock() }
        if let c = cachedFile { return c }
        guard let url = Bundle.module.url(forResource: "Java8RuntimeCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(Java8RuntimeCatalogFile.self, from: data) else {
            return nil
        }
        cachedFile = file
        return file
    }

    /// Built-in-Eintrag für die aktuelle Hardware, falls im Katalog vorhanden.
    static func builtinEntryForCurrentHost() -> Java8BuiltinCatalogEntry? {
        let arch = hostArchitectureString()
        return loadCatalogFile()?.entries.first { $0.architecture == arch }
    }

    static func allBuiltins() -> [Java8BuiltinCatalogEntry] {
        loadCatalogFile()?.entries ?? []
    }
}

extension Java8RuntimeCustomEntry {
    static func newDraft() -> Java8RuntimeCustomEntry {
        Java8RuntimeCustomEntry(
            Id: UUID().uuidString,
            Label: "",
            Architecture: Java8RuntimeCatalogLoader.hostArchitectureString(),
            DownloadUrl: "",
            HashType: .sha256,
            ExpectedHash: "",
            Active: true
        )
    }
}
