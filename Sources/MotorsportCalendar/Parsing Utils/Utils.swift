import Foundation

extension String {
    func applying(_ transform: (String) -> String) -> String {
        transform(self)
    }

    func trimmingWhitespace() -> String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Calendar {
    static var gmt: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = .gmt
        return calendar
    }
}
