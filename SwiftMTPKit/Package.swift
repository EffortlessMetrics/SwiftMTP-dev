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
  ],
  dependencies: [
    // Temporarily removed external dependencies to fix compatibility issues
  ],
  targets: [
    // libusb via Homebrew for dev (dynamic)
    .systemLibrary(name: "CLibusb", path: "Sources/CLibusb", pkgConfig: "libusb-1.0", providers: [.brew(["libusb"])]),

    .executableTarget(name: "simple-probe",
                      dependencies: ["CLibusb"],
                      path: "Sources/Tools/simple-probe",
                      swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),
  ]
)
