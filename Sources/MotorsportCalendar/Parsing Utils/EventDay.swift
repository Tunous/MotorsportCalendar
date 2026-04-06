import Foundation

struct EventDay: Equatable {
    let day: Int
    let month: Int
    let year: Int
}

extension EventDay {
    /// Parses a day from a question heading in various WRC itinerary formats.
    /// Uses `fallbackYear` when no year is present in the text.
    ///
    /// Supported formats:
    /// - `Thursday, 9 April 2026`   — Weekday, Day Month Year
    /// - `Thursday 25 June 2026`    — Weekday Day Month Year (no comma)
    /// - `Saturday, April 202611`   — Weekday, Month YearDay (year+day concatenated)
    /// - `Thursday, April 23`       — Weekday, Month Day
    /// - `Thursday, 28 May`         — Weekday, Day Month
    /// - `Wednesday, 06.05.`        — Weekday, Day.Month.
    static func parse(_ text: String, year fallbackYear: Int) -> EventDay? {
        let normalized = text.trimmingWhitespace()
        return parseDotSeparatedNumeric(normalized, fallbackYear: fallbackYear)
            ?? parseConcatenatedYearDay(normalized)
            ?? parseWithExplicitYear(normalized)
            ?? parseWithFallbackYear(normalized, fallbackYear: fallbackYear)
    }

    /// Handles `Wednesday, 06.05.` — numeric day.month. with no year.
    /// Checked first to prevent lenient `Date.ParseStrategy` from misreading
    /// the numeric tokens as month/day in a different order.
    private static func parseDotSeparatedNumeric(_ text: String, fallbackYear: Int) -> EventDay? {
        guard let match = text.firstMatch(of: /^[A-Za-z]+,?\s+(?<day>\d{1,2})\.(?<month>\d{1,2})\.$/) else {
            return nil
        }
        guard let day = Int(match.output.day), let month = Int(match.output.month) else {
            return nil
        }
        return EventDay(day: day, month: month, year: fallbackYear)
    }

    /// Handles `Saturday, April 202611` — month name followed by a 5–6 digit blob
    /// where the first four digits are the year and the remainder is the day.
    private static func parseConcatenatedYearDay(_ text: String) -> EventDay? {
        guard let match = text.firstMatch(of: /^[A-Za-z]+,?\s+(?<month>[A-Za-z]+)\s+(?<yearDay>\d{5,6})$/) else {
            return nil
        }
        let yearDayStr = String(match.output.yearDay)
        guard
            let parsedYear = Int(yearDayStr.prefix(4)),
            let parsedDay = Int(yearDayStr.dropFirst(4)),
            (1...31).contains(parsedDay),
            let monthNum = monthNumber(from: String(match.output.month))
        else {
            return nil
        }
        return EventDay(day: parsedDay, month: monthNum, year: parsedYear)
    }

    /// Handles `Thursday, 9 April 2026` and `Thursday 25 June 2026` — full date with year,
    /// with or without a comma after the weekday.
    private static func parseWithExplicitYear(_ text: String) -> EventDay? {
        let formats: [Date.FormatString] = [
            "\(weekday: .wide), \(day: .defaultDigits) \(month: .wide) \(year: .defaultDigits)",
            "\(weekday: .wide) \(day: .defaultDigits) \(month: .wide) \(year: .defaultDigits)",
        ]
        return formats.firstResult { format in
            let strategy = Date.ParseStrategy(format: format, locale: posixLocale, timeZone: .gmt)
            return (try? Date(text, strategy: strategy))?.asEventDay
        }
    }

    /// Handles `Thursday, April 23` and `Thursday, 28 May` — date with no year.
    /// The fallback year is appended to the text before parsing so a standard
    /// format string with a year component can be used.
    private static func parseWithFallbackYear(_ text: String, fallbackYear: Int) -> EventDay? {
        let textWithYear = "\(text) \(fallbackYear)"
        let formats: [Date.FormatString] = [
            "\(weekday: .wide), \(month: .wide) \(day: .defaultDigits) \(year: .defaultDigits)",
            "\(weekday: .wide), \(day: .defaultDigits) \(month: .wide) \(year: .defaultDigits)",
        ]
        return formats.firstResult { format in
            let strategy = Date.ParseStrategy(format: format, locale: posixLocale, timeZone: .gmt)
            return (try? Date(textWithYear, strategy: strategy))?.asEventDay(overridingYear: fallbackYear)
        }
    }

    private static func monthNumber(from text: String) -> Int? {
        let formats: [Date.FormatString] = ["\(month: .wide)", "\(month: .abbreviated)"]
        return formats.firstResult { format in
            let strategy = Date.ParseStrategy(format: format, locale: posixLocale, timeZone: .gmt)
            return (try? Date(text, strategy: strategy)).map { Calendar.gmt.component(.month, from: $0) }
        }
    }

    private static let posixLocale = Locale(identifier: "en_US_POSIX")
}

private extension Date {
    var asEventDay: EventDay {
        EventDay(
            day: Calendar.gmt.component(.day, from: self),
            month: Calendar.gmt.component(.month, from: self),
            year: Calendar.gmt.component(.year, from: self)
        )
    }

    func asEventDay(overridingYear year: Int) -> EventDay {
        EventDay(
            day: Calendar.gmt.component(.day, from: self),
            month: Calendar.gmt.component(.month, from: self),
            year: year
        )
    }
}

private extension Array {
    /// Returns the first non-nil result produced by `transform`, or `nil` if all elements yield nil.
    func firstResult<T>(_ transform: (Element) -> T?) -> T? {
        for element in self {
            if let result = transform(element) { return result }
        }
        return nil
    }
}
