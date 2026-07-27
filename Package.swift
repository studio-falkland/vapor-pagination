// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vapor-pagination",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "VaporPagination", targets: ["VaporPagination"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.121.4"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.0.0"),
        .package(url: "https://github.com/studio-falkland/vapor-utilities.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "VaporPagination",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "VaporUtilities", package: "vapor-utilities"),
            ]
        ),
        .testTarget(
            name: "VaporPaginationTests",
            dependencies: [
                "VaporPagination",
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
            ]
        ),
    ]
)