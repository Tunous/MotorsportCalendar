import Testing
@testable import MotorsportCalendar

@Suite("StageLine.parse")
struct StageLineTests {

    // MARK: - Lines with time

    @Test("Standard time + title + km suffix")
    func timeAndTitleWithKm() {
        let result = StageLine.parse("15:05: SS1 Águeda / Sever (15.08 km)")
        #expect(result == StageLine(time: .init(hour: 15, minute: 5), title: "SS1 Águeda / Sever", isConfirmed: true))
    }

    @Test("Time + title without km suffix")
    func timeAndTitleWithoutKm() {
        let result = StageLine.parse("18:30: Ceremonial Start - Rijeka Korzo")
        #expect(result == StageLine(time: .init(hour: 18, minute: 30), title: "Ceremonial Start - Rijeka Korzo", isConfirmed: true))
    }

    @Test("ALL CAPS words in title are converted to title case")
    func allCapsWordsNormalized() {
        let result = StageLine.parse("15:06: SS5 VALLESECO - ARTENARA 2 (15.27 km)")
        #expect(result == StageLine(time: .init(hour: 15, minute: 6), title: "SS5 Valleseco - Artenara 2", isConfirmed: true))
    }

    @Test("Single-digit hour is parsed correctly")
    func singleDigitHour() {
        let result = StageLine.parse("9:00: SS2 Morning Stage (8.50 km)")
        #expect(result?.time == StageLine.Time(hour: 9, minute: 0))
        #expect(result?.title == "SS2 Morning Stage")
    }

    @Test("Time separator with space instead of colon")
    func timeSeparatorSpace() {
        let result = StageLine.parse("10:15 SS3 Forest Loop (12.00 km)")
        #expect(result?.time == StageLine.Time(hour: 10, minute: 15))
        #expect(result?.title == "SS3 Forest Loop")
    }

    // MARK: - Lines without time

    @Test("Title-only line has nil time")
    func titleOnlyHasNilTime() {
        let result = StageLine.parse("Shakedown - Baltar (5.72 km)")
        #expect(result?.time == nil)
        #expect(result?.title == "Shakedown - Baltar")
    }

    @Test("Title-only without km has nil time")
    func titleOnlyNoKmHasNilTime() {
        let result = StageLine.parse("Service Park Opening")
        #expect(result?.time == nil)
        #expect(result?.title == "Service Park Opening")
    }

    // MARK: - isConfirmed

    @Test("Stage with time is confirmed")
    func stageWithTimeIsConfirmed() {
        let result = StageLine.parse("14:00: SS7 Lake Stage (10.00 km)")
        #expect(result?.isConfirmed == true)
    }

    @Test("Stage without time is unconfirmed")
    func stageWithoutTimeIsUnconfirmed() {
        let result = StageLine.parse("Shakedown - Baltar (5.72 km)")
        #expect(result?.isConfirmed == false)
    }

    // MARK: - Title normalisation

    @Test("km suffix is stripped")
    func kmSuffixStripped() {
        #expect(StageLine.parse("08:00: SS1 Test (5.72 km)")?.title == "SS1 Test")
        #expect(StageLine.parse("08:00: SS1 Test (5.72KM)")?.title == "SS1 Test")
    }

    @Test("Stage identifiers with digits are not title-cased")
    func stageIdentifiersUnchanged() {
        let result = StageLine.parse("10:00: SSS1 STAGE NAME (3.00 km)")
        #expect(result?.title == "SSS1 Stage Name")
    }

    @Test("Mixed-case words are left unchanged")
    func mixedCaseUnchanged() {
        let result = StageLine.parse("10:00: Águeda / Sever")
        #expect(result?.title == "Águeda / Sever")
    }

    // MARK: - Stage abbreviation uppercase

    @Test("Lowercase ss abbreviation with number is uppercased")
    func lowercaseSSAbbreviationUppercased() {
        #expect(StageLine.parse("08:00: ss3 Stage Name")?.title == "SS3 Stage Name")
    }

    @Test("Mixed-case Ss abbreviation with number is uppercased")
    func mixedCaseSSAbbreviationUppercased() {
        #expect(StageLine.parse("08:00: Ss3 Stage Name")?.title == "SS3 Stage Name")
    }

    @Test("Lowercase sss abbreviation with number is uppercased")
    func lowercaseSSSAbbreviationUppercased() {
        #expect(StageLine.parse("08:00: sss1 Stage Name")?.title == "SSS1 Stage Name")
    }

    @Test("Title-cased Sss abbreviation with number is uppercased")
    func titleCasedSSSAbbreviationUppercased() {
        #expect(StageLine.parse("08:00: Sss1 Stage Name")?.title == "SSS1 Stage Name")
    }

    @Test("Standalone Sss without number is uppercased")
    func standaloneSssUppercased() {
        #expect(StageLine.parse("08:00: Sss Stage Name")?.title == "SSS Stage Name")
    }

    @Test("Correct SS abbreviation is unchanged")
    func correctSSAbbreviationUnchanged() {
        #expect(StageLine.parse("08:00: SS3 Stage Name")?.title == "SS3 Stage Name")
    }

    @Test("Correct SSS abbreviation is unchanged")
    func correctSSSAbbreviationUnchanged() {
        #expect(StageLine.parse("08:00: SSS1 Stage Name")?.title == "SSS1 Stage Name")
    }

    // MARK: - Duplicate leading abbreviation removal

    @Test("Duplicate SS numbers at start are deduplicated keeping first")
    func duplicateSSNumbersDeduplicatedKeepingFirst() {
        #expect(StageLine.parse("08:00: SS1 SS2 Stage Name")?.title == "SS1 Stage Name")
    }

    @Test("Duplicate SSS numbers at start are deduplicated keeping first")
    func duplicateSSSNumbersDeduplicatedKeepingFirst() {
        #expect(StageLine.parse("08:00: SSS1 SSS2 Stage Name")?.title == "SSS1 Stage Name")
    }

    @Test("Mixed SS and SSS duplicates at start are deduplicated keeping first")
    func mixedSSAndSSSDeduplicatedKeepingFirst() {
        #expect(StageLine.parse("08:00: SS1 SSS1 Stage Name")?.title == "SS1 Stage Name")
    }

    @Test("Single SS abbreviation at start is not changed")
    func singleSSAbbreviationUnchanged() {
        #expect(StageLine.parse("08:00: SS1 Stage Name")?.title == "SS1 Stage Name")
    }

    @Test("SS abbreviations not at the start are not removed")
    func ssAbbreviationsNotAtStartPreserved() {
        #expect(StageLine.parse("08:00: Stage Name SS1 SS2")?.title == "Stage Name SS1 SS2")
    }

    // MARK: - Invalid input

    @Test("Empty string returns nil")
    func emptyString() {
        #expect(StageLine.parse("") == nil)
    }

    @Test("Whitespace-only string returns nil")
    func whitespaceOnly() {
        #expect(StageLine.parse("   ") == nil)
    }
}
