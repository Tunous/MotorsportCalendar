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
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = TimeZone.gmt
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // "Wednesday, 06.05." — numeric day.month. — must be checked first to prevent lenient
        // Date.ParseStrategy from misinterpreting the numeric tokens as month/day.
        if let match = normalized.firstMatch(of: /^[A-Za-z]+,?\s+(?<day>\d{1,2})\.(?<month>\d{1,2})\.$/) {
            if let day = Int(match.output.day), let month = Int(match.output.month) {
                return EventDay(day: day, month: month, year: fallbackYear)
            }
        }

        // "Saturday, April 202611" — year (4 digits) and day (1–2 digits) concatenated after month
        if let match = normalized.firstMatch(of: /^[A-Za-z]+,?\s+(?<month>[A-Za-z]+)\s+(?<yearDay>\d{5,6})$/) {
            let yearDayStr = String(match.output.yearDay)
            let yearStr = String(yearDayStr.prefix(4))
            let dayStr = String(yearDayStr.dropFirst(4))
            if let parsedYear = Int(yearStr),
               let parsedDay = Int(dayStr), parsedDay >= 1, parsedDay <= 31,
               let monthNum = monthNumber(from: String(match.output.month)) {
                return EventDay(day: parsedDay, month: monthNum, year: parsedYear)
            }
        }

        // Formats with an explicit year
        for format: Date.FormatString in [
            "\(weekday: .wide), \(day: .defaultDigits) \(month: .wide) \(year: .defaultDigits)",
            "\(weekday: .wide) \(day: .defaultDigits) \(month: .wide) \(year: .defaultDigits)",
        ] {
            let strategy = Date.ParseStrategy(format: format, locale: locale, timeZone: timeZone)
            if let date = try? Date(normalized, strategy: strategy) {
                return date.asEventDay
            }
        }

        // Formats without year — append fallback year to the text before parsing
        let textWithYear = "\(normalized) \(fallbackYear)"
        for format: Date.FormatString in [
            "\(weekday: .wide), \(month: .wide) \(day: .defaultDigits) \(year: .defaultDigits)",
            "\(weekday: .wide), \(day: .defaultDigits) \(month: .wide) \(year: .defaultDigits)",
        ] {
            let strategy = Date.ParseStrategy(format: format, locale: locale, timeZone: timeZone)
            if let date = try? Date(textWithYear, strategy: strategy) {
                return date.asEventDay(overridingYear: fallbackYear)
            }
        }

        return nil
    }

    private static func monthNumber(from text: String) -> Int? {
        let locale = Locale(identifier: "en_US_POSIX")
        for format: Date.FormatString in ["\(month: .wide)", "\(month: .abbreviated)"] {
            let strategy = Date.ParseStrategy(format: format, locale: locale, timeZone: .gmt)
            if let date = try? Date(text, strategy: strategy) {
                return Calendar.gmt.component(.month, from: date)
            }
        }
        return nil
    }
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
