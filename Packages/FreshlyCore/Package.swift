// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FreshlyCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "FreshlyCore",
            targets: [
                "FreshlyModels",
                "FreshlyScanner",
                "FreshlySources",
                "FreshlyInstaller",
                "FreshlySecurity",
                "FreshlyEngine",
            ]
        ),
        .executable(name: "validate-definitions", targets: ["FreshlyDefinitionsValidator"]),
    ],
    targets: [
        .target(name: "FreshlyModels"),
        .executableTarget(name: "FreshlyDefinitionsValidator", dependencies: ["FreshlyModels"]),
        .target(name: "FreshlySecurity", dependencies: ["FreshlyModels"]),
        .target(name: "FreshlyScanner", dependencies: ["FreshlyModels", "FreshlySecurity"]),
        .target(name: "FreshlySources", dependencies: ["FreshlyModels"]),
        .target(name: "FreshlyInstaller", dependencies: ["FreshlyModels", "FreshlySecurity"]),
        .target(name: "FreshlyEngine", dependencies: ["FreshlyModels", "FreshlyScanner", "FreshlySources"]),
        .testTarget(
            name: "FreshlyCoreTests",
            dependencies: [
                "FreshlyModels",
                "FreshlyScanner",
                "FreshlySources",
                "FreshlyInstaller",
                "FreshlySecurity",
                "FreshlyEngine",
            ],
            resources: [
                .copy("Fixtures")
            ]
        ),
    ]
)
