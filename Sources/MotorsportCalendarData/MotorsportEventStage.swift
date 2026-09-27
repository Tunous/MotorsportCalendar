//
//  MotorsportEventStage.swift
//  
//
//  Created by Łukasz Rutkowski on 26/02/2024.
//

import Foundation

public struct MotorsportEventStage: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isConfirmed: Bool
    public var isSignificant: Bool

    public init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isConfirmed: Bool = true,
        isSignificant: Bool = true,
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isConfirmed = isConfirmed
        self.isSignificant = isSignificant
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.startDate = try container.decode(Date.self, forKey: .startDate)
        self.endDate = try container.decode(Date.self, forKey: .endDate)
        self.isConfirmed = try container.decodeIfPresent(Bool.self, forKey: .isConfirmed) ?? true
        self.isSignificant = try container.decodeIfPresent(Bool.self, forKey: .isSignificant) ?? true
    }
}
