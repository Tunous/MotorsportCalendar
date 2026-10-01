import Foundation
import SwiftSoup
import Testing
@testable import MotorsportCalendar

struct WECEventPageParserTests {
    @Test func `builds event from page schedule when iCalendar is unavailable`() throws {
        let document = try SwiftSoup.parse("""
        <h1>
          <span class="d-block">6 Hours of</span>
          <span class="d-block">Qatar 2027</span>
        </h1>
        <div is="timemode-switch">
          <div class="grid">
            <div>
              <div class="ff-normal">March 25<sup>th</sup></div>
              <div class="d-flex flex-column align-items-start gap-1">
                <div class="fw-bold lh-sm">Free Practice 1</div>
                <div class="text-primary fst-italic"><em class="text-danger">TBC</em></div>
              </div>
            </div>
            <div>
              <div class="ff-normal">March 27<sup>th</sup></div>
              <div class="d-flex flex-column align-items-start gap-1">
                <div class="fw-bold lh-sm">Race</div>
                <div class="text-primary fst-italic">
                  <span data-local="01:00 PM" data-timestamp="1806141600">01:00 PM</span>
                </div>
              </div>
            </div>
          </div>
        </div>
        """)

        let event = try #require(try WECEventPageParser.event(from: document, year: 2027, series: .wec))

        #expect(event.id == "6-hours-of-qatar")
        #expect(event.title == "6 Hours of Qatar")
        #expect(!event.isConfirmed)
        #expect(event.stages.map(\.id) == ["practice-1", "race"])

        let practice = event.stages[0]
        #expect(!practice.isConfirmed)
        #expect(!practice.isSignificant)
        // Midnight in track time (UTC+3), derived from the race's local time and timestamp.
        #expect(practice.startDate == Date(timeIntervalSince1970: 1_805_922_000))
        #expect(practice.endDate == practice.startDate.addingTimeInterval(24 * 60 * 60))

        let race = event.stages[1]
        #expect(race.isConfirmed)
        #expect(race.isSignificant)
        #expect(race.startDate == Date(timeIntervalSince1970: 1_806_141_600))
        #expect(event.startDate == practice.startDate)
        #expect(race.endDate == race.startDate.addingTimeInterval(6 * 60 * 60))
        #expect(event.endDate == race.endDate)
    }

    @Test func `race length is taken from event title`() throws {
        #expect(WECEventPageParser.raceDuration(fromTitle: "24 Hours of Le Mans") == TimeInterval(24 * 60 * 60))
        #expect(WECEventPageParser.raceDuration(fromTitle: "Bapco Energies 8 Hours of Bahrain") == TimeInterval(8 * 60 * 60))
        #expect(WECEventPageParser.raceDuration(fromTitle: "Qatar 1812km") == nil)
    }

    @Test func `track offset handles negative offsets and falls back to UTC`() throws {
        let americas = try SwiftSoup.parse("""
        <div is="timemode-switch">
          <span data-local="12:00 AM" data-timestamp="1820552400">12:00 AM</span>
        </div>
        """)
        let unscheduled = try SwiftSoup.parse(#"<div is="timemode-switch"></div>"#)

        #expect(try WECEventPageParser.trackUTCOffset(from: americas) == -5 * 60 * 60)
        #expect(try WECEventPageParser.trackUTCOffset(from: unscheduled) == 0)
    }
}
