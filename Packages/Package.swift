// swift-tools-version: 6.2
import PackageDescription

// Modul aplikasi iOS Anastrophe (SDD §5.1). Minimum iOS 26.0 (ADR-0006).
// macOS hanya dipakai agar `swift test` bisa jalan di host; modul yang butuh
// CoreNFC/CoreBluetooth/Security menyediakan implementasi live di balik `#if os(iOS)`.
let package = Package(
    name: "AnastropheKit",
    defaultLocalization: "id",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "ANFeatures", targets: ["ANFeatures"]),
        .library(name: "ANCore", targets: ["ANCore"]),
        .library(name: "ANProtocol", targets: ["ANProtocol"]),
        .library(name: "ANCrypto", targets: ["ANCrypto"]),
        .library(name: "ANChannelNFC", targets: ["ANChannelNFC"]),
        .library(name: "ANChannelBLE", targets: ["ANChannelBLE"]),
        .library(name: "ANStorage", targets: ["ANStorage"]),
        .library(name: "ANNetworking", targets: ["ANNetworking"]),
        .library(name: "ANNFCEnroll", targets: ["ANNFCEnroll"]),
        .library(name: "ANWallet", targets: ["ANWallet"]),
        .library(name: "ANDesignSystem", targets: ["ANDesignSystem"]),
    ],
    targets: [
        .target(name: "ANCore"),
        .target(name: "ANDesignSystem"),
        .target(name: "ANCrypto", dependencies: ["ANCore", "ANProtocol"]),
        .target(name: "ANProtocol", dependencies: ["ANCore"]),
        .target(name: "ANStorage", dependencies: ["ANCore", "ANCrypto"]),
        .target(name: "ANNetworking", dependencies: ["ANCore"]),
        .target(name: "ANNFCEnroll", dependencies: ["ANCore"]),
        .target(name: "ANChannelNFC", dependencies: ["ANCore", "ANProtocol", "ANCrypto"]),
        .target(name: "ANChannelBLE", dependencies: ["ANCore", "ANProtocol", "ANCrypto"]),
        .target(name: "ANWallet", dependencies: ["ANCore"]),
        .target(
            name: "ANFeatures",
            dependencies: ["ANCore", "ANDesignSystem", "ANChannelNFC", "ANChannelBLE", "ANStorage", "ANNetworking", "ANWallet", "ANNFCEnroll"],
            resources: [.process("Resources")]
        ),
        // Utilitas khusus test (reader ANP/1 perangkat lunak, signer & counter in-memory).
        .target(name: "ANTestSupport", dependencies: ["ANCore", "ANProtocol", "ANCrypto"], path: "Tests/ANTestSupport"),
        .testTarget(name: "ANCoreTests", dependencies: ["ANCore"]),
        .testTarget(name: "ANProtocolTests", dependencies: ["ANProtocol"]),
        .testTarget(name: "ANCryptoTests", dependencies: ["ANCrypto", "ANProtocol", "ANTestSupport"], resources: [.process("Resources")]),
        .testTarget(name: "ANChannelNFCTests", dependencies: ["ANChannelNFC", "ANCrypto", "ANProtocol", "ANTestSupport"]),
        .testTarget(name: "ANChannelBLETests", dependencies: ["ANChannelBLE", "ANCrypto", "ANProtocol", "ANTestSupport"]),
        .testTarget(name: "ANStorageTests", dependencies: ["ANStorage", "ANCrypto"]),
        .testTarget(name: "ANNetworkingTests", dependencies: ["ANNetworking"]),
        .testTarget(name: "ANNFCEnrollTests", dependencies: ["ANNFCEnroll", "ANCore"]),
        .testTarget(name: "ANFeaturesTests", dependencies: ["ANFeatures", "ANCore", "ANCrypto", "ANStorage", "ANNetworking", "ANTestSupport"]),
    ],
    swiftLanguageModes: [.v6]
)
