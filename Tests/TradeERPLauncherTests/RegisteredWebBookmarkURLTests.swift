import XCTest

@testable import TradeERPLauncherLib

final class RegisteredWebBookmarkURLTests: XCTestCase {
    func testValidHttpsWithPath() {
        XCTAssertTrue(RegisteredApplicationsStore.isValidWebBookmarkURL("https://example.com/webapp/"))
    }

    func testValidHttpWithPort() {
        XCTAssertTrue(RegisteredApplicationsStore.isValidWebBookmarkURL("http://intranet.local:8080/portal"))
    }

    func testRejectsFtp() {
        XCTAssertFalse(RegisteredApplicationsStore.isValidWebBookmarkURL("ftp://files.example/pub"))
    }

    func testRejectsJavaScript() {
        XCTAssertFalse(RegisteredApplicationsStore.isValidWebBookmarkURL("javascript:alert(1)"))
    }

    func testRejectsEmpty() {
        XCTAssertFalse(RegisteredApplicationsStore.isValidWebBookmarkURL(""))
        XCTAssertFalse(RegisteredApplicationsStore.isValidWebBookmarkURL("   "))
    }

    func testLegacyRegisteredApplicationRecordJSONDecodesAsLauncher() throws {
        let json = """
        {"id":"00000000-0000-4000-8000-000000000001","path":"https://h/x","importedFilePath":null,"displayName":"X","iconContentHash":null}
        """.data(using: .utf8)!
        let rec = try JSONDecoder().decode(RegisteredApplicationRecord.self, from: json)
        XCTAssertEqual(rec.targetKind, .launcher)
    }
}
