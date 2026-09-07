// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "LookAround",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "LookAround", targets: ["LookAround"])
    ],
    targets: [
        .executableTarget(
            name: "LookAround",
            path: "Sources/LookAround"
        )
    ]
)
