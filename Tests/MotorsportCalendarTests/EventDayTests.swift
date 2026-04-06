import Testing
@testable import MotorsportCalendar

@Suite("EventDay.parse")
struct EventDayTests {
    let fallbackYear = 2026

    // MARK: - Weekday, Day Month Year

    @Test("Thursday, 9 April 2026")
    func weekdayCommaDayMonthYear() {
        let result = EventDay.parse("Thursday, 9 April 2026", year: fallbackYear)
        #expect(result == EventDay(day: 9, month: 4, year: 2026))
    }

    @Test("Thursday, 09 April 2026 — zero-padded day")
    func weekdayCommaDayMonthYearZeroPadded() {
        let result = EventDay.parse("Thursday, 09 April 2026", year: fallbackYear)
        #expect(result == EventDay(day: 9, month: 4, year: 2026))
    }

    @Test("Friday, 31 December 2026")
    func weekdayCommaDayMonthYearEndOfYear() {
        let result = EventDay.parse("Friday, 31 December 2026", year: fallbackYear)
        #expect(result == EventDay(day: 31, month: 12, year: 2026))
    }

    // MARK: - Weekday Day Month Year (no comma)

    @Test("Thursday 25 June 2026")
    func weekdayDayMonthYear() {
        let result = EventDay.parse("Thursday 25 June 2026", year: fallbackYear)
        #expect(result == EventDay(day: 25, month: 6, year: 2026))
    }

    @Test("Saturday 1 January 2028")
    func weekdayDayMonthYearDifferentYear() {
        let result = EventDay.parse("Saturday 1 January 2028", year: fallbackYear)
        #expect(result == EventDay(day: 1, month: 1, year: 2028))
    }

    // MARK: - Weekday, Month YearDay (concatenated)

    @Test("Saturday, April 202611")
    func weekdayCommaMonthYearDayConcatenated() {
        let result = EventDay.parse("Saturday, April 202611", year: fallbackYear)
        #expect(result == EventDay(day: 11, month: 4, year: 2026))
    }

    @Test("Monday, March 20261 — single-digit day concatenated")
    func weekdayCommaMonthYearDaySingleDigitConcatenated() {
        let result = EventDay.parse("Monday, March 20261", year: fallbackYear)
        #expect(result == EventDay(day: 1, month: 3, year: 2026))
    }

    @Test("Sunday, December 202631")
    func weekdayCommaMonthYearDayConcatenatedEndOfMonth() {
        let result = EventDay.parse("Sunday, December 202631", year: fallbackYear)
        #expect(result == EventDay(day: 31, month: 12, year: 2026))
    }

    // MARK: - Weekday, Month Day (no year)

    @Test("Thursday, April 23")
    func weekdayCommaMonthDay() {
        let result = EventDay.parse("Thursday, April 23", year: fallbackYear)
        #expect(result == EventDay(day: 23, month: 4, year: fallbackYear))
    }

    @Test("Monday, January 1")
    func weekdayCommaMonthDayFirstOfMonth() {
        let result = EventDay.parse("Monday, January 1", year: fallbackYear)
        #expect(result == EventDay(day: 1, month: 1, year: fallbackYear))
    }

    // MARK: - Weekday, Day Month (no year)

    @Test("Thursday, 28 May")
    func weekdayCommaDayMonth() {
        let result = EventDay.parse("Thursday, 28 May", year: fallbackYear)
        #expect(result == EventDay(day: 28, month: 5, year: fallbackYear))
    }

    @Test("Sunday, 7 November")
    func weekdayCommaDayMonthSingleDigit() {
        let result = EventDay.parse("Sunday, 7 November", year: fallbackYear)
        #expect(result == EventDay(day: 7, month: 11, year: fallbackYear))
    }

    // MARK: - Weekday, Day.Month. (numeric)

    @Test("Wednesday, 06.05.")
    func weekdayCommaDotSeparated() {
        let result = EventDay.parse("Wednesday, 06.05.", year: fallbackYear)
        #expect(result == EventDay(day: 6, month: 5, year: fallbackYear))
    }

    @Test("Friday, 1.1. — single-digit day and month")
    func weekdayCommaDotSeparatedSingleDigits() {
        let result = EventDay.parse("Friday, 1.1.", year: fallbackYear)
        #expect(result == EventDay(day: 1, month: 1, year: fallbackYear))
    }

    @Test("Tuesday, 31.12.")
    func weekdayCommaDotSeparatedEndOfYear() {
        let result = EventDay.parse("Tuesday, 31.12.", year: fallbackYear)
        #expect(result == EventDay(day: 31, month: 12, year: fallbackYear))
    }

    // MARK: - Fallback year usage

    @Test("Formats without year use the provided fallback year")
    func fallbackYearIsApplied() {
        let customYear = 2028
        #expect(EventDay.parse("Thursday, April 23", year: customYear)?.year == customYear)
        #expect(EventDay.parse("Thursday, 28 May", year: customYear)?.year == customYear)
        #expect(EventDay.parse("Wednesday, 06.05.", year: customYear)?.year == customYear)
    }

    // MARK: - Invalid input

    @Test("Empty string returns nil")
    func emptyString() {
        #expect(EventDay.parse("", year: fallbackYear) == nil)
    }

    @Test("Unrecognised format returns nil")
    func unrecognisedFormat() {
        #expect(EventDay.parse("not a date at all", year: fallbackYear) == nil)
    }

    @Test("Leading and trailing whitespace is handled")
    func trimmingWhitespace() {
        let result = EventDay.parse("  Thursday, 9 April 2026  ", year: fallbackYear)
        #expect(result == EventDay(day: 9, month: 4, year: 2026))
    }
}
