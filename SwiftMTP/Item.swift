//
//  Item.swift
//  SwiftMTP
//
//  Created by Steven Zimmerman on 2025-09-01.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
