import Foundation
import Testing
@testable import MotorsportCalendar

@Suite("WRC event timezone")
struct WRCCalendarProviderTests {
    @Test("Itinerary offsets take precedence over the calendar card offset")
    func eventTimeZoneSelection() throws {
        let paraguay = try #require(WRCCalendarProvider.timeZone(
            fromISO8601: "2026-08-27T09:00:00-03:00"
        ))
        let explicit = WRCCalendarProvider.eventTimeZone(
            faqTitles: ["All times UTC+2"],
            fallback: paraguay
        )

        #expect(explicit.secondsFromGMT() == 2 * 60 * 60)
        #expect(paraguay.secondsFromGMT(for: Date(timeIntervalSince1970: 1_787_918_580)) == -3 * 60 * 60)
    }
}
