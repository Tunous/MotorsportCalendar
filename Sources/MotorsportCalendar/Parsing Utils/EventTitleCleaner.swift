import Foundation

struct EventTitleCleaner {
    let year: Int

    func clean(_ text: String) -> String {
        text
            .applying(removeTrailingYear)
            .applying(removeLeadingSeriesPrefix)
            .trimmingWhitespace()
    }

    private func removeTrailingYear(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+\#(year)$"#, with: "", options: .regularExpression)
    }

    private func removeLeadingSeriesPrefix(_ text: String) -> String {
        text.replacingOccurrences(of: #"^\s*WRC\s+"#, with: "", options: .regularExpression)
    }
}

