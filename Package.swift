// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "pile",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "pile", targets: ["pile"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.10.1"),
    ],
    targets: [
        .executableTarget(
            name: "pile",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
