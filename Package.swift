// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Diroid",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Diroid"
        ),
    ],
    swiftLanguageModes: [.v6]
)
