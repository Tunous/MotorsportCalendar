import Foundation
import Testing
@testable import MotorsportCalendar
import MotorsportCalendarData

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

        let events = try RacingICalParser.parse(url, year: 2026, series: .formula1)
        let event = try #require(events.first)

        #expect(event.stages.map(\.title) == ["Practice 1"])
        #expect(event.stages.map(\.id) == ["practice-1"])
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

        let events = try RacingICalParser.parse(url, year: 2026, series: .formula1)
        let event = try #require(events.first)

        #expect(event.title == "Bahrain Grand Prix in Malaysia")
        #expect(event.id == "bahrain-grand-prix-in-malaysia")
        #expect(event.stages.map(\.title) == ["Qualifying"])
        #expect(event.stages.map(\.isConfirmed) == [false])
        #expect(event.isConfirmed == false)
    }

    @Test func `class names disambiguate practice sessions`() throws {
        let calendar = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//MotorsportCalendar Tests//EN
        BEGIN:VEVENT
        DTSTART:20260717T113000Z
        DTEND:20260717T123000Z
        SUMMARY:6 HOURS OF BARCELONA 2026 - Free Practice 3 - LMGT3
        UID:practice-a@example.com
        END:VEVENT
        BEGIN:VEVENT
        DTSTART:20260717T133000Z
        DTEND:20260717T143000Z
        SUMMARY:6 HOURS OF BARCELONA 2026 - Free Practice 3 - Hypercar
        UID:practice-b@example.com
        END:VEVENT
        END:VCALENDAR
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wec-duplicate-practice-\(UUID().uuidString).ics")
        try calendar.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let event = try #require(RacingICalParser.parse(url, year: 2026, series: .wec).first)

        #expect(event.stages.map(\.id) == [
            "practice-3-lmgt3",
            "practice-3-hypercar",
        ])
    }

    @Test func `date-only values are UTC midnight regardless of local time zone`() throws {
        let event = try parseSingleEvent(sessions: [
            dateOnly("Qualifying", start: "20270313", end: "20270314"),
        ])

        #expect(event.startDate == utc(2027, 3, 13))
        #expect(event.endDate == utc(2027, 3, 14))
        #expect(event.stages.map(\.startDate) == [utc(2027, 3, 13)])
        #expect(event.stages.map(\.endDate) == [utc(2027, 3, 14)])
    }

    @Test func `date-time values keep their absolute instant`() throws {
        let event = try parseSingleEvent(sessions: [
            """
            BEGIN:VEVENT
            DTSTART:20270313T143000Z
            DTEND:20270313T153000Z
            LOCATION:Bahrain
            SUMMARY:FORMULA 1 BAHRAIN GRAND PRIX 2027 - Qualifying
            UID:qualifying
            END:VEVENT
            """,
        ])

        #expect(event.startDate == utc(2027, 3, 13).addingTimeInterval(14.5 * 3600))
    }

    @Test func `stages with the same start follow the weekend running order`() throws {
        let event = try parseSingleEvent(sessions: [
            dateOnly("Race", start: "20270314", end: "20270315"),
            dateOnly("Sprint Race", start: "20270313", end: "20270314"),
            dateOnly("Qualifying", start: "20270313", end: "20270314"),
            dateOnly("Sprint Qualification", start: "20270312", end: "20270313"),
            dateOnly("Practice 1", start: "20270312", end: "20270313"),
        ])

        #expect(event.stages.map(\.title) == [
            "Practice 1", "Sprint Qualification", "Sprint Race", "Qualifying", "Race",
        ])
    }

    @Test func `regular weekend ties are ordered independently of feed order`() throws {
        let event = try parseSingleEvent(sessions: [
            dateOnly("Practice 2", start: "20270319", end: "20270320"),
            dateOnly("Practice 1", start: "20270319", end: "20270320"),
            dateOnly("Qualifying", start: "20270320", end: "20270321"),
            dateOnly("Practice 3", start: "20270320", end: "20270321"),
        ])

        #expect(event.stages.map(\.title) == ["Practice 1", "Practice 2", "Practice 3", "Qualifying"])
    }

    @Test func `start time takes precedence over running order`() throws {
        let event = try parseSingleEvent(sessions: [
            dateOnly("Practice 1", start: "20270320", end: "20270321"),
            dateOnly("Race", start: "20270319", end: "20270320"),
        ])

        #expect(event.stages.map(\.title) == ["Race", "Practice 1"])
    }

    @Test func `unknown stages with the same start keep feed order after known ones`() throws {
        let event = try parseSingleEvent(sessions: [
            dateOnly("Zeta Session", start: "20270319", end: "20270320"),
            dateOnly("Race", start: "20270319", end: "20270320"),
            dateOnly("Alpha Session", start: "20270319", end: "20270320"),
        ])

        #expect(event.stages.map(\.title) == ["Race", "Zeta Session", "Alpha Session"])
    }

    private func dateOnly(_ stage: String, start: String, end: String) -> String {
        """
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:\(start)
        DTEND;VALUE=DATE:\(end)
        LOCATION:Bahrain
        SUMMARY:FORMULA 1 BAHRAIN GRAND PRIX 2027 - \(stage)
        UID:\(stage.replacingOccurrences(of: " ", with: "-"))-\(start)
        END:VEVENT
        """
    }

    private func parseSingleEvent(sessions: [String]) throws -> MotorsportEvent {
        let calendar = (["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//MotorsportCalendar Tests//EN"] + sessions + ["END:VCALENDAR"])
            .joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("formula-1-\(UUID().uuidString).ics")
        try calendar.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let events = try RacingICalParser.parse(url, year: 2027, series: .formula1)
        return try #require(events.first)
    }

    private func utc(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateComponents(calendar: .gmt, timeZone: .gmt, year: year, month: month, day: day).date!
    }
}
