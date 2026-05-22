import XCTest

@testable import TradeERPLauncherLib

final class HttpBrokerWarningTests: XCTestCase {
    func testHttpsRequiresNoWarning() {
        let d = HttpBrokerWarning.decide(brokerString: "https://broker.example/app", acknowledgedHosts: [])
        XCTAssertEqual(d, .noWarningNeeded)
    }

    func testFsclientLauncherUriRequiresNoWarning() {
        let d = HttpBrokerWarning.decide(
            brokerString: "fsclientlauncher:launch?broker=http%3A%2F%2Fa%2Fb",
            acknowledgedHosts: []
        )
        XCTAssertEqual(d, .noWarningNeeded)
    }

    func testEmptyBrokerStringNoWarning() {
        XCTAssertEqual(HttpBrokerWarning.decide(brokerString: "", acknowledgedHosts: []), .noWarningNeeded)
    }

    func testHttpUnknownHostTriggersWarn() {
        let d = HttpBrokerWarning.decide(brokerString: "http://intern.example/app", acknowledgedHosts: [])
        XCTAssertEqual(d, .warn(host: "intern.example"))
    }

    func testHttpHostIsLowercased() {
        let d = HttpBrokerWarning.decide(brokerString: "http://INTERN.Example/app", acknowledgedHosts: [])
        XCTAssertEqual(d, .warn(host: "intern.example"))
    }

    func testAcknowledgedHostSkipsWarning() {
        let acked: Set<String> = ["intern.example"]
        let d = HttpBrokerWarning.decide(brokerString: "http://intern.example/app", acknowledgedHosts: acked)
        XCTAssertEqual(d, .alreadyAcknowledged(host: "intern.example"))
    }

    func testHttpWithoutHostNoWarning() {
        // URL ohne Host (kommt z. B. bei kaputten Eingaben vor) — nicht warnen, darum kümmern sich
        // andere Validierungen (`BrokerFetcher.normalizedBrokerURL`).
        let d = HttpBrokerWarning.decide(brokerString: "http:///path", acknowledgedHosts: [])
        XCTAssertEqual(d, .noWarningNeeded)
    }
}

final class HttpBrokerAcknowledgedHostsStoreTests: XCTestCase {
    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "TradeERPLauncher.Tests.HttpBrokerStore." + UUID().uuidString
        // `UserDefaults(suiteName:)` legt im Standard-Plist nichts an, bis ein `set` erfolgt — sauber für Tests.
        return UserDefaults(suiteName: suiteName)!
    }

    func testStartsEmpty() {
        let d = makeIsolatedDefaults()
        XCTAssertTrue(HttpBrokerAcknowledgedHostsStore.loadAcknowledgedHosts(from: d).isEmpty)
    }

    func testAcknowledgePersistsAndDeduplicates() {
        let d = makeIsolatedDefaults()
        HttpBrokerAcknowledgedHostsStore.acknowledge(host: "intern.example", in: d)
        HttpBrokerAcknowledgedHostsStore.acknowledge(host: "INTERN.example", in: d)
        let loaded = HttpBrokerAcknowledgedHostsStore.loadAcknowledgedHosts(from: d)
        XCTAssertEqual(loaded, ["intern.example"])
    }

    func testIgnoresEmptyHost() {
        let d = makeIsolatedDefaults()
        HttpBrokerAcknowledgedHostsStore.acknowledge(host: "  ", in: d)
        XCTAssertTrue(HttpBrokerAcknowledgedHostsStore.loadAcknowledgedHosts(from: d).isEmpty)
    }
}
