// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "SwiftMTPKit",
  defaultLocalization: "en",
  platforms: [.macOS(.v26), .iOS(.v26)],
  products: [
    .library(name: "MTPEndianCodec", targets: ["MTPEndianCodec"]),
    .library(name: "SwiftMTPCore", targets: ["SwiftMTPCore"]),
    .library(name: "SwiftMTPTransportLibUSB", targets: ["SwiftMTPTransportLibUSB"]),
    .library(name: "SwiftMTPIndex", targets: ["SwiftMTPIndex"]),
    .library(name: "SwiftMTPSync", targets: ["SwiftMTPSync"]),
    .library(name: "SwiftMTPObservability", targets: ["SwiftMTPObservability"]),
    .library(name: "SwiftMTPQuirks", targets: ["SwiftMTPQuirks"]),
    .library(name: "SwiftMTPStore", targets: ["SwiftMTPStore"]),
    .library(name: "SwiftMTPXPC", targets: ["SwiftMTPXPC"]),
    .library(name: "SwiftMTPFileProvider", targets: ["SwiftMTPFileProvider"]),
    .library(name: "SwiftMTPTestKit", targets: ["SwiftMTPTestKit"]),
    .library(name: "SwiftMTPCLI", targets: ["SwiftMTPCLI"]),
    .library(name: "SwiftMTPUI", targets: ["SwiftMTPUI"]),
    .plugin(name: "SwiftMTPBuildTool", targets: ["SwiftMTPBuildTool"]),
    .executable(name: "swiftmtp", targets: ["swiftmtp-cli"]),
    .executable(name: "SwiftMTPApp", targets: ["SwiftMTPApp"]),
    .executable(name: "MTPEndianCodecFuzz", targets: ["MTPEndianCodecFuzz"]),
    .executable(name: "SwiftMTPFuzz", targets: ["SwiftMTPFuzz"]),
    .executable(name: "simple-probe", targets: ["simple-probe"]),
    .executable(name: "test-xiaomi", targets: ["test-xiaomi"]),
    .executable(name: "learn-promote", targets: ["learn-promote"]),
    .executable(name: "swiftmtp-docs", targets: ["swiftmtp-docs"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-async-algorithms.git", exact: "1.1.1"),
    .package(url: "https://github.com/apple/swift-collections.git", exact: "1.3.0"),
    .package(url: "https://github.com/stephencelis/SQLite.swift.git", exact: "0.15.5"),
    .package(url: "https://github.com/Tyler-Keith-Thompson/CucumberSwift", from: "5.0.0"),
    .package(url: "https://github.com/typelift/SwiftCheck", from: "0.12.0"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.10.0"),
  ],
  targets: [
    // MARK: - Foundation Layer

    .target(
      name: "MTPEndianCodec",
      swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    .target(
      name: "SwiftMTPCLI",
      swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    .target(
      name: "SwiftMTPObservability",
      swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    .target(
      name: "SwiftMTPCore",
      dependencies: [
        "SwiftMTPObservability",
        "SwiftMTPQuirks",
        "SwiftMTPCLI",
        "MTPEndianCodec",
        .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
        .product(name: "Collections", package: "swift-collections"),
      ]),

    .target(
      name: "SwiftMTPStore",
      dependencies: ["SwiftMTPCore"],
      swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    // libusb via Homebrew for dev (dynamic)
    .systemLibrary(
      name: "CLibusb", path: "Sources/CLibusb", pkgConfig: "libusb-1.0",
      providers: [.brew(["libusb"])]),

    .target(
      name: "SwiftMTPTransportLibUSB",
      dependencies: [
        "SwiftMTPCore", "SwiftMTPObservability", "CLibusb",
      ]),

    .target(
      name: "SwiftMTPIndex",
      dependencies: [
        "SwiftMTPCore", "SwiftMTPStore",
        .product(name: "Collections", package: "swift-collections"),
        .product(name: "SQLite", package: "SQLite.swift"),
      ],
      resources: [.copy("Schema.sql"), .copy("LiveIndex/LiveIndexSchema.sql")],
      swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    .target(
      name: "SwiftMTPSync",
      dependencies: [
        "SwiftMTPCore", "SwiftMTPIndex", "SwiftMTPObservability", "SwiftMTPStore",
        .product(name: "SQLite", package: "SQLite.swift"),
      ],
      swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    .target(
      name: "SwiftMTPQuirks",
      dependencies: [],
      resources: [.process("Resources")]),

    .target(
      name: "SwiftMTPTestKit",
      dependencies: ["SwiftMTPCore", "SwiftMTPQuirks", "MTPEndianCodec"]),

    .target(
      name: "SwiftMTPXPC",
      dependencies: ["SwiftMTPCore", "SwiftMTPTransportLibUSB", "SwiftMTPIndex"]),

    .target(
      name: "SwiftMTPFileProvider",
      dependencies: ["SwiftMTPCore", "SwiftMTPIndex", "SwiftMTPStore", "SwiftMTPXPC"]),

    // MARK: - UI / App

    .target(
      name: "SwiftMTPUI",
      dependencies: [
        "SwiftMTPCore",
        "SwiftMTPTransportLibUSB",
        "SwiftMTPIndex",
        "SwiftMTPQuirks",
        "SwiftMTPFileProvider",
      ]),

    .plugin(
      name: "SwiftMTPBuildTool",
      capability: .command(
        intent: .custom(
          verb: "generate-docs", description: "Regenerate device documentation from quirks.json"),
        permissions: [.writeToPackageDirectory(reason: "Update device documentation pages")]
      )),

    .executableTarget(
      name: "swiftmtp-cli",
      dependencies: [
        "SwiftMTPCore", "SwiftMTPTransportLibUSB", "SwiftMTPIndex", "SwiftMTPSync",
        "SwiftMTPObservability", "SwiftMTPQuirks", "SwiftMTPStore", "SwiftMTPXPC",
      ],
      path: "Sources/Tools/swiftmtp-cli",
      swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    .executableTarget(
      name: "SwiftMTPApp",
      dependencies: ["SwiftMTPUI"],
      path: "Sources/Tools/SwiftMTPApp"),

    .executableTarget(
      name: "MTPEndianCodecFuzz",
      dependencies: ["MTPEndianCodec"],
      path: "Sources/Tools/MTPEndianCodecFuzz"),

    .executableTarget(
      name: "SwiftMTPFuzz",
      dependencies: ["SwiftMTPCore"],
      path: "Sources/Tools/SwiftMTPFuzz"),

    .executableTarget(
      name: "simple-probe",
      dependencies: ["CLibusb"],
      path: "Sources/Tools/simple-probe"),

    .executableTarget(
      name: "test-xiaomi",
      dependencies: ["SwiftMTPCore", "SwiftMTPTransportLibUSB", "CLibusb"],
      path: "Sources/Tools/test-xiaomi"),

    .executableTarget(
      name: "learn-promote",
      dependencies: ["SwiftMTPCore", "SwiftMTPQuirks"],
      path: "Sources/Tools/learn-promote"),

    .executableTarget(
      name: "swiftmtp-docs",
      dependencies: [],
      path: "Sources/Tools/docc-generator-tool"),

    .testTarget(
      name: "CoreTests",
      dependencies: [
        "SwiftMTPCore", "SwiftMTPTransportLibUSB", "CLibusb", "SwiftMTPQuirks", "SwiftMTPTestKit",
      ]),
    .testTarget(
      name: "IndexTests",
      dependencies: [
        "SwiftMTPIndex", "SwiftMTPCore", "SwiftMTPSync", "SwiftMTPTransportLibUSB", "CLibusb",
        "SwiftMTPQuirks", "SwiftMTPTestKit",
      ]),
    .testTarget(name: "TransportTests", dependencies: ["SwiftMTPTransportLibUSB", "CLibusb"]),
    .testTarget(
      name: "BDDTests",
      dependencies: [
        "SwiftMTPCore", "SwiftMTPTransportLibUSB",
        .product(name: "CucumberSwift", package: "CucumberSwift"),
      ],
      resources: [.copy("Features")]),
    .testTarget(
      name: "PropertyTests",
      dependencies: [
        "SwiftMTPCore", "SwiftMTPIndex", "SwiftMTPObservability", "SwiftMTPStore", "SwiftMTPQuirks",
        "SwiftCheck",
      ]),
    .testTarget(
      name: "SnapshotTests",
      dependencies: [
        "SwiftMTPCore",
        "SwiftMTPIndex",
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
      ],
      exclude: ["__Snapshots__"]),
    .testTarget(
      name: "TestKitTests",
      dependencies: ["SwiftMTPTestKit", "SwiftMTPCore"]),
    .testTarget(
      name: "FileProviderTests",
      dependencies: [
        "SwiftMTPFileProvider", "SwiftMTPTestKit", "SwiftMTPIndex", "SwiftMTPCore", "SwiftMTPXPC",
      ]),
    .testTarget(
      name: "XPCTests",
      dependencies: [
        "SwiftMTPXPC",
        "SwiftMTPCore",
        "SwiftMTPTestKit",
      ]),
    .testTarget(
      name: "IntegrationTests",
      dependencies: [
        "SwiftMTPCore", "SwiftMTPTransportLibUSB", "SwiftMTPIndex", "SwiftMTPFileProvider",
        "SwiftMTPXPC", "SwiftMTPQuirks", "SwiftMTPTestKit",
      ]),
    .testTarget(
      name: "StoreTests",
      dependencies: [
        "SwiftMTPStore",
        "SwiftMTPTestKit",
        "SwiftMTPCore",
      ]),
    .testTarget(
      name: "SyncTests",
      dependencies: [
        "SwiftMTPSync",
        "SwiftMTPTestKit",
        "SwiftMTPCore",
        "SwiftMTPIndex",
      ]),

    .testTarget(
      name: "ErrorHandlingTests",
      dependencies: [
        "SwiftMTPCore",
        "SwiftMTPIndex",
        "SwiftMTPStore",
        "SwiftMTPSync",
        "SwiftMTPTransportLibUSB",
        "SwiftMTPTestKit",
      ]),
    .testTarget(
      name: "ScenarioTests",
      dependencies: [
        "SwiftMTPCore",
        "SwiftMTPTransportLibUSB",
        "SwiftMTPIndex",
        "SwiftMTPSync",
        "SwiftMTPTestKit",
      ]),
    .testTarget(
      name: "ToolingTests",
      dependencies: [
        "swiftmtp-cli",
        "SwiftMTPCore",
      ]),

    // MARK: - MTPEndianCodec Tests

    .testTarget(
      name: "MTPEndianCodecTests",
      dependencies: ["MTPEndianCodec"],
      exclude: ["Corpus", "__Snapshots__"]),

    .testTarget(
      name: "SwiftMTPCLITests",
      dependencies: ["SwiftMTPCLI", "SwiftMTPCore"]),
  ]
)
