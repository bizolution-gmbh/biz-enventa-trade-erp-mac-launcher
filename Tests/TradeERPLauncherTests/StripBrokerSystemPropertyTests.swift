import XCTest

@testable import TradeERPLauncherLib

/// Reine Logik aus `LaunchCoordinator.stripBrokerSystemProperty(named:from:)` — sie ersetzt zwei
/// vorher fast deckungsgleiche Private-Helfer (`stripDisplayConsoleSystemProperties`,
/// `stripTraceLevelSystemProperties`) und filtert konsequent **case-insensitive**.
final class StripBrokerSystemPropertyTests: XCTestCase {
    private func runStrip(_ args: [String], property: String) -> [String] {
        var v = args
        LaunchCoordinator.stripBrokerSystemProperty(named: property, from: &v)
        return v
    }

    func testRemovesDisplayConsoleVariants() {
        let out = runStrip(
            [
                "-DDisplayConsole=true",
                "-DdisplayConsole=false",
                "-DDISPLAYCONSOLE=on",
                "-DOther=keep",
            ],
            property: "DisplayConsole"
        )
        XCTAssertEqual(out, ["-DOther=keep"])
    }

    func testRemovesTraceLevelVariants() {
        let out = runStrip(
            [
                "-DTraceLevel=Verbose",
                "-DtraceLevel=Information",
                "-Dtracelevel=Warning",
                "-DKeep=ok",
            ],
            property: "TraceLevel"
        )
        XCTAssertEqual(out, ["-DKeep=ok"])
    }

    func testKeepsUnrelatedDProperties() {
        let out = runStrip(
            [
                "-Dfoo=bar",
                "-Djava.net.useSystemProxies=true",
                "-DTraceLevelExtended=oops",
            ],
            property: "TraceLevel"
        )
        // `-DTraceLevelExtended=` ist ein anderer Schlüssel — Vergleich darf nicht per Prefix erfolgen.
        XCTAssertEqual(out, [
            "-Dfoo=bar",
            "-Djava.net.useSystemProxies=true",
            "-DTraceLevelExtended=oops",
        ])
    }

    func testKeepsNonSystemPropertyTokens() {
        let out = runStrip(
            ["-Xmx512m", "-server", "--add-opens", "java.base/java.lang=ALL-UNNAMED"],
            property: "DisplayConsole"
        )
        XCTAssertEqual(out, ["-Xmx512m", "-server", "--add-opens", "java.base/java.lang=ALL-UNNAMED"])
    }

    func testIgnoresMalformedDArgsWithoutEquals() {
        let out = runStrip(["-DDisplayConsole", "-Dfoo=bar"], property: "DisplayConsole")
        XCTAssertEqual(out, ["-DDisplayConsole", "-Dfoo=bar"])
    }

    func testIgnoresJustDashD() {
        let out = runStrip(["-D", "-Dfoo=bar"], property: "foo")
        XCTAssertEqual(out, ["-D"])
    }

    func testTrimsWhitespaceAroundToken() {
        let out = runStrip(["  -DDisplayConsole=true  ", "-Dfoo=bar"], property: "DisplayConsole")
        XCTAssertEqual(out, ["-Dfoo=bar"])
    }

    func testValueCanContainEqualsSign() {
        let out = runStrip(
            ["-DTraceLevel=key=value;other=1", "-Dfoo=bar"],
            property: "TraceLevel"
        )
        XCTAssertEqual(out, ["-Dfoo=bar"])
    }
}
