import Foundation

public enum StableIdentifier {
    public static func event(_ value: String, series: Series) -> String {
        normalizedSlug(value)
    }

    public static func session(_ value: String, series: Series) -> String {
        switch series {
        case .wrc:
            wrcSessionIdentifier(value)
        case .formula1, .wec:
            iCalendarSessionIdentifier(value)
        }
    }

    public static func isNormalized(_ value: String) -> Bool {
        !value.isEmpty && normalizedSlug(value) == value
    }

    private static func wrcSessionIdentifier(_ value: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = value.firstMatch(of: /\b(SSS?)\s*(\d+)\b/.ignoresCase()) {
            return "\(match.1.lowercased())\(match.2)"
        }

        let lowercasedValue = value.lowercased()
        let qualifiedPrefixes = ["flexi service", "remote service", "service", "tyre fitting zone"]
        for prefix in qualifiedPrefixes where lowercasedValue.hasPrefix(prefix) {
            let remainder = lowercasedValue.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            let qualifier = remainder.prefix { $0.isLetter || $0.isNumber }
            if !qualifier.isEmpty && (qualifier.count == 1 || qualifier.allSatisfy(\.isNumber)) {
                return normalizedSlug("\(prefix) \(qualifier)")
            }
            return normalizedSlug(prefix)
        }

        let semanticPrefixes = [
            "ceremonial start",
            "shakedown",
            "wolf power stage",
            "parc fermé",
            "podium",
            "finish",
            "regroup",
            "start",
            "sss",
        ]
        for prefix in semanticPrefixes where startsWithSemanticPrefix(lowercasedValue, prefix: prefix) {
            return normalizedSlug(prefix)
        }

        return normalizedSlug(value)
    }

    private static func iCalendarSessionIdentifier(_ value: String) -> String {
        let identifier = normalizedSlug(value)
        let components = identifier.split(separator: "-").map(String.init)

        if let practiceNumber = practiceNumber(in: components) {
            return (["practice", practiceNumber] + classDiscriminators(in: components))
                .joined(separator: "-")
        }
        if components.contains("sprint") && components.contains(where: { ["qualification", "qualifying", "shootout"].contains($0) }) {
            return "sprint-qualification"
        }
        if components.contains("sprint") {
            return "sprint-race"
        }
        if components.contains("hyperpole") {
            return semanticIdentifier("hyperpole", components: components)
        }
        if components.contains(where: { ["qualification", "qualifying"].contains($0) }) {
            return semanticIdentifier("qualifying", components: components)
        }
        if components.contains("race") {
            return "race"
        }
        if components.contains("warm") && components.contains("up") {
            return "warm-up"
        }

        return identifier
    }

    private static func practiceNumber(in components: [String]) -> String? {
        let numberWords = [
            "one": "1", "first": "1",
            "two": "2", "second": "2",
            "three": "3", "third": "3",
            "four": "4", "fourth": "4",
        ]
        for (index, component) in components.enumerated() {
            if component.hasPrefix("fp"), let number = component.last, number.isNumber {
                return String(number)
            }
            guard component == "practice" else { continue }
            for suffix in components.dropFirst(index + 1) {
                if suffix.allSatisfy(\.isNumber) {
                    return suffix
                }
                if let number = numberWords[suffix] {
                    return number
                }
            }
        }
        for (word, number) in numberWords where components.contains(word) && components.contains("practice") {
            return number
        }
        return nil
    }

    private static func semanticIdentifier(_ semantic: String, components: [String]) -> String {
        let discriminators = components.filter { $0.allSatisfy(\.isNumber) }
            + classDiscriminators(in: components)
        return ([semantic] + discriminators).joined(separator: "-")
    }

    private static func classDiscriminators(in components: [String]) -> [String] {
        let knownClasses = Set(["hypercar", "lmp1", "lmp2", "lmgt3", "gte", "pro", "am"])
        return components.filter(knownClasses.contains)
    }

    private static func startsWithSemanticPrefix(_ value: String, prefix: String) -> Bool {
        value == prefix || value.hasPrefix(prefix + " ") || value.hasPrefix(prefix + ",")
    }

    private static func normalizedSlug(_ value: String) -> String {
        let locale = Locale(identifier: "en_US_POSIX")
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: locale
        ).lowercased(with: locale)
        var result = ""
        var needsSeparator = false

        for scalar in folded.unicodeScalars {
            let isLowercaseLetter = scalar.isASCII && CharacterSet.lowercaseLetters.contains(scalar)
            let isDigit = scalar.isASCII && CharacterSet.decimalDigits.contains(scalar)
            if isLowercaseLetter || isDigit {
                if needsSeparator && !result.isEmpty {
                    result.append("-")
                }
                result.unicodeScalars.append(scalar)
                needsSeparator = false
            } else {
                needsSeparator = true
            }
        }
        return result
    }
}
