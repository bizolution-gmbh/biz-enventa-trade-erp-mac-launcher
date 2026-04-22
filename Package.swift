// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TradeERPLauncher",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "TradeERPLauncher", targets: ["TradeERPLauncher"]),
    ],
    targets: [
        .target(
            name: "TradeERPLauncherLib",
            path: "Sources/TradeERPLauncherLib",
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
            name: "TradeERPLauncher",
            dependencies: ["TradeERPLauncherLib"],
            path: "Sources/TradeERPLauncher",
            sources: ["Main.swift"]
        ),
        .testTarget(
            name: "TradeERPLauncherTests",
            dependencies: ["TradeERPLauncherLib"],
            path: "Tests/TradeERPLauncherTests"
        ),
    ]
)
