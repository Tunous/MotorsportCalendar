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
            .applying(removeDistanceSuffix)
            .trimmingWhitespace()
            .applying(collapseInternalWhitespace)
            .applying(removeLeadingTBCPrefix)
            .applying(titleCaseAllCapsWords)
            .applying(uppercaseStageAbbreviations)
            .applying(collapseSpacedStageNumbers)
            .applying(removeDuplicateLeadingAbbreviations)
    }

    /// Removes a trailing distance annotation such as "(15.08 km)" or "(5 KM)".
    private static func removeDistanceSuffix(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\s*\(\s*\d+(?:\.\d+)?\s*km\s*\)\s*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    /// Collapses any run of multiple spaces into a single space so that source data
    /// with irregular spacing does not produce double spaces in the final title.
    private static func collapseInternalWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
    }

    /// Strips a leading "TBC:" prefix that some unconfirmed stages carry before their actual title
    /// (e.g. `TBC: SS1 Eko SSS` → `SS1 Eko SSS`).
    private static func removeLeadingTBCPrefix(_ text: String) -> String {
        text.replacingOccurrences(of: #"^TBC\s*:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
    }

    /// Converts words that are entirely uppercase alphabetic characters to title case
    /// (e.g. `VALLESECO` → `Valleseco`). Words containing digits (e.g. `SS5`) are left unchanged.
    private static func titleCaseAllCapsWords(_ text: String) -> String {
        text
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { word -> String in
                guard
                    word.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }),
                    String(word) == String(word).uppercased(),
                    word.count > 1
                else {
                    return String(word)
                }
                return word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }

    /// Restores correct uppercase on stage abbreviations (`SS`, `SSS`) followed by a number
    /// that may have been lowered by title-casing (e.g. `Ss3` → `SS3`, `Sss1` → `SSS1`).
    /// Also corrects the standalone `Sss` form that carries no number (e.g. `Sss` → `SSS`).
    private static func uppercaseStageAbbreviations(_ text: String) -> String {
        text
            .replacing(/\b([Ss][Ss][Ss]?)(\d+)\b/) { match in
                String(match.output.1).uppercased() + String(match.output.2)
            }
            .replacingOccurrences(of: #"\bSss\b"#, with: "SSS", options: .regularExpression)
    }

    /// Collapses a spaced-out stage number abbreviation into a compact form
    /// (e.g. `SS 23` → `SS23`, `SSS 4` → `SSS4`).
    private static func collapseSpacedStageNumbers(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\b(SSS?) (\d+)\b"#,
            with: "$1$2",
            options: .regularExpression
        )
    }

    /// Removes a duplicate numbered stage abbreviation at the start of the title when two
    /// consecutive identifiers are present, keeping only the first
    /// (e.g. `SS1 SS2 Stage Name` → `SS1 Stage Name`).
    private static func removeDuplicateLeadingAbbreviations(_ text: String) -> String {
        guard let match = text.firstMatch(of: /^(SSS?\d+)\s+(SSS?\d+)\s+(.+)$/) else {
            return text
        }
        return "\(match.output.1) \(match.output.3)"
    }
}
