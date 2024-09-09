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
        let url = URL(string: "https://www.fiawec.com/en/season/about")!

        let html = try String(contentsOf: url, encoding: .utf8)
        let document = try SwiftSoup.parse(html, "https://www.fiawec.com")

        let elements = try document.select(SelectorQuery.topLevelItemScope)

        let events = try elements.map { element in
            let event = try getEvent(from: element)
            let stages = event.subEvents.map { subEvent in
                return MotorsportEventStage(
                    title: subEvent.name,
                    startDate: subEvent.startDate,
                    endDate: subEvent.endDate
                )
            }
            return MotorsportEvent(
                title: event.name.trimmingCharacters(in: .whitespacesAndNewlines),
                startDate: event.startDate,
                endDate: event.endDate,
                stages: stages,
                isConfirmed: true
            )
        }

        return events
    }

    private func getEvent(from element: Element) throws -> Event {
        let workingElement = element.copy() as! Element
        let children = try workingElement.children().select(SelectorQuery.topLevelItemScope).remove()

        let type = try workingElement.attr("itemtype")
        let attributes = try workingElement.select(SelectorQuery.itemProp)
        let propertyKeyValues = try attributes
            .filter { try !$0.attr("itemprop").isEmpty }
            .map { property in
                let key = try property.attr("itemprop")
                let value = try property.itemPropValue()
                return (key, value)
            }
        let properties = Dictionary(propertyKeyValues, uniquingKeysWith: { lhs, rhs in lhs })
        let name = properties["name"] ?? ""
        var startDate = try Date.ISO8601FormatStyle.iso8601.parse(properties["startDate"] ?? "")
        var endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!

        let text = try workingElement.text()

        var subEvents = try children.map(getEvent(from:))
        if !subEvents.isEmpty {
            for index in 0..<(subEvents.count - 1) {
                let nextEvent = subEvents[index + 1]
                let dateBeforeNextSubEventStart = nextEvent.startDate.addingTimeInterval(-1)
                let dayAfterStartDate = Calendar.current.date(byAdding: .day, value: 1, to: subEvents[index].startDate)!
                subEvents[index].endDate = min(dayAfterStartDate, dateBeforeNextSubEventStart)
            }
            subEvents[subEvents.count - 1].endDate = Calendar.current.date(byAdding: .day, value: 1, to: subEvents[subEvents.count - 1].startDate)!
        }

        if let firstChild = subEvents.first {
            startDate = min(startDate, firstChild.startDate)
        }
        if let lastChild = subEvents.last {
            endDate = max(endDate, lastChild.endDate)
        }
        return Event(
            type: type,
            name: name,
            startDate: startDate,
            endDate: endDate,
            subEvents: subEvents
        )
    }
}

fileprivate struct Event {
    let type: String
    let name: String
    let startDate: Date
    var endDate: Date
    let subEvents: [Event]
}

extension Element {
    func itemPropValue() throws -> String {
        if tagName() == "a" && hasAttr("href") {
            return try attr("href")
        }
        if tagName() == "img" && hasAttr("src") {
            return try attr("src")
        }
        if hasAttr("content") {
            return try attr("content")
        }
        return try html()
    }
}

enum SelectorQuery {
    static let topLevelItemScope = "[itemscope]:not([itemscope] [itemscope])"
    static let itemProp = "[itemprop]:not([itemscope])"
}
