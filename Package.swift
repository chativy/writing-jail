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
            name: "WritingJailCore",
            path: "src/WritingJailCore"
        ),
        .executableTarget(
            name: "WritingJail",
            dependencies: ["WritingJailCore"],
            path: "src/WritingJail"
        ),
        .testTarget(
            name: "WritingJailCoreTests",
            dependencies: ["WritingJailCore"],
            path: "tests/WritingJailCoreTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
