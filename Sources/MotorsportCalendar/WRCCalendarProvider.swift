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
import Algorithms

struct WRCCalendarProvider: CalendarProvider {
    let outputURL: URL
    let series: Series = .wrc

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func events(year: Int) async throws -> [MotorsportEvent] {
        let dateParser = Date.VerbatimFormatStyle(
            format: "\(day: .defaultDigits).\(month: .defaultDigits).\(year: .defaultDigits)",
            timeZone: .gmt,
            calendar: .gmt
        ).parseStrategy

        let url = URL(string: "https://www.ewrc-results.com/season/\(year)/1-wrc/")!
        let document = try await getDocument(url: url)
        let interestingNodes = try document.getElementsMatchingOwnText(" \(year)$").chunks(ofCount: 2)

        var events: [MotorsportEvent] = []
        for pair in interestingNodes {
            let nameNode = pair.first!
            let dateNode = pair.last!
            let name = try nameNode.text()
            let eventPath = try nameNode.attr("href")
            let datesText = try dateNode.text().split(separator: "-")

            let startDateText = String(datesText[0].replacing(" ", with: "") + "\(year)")
            let startDate = try dateParser.parse(startDateText)
            let endDateText = String(datesText[1].replacing(" ", with: ""))
            let endDate = try dateParser.parse(endDateText)

            let timetablePath = eventPath.replacing("final-results", with: "itinerary")
            let eventURL = URL(string: "https://www.ewrc-results.com/\(timetablePath)")!
            let eventDocument = try await getDocumentIgnoringBadResponse(url: eventURL)

            var stageStartDate = Date.distantPast
            var stages: [MotorsportEventStage] = []
            if let eventDocument {
                let stageTimeNodes = try eventDocument.getElementsMatchingOwnText(#"\d\d:\d\d"#)
                    .filter { $0.parents().contains(where: { $0.hasClass("md:block") }) }
                    .filter { !$0.hasNextSibling() }

                let timeZone = try extractEventTimeZone(from: eventDocument)

                for stageTimeNode in stageTimeNodes {
                    let stageRowNode = stageTimeNode.parent()!
                    let stageCode = try stageRowNode.child(0).text()
                    let stageName = try stageRowNode.child(1).text()
                    let dateText = try stageRowNode.child(3).text().drop(while: { !$0.isWhitespace }).replacing(" ", with: "")
                    let timeText = try stageTimeNode.text()

                    if !dateText.isEmpty {
                        stageStartDate = try dateParser.parse("\(dateText)\(year)")
                    }

                    guard let date = try parseStageDate(from: stageTimeNode, startDate: stageStartDate, year: year, timeZone: timeZone) else {
                        stages = []
                        break
                    }

                    stageStartDate = max(stageStartDate, date)

                    let title = stageCode.isEmpty ? stageName : stageCode + " " + stageName
                    stages.append(
                        MotorsportEventStage(
                            title: title,
                            startDate: date,
                            endDate: date,
                            isSignificant: isSignificant(title: title)
                        )
                    )
                }

                tweakDates(of: &stages)
            }

            let event = MotorsportEvent(
                title: name.replacing(year.description, with: "").trimmingCharacters(in: .whitespaces),
                startDate: stages.first?.startDate ?? startDate,
                endDate: stages.last?.endDate ?? endDate,
                stages: stages,
                isConfirmed: !stages.isEmpty
            )
            events.append(event)
        }
        return await onlyNotEndedEvents(events, year: year)
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

                Regex {
                    Anchor.wordBoundary
                    "Podium"
                    Anchor.wordBoundary
                }
            }
        }) != nil
    }

    private func getDocument(url: URL) async throws -> Document {
        setTimezoneCookie(for: url)

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
        return try SwiftSoup.parse(html, "https://www.ewrc-results.com")
    }

    private func getDocumentIgnoringBadResponse(url: URL) async throws -> Document? {
        do {
            return try await getDocument(url: url)
        } catch {
            if error as? URLError == URLError(.badServerResponse) {
                return nil
            } else {
                throw error
            }
        }
    }

    private func setTimezoneCookie(for url: URL) {
        let timezoneCookie = HTTPCookie(properties: [
            .path: "/",
            .name: "timezone",
            .value: "UTC",
            .domain: "www.ewrc-results.com",
        ])!
        HTTPCookieStorage.shared.setCookies([timezoneCookie], for: url, mainDocumentURL: nil)
    }

    // 12:00 21. 11. UTC
    // 12:00 UTC
    // 12:00 21. 11.
    // 12:00
    private func parseStageDate(from node: Element, startDate: Date, year: Int, timeZone: TimeZone) throws -> Date? {
        guard let stageTimeMatch = try node.text().firstMatch(of: #/(?<hour>\d+):(?<minute>\d+)\s*((?<day>\d+)\. (?<month>\d+)\.)?\s*(UTC)?/#) else {
            return nil
        }
        let calendar = Calendar.gmt
        let hour = Int(stageTimeMatch.output.hour)!
        let minute = Int(stageTimeMatch.output.minute)!
        let day = stageTimeMatch.output.day.map { Int($0)! } ?? calendar.component(.day, from: startDate)
        let month = stageTimeMatch.output.month.map { Int($0)! } ?? calendar.component(.month, from: startDate)
        return DateComponents(calendar: calendar, timeZone: timeZone, year: year, month: month, day: day, hour: hour, minute: minute, second: 0).date!
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
        let scriptWithTimeZone = try document.getElementsByTag("script")
            .first(where: { try $0.html().contains("timezone") })
        guard let scriptWithTimeZone else {
            return .gmt
        }
        let html = try scriptWithTimeZone.html()
        if let index = html.firstRange(of: #"\"timezone\":\""#)?.upperBound {
            let timeZoneText = html[index...].prefix(while: { $0 != "\\"})
            return TimeZone(identifier: String(timeZoneText)) ?? .gmt
        }
        return .gmt
    }
}

extension Calendar {
    static var gmt: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = .gmt
        return calendar
    }
}
