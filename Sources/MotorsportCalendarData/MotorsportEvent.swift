//
//  MotorsportEvent.swift
//  
//
//  Created by Łukasz Rutkowski on 26/02/2024.
//

import Foundation

public struct MotorsportEvent: Codable, Hashable, Sendable {
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var stages: [MotorsportEventStage]
    public var isConfirmed: Bool

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
