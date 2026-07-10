// swift-tools-version: 5.9

import PackageDescription

let iterationPilotDependencies: [Target.Dependency] = [
    "CLibXLS",
    .product(name: "CoreXLSX", package: "CoreXLSX"),
    .product(name: "ZIPFoundation", package: "ZIPFoundation"),
    .product(name: "DuckDB", package: "duckdb-swift")
]

let iterationPilotLinkerSettings: [LinkerSetting] = [
    .linkedLibrary("sqlite3"),
    .linkedFramework("Security")
]

let package = Package(
    name: "IterationPilot",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "IterationPilot", targets: ["IterationPilot"])
    ],
    dependencies: [
        .package(url: "https://github.com/CoreOffice/CoreXLSX.git", .upToNextMinor(from: "0.14.1")),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", .upToNextMinor(from: "0.9.11")),
        .package(url: "https://github.com/duckdb/duckdb-swift.git", .upToNextMajor(from: "1.1.0"))
    ],
    targets: [
        .target(
            name: "CLibXLS",
            path: "Sources/CLibXLS",
            publicHeadersPath: "include"
        ),
        .target(
            name: "IterationPilotCore",
            dependencies: iterationPilotDependencies,
            path: "Sources/IterationPilot",
            exclude: ["App"],
            linkerSettings: iterationPilotLinkerSettings
        ),
        .executableTarget(
            name: "IterationPilot",
            dependencies: ["IterationPilotCore"],
            path: "Sources/IterationPilot/App",
            linkerSettings: iterationPilotLinkerSettings
        ),
        .testTarget(
            name: "IterationPilotTests",
            dependencies: ["IterationPilotCore"],
            path: "Tests/IterationPilotTests",
            linkerSettings: iterationPilotLinkerSettings
        )
    ]
)
