// swift-tools-version: 5.9
import PackageDescription

// Peephole: `PeepholePane` (whole camera/mic sentinel as a dynamic
// library via SuiteKit, loadable by the launcher) + `Peephole` (thin
// @main standalone shim, behaviour unchanged).
let package = Package(
    name: "Peephole",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Peephole", targets: ["Peephole"]),
        .library(name: "PeepholePane", type: .dynamic, targets: ["PeepholePane"])
    ],
    dependencies: [ .package(path: "../suitekit-swift") ],
    targets: [
        .target(
            name: "PeepholePane",
            dependencies: [.product(name: "SuiteKit", package: "suitekit-swift")],
            path: "Sources/PeepholePane"
        ),
        .executableTarget(
            name: "Peephole",
            dependencies: ["PeepholePane", .product(name: "SuiteKit", package: "suitekit-swift")],
            path: "Sources/Peephole"
        )
    ]
)
