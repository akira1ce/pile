// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "pile",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "pile", targets: ["pile"]),
    ],
    targets: [
        .executableTarget(
            name: "pile",
            path: "Sources"
        ),
    ],
    swiftLanguageModes: [.v6]
)
