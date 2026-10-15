// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RailsKit",
    platforms: [.iOS(.v26)],
    products: [.library(name: "RailsKit", targets: ["RailsKit"])],
    targets: [
        .target(
            name: "RailsKit",
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
