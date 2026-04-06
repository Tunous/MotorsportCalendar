import Testing
@testable import MotorsportCalendar

@Suite("EventTitleCleaner.clean")
struct EventTitleCleanerTests {
    let year = 2026

    // MARK: - Year removal

    @Test("Trailing year is removed")
    func trailingYearRemoved() {
        #expect(cleaner.clean("Rally Estonia 2026") == "Rally Estonia")
    }

    @Test("Trailing year with extra whitespace is removed")
    func trailingYearWithWhitespaceRemoved() {
        #expect(cleaner.clean("Rally Estonia  2026") == "Rally Estonia")
    }

    @Test("Year in the middle of the title is removed")
    func yearInMiddleRemoved() {
        #expect(cleaner.clean("Rally Islas Canarias 2026 - Rally of Spain") == "Rally Islas Canarias - Rally of Spain")
    }

    @Test("Year at the very start is not removed — no preceding whitespace to match")
    func yearAtStartPreserved() {
        #expect(cleaner.clean("2026 Rally Estonia") == "2026 Rally Estonia")
    }

    @Test("A different year is not removed")
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

    @Test("Both prefix and year are removed")
    func prefixAndYearRemoved() {
        #expect(cleaner.clean("WRC Rally Estonia 2026") == "Rally Estonia")
    }

    @Test("Prefix, mid-string year, and suffix are all cleaned")
    func prefixMidYearAndSuffixCleaned() {
        #expect(cleaner.clean("WRC Rally Islas Canarias 2026 - Rally of Spain") == "Rally Islas Canarias - Rally of Spain")
    }

    @Test("Title with neither prefix nor year is unchanged")
    func cleanTitleUnchanged() {
        #expect(cleaner.clean("Rally Estonia") == "Rally Estonia")
    }

    // MARK: - First letter capitalization

    @Test("Lowercase first letter is capitalized")
    func lowercaseFirstLetterCapitalized() {
        #expect(cleaner.clean("ueno Rally del Paraguay") == "Ueno Rally del Paraguay")
    }

    @Test("Already-capitalized title is unchanged")
    func capitalizedTitleUnchanged() {
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
