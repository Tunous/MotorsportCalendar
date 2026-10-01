import Foundation
import MotorsportCalendarData
import Testing
@testable import MotorsportCalendar

struct CalendarProviderTests {
    @Test func `season without published events is not written`() async throws {
        let outputURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let didUpdate = try await EmptyCalendarProvider(outputURL: outputURL).run(year: 2027)

        #expect(!didUpdate)
        #expect(!FileManager.default.fileExists(atPath: outputURL.appending(path: "wrc/2027.json").path()))
    }
}

private struct EmptyCalendarProvider: CalendarProvider {
    let outputURL: URL
    let series: Series = .wrc

    func events(year: Int) async throws -> [MotorsportEvent] { [] }
}
