// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "SwiftMTP",
  defaultLocalization: "en",
  platforms: [
    .macOS(.v26),
    .iOS(.v26)
  ],
  products: [
    .executable(name: "simple-probe", targets: ["simple-probe"]),
    .executable(name: "swiftmtp", targets: ["swiftmtp-cli"]),
    .library(name: "SwiftMTPCore", targets: ["SwiftMTPCore"]),
    .library(name: "MTPEndianCodec", targets: ["MTPEndianCodec"]),
    .library(name: "SwiftMTPStore", targets: ["SwiftMTPStore"]),
    .library(name: "SwiftMTPUI", targets: ["SwiftMTPUI"]),
    .library(name: "SwiftMTPQuirks", targets: ["SwiftMTPQuirks"]),
    .library(name: "SwiftMTPCLI", targets: ["SwiftMTPCLI"]),
    .executable(name: "SwiftMTPApp", targets: ["SwiftMTPApp"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-collections.git", exact: "1.3.0"),
    .package(url: "https://github.com/Tyler-Keith-Thompson/CucumberSwift", from: "5.0.0"),
    .package(url: "https://github.com/typelift/SwiftCheck", from: "0.12.0"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.10.0"),
  ],
  targets: [
    // SQLite3 via system library
    .systemLibrary(name: "CSQLite", path: "SwiftMTPKit/Sources/CSQLite", providers: [.apt(["libsqlite3-dev"]), .brew(["sqlite"])]),

    // libusb via Homebrew for dev (dynamic)
    .systemLibrary(name: "CLibusb", path: "SwiftMTPKit/Sources/CLibusb", pkgConfig: "libusb-1.0", providers: [.brew(["libusb"])]),

    // Core MTP functionality
    .target(name: "SwiftMTPCore",
            dependencies: [
                "SwiftMTPQuirks", "SwiftMTPObservability", "SwiftMTPCLI", "MTPEndianCodec",
                .product(name: "Collections", package: "swift-collections"),
            ],
            path: "SwiftMTPKit/Sources/SwiftMTPCore",
            sources: ["Internal", "Public"]),

    // Shared CLI parsing/output surfaces extracted to a dedicated module.
    .target(name: "SwiftMTPCLI",
            dependencies: [],
            path: "SwiftMTPKit/Sources/SwiftMTPCLI"),

    .target(name: "MTPEndianCodec",
            dependencies: [],
            path: "SwiftMTPKit/Sources/MTPEndianCodec"),

    // Transport layer for libusb
    .target(name: "SwiftMTPTransportLibUSB",
            dependencies: ["SwiftMTPCore", "CLibusb"],
            path: "SwiftMTPKit/Sources/SwiftMTPTransportLibUSB"),

    // Index and snapshot functionality
    .target(name: "SwiftMTPIndex",
            dependencies: ["SwiftMTPCore", "CSQLite"],
            path: "SwiftMTPKit/Sources/SwiftMTPIndex",
            exclude: ["Schema.sql"]),

    // Sync and mirror functionality
    .target(name: "SwiftMTPSync",
            dependencies: ["SwiftMTPCore", "SwiftMTPIndex"],
            path: "SwiftMTPKit/Sources/SwiftMTPSync"),

    // Observability utilities
    .target(name: "SwiftMTPObservability",
            dependencies: [],
            path: "SwiftMTPKit/Sources/SwiftMTPObservability"),

    // Device quirks and tuning database
    .target(name: "SwiftMTPQuirks",
            dependencies: [],
            path: "SwiftMTPKit/Sources/SwiftMTPQuirks",
            resources: [.process("Resources")]),

    // Persistence and data storage
    .target(name: "SwiftMTPStore",
            dependencies: ["SwiftMTPCore", "CSQLite"],
            path: "SwiftMTPKit/Sources/SwiftMTPStore"),

    // XPC service for File Provider extension
    .target(name: "SwiftMTPXPC",
            dependencies: ["SwiftMTPCore", "SwiftMTPTransportLibUSB", "SwiftMTPIndex"],
            path: "SwiftMTPKit/Sources/SwiftMTPXPC",
            swiftSettings: [.swiftLanguageMode(.v5)]),

    // File Provider extension bridge
    .target(name: "SwiftMTPFileProvider",
            dependencies: ["SwiftMTPCore", "SwiftMTPIndex", "SwiftMTPStore", "SwiftMTPXPC"],
            path: "SwiftMTPKit/Sources/SwiftMTPFileProvider",
            swiftSettings: [.swiftLanguageMode(.v5)]),

    // UI Components (SwiftUI)
    .target(name: "SwiftMTPUI",
            dependencies: [
                "SwiftMTPCore", "SwiftMTPSync", "SwiftMTPTransportLibUSB",
                "SwiftMTPObservability", "CLibusb",
                "SwiftMTPIndex",
                "SwiftMTPQuirks",
                "SwiftMTPXPC",
                "SwiftMTPFileProvider",
                "SwiftMTPStore",
            ],
            path: "SwiftMTPKit/Sources/SwiftMTPUI"),

    .executableTarget(name: "simple-probe",
                      dependencies: ["CLibusb"],
                      path: "SwiftMTPKit/Sources/Tools/simple-probe",
                      swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    .executableTarget(name: "test-xiaomi",
                      dependencies: [
                        "SwiftMTPCore",
                        "SwiftMTPTransportLibUSB",
                        "SwiftMTPObservability",
                        "CLibusb"
                      ],
                      path: "SwiftMTPKit/Sources/Tools/test-xiaomi",
                      swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    .executableTarget(name: "swiftmtp-cli",
                      dependencies: [
                        "SwiftMTPCore",
                        "SwiftMTPCLI",
                        "SwiftMTPTransportLibUSB",
                        "SwiftMTPIndex",
                        "SwiftMTPQuirks",
                        "SwiftMTPObservability",
                        "SwiftMTPStore",
                        "CLibusb"
                      ],
                      path: "SwiftMTPKit/Sources/Tools/swiftmtp-cli",
                      swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),
                      
    .executableTarget(name: "SwiftMTPApp",
                      dependencies: ["SwiftMTPUI"],
                      path: "SwiftMTPKit/Sources/Tools/SwiftMTPApp",
                      swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    .executableTarget(
      name: "MTPEndianCodecFuzz",
      dependencies: ["MTPEndianCodec", "SwiftMTPCore"],
      path: "SwiftMTPKit/Sources/Tools/MTPEndianCodecFuzz",
      swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]
    ),
                      
    .executableTarget(name: "SwiftMTPFuzz",
                      dependencies: ["SwiftMTPCore", "SwiftMTPTransportLibUSB"],
                      path: "SwiftMTPKit/Sources/Tools/SwiftMTPFuzz"),

    // Tests
    .testTarget(name: "BDDTests",
                dependencies: ["SwiftMTPCore", "SwiftMTPTransportLibUSB", .product(name: "CucumberSwift", package: "CucumberSwift")],
                path: "SwiftMTPKit/Tests/BDDTests",
                resources: [.copy("Features")]),

    .testTarget(name: "SwiftMTPCLITests",
                dependencies: ["SwiftMTPCLI", "SwiftMTPCore", "SwiftCheck"],
                path: "SwiftMTPKit/Tests/SwiftMTPCLITests"),

    .testTarget(
      name: "MTPEndianCodecTests",
      dependencies: [
        "MTPEndianCodec",
        "SwiftMTPCore",
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
      ],
      path: "SwiftMTPKit/Tests/MTPEndianCodecTests",
      resources: [.copy("Corpus")]
    ),
                
    .testTarget(name: "PropertyTests",
                dependencies: [
                    "SwiftMTPCore",
                    "SwiftMTPIndex",
                    "SwiftMTPObservability",
                    "SwiftMTPStore",
                    "SwiftMTPQuirks",
                    "SwiftCheck",
                ],
                path: "SwiftMTPKit/Tests/PropertyTests"),
                
    .testTarget(name: "SnapshotTests",
                dependencies: [
                    "SwiftMTPCore", 
                    "SwiftMTPIndex",
                    .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
                ],
                path: "SwiftMTPKit/Tests/SnapshotTests",
                exclude: ["__Snapshots__"]),
  ]
)
