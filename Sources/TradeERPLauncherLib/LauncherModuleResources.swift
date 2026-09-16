import Foundation

/// SPM-Ressourcen der Lib **ohne** den generierten `Bundle.module`-Accessor.
///
/// `Bundle.module` ruft `fatalError` auf, wenn `TradeERPLauncher_TradeERPLauncherLib.bundle`
/// nicht am vom Compiler erwarteten Ort liegt. `swift build` sucht u. a. neben der `.app`-Wurzel
/// oder unter einem hart kodierten `.build`-Pfad der Build-Maschine — beides fehlt in einer
/// aus dem DMG kopierten App. Die SVGs unter `Contents/Resources/` allein helfen dann nicht,
/// weil der Accessor abstürzt, bevor `Bundle.main` ausgewertet wird.
///
/// `swift test` setzt `Bundle.main` auf Xcodes `xctest`; die Lib ist statisch in das `.xctest`
/// gelinkt, daher `Bundle(for:)` statt `Bundle.main` für den Nachbarpfad des SPM-Bundles.
enum LauncherModuleResources {
    static let bundleFileName = "TradeERPLauncher_TradeERPLauncherLib.bundle"

    private final class BundleToken {}

    static var bundle: Bundle {
        for url in candidateBundleURLs where FileManager.default.fileExists(atPath: url.path) {
            if let found = Bundle(url: url) { return found }
        }
        return Bundle.main
    }

    static var resourceURL: URL? {
        bundle.resourceURL ?? Bundle.main.resourceURL
    }

    static func url(forResource name: String, withExtension ext: String?) -> URL? {
        bundle.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }

    static var candidateBundleURLs: [URL] {
        let file = bundleFileName
        var urls: [URL] = []
        urls.append(contentsOf: locations(relativeTo: Bundle.main, file: file))
        urls.append(contentsOf: locations(relativeTo: Bundle(for: BundleToken.self), file: file))
        return urls
    }

    private static func locations(relativeTo host: Bundle, file: String) -> [URL] {
        var urls: [URL] = [
            host.bundleURL.appendingPathComponent(file),
            host.bundleURL.deletingLastPathComponent().appendingPathComponent(file),
        ]
        if let resources = host.resourceURL {
            urls.append(resources.appendingPathComponent(file))
        }
        if let exeDir = host.executableURL?.deletingLastPathComponent() {
            urls.append(exeDir.appendingPathComponent(file))
        }
        return urls
    }
}
