import XCTest

@testable import TradeERPLauncherLib

final class LaunchHTTPUserInputURLParsingTests: XCTestCase {
    func testSanitizeFullWidthColonSlash() {
        let raw = "https\u{FF1A}\u{FF0F}\u{FF0F}example.com/api/fsclient?x=1"
        let s = sanitizeHttpURLUserInput(raw)
        XCTAssertTrue(s.hasPrefix("https://example.com/"))
    }

    func testStripLeadingGarbageBeforeHttp() {
        let raw = "Siehe Link https://host/app/api/fsclient?broker=1"
        let t = stripLeadingGarbageBeforeHTTPScheme(raw)
        XCTAssertTrue(t.hasPrefix("https://host/"))
    }

    func testStripLeadingDoesNotBreakLauncherScheme() {
        let raw = "fsclientlauncher:launch?broker=https%3A%2F%2Fx"
        XCTAssertEqual(stripLeadingGarbageBeforeHTTPScheme(raw), raw)
    }

    func testParseLenientHTTPURLWithEncodedQuery() {
        let u = parseLenientHTTPURL("https://host/path?a=b&c=d e")
        XCTAssertNotNil(u)
        XCTAssertEqual(u?.host, "host")
    }
}
