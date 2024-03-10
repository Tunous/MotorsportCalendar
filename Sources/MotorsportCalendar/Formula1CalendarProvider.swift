//
//  Formula1CalendarProvider.swift
//  
//
//  Created by Łukasz Rutkowski on 05/03/2024.
//

import Foundation
import MotorsportCalendarData
import iCalendarParser
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
        let parser = ICParser()
        guard let calendar = parser.calendar(from: string) ?? parser.calendar(from: string.replacingOccurrences(of: "\n", with: "\r\n")) else {
            throw ValidationError("Malformed calendar data")
        }
        let events = calendar.events.compactMap { event -> Event? in
            guard let startDate = event.dtStart?.date else { return nil }
            guard Calendar.current.component(.year, from: startDate) == year else { return nil }
            return Event(event: event)
        }
        let groupedEvents = Dictionary(grouping: events, by: \.name)
        let sortedEvents = groupedEvents.sorted(using: KeyPathComparator(\.value.first?.startDate))
        let finalEvents = sortedEvents.map { name, sessions -> MotorsportEvent in
            let stages = sessions.map {
                MotorsportEventStage(
                    title: $0.sessionType.rawValue,
                    startDate: $0.startDate,
                    endDate: $0.endDate
                )
            }
            let startDate = sessions.first(where: { $0.sessionType == .practice1 })!.startDate
            let endDate = sessions.first(where: { $0.sessionType == .race })!.endDate
            return MotorsportEvent(
                title: name,
                startDate: startDate,
                endDate: endDate,
                stages: stages.sorted(using: KeyPathComparator(\.startDate)),
                isConfirmed: sessions.allSatisfy({ $0.hasConfirmedDates })
            )
        }

        return finalEvents
    }
}

fileprivate struct Event: Encodable {
    let sessionType: SessionType
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

    init?(event: ICEvent) {
        guard
            let summary = event.summary,
            let sessionType = SessionType(summary: summary),
            let startDate = event.dtStart,
            let endDate = event.dtEnd,
            let description = event.location
        else {
            return nil
        }
        self.sessionType = sessionType
        self.startDate = startDate.date
        self.endDate = endDate.date
        self.name = description
        self.hasConfirmedDates = !summary.hasSuffix("(TBC)")
    }
}

fileprivate enum SessionType: String, Encodable {
    case practice1 = "Practice 1"
    case practice2 = "Practice 2"
    case practice3 = "Practice 3"
    case sprintShootout = "Sprint Shootout"
    case sprintRace = "Sprint Race"
    case qualifying = "Qualifying"
    case race = "Race"

    init?(summary: String) {
        let mapping: [String: SessionType] = [
            "Practice 1": .practice1,
            "Practice 2": .practice2,
            "Practice 3": .practice3,
            "Qualifying": .qualifying,
            "Sprint Shootout": .sprintShootout,
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

    init(string: String) {
        name = String(string.drop(while: { $0 != "1" })
            .dropFirst(2)
            .prefix(while: { $0 != "-" })
            .dropLast(6))
    }
}
