// swift-tools-version: 6.0

import PackageDescription

// The iOS app target locks deployment at iOS 26.0 in ios/Nuum.xcodeproj.
// These manifests leave platforms unset so `swift test` can build the libraries on the host.
let package = Package(
    name: "NuumFeatureConversation",
    products: [
        .library(name: "NuumFeatureConversation", targets: ["NuumFeatureConversation"]),
    ],
    dependencies: [
        .package(path: "../NuumContracts"),
        .package(path: "../NuumProtocol"),
    ],
    targets: [
        .target(
            name: "NuumFeatureConversation",
            dependencies: [
                "NuumContracts",
                "NuumProtocol",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "NuumFeatureConversationTests",
            dependencies: [
                "NuumFeatureConversation",
                "NuumContracts",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
