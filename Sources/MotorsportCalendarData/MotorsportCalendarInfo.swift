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

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawUpdates = try container.decode([String: Date].self, forKey: .updates)
        let seriesUpdates = rawUpdates.compactMap { (key, date) -> (Series, Date)? in
            guard let series = Series(rawValue: key) else { return nil }
            return (series, date)
        }
        self.updates = Dictionary(uniqueKeysWithValues: seriesUpdates)
    }
}
