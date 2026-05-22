import XCTest

@testable import TradeERPLauncherLib

/// SHA-1-Werte stammen aus einer unsignierten Broker-Antwort und werden zur Bildung von
/// Cache-Pfaden verwendet. `isValidSha1Hex` ist die Defense-in-Depth-Schranke davor —
/// die hier abgesicherten Fälle sind genau die, die einen Pfad-Traversal oder ungültige
/// Dateinamen erlauben würden.
final class JarCacheSha1ValidationTests: XCTestCase {
    func testAcceptsCanonicalLowerHex() {
        XCTAssertTrue(JarCache.isValidSha1Hex("0123456789abcdef0123456789abcdef01234567"))
    }

    func testAcceptsUpperHex() {
        XCTAssertTrue(JarCache.isValidSha1Hex("0123456789ABCDEF0123456789ABCDEF01234567"))
    }

    func testAcceptsMixedCaseHex() {
        XCTAssertTrue(JarCache.isValidSha1Hex("0123456789AbCdEf0123456789aBcDeF01234567"))
    }

    func testRejectsTooShort() {
        XCTAssertFalse(JarCache.isValidSha1Hex("0123456789abcdef"))
    }

    func testRejectsTooLong() {
        XCTAssertFalse(JarCache.isValidSha1Hex("0123456789abcdef0123456789abcdef0123456701234567"))
    }

    func testRejectsEmpty() {
        XCTAssertFalse(JarCache.isValidSha1Hex(""))
    }

    /// Pfad-Traversal in einer 40-stelligen Eingabe (drei Punkte + Schrägstrich + Padding) —
    /// muss strikt abgelehnt werden, sonst bilden `appendingPathComponent`-Aufrufe darunter
    /// einen Pfad außerhalb des Cache-Verzeichnisses.
    func testRejectsPathTraversal() {
        XCTAssertFalse(JarCache.isValidSha1Hex("..//..//..//etc/passwd0123456789abcdef0123"))
    }

    func testRejectsSlash() {
        XCTAssertFalse(JarCache.isValidSha1Hex("0123456789abcdef0123456789abcdef0123/567"))
    }

    func testRejectsBackslash() {
        XCTAssertFalse(JarCache.isValidSha1Hex("0123456789abcdef0123456789abcdef0123\\567"))
    }

    /// NUL-Byte in einer ansonsten korrekten Längen-Eingabe (39 Hex-Zeichen + 1 NUL = 40).
    func testRejectsNulByte() {
        let prefix = "0123456789abcdef0123456789abcdef0123456" // 39
        let withNul = prefix + "\u{0000}"
        XCTAssertEqual(withNul.count, 40)
        XCTAssertFalse(JarCache.isValidSha1Hex(withNul))
    }

    func testRejectsNonHexPunctuation() {
        XCTAssertFalse(JarCache.isValidSha1Hex("0123456789abcdef0123456789abcdef0123g567"))
    }

    func testRejectsLeadingTrailingWhitespace() {
        XCTAssertFalse(JarCache.isValidSha1Hex(" 0123456789abcdef0123456789abcdef01234567"))
        XCTAssertFalse(JarCache.isValidSha1Hex("0123456789abcdef0123456789abcdef01234567 "))
    }

    /// Negativtest mit `downloadJar`: ein offensichtlich invalider Sha1 muss vor jedem
    /// Datei-System-Zugriff zu `LaunchError.invalidJarSha1Format` werden.
    func testDownloadJarRejectsInvalidSha1Synchronously() async {
        let badJar = ApiJarFile(
            Href: "main.jar",
            Sha1: "../../../etc/passwd",
            main: "1",
            Os: nil,
            Architecture: nil,
            nativeLib: nil,
            Size: nil
        )
        let baseURL = URL(string: "https://example.invalid/app/javaclient")!
        do {
            try await JarCache.downloadJar(baseJarUri: baseURL, jar: badJar)
            XCTFail("Erwartet Fehler bei ungültigem SHA-1.")
        } catch let LaunchError.invalidJarSha1Format(href, sha1) {
            XCTAssertEqual(href, "main.jar")
            XCTAssertEqual(sha1, "../../../etc/passwd")
        } catch {
            XCTFail("Unerwarteter Fehlertyp: \(error)")
        }
    }
}
