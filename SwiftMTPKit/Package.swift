// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "SwiftMTPKit",
  defaultLocalization: "en",
  platforms: [ .macOS(.v15), .iOS(.v18) ],
  products: [
    .library(name: "SwiftMTPObservability", targets: ["SwiftMTPObservability"]),
    .library(name: "SwiftMTPCore", targets: ["SwiftMTPCore"]),
    .library(name: "SwiftMTPTransportLibUSB", targets: ["SwiftMTPTransportLibUSB"]),
    .library(name: "SwiftMTPIndex", targets: ["SwiftMTPIndex"]),
    .library(name: "SwiftMTPSync", targets: ["SwiftMTPSync"]),
    .library(name: "SwiftMTPXPC", targets: ["SwiftMTPXPC"]),
    .library(name: "SwiftMTPFileProvider", targets: ["SwiftMTPFileProvider"]),
    .executable(name: "swiftmtp", targets: ["swiftmtp-cli"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
    .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0")
  ],
  targets: [
    .target(name: "SwiftMTPObservability",
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    .target(name: "SwiftMTPCore",
            dependencies: [
              "SwiftMTPObservability",
              .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
              .product(name: "Collections", package: "swift-collections")
            ]),

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

    .target(name: "SwiftMTPXPC",
            dependencies: ["SwiftMTPCore"],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    .target(name: "SwiftMTPFileProvider",
            dependencies: ["SwiftMTPXPC"],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    .executableTarget(name: "swiftmtp-cli",
                      dependencies: ["SwiftMTPCore", "SwiftMTPTransportLibUSB", "SwiftMTPIndex", "SwiftMTPSync"],
                      path: "Sources/Tools/swiftmtp-cli",
                      resources: [.copy("../../legal/licenses/THIRD-PARTY-NOTICES.md")],
                      swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    .executableTarget(name: "simple-probe",
                      dependencies: ["CLibusb"],
                      path: "Sources/Tools/simple-probe",
                      swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    .testTarget(name: "CoreTests", dependencies: ["SwiftMTPCore"]),
    .testTarget(name: "IndexTests", dependencies: ["SwiftMTPIndex"]),
    .testTarget(name: "TransportTests", dependencies: ["SwiftMTPTransportLibUSB"]),
    .testTarget(name: "ScenarioTests", dependencies: ["SwiftMTPCore", "SwiftMTPObservability", "SwiftMTPIndex"]),
  ]
)
