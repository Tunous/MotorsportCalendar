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
        guard let seasonContent = try seasonContent(in: document, year: year) else {
            logParseWarning("Season \(year) overview links not found")
            return []
        }
        let eventLinks = try seasonEventLinks(from: seasonContent, baseURL: baseURL)
        let skippedCompletedEvents = eventLinks.filter(\.isCompleted)
        let activeEventLinks = eventLinks.filter { !$0.isCompleted }
        logParseInfo("Found \(eventLinks.count) WEC event links for \(year), skipping \(skippedCompletedEvents.count) completed")

        var allEvents: [MotorsportEvent] = []
        for eventLink in activeEventLinks {
            let eventURL = eventLink.url
            logParseInfo("Loading event page \(eventURL.absoluteString)")
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
                logParseInfo("Parsing iCal \(calendarURL.absoluteString)")
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

    private func seasonContent(in document: Document, year: Int) throws -> Element? {
        let seasonIdentifier = try document
            .select(".season-overview .season-selector[data-season]")
            .first { try $0.text().localizedCaseInsensitiveContains("Season \(year)") }?
            .attr("data-season")

        if let seasonIdentifier {
            return try document
                .select(#".season-overview .season-content[data-season="\#(seasonIdentifier)"]"#)
                .first()
        }

        return try document.select(".season-overview .season-content").first()
    }

    private func seasonEventLinks(from seasonContent: Element, baseURL: URL) throws -> [WECSeasonEventLink] {
        let elements = try seasonContent.select(#"a[href*="/en/race/"]"#)
        var links: [WECSeasonEventLink] = []
        var seenURLs: Set<URL> = []

        for element in elements {
            let href = try element.attr("href")
            guard let eventURL = URL(string: href, relativeTo: baseURL)?.absoluteURL else {
                logParseWarning("Invalid event URL: \(href)")
                continue
            }
            guard seenURLs.insert(eventURL).inserted else {
                continue
            }
            links.append(
                WECSeasonEventLink(
                    url: eventURL,
                    isCompleted: try element.classNames().contains("opacity-25")
                )
            )
        }

        return links
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

private struct WECSeasonEventLink {
    let url: URL
    let isCompleted: Bool
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
