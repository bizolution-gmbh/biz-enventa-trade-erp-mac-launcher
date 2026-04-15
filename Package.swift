// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FSClientLauncherMac",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "FSClientLauncher", targets: ["FSClientLauncher"]),
    ],
    targets: [
        .executableTarget(
            name: "FSClientLauncher",
            path: "Sources/FSClientLauncher",
            resources: [
                .copy("Resources/Icon.png"),
            ]
        ),
    ]
)
