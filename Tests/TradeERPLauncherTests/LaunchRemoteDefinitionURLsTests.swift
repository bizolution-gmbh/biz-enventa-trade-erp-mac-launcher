import XCTest

@testable import TradeERPLauncherLib

final class LaunchRemoteDefinitionURLsTests: XCTestCase {
    func testRemoteClientDefinitionApiURL() {
        let u = remoteClientDefinitionApiURL(from: "https://srv/crm/api/fsclient?lang=de")
        XCTAssertNotNil(u)
        XCTAssertTrue(u?.absoluteString.contains("/api/fsclient") ?? false)
    }

    func testJnlpRemoteAPIURL() {
        let u = jnlpRemoteAPIURL(from: "https://srv/crm/api/jnlp?file=1")
        XCTAssertNotNil(u)
    }

    func testRemoteDefinitionDocumentURLDetectsFsclientInPath() {
        let u = remoteDefinitionDocumentURL(from: "https://host/x/fsclient.json")
        XCTAssertNotNil(u)
    }
}
