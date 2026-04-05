import Foundation

struct StageLine: Equatable {
    struct Time: Equatable {
        let hour: Int
        let minute: Int
    }

    let time: Time?
    let title: String
    let isConfirmed: Bool
}

extension StageLine {
    /// Parses a raw stage line from WRC itinerary data.
    ///
    /// Supported formats:
    /// - `15:05: SS1 Águeda / Sever (15.08 km)` — time + title + optional km
    /// - `18:30: Ceremonial Start - Rijeka Korzo`  — time + title
    /// - `Shakedown - Baltar (5.72 km)`            — title only (time is nil)
    ///
    /// All-uppercase alphabetic words in the title are converted to title case
    /// (e.g. `VALLESECO` → `Valleseco`). Words containing digits (e.g. `SS5`) are unchanged.
    static func parse(_ text: String) -> StageLine? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let time: Time?
        let rawTitle: String

        if let match = trimmed.firstMatch(of: /^\s*(?<hour>\d{1,2}):(?<minute>\d{2})(?:\s*:\s*|\s+)(?<title>.+?)\s*$/) {
            guard let hour = Int(match.output.hour), let minute = Int(match.output.minute) else {
                return nil
            }
            time = Time(hour: hour, minute: minute)
            rawTitle = String(match.output.title)
        } else {
            time = nil
            rawTitle = trimmed
        }

        let title = normalizeTitle(rawTitle)
        guard !title.isEmpty else { return nil }

        return StageLine(time: time, title: title, isConfirmed: time != nil)
    }

    private static func normalizeTitle(_ raw: String) -> String {
        raw
            .replacingOccurrences(
                of: #"\s*\(\s*\d+(?:\.\d+)?\s*km\s*\)\s*$"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { titleCasedIfAllCaps($0) }
            .joined(separator: " ")
    }

    /// Title-cases a word only if it is entirely composed of Unicode letters and entirely uppercase.
    /// Words containing digits or mixed case are returned unchanged.
    private static func titleCasedIfAllCaps(_ word: Substring) -> String {
        guard
            word.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }),
            String(word) == String(word).uppercased(),
            word.count > 1
        else {
            return String(word)
        }
        return word.prefix(1).uppercased() + word.dropFirst().lowercased()
    }
}
