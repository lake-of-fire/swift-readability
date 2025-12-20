// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftReadability",
    platforms: [
        .macOS(.v15),
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
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.5"),
        // Pin to a Swift 6.2-compatible revision (SwiftSyntax 603.x).
        .package(url: "https://github.com/apple/swift-testing.git", revision: "1d3961a0b006c25bec5301a01f4ba4fbfa7253c6")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SwiftReadability",
            dependencies: [
                .product(name: "SwiftSoup", package: "SwiftSoup")
            ]
        ),
        .testTarget(
            name: "SwiftReadabilityTests",
            dependencies: [
                "SwiftReadability",
                .product(name: "Testing", package: "swift-testing")
            ]
        ),
    ]
)
