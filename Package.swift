// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WritingJail",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WritingJail", targets: ["WritingJail"])
    ],
    targets: [
        .target(
            name: "FocusWriterCore",
            path: "src/FocusWriterCore"
        ),
        .executableTarget(
            name: "WritingJail",
            dependencies: ["FocusWriterCore"],
            path: "src/FocusWriter"
        ),
        .testTarget(
            name: "FocusWriterCoreTests",
            dependencies: ["FocusWriterCore"],
            path: "tests/FocusWriterCoreTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
