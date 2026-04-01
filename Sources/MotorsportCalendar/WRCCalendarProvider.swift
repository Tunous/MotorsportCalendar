//
//  WRCCalendarProvider.swift
//  
//
//  Created by Łukasz Rutkowski on 09/03/2024.
//

import Foundation
import MotorsportCalendarData
import SwiftSoup
import RegexBuilder

struct WRCCalendarProvider: CalendarProvider {
    let outputURL: URL
    let series: Series = .wrc

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func events(year: Int) async throws -> [MotorsportEvent] {
        let baseURL = URL(string: "https://www.wrc.com")!
        let calendarURL = URL(string: "https://www.wrc.com/en/calendar?rb3TabId=upcoming")!
        logParseInfo("Loading calendar page \(calendarURL.absoluteString) for \(year)")
        let document = try await getDocument(url: calendarURL, baseURL: baseURL)
        let eventCards = try document.select("a.event-feed-card[href]")
        if eventCards.isEmpty {
            logParseWarning("No event cards found on calendar page")
        }
        let existingEventsByTitle = Dictionary(
            uniqueKeysWithValues: (await load(year: year) ?? []).map { ($0.title, $0) }
        )

        var events: [MotorsportEvent] = []
        for eventCard in eventCards {
            guard
                let titleNode = try eventCard.select(".event-feed-card__title").first(),
                let dateNode = try eventCard.select("time.event-feed-card__date-text").first()
            else {
                logParseWarning("Skipping event card: missing title or date node")
                continue
            }

            let rawTitle = try titleNode.text().trimmingCharacters(in: .whitespacesAndNewlines)
            let eventTitle = cleanEventTitle(rawTitle, year: year)
            let dateTimeText = try dateNode.attr("datetime")
            guard let startDate = parseISO8601Date(dateTimeText) else {
                logParseWarning("Skipping \(eventTitle): invalid datetime '\(dateTimeText)'")
                continue
            }

            if Calendar.gmt.component(.year, from: startDate) != year {
                continue
            }

            let startDateText = try dateNode.text()
            let fallbackEndDate = parseEventEndDate(from: startDateText, fallbackStartDate: startDate) ?? startDate
            let eventPath = try eventCard.attr("href")
            guard let eventURL = URL(string: eventPath, relativeTo: baseURL)?.absoluteURL else {
                logParseWarning("Skipping \(eventTitle): invalid event URL '\(eventPath)'")
                continue
            }

            let eventYear = Calendar.gmt.component(.year, from: startDate)
            let parsedStages = try await extractStages(
                for: eventURL,
                eventTitle: eventTitle,
                baseURL: baseURL,
                fallbackYear: eventYear
            )
            let stages: [MotorsportEventStage]
            if parsedStages.isEmpty,
               let existingEvent = existingEventsByTitle[eventTitle],
               hasUsefulStages(existingEvent.stages) {
                logParseInfo("Using existing stages for \(eventTitle) because no stages were parsed this run")
                stages = existingEvent.stages
            } else {
                stages = parsedStages
            }

            if stages.isEmpty {
                logMissingStages(for: eventTitle, startDate: startDate)
            }

            let event = MotorsportEvent(
                title: eventTitle,
                startDate: stages.first?.startDate ?? startDate,
                endDate: stages.last?.endDate ?? fallbackEndDate,
                stages: stages,
                isConfirmed: !stages.isEmpty && stages.allSatisfy(\.isConfirmed)
            )
            events.append(event)
        }
        events.sort { $0.startDate < $1.startDate }
        return await onlyNotEndedEvents(events, year: year)
    }

