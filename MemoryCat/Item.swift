//
//  Item.swift
//  MemoryCat
//
//  Created by FangHao on 2025/11/20.
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
