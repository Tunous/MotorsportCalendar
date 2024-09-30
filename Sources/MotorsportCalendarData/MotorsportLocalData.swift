//
//  MotorsportLocalData.swift
//  MotorsportCalendar
//
//  Created by Łukasz Rutkowski on 30/09/2024.
//

import Foundation

public enum MotorsportLocalData {
    public static func events(series: Series, year: Int) -> [MotorsportEvent] {
        guard
            let url = Bundle.module.url(forResource: "Data/\(series.rawValue)/\(year)", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let events = try? JSONDecoder.motorsportCalendar.decode([MotorsportEvent].self, from: data)
        else {
            return []
        }
        return events
    }
}
