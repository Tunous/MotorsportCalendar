//
//  WECCalendarProvider.swift
//  MotorsportCalendar
//
//  Created by Łukasz Rutkowski on 09/09/2024.
//

import Foundation
import MotorsportCalendarData
import SwiftSoup

struct WECCalendarProvider: CalendarProvider {
    let outputURL: URL
    let series: Series = .wec

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func events(year: Int) async throws -> [MotorsportEvent] {
        let url = URL(string: "https://info.sportall.tv/program/FIA%20WEC/en/output_FIA%20WEC_1_\(year).html")!
        let html = try String(contentsOf: url, encoding: .utf8)
        let document = try SwiftSoup.parse(html, "https://info.sportall.tv")
        let elements = try document.select("table.liveEventsTable")
        var allEvents: [MotorsportEvent] = []
        for element in elements {
            let isConfirmedMapping = try extractConfirmedState(from: element)
            let calendarURLString = try unwrap(element.select("a img").last()?.parent()?.attr("href"))
            let calendarURL = URL(string: calendarURLString)
            var events = try RacingICalParser.parse(calendarURL!, year: year)
            if !events.isEmpty {
                updateEventConfirmedState(&events[0], isConfirmedMapping: isConfirmedMapping)
            }

            allEvents.append(contentsOf: events)
        }
        return allEvents
    }

    private func updateEventConfirmedState(_ event: inout MotorsportEvent, isConfirmedMapping: [String: Bool]) {
        for index in event.stages.indices {
            let stage = event.stages[index]
            let isStageConfirmed = isConfirmedMapping[stage.title] ?? stage.isConfirmed
            event.stages[index].isConfirmed = isStageConfirmed
            if !isStageConfirmed {
                event.isConfirmed = false
            }
        }
    }

    private func extractConfirmedState(from element: Element) throws -> [String: Bool] {
        let sessions = try element.select("#sessions tr")
        let isConfirmedMapping = try sessions.map { session in
            let name = try session.child(0).text()
            let timeText = try session.children().last()?.text()
            let isConfirmed = timeText != "TBC"
            return (name, isConfirmed)
        }
        return Dictionary(uniqueKeysWithValues: isConfirmedMapping)
    }
}
