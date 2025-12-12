//
//  MotorsportCalendarInfo.swift
//
//
//  Created by Łukasz Rutkowski on 25/02/2024.
//

import Foundation

public struct MotorsportCalendarInfo: Codable {
    public var updatesByYear: [Int: [Series: Date]]

    public init(updates: [Int: [Series: Date]]) {
        self.updatesByYear = updates
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawUpdates = try container.decode([String: Date].self, forKey: .updates)
        self.updatesByYear = [:]
        for (key, date) in rawUpdates {
            let splitKey = key.split(separator: ":")
            guard
                !splitKey.isEmpty,
                let series = Series(rawValue: String(splitKey[0])),
                let year = splitKey.count > 1 ? Int(splitKey[1]) : 2025
            else { continue }

            self.updatesByYear[year, default: [:]][series] = date
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var rawUpdates: [String: Date] = [:]
        for (year, updates) in updatesByYear {
            for (series, date) in updates {
                rawUpdates["\(series):\(year)"] = date
            }
        }
        try container.encode(rawUpdates, forKey: .updates)
    }

    enum CodingKeys: CodingKey {
        case updates
    }
}

