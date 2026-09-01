// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Ditto",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Ditto", targets: ["Ditto"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.1")
    ],
    targets: [
        .executableTarget(
            name: "Ditto",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "HotKey"
            ],
            path: "Sources/Ditto"
        ),
        .testTarget(
            name: "DittoTests",
            dependencies: ["Ditto"],
            path: "Tests/DittoTests"
        )
    ]
)
