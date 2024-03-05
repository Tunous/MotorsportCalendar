//
//  CalendarProvider.swift
//  
//
//  Created by Łukasz Rutkowski on 05/03/2024.
//

import Foundation
import MotorsportCalendarData

protocol CalendarProvider {
    var outputURL: URL { get }
    var series: Series { get }

    func events(year: Int) async throws -> [MotorsportEvent]
}

extension CalendarProvider {
    func run(year: Int) async throws -> Bool {
        print("[\(Self.self)] Updating calendar…")

        let events = try await events(year: year)
        let eventsData = try JSONEncoder.motorsportCalendar.encode(events)

        let directory = outputURL.appending(path: series.rawValue)
        let url = directory.appending(path: "\(year).json")
        let storedEventsData = try? Data(contentsOf: url)

        if eventsData == storedEventsData {
            print("[\(Self.self)] Calendar unchanged")
            return false
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try eventsData.write(to: url)
        print("[\(Self.self)] Updated calendar")
        return true
    }
}
