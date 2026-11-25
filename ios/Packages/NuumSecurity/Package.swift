// swift-tools-version: 6.0

import PackageDescription

// The iOS app target locks deployment at iOS 26.0 in ios/Nuum.xcodeproj.
// These manifests leave platforms unset so `swift test` can build the libraries on the host.
let package = Package(
    name: "NuumSecurity",
    products: [
        .library(name: "NuumSecurity", targets: ["NuumSecurity"]),
    ],
    dependencies: [
        .package(path: "../NuumContracts"),
    ],
    targets: [
        .target(
            name: "NuumSecurity",
            dependencies: [
                "NuumContracts",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
