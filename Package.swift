// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pastie",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Pastie", targets: ["Pastie"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.1")
    ],
    targets: [
        .executableTarget(
            name: "Pastie",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "HotKey"
            ],
            path: "Sources/Pastie"
        ),
        .testTarget(
            name: "PastieTests",
            dependencies: ["Pastie"],
            path: "Tests/PastieTests"
        )
    ]
)
