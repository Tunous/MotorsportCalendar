//
//  WRCCalendarProvider.swift
//  
//
//  Created by Łukasz Rutkowski on 09/03/2024.
//

import Foundation
import MotorsportCalendarData
import SwiftSoup

struct WRCCalendarProvider: CalendarProvider {
    let outputURL: URL
    let series: Series = .wrc

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func events(year: Int) async throws -> [MotorsportEvent] {
        let dateParser = Date.VerbatimFormatStyle(
            format: "\(day: .defaultDigits). \(month: .defaultDigits). \(year: .defaultDigits)",
            timeZone: .gmt,
            calendar: .gmt
        ).parseStrategy

        let url = URL(string: "https://www.ewrc-results.com/season/\(year)/1-wrc/")!
        let document = try await getDocument(url: url)
        let eventNodes = try document.select("div.season-event")

        var events: [MotorsportEvent] = []
        for node in eventNodes {
            let nameNode = try node.select("div.season-event-name > a")
            let name = try nameNode.text()
            let path = try nameNode.attr("href")
            let datesText = try node.select("div.event-info").text().prefix(while: { $0 != "," }).split(separator: "–")

            let startDateText = datesText[0].trimmingCharacters(in: .whitespaces) + " \(year)"
            let startDate = try dateParser.parse(startDateText)
            let endDateText = datesText[1].trimmingCharacters(in: .whitespaces)
            let endDate = try dateParser.parse(endDateText)

            let pathComponent = path.split(separator: "/").last!
            let eventURL = URL(string: "https://www.ewrc-results.com/timetable/\(pathComponent)/")!

            let eventHtml = try String(contentsOf: eventURL)
            let eventDocument = try await getDocument(url: eventURL)

            var stageStartDate = Date.distantPast
            var stages: [MotorsportEventStage] = []
            let stagesTable = try eventDocument.select("div.mt-3")[0].children()
            for stageNode in stagesTable {
                guard !stageNode.children().isEmpty() else { continue }
                let stageCode = try stageNode.select(".harm-ss").text()
                let stageName = try stageNode.select(".harm-stage").text()
                let stageDateText = try stageNode.select(".harm-date").text().drop(while: { !$0.isWhitespace }).dropFirst()
                if !stageDateText.isEmpty {
                    stageStartDate = try dateParser.parse("\(stageDateText) \(year)")
                }

                guard let date = try parseStageUTCDate(from: stageNode, startDate: stageStartDate, year: year) else {
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

            let event = MotorsportEvent(
                title: name.replacingOccurrences(of: year.description, with: "").trimmingCharacters(in: .whitespaces),
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
        return title.firstMatch(of: /((\bSS\d+\b)|(\bShakedown\b)|(\bPodium\b))/) != nil
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
    private func parseStageUTCDate(from stageNode: Element, startDate: Date, year: Int) throws -> Date? {
        let stageTimeNode = try stageNode.select(".harm-time").first()
        let stageTimeText = try stageTimeNode?.nextElementSibling()?.text() ?? stageTimeNode?.text() ?? ""
        guard let stageTimeMatch = stageTimeText.firstMatch(of: #/(?<hour>\d+):(?<minute>\d+)\s*((?<day>\d+)\. (?<month>\d+)\.)?\s*(UTC)?/#) else {
            return nil
        }
        let calendar = Calendar.gmt
        let hour = Int(stageTimeMatch.output.hour)!
        let minute = Int(stageTimeMatch.output.minute)!
        let day = stageTimeMatch.output.day.map { Int($0)! } ?? calendar.component(.day, from: startDate)
        let month = stageTimeMatch.output.month.map { Int($0)! } ?? calendar.component(.month, from: startDate)
        return DateComponents(calendar: calendar, timeZone: .gmt, year: year, month: month, day: day, hour: hour, minute: minute, second: 0).date!
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
}

extension Calendar {
    static var gmt: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = .gmt
        return calendar
    }
}
