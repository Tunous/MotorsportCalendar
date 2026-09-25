import ArgumentParser
import Foundation
import MotorsportCalendarData

@main
struct MotorsportCalendar: AsyncParsableCommand {

    @Option
    var output: String

    @Option(transform: { string in
        guard let url = URL(string: string) else {
            throw ValidationError("Incorrect Formula 1 calendar url")
        }
        return url
    })
    var formula1CalendarURL: URL?

    @Flag(help: "Generate the Formula 1 calendar")
    var formula1 = false

    @Flag(help: "Generate the WRC calendar")
    var wrc = false

    @Flag(help: "Generate the WEC calendar")
    var wec = false

    @Option
    var year: Int = Calendar.current.component(.year, from: .now)

    var selectedSeries: Set<Series> {
        let selections: [Series?] = [
            formula1 ? .formula1 : nil,
            wrc ? .wrc : nil,
            wec ? .wec : nil,
        ]
        let selected = Set(selections.compactMap { $0 })
        return selected.isEmpty ? Set(Series.allCases) : selected
    }

    mutating func run() async throws {
        let outputPath = NSString(string: output).expandingTildeInPath
        let outputURL = URL(filePath: outputPath, directoryHint: .isDirectory)

        var providers: [any CalendarProvider] = []
        if selectedSeries.contains(.formula1) {
            guard let formula1CalendarURL else {
                throw ValidationError("--formula1-calendar-url is required when generating Formula 1")
            }
            providers.append(Formula1CalendarProvider(outputURL: outputURL, calendarURL: formula1CalendarURL))
        }
        if selectedSeries.contains(.wrc) {
            providers.append(WRCCalendarProvider(outputURL: outputURL))
        }
        if selectedSeries.contains(.wec) {
            providers.append(WECCalendarProvider(outputURL: outputURL))
        }

        let updatedSeries = try await withThrowingTaskGroup(of: (Series, Bool).self, returning: Set<Series>.self) { group in
            for provider in providers {
                group.addTask { [year] in
                    do {
                        let didUpdate = try await provider.run(year: year)
                        return (provider.series, didUpdate)
                    } catch {
                        print(coloredLog("[\(provider.series)] Error: \(error)", color: LogColor.red))
                        throw error
                    }
                }
            }

            var updatedSeries: Set<Series> = []
            for try await (series, didUpdate) in group {
                if didUpdate {
                    updatedSeries.insert(series)
                }
            }
            return updatedSeries
        }

        var info = makeInfo(outputURL: outputURL)
        for series in updatedSeries {
            info.updatesByYear[year, default: [:]][series] = .now
        }

        print()
        if !updatedSeries.isEmpty {
            let infoData = try JSONEncoder.motorsportCalendar.encode(info)
            let infoURL = outputURL.appending(path: "info.json")
            try infoData.write(to: infoURL)
            print("Calendar updated")
        } else {
            print("Calendar unchanged")
        }
    }

    private func makeInfo(outputURL: URL) -> MotorsportCalendarInfo {
        let infoURL = outputURL.appending(path: "info.json")
        do {
            let infoData = try Data(contentsOf: infoURL)
            return try JSONDecoder.motorsportCalendar.decode(MotorsportCalendarInfo.self, from: infoData)
        } catch {
            let keyValues = Series.allCases.map { ($0, Date.now) }
            let updates = Dictionary(uniqueKeysWithValues: keyValues)
            return MotorsportCalendarInfo(updates: [year: updates])
        }
    }
}
