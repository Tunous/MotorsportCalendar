//
//  Formula1CalendarProvider.swift
//  
//
//  Created by Łukasz Rutkowski on 05/03/2024.
//

import Foundation
import MotorsportCalendarData
import ICalSwift
import ArgumentParser

struct Formula1CalendarProvider: CalendarProvider {
    private let calendarURL: URL

    let outputURL: URL
    let series: Series = .formula1

    init(
        outputURL: URL,
        calendarURL: URL
    ) {
        self.outputURL = outputURL
        self.calendarURL = calendarURL
    }

    func events(year: Int) async throws -> [MotorsportEvent] {
        let (data, _) = try await URLSession.shared.data(from: calendarURL)
        guard let string = String(data: data, encoding: .utf8) else {
            throw ValidationError("Malformed calendar data")
        }
        let parser = ICalParser()
        guard let calendar = parser.parseCalendar(ics: string.replacingOccurrences(of: "\r\n", with: "\n")) else {
            throw ValidationError("Malformed calendar data")
        }
        let events = calendar.events.compactMap { event -> Event? in
            guard let startDate = event.dtstart?.date else { return nil }
            guard Calendar.current.component(.year, from: startDate) == year else { return nil }
            return Event(event: event)
        }
        let groupedEvents = Dictionary(grouping: events, by: \.name)
        let sortedEvents = groupedEvents.sorted(using: KeyPathComparator(\.value.first?.startDate))

        let finalEvents = sortedEvents.map { name, sessions -> MotorsportEvent in
            let stages: [MotorsportEventStage]
            if sessions.contains(where: { $0.sessionType == nil }) {
                stages = []
            } else {
                stages = sessions.map {
                    MotorsportEventStage(
                        title: $0.sessionType!.rawValue,
                        startDate: $0.startDate,
                        endDate: $0.endDate
                    )
                }
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

        if let existingEvents = await load(year: year), let firstEventDate = finalEvents.first?.startDate {
            let missedEvents = existingEvents.prefix(while: { $0.startDate < firstEventDate })
            return missedEvents + finalEvents
        }

        return finalEvents
    }
}

fileprivate struct Event: Encodable {
    let sessionType: SessionType?
    let startDate: Date
    let endDate: Date
    let name: String
    let hasConfirmedDates: Bool

    enum CodingKeys: CodingKey {
        case sessionType
        case startDate
        case endDate
        case hasConfirmedDates
    }

    init?(event: ICalEvent) {
        guard
            let summary = event.summary,
            let startDate = event.dtstart,
            let endDate = event.dtend,
            let location = event.location
        else {
            return nil
        }
        self.sessionType = SessionType(summary: summary)
        self.startDate = startDate.date
        self.endDate = endDate.date
        self.name = EventName(summary: summary, location: location).name
        self.hasConfirmedDates = !summary.hasSuffix("(TBC)")
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
        return nil
    }
}

fileprivate struct EventName {
    let name: String

    init(summary: String, location: String) {
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
            namePrefix = "Spanish"
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
            namePrefix = location
        }
        name = namePrefix + " Grand Prix"
    }
}
