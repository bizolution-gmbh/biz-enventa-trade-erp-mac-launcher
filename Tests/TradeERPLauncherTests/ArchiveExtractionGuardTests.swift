import XCTest

@testable import TradeERPLauncherLib

final class ArchiveExtractionGuardTests: XCTestCase {
    private var stagingURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveExtractionGuardTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        stagingURL = base
    }

    override func tearDownWithError() throws {
        if let s = stagingURL {
            try? FileManager.default.removeItem(at: s)
        }
        try super.tearDownWithError()
    }

    // MARK: - Reine Pfadlogik

    func testIsPathContainedExactDirectoryAccepted() {
        let prefix = "/tmp/stage/"
        XCTAssertTrue(ArchiveExtractionGuard.isPathContained(candidatePath: "/tmp/stage", stagePathPrefix: prefix))
    }

    func testIsPathContainedNestedAccepted() {
        let prefix = "/tmp/stage/"
        XCTAssertTrue(ArchiveExtractionGuard.isPathContained(candidatePath: "/tmp/stage/a/b", stagePathPrefix: prefix))
    }

    func testIsPathContainedSiblingRejected() {
        let prefix = "/tmp/stage/"
        XCTAssertFalse(ArchiveExtractionGuard.isPathContained(candidatePath: "/tmp/stage2", stagePathPrefix: prefix))
        XCTAssertFalse(ArchiveExtractionGuard.isPathContained(candidatePath: "/tmp/stage2/x", stagePathPrefix: prefix))
    }

    func testIsPathContainedOutsideRejected() {
        let prefix = "/tmp/stage/"
        XCTAssertFalse(ArchiveExtractionGuard.isPathContained(candidatePath: "/etc/passwd", stagePathPrefix: prefix))
    }

    func testCanonicalPathPrefixHasTrailingSlash() {
        let dir = URL(fileURLWithPath: "/tmp/stage", isDirectory: true)
        let prefix = ArchiveExtractionGuard.canonicalPathPrefix(forDirectory: dir)
        XCTAssertTrue(prefix.hasSuffix("/"))
    }

    // MARK: - Datei-IO

    func testEmptyStagingPasses() throws {
        XCTAssertNoThrow(try ArchiveExtractionGuard.verifyContainedExtraction(stagingDirectory: stagingURL))
    }

    func testNormalNestedFilePasses() throws {
        let inner = stagingURL.appendingPathComponent("nested/dir", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try Data("ok".utf8).write(to: inner.appendingPathComponent("file.txt"))
        XCTAssertNoThrow(try ArchiveExtractionGuard.verifyContainedExtraction(stagingDirectory: stagingURL))
    }

    /// Symlink mit absolutem Ziel außerhalb des Staging-Verzeichnisses muss einen Fehler werfen.
    func testRejectsSymlinkPointingOutsideAbsolute() throws {
        let evil = stagingURL.appendingPathComponent("payload-link")
        try FileManager.default.createSymbolicLink(at: evil, withDestinationURL: URL(fileURLWithPath: "/etc/passwd"))
        XCTAssertThrowsError(
            try ArchiveExtractionGuard.verifyContainedExtraction(stagingDirectory: stagingURL)
        ) { error in
            guard case ArchiveExtractionGuard.ExtractionError.symlinkEscapesStaging = error else {
                return XCTFail("Erwartet symlinkEscapesStaging, war: \(error)")
            }
        }
    }

    /// Relativer Symlink mit `../`, der aus dem Staging-Verzeichnis hinausführt.
    func testRejectsSymlinkPointingOutsideRelative() throws {
        let inner = stagingURL.appendingPathComponent("subdir", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        let evil = inner.appendingPathComponent("escape-link")
        // Zwei Ebenen hoch (subdir → stage → über stage hinaus zu /etc/passwd).
        try FileManager.default.createSymbolicLink(atPath: evil.path, withDestinationPath: "../../etc/passwd")
        XCTAssertThrowsError(
            try ArchiveExtractionGuard.verifyContainedExtraction(stagingDirectory: stagingURL)
        ) { error in
            guard case ArchiveExtractionGuard.ExtractionError.symlinkEscapesStaging = error else {
                return XCTFail("Erwartet symlinkEscapesStaging, war: \(error)")
            }
        }
    }

    /// Relative Symlinks innerhalb des Staging-Verzeichnisses sind erlaubt.
    func testAcceptsHarmlessRelativeSymlinkInsideStaging() throws {
        let target = stagingURL.appendingPathComponent("target.txt")
        try Data("ok".utf8).write(to: target)
        let link = stagingURL.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "target.txt")
        XCTAssertNoThrow(try ArchiveExtractionGuard.verifyContainedExtraction(stagingDirectory: stagingURL))
    }
}
