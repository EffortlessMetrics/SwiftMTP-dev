//
//  Item.swift
//  SwiftMTP
//
//  Created by Steven Zimmerman on 9/6/25.
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
