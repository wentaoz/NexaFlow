import Foundation

enum AnalysisOutputTextFormatter {
    private static let signedDecimalPattern = #"[+\-−－﹣]?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?"#

    static func normalizedPercentages(in text: String) -> String {
        let withPointRanges = replaceMatches(
            in: text,
            pattern: #"(\#(signedDecimalPattern))(\s*(?:~|～|至|到|-|–|—)\s*)(\#(signedDecimalPattern))(\s*个百分点)"#
        ) { match, source in
            guard match.numberOfRanges == 5,
                  let lower = formattedNumber(source.substring(with: match.range(at: 1))),
                  let upper = formattedNumber(source.substring(with: match.range(at: 3))) else {
                return nil
            }
            let separator = source.substring(with: match.range(at: 2))
            let suffix = source.substring(with: match.range(at: 4))
            return "\(lower)\(separator)\(upper)\(suffix)"
        }

        let withSinglePoints = replaceMatches(
            in: withPointRanges,
            pattern: #"(\#(signedDecimalPattern))(\s*个百分点)"#
        ) { match, source in
            guard match.numberOfRanges == 3,
                  let value = formattedNumber(source.substring(with: match.range(at: 1))) else {
                return nil
            }
            return "\(value)\(source.substring(with: match.range(at: 2)))"
        }

        return replaceMatches(
            in: withSinglePoints,
            pattern: #"(\#(signedDecimalPattern))\s*[%％]"#
        ) { match, source in
            guard match.numberOfRanges == 2,
                  let value = formattedNumber(source.substring(with: match.range(at: 1))) else {
                return nil
            }
            return "\(value)%"
        }
    }

    private static func replaceMatches(
        in text: String,
        pattern: String,
        transform: (NSTextCheckingResult, NSString) -> String?
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let source = text as NSString
        var result = text
        let fullRange = NSRange(location: 0, length: source.length)
        for match in regex.matches(in: text, range: fullRange).reversed() {
            guard let replacement = transform(match, source),
                  let range = Range(match.range, in: result) else {
                continue
            }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    private static func formattedNumber(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "﹣", with: "-")
        guard let value = Double(normalized) else { return nil }
        let formatted = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
        if trimmed.hasPrefix("+"), !formatted.hasPrefix("-") {
            return "+\(formatted)"
        }
        return formatted
    }
}
