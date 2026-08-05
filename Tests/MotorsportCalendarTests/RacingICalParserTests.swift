import Foundation
import Testing
@testable import MotorsportCalendar

struct RacingICalParserTests {
    @Test func `practice zero is normalized to practice one`() throws {
        let calendar = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//MotorsportCalendar Tests//EN
        BEGIN:VEVENT
        DTSTART:20260717T113000Z
        DTEND:20260717T123000Z
        LOCATION:Belgium
        SUMMARY:FORMULA 1 BELGIAN GRAND PRIX 2026 - Practice 0
        UID:practice-zero
        END:VEVENT
        END:VCALENDAR
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("formula-1-practice-zero-\(UUID().uuidString).ics")
        try calendar.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let events = try RacingICalParser.parse(url, year: 2026)
        let event = try #require(events.first)

        #expect(event.stages.map(\.title) == ["Practice 1"])
    }

    @Test func `Grand Prix in location is extracted and trailing TBC is removed`() throws {
        let calendar = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//MotorsportCalendar Tests//EN
        BEGIN:VEVENT
        DTSTART:20261001T113000Z
        DTEND:20261001T123000Z
        LOCATION:Malaysia
        SUMMARY:⏱️ FORMULA 1 GULF AIR BAHRAIN GRAND PRIX IN MALAYSIA 2026 - Qualifying (TBC)
        UID:bahrain-in-malaysia-qualifying
        END:VEVENT
        END:VCALENDAR
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("formula-1-tbc-\(UUID().uuidString).ics")
        try calendar.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let events = try RacingICalParser.parse(url, year: 2026)
        let event = try #require(events.first)

        #expect(event.title == "Bahrain Grand Prix in Malaysia")
        #expect(event.stages.map(\.title) == ["Qualifying"])
        #expect(event.stages.map(\.isConfirmed) == [false])
        #expect(event.isConfirmed == false)
    }
}
