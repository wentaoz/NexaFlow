import CryptoKit
import Foundation

struct ReferenceFingerprints {
    var normalizedURL: String
    var domain: String
    var urlHash: String
    var titleHash: String
    var contentHash: String
}

enum ReferenceDedupeService {
    static func enriched(_ item: ExternalReferenceItem, source: ExternalReferenceSource?) -> ExternalReferenceItem {
        var copy = item
        let fingerprints = fingerprints(for: item, source: source)
        copy.normalizedURL = fingerprints.normalizedURL
        copy.urlHash = fingerprints.urlHash
        copy.titleHash = fingerprints.titleHash
        copy.contentHash = fingerprints.contentHash
        return copy
    }

    static func fingerprints(for item: ExternalReferenceItem, source: ExternalReferenceSource?) -> ReferenceFingerprints {
        let normalizedURL = normalizeURL(item.url)
        let domain = domain(from: normalizedURL)
        let compactTitle = normalizeText(item.title)
        let compactContent = normalizeText(clipped(item.rawContent.nilIfBlank ?? item.summary, to: 4_000))
        let competitorKey = (source?.competitorName.nilIfBlank ?? item.sourceName).lowercased()

        return ReferenceFingerprints(
            normalizedURL: normalizedURL,
            domain: domain,
            urlHash: sha256(normalizedURL),
            titleHash: sha256("\(competitorKey)|\(domain)|\(compactTitle)"),
            contentHash: sha256("\(competitorKey)|\(compactContent)")
        )
    }

    static func isDuplicate(_ item: ExternalReferenceItem, against existing: [ExternalReferenceItem]) -> Bool {
        existing.contains { candidate in
            if !item.urlHash.isEmpty && item.urlHash == candidate.urlHash { return true }
            if !item.titleHash.isEmpty && item.titleHash == candidate.titleHash { return true }
            if !item.contentHash.isEmpty && item.contentHash == candidate.contentHash { return true }
            if !item.normalizedURL.isEmpty && item.normalizedURL == candidate.normalizedURL { return true }
            return isSimilarTitle(item.title, candidate.title)
        }
    }

    static func isSimilarTitle(_ lhs: String, _ rhs: String, threshold: Double = 0.72) -> Bool {
        similarity(lhs, rhs) >= threshold
    }

    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let left = Set(tokens(lhs))
        let right = Set(tokens(rhs))
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        return Double(left.intersection(right).count) / Double(left.union(right).count)
    }

    private static func tokens(_ value: String) -> [String] {
        normalizeText(value)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
    }

    private static func normalizeURL(_ value: String) -> String {
        guard var components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return value.lowercased()
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        let trackingPrefixes = ["utm_", "fbclid", "gclid", "yclid"]
        components.queryItems = components.queryItems?
            .filter { item in
                let name = item.name.lowercased()
                return !trackingPrefixes.contains { name.hasPrefix($0) }
            }
            .sorted { $0.name < $1.name }
        return components.string?.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased() ?? value.lowercased()
    }

    private static func domain(from url: String) -> String {
        URL(string: url).flatMap(\.host) ?? ""
    }

    private static func normalizeText(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func clipped(_ value: String, to limit: Int) -> String {
        value.count > limit ? String(value.prefix(limit)) : value
    }
}
