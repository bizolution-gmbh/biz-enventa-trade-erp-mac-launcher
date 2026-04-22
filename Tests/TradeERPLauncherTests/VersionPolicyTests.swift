import XCTest

@testable import TradeERPLauncherLib

final class VersionPolicyTests: XCTestCase {
    func testSemanticParseRequiresAtLeastTwoComponents() {
        XCTAssertNil(VersionPolicy.Semantic.parse("1"))
        XCTAssertNil(VersionPolicy.Semantic.parse(""))
        XCTAssertNotNil(VersionPolicy.Semantic.parse("1.2"))
        XCTAssertNotNil(VersionPolicy.Semantic.parse("4.8.0.1"))
    }

    func testEvaluateMissingMinVersionIsOk() {
        let installed = VersionPolicy.Semantic(major: 4, minor: 8, build: 0, revision: 0)
        if case .ok = VersionPolicy.evaluateLauncherMinVersion(nil, installed: installed) {} else {
            XCTFail("expected .ok")
        }
        if case .ok = VersionPolicy.evaluateLauncherMinVersion("  ", installed: installed) {} else {
            XCTFail("expected .ok")
        }
    }

    func testEvaluateInstalledOlderMajorMinorMustUpdate() {
        let installed = VersionPolicy.Semantic(major: 1, minor: 0, build: 0, revision: 0)
        guard case let .mustUpdate(req, ins) = VersionPolicy.evaluateLauncherMinVersion("2.0", installed: installed) else {
            return XCTFail("expected .mustUpdate")
        }
        XCTAssertEqual(req, "2.0")
        // `format` gibt bei gesetztem build/revision (≥ 0) vier Komponenten aus — siehe `VersionPolicy.format`.
        XCTAssertEqual(ins, "1.0.0.0")
    }

    func testEvaluateSameMajorMinorButLowerPatchShouldAsk() {
        let installed = VersionPolicy.Semantic(major: 4, minor: 8, build: 0, revision: 0)
        guard case let .shouldAskToContinue(req, _) = VersionPolicy.evaluateLauncherMinVersion("4.8.0.1", installed: installed)
        else {
            return XCTFail("expected .shouldAskToContinue")
        }
        XCTAssertEqual(req, "4.8.0.1")
    }

    func testEvaluateInstalledMeetsMinIsOk() {
        let installed = VersionPolicy.Semantic(major: 4, minor: 8, build: 1, revision: 0)
        if case .ok = VersionPolicy.evaluateLauncherMinVersion("4.8.0.0", installed: installed) {} else {
            XCTFail("expected .ok")
        }
    }
}
