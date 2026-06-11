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

extension Task where Success == Never, Failure == Never {
    static func retry<T>(
        maxAttempts: Int = 3,
        onRetry: ((Int, any Error) -> Void)? = nil,
        operation: () async throws -> T
    ) async throws -> T {
        precondition(maxAttempts > 0)

        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                guard attempt < maxAttempts else { throw error }
                onRetry?(attempt, error)
                try await Task.sleep(for: .seconds(attempt))
            }
        }

        fatalError("Unreachable")
    }
}
