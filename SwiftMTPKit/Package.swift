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
  ],
  dependencies: [
    // Temporarily removed external dependencies to fix compatibility issues
  ],
  targets: [
    // libusb via Homebrew for dev (dynamic)
    .systemLibrary(name: "CLibusb", path: "Sources/CLibusb", pkgConfig: "libusb-1.0", providers: [.brew(["libusb"])]),

    // Core MTP functionality
    .target(name: "SwiftMTPCore",
            dependencies: [],
            path: "Sources/SwiftMTPCore"),

    // Transport layer for libusb
    .target(name: "SwiftMTPTransportLibUSB",
            dependencies: ["SwiftMTPCore", "CLibusb"],
            path: "Sources/SwiftMTPTransportLibUSB"),

    // Index and snapshot functionality (excluded for now due to SQLite dependency issues)
    // .target(name: "SwiftMTPIndex",
    //         dependencies: ["SwiftMTPCore"],
    //         path: "Sources/SwiftMTPIndex",
    //         exclude: ["Schema.sql"]),

    // Sync and mirror functionality (excluded for now due to SwiftMTPIndex dependency)
    // .target(name: "SwiftMTPSync",
    //         dependencies: ["SwiftMTPCore", "SwiftMTPIndex"],
    //         path: "Sources/SwiftMTPSync"),

    // Observability utilities
    .target(name: "SwiftMTPObservability",
            dependencies: ["SwiftMTPCore"],
            path: "Sources/SwiftMTPObservability"),

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
                        "CLibusb"
                      ],
                      path: "Sources/Tools/swiftmtp-cli",
                      swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),
  ]
)
