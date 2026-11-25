// swift-tools-version: 6.0

import PackageDescription

// The iOS app target locks deployment at iOS 26.0 in ios/Nuum.xcodeproj.
// These manifests leave platforms unset so `swift test` can build the libraries on the host.
let package = Package(
    name: "NuumModel",
    products: [
        .library(name: "NuumModel", targets: ["NuumModel"]),
    ],
    dependencies: [
        .package(path: "../NuumContracts"),
        .package(path: "../NuumProtocol"),
    ],
    targets: [
        .target(
            name: "NuumModel",
            dependencies: [
                "NuumContracts",
                "NuumProtocol",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
