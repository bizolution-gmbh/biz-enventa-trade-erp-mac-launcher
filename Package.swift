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
            exclude: [
                // Werden vom Build-Skript aus dem Arbeitsbaum gelesen/kopiert, nicht als SPM-Ressource eingebunden (vermeidet „unhandled files“-Warnung).
                "Resources/AppIcon.icns",
                "Resources/AppIcon.iconset",
                "Resources/enventa-logo-full.svg",
                "Resources/enventa-mark-cropped.svg",
            ],
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
