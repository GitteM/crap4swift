// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "crap4swift",
    products: [
        .executable(name: "crap4swift", targets: ["crap4swift"]),
        .library(name: "Crap4SwiftCore", targets: ["Crap4SwiftCore"])
    ],
    targets: [
        .target(name: "Crap4SwiftCore"),
        .executableTarget(name: "crap4swift", dependencies: ["Crap4SwiftCore"]),
        .testTarget(name: "Crap4SwiftCoreTests", dependencies: ["Crap4SwiftCore"])
    ]
)
