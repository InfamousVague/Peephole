// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Peephole",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Peephole",
            path: "Sources/Peephole"
        )
    ]
)
