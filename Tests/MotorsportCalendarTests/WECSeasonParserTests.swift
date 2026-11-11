import Foundation
import SwiftSoup
import Testing
@testable import MotorsportCalendar

struct WECSeasonParserTests {
    private let baseURL = URL(string: "https://www.fiawec.com")!

    private let nextSeasonOnlyHTML = """
    <div class="season-overview">
      <a class="season-selector season-selector--link" href="/en/season/2026">PREVIOUS SEASONS</a>
      <button class="season-selector active" data-season="15">Season 2027</button>
      <div class="season-content" data-season="15">
        <a href="/en/race/qatar-1812km-2027">QAT</a>
        <a href="/en/race/6-hours-of-imola-2027">ITA</a>
      </div>
    </div>
    """

    @Test func `season content is missing when page lists only another season`() throws {
        let document = try SwiftSoup.parse(nextSeasonOnlyHTML)

        #expect(try WECSeasonParser.seasonContent(in: document, year: 2026) == nil)
        #expect(try WECSeasonParser.seasonContent(in: document, year: 2027) != nil)
    }

    @Test func `season content is selected by season year`() throws {
        let document = try SwiftSoup.parse("""
        <div class="season-overview">
          <button class="season-selector" data-season="14">Season 2026</button>
          <button class="season-selector" data-season="15">Season 2027</button>
          <div class="season-content" data-season="14"><a href="/en/race/6-hours-of-fuji-2026">JPN</a></div>
          <div class="season-content" data-season="15"><a href="/en/race/6-hours-of-fuji-2027">JPN</a></div>
        </div>
        """)

        let content = try #require(try WECSeasonParser.seasonContent(in: document, year: 2026))
        let links = try WECSeasonParser.eventLinks(from: content, baseURL: baseURL)

        #expect(links.map(\.url.absoluteString) == ["https://www.fiawec.com/en/race/6-hours-of-fuji-2026"])
    }

    @Test func `event links expose year from url`() throws {
        let document = try SwiftSoup.parse(nextSeasonOnlyHTML)
        let content = try #require(try WECSeasonParser.seasonContent(in: document, year: 2027))
        let links = try WECSeasonParser.eventLinks(from: content, baseURL: baseURL)

        #expect(links.map(\.year) == [2027, 2027])
        #expect(WECSeasonEventLink(url: URL(string: "https://www.fiawec.com/en/race/le-mans")!, isCompleted: false).year == nil)
    }
}
