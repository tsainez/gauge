//
//  Item.swift
//  gauge
//
//  Created by Tony Sainez on 9/25/26.
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
