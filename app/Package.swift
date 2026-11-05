// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "TouchBarCompanion",
    platforms: [.macOS(.v12)],
    targets: [
        .target(name: "CompanionCore"),
        .executableTarget(
            name: "TouchBarCompanion",
            dependencies: ["CompanionCore"]
        ),
        .testTarget(
            name: "CompanionCoreTests",
            dependencies: ["CompanionCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
