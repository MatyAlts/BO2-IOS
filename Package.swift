// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BO2RuntimeProbe",
    platforms: [.iOS("18.0"), .macOS(.v13)],
    targets: [.testTarget(name: "ProbeCoreTests", path: "Tests/ProbeCoreTests")]
)
