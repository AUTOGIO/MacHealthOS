// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "MacHealthOS",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "MacHealthOS",
            targets: ["MacHealthOS"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MacHealthOS"
        ),
        .testTarget(
            name: "MacHealthOSTests",
            dependencies: ["MacHealthOS"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
