// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LedgeIt",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/jkrukowski/swift-embeddings", from: "0.0.16"),
        .package(url: "https://github.com/mattt/AnyLanguageModel", from: "0.7.0"),
    ],
    targets: [
        .target(
            name: "CSQLiteVec",
            path: "Sources/CSQLiteVec",
            publicHeadersPath: "include",
            cSettings: [
                .define("SQLITE_CORE"),
            ]
        ),
        .executableTarget(
            name: "LedgeIt",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Embeddings", package: "swift-embeddings"),
                .product(name: "AnyLanguageModel", package: "AnyLanguageModel"),
                "CSQLiteVec",
            ],
            path: "LedgeIt",
            exclude: ["Info.plist", "LedgeIt.entitlements"],
            resources: [
                .process("Assets.xcassets"),
            ]
        ),
        .testTarget(
            name: "LedgeItTests",
            dependencies: [
                "LedgeIt",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "AnyLanguageModel", package: "AnyLanguageModel"),
            ],
            path: "Tests"
        ),
    ]
)
