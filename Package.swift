// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftReadability",
    platforms: [
        .macOS(.v13),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v9)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SwiftReadability",
            targets: ["SwiftReadability"]
        ),
        .library(
            name: "SwiftReadabilityJavaScriptReference",
            targets: ["SwiftReadabilityJavaScriptReference"]
        ),
        .executable(
            name: "SwiftReadabilityBench",
            targets: ["SwiftReadabilityBench"]
        ),
        .executable(
            name: "SwiftReadabilityContract",
            targets: ["SwiftReadabilityContract"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.13.6"),
        // Mozilla Readability delegates URL resolution to the browser's WHATWG
        // URL implementation. Foundation.URL follows different legacy rules;
        // WebURL is the native-Swift, WPT-verified implementation of that contract.
        .package(url: "https://github.com/karwa/swift-url.git", exact: "0.4.2")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SwiftReadability",
            dependencies: [
                .product(name: "SwiftSoup", package: "SwiftSoup"),
                .product(name: "WebURL", package: "swift-url")
            ]
        ),
        .target(
            name: "SwiftReadabilityJavaScriptReference",
            resources: [
                .copy("Resources/Readability.js"),
                .copy("Resources/Readability-readerable.js")
            ]
        ),
        .target(name: "SwiftReadabilityFixtureSupport"),
        .executableTarget(
            name: "SwiftReadabilityBench",
            dependencies: [
                "SwiftReadability",
                "SwiftReadabilityFixtureSupport"
            ]
        ),
        .executableTarget(
            name: "SwiftReadabilityContract",
            dependencies: [
                "SwiftReadability",
                "SwiftReadabilityFixtureSupport"
            ]
        ),
        .testTarget(
            name: "SwiftReadabilityTests",
            dependencies: [
                "SwiftReadability",
                "SwiftReadabilityJavaScriptReference",
                "SwiftReadabilityFixtureSupport"
            ],
            resources: [
                .copy("Fixtures")
            ]
        ),
    ]
)
