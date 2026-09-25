import Testing
@testable import MotorsportCalendar

@Suite("MotorsportCalendar command")
struct MotorsportCalendarCommandTests {
    @Test("Series flags select one or more series, defaulting to all")
    func seriesSelection() throws {
        let cases = [
            (arguments: ["--output", "/tmp/calendars"], expected: ["formula1", "wec", "wrc"]),
            (arguments: ["--output", "/tmp/calendars", "--formula1"], expected: ["formula1"]),
            (arguments: ["--output", "/tmp/calendars", "--wrc"], expected: ["wrc"]),
            (arguments: ["--output", "/tmp/calendars", "--wec"], expected: ["wec"]),
            (arguments: ["--output", "/tmp/calendars", "--formula1", "--wec"], expected: ["formula1", "wec"]),
        ]

        for testCase in cases {
            let command = try MotorsportCalendar.parse(testCase.arguments)
            let selected = command.selectedSeries.map(\.rawValue).sorted()
            #expect(selected == testCase.expected)
        }
    }
}
