// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Prompt",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "Prompt",
            targets: ["Prompt"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/onevcat/Rainbow.git", from: "4.0.0")
    ],
    targets: [
        .target(
            name: "Prompt",
            dependencies: [
                .product(name: "Rainbow", package: "Rainbow")
            ],
            path: "Sources/Prompt"
        ),
        .testTarget(
            name: "PromptTests",
            dependencies: ["Prompt"],
            path: "Tests/PromptTests"
        )
    ]
)
