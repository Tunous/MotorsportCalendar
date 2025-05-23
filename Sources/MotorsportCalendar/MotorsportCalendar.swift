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
    var formula1CalendarURL: URL

    @Option
    var year: Int = Calendar.current.component(.year, from: .now)

    mutating func run() async throws {
        let outputPath = NSString(string: output).expandingTildeInPath
        let outputURL = URL(filePath: outputPath, directoryHint: .isDirectory)

        let providers: [any CalendarProvider] = [
            Formula1CalendarProvider(outputURL: outputURL, calendarURL: formula1CalendarURL),
            WRCCalendarProvider(outputURL: outputURL),
            WECCalendarProvider(outputURL: outputURL),
        ]

        let updatedSeries = try await withThrowingTaskGroup(of: (Series, Bool).self, returning: Set<Series>.self) { group in
            for provider in providers {
                group.addTask { [year] in
                    do {
                        let didUpdate = try await provider.run(year: year)
                        return (provider.series, didUpdate)
                    } catch {
                        print("[\(provider.series)] Error:", error)
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
            info.updates[series] = .now
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
            return .init(updates: updates)
        }
    }
}
