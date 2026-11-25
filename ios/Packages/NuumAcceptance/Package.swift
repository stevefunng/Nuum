// swift-tools-version: 6.0

import PackageDescription

// The iOS app target locks deployment at iOS 26.0 in ios/Nuum.xcodeproj.
// These manifests leave platforms unset so `swift test` can build the libraries on the host.
// This package has no Swift package dependencies. The app target must not link it.
let package = Package(
    name: "NuumAcceptance",
    products: [
        .library(name: "NuumAcceptance", targets: ["NuumAcceptance"]),
    ],
    targets: [
        .target(
            name: "NuumAcceptance",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "NuumAcceptanceTests",
            dependencies: ["NuumAcceptance"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
