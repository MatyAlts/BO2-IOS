// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BO2RuntimeProbe",
    platforms: [.iOS("18.0"), .macOS(.v13)],
    products: [.library(name: "ProbeCore", targets: ["ProbeCore"])],
    targets: [
        .target(name: "CProbe", path: "Sources/CProbe", publicHeadersPath: "include"),
        .target(name: "ProbeCore", dependencies: ["CProbe"]),
        .testTarget(name: "ProbeCoreTests", dependencies: ["ProbeCore"]),
        .testTarget(name: "AOTCoreTests", dependencies: [])
    ]
)
