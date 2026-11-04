// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BO2RuntimeProbe",
    platforms: [.iOS("18.0"), .macOS(.v13)],
    products: [.library(name: "ProbeCore", targets: ["ProbeCore"]),
               .library(name: "AOTCore", targets: ["AOTCore"])],
    targets: [
        .target(name: "CProbe", path: "Sources/CProbe", publicHeadersPath: "include"),
        .target(name: "ProbeCore", dependencies: ["CProbe"]),
        .testTarget(name: "ProbeCoreTests", dependencies: ["ProbeCore"]),
        .target(name: "CAOTEngine", path: "Generated/CAOTEngine", exclude: ["engine.inc"], publicHeadersPath: "include"),
        .target(name: "AOTCore", dependencies: ["CAOTEngine"], path: "Generated/AOTCore", resources: [.copy("Resources/VMImage.bin"), .copy("Resources/ImageMetadata.json")]),
        .testTarget(name: "AOTCoreTests", dependencies: ["AOTCore"])
    ]
)
