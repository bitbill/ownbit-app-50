// swift-tools-version:5.9
// Package.swift — Ownbit core (extracted from Ownbit iOS 5.x).
// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
//
// Ownbit core (iOS): mnemonic generation, key storage, key derivation and signing.
import PackageDescription

let package = Package(
    name: "OwnbitCore",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "OwnbitCore", targets: ["OwnbitCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", exact: "1.8.0"),  // same version the app ships
    ],
    targets: [
        // libscrypt (BSD-2-Clause), the same C implementation the app links
        .target(
            name: "CLibscrypt",
            path: "Sources/CLibscrypt",
            exclude: ["LICENSE", "README.md"]
        ),
        .target(
            name: "OwnbitCore",
            dependencies: ["CLibscrypt", "CryptoSwift"],
            path: "Sources/OwnbitCore"
        ),
        .testTarget(
            name: "OwnbitCoreTests",
            dependencies: ["OwnbitCore"],
            path: "Tests/OwnbitCoreTests",
            exclude: ["PublicProtocol/Fixtures"]   // read through #filePath, not as resources
        ),
    ]
)
