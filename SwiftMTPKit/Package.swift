// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "SwiftMTPKit",
  defaultLocalization: "en",
  platforms: [ .macOS(.v15), .iOS(.v18) ],
  products: [
    .library(name: "SwiftMTPCore", targets: ["SwiftMTPCore"]),
    .library(name: "SwiftMTPTransportLibUSB", targets: ["SwiftMTPTransportLibUSB"]),
    .library(name: "SwiftMTPIndex", targets: ["SwiftMTPIndex"]),
    .library(name: "SwiftMTPSync", targets: ["SwiftMTPSync"]),
    .library(name: "SwiftMTPObservability", targets: ["SwiftMTPObservability"]),
    .library(name: "SwiftMTPQuirks", targets: ["SwiftMTPQuirks"]),
    .library(name: "SwiftMTPStore", targets: ["SwiftMTPStore"]),
    .executable(name: "swiftmtp", targets: ["swiftmtp-cli"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-async-algorithms.git", exact: "1.0.1"),
    .package(url: "https://github.com/apple/swift-collections.git", exact: "1.1.1"),
    .package(url: "https://github.com/stephencelis/SQLite.swift.git", exact: "0.15.3"),
    .package(url: "https://github.com/Tyler-Keith-Thompson/CucumberSwift", from: "5.0.0"),
    .package(url: "https://github.com/typelift/SwiftCheck", from: "0.12.0"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.10.0"),
  ],
  targets: [
    .target(name: "SwiftMTPObservability",
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    .target(name: "SwiftMTPCore",
            dependencies: [
              "SwiftMTPObservability",
              "SwiftMTPQuirks",
              .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
              .product(name: "Collections", package: "swift-collections")
            ]),

    .target(name: "SwiftMTPStore",
            dependencies: ["SwiftMTPCore"],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    // libusb via Homebrew for dev (dynamic)
    .systemLibrary(name: "CLibusb", path: "Sources/CLibusb", pkgConfig: "libusb-1.0", providers: [.brew(["libusb"])]),

    .target(name: "SwiftMTPTransportLibUSB",
            dependencies: [
              "SwiftMTPCore", "SwiftMTPObservability", "CLibusb"
            ]),

    .target(name: "SwiftMTPIndex",
            dependencies: ["SwiftMTPCore", .product(name: "Collections", package: "swift-collections"), .product(name: "SQLite", package: "SQLite.swift")],
            resources: [.copy("Schema.sql")],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    .target(name: "SwiftMTPSync",
            dependencies: ["SwiftMTPCore", "SwiftMTPIndex", "SwiftMTPObservability", .product(name: "SQLite", package: "SQLite.swift")],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    .target(name: "SwiftMTPQuirks",
            dependencies: [],
            resources: [.process("Resources")]),

    .executableTarget(name: "swiftmtp-cli",
                      dependencies: ["SwiftMTPCore", "SwiftMTPTransportLibUSB", "SwiftMTPIndex", "SwiftMTPSync", "SwiftMTPObservability", "SwiftMTPQuirks", "SwiftMTPStore"],
                      path: "Sources/Tools/swiftmtp-cli",
                      swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    .testTarget(name: "CoreTests", dependencies: ["SwiftMTPCore", "SwiftMTPTransportLibUSB", "CLibusb"]),
    .testTarget(name: "IndexTests", dependencies: ["SwiftMTPIndex", "SwiftMTPCore", "SwiftMTPSync", "SwiftMTPTransportLibUSB", "CLibusb"]),
    .testTarget(name: "TransportTests", dependencies: ["SwiftMTPTransportLibUSB", "CLibusb"]),
    .testTarget(name: "BDDTests",
                dependencies: ["SwiftMTPCore", "SwiftMTPTransportLibUSB", .product(name: "CucumberSwift", package: "CucumberSwift")],
                resources: [.copy("Features")]),
    .testTarget(name: "PropertyTests",
                dependencies: ["SwiftMTPCore", "SwiftCheck"]),
    .testTarget(name: "SnapshotTests",
                dependencies: [
                    "SwiftMTPCore", 
                    "SwiftMTPIndex",
                    .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
                ],
                exclude: ["__Snapshots__"]),
  ]
)