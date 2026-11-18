// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZakkaCore",
    platforms: [.iOS("27.0"), .macOS(.v14)],
    products: [.library(name: "ZakkaCore", targets: ["ZakkaCore"])],
    targets: [.target(name: "ZakkaCore"), .testTarget(name: "ZakkaCoreTests", dependencies: ["ZakkaCore"])]
)
