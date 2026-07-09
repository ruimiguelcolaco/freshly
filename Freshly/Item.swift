//
//  Item.swift
//  Freshly
//
//  Created by Rui Colaço on 09/07/2026.
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
