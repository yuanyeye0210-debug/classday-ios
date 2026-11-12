// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClassdayCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "ClassdayCore", targets: ["ClassdayCore"]),
        .executable(name: "classday-backup", targets: ["ClassdayBackupTool"]),
    ],
    targets: [
        .target(
            name: "ClassdayCore",
            dependencies: [
                // Apple builds use the Compression framework. Linux swift test inflates
                // ZIP method 8 with the system zlib. This is not a third-party package.
                .target(name: "ClassdayZlib", condition: .when(platforms: [.linux])),
            ]
        ),
        .target(
            name: "ClassdayZlib",
            publicHeadersPath: "include",
            linkerSettings: [.linkedLibrary("z")]
        ),
        .executableTarget(
            name: "ClassdayBackupTool",
            dependencies: ["ClassdayCore"]
        ),
        .testTarget(
            name: "ClassdayCoreTests",
            dependencies: ["ClassdayCore"]
        ),
    ]
)
