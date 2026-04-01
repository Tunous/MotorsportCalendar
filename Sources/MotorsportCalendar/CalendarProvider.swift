//
//  CalendarProvider.swift
//  
//
//  Created by Łukasz Rutkowski on 05/03/2024.
//

import Foundation
import MotorsportCalendarData

protocol CalendarProvider: Sendable {
    var outputURL: URL { get }
    var series: Series { get }

    func events(year: Int) async throws -> [MotorsportEvent]
}

extension CalendarProvider {
    func logParseInfo(_ message: String) {
        print("[\(series)][parse] \(message)")
    }

    func logParseWarning(_ message: String) {
        print("[\(series)][parse][warning] \(message)")
    }

    func logParseError(_ message: String) {
        print("[\(series)][parse][error] \(message)")
    }

    func run(year: Int) async throws -> Bool {
        let events = try await events(year: year)
        let mergedEvents = await addBackRemovedCancelledEvents(from: events, year: year)
        let eventsData = try JSONEncoder.motorsportCalendar.encode(mergedEvents)

        let directory = outputURL.appending(path: series.rawValue)
        let url = directory.appending(path: "\(year).json")
        let storedEventsData = try? Data(contentsOf: url)

        if eventsData == storedEventsData {
            print("[\(series)] No changes")
            return false
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try eventsData.write(to: url)
        print("[\(series)] Updated")
        return true
    }

    func addBackRemovedCancelledEvents(from updatedEvents: [MotorsportEvent], year: Int) async -> [MotorsportEvent] {
        guard let existingEvents = await load(year: year) else {
            return updatedEvents
        }

        let updatedTitles = Set(updatedEvents.map { normalizedEventTitle($0.title) })
        let removedCancelledEvents = existingEvents.filter {
            $0.isCancelled && !updatedTitles.contains(normalizedEventTitle($0.title))
        }

        guard !removedCancelledEvents.isEmpty else {
            return updatedEvents
        }

        var mergedEvents = updatedEvents
        mergedEvents.append(contentsOf: removedCancelledEvents)
        mergedEvents.sort {
            if $0.startDate == $1.startDate {
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return $0.startDate < $1.startDate
        }
        return mergedEvents
    }

    private func normalizedEventTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func load(year: Int) async -> [MotorsportEvent]? {
        let directory = outputURL.appending(path: series.rawValue)
        let url = directory.appending(path: "\(year).json")
        guard let storedEventsData = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder.motorsportCalendar.decode([MotorsportEvent].self, from: storedEventsData)
    }

    func onlyNotEndedEvents(_ updatedEvents: [MotorsportEvent], year: Int) async -> [MotorsportEvent] {
        guard let existingEvents = await load(year: year) else {
            return updatedEvents
        }
        var events: [MotorsportEvent] = []
        events.append(contentsOf: existingEvents.prefix(while: { $0.endDate < .now }))
        events.append(contentsOf: updatedEvents.drop(while: { $0.endDate < .now }))
        return events
    }
}