    private func extractStages(for eventURL: URL, eventTitle: String, baseURL: URL, fallbackYear: Int) async throws -> [MotorsportEventStage] {
        guard let eventDocument = try await getDocumentIgnoringBadResponse(url: eventURL, baseURL: baseURL) else {
            logParseWarning("Event page unavailable: \(eventURL.absoluteString)")
            return []
        }

        if let itineraryPath = try findItineraryPath(in: eventDocument),
           let itineraryURL = URL(string: itineraryPath, relativeTo: eventURL)?.absoluteURL,
           let itineraryDocument = try await getDocumentIgnoringBadResponse(url: itineraryURL, baseURL: baseURL) {
            let itineraryStages = try parseStagesFromItineraryDocument(
                itineraryDocument,
                itineraryURL: itineraryURL,
                fallbackYear: fallbackYear
            )
            if !itineraryStages.isEmpty {
                return itineraryStages
            }
        }

        guard let iCalPath = try extractICalPath(from: eventDocument) else {
            return []
        }

        guard let iCalURL = URL(string: iCalPath, relativeTo: eventURL)?.absoluteURL else {
            logParseWarning("Invalid iCal URL '\(iCalPath)' for event page \(eventURL.absoluteString)")
            return []
        }

        do {
            let iCalEvents = try RacingICalParser.parse(iCalURL, year: fallbackYear)
            let fallbackEvent = bestMatchingEvent(from: iCalEvents, eventTitle: eventTitle)
            let fallbackStages = fallbackEvent?.stages ?? []
            return sanitizeStages(fallbackStages, eventTitle: eventTitle, source: "iCal fallback")
        } catch {
            logParseWarning("Failed parsing iCal fallback \(iCalURL.absoluteString): \(error)")
            return []
        }
    }

    private func parseStagesFromItineraryDocument(
        _ itineraryDocument: Document,
        itineraryURL: URL,
        fallbackYear: Int
    ) throws -> [MotorsportEventStage] {
        let timeZone = try extractEventTimeZone(from: itineraryDocument)
        let stageSections = try itineraryDocument.select(".faq-layout-view .faq-view")
        if stageSections.isEmpty {
            return []
        }

        var stages: [MotorsportEventStage] = []
        for stageSection in stageSections {
            let dateText = try stageSection.select(".faq-view__question").text()
            guard let stageDay = parseItineraryDay(from: dateText, fallbackYear: fallbackYear) else {
                logParseWarning("Skipping stage section with unparseable date '\(dateText)' at \(itineraryURL.absoluteString)")
                continue
            }

            let stageNodes = try stageSection.select(".faq-view__answer li.inline-enumeration__item")
            var lastStageDateInDay: Date?
            for stageNode in stageNodes {
                let stageText = try stageNode.text().trimmingCharacters(in: .whitespacesAndNewlines)
                guard let stageData = parseStageLine(stageText) else {
                    logParseWarning("Skipping stage line with unparseable data '\(stageText)' at \(itineraryURL.absoluteString)")
                    continue
                }
                let stageTitle = stageData.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !stageTitle.isEmpty else {
                    logParseWarning("Skipping stage with empty title at \(itineraryURL.absoluteString)")
                    continue
                }

                let stageDate: Date
                if stageData.isConfirmed {
                    guard let confirmedDate = makeDate(
                        year: stageDay.year,
                        month: stageDay.month,
                        day: stageDay.day,
                        hour: stageData.hour,
                        minute: stageData.minute,
                        timeZone: timeZone
                    ) else {
                        logParseWarning("Skipping stage '\(stageData.title)': failed to build date from \(stageDay.year)-\(stageDay.month)-\(stageDay.day) \(stageData.hour):\(stageData.minute)")
                        continue
                    }
                    stageDate = confirmedDate
                } else if let previousDate = lastStageDateInDay {
                    // Keep TBC entries aligned with prior stage time when listed later in the same day.
                    stageDate = previousDate
                } else {
                    guard let startOfDayDate = makeDate(
                        year: stageDay.year,
                        month: stageDay.month,
                        day: stageDay.day,
                        hour: 0,
                        minute: 0,
                        timeZone: timeZone
                    ) else {
                        logParseWarning("Skipping stage '\(stageData.title)': failed to build fallback day-start date for \(stageDay.year)-\(stageDay.month)-\(stageDay.day)")
                        continue
                    }
                    stageDate = startOfDayDate
                }

                stages.append(
                    MotorsportEventStage(
                        title: stageTitle,
                        startDate: stageDate,
                        endDate: stageDate,
                        isConfirmed: stageData.isConfirmed,
                        isSignificant: isSignificant(title: stageTitle)
                    )
                )
                lastStageDateInDay = stageDate
            }
        }

        if stages.isEmpty {
            return []
        }

        stages.sort { $0.startDate < $1.startDate }
        tweakDates(of: &stages)
        return stages
    }

