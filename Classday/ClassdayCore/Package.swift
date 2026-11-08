// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClassdayCore",
    products: [
        .library(name: "ClassdayCore", targets: ["ClassdayCore"]),
        .executable(name: "classday-backup", targets: ["ClassdayBackupTool"]),
    ],
    targets: [
        .target(name: "ClassdayCore"),
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
