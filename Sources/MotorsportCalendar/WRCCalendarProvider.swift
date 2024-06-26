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
        let url = URL(string: "https://www.ewrc-results.com/season/2024/1-wrc/")!

        var calendar = Calendar.current
        calendar.timeZone = .gmt
        let dateParser = Date.VerbatimFormatStyle.init(
            format: "\(day: .defaultDigits). \(month: .defaultDigits). \(year: .defaultDigits)",
            timeZone: .gmt,
            calendar: calendar
        ).parseStrategy

        let html = try String(contentsOf: url)
        let document = try SwiftSoup.parse(html, "https://www.ewrc-results.com")
        let eventNodes = try document.select("div.season-event")

        let existingEvents = await load(year: year) ?? []

        let events = try eventNodes.compactMap { node -> MotorsportEvent? in
            let nameNode = try node.select("div.season-event-name > a")
            let name = try nameNode.text()
            let path = try nameNode.attr("href")
            let datesText = try node.select("div.event-info").text().prefix(while: { $0 != "," }).split(separator: "–")

            let startDateText = datesText[0].trimmingCharacters(in: .whitespaces) + " \(year)"
            let startDate = try dateParser.parse(startDateText)
            let endDateText = datesText[1].trimmingCharacters(in: .whitespaces)
            let endDate = try dateParser.parse(endDateText)

            if endDate < .now {
                return nil
            }

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
                let newDate: Date
                if !stageDateText.isEmpty {
                    newDate = try dateParser.parse("\(stageDateText) \(year)")
                } else {
                    newDate = stageStartDate
                }
                let stageTimeNode = try stageNode.select(".harm-time").first()
                let stageTimeText = try stageTimeNode?.nextElementSibling()?.text() ?? stageTimeNode?.text() ?? ""
                let stageTime = stageTimeText.split(separator: ":")
                guard
                    stageTime.count >= 2,
                    let hour = Int(stageTime[0].drop(while: { !$0.isNumber })),
                    let minute = Int(stageTime[1].prefix(while: { $0.isNumber }))
                else {
                    stages = []
                    break
                }

                stageStartDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: newDate)!

                stages.append(
                    MotorsportEventStage(
                        title: stageCode.isEmpty ? stageName : stageCode + " " + stageName,
                        startDate: stageStartDate,
                        endDate: stageStartDate
                    )
                )
            }

            for index in stages.indices.dropLast() {
                let nextStage = stages[index + 1]
                if calendar.isDate(stages[index].startDate, inSameDayAs: nextStage.startDate) {
                    stages[index].endDate = nextStage.startDate.addingTimeInterval(-1)
                } else {
                    stages[index].endDate = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: stages[index].startDate)!
                }
            }
            if !stages.isEmpty {
                stages[stages.count - 1].endDate = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: stages[stages.count - 1].startDate)!
            }
            return MotorsportEvent(
                title: name.replacingOccurrences(of: year.description, with: "").trimmingCharacters(in: .whitespaces),
                startDate: stages.first?.startDate ?? startDate,
                endDate: stages.last?.endDate ?? endDate,
                stages: stages,
                isConfirmed: !stages.isEmpty
            )
        }
        if let firstEventDate = events.first?.startDate {
            let missedEvents = existingEvents.prefix(while: { $0.startDate < firstEventDate })
            return missedEvents + events
        }
        return events
    }
}
