// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TypelessClone",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "TypelessClone",
            path: "Sources/TypelessClone",
            resources: [
                .copy("../../Resources/Info.plist")
            ]
        )
    ]
)
