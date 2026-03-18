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
    public var isCancelled: Bool

    public init(
        title: String,
        startDate: Date,
        endDate: Date,
        stages: [MotorsportEventStage],
        isConfirmed: Bool,
        isCancelled: Bool = false,
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.stages = stages
        self.isConfirmed = isConfirmed
        self.isCancelled = isCancelled
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decode(String.self, forKey: .title)
        self.startDate = try container.decode(Date.self, forKey: .startDate)
        self.endDate = try container.decode(Date.self, forKey: .endDate)
        self.stages = try container.decode([MotorsportEventStage].self, forKey: .stages)
        self.isConfirmed = try container.decode(Bool.self, forKey: .isConfirmed)
        self.isCancelled = try container.decodeIfPresent(Bool.self, forKey: .isCancelled) ?? false
    }
}
