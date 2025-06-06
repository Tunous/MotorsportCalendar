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
        let url = URL(string: "https://www.ewrc-results.com/season/\(year)/1-wrc/")!

        var calendar = Calendar.current
        calendar.timeZone = .gmt
        let dateParser = Date.VerbatimFormatStyle(
            format: "\(day: .defaultDigits). \(month: .defaultDigits). \(year: .defaultDigits)",
            timeZone: .gmt,
            calendar: calendar
        ).parseStrategy

        let html = try String(contentsOf: url)
        let document = try SwiftSoup.parse(html, "https://www.ewrc-results.com")
        let eventNodes = try document.select("div.season-event")

        let events = try eventNodes.compactMap { node -> MotorsportEvent? in
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
            let timezoneCookie = HTTPCookie(properties: [
                .path: "/",
                .name: "timezone",
                .value: "UTC",
                .domain: "www.ewrc-results.com",
            ])!
            HTTPCookieStorage.shared.setCookies([timezoneCookie], for: eventURL, mainDocumentURL: nil)

            let eventHtml = try String(contentsOf: eventURL)
            let eventDocument = try SwiftSoup.parse(eventHtml, "https://www.ewrc-results.com")

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

                // 12:00 21. 11. UTC
                // 12:00 UTC
                // 12:00 21. 11.
                // 12:00
                func parseUTCDate() throws -> Date? {
                    let stageTimeNode = try stageNode.select(".harm-time").first()
                    let stageTimeText = try stageTimeNode?.nextElementSibling()?.text() ?? stageTimeNode?.text() ?? ""
                    guard let stageTimeMatch = stageTimeText.firstMatch(of: #/(?<hour>\d+):(?<minute>\d+)\s*((?<day>\d+)\. (?<month>\d+)\.)?\s*(UTC)?/#) else {
                        return nil
                    }
                    let hour = Int(stageTimeMatch.output.hour)!
                    let minute = Int(stageTimeMatch.output.minute)!
                    let day = stageTimeMatch.output.day.map { Int($0)! }
                    let month = stageTimeMatch.output.month.map { Int($0)! }
                    if let day, let month {
                        let date = try dateParser.parse("\(day). \(month). \(year)")
                        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)!
                    }
                    return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: stageStartDate)!
                }

                guard let date = try parseUTCDate() else {
                    stages = []
                    break
                }

                stageStartDate = max(stageStartDate, date)

                stages.append(
                    MotorsportEventStage(
                        title: stageCode.isEmpty ? stageName : stageCode + " " + stageName,
                        startDate: date,
                        endDate: date
                    )
                )
            }

            let maxDurationInHours = 3
            for index in stages.indices.dropLast() {
                stages[index + 1].startDate = max(stages[index].startDate, stages[index + 1].startDate)

                let nextStage = stages[index + 1]
                let dateBeforeStartOfNextStage = max(stages[index].startDate.addingTimeInterval(10*60), nextStage.startDate.addingTimeInterval(-1))
                let areStagesInSameDay = calendar.isDate(stages[index].startDate, inSameDayAs: nextStage.startDate)

                if areStagesInSameDay && nextStage.startDate > stages[index].startDate && DateInterval(start: stages[index].startDate, end: nextStage.startDate).duration < (60*60 * TimeInterval(maxDurationInHours)) {
                    stages[index].endDate = dateBeforeStartOfNextStage
                } else {
                    stages[index].endDate = min(calendar.date(byAdding: .hour, value: maxDurationInHours, to: stages[index].startDate)!, dateBeforeStartOfNextStage)
                }
            }
            if !stages.isEmpty {
                stages[stages.count - 1].endDate = calendar.date(byAdding: .hour, value: maxDurationInHours, to: stages[stages.count - 1].startDate)!
            }
            return MotorsportEvent(
                title: name.replacingOccurrences(of: year.description, with: "").trimmingCharacters(in: .whitespaces),
                startDate: stages.first?.startDate ?? startDate,
                endDate: stages.last?.endDate ?? endDate,
                stages: stages,
                isConfirmed: !stages.isEmpty
            )
        }
        return await onlyNotEndedEvents(events, year: year)
    }
}
