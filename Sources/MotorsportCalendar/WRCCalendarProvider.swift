import Foundation
import MotorsportCalendarData
import SwiftSoup
import RegexBuilder

struct WRCCalendarProvider: CalendarProvider {
    let outputURL: URL
    let series: Series = .wrc

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func events(year: Int) async throws -> [MotorsportEvent] {
        let baseURL = URL(string: "https://www.wrc.com")!
        let calendarURL = URL(string: "https://www.wrc.com/en/calendar?rb3TabId=upcoming")!
        logParseInfo("Loading calendar page \(calendarURL.absoluteString) for \(year)")

        let document = try await getDocument(url: calendarURL, baseURL: baseURL)
        let eventCards = try document.select("a.event-feed-card[href]")
        if eventCards.isEmpty {
            logParseWarning("No event cards found on calendar page")
        }

        var events: [MotorsportEvent] = []
        for eventCard in eventCards {
            guard
                let titleNode = try eventCard.select(".event-feed-card__title").first(),
                let dateNode = try eventCard.select("time.event-feed-card__date-text").first()
            else {
                logParseWarning("Skipping event card: missing title or date node")
                continue
            }

            let rawTitle = try titleNode.text().trimmingCharacters(in: .whitespacesAndNewlines)
            let eventTitle = EventTitleCleaner(year: year).clean(rawTitle)
            let dateTimeText = try dateNode.attr("datetime")
            guard let startDate = parseISO8601Date(dateTimeText) else {
                logParseWarning("Skipping \(eventTitle): invalid datetime '\(dateTimeText)'")
                continue
            }

            if Calendar.gmt.component(.year, from: startDate) != year {
                continue
            }

            let startDateText = try dateNode.text()
            let fallbackEndDate = parseEventEndDate(from: startDateText, fallbackStartDate: startDate) ?? startDate

            let eventPath = try eventCard.attr("href")
            guard let eventURL = URL(string: eventPath, relativeTo: baseURL)?.absoluteURL else {
                logParseWarning("Skipping \(eventTitle): invalid event URL '\(eventPath)'")
                continue
            }

            let slug = eventURL.lastPathComponent
            let stages: [MotorsportEventStage]
            if let itineraryLink = try await fetchItineraryLink(forEventSlug: slug) {
                stages = try await fetchStages(forEventSlug: String(itineraryLink.dropFirst()), fallbackYear: year)
            } else {
                stages = []
            }

            let event = MotorsportEvent(
                title: eventTitle,
                startDate: stages.first?.startDate ?? startDate,
                endDate: stages.last?.endDate ?? fallbackEndDate,
                stages: stages,
                isConfirmed: !stages.isEmpty && stages.allSatisfy(\.isConfirmed)
            )
            events.append(event)
        }

        events.sort { $0.startDate < $1.startDate }
        return await onlyNotEndedEvents(events, year: year)
    }

    private func fetchItineraryLink(forEventSlug eventSlug: String) async throws -> String? {
        let endpoint = makeEventLinksURL(eventSlug: eventSlug)
        let responseData = try await getData(url: endpoint)

        let decoder = JSONDecoder()
        let payload = try decoder.decode(WRCEventLinksResponse.self, from: responseData)
        return payload.data.tabs.first { $0.label == "Itinerary" }?.url
    }

