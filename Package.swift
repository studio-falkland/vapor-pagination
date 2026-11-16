// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "vapor-pagination",
    platforms: [
        .macOS("26.2")
    ],
    products: [
        .library(name: "VaporPagination", targets: ["VaporPagination"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "5.0.0-beta.4"),
        .package(url: "https://github.com/vapor/fluent-kit.git", from: "1.57.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.0.0"),
        .package(url: "https://github.com/studio-falkland/vapor-utilities.git", branch: "vapor5"),
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.14.0"),
    ],
    targets: [
        .target(
            name: "VaporPagination",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "FluentKit", package: "fluent-kit"),
                .product(name: "VaporUtilities", package: "vapor-utilities"),
            ]
        ),
        .testTarget(
            name: "VaporPaginationTests",
            dependencies: [
                "VaporPagination",
                .product(name: "FluentKit", package: "fluent-kit"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "VaporUtilities", package: "vapor-utilities"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
    ]
)
