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

    func testBrokerBaseStringForApplicationIconFromLauncherUri() {
        let uri =
            "fsclientlauncher:launch?title=ENV-P-BIZ&broker=http%3A%2F%2Fsrv-enventa01.hq.bizolution.de%2FENV-P-BIZ%2F&theme=DefaultID&language=de&lookAndFeel=1&noDomainAuth=false"
        let b = LaunchConfiguration.brokerBaseStringForApplicationIcon(shortcutTarget: uri, backingFilePath: nil)
        XCTAssertNotNil(b)
        XCTAssertTrue(b!.contains("srv-enventa01.hq.bizolution.de"))
        XCTAssertTrue(b!.contains("ENV-P-BIZ"))
    }
}
