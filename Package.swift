// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Koe",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Koe",
            path: "Sources/Koe",
            resources: [
                .copy("../../Resources/Info.plist")
            ]
        )
    ]
)
