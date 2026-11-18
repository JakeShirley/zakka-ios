// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZakkaRaster",
    platforms: [.iOS("27.0")],
    products: [.library(name: "ZakkaRaster", targets: ["ZakkaRaster"])],
    targets: [
        .binaryTarget(name: "CResvg", path: "CResvg.xcframework"),
        .target(name: "ZakkaRaster", dependencies: ["CResvg"]),
    ]
)
