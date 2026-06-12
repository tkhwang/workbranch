// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WorkbranchCompanion",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CompanionCore", targets: ["CompanionCore"]),
        .executable(name: "WorkbranchCompanion", targets: ["CompanionApp"]),
        .executable(name: "CompanionCoreTestRunner", targets: ["CompanionCoreTestRunner"]),
    ],
    targets: [
        .target(name: "CompanionCore"),
        .executableTarget(name: "CompanionApp", dependencies: ["CompanionCore"]),
        .executableTarget(name: "CompanionCoreTestRunner", dependencies: ["CompanionCore"]),
        .testTarget(name: "CompanionCoreTests", dependencies: ["CompanionCore"]),
    ]
)
