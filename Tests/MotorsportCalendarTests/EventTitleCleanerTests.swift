import Testing
@testable import MotorsportCalendar

@Suite("EventTitleCleaner.clean")
struct EventTitleCleanerTests {
    let year = 2026

    // MARK: - Trailing year removal

    @Test("Trailing year is removed")
    func trailingYearRemoved() {
        #expect(cleaner.clean("Rally Estonia 2026") == "Rally Estonia")
    }

    @Test("Trailing year with extra whitespace is removed")
    func trailingYearWithWhitespaceRemoved() {
        #expect(cleaner.clean("Rally Estonia  2026") == "Rally Estonia")
    }

    @Test("Year in the middle of the title is not removed")
    func yearInMiddlePreserved() {
        #expect(cleaner.clean("2026 Rally Estonia") == "2026 Rally Estonia")
    }

    @Test("A different year at the end is not removed")
    func differentYearPreserved() {
        #expect(cleaner.clean("Rally Estonia 2025") == "Rally Estonia 2025")
    }

    // MARK: - Leading series prefix removal

    @Test("Leading 'WRC ' prefix is removed")
    func leadingWRCPrefixRemoved() {
        #expect(cleaner.clean("WRC Rally Estonia") == "Rally Estonia")
    }

    @Test("Leading 'WRC ' with extra spaces is removed")
    func leadingWRCPrefixWithSpacesRemoved() {
        #expect(cleaner.clean("WRC  Rally Estonia") == "Rally Estonia")
    }

    @Test("'WRC' in the middle of the title is not removed")
    func wrcInMiddlePreserved() {
        #expect(cleaner.clean("Rally WRC Estonia") == "Rally WRC Estonia")
    }

    // MARK: - Combined

    @Test("Both prefix and trailing year are removed")
    func prefixAndTrailingYearRemoved() {
        #expect(cleaner.clean("WRC Rally Estonia 2026") == "Rally Estonia")
    }

    @Test("Title with neither prefix nor year is unchanged")
    func cleanTitleUnchanged() {
        #expect(cleaner.clean("Rally Estonia") == "Rally Estonia")
    }

    // MARK: - Whitespace trimming

    @Test("Leading and trailing whitespace is trimmed")
    func outerWhitespaceTrimmed() {
        #expect(cleaner.clean("  Rally Estonia  ") == "Rally Estonia")
    }

    @Test("Empty string returns empty string")
    func emptyString() {
        #expect(cleaner.clean("") == "")
    }

    // MARK: - Helpers

    private var cleaner: EventTitleCleaner { EventTitleCleaner(year: year) }
}
