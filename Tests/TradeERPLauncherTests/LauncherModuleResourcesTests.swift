import XCTest

@testable import TradeERPLauncherLib

final class LauncherModuleResourcesTests: XCTestCase {
    func testJava8CatalogLoadsWithoutBundleModule() {
        let file = Java8RuntimeCatalogLoader.loadCatalogFile()
        XCTAssertNotNil(file, "Java8RuntimeCatalog.json muss über LauncherModuleResources gefunden werden")
        XCTAssertFalse(file?.entries.isEmpty ?? true)
    }

    func testFullLogoSVGLoadsBundledFileNotEmbeddedPlaceholder() {
        let svg = BizolutionSVGSource.fullLogoSVGForRuntime(isDark: false)
        XCTAssertFalse(
            svg.contains("font-family=\"system-ui"),
            "Platzhalter-SVG bedeutet, dass die gebündelte Logo-Datei nicht geladen wurde"
        )
        XCTAssertGreaterThan(svg.count, 400)
    }

    func testCandidateBundleURLsFindExistingSpmBundle() {
        let existing = LauncherModuleResources.candidateBundleURLs.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        XCTAssertFalse(existing.isEmpty, "mindestens ein SPM-Resource-Bundle-Pfad muss existieren")
    }
}
