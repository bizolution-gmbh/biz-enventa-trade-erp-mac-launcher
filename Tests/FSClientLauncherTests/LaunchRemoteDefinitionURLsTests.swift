import XCTest

@testable import FSClientLauncherLib

final class LaunchRemoteDefinitionURLsTests: XCTestCase {
    func testRemoteFsClientDefinitionApiURL() {
        let u = remoteFsClientDefinitionApiURL(from: "https://srv/crm/api/fsclient?lang=de")
        XCTAssertNotNil(u)
        XCTAssertTrue(u?.absoluteString.contains("/api/fsclient") ?? false)
    }

    func testJnlpRemoteAPIURL() {
        let u = jnlpRemoteAPIURL(from: "https://srv/crm/api/jnlp?file=1")
        XCTAssertNotNil(u)
    }

    func testFsclientRemoteAPIURLDetectsFsclientInPath() {
        let u = fsclientRemoteAPIURL(from: "https://host/x/fsclient.json")
        XCTAssertNotNil(u)
    }
}
