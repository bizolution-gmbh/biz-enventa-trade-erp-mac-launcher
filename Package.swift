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
        .target(
            name: "FSClientLauncherLib",
            path: "Sources/FSClientLauncherLib",
            resources: [
                .copy("Resources/Icon.png"),
            ]
        ),
        .executableTarget(
            name: "FSClientLauncher",
            dependencies: ["FSClientLauncherLib"],
            path: "Sources/FSClientLauncher",
            sources: ["Main.swift"]
        ),
        .testTarget(
            name: "FSClientLauncherTests",
            dependencies: ["FSClientLauncherLib"],
            path: "Tests/FSClientLauncherTests"
        ),
    ]
)
