// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BO2RuntimeProbe",
    platforms: [.iOS(.v18), .macOS(.v13)],
    targets: [.testTarget(name: "ProbeCoreTests", path: "Tests/ProbeCoreTests")]
)
