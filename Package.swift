// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "compote",
    platforms: [
        .macOS("15.0"),
        .iOS("17.0"),
        .tvOS("17.0"),
        .watchOS("10.0"),
        .macCatalyst("17.0")
    ],
    products: [
        .executable(name: "compote", targets: ["compote"]),
        .library(name: "CompoteCore", targets: ["CompoteCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/briannadoubt/containerization.git", from: "0.1.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0")
    ],
    targets: [
        .executableTarget(
            name: "compote",
            dependencies: [
                "CompoteCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "CompoteCore",
            dependencies: [
                .product(name: "Containerization", package: "containerization"),
                .product(name: "ContainerizationOCI", package: "containerization"),
                .product(name: "ContainerizationEXT4", package: "containerization"),
                .product(name: "ContainerizationNetlink", package: "containerization"),
                .product(name: "Logging", package: "swift-log"),
                "Yams"
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "CompoteCoreTests",
            dependencies: ["CompoteCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
