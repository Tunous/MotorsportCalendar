//
//  MotorsportCalendarInfo.swift
//
//
//  Created by Łukasz Rutkowski on 25/02/2024.
//

import Foundation

public struct MotorsportCalendarInfo: Codable {
    public package(set) var updates: [Series: Date]

    package init(updates: [Series: Date]) {
        self.updates = updates
    }
}
