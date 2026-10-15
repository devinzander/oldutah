// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CemeteryKit",
    platforms: [.iOS(.v26)],
    products: [.library(name: "CemeteryKit", targets: ["CemeteryKit"])],
    targets: [
        .target(
            name: "CemeteryKit",
            resources: [.process("Resources")],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
    ]
)
