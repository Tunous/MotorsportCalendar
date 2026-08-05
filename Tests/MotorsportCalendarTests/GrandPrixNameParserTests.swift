import Testing
@testable import MotorsportCalendar

@Suite("GrandPrixNameParser.parse")
struct GrandPrixNameParserTests {
    @Test("Extracts the event name after sponsor text")
    func extractsNameAfterSponsorText() {
        let summary = "⏱️ FORMULA 1 GULF AIR BAHRAIN GRAND PRIX IN MALAYSIA 2026 - Qualifying (TBC)"

        #expect(
            GrandPrixNameParser.parse(summary: summary, location: "Malaysia") ==
                "Bahrain Grand Prix in Malaysia"
        )
    }

    @Test("Supports multi-word Grand Prix names")
    func supportsMultiWordNames() {
        let summary = "FORMULA 1 ETIHAD AIRWAYS ABU DHABI GRAND PRIX IN UAE 2026 - Race"

        #expect(
            GrandPrixNameParser.parse(summary: summary, location: "UAE") ==
                "Abu Dhabi Grand Prix in UAE"
        )
    }

    @Test("Uses the location mapping for ordinary summaries")
    func usesLocationMappingForOrdinarySummaries() {
        #expect(
            GrandPrixNameParser.parse(
                summary: "FORMULA 1 JAPANESE GRAND PRIX 2026 - Race",
                location: "Japan"
            ) == "Japanese Grand Prix"
        )
    }

    @Test("Uses summary details for location-specific names")
    func usesSummaryDetailsForLocationSpecificNames() {
        #expect(
            GrandPrixNameParser.parse(
                summary: "FORMULA 1 MIAMI GRAND PRIX 2026 - Race",
                location: "United States"
            ) == "Miami Grand Prix"
        )
    }

    @Test("Falls back to the location for unknown summaries")
    func fallsBackToLocation() {
        let summary = "FORMULA 1 BAHRAIN GRAND PRIX 2026 - Race"

        #expect(GrandPrixNameParser.parse(summary: summary, location: "Bahrain") == "Bahrain Grand Prix")
    }
}
