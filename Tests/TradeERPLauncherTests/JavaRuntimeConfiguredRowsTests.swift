import XCTest
@testable import TradeERPLauncherLib

final class JavaRuntimeConfiguredRowsTests: XCTestCase {
    func testConfiguredRowsCoverEightElevenTwentyOne() {
        let rows = JavaRuntimeResolver.javaRuntimeConfiguredRows()
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(Set(rows.map(\.majorVersion)), [8, 11, 21])
    }

    func testFsclProcessMirrorListsThreeVariables() {
        let lines = JavaRuntimeResolver.fsclEnvironmentProcessMirrorLines()
        XCTAssertEqual(lines.map(\.variableName), ["FSCL_JRE8", "FSCL_JDK11", "FSCL_JDK21"])
        XCTAssertEqual(lines.map(\.rowTitle), ["Java 8", "Java 11", "Java 21"])
    }
}
