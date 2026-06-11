import Foundation
import SwiftSoup
import Testing
@testable import MotorsportCalendar

struct WECItineraryParserTests {
    @Test func `website timestamps override double-offset iCalendar starts`() throws {
        let html = """
        <div is="timemode-switch">
          <div class="d-flex flex-column align-items-start gap-1">
            <div class="fw-bold lh-sm">Free Practice 3</div>
            <span data-local="02:45 PM" data-timestamp="1781181900">02:45 PM</span>
          </div>
        </div>
        """
        let document = try SwiftSoup.parse(html)
        let date = try #require(WECItineraryParser.startDates(from: document)["Free Practice 3"])

        #expect(date == Date(timeIntervalSince1970: 1_781_181_900))
    }

    @Test func `website timestamps are independent of local timezone`() throws {
        let document = try SwiftSoup.parse("""
        <div is="timemode-switch">
          <div class="d-flex flex-column align-items-start gap-1">
            <div class="fw-bold lh-sm">Race</div>
            <span data-timestamp="1781359200">04:00 PM</span>
          </div>
        </div>
        """)

        let date = try #require(WECItineraryParser.startDates(from: document)["Race"])
        let utc = try #require(TimeZone(identifier: "UTC"))
        let warsaw = try #require(TimeZone(identifier: "Europe/Warsaw"))
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))

        #expect(Calendar.gregorian(in: utc).dateComponents([.hour], from: date).hour == 14)
        #expect(Calendar.gregorian(in: warsaw).dateComponents([.hour], from: date).hour == 16)
        #expect(Calendar.gregorian(in: losAngeles).dateComponents([.hour], from: date).hour == 7)
    }
}

private extension Calendar {
    static func gregorian(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
