//
//  CalendarProvider.swift
//  
//
//  Created by Łukasz Rutkowski on 05/03/2024.
//

import Foundation
import MotorsportCalendarData

protocol CalendarProvider: Sendable {
    var outputURL: URL { get }
    var series: Series { get }

    func events(year: Int) async throws -> [MotorsportEvent]
}

extension CalendarProvider {
    func run(year: Int) async throws -> Bool {
        let events = try await events(year: year)
        let eventsData = try JSONEncoder.motorsportCalendar.encode(events)

        let directory = outputURL.appending(path: series.rawValue)
        let url = directory.appending(path: "\(year).json")
        let storedEventsData = try? Data(contentsOf: url)

        if eventsData == storedEventsData {
            print("[\(series)] No changes")
            return false
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try eventsData.write(to: url)
        print("[\(series)] Updated")
        return true
    }

    func load(year: Int) async -> [MotorsportEvent]? {
        let directory = outputURL.appending(path: series.rawValue)
        let url = directory.appending(path: "\(year).json")
        guard let storedEventsData = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder.motorsportCalendar.decode([MotorsportEvent].self, from: storedEventsData)
    }
}
