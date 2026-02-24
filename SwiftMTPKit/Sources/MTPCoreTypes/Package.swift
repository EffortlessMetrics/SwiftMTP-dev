// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "MTPCoreTypes",
  defaultLocalization: "en",
  platforms: [.macOS(.v15), .iOS(.v18)],
  products: [
    .library(name: "MTPCoreTypes", targets: ["MTPCoreTypes"])
  ],
  dependencies: [
    .package(path: "../MTPEndianCodec")
  ],
  targets: [
    .target(
      name: "MTPCoreTypes",
      dependencies: [
        "MTPEndianCodec"
      ],
      swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),
    .testTarget(
      name: "MTPCoreTypesTests",
      dependencies: ["MTPCoreTypes"]),
  ]
)
