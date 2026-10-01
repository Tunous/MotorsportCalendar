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
                events = try RacingICalParser.parse(calendarURL, year: year, series: series)
            } catch CalendarParsingError.invalidICalendar {
                logParseWarning("iCal unavailable at \(calendarURL.absoluteString), falling back to event page schedule")
                events = try WECEventPageParser.event(from: eventDocument, year: year, series: series).map { [$0] } ?? []
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
        let sessions = try WECPageSession.all(in: try timemodeSwitch(in: document))
        return Dictionary(uniqueKeysWithValues: sessions.map { ($0.name, $0.isConfirmed) })
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
        var startDates: [String: Date] = [:]
        for session in try WECPageSession.all(in: try timemodeSwitch(in: document)) {
            startDates[session.name] = session.startDate
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

private func timemodeSwitch(in document: Document) throws -> Elements {
    try document.select("[is=timemode-switch]")
}

/// A session listed in the schedule on a WEC event page.
struct WECPageSession {
    let name: String
    /// Missing while the session time is TBC.
    let startDate: Date?
    let isConfirmed: Bool

    static func all(in root: Elements) throws -> [WECPageSession] {
        try root.select("div.d-flex.flex-column.align-items-start.gap-1").array().compactMap { session in
            guard let nameElement = try session.select("div.fw-bold.lh-sm").first() else { return nil }
            let name = try nameElement.text().trimmingWhitespace()
            guard !name.isEmpty else { return nil }

            let startDate = try session.select("[data-timestamp]").first()
                .flatMap { TimeInterval(try $0.attr("data-timestamp")) }
                .map { Date(timeIntervalSince1970: $0) }
            let timeText = try session.select("div.text-primary.fst-italic").first()?.text() ?? ""
            return WECPageSession(
                name: name,
                startDate: startDate,
                isConfirmed: !timeText.localizedCaseInsensitiveContains("TBC")
            )
        }
    }
}

/// Builds an event from the schedule shown on the event page. Used when the
/// iCalendar feed is not published yet (e.g. next season's events).
enum WECEventPageParser {
    private static let secondsInDay: TimeInterval = 24 * 60 * 60

    static func event(from document: Document, year: Int, series: Series) throws -> MotorsportEvent? {
        let title = EventTitleCleaner(year: year).clean(
            try document.select("h1 span").array().map { try $0.text() }.joined(separator: " ")
        )
        guard !title.isEmpty else { return nil }
        let utcOffset = try trackUTCOffset(from: document)
        let raceDuration = raceDuration(fromTitle: title)

        var stages: [MotorsportEventStage] = []
        for day in try document.select("[is=timemode-switch] .grid > div") {
            guard
                let dayHeader = try day.select("div.ff-normal").first(),
                let dayStart = dayStart(from: try dayHeader.text(), year: year, utcOffset: utcOffset)
            else {
                continue
            }
            let dayEnd = dayStart.addingTimeInterval(secondsInDay)

            for session in try WECPageSession.all(in: Elements([day])) {
                let id = StableIdentifier.session(session.name, series: series)
                let endDate = if let startDate = session.startDate, id == "race", let raceDuration {
                    startDate.addingTimeInterval(raceDuration)
                } else {
                    // Page has no session durations, so sessions last until the end of the track day.
                    max(dayEnd, session.startDate ?? dayStart)
                }
                stages.append(
                    MotorsportEventStage(
                        id: id,
                        title: session.name,
                        startDate: session.startDate ?? dayStart,
                        endDate: endDate,
                        isConfirmed: session.isConfirmed,
                        isSignificant: !session.name.localizedCaseInsensitiveContains("practice")
                    )
                )
            }
        }

        guard
            let startDate = stages.map(\.startDate).min(),
            let endDate = stages.map(\.endDate).max()
        else {
            return nil
        }
        return MotorsportEvent(
            id: StableIdentifier.event(title, series: series),
            title: title,
            startDate: startDate,
            endDate: endDate,
            stages: stages.sorted(using: KeyPathComparator(\.startDate)),
            isConfirmed: stages.allSatisfy(\.isConfirmed),
            isCancelled: false
        )
    }

    /// Race length from titles like "24 Hours of Le Mans".
    static func raceDuration(fromTitle title: String) -> TimeInterval? {
        guard
            let match = title.firstMatch(of: /\b(\d+)\s+Hours\b/.ignoresCase()),
            let hours = Int(match.1)
        else {
            return nil
        }
        return TimeInterval(hours * 60 * 60)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "hh:mm a"
        return formatter
    }()

    /// Derives the track UTC offset from a session showing both its track-local time and its timestamp.
    /// Falls back to UTC when no session is scheduled yet.
    static func trackUTCOffset(from document: Document) throws -> TimeInterval {
        for element in try document.select("[is=timemode-switch] [data-local][data-timestamp]") {
            guard
                let timestamp = TimeInterval(try element.attr("data-timestamp")),
                let localTime = timeFormatter.date(from: try element.attr("data-local"))
            else {
                continue
            }
            let utcTimeOfDay = timestamp.truncatingRemainder(dividingBy: secondsInDay)
            let localTimeOfDay = localTime.timeIntervalSince1970.truncatingRemainder(dividingBy: secondsInDay)
            var offset = localTimeOfDay - utcTimeOfDay
            if offset > 14 * 60 * 60 { offset -= secondsInDay }
            if offset < -12 * 60 * 60 { offset += secondsInDay }
            return offset
        }
        return 0
    }

    /// Parses a day header like "March 25th" into the start of that day in track time.
    static func dayStart(from header: String, year: Int, utcOffset: TimeInterval) -> Date? {
        EventDay.parse(header, year: year)?.startOfDayUTC?.addingTimeInterval(-utcOffset)
    }
}
