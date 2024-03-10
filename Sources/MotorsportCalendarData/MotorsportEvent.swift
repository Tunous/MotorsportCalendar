//
//  MotorsportEvent.swift
//  
//
//  Created by Łukasz Rutkowski on 26/02/2024.
//

import Foundation

public struct MotorsportEvent: Codable {
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let stages: [MotorsportEventStage]
    public let isConfirmed: Bool

    public init(
        title: String,
        startDate: Date,
        endDate: Date,
        stages: [MotorsportEventStage],
        isConfirmed: Bool
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.stages = stages
        self.isConfirmed = isConfirmed
    }
}
