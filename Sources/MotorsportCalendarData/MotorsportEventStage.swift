//
//  MotorsportEventStage.swift
//  
//
//  Created by Łukasz Rutkowski on 26/02/2024.
//

import Foundation

public struct MotorsportEventStage: Codable {
    public let title: String
    public let startDate: Date
    public package(set) var endDate: Date

    public init(
        title: String,
        startDate: Date,
        endDate: Date
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
    }
}
