//
//  ContentView.swift
//  SwiftMTP
//
//  Created by Steven Zimmerman on 9/6/25.
//

import SwiftUI
import SwiftMTPUI

struct ContentView: View {
    var body: some View {
        DeviceBrowserView()
            .frame(minWidth: 800, minHeight: 500)
    }
}

#Preview {
    ContentView()
}