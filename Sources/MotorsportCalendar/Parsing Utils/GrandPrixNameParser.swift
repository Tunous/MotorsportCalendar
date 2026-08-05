import Foundation

/// Parses Formula 1 event names from calendar summaries and locations.
///
/// The calendar can prefix the actual event name with a sponsor, for example:
/// `FORMULA 1 GULF AIR BAHRAIN GRAND PRIX IN MALAYSIA 2026 - Qualifying`.
struct GrandPrixNameParser {
    /// Parses the Formula 1 event name for an iCalendar summary and location.
    static func parse(summary: String, location: String) -> String {
        if let qualifiedName = qualifiedName(summary: summary, location: location) {
            return qualifiedName
        }

        let namePrefix: String
        switch location.lowercased() {
        case "saudi arabia":
            namePrefix = "Saudi Arabian"
        case "australia":
            namePrefix = "Australian"
        case "japan":
            namePrefix = "Japanese"
        case "china":
            namePrefix = "Chinese"
        case "united states":
            if summary.localizedStandardContains("miami") {
                namePrefix = "Miami"
            } else if summary.localizedStandardContains("las vegas") {
                namePrefix = "Las Vegas"
            } else {
                namePrefix = "United States"
            }
        case "italy":
            namePrefix = summary.localizedStandardContains("romagna") ? "Emilia Romagna" : "Italian"
        case "canada":
            namePrefix = "Canadian"
        case "spain":
            namePrefix = summary.localizedStandardContains("barcelona") ? "Barcelona-Catalunya" : "Spanish"
        case "austria":
            namePrefix = "Austrian"
        case "united kingdom":
            namePrefix = "British"
        case "hungary":
            namePrefix = "Hungarian"
        case "belgium":
            namePrefix = "Belgian"
        case "netherlands":
            namePrefix = "Dutch"
        case "mexico":
            namePrefix = "Mexico City"
        case "brazil":
            namePrefix = "São Paulo"
        case "united arab emirates":
            namePrefix = "Abu Dhabi"
        default:
            if summary.localizedCaseInsensitiveContains("pre-season testing") {
                return preSeasonTestingName
            }
            namePrefix = location
        }
        return "\(namePrefix) Grand Prix"
    }

    private static func qualifiedName(summary: String, location: String) -> String? {
        let marker = " Grand Prix in \(location)"
        guard let markerRange = summary.range(of: marker, options: .caseInsensitive) else {
            return nil
        }

        let textBeforeMarker = String(summary[..<markerRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name = knownNames.first(where: { textBeforeMarker.hasSuffixIgnoringCase(" \($0)") }) else {
            return nil
        }
        return "\(name) Grand Prix in \(location)"
    }

    private static let knownNames = [
        "Barcelona-Catalunya",
        "Emilia Romagna",
        "Saudi Arabian",
        "United States",
        "Las Vegas",
        "Mexico City",
        "Abu Dhabi",
        "São Paulo",
        "Australian",
        "Japanese",
        "Chinese",
        "Bahrain",
        "Miami",
        "Canadian",
        "Austrian",
        "British",
        "Hungarian",
        "Belgian",
        "Dutch",
        "Spanish",
        "Italian",
    ]
}

private extension String {
    func hasSuffixIgnoringCase(_ suffix: String) -> Bool {
        lowercased().hasSuffix(suffix.lowercased())
    }
}
