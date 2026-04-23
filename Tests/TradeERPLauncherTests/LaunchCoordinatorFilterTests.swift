import XCTest
import Foundation

@testable import TradeERPLauncherLib

final class LaunchCoordinatorFilterTests: XCTestCase {
    private func jar(os: String?, arch: String?) -> ApiJarFile {
        ApiJarFile(
            Href: "x.jar",
            Sha1: "a",
            main: nil,
            Os: os,
            Architecture: arch,
            nativeLib: nil,
            Size: nil
        )
    }

    func testFilterDropsWindowsOnly() {
        let jars = [
            jar(os: "Windows", arch: nil),
            jar(os: "macOS", arch: nil),
            jar(os: nil, arch: nil),
        ]
        let out = LaunchCoordinator.filterOsArchitecture(jarFiles: jars, jvmArch: nil)
        XCTAssertEqual(out.count, 2)
        XCTAssertTrue(out.allSatisfy { $0.Os?.lowercased() != "windows" })
    }

    func testFilterKeepsMacDarwinOs() {
        let jars = [jar(os: "Darwin", arch: nil), jar(os: "OSX", arch: nil)]
        let out = LaunchCoordinator.filterOsArchitecture(jarFiles: jars, jvmArch: nil)
        XCTAssertEqual(out.count, 2)
    }

    func testFilterByArchitectureAarch64Arm64Alias() {
        let jars = [
            jar(os: nil, arch: "aarch64"),
            jar(os: nil, arch: "x86_64"),
        ]
        let out = LaunchCoordinator.filterOsArchitecture(jarFiles: jars, jvmArch: "arm64")
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.Architecture?.lowercased(), "aarch64")
    }

    /// JVM-`os.arch` wird zu „amd64“ normalisiert; Broker-JARs oft „x86_64“.
    func testFilterByArchitectureAmd64X86_64Alias() {
        let jars = [
            jar(os: nil, arch: "x86_64"),
            jar(os: nil, arch: "aarch64"),
        ]
        let out = LaunchCoordinator.filterOsArchitecture(jarFiles: jars, jvmArch: "amd64")
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.Architecture?.lowercased(), "x86_64")
    }
}

// MARK: - HTTPOutboundRedirectPolicy (gleiches Modul wie oben — vermeidet XCTest-Modulauflösung in separater Datei bei manchen Toolchains)

final class HTTPOutboundRedirectPolicyTests: XCTestCase {
    func testFollowsHttpRedirectWithHost() {
        let next = URL(string: "https://example.com/path")!
        let req = URLRequest(url: next)
        let prev = URL(string: "https://origin.example/")!
        let resp = HTTPURLResponse(url: prev, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: nil)!
        var out: URLRequest?
        HTTPOutboundRedirectPolicy.respondToRedirect(context: "test", response: resp, newRequest: req) { out = $0 }
        XCTAssertNotNil(out)
        XCTAssertEqual(out?.url?.absoluteString, next.absoluteString)
    }

    func testRejectsLauncherSchemeRedirect() {
        let next = URL(string: "fsclientlauncher:launch?broker=https%3A%2F%2Fx")!
        let req = URLRequest(url: next)
        let prev = URL(string: "https://server/app/api/fsclient")!
        let resp = HTTPURLResponse(url: prev, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: nil)!
        var out: URLRequest?
        HTTPOutboundRedirectPolicy.respondToRedirect(context: "test", response: resp, newRequest: req) { out = $0 }
        XCTAssertNil(out)
    }

    func testRejectsNonHttpRedirect() {
        let next = URL(string: "ftp://files.example/pub")!
        let req = URLRequest(url: next)
        let prev = URL(string: "https://a/")!
        let resp = HTTPURLResponse(url: prev, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: nil)!
        var out: URLRequest?
        HTTPOutboundRedirectPolicy.respondToRedirect(context: "test", response: resp, newRequest: req) { out = $0 }
        XCTAssertNil(out)
    }
}
