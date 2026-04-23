import XCTest
import Foundation

@testable import TradeERPLauncherLib

final class BrokerFetcherNormalizationTests: XCTestCase {
    func testBrokerRootStripsFsclientAshxBeforeAppendingJarDownload() throws {
        let base = try BrokerFetcher.normalizedBrokerURL(
            "https://server.example/MeineApp/api/fsclient.ashx?broker=1&lang=de"
        )
        let jar = base.appendingPathComponent("api").appendingPathComponent("jardownload")
        XCTAssertEqual(base.path, "/MeineApp")
        XCTAssertEqual(jar.absoluteString, "https://server.example/MeineApp/api/jardownload")
    }

    func testBrokerRootStripsJnlpAshx() throws {
        let base = try BrokerFetcher.normalizedBrokerURL(
            "https://server.example/crm/api/jnlp.ashx?file=1"
        )
        XCTAssertEqual(base.path, "/crm")
    }

    func testBrokerRootStripsPlainApiFsclient() throws {
        let base = try BrokerFetcher.normalizedBrokerURL("https://server.example/crm/api/fsclient?x=1")
        XCTAssertEqual(base.path, "/crm")
    }

    func testBrokerRootUnchangedWhenAlreadyAppRoot() throws {
        let base = try BrokerFetcher.normalizedBrokerURL("https://server.example/MeineApp")
        XCTAssertEqual(base.path, "/MeineApp")
    }
}
