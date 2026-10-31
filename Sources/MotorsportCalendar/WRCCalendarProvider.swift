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

        let eventCards = try await fetchCalendarEventCards(url: calendarURL, baseURL: baseURL)
        if eventCards.isEmpty {
            // No upcoming events is valid at the end of the season, but only if the past tab still parses.
            try await validatePastEventsParse(baseURL: baseURL)
            logParseInfo("No upcoming WRC events found, but past events parse correctly; treating as end of season")
            return []
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
                stages = try await fetchStages(
                    forEventSlug: String(itineraryLink.dropFirst()),
                    fallbackYear: year,
                    eventStartDate: startDate,
                    fallbackTimeZone: Self.timeZone(fromISO8601: dateTimeText) ?? .gmt
                )
            } else {
                stages = []
            }

            let event = MotorsportEvent(
                id: StableIdentifier.event(slug, series: series),
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
        return payload.data.tabs.first { Self.isItineraryTabLabel($0.label) }?.url
    }

    static func isItineraryTabLabel(_ label: String) -> Bool {
        label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "itinerary"
    }

    private func fetchStages(
        forEventSlug eventSlug: String,
        fallbackYear: Int,
        eventStartDate: Date,
        fallbackTimeZone: TimeZone
    ) async throws -> [MotorsportEventStage] {
        let endpoint = makeEventDetailsURL(eventSlug: eventSlug)
        let responseData = try await getData(url: endpoint)

        let decoder = JSONDecoder()
        let payload = try decoder.decode(WRCEventDetailsResponse.self, from: responseData)
        let faqBlocks = payload.data.items.filter { $0.type == "faq" && !($0.elements ?? []).isEmpty }
        guard !faqBlocks.isEmpty else {
            if eventStartDate <= .now {
                logParseWarning("No WRC itinerary FAQ blocks found for '\(eventSlug)' after event start; recovering with event-level dates and empty stages.")
            }
            return []
        }

        let eventTimeZone = Self.eventTimeZone(
            faqTitles: faqBlocks.compactMap(\.title),
            fallback: fallbackTimeZone
        )

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
                    let isConfirmed: Bool
                    if let time = stageLine.time {
                        stageDate = makeDate(
                            year: stageDay.year,
                            month: stageDay.month,
                            day: stageDay.day,
                            hour: time.hour,
                            minute: time.minute,
                            timeZone: eventTimeZone
                        )
                        isConfirmed = true
                    } else {
                        let fallback = Self.untimedStageFallback(
                            dayStart: dayStart,
                            eventStartDate: eventStartDate,
                            previousStageEndDate: stages.last?.endDate,
                            timeZone: eventTimeZone
                        )
                        stageDate = fallback.date
                        isConfirmed = fallback.isConfirmed
                    }

                    stages.append(
                        MotorsportEventStage(
                            id: StableIdentifier.session(stageLine.title, series: series),
                            title: stageLine.title,
                            startDate: stageDate,
                            endDate: stageDate,
                            isConfirmed: isConfirmed,
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
        Self.disambiguateStageIdentifiers(&stages)
        tweakDates(of: &stages)
        return stages
    }

    static func disambiguateStageIdentifiers(_ stages: inout [MotorsportEventStage]) {
        let indexGroups = Dictionary(grouping: stages.indices) { stages[$0].id }
        for indices in indexGroups.values where indices.count > 1 {
            for (offset, index) in indices.enumerated() {
                stages[index].id += "-\(offset + 1)"
            }
        }
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

    private func getDocument(url: URL, baseURL: URL) async throws -> (document: Document, html: String) {
        let htmlData = try await getData(url: url)
        guard let html = String(data: htmlData, encoding: .utf8) else {
            logParseError("Response from \(url.absoluteString) is not valid UTF-8 (\(htmlData.count) bytes)")
            throw URLError(.cannotDecodeContentData)
        }
        return (try SwiftSoup.parse(html, baseURL.absoluteString), html)
    }

    private func fetchCalendarEventCards(url: URL, baseURL: URL) async throws -> Elements {
        // wrc.com intermittently responds with HTTP 200 and an empty client-side app shell
        // (no title, empty body) instead of the server-rendered calendar. Retry those responses.
        try await Task.retry(maxAttempts: 5, onRetry: { attempt, error in
            logParseWarning("Attempt \(attempt) to load \(url.absoluteString) failed: \(error); retrying")
        }) {
            let (document, html) = try await getDocument(url: url, baseURL: baseURL)
            let eventCards = try document.select("a.event-feed-card[href]")
            logCalendarPageDiagnostics(url: url, document: document, html: html, eventCardCount: eventCards.count)
            if eventCards.isEmpty, try Self.isUnrenderedPage(document) {
                throw CalendarParsingError.missingValue(
                    description: "WRC calendar page \(url.absoluteString) was returned without server-rendered content"
                )
            }
            return eventCards
        }
    }

    /// Whether the document is the bare client-side app shell, which has an empty title and no body text.
    static func isUnrenderedPage(_ document: Document) throws -> Bool {
        let title = try document.title().trimmingWhitespace()
        let bodyText = try document.body()?.text().trimmingWhitespace() ?? ""
        return title.isEmpty && bodyText.isEmpty
    }

    static func isUnrenderedPage(html: String) throws -> Bool {
        try isUnrenderedPage(SwiftSoup.parse(html))
    }

    /// Logs a summary of the fetched calendar page so that intermittent parsing failures
    /// (e.g. bot protection pages, cached variants or client-side rendered shells) can be identified from CI logs.
    private func logCalendarPageDiagnostics(url: URL, document: Document, html: String, eventCardCount: Int) {
        let pageTitle = (try? document.title()) ?? "<unavailable>"
        let anyCardCount = (try? document.select(".event-feed-card").count) ?? -1
        let titleNodeCount = (try? document.select(".event-feed-card__title").count) ?? -1
        let dateNodeCount = (try? document.select("time.event-feed-card__date-text").count) ?? -1
        let scriptCount = (try? document.select("script").count) ?? -1
        logParseInfo(
            "Calendar page \(url.absoluteString): \(html.utf8.count) bytes, title '\(pageTitle)', "
            + "\(eventCardCount) linked event cards, \(anyCardCount) .event-feed-card elements, "
            + "\(titleNodeCount) title nodes, \(dateNodeCount) date nodes, \(scriptCount) scripts"
        )

        guard eventCardCount == 0 else { return }

        let markers = [
            "event-feed-card", "rb3TabId", "__NEXT_DATA__", "captcha", "cloudflare", "cf-chl",
            "access denied", "forbidden", "akamai", "enable javascript", "just a moment",
        ]
        let lowercasedHTML = html.lowercased()
        let foundMarkers = markers.filter { lowercasedHTML.contains($0.lowercased()) }
        logParseWarning("No linked event cards on \(url.absoluteString); markers present in HTML: \(foundMarkers.isEmpty ? "none" : foundMarkers.joined(separator: ", "))")

        let bodyText = ((try? document.body()?.text()) ?? "").trimmingWhitespace()
        logParseWarning("Body text preview (\(bodyText.count) chars): \(String(bodyText.prefix(1000)))")
        logParseWarning("HTML preview: \(String(html.prefix(2000)))")
        saveDebugHTML(html, for: url)
    }

    /// When `MOTORSPORT_CALENDAR_DEBUG_DIR` is set, dumps the raw HTML so CI can upload it as an artifact.
    private func saveDebugHTML(_ html: String, for url: URL) {
        guard let debugDirectory = ProcessInfo.processInfo.environment["MOTORSPORT_CALENDAR_DEBUG_DIR"], !debugDirectory.isEmpty else {
            return
        }
        let directoryURL = URL(filePath: debugDirectory, directoryHint: .isDirectory)
        let tab = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "rb3TabId" }?.value ?? "page"
        let timestamp = Int(Date.now.timeIntervalSince1970)
        let fileURL = directoryURL.appending(path: "wrc-calendar-\(tab)-\(timestamp).html")
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try Data(html.utf8).write(to: fileURL)
            logParseInfo("Saved calendar page HTML to \(fileURL.path)")
        } catch {
            logParseWarning("Failed to save debug HTML to \(fileURL.path): \(error)")
        }
    }

    private func validatePastEventsParse(baseURL: URL) async throws {
        let pastURL = URL(string: "https://www.wrc.com/en/calendar?rb3TabId=past")!
        logParseInfo("No upcoming WRC event cards found; validating past calendar page \(pastURL.absoluteString)")
        let pastEventCards = try await fetchCalendarEventCards(url: pastURL, baseURL: baseURL)
        var missingTitleCount = 0
        var missingDateCount = 0
        var invalidDates: [String] = []
        var parsableCount = 0
        for eventCard in pastEventCards {
            guard try eventCard.select(".event-feed-card__title").first() != nil else {
                missingTitleCount += 1
                continue
            }
            guard let dateNode = try eventCard.select("time.event-feed-card__date-text").first() else {
                missingDateCount += 1
                continue
            }
            let dateTimeText = try dateNode.attr("datetime")
            if parseISO8601Date(dateTimeText) != nil {
                parsableCount += 1
            } else {
                invalidDates.append(dateTimeText)
            }
        }
        let summary = "\(pastEventCards.count) past cards: \(parsableCount) parsable, "
            + "\(missingTitleCount) missing title, \(missingDateCount) missing date, "
            + "\(invalidDates.count) invalid datetime\(invalidDates.isEmpty ? "" : " (e.g. '\(invalidDates.prefix(3).joined(separator: "', '"))')")"
        logParseInfo("Past calendar page validation: \(summary)")
        guard parsableCount > 0 else {
            throw CalendarParsingError.missingValue(
                description: "No WRC event cards found on upcoming calendar page and no past event could be parsed (\(summary))"
            )
        }
    }

    private func getData(url: URL) async throws -> Data {
        try await Task.retry(onRetry: { attempt, error in
            logParseWarning("Request attempt \(attempt) for \(url.absoluteString) failed: \(error); retrying")
        }) {
            var request = URLRequest(url: url)
            request.setValue("MotoWeekParser/1.0", forHTTPHeaderField: "User-Agent")

            let startedAt = Date.now
            let (data, response) = try await URLSession.shared.data(for: request)
            let elapsed = Date.now.timeIntervalSince(startedAt)
            guard let httpResponse = response as? HTTPURLResponse else {
                logParseError("Non-HTTP response for \(url.absoluteString)")
                throw URLError(.badServerResponse)
            }
            logParseInfo(
                "GET \(url.absoluteString) -> \(httpResponse.statusCode), \(data.count) bytes in \(String(format: "%.2f", elapsed))s"
                + Self.diagnosticHeaders(of: httpResponse)
            )
            guard httpResponse.statusCode == 200 else {
                let bodyPreview = String(decoding: data.prefix(500), as: UTF8.self)
                logParseError("Unexpected HTTP status \(httpResponse.statusCode) for \(url.absoluteString); body preview: \(bodyPreview)")
                throw URLError(.badServerResponse, userInfo: [
                    NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode) for \(url.absoluteString)"
                ])
            }
            return data
        }
    }

    private static let diagnosticHeaderNames = [
        "Content-Type", "Content-Length", "Content-Encoding", "Server", "Date", "Age", "Cache-Control",
        "ETag", "Last-Modified", "Vary", "Via", "X-Cache", "X-Cache-Hits", "X-Served-By", "X-Request-Id",
        "X-Redirect-Chain", "X-Extended-Stale-Cache-Match", "CF-Cache-Status", "CF-Ray", "X-Amz-Cf-Pop", "X-Amz-Cf-Id",
    ]

    private static func diagnosticHeaders(of response: HTTPURLResponse) -> String {
        let pairs = diagnosticHeaderNames.compactMap { name in
            response.value(forHTTPHeaderField: name).map { "\(name)=\($0)" }
        }
        return pairs.isEmpty ? "" : " [\(pairs.joined(separator: "; "))]"
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

    static func eventTimeZone(faqTitles: [String], fallback: TimeZone) -> TimeZone {
        faqTitles.compactMap(extractTimeZone(from:)).first
            ?? fallback
    }

    static func untimedStageFallback(
        dayStart: Date,
        eventStartDate: Date,
        previousStageEndDate: Date?,
        timeZone: TimeZone
    ) -> (date: Date, isConfirmed: Bool) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if let previousStageEndDate, calendar.isDate(previousStageEndDate, inSameDayAs: dayStart) {
            return (previousStageEndDate, false)
        }
        if calendar.isDate(eventStartDate, inSameDayAs: dayStart) {
            return (eventStartDate, true)
        }
        return (dayStart, false)
    }

    static func timeZone(fromISO8601 text: String) -> TimeZone? {
        if text.hasSuffix("Z") {
            return .gmt
        }
        guard let match = text.firstMatch(of: #/(?<sign>[+-])(?<hours>\d{2}):(?<minutes>\d{2})$/#),
              let hours = Int(match.output.hours),
              let minutes = Int(match.output.minutes) else {
            return nil
        }
        let multiplier = String(match.output.sign) == "-" ? -1 : 1
        return TimeZone(secondsFromGMT: multiplier * ((hours * 60 * 60) + (minutes * 60)))
    }

    private static func extractTimeZone(from text: String) -> TimeZone? {
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
