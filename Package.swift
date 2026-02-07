// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "SwiftMTP",
  defaultLocalization: "en",
  platforms: [ .macOS(.v15), .iOS(.v18) ],
  products: [
    .executable(name: "simple-probe", targets: ["simple-probe"]),
    .executable(name: "swiftmtp", targets: ["swiftmtp-cli"]),
    .library(name: "SwiftMTPQuirks", targets: ["SwiftMTPQuirks"]),
    .executable(name: "SwiftMTPApp", targets: ["SwiftMTPApp"]),
  ],
  dependencies: [
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
            dependencies: [],
            path: "SwiftMTPKit/Sources/SwiftMTPCore",
            sources: ["Internal", "Public", "CLI"]),

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
            dependencies: ["SwiftMTPCore"],
            path: "SwiftMTPKit/Sources/SwiftMTPObservability"),

    // Device quirks and tuning database
    .target(name: "SwiftMTPQuirks",
            dependencies: ["SwiftMTPCore"],
            path: "SwiftMTPKit/Sources/SwiftMTPQuirks",
            resources: [.process("Resources")]),

    // UI Components (SwiftUI)
    .target(name: "SwiftMTPUI",
            dependencies: ["SwiftMTPCore", "SwiftMTPSync", "SwiftMTPTransportLibUSB", "SwiftMTPObservability", "CLibusb"],
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
                        "SwiftMTPTransportLibUSB",
                        "SwiftMTPIndex",
                        "SwiftMTPQuirks",
                        "SwiftMTPObservability",
                        "CLibusb"
                      ],
                      path: "SwiftMTPKit/Sources/Tools/swiftmtp-cli",
                      swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),
                      
    .executableTarget(name: "SwiftMTPApp",
                      dependencies: ["SwiftMTPUI"],
                      path: "SwiftMTPKit/Sources/Tools/SwiftMTPApp",
                      swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),
                      
    .executableTarget(name: "SwiftMTPFuzz",
                      dependencies: ["SwiftMTPCore", "SwiftMTPTransportLibUSB"],
                      path: "SwiftMTPKit/Sources/Tools/SwiftMTPFuzz"),

    // Tests
    .testTarget(name: "BDDTests",
                dependencies: ["SwiftMTPCore", "SwiftMTPTransportLibUSB", .product(name: "CucumberSwift", package: "CucumberSwift")],
                path: "SwiftMTPKit/Tests/BDDTests",
                resources: [.copy("Features")]),
                
    .testTarget(name: "PropertyTests",
                dependencies: ["SwiftMTPCore", "SwiftCheck"],
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