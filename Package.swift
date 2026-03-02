// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalMind",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LocalMindLib", targets: ["LocalMindLib"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.19"),
    ],
    targets: [
        .target(
            name: "LocalMindLib",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "LocalMind",
            exclude: ["Resources/Info.plist", "Resources/LocalMind.entitlements", "Resources/Assets.xcassets"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
