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
    .executable(name: "swiftmtp", targets: ["swiftmtp-cli"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
    .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0")
  ],
  targets: [
    .target(name: "SwiftMTPObservability",
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    .target(name: "SwiftMTPCore",
            dependencies: [
              "SwiftMTPObservability",
              .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
              .product(name: "Collections", package: "swift-collections")
            ],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    // libusb via Homebrew for dev (dynamic)
    .systemLibrary(name: "CLibusb", pkgConfig: "libusb-1.0", providers: [.brew(["libusb"])]),

    .target(name: "SwiftMTPTransportLibUSB",
            dependencies: [
              "SwiftMTPCore", "SwiftMTPObservability", "CLibusb",
              .product(name: "Atomics", package: "swift-atomics")
            ],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    .target(name: "SwiftMTPIndex",
            dependencies: ["SwiftMTPCore", .product(name: "Collections", package: "swift-collections")],
            resources: [.copy("Schema.sql")],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    .target(name: "SwiftMTPSync",
            dependencies: ["SwiftMTPCore", "SwiftMTPIndex", "SwiftMTPObservability"],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    .executableTarget(name: "swiftmtp-cli",
                      dependencies: ["SwiftMTPCore", "SwiftMTPIndex", "SwiftMTPSync"],
                      swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),

    .testTarget(name: "CoreTests", dependencies: ["SwiftMTPCore"]),
    .testTarget(name: "IndexTests", dependencies: ["SwiftMTPIndex"]),
    .testTarget(name: "TransportTests", dependencies: ["SwiftMTPTransportLibUSB"]),
    .testTarget(name: "ScenarioTests", dependencies: ["SwiftMTPCore", "SwiftMTPObservability"]),
  ]
)
