// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "shortcutctl",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "shortcutctl", targets: ["shortcutctl"]),
        .library(name: "ShortcutCore", targets: ["ShortcutCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2")
    ],
    targets: [
        .target(name: "ShortcutCore"),
        .executableTarget(
            name: "shortcutctl",
            dependencies: [
                "ShortcutCore", .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]),
        .testTarget(name: "ShortcutCoreTests", dependencies: ["ShortcutCore"]),
    ]
)
