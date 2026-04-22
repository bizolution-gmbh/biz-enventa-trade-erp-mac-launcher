import XCTest

@testable import TradeERPLauncherLib

final class LaunchConfigurationBridgeTests: XCTestCase {
    func testEmbeddedJnlpBridgeExtractsUrlQuery() {
        let raw =
            "fsclientlauncher:jnlp?url=https%3A%2F%2Fserver.example%2Fcrm%2Fapi%2Fjnlp%3Ffile%3D1"
        let out = LaunchConfiguration.embeddedHttpURLFromLauncherJnlpBridge(raw)
        XCTAssertEqual(out, "https://server.example/crm/api/jnlp?file=1")
    }

    func testEmbeddedJnlpBridgeRejectsLaunchPath() {
        let raw = "fsclientlauncher:launch?broker=https%3A%2F%2Fx"
        XCTAssertNil(LaunchConfiguration.embeddedHttpURLFromLauncherJnlpBridge(raw))
    }
}
