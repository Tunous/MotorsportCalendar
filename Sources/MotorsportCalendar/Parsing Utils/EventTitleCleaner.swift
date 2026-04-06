import Foundation

struct EventTitleCleaner {
    let year: Int

    func clean(_ text: String) -> String {
        text
            .applying(removeYear)
            .applying(removeLeadingSeriesPrefix)
            .trimmingWhitespace()
            .applying(capitalizeFirstLetter)
    }

    private func removeYear(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+\#(year)\b"#, with: "", options: .regularExpression)
    }

    private func removeLeadingSeriesPrefix(_ text: String) -> String {
        text.replacingOccurrences(of: #"^\s*WRC\s+"#, with: "", options: .regularExpression)
    }

    private func capitalizeFirstLetter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}

