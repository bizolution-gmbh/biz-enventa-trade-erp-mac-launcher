import XCTest
@testable import TradeERPLauncherLib

final class ZuluJava8FxRuntimeDownloaderTests: XCTestCase {
    private var stagingURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZuluJava8FxRuntimeDownloaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        stagingURL = base
    }

    override func tearDownWithError() throws {
        if let s = stagingURL {
            try? FileManager.default.removeItem(at: s)
        }
        try super.tearDownWithError()
    }

    func testFindFirstJdkBundleNewAzulLayoutWithoutJdkSuffix() throws {
        let wrapper = stagingURL.appendingPathComponent(
            "zulu8.96.0.205-ca-fx-jdk8.0.504-macosx_aarch64",
            isDirectory: true
        )
        try createFakeMacJdkBundle(at: wrapper)

        let found = ZuluJava8FxRuntimeDownloader.findFirstJdkBundle(under: stagingURL)
        XCTAssertEqual(found?.resolvingSymlinksInPath().path, wrapper.resolvingSymlinksInPath().path)
    }

    func testFindFirstJdkBundleLegacyInnerJdkDirectory() throws {
        let wrapper = stagingURL.appendingPathComponent("zulu8.92.0.21-ca-fx-jdk8.0.482-macosx_aarch64", isDirectory: true)
        let jdk = wrapper.appendingPathComponent("zulu-8.jdk", isDirectory: true)
        try createFakeMacJdkBundle(at: jdk)

        let found = ZuluJava8FxRuntimeDownloader.findFirstJdkBundle(under: stagingURL)
        XCTAssertEqual(found?.resolvingSymlinksInPath().path, jdk.resolvingSymlinksInPath().path)
    }

    func testFindFirstJdkBundleContentsDirectlyUnderStaging() throws {
        try createFakeMacJdkBundle(at: stagingURL)

        let found = ZuluJava8FxRuntimeDownloader.findFirstJdkBundle(under: stagingURL)
        XCTAssertEqual(found?.resolvingSymlinksInPath().path, stagingURL.resolvingSymlinksInPath().path)
    }

    func testFindFirstJdkBundleIgnoresNestedJreJavaWithoutBundleRoot() throws {
        let decoy = stagingURL.appendingPathComponent("not-a-bundle/jre/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: decoy, withIntermediateDirectories: true)
        try Data().write(to: decoy.appendingPathComponent("java", isDirectory: false))

        XCTAssertNil(ZuluJava8FxRuntimeDownloader.findFirstJdkBundle(under: stagingURL))
    }

    func testFindFirstJdkBundleEmptyStaging() {
        XCTAssertNil(ZuluJava8FxRuntimeDownloader.findFirstJdkBundle(under: stagingURL))
    }

    private func createFakeMacJdkBundle(at root: URL) throws {
        let bin = root.appendingPathComponent("Contents/Home/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data().write(to: bin.appendingPathComponent("java", isDirectory: false))
    }
}
