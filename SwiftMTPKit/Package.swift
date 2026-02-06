// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "SwiftMTPKit",
  defaultLocalization: "en",
  platforms: [ .macOS(.v15), .iOS(.v18) ],
  products: [
    .executable(name: "simple-probe", targets: ["simple-probe"]),
    .executable(name: "swiftmtp", targets: ["swiftmtp-cli"]),
    .library(name: "SwiftMTPQuirks", targets: ["SwiftMTPQuirks"]),
    // .executable(name: "learn-promote", targets: ["learn-promote"]),
  ],
  dependencies: [
    // SQLite3 via system library
    .package(url: "https://github.com/Tyler-Keith-Thompson/CucumberSwift", from: "5.0.0"),
    .package(url: "https://github.com/typelift/SwiftCheck", from: "0.12.0"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.10.0"),
  ],
  targets: [
    // SQLite3 via system library
    .systemLibrary(name: "CSQLite", path: "Sources/CSQLite", providers: [.apt(["libsqlite3-dev"]), .brew(["sqlite"])]),

    // libusb via Homebrew for dev (dynamic)
    .systemLibrary(name: "CLibusb", path: "Sources/CLibusb", pkgConfig: "libusb-1.0", providers: [.brew(["libusb"])]),

    // Core MTP functionality
    .target(name: "SwiftMTPCore",
            dependencies: [],
            path: "Sources/SwiftMTPCore",
            sources: ["Internal", "Public", "CLI"]),

    // Transport layer for libusb
    .target(name: "SwiftMTPTransportLibUSB",
            dependencies: ["SwiftMTPCore", "CLibusb"],
            path: "Sources/SwiftMTPTransportLibUSB"),

    // Index and snapshot functionality
    .target(name: "SwiftMTPIndex",
            dependencies: ["SwiftMTPCore", "CSQLite"],
            path: "Sources/SwiftMTPIndex",
            exclude: ["Schema.sql"]),

    // Sync and mirror functionality
    .target(name: "SwiftMTPSync",
            dependencies: ["SwiftMTPCore", "SwiftMTPIndex"],
            path: "Sources/SwiftMTPSync"),

    // Observability utilities
    .target(name: "SwiftMTPObservability",
            dependencies: ["SwiftMTPCore"],
            path: "Sources/SwiftMTPObservability"),

    // Device quirks and tuning database
    .target(name: "SwiftMTPQuirks",
            dependencies: ["SwiftMTPCore"],
            path: "Sources/SwiftMTPQuirks",
            resources: [.process("Resources")]),

    // UI Components (SwiftUI)
    .target(name: "SwiftMTPUI",
            dependencies: ["SwiftMTPCore", "SwiftMTPSync", "SwiftMTPTransportLibUSB", "SwiftMTPObservability", "CLibusb"],
            path: "Sources/SwiftMTPUI"),

    // File Provider extension (excluded for now due to SwiftMTPXPC dependency)
    // .target(name: "SwiftMTPFileProvider",
    //         dependencies: ["SwiftMTPCore", "SwiftMTPTransportLibUSB"],
    //         path: "Sources/SwiftMTPFileProvider"),

    // XPC service (excluded for now due to @objc compatibility issues)
    // .target(name: "SwiftMTPXPC",
    //         dependencies: ["SwiftMTPCore", "SwiftMTPTransportLibUSB"],
    //         path: "Sources/SwiftMTPXPC"),

    .executableTarget(name: "simple-probe",
                      dependencies: ["CLibusb"],
                      path: "Sources/Tools/simple-probe",
                      swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    .executableTarget(name: "test-xiaomi",
                      dependencies: [
                        "SwiftMTPCore",
                        "SwiftMTPTransportLibUSB",
                        "SwiftMTPObservability",
                        "CLibusb"
                      ],
                      path: "Sources/Tools/test-xiaomi",
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
                      path: "Sources/Tools/swiftmtp-cli",
                      swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),
                      
    .executableTarget(name: "SwiftMTPApp",
                      dependencies: ["SwiftMTPUI"],
                      path: "Sources/Tools/SwiftMTPApp",
                      swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),
                      
    .executableTarget(name: "SwiftMTPFuzz",
                      dependencies: ["SwiftMTPCore", "SwiftMTPTransportLibUSB"],
                      path: "Sources/Tools/SwiftMTPFuzz"),

    // .executableTarget(name: "learn-promote",
    //                   dependencies: ["SwiftMTPCore"],
    //                   path: "Sources/Tools/learn-promote",
    //                   swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    // Tests
    .testTarget(name: "BDDTests",
                dependencies: ["SwiftMTPCore", "SwiftMTPTransportLibUSB", .product(name: "CucumberSwift", package: "CucumberSwift")],
                path: "Tests/BDDTests",
                resources: [.copy("Features")]),
                
    .testTarget(name: "PropertyTests",
                dependencies: ["SwiftMTPCore", "SwiftCheck"],
                path: "Tests/PropertyTests"),
                
    .testTarget(name: "SnapshotTests",
                dependencies: [
                    "SwiftMTPCore", 
                    "SwiftMTPIndex",
                    .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
                ],
                path: "Tests/SnapshotTests",
                exclude: ["__Snapshots__"]),
  ]
)
