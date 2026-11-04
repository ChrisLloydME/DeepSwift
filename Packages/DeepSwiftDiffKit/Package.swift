// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DeepSwiftDiffKit",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "DiffCore", targets: ["DiffCore"]),
        .library(name: "DiffUI", targets: ["DiffUI"])
    ],
    targets: [
        .target(
            name: "DiffCore",
            path: "Sources/DiffCore"
        ),
        .target(
            name: "DiffUI",
            dependencies: ["DiffCore"],
            path: "Sources/DiffUI"
        ),
        .testTarget(
            name: "DiffCoreTests",
            dependencies: ["DiffCore"],
            path: "Tests/DiffCoreTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
