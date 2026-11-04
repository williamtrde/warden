// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Warden",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WardenCore", targets: ["WardenCore"])
    ],
    targets: [
        .target(
            name: "WardenCore",
            linkerSettings: [
                // The on-device model only exists on macOS 26+. Weak linking keeps the
                // binary loadable on macOS 14 and on Macs without Apple Intelligence.
                .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"])
            ]
        ),
        .testTarget(
            name: "WardenCoreTests",
            dependencies: ["WardenCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
