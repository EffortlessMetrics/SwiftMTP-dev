//
//  ContentView.swift
//  SwiftMTP
//
//  Created by Steven Zimmerman on 9/6/25.
//

import SwiftUI
#if canImport(SwiftMTPUI)
import SwiftMTPUI
#endif

struct ContentView: View {
    var body: some View {
        Group {
            #if canImport(SwiftMTPUI)
            DeviceBrowserView()
            #else
            VStack(spacing: 12) {
                Text("SwiftMTP")
                    .font(.title)
                Text("SwiftMTPKit UI modules are unavailable in this build configuration.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }
            #endif
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}

#Preview {
    ContentView()
}
