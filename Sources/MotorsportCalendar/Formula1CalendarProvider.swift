//
//  Formula1CalendarProvider.swift
//  
//
//  Created by Łukasz Rutkowski on 05/03/2024.
//

import Foundation
import MotorsportCalendarData
import ICalSwift
import ArgumentParser

struct Formula1CalendarProvider: CalendarProvider {
    private let calendarURL: URL

    let outputURL: URL
    let series: Series = .formula1

    init(
        outputURL: URL,
        calendarURL: URL
    ) {
        self.outputURL = outputURL
        self.calendarURL = calendarURL
    }

    func events(year: Int) async throws -> [MotorsportEvent] {
        let updatedEvents = try RacingICalParser.parse(calendarURL, year: year)
        return await onlyNotEndedEvents(updatedEvents, year: year)
    }
}
