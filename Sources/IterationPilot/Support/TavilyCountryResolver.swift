import Foundation

enum TavilyCountryResolver {
    struct Decision: Hashable {
        var original: String
        var normalizedCountry: String?
        var queryAliases: [String]
        var shouldSendCountry: Bool
        var reason: String

        var sentCountry: String? {
            shouldSendCountry ? normalizedCountry : nil
        }
    }

    static func decision(country rawCountry: String, topic rawTopic: String) -> Decision {
        let original = rawCountry.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTopic = rawTopic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalized = normalizeCountry(original)

        let aliases = aliases(for: normalized, original: original)
        guard let normalized else {
            return Decision(
                original: original,
                normalizedCountry: nil,
                queryAliases: aliases,
                shouldSendCountry: false,
                reason: original.isEmpty ? "未配置 country" : "country 无法规范化，已仅作为 query 语义使用"
            )
        }

        guard normalizedTopic.isEmpty || normalizedTopic == "general" else {
            return Decision(
                original: original,
                normalizedCountry: normalized,
                queryAliases: aliases,
                shouldSendCountry: false,
                reason: "Tavily \(normalizedTopic) topic 不发送 country 参数，国家信息写入 query"
            )
        }

        return Decision(
            original: original,
            normalizedCountry: normalized,
            queryAliases: aliases,
            shouldSendCountry: true,
            reason: "Tavily general topic 使用规范化 country 参数"
        )
    }

    static func normalizedSource(_ source: ExternalReferenceSource) -> ExternalReferenceSource {
        var copy = source
        let decision = decision(country: source.tavilyCountry, topic: source.tavilyTopic)
        if let normalized = decision.normalizedCountry {
            copy.tavilyCountry = normalized
        }
        if source.collectorType == .tavilySearch, !decision.queryAliases.isEmpty {
            let queryText = copy.queryTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            let keywordText = copy.keywordsText.trimmingCharacters(in: .whitespacesAndNewlines)
            let aliases = decision.queryAliases.filter { alias in
                !queryText.localizedCaseInsensitiveContains(alias) &&
                    !keywordText.localizedCaseInsensitiveContains(alias)
            }
            if !aliases.isEmpty {
                let joined = aliases.joined(separator: ", ")
                copy.keywordsText = keywordText.isEmpty ? joined : "\(keywordText), \(joined)"
            }
        }
        return copy
    }

    private static func normalizeCountry(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let key = value.normalizedKey
        if key.contains("mexico") || key.contains("méxico") || value.contains("墨西哥") || key == "mx" {
            return "mexico"
        }
        if key.contains("philippines") || value.contains("菲律宾") || key == "ph" {
            return "philippines"
        }
        if key.contains("colombia") || value.contains("哥伦比亚") || key == "co" {
            return "colombia"
        }
        if key.contains("peru") || value.contains("秘鲁") || key == "pe" {
            return "peru"
        }
        if key.contains("chile") || value.contains("智利") || key == "cl" {
            return "chile"
        }
        return nil
    }

    private static func aliases(for normalized: String?, original: String) -> [String] {
        switch normalized {
        case "mexico":
            return ["Mexico", "México", "MX", "墨西哥"]
        case "philippines":
            return ["Philippines", "PH", "菲律宾"]
        case "colombia":
            return ["Colombia", "CO", "哥伦比亚"]
        case "peru":
            return ["Peru", "PE", "秘鲁"]
        case "chile":
            return ["Chile", "CL", "智利"]
        default:
            return original.isEmpty ? [] : [original]
        }
    }
}
