// swift-tools-version: 5.9
import PackageDescription

// macOS runs the networking/model regressions; the app remains an Xcode iOS target.
let package = Package(
    name: "NetScanCore",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "NetScanCore", targets: ["NetScanCore"])],
    targets: [
        .target(name: "NetScanCore", path: "NetScan",
                exclude: ["App", "Views", "Resources", "NetScan.xcodeproj"]),
        .testTarget(name: "NetScanCoreTests", dependencies: ["NetScanCore"], path: "Tests/NetScanCoreTests")
    ]
)
