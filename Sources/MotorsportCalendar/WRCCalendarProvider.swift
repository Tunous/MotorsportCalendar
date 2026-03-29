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
        let document = try await getDocument(url: calendarURL, baseURL: baseURL)
        let eventCards = try document.select("a.event-feed-card[href]")

        var events: [MotorsportEvent] = []
        for eventCard in eventCards {
            guard
                let titleNode = try eventCard.select(".event-feed-card__title").first(),
                let dateNode = try eventCard.select("time.event-feed-card__date-text").first()
            else {
                continue
            }

            let rawTitle = try titleNode.text().trimmingCharacters(in: .whitespacesAndNewlines)
            let eventTitle = cleanEventTitle(rawTitle, year: year)
            let dateTimeText = try dateNode.attr("datetime")
            guard let startDate = parseISO8601Date(dateTimeText) else {
                continue
            }

            if Calendar.gmt.component(.year, from: startDate) != year {
                continue
            }

            let startDateText = try dateNode.text()
            let fallbackEndDate = parseEventEndDate(from: startDateText, fallbackStartDate: startDate) ?? startDate
            let eventPath = try eventCard.attr("href")
            guard let eventURL = URL(string: eventPath, relativeTo: baseURL)?.absoluteURL else {
                continue
            }

            let eventYear = Calendar.gmt.component(.year, from: startDate)
            let stages = try await extractStages(for: eventURL, baseURL: baseURL, fallbackYear: eventYear)

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

    private func extractStages(for eventURL: URL, baseURL: URL, fallbackYear: Int) async throws -> [MotorsportEventStage] {
        guard
            let eventDocument = try await getDocumentIgnoringBadResponse(url: eventURL, baseURL: baseURL),
            let itineraryPath = try findItineraryPath(in: eventDocument),
            let itineraryURL = URL(string: itineraryPath, relativeTo: eventURL)?.absoluteURL,
            let itineraryDocument = try await getDocumentIgnoringBadResponse(url: itineraryURL, baseURL: baseURL)
        else {
            return []
        }

        let timeZone = try extractEventTimeZone(from: itineraryDocument)
        let stageSections = try itineraryDocument.select(".faq-layout-view .faq-view")

        var stages: [MotorsportEventStage] = []
        for stageSection in stageSections {
            let dateText = try stageSection.select(".faq-view__question").text()
            guard let stageDay = parseItineraryDay(from: dateText, fallbackYear: fallbackYear) else {
                continue
            }

            let stageNodes = try stageSection.select(".faq-view__answer li.inline-enumeration__item")
            for stageNode in stageNodes {
                let stageText = try stageNode.text().trimmingCharacters(in: .whitespacesAndNewlines)
                guard
                    let stageData = parseStageLine(stageText),
                    let stageDate = makeDate(
                        year: stageDay.year,
                        month: stageDay.month,
                        day: stageDay.day,
                        hour: stageData.hour,
                        minute: stageData.minute,
                        timeZone: timeZone
                    )
                else {
                    continue
                }

                stages.append(
                    MotorsportEventStage(
                        title: stageData.title,
                        startDate: stageDate,
                        endDate: stageDate,
                        isConfirmed: stageData.isConfirmed,
                        isSignificant: isSignificant(title: stageData.title)
                    )
                )
            }
        }

        if stages.isEmpty {
            return []
        }

        stages.sort { $0.startDate < $1.startDate }
        tweakDates(of: &stages)
        return stages
    }

    private func isSignificant(title: String) -> Bool {
        return title.firstMatch(of: Regex {
            ChoiceOf {
                Regex {
                    Anchor.wordBoundary
                    "SS"
                    OneOrMore(.digit)
                    Anchor.wordBoundary
                }

                Regex {
                    Anchor.wordBoundary
                    "Shakedown"
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
        do {
            return try await getDocument(url: url, baseURL: baseURL)
        } catch {
            if error as? URLError == URLError(.badServerResponse) {
                return nil
            } else {
                throw error
            }
        }
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
        let tabLinks = try document.select("a.page-tabs__tab[href]")
        for tabLink in tabLinks {
            let href = try tabLink.attr("href")
            let text = try tabLink.text().trimmingCharacters(in: .whitespacesAndNewlines)
            if href.localizedCaseInsensitiveContains("/itinerary-") || text.localizedCaseInsensitiveContains("itinerary") {
                return href
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

        if let concatMatch = normalized.firstMatch(of: #/(?<month>[A-Za-z]+)\s+(?<year>\d{4})(?<day>\d{2})\b/#),
           let month = monthNumber(from: String(concatMatch.output.month)),
           let year = Int(concatMatch.output.year),
           let day = Int(concatMatch.output.day),
           (1...31).contains(day) {
            return (year, month, day)
        }

        if let monthDayYear = normalized.firstMatch(of: #/(?<month>[A-Za-z]+)\s+(?<day>\d{1,2})(?:,?\s*(?<year>\d{4}))?/#),
           let month = monthNumber(from: String(monthDayYear.output.month)),
           let day = Int(monthDayYear.output.day),
           (1...31).contains(day) {
            let year = monthDayYear.output.year.flatMap { Int($0) } ?? extractedYear
            return (year, month, day)
        }

        if let dayMonthYear = normalized.firstMatch(of: #/(?<day>\d{1,2})\s+(?<month>[A-Za-z]+)(?:\s+(?<year>\d{4}))?/#),
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
        guard let stageTimeMatch = text.firstMatch(of: #/^\s*(?<hour>\d{1,2}):(?<minute>\d{2})\s*:\s*(?<title>.+?)\s*$/#) else {
            let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return (0, 0, title, false)
        }

        guard
            let hour = Int(stageTimeMatch.output.hour),
            let minute = Int(stageTimeMatch.output.minute)
        else {
            return nil
        }

        let title = String(stageTimeMatch.output.title).trimmingCharacters(in: .whitespacesAndNewlines)
        return (hour, minute, title, true)
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
