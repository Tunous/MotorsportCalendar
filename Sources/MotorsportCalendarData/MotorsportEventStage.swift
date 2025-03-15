//
//  MotorsportEventStage.swift
//  
//
//  Created by Łukasz Rutkowski on 26/02/2024.
//

import Foundation

public struct MotorsportEventStage: Codable, Hashable, Sendable {
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isConfirmed: Bool

    public init(
        title: String,
        startDate: Date,
        endDate: Date,
        isConfirmed: Bool = true
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isConfirmed = isConfirmed
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decode(String.self, forKey: .title)
        self.startDate = try container.decode(Date.self, forKey: .startDate)
        self.endDate = try container.decode(Date.self, forKey: .endDate)
        self.isConfirmed = try container.decodeIfPresent(Bool.self, forKey: .isConfirmed) ?? true
    }
}
