// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CareCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "CareCore", targets: ["CareCore"])],
    targets: [
        .target(name: "CareCore"),
        .testTarget(name: "CareCoreTests", dependencies: ["CareCore"])
    ]
)
