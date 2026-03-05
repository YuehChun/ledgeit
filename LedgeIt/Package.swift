// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LedgeIt",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
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
            ],
            path: "Tests"
        ),
    ]
)
