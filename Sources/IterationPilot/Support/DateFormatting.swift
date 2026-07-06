import Foundation

enum DateFormatting {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    static let percent: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    static let decimal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

enum DateParsing {
    static func parse(_ rawValue: String) -> Date? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let date = DateParsingCache.iso.date(from: value) { return date }
        if let date = DateParsingCache.fractionalISO.date(from: value) { return date }

        for pattern in DateParsingCache.patterns {
            let formatter = DateParsingCache.dateFormatter(for: pattern)
            if let date = formatter.date(from: value) { return date }
        }

        return nil
    }

    static func periodRange(_ rawValue: String) -> (start: Date, end: Date)? {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "~", with: "-")
            .replacingOccurrences(of: "至", with: "-")
            .replacingOccurrences(of: "到", with: "-")
            .replacingOccurrences(of: "年", with: "/")
            .replacingOccurrences(of: "月", with: "/")
            .replacingOccurrences(of: "日", with: "")
        guard let match = DateParsingCache.periodRangeRegex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)),
              let startRange = Range(match.range(at: 1), in: normalized),
              let endRange = Range(match.range(at: 2), in: normalized) else {
            if let monthDayMatch = DateParsingCache.monthDayRangeRegex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)),
               let startRange = Range(monthDayMatch.range(at: 1), in: normalized),
               let endRange = Range(monthDayMatch.range(at: 2), in: normalized) {
                let currentYear = Calendar.current.component(.year, from: Date())
                let startText = String(normalized[startRange]).replacingOccurrences(of: "-", with: "/")
                let endText = String(normalized[endRange]).replacingOccurrences(of: "-", with: "/")
                let startParts = startText.split(separator: "/").compactMap { Int($0) }
                let endParts = endText.split(separator: "/").compactMap { Int($0) }
                if startParts.count == 2, endParts.count == 2 {
                    let endYear = endParts[0] < startParts[0] ? currentYear + 1 : currentYear
                    if let start = parse("\(currentYear)/\(startText)"),
                       let end = parse("\(endYear)/\(endText)") {
                        return start <= end ? (start, end) : (end, start)
                    }
                }
            }
            if let single = parse(rawValue) {
                return (single, single)
            }
            return nil
        }
        let startText = String(normalized[startRange])
        var endText = String(normalized[endRange])
        if endText.filter({ $0 == "/" || $0 == "-" }).count == 1,
           let year = startText.split(whereSeparator: { $0 == "/" || $0 == "-" }).first {
            endText = "\(year)/\(endText)"
        }
        guard let start = parse(startText), let end = parse(endText) else { return nil }
        return start <= end ? (start, end) : (end, start)
    }
}

private enum DateParsingCache {
    static let patterns = [
        "yyyy-MM-dd",
        "yyyy-M-d",
        "yyyy/MM/dd",
        "yyyy/M/d",
        "yyyy.M.d",
        "MM/dd/yyyy",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy/MM/dd HH:mm:ss",
        "EEE, d MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "d MMM yyyy",
        "dd MMM yyyy"
    ]

    private static let periodRangeRegexPattern =
        #"(\d{4}[/-]\d{1,2}[/-]\d{1,2})\s*-\s*((?:\d{4}[/-])?\d{1,2}[/-]\d{1,2})"#

    static let periodRangeRegex: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(pattern: periodRangeRegexPattern) else {
            preconditionFailure("Invalid static regex pattern: \(periodRangeRegexPattern)")
        }
        return regex
    }()

    private static let monthDayRangeRegexPattern =
        #"(\d{1,2}[/-]\d{1,2})\s*-\s*(\d{1,2}[/-]\d{1,2})"#

    static let monthDayRangeRegex: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(pattern: monthDayRangeRegexPattern) else {
            preconditionFailure("Invalid static regex pattern: \(monthDayRangeRegexPattern)")
        }
        return regex
    }()

    static var iso: ISO8601DateFormatter {
        threadCachedFormatter(key: "DateParsingCache.iso") {
            ISO8601DateFormatter()
        }
    }

    static var fractionalISO: ISO8601DateFormatter {
        threadCachedFormatter(key: "DateParsingCache.fractionalISO") {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }
    }

    static func dateFormatter(for pattern: String) -> DateFormatter {
        threadCachedFormatter(key: "DateParsingCache.date.\(pattern)") {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = pattern
            return formatter
        }
    }

    private static func threadCachedFormatter<T: AnyObject>(key: String, create: () -> T) -> T {
        let dictionary = Thread.current.threadDictionary
        if let formatter = dictionary[key] as? T {
            return formatter
        }
        let formatter = create()
        dictionary[key] = formatter
        return formatter
    }
}

extension Double {
    var compactText: String {
        DateFormatting.decimal.string(from: NSNumber(value: self)) ?? String(format: "%.2f", self)
    }
}

extension String {
    var normalizedKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