    private func bestMatchingEvent(from events: [MotorsportEvent], eventTitle: String) -> MotorsportEvent? {
        guard !events.isEmpty else { return nil }
        let normalizedTitle = normalizedEventTitle(eventTitle)
        return events.first(where: { normalizedEventTitle($0.title) == normalizedTitle && !$0.stages.isEmpty })
            ?? events.first(where: { !$0.stages.isEmpty })
    }

    private func normalizedEventTitle(_ title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: #"\bwrc\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*-\s*rally of .+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\b\d{4}\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func logMissingStages(for eventTitle: String, startDate: Date) {
        let warningHorizon = Date.now.addingTimeInterval(60 * 60 * 24 * 45)
        if startDate <= warningHorizon {
            logParseWarning("Event has no stages: \(eventTitle)")
        } else {
            logParseInfo("Event has no stages yet (likely not published): \(eventTitle)")
        }
    }

    private func sanitizeStages(_ stages: [MotorsportEventStage], eventTitle: String, source: String) -> [MotorsportEventStage] {
        let filteredStages = stages.filter {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let droppedCount = stages.count - filteredStages.count
        if droppedCount > 0 {
            logParseInfo("Dropped \(droppedCount) empty-title stage(s) for \(eventTitle) from \(source)")
        }
        return filteredStages
    }

    private func hasUsefulStages(_ stages: [MotorsportEventStage]) -> Bool {
        stages.contains { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func isSignificant(title: String) -> Bool {
        if title.localizedCaseInsensitiveContains("shakedown") {
            return true
        }

        return title.firstMatch(of: Regex {
            ChoiceOf {
                Regex {
                    Anchor.wordBoundary
                    "SSS"
                    OneOrMore(.digit)
                    Anchor.wordBoundary
                }
                Regex {
                    Anchor.wordBoundary
                    "SS"
                    OneOrMore(.digit)
                    Anchor.wordBoundary
                }
            }
        }) != nil
    }

    private func getDocument(url: URL, baseURL: URL) async throws -> Document {
        var request = URLRequest(url: url)
        request.setValue("MotoWeekParser/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200,
            let html = String(data: data, encoding: .utf8)
        else {
            throw URLError(.badServerResponse)
        }
        return try SwiftSoup.parse(html, baseURL.absoluteString)
    }

    private func getDocumentIgnoringBadResponse(url: URL, baseURL: URL) async throws -> Document? {
        let retryDelays: [Duration] = [.zero, .milliseconds(300), .milliseconds(800)]
        var lastError: Error?

        for delay in retryDelays {
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }

            do {
                return try await getDocument(url: url, baseURL: baseURL)
            } catch {
                lastError = error
                logParseWarning("Failed loading \(url.absoluteString): \(error)")

                if let urlError = error as? URLError {
                    switch urlError.code {
                    case .badServerResponse, .timedOut, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
                        continue
                    default:
                        throw error
                    }
                } else {
                    throw error
                }
            }
        }

        if let urlError = lastError as? URLError, urlError.code == .badServerResponse {
            return nil
        }

        throw lastError ?? URLError(.unknown)
    }

    private func parseISO8601Date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime, .withTimeZone]
        return formatter.date(from: text)
    }

    private func parseEventEndDate(from text: String, fallbackStartDate: Date) -> Date? {
        let normalizedText = text.replacingOccurrences(of: "–", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)

        if let match = normalizedText.firstMatch(of: #/^\s*(?<startDay>\d{1,2})\s*-\s*(?<endDay>\d{1,2})\s+(?<month>[A-Za-z]+)\s+(?<year>\d{4})\s*$/#) {
            guard
                let month = monthNumber(from: String(match.output.month)),
                let year = Int(match.output.year),
                let endDay = Int(match.output.endDay)
            else {
                return nil
            }
            return makeDate(year: year, month: month, day: endDay, hour: 23, minute: 59, timeZone: .gmt)
        }

        if let match = normalizedText.firstMatch(of: #/^\s*(?<startDay>\d{1,2})\s+(?<startMonth>[A-Za-z]+)\s*-\s*(?<endDay>\d{1,2})\s+(?<endMonth>[A-Za-z]+)\s+(?<year>\d{4})\s*$/#) {
            guard
                let month = monthNumber(from: String(match.output.endMonth)),
                let year = Int(match.output.year),
                let endDay = Int(match.output.endDay)
            else {
                return nil
            }
            return makeDate(year: year, month: month, day: endDay, hour: 23, minute: 59, timeZone: .gmt)
        }

        if let match = normalizedText.firstMatch(of: #/^\s*(?<day>\d{1,2})\s+(?<month>[A-Za-z]+)\s+(?<year>\d{4})\s*$/#) {
            guard
                let month = monthNumber(from: String(match.output.month)),
                let year = Int(match.output.year),
                let day = Int(match.output.day)
            else {
                return nil
            }
            return makeDate(year: year, month: month, day: day, hour: 23, minute: 59, timeZone: .gmt)
        }

        return Calendar.gmt.date(byAdding: .day, value: 2, to: fallbackStartDate)
    }

    private func cleanEventTitle(_ text: String, year: Int) -> String {
        return text
            .replacingOccurrences(of: #"\s+\#(year)$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*WRC\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func findItineraryPath(in document: Document) throws -> String? {
        let scripts = try document.select("script")
        for script in scripts {
            let scriptContent = try script.html()

            if let match = scriptContent.firstMatch(of: #/"label":"Itinerary","url":"(?<url>[^"]+)"/#) {
                return String(match.output.url).replacingOccurrences(of: #"\/"#, with: "/")
            }

            if let match = scriptContent.firstMatch(of: #/"text":"Itinerary","link":"(?<url>[^"]+)"/#) {
                return String(match.output.url).replacingOccurrences(of: #"\/"#, with: "/")
            }
        }
        return nil
    }

    private func extractICalPath(from document: Document) throws -> String? {
        let scripts = try document.select("script")
        for script in scripts {
            let scriptContent = try script.html()
            if let match = scriptContent.firstMatch(of: #/"icalLink":"(?<url>[^"]+)"/#) {
                return String(match.output.url).replacingOccurrences(of: #"\/"#, with: "/")
            }
        }
        return nil
    }

    private func parseItineraryDay(from text: String, fallbackYear: Int) -> (year: Int, month: Int, day: Int)? {
        let normalized = text.replacingOccurrences(of: "\u{00a0}", with: " ")
        let extractedYear = normalized.firstMatch(of: #/(?<year>\d{4})/#).flatMap { Int($0.output.year) } ?? fallbackYear

        if let numericMatch = normalized.firstMatch(of: #/(?<day>\d{1,2})\.(?<month>\d{1,2})\.?/#),
           let day = Int(numericMatch.output.day),
           let month = Int(numericMatch.output.month),
           (1...31).contains(day),
           (1...12).contains(month) {
            return (extractedYear, month, day)
        }

        // Handles malformed headers like "Saturday, April 202611" => April 11, 2026
        if let concatMatch = normalized.firstMatch(of: #/(?<month>[A-Za-z]+)\s+(?<year>\d{4})(?<day>\d{1,2})\b/#),
           let month = monthNumber(from: String(concatMatch.output.month)),
           let year = Int(concatMatch.output.year),
           let day = Int(concatMatch.output.day),
           (1...31).contains(day) {
            return (year, month, day)
        }

        if let monthDayYear = normalized.firstMatch(of: #/(?<month>[A-Za-z]+)\s+(?<day>\d{1,2})(?!\d)(?:,?\s*(?<year>\d{4}))?/#),
           let month = monthNumber(from: String(monthDayYear.output.month)),
           let day = Int(monthDayYear.output.day),
           (1...31).contains(day) {
            let year = monthDayYear.output.year.flatMap { Int($0) } ?? extractedYear
            return (year, month, day)
        }

        if let dayMonthYear = normalized.firstMatch(of: #/(?<day>\d{1,2})(?!\d)\s+(?<month>[A-Za-z]+)(?:\s+(?<year>\d{4}))?/#),
           let month = monthNumber(from: String(dayMonthYear.output.month)),
           let day = Int(dayMonthYear.output.day),
           (1...31).contains(day) {
            let year = dayMonthYear.output.year.flatMap { Int($0) } ?? extractedYear
            return (year, month, day)
        }

        if let dayMatch = normalized.firstMatch(of: #/\d{4}(?<day>\d{1,2})\b/#),
           let month = monthNumberFromSentence(normalized),
           let day = Int(dayMatch.output.day) {
            return (extractedYear, month, day)
        }

        return nil
    }

    private func parseStageLine(_ text: String) -> (hour: Int, minute: Int, title: String, isConfirmed: Bool)? {
        guard let stageTimeMatch = text.firstMatch(of: #/^\s*(?<hour>\d{1,2}):(?<minute>\d{2})(?:\s*:\s*|\s+)(?<title>.+?)\s*$/#) else {
            let title = normalizedStageTitle(text)
            guard !title.isEmpty else { return nil }
            return (0, 0, title, false)
        }

        guard
            let hour = Int(stageTimeMatch.output.hour),
            let minute = Int(stageTimeMatch.output.minute)
        else {
            return nil
        }

        let title = normalizedStageTitle(String(stageTimeMatch.output.title))
        return (hour, minute, title, true)
    }

    private func normalizedStageTitle(_ rawTitle: String) -> String {
        let withoutDistance = rawTitle
            .replacingOccurrences(of: #"\s*\(\s*\d+(?:\.\d+)?\s*km\s*\)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let titleCased = titleCaseIfAllUppercase(withoutDistance)
        let normalizedAcronyms = normalizeStageAcronyms(in: titleCased)
        return removeDuplicateLeadingStageNumber(in: normalizedAcronyms)
    }

    private func titleCaseIfAllUppercase(_ text: String) -> String {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return text }
        guard letters.allSatisfy({ CharacterSet.uppercaseLetters.contains($0) }) else { return text }

        var converted = text.localizedLowercase.capitalized

        let replacements: [(String, String)] = [
            (#"\bSs(?<number>\d+)\b"#, "SS$1"),
            (#"\bSss(?<number>\d+)\b"#, "SSS$1"),
            (#"\bSss\b"#, "SSS"),
            (#"\bTbc\b"#, "TBC"),
            (#"\bBp\b"#, "BP"),
        ]

        for (pattern, template) in replacements {
            converted = converted.replacingOccurrences(
                of: pattern,
                with: template,
                options: .regularExpression
            )
        }

        return converted
    }

    private func normalizeStageAcronyms(in text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: #"\bSSS\s+(?<number>\d+)\b"#, with: "SSS$1", options: .regularExpression)
            .replacingOccurrences(of: #"\bSS\s+(?<number>\d+)\b"#, with: "SS$1", options: .regularExpression)
            .replacingOccurrences(of: #"\bSss\b"#, with: "SSS", options: .regularExpression)
        if normalized.localizedCaseInsensitiveContains("SSS") {
            normalized = normalized.replacingOccurrences(of: #"\bSss(?<number>\d+)\b"#, with: "SSS$1", options: .regularExpression)
        }
        return normalized
    }

    private func removeDuplicateLeadingStageNumber(in text: String) -> String {
        guard let match = text.firstMatch(of: #/^\s*(?<first>SSS?\d+)\s+(?<second>SSS?\d+)\s+(?<rest>.+?)\s*$/#) else {
            return text
        }

        return "\(match.output.first) \(match.output.rest)"
    }

    private func monthNumberFromSentence(_ text: String) -> Int? {
        for (name, month) in Self.monthMapping {
            if text.localizedCaseInsensitiveContains(name) {
                return month
            }
        }
        return nil
    }

    private func monthNumber(from text: String) -> Int? {
        let lowered = text.lowercased()
        return Self.monthMapping[lowered]
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, timeZone: TimeZone) -> Date? {
        DateComponents(
            calendar: .gmt,
            timeZone: timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: 0
        ).date
    }

    private func tweakDates(of stages: inout [MotorsportEventStage]) {
        let maxDurationInHours = 3
        let calendar = Calendar.gmt
        for index in stages.indices.dropLast() {
            // Stages sometimes are marked as starting earlier than previous.
            // Override the start date for them to start date of previous to always have dates in order.
            stages[index + 1].startDate = max(stages[index].startDate, stages[index + 1].startDate)

            let nextStage = stages[index + 1]
            let dateBeforeStartOfNextStage = max(stages[index].startDate.addingTimeInterval(10*60), nextStage.startDate.addingTimeInterval(-1))
            let areStagesInSameDay = calendar.isDate(stages[index].startDate, inSameDayAs: nextStage.startDate)

            if areStagesInSameDay && nextStage.startDate > stages[index].startDate && DateInterval(start: stages[index].startDate, end: nextStage.startDate).duration < (60*60 * TimeInterval(maxDurationInHours)) {
                // For stages that are in the same day and are close to each other order set their end dates to be connected
                stages[index].endDate = dateBeforeStartOfNextStage
            } else {
                // Otherwise set end date up to the specified hours limit
                stages[index].endDate = min(calendar.date(byAdding: .hour, value: maxDurationInHours, to: stages[index].startDate)!, dateBeforeStartOfNextStage)
            }
        }
        if !stages.isEmpty {
            // Set end time for last stage of event to max value
            stages[stages.count - 1].endDate = calendar.date(byAdding: .hour, value: maxDurationInHours, to: stages[stages.count - 1].startDate)!
        }
    }

    private func extractEventTimeZone(from document: Document) throws -> TimeZone {
        let timeZoneText = try document.select(".faq-layout-view__header-title").text()
        if let timeZoneMatch = timeZoneText.firstMatch(of: #/UTC\s*(?<sign>[+-])\s*(?<hours>\d{1,2})(?::?(?<minutes>\d{2}))?/#),
           let hours = Int(timeZoneMatch.output.hours) {
            let minutes = timeZoneMatch.output.minutes.flatMap { Int($0) } ?? 0
            let multiplier = String(timeZoneMatch.output.sign) == "-" ? -1 : 1
            let offset = multiplier * ((hours * 60 * 60) + (minutes * 60))
            return TimeZone(secondsFromGMT: offset) ?? .gmt
        }

        return .gmt
    }

    private static let monthMapping: [String: Int] = [
        "jan": 1, "january": 1,
        "feb": 2, "february": 2,
        "mar": 3, "march": 3,
        "apr": 4, "april": 4,
        "may": 5,
        "jun": 6, "june": 6,
        "jul": 7, "july": 7,
        "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9,
        "oct": 10, "october": 10,
        "nov": 11, "november": 11,
        "dec": 12, "december": 12,
    ]
}

extension Calendar {
    static var gmt: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = .gmt
        return calendar
    }
}
