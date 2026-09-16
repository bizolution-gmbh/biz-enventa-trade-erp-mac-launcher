import XCTest

@testable import TradeERPLauncherLib

final class Java8RuntimeCatalogTests: XCTestCase {
    func testBuiltinCatalogPinsZulu896CaFxForBothArchitectures() throws {
        let file = try XCTUnwrap(Java8RuntimeCatalogLoader.loadCatalogFile())
        XCTAssertEqual(file.entries.count, 2)

        let arm = try XCTUnwrap(file.entries.first { $0.architecture == "arm64" })
        XCTAssertEqual(arm.id, "zulu8-fx-builtin-aarch64")
        XCTAssertEqual(
            arm.downloadUrl,
            "https://cdn.azul.com/zulu/bin/zulu8.96.0.205-ca-fx-jdk8.0.504-macosx_aarch64.tar.gz"
        )
        XCTAssertEqual(arm.hashType, .sha256)
        XCTAssertEqual(arm.expectedHash, "300feca3a32385d5181021c30ffd88aeaa392c83e21565ca72759f73f26d8770")

        let intel = try XCTUnwrap(file.entries.first { $0.architecture == "x86_64" })
        XCTAssertEqual(intel.id, "zulu8-fx-builtin-x86_64")
        XCTAssertEqual(
            intel.downloadUrl,
            "https://cdn.azul.com/zulu/bin/zulu8.96.0.205-ca-fx-jdk8.0.504-macosx_x64.tar.gz"
        )
        XCTAssertEqual(intel.hashType, .sha256)
        XCTAssertEqual(intel.expectedHash, "aa4a016b8ef8607ea8bd106feb663c11a9ccfe0bbb7b6c29ee62493fd329fb23")
    }
}
