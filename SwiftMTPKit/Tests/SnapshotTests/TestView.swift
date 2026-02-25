// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import SwiftUI

struct TestView: View {
  var body: some View {
    VStack {
      Text("SwiftMTP Visual Test")
        .font(.title)
        .padding()

      HStack {
        Image(systemName: "externaldrive.fill")
        Text("Device Connected")
      }
      .padding()
      .background(Color.blue.opacity(0.1))
      .cornerRadius(8)
    }
    .frame(width: 300, height: 200)
    .background(Color.white)
  }
}
