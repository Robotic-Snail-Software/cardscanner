// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CardScanner",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "CardScanner", targets: ["CardScanner"])
    ],
    targets: [
        .target(
            name: "CardScanner",
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        ),
        .testTarget(
            name: "CardScannerTests",
            dependencies: ["CardScanner"],
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        )
    ]
)
