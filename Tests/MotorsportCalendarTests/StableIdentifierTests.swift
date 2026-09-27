import Foundation
import Testing
@testable import MotorsportCalendar
import MotorsportCalendarData

struct StableIdentifierTests {
    @Test(
        "WRC session identifiers use itinerary semantics",
        arguments: [
            ("SS1 Original Stage Name", "ss1"),
            ("Ss 23 Wolf Power Stage - Fafe 2", "ss23"),
            ("SSS4 City Stage", "sss4"),
            ("Wolf Power Stage - SS20 Himos-Jämsä 2", "ss20"),
            ("Finish - SS 16 BioBío 2", "ss16"),
            ("Ceremonial Start - Rijeka", "ceremonial-start"),
            ("Shakedown (Baltar)", "shakedown"),
            ("Flexi service A - Service Park", "flexi-service-a"),
            ("Remote service 2 - Tyre Zone", "remote-service-2"),
            ("Podium - Sunday", "podium"),
            ("Parc Fermé - City Centre", "parc-ferme"),
        ]
    )
    func wrcSession(value: String, expectedIdentifier: String) {
        #expect(StableIdentifier.session(value, series: .wrc) == expectedIdentifier)
    }

    @Test(
        "WRC event identifiers use normalized source slugs",
        arguments: [
            ("wrc-rallye-monte-carlo-2026", "wrc-rallye-monte-carlo-2026"),
            ("WRC Vodafone Rally de Portugal 2026", "wrc-vodafone-rally-de-portugal-2026"),
            ("wrc-forum8-rally-japan-2026", "wrc-forum8-rally-japan-2026"),
            ("wrc-eko-acropolis-rally-greece-2026", "wrc-eko-acropolis-rally-greece-2026"),
            ("wrc-delfi-rally-estonia-2026", "wrc-delfi-rally-estonia-2026"),
            ("wrc-secto-rally-finland-2026", "wrc-secto-rally-finland-2026"),
            ("wrc-rally-chile-biobio-2026", "wrc-rally-chile-biobio-2026"),
        ]
    )
    func wrcEvent(sourceSlug: String, expectedIdentifier: String) {
        #expect(StableIdentifier.event(sourceSlug, series: .wrc) == expectedIdentifier)
    }

    @Test("WRC event and session normalization are independent")
    func wrcEntityKinds() {
        #expect(StableIdentifier.event("Service Park Rally 2026", series: .wrc) == "service-park-rally-2026")
        #expect(StableIdentifier.event("Start Rally 2026", series: .wrc) == "start-rally-2026")
        #expect(StableIdentifier.event("Finish Rally 2026", series: .wrc) == "finish-rally-2026")
        #expect(StableIdentifier.session("Service Park Rally 2026", series: .wrc) == "service")
        #expect(StableIdentifier.session("Start Rally 2026", series: .wrc) == "start")
        #expect(StableIdentifier.session("Finish Rally 2026", series: .wrc) == "finish")
    }

    @Test(
        "Equivalent iCalendar session titles retain identity",
        arguments: [
            ("Practice 1", "practice-1"),
            ("Free Practice 1", "practice-1"),
            ("First Practice Session", "practice-1"),
            ("Practice Session 1", "practice-1"),
            ("FP1", "practice-1"),
            ("Free Practice 3 - LMGT3", "practice-3-lmgt3"),
            ("Free Practice 3 - Hypercar", "practice-3-hypercar"),
            ("Sprint Shootout", "sprint-qualification"),
            ("Sprint Qualifying Session", "sprint-qualification"),
            ("Sprint", "sprint-race"),
            ("Sprint Race", "sprint-race"),
            ("Qualifying Session", "qualifying"),
            ("Race Session", "race"),
            ("Qualifying - LMGT3", "qualifying-lmgt3"),
            ("Hyperpole 2 - Hypercar", "hyperpole-2-hypercar"),
        ]
    )
    func iCalendarSession(value: String, expectedIdentifier: String) {
        #expect(StableIdentifier.session(value, series: .formula1) == expectedIdentifier)
    }

    @Test(arguments: Series.allCases, 2024...2026)
    func bundledCalendarIdentifiersAreValidAndUnique(series: Series, year: Int) {
        let events = MotorsportLocalData.events(series: series, year: year)

        #expect(!events.isEmpty)
        #expect(allIdentifiersAreValidAndUnique(events.map(\.id)))

        if series == .wrc {
            #expect(events.allSatisfy { $0.id.hasPrefix("wrc-") && $0.id.hasSuffix("-\(year)") })
        } else {
            #expect(events.allSatisfy { $0.id == StableIdentifier.event($0.title, series: series) })
        }

        for event in events {
            #expect(allIdentifiersAreValidAndUnique(event.stages.map(\.id)))
            #expect(sessionIdentifiersMatchGenerationRules(for: event, series: series))
        }
    }

    private func allIdentifiersAreValidAndUnique(_ identifiers: [String]) -> Bool {
        identifiers.allSatisfy { StableIdentifier.isNormalized($0) }
            && identifiers.count == Set(identifiers).count
    }

    private func sessionIdentifiersMatchGenerationRules(
        for event: MotorsportEvent,
        series: Series
    ) -> Bool {
        var expectedIdentifiers = event.stages.map { StableIdentifier.session($0.title, series: series) }
        let indexGroups = Dictionary(grouping: expectedIdentifiers.indices) { expectedIdentifiers[$0] }

        if series == .wrc {
            for indices in indexGroups.values where indices.count > 1 {
                for (ordinal, index) in indices.enumerated() {
                    expectedIdentifiers[index] += "-\(ordinal + 1)"
                }
            }
            return event.stages.map(\.id) == expectedIdentifiers
        }

        return event.stages.map(\.id) == expectedIdentifiers
    }

    @Test func requiredIdentifierEncodingAndDecoding() throws {
        let dataWithoutIdentifier = Data(#"{"title":"São Paulo","startDate":"2026-01-01T00:00:00Z","endDate":"2026-01-01T01:00:00Z","stages":[],"isConfirmed":true}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder.motorsportCalendar.decode(MotorsportEvent.self, from: dataWithoutIdentifier)
        }

        let event = MotorsportEvent(
            id: "sao-paulo",
            title: "São Paulo",
            startDate: .distantPast,
            endDate: .distantFuture,
            stages: [],
            isConfirmed: true
        )
        let encoded = try JSONEncoder.motorsportCalendar.encode(event)
        #expect(String(decoding: encoded, as: UTF8.self).contains(#""id":"sao-paulo""#))
    }
}
