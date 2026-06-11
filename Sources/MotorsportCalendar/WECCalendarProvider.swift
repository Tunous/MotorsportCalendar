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
        let baseURL = URL(string: "https://www.fiawec.com")!
        logParseInfo("Loading season page \(baseURL.absoluteString) for \(year)")
        let html = try String(contentsOf: baseURL, encoding: .utf8)
        let document = try SwiftSoup.parse(html, baseURL.absoluteString)
        guard let elements = try document.select(".season-overview .season-content").last()?.select("a") else {
            logParseWarning("Season overview links not found")
            return []
        }

        var allEvents: [MotorsportEvent] = []
        for element in elements {
            let href = try element.attr("href")
            guard let eventURL = URL(string: href, relativeTo: baseURL)?.absoluteURL else {
                logParseWarning("Invalid event URL: \(href)")
                continue
            }

            let eventHTML = try String(contentsOf: eventURL, encoding: .utf8)
            let eventDocument = try SwiftSoup.parse(eventHTML, eventURL.absoluteString)

            let isConfirmedMapping = try extractConfirmedState(from: eventDocument)
            guard let calendarURLString = try extractCalendarURL(from: eventDocument) else {
                logParseWarning("Calendar URL missing on event page \(eventURL.absoluteString)")
                continue
            }
            let calendarURL = try unwrap(URL(string: calendarURLString, relativeTo: eventURL)?.absoluteURL)

            var events: [MotorsportEvent]
            do {
                events = try RacingICalParser.parse(calendarURL, year: year)
            } catch {
                logParseError("Failed parsing iCal \(calendarURL.absoluteString): \(error)")
                throw error
            }

            if events.isEmpty {
                logParseWarning("No events parsed from \(calendarURL.absoluteString)")
            }
            if !events.isEmpty {
                let itineraryStartDates = try WECItineraryParser.startDates(from: eventDocument)
                WECItineraryParser.apply(startDates: itineraryStartDates, to: &events[0])
                updateEventConfirmedState(&events[0], isConfirmedMapping: isConfirmedMapping)
            }
            allEvents.append(contentsOf: events)
        }

        for event in allEvents where event.stages.isEmpty {
            logParseWarning("Event has no stages: \(event.title)")
        }

        return await onlyNotEndedEvents(allEvents, year: year)
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

    private func extractConfirmedState(from document: Document) throws -> [String: Bool] {
        let currentSessions = try document.select("[is=timemode-switch] div.d-flex.flex-column.align-items-start.gap-1")
        guard !currentSessions.isEmpty else { return [:] }
        let mapping = try currentSessions.compactMap { session -> (String, Bool)? in
            guard
                let nameElement = try session.select("div.fw-bold.lh-sm").first(),
                let timeElement = try session.select("div.text-primary.fst-italic").first()
            else {
                return nil
            }
            let name = try nameElement.text().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                return nil
            }
            let timeText = try timeElement.text().trimmingCharacters(in: .whitespacesAndNewlines)
            let isConfirmed = !timeText.localizedCaseInsensitiveContains("TBC")
            return (name, isConfirmed)
        }
        return Dictionary(uniqueKeysWithValues: mapping)
    }

    private func extractCalendarURL(from document: Document) throws -> String? {
        return try document.select(#"a[href*="/race/calendar/"]"#).first()?.attr("href")
    }
}

enum WECItineraryParser {
    static func startDates(from document: Document) throws -> [String: Date] {
        let sessions = try document.select("[is=timemode-switch] div.d-flex.flex-column.align-items-start.gap-1")
        var startDates: [String: Date] = [:]

        for session in sessions {
            guard
                let nameElement = try session.select("div.fw-bold.lh-sm").first(),
                let timestampElement = try session.select("[data-timestamp]").first(),
                let timestamp = TimeInterval(try timestampElement.attr("data-timestamp"))
            else {
                continue
            }

            let name = try nameElement.text().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            startDates[name] = Date(timeIntervalSince1970: timestamp)
        }

        return startDates
    }

    static func apply(startDates: [String: Date], to event: inout MotorsportEvent) {
        for index in event.stages.indices {
            guard let correctedStartDate = startDates[event.stages[index].title] else { continue }

            let offset = correctedStartDate.timeIntervalSince(event.stages[index].startDate)
            event.stages[index].startDate = correctedStartDate
            event.stages[index].endDate = event.stages[index].endDate.addingTimeInterval(offset)
        }

        guard
            let startDate = event.stages.map(\.startDate).min(),
            let endDate = event.stages.map(\.endDate).max()
        else {
            return
        }
        event.startDate = startDate
        event.endDate = endDate
    }
}
