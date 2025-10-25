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
    public var type: MotorsportEventStageType

    public init(
        title: String,
        startDate: Date,
        endDate: Date,
        isConfirmed: Bool = true,
        type: MotorsportEventStageType
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isConfirmed = isConfirmed
        self.type = type
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decode(String.self, forKey: .title)
        self.startDate = try container.decode(Date.self, forKey: .startDate)
        self.endDate = try container.decode(Date.self, forKey: .endDate)
        self.isConfirmed = try container.decodeIfPresent(Bool.self, forKey: .isConfirmed) ?? true
        self.type = try container.decode(MotorsportEventStageType.self, forKey: .type)
    }
}

public struct MotorsportEventStageType: Codable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.rawValue = "unknown"
        } else {
            self.rawValue = try container.decode(String.self)
        }
    }

    // MARK: - Formula 1 stages

    public static let training = MotorsportEventStageType("training")
    public static let qualifying = MotorsportEventStageType("qualifying")
    public static let sprint = MotorsportEventStageType("sprint")
    public static let sprintQualifying = MotorsportEventStageType("sprint_qualifying")
    public static let race = MotorsportEventStageType("race")

    // MARK: - WRC stages

    public static let shakedown = MotorsportEventStageType("shakedown")
    public static let start = MotorsportEventStageType("start")
    public static let specialStage = MotorsportEventStageType("special_stage")
    public static let regroup = MotorsportEventStageType("regroup")
    public static let service = MotorsportEventStageType("service")
    public static let flexiService = MotorsportEventStageType("flexi_service")
    public static let powerStage = MotorsportEventStageType("power_stage")
    public static let podium = MotorsportEventStageType("podium")

    // MARK: - WEC stages

    public static let hyperpole = MotorsportEventStageType("hyperpole")
}
