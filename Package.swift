// swift-tools-version: 5.9
import PackageDescription

// Peephole: three SPM products —
//   • `PeepholePane` (.dynamic) — camera/mic sentinel dylib.
//   • `Peephole` (.executable) — thin standalone shim.
//   • `PeepholeShared` (.library, .static) — App Group +
//     `SharedPeephole` snapshot + `SharedPeepholeStore`. Consumed by
//     `PeepholePane`, `Peephole`, AND the Xcode widget target at
//     `Widget/PeepholeWidgets.xcodeproj`. SwiftPM can't build the
//     widget extension itself (SR-14944: no app-extension productType).
let package = Package(
    name: "Peephole",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Peephole", targets: ["Peephole"]),
        .library(name: "PeepholePane", type: .dynamic,
                 targets: ["PeepholePane"]),
        .library(name: "PeepholeShared", targets: ["PeepholeShared"])
    ],
    dependencies: [ .package(path: "../suitekit-swift") ],
    targets: [
        .target(
            name: "PeepholeShared",
            path: "Sources/PeepholeShared"
        ),
        .target(
            name: "PeepholePane",
            dependencies: [
                "PeepholeShared",
                .product(name: "SuiteKit", package: "suitekit-swift")
            ],
            path: "Sources/PeepholePane"
        ),
        .executableTarget(
            name: "Peephole",
            dependencies: [
                "PeepholePane",
                "PeepholeShared",
                .product(name: "SuiteKit", package: "suitekit-swift")
            ],
            path: "Sources/Peephole"
        )
    ]
)
