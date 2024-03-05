//
//  WRCCalendarProvider.swift
//
//
//  Created by Łukasz Rutkowski on 05/03/2024.
//

import Foundation
import MotorsportCalendarData

struct WRCCalendarProvider: CalendarProvider {

    let outputURL: URL
    let series: Series = .wrc

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func events(year: Int) async throws -> [MotorsportEvent] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.wrc.com"
        components.path = "/content/filters/calendar"
        components.queryItems = [
            URLQueryItem(name: "championship", value: "wrc"),
            URLQueryItem(name: "year", value: "\(year)")
        ]
        let request = URLRequest(url: components.url!)
        let (data, _) = try await URLSession.shared.data(for: request)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let object = try decoder.decode(CalendarResponse.self, from: data)

        var continueFetchingStages = true
        var events: [MotorsportEvent] = []
        for event in object.content {
            let stages: [MotorsportEventStage]?
            if continueFetchingStages {
                print("[\(Self.self)] Getting stages of \(event.title)")
                var components = URLComponents()
                components.scheme = "https"
                components.host = "api.rally.tv"
                components.path = "/content/filters/schedule"
                components.queryItems = [
                    URLQueryItem(name: "byListingTime", value: "\(Int(event.startDate.timeIntervalSince1970 * 1000))~\(Int(event.endDate.timeIntervalSince1970 * 1000))"),
                    URLQueryItem(name: "seriesUid", value: event.id)
                ]
                let request = URLRequest(url: components.url!)
                let (data, _) = try await URLSession.shared.data(for: request)

                let object = try decoder.decode(ScheduleResponse.self, from: data)
                stages = object.content.map { element in
                    MotorsportEventStage(
                        id: element.id,
                        title: element.title,
                        startDate: element.availableOn,
                        endDate: element.availableTill
                    )
                }
            } else {
                stages = nil
            }
            let isConfirmed = stages?.isEmpty == false || event.endDate < .now
            events.append(
                MotorsportEvent(
                    id: event.id,
                    title: event.title,
                    startDate: event.startDate,
                    endDate: event.endDate,
                    stages: stages ?? [],
                    isConfirmed: isConfirmed
                )
            )
            continueFetchingStages = !isConfirmed
        }
        return events
    }
}

fileprivate struct CalendarResponse: Decodable {
    let content: [Content]

    struct Content: Decodable, Identifiable, Hashable {
        let title: String
        let startDate: Date
        let endDate: Date
        let seriesUid: String
        let images: [Image]

        var id: String { seriesUid }

        var dateInterval: DateInterval {
            DateInterval(start: startDate, end: endDate)
        }

        struct Image: Decodable, Hashable {
            let url: URL
        }
    }
}

fileprivate struct ScheduleResponse: Decodable {
    let content: [Content]

    struct Content: Decodable, Identifiable {
        let uid: String
        let title: String
        let availableOn: Date
        let availableTill: Date

        var id: String { uid }
    }
}
