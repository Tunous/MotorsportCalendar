//
//  RacingICalParser.swift
//  MotorsportCalendar
//
//  Created by Łukasz Rutkowski on 08/05/2025.
//

import Foundation
import MotorsportCalendarData
import ICalSwift

let preSeasonTestingName = "Pre-Season Testing"

enum RacingICalParser {
    static func parse(_ url: URL, year: Int) throws -> [MotorsportEvent] {
        let string = try String(contentsOf: url)
        let cleanedString = string.replacingOccurrences(of: "\r\n", with: "\n")
        let parser = ICalParser()
        let calendar = try unwrap(parser.parseCalendar(ics: cleanedString))

        let events = calendar.events.compactMap { event -> Event? in
            guard let startDate = event.dtstart?.date else { return nil }
            guard Calendar.current.component(.year, from: startDate) == year else { return nil }
            return Event(event: event)
        }
        var groupedEvents = Dictionary(grouping: events, by: \.name)
        groupPreSeasonEventsByWeek(in: &groupedEvents)

        let sortedEvents = groupedEvents.sorted(using: KeyPathComparator(\.value.first))

        return try sortedEvents.map { name, sessions -> MotorsportEvent in
            let stages = sessions.map {
                MotorsportEventStage(
                    title: $0.stageName,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    isSignificant: !$0.stageName.localizedCaseInsensitiveContains("practice")
                )
            }
            let titles = stages.map(\.title)
            if titles.count != Set(titles).count {
                throw CalendarParsingError.duplicateStages(eventName: name, stages: titles)
            }
            let startDate = sessions.min(by: { $0.startDate < $1.startDate })!.startDate
            let endDate = sessions.max(by: { $0.endDate < $1.endDate })!.endDate
            return MotorsportEvent(
                title: name,
                startDate: startDate,
                endDate: endDate,
                stages: stages.sorted(using: KeyPathComparator(\.startDate)),
                isConfirmed: !stages.isEmpty && sessions.allSatisfy({ $0.hasConfirmedDates })
            )
        }
    }

    private static func groupPreSeasonEventsByWeek(in events: inout [String: [Event]]) {
        guard let preSeasonTestingEvents = events[preSeasonTestingName]?.sorted() else { return }
        var index = 1
        var week = 0
        for event in preSeasonTestingEvents {
            let eventWeek = Calendar.current.component(.weekOfYear, from: event.startDate)
            if eventWeek != week && week > 0 {
                index += 1
            }
            events["\(preSeasonTestingName) \(index)", default: []].append(event)
            week = eventWeek
        }
        events.removeValue(forKey: preSeasonTestingName)
    }
}

enum CalendarParsingError: Error {
    case missingValue(description: String)
    case duplicateStages(eventName: String, stages: [String])
}

func unwrap<T>(_ value: T?, function: StaticString = #function, line: UInt8 = #line) throws -> T {
    guard let value else {
        throw CalendarParsingError.missingValue(description: "\(function) at line \(line) value is nil")
    }
    return value
}

fileprivate struct Event: Comparable {
    let stageName: String
    let startDate: Date
    let endDate: Date
    let name: String
    let hasConfirmedDates: Bool

    init?(event: ICalEvent) {
        guard
            let summary = event.summary,
            let startDate = event.dtstart,
            let endDate = event.dtend
        else {
            return nil
        }
        self.stageName = summary.split(separator: " - ").dropFirst().joined(separator: " - ")
        self.startDate = startDate.date
        self.endDate = endDate.date
        if let location = event.location {
            self.name = EventName.formula1(summary: summary, location: location)
        } else {
            self.name = EventName.wec(summary: summary)
        }
        self.hasConfirmedDates = !summary.hasSuffix("(TBC)")
    }

    static func < (lhs: Event, rhs: Event) -> Bool {
        lhs.startDate < rhs.startDate
    }
}

fileprivate enum SessionType: String, Encodable {
    case practice1 = "Practice 1"
    case practice2 = "Practice 2"
    case practice3 = "Practice 3"
    case sprintQualification = "Sprint Qualification"
    case sprintRace = "Sprint Race"
    case qualifying = "Qualifying"
    case race = "Race"

    init?(summary: String) {
        let mapping: [String: SessionType] = [
            "Practice 1": .practice1,
            "Practice 2": .practice2,
            "Practice 3": .practice3,
            "Qualifying": .qualifying,
            "Sprint Shootout": .sprintQualification,
            "Sprint Qualification": .sprintQualification,
            "Sprint Race": .sprintRace,
            "Race": .race,
        ]
        for (substring, type) in mapping {
            if summary.contains("- \(substring)") {
                self = type
                return
            }
        }
        print("!! Unsupported session type: \(summary)")
        return nil
    }
}

fileprivate struct EventName {
    let name: String

    static func wec(summary: String) -> String{
        let raw = summary.split(separator: " - ").first.map { String($0) } ?? summary
        if raw.hasSuffix(" 2025") {
            return String(raw.dropLast(5))
        }
        return raw
    }

    static func formula1(summary: String, location: String) -> String {
        let namePrefix: String
        switch location.lowercased() {
        case "saudi arabia":
            namePrefix = "Saudi Arabian"
        case "australia":
            namePrefix = "Australian"
        case "japan":
            namePrefix = "Japanese"
        case "china":
            namePrefix = "Chinese"
        case "united states":
            if summary.localizedStandardContains("miami") {
                namePrefix = "Miami"
            } else if summary.localizedStandardContains("las vegas") {
                namePrefix = "Las Vegas"
            } else {
                namePrefix = "United States"
            }
        case "italy":
            if summary.localizedStandardContains("romagna") {
                namePrefix = "Emilia Romagna"
            } else {
                namePrefix = "Italian"
            }
        case "canada":
            namePrefix = "Canadian"
        case "spain":
            if summary.localizedStandardContains("barcelona") {
                namePrefix = "Barcelona-Catalunya"
            } else {
                namePrefix = "Spanish"
            }
        case "austria":
            namePrefix = "Austrian"
        case "united kingdom":
            namePrefix = "British"
        case "hungary":
            namePrefix = "Hungarian"
        case "belgium":
            namePrefix = "Belgian"
        case "netherlands":
            namePrefix = "Dutch"
        case "mexico":
            namePrefix = "Mexico City"
        case "brazil":
            namePrefix = "São Paulo"
        case "united arab emirates":
            namePrefix = "Abu Dhabi"
        default:
            if summary.localizedCaseInsensitiveContains("pre-season testing") {
                return preSeasonTestingName
            }
            namePrefix = location
        }
        return namePrefix + " Grand Prix"
    }
}
