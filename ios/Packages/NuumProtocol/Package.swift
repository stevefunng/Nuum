// swift-tools-version: 6.0

import PackageDescription

// The iOS app target locks deployment at iOS 26.0 in ios/Nuum.xcodeproj.
// These manifests leave platforms unset so `swift test` can build the libraries on the host.
let package = Package(
    name: "NuumProtocol",
    products: [
        .library(name: "NuumProtocol", targets: ["NuumProtocol"]),
    ],
    targets: [
        .target(
            name: "NuumProtocol",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "NuumProtocolTests",
            dependencies: ["NuumProtocol"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
