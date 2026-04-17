import XCTest

@testable import FSClientLauncherLib

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
}
