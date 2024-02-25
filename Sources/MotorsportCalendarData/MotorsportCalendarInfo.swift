//
//  MotorsportCalendarInfo.swift
//
//
//  Created by Łukasz Rutkowski on 25/02/2024.
//

import Foundation

public struct MotorsportCalendarInfo: Codable {
    public package(set) var updates: Updates

    package init(updates: Updates) {
        self.updates = updates
    }

    public struct Updates: Codable {
        public package(set) var formula1: Date
        public package(set) var wrc: Date

        package init(formula1: Date, wrc: Date) {
            self.formula1 = formula1
            self.wrc = wrc
        }
    }
}
