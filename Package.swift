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
        .executable(
            name: "SwiftReadabilityBench",
            targets: ["SwiftReadabilityBench"]
        ),
    ],
    dependencies: [
        .package(path: "../SwiftSoup")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SwiftReadability",
            dependencies: [
                .product(name: "SwiftSoup", package: "SwiftSoup")
            ],
            resources: [
                .copy("Resources/Readability.js"),
                .copy("Resources/Readability-readerable.js")
            ]
        ),
        .executableTarget(
            name: "SwiftReadabilityBench",
            dependencies: [
                "SwiftReadability"
            ]
        ),
        .testTarget(
            name: "SwiftReadabilityTests",
            dependencies: [
                "SwiftReadability"
            ],
            exclude: [
                "Fixtures"
            ]
        ),
    ]
)
