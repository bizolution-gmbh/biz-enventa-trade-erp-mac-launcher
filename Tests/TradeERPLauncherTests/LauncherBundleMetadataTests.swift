import XCTest

@testable import TradeERPLauncherLib

final class LauncherBundleMetadataTests: XCTestCase {
    func testDisplayVersionWithoutTagEqualsShortVersion() {
        XCTAssertEqual(
            LauncherBundleMetadata.formatDisplayVersion(shortVersion: "4.8.0.2", preReleaseTag: nil),
            "4.8.0.2"
        )
    }

    func testDisplayVersionWithEmptyTagEqualsShortVersion() {
        XCTAssertEqual(
            LauncherBundleMetadata.formatDisplayVersion(shortVersion: "4.8.0.2", preReleaseTag: ""),
            "4.8.0.2"
        )
    }

    func testDisplayVersionWithWhitespaceOnlyTagEqualsShortVersion() {
        XCTAssertEqual(
            LauncherBundleMetadata.formatDisplayVersion(shortVersion: "4.8.0.2", preReleaseTag: "   "),
            "4.8.0.2"
        )
    }

    func testDisplayVersionWithDevTagAppendsSuffix() {
        XCTAssertEqual(
            LauncherBundleMetadata.formatDisplayVersion(shortVersion: "4.8.0.2", preReleaseTag: "dev"),
            "4.8.0.2-dev"
        )
    }

    func testDisplayVersionTrimsTagWhitespace() {
        XCTAssertEqual(
            LauncherBundleMetadata.formatDisplayVersion(shortVersion: "4.8.0.2", preReleaseTag: "  beta  "),
            "4.8.0.2-beta"
        )
    }
}
