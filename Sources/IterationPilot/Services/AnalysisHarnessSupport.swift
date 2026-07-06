import Foundation

enum HarnessValueParser {
    static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dateFormatters: [DateFormatter] = {
        ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy-MM-dd HH:mm:ss", "MM/dd/yyyy", "yyyy.MM.dd"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter
        }
    }()

    static func number(from raw: String) -> Double? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var multiplier = 1.0
        if text.hasSuffix("%") {
            text.removeLast()
            multiplier = 1
        }
        text = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "MXN", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(text).map { $0 * multiplier }
    }

    static func date(from raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let date = dateFormatters.lazy.compactMap({ $0.date(from: text) }).first {
            return date
        }
        let weekPattern = #"(\d{4})[-/](\d{1,2})[-/](\d{1,2})"#
        if let match = text.range(of: weekPattern, options: .regularExpression) {
            return dateFormatters.lazy.compactMap { $0.date(from: String(text[match])) }.first
        }
        return nil
    }

    static func matches(_ raw: String, filter: HarnessFilterDefinition) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch filter.op {
        case .equals:
            return text.normalizedKey == filter.value.normalizedKey
        case .notEquals:
            return text.normalizedKey != filter.value.normalizedKey
        case .contains:
            return text.normalizedKey.contains(filter.value.normalizedKey)
        case .inList:
            return Set(filter.values.map(\.normalizedKey)).contains(text.normalizedKey)
        case .greaterThan, .greaterThanOrEqual, .lessThan, .lessThanOrEqual, .between:
            guard let lhs = number(from: text) else { return false }
            let rhs = number(from: filter.value) ?? 0
            switch filter.op {
            case .greaterThan: return lhs > rhs
            case .greaterThanOrEqual: return lhs >= rhs
            case .lessThan: return lhs < rhs
            case .lessThanOrEqual: return lhs <= rhs
            case .between:
                let bounds = filter.values.compactMap { number(from: $0) }
                guard bounds.count >= 2 else { return false }
                return lhs >= min(bounds[0], bounds[1]) && lhs <= max(bounds[0], bounds[1])
            default:
                return false
            }
        }
    }

    static func compactNumber(_ value: Double, maximumFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func suspiciousReportNumbers(in report: String) -> [String] {
        let pattern = #"(?<![A-Za-z])[-+]?\d{1,3}(?:,\d{3})+(?:\.\d+)?%?|[-+]?\d+\.\d+%"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(report.startIndex..<report.endIndex, in: report)
        return regex.matches(in: report, range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: report) else { return nil }
            return String(report[range])
        }
    }
}

enum HarnessJSONExtractor {
    static func extractJSONObject(from text: String) -> String {
        if let fenced = text.range(of: #"```(?:json)?\s*([\s\S]*?)```"#, options: .regularExpression) {
            let fencedText = String(text[fenced])
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if fencedText.hasPrefix("{") { return fencedText }
        }
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return text
        }
        return String(text[start...end])
    }
}

extension ImportedReport {
    var harnessRows: [[String: String]] {
        if !storedDataRows.isEmpty { return storedDataRows }
        if !sampleRows.isEmpty { return sampleRows }
        guard !rawRows.isEmpty, !headers.isEmpty else { return [] }
        return rawRows.map { row in
            Dictionary(uniqueKeysWithValues: headers.enumerated().map { index, header in
                (header, index < row.count ? row[index] : "")
            })
        }
    }
}

extension JSONEncoder {
    static var harnessEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var harnessDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