    private func fetchStages(forEventSlug eventSlug: String, fallbackYear: Int) async throws -> [MotorsportEventStage] {
        let endpoint = makeEventDetailsURL(eventSlug: eventSlug)
        let responseData = try await getData(url: endpoint)

        let decoder = JSONDecoder()
        let payload = try decoder.decode(WRCEventDetailsResponse.self, from: responseData)
        let faqBlocks = payload.data.items.filter { $0.type == "faq" && !($0.elements ?? []).isEmpty }
        guard !faqBlocks.isEmpty else {
            logParseError("Couldn't find any FAQ blocks with stage information")
            return []
        }

        let eventTimeZone = faqBlocks
            .compactMap { $0.title }
            .compactMap(extractTimeZone(from:))
            .first ?? .gmt

        var stages: [MotorsportEventStage] = []
        for faqBlock in faqBlocks {
            for element in faqBlock.elements ?? [] {
                let questionText = (element.question ?? []).compactMap(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                guard let stageDay = EventDay.parse(questionText, year: fallbackYear) else {
                    logParseError("Couldn't parse stages date from: \(questionText)")
                    continue
                }

                let rawStageLines = (element.answer ?? [])
                    .flatMap(\.items)
                    .flatMap(\.elements)
                    .compactMap(\.text)

                let dayStart = makeDate(
                    year: stageDay.year,
                    month: stageDay.month,
                    day: stageDay.day,
                    hour: 0,
                    minute: 0,
                    timeZone: eventTimeZone
                )

                for rawLine in rawStageLines {
                    guard let stageLine = StageLine.parse(rawLine) else {
                        logParseError("Couldn't parse stage line from: \(rawLine)")
                        continue
                    }

                    let stageDate: Date
                    if let time = stageLine.time {
                        stageDate = makeDate(
                            year: stageDay.year,
                            month: stageDay.month,
                            day: stageDay.day,
                            hour: time.hour,
                            minute: time.minute,
                            timeZone: eventTimeZone
                        )
                    } else {
                        var calendar = Calendar(identifier: .gregorian)
                        calendar.timeZone = eventTimeZone
                        if let last = stages.last, calendar.isDate(last.endDate, inSameDayAs: dayStart) {
                            stageDate = last.endDate
                        } else {
                            stageDate = dayStart
                        }
                    }

                    stages.append(
                        MotorsportEventStage(
                            title: stageLine.title,
                            startDate: stageDate,
                            endDate: stageDate,
                            isConfirmed: stageLine.isConfirmed,
                            isSignificant: isSignificant(title: stageLine.title)
                        )
                    )
                }
            }
        }

        guard !stages.isEmpty else {
            logParseError("Couldn't fetch stages for event: \(eventSlug)")
            return []
        }
        stages.sort { $0.startDate < $1.startDate }
        tweakDates(of: &stages)
        return stages
    }

    private func makeEventDetailsURL(eventSlug: String) -> URL {
        var components = URLComponents(string: "https://www.wrc.com/v3/api/graphql/v1/v3/feed/en-INT")!
        components.queryItems = [
            URLQueryItem(name: "disableUsageRestrictions", value: "true"),
            URLQueryItem(name: "filter[type]", value: "event-details"),
            URLQueryItem(name: "filter[uriSlug]", value: eventSlug),
            URLQueryItem(name: "page[limit]", value: "1"),
            URLQueryItem(name: "rb3Schema", value: "v1:inlineContent"),
            URLQueryItem(name: "rb3Locale", value: "en"),
        ]
        return components.url!
    }

    private func makeEventLinksURL(eventSlug: String) -> URL {
        var components = URLComponents(string: "https://www.wrc.com/v3/api/graphql/v1/v3/query/en-INT")!
        components.queryItems = [
            URLQueryItem(name: "filter[type]", value: "event-profiles"),
            URLQueryItem(name: "filter[uriSlug]", value: eventSlug),
            URLQueryItem(name: "rb3Schema", value: "v1:pageTabs"),
            URLQueryItem(name: "rb3Locale", value: "en"),
            URLQueryItem(name: "rb3PageTabsBaseUrl", value: "/")
        ]
        return components.url!
    }

    private func getDocument(url: URL, baseURL: URL) async throws -> Document {
        let htmlData = try await getData(url: url)
        guard let html = String(data: htmlData, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }
        return try SwiftSoup.parse(html, baseURL.absoluteString)
    }

    private func getData(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("MotoWeekParser/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func parseISO8601Date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime, .withTimeZone]
        return formatter.date(from: text)
    }

    private func parseEventEndDate(from text: String, fallbackStartDate: Date) -> Date? {
        let normalizedText = text.replacingOccurrences(of: "–", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)

        if let match = normalizedText.firstMatch(of: #/^\s*(?<startDay>\d{1,2})\s*-\s*(?<endDay>\d{1,2})\s+(?<month>[A-Za-z]+)\s+(?<year>\d{4})\s*$/#) {
            guard
                let month = monthNumber(from: String(match.output.month)),
                let year = Int(match.output.year),
                let endDay = Int(match.output.endDay)
            else {
                return nil
            }
            return makeDate(year: year, month: month, day: endDay, hour: 23, minute: 59, timeZone: .gmt)
        }

        if let match = normalizedText.firstMatch(of: #/^\s*(?<startDay>\d{1,2})\s+(?<startMonth>[A-Za-z]+)\s*-\s*(?<endDay>\d{1,2})\s+(?<endMonth>[A-Za-z]+)\s+(?<year>\d{4})\s*$/#) {
            guard
                let month = monthNumber(from: String(match.output.endMonth)),
                let year = Int(match.output.year),
                let endDay = Int(match.output.endDay)
            else {
                return nil
            }
            return makeDate(year: year, month: month, day: endDay, hour: 23, minute: 59, timeZone: .gmt)
        }

        if let match = normalizedText.firstMatch(of: #/^\s*(?<day>\d{1,2})\s+(?<month>[A-Za-z]+)\s+(?<year>\d{4})\s*$/#) {
            guard
                let month = monthNumber(from: String(match.output.month)),
                let year = Int(match.output.year),
                let day = Int(match.output.day)
            else {
                return nil
            }
            return makeDate(year: year, month: month, day: day, hour: 23, minute: 59, timeZone: .gmt)
        }

        return Calendar.gmt.date(byAdding: .day, value: 2, to: fallbackStartDate)
    }

    private func extractTimeZone(from text: String) -> TimeZone? {
        if let timeZoneMatch = text.firstMatch(of: #/UTC\s*(?<sign>[+-])\s*(?<hours>\d{1,2})(?::?(?<minutes>\d{2}))?/#),
           let hours = Int(timeZoneMatch.output.hours) {
            let minutes = timeZoneMatch.output.minutes.flatMap { Int($0) } ?? 0
            let multiplier = String(timeZoneMatch.output.sign) == "-" ? -1 : 1
            let offset = multiplier * ((hours * 60 * 60) + (minutes * 60))
            return TimeZone(secondsFromGMT: offset)
        }
        return nil
    }

    private func isSignificant(title: String) -> Bool {
        if title.localizedCaseInsensitiveContains("shakedown") {
            return true
        }

        return title.firstMatch(of: Regex {
            ChoiceOf {
                Regex {
                    Anchor.wordBoundary
                    "SSS"
                    OneOrMore(.digit)
                    Anchor.wordBoundary
                }
                Regex {
                    Anchor.wordBoundary
                    "SS"
                    OneOrMore(.digit)
                    Anchor.wordBoundary
                }
            }
        }) != nil
    }

    private func monthNumber(from text: String) -> Int? {
        let lowered = text.lowercased()
        return Self.monthMapping[lowered]
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, timeZone: TimeZone) -> Date {
        DateComponents(
            calendar: .gmt,
            timeZone: timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: 0
        ).date!
    }

    private func tweakDates(of stages: inout [MotorsportEventStage]) {
        let maxDurationInHours = 3
        let calendar = Calendar.gmt
        for index in stages.indices.dropLast() {
            stages[index + 1].startDate = max(stages[index].startDate, stages[index + 1].startDate)

            let nextStage = stages[index + 1]
            let dateBeforeStartOfNextStage = max(stages[index].startDate.addingTimeInterval(10 * 60), nextStage.startDate.addingTimeInterval(-1))
            let areStagesInSameDay = calendar.isDate(stages[index].startDate, inSameDayAs: nextStage.startDate)

            if areStagesInSameDay && nextStage.startDate > stages[index].startDate && DateInterval(start: stages[index].startDate, end: nextStage.startDate).duration < (60 * 60 * TimeInterval(maxDurationInHours)) {
                stages[index].endDate = dateBeforeStartOfNextStage
            } else {
                stages[index].endDate = min(calendar.date(byAdding: .hour, value: maxDurationInHours, to: stages[index].startDate)!, dateBeforeStartOfNextStage)
            }
        }
        if !stages.isEmpty {
            stages[stages.count - 1].endDate = calendar.date(byAdding: .hour, value: maxDurationInHours, to: stages[stages.count - 1].startDate)!
        }
    }

    private static let monthMapping: [String: Int] = [
        "jan": 1, "january": 1,
        "feb": 2, "february": 2,
        "mar": 3, "march": 3,
        "apr": 4, "april": 4,
        "may": 5,
        "jun": 6, "june": 6,
        "jul": 7, "july": 7,
        "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9,
        "oct": 10, "october": 10,
        "nov": 11, "november": 11,
        "dec": 12, "december": 12,
    ]
}

struct WRCEventDetailsResponse: Decodable {
    let data: DataNode

    struct DataNode: Decodable {
        let items: [Item]
    }

    struct Item: Decodable {
        let type: String
        let title: String?
        let elements: [Element]?
    }

    struct Element: Decodable {
        let question: [InlinePart]?
        let answer: [AnswerBlock]?
    }

    struct InlinePart: Decodable {
        let text: String?
    }

    struct AnswerBlock: Decodable {
        let type: String?
        let items: [AnswerItem]

        private enum CodingKeys: String, CodingKey {
            case type
            case items
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decodeIfPresent(String.self, forKey: .type)
            items = try container.decodeIfPresent([AnswerItem].self, forKey: .items) ?? []
        }
    }

    struct AnswerItem: Decodable {
        let elements: [InlinePart]
    }
}

struct WRCEventLinksResponse: Decodable {
    let data: DataNode

    struct DataNode: Decodable {
        let tabs: [Tab]
    }

    struct Tab: Decodable {
        let label: String
        let url: String
    }
}
