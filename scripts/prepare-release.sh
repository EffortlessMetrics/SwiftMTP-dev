#!/usr/bin/env bash
set -euo pipefail
perl -0777 -pe 's/\.systemLibrary\([\s\S]*?providers:[\s\S]*?\),/.binaryTarget(name: "CLibusb", path: "ThirdParty\\/CLibusb.xcframework"),/g' \
  SwiftMTPKit/Package.swift > SwiftMTPKit/Package.swift.tmp
mv SwiftMTPKit/Package.swift.tmp SwiftMTPKit/Package.swift
