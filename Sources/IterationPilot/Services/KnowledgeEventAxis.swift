import Foundation

enum KnowledgeEventTimingBasis: String {
    case explicitLaunchDate
    case explicitMentionedDate
    case documentCreatedAt
    case documentUpdatedAt
    case knowledgeCreatedAt

    var label: String {
        switch self {
        case .explicitLaunchDate: return "文档内明确上线/发布日期"
        case .explicitMentionedDate: return "文档内提及日期"
        case .documentCreatedAt: return "Confluence 文档创建时间"
        case .documentUpdatedAt: return "Confluence 文档更新时间"
        case .knowledgeCreatedAt: return "知识库创建时间"
        }
    }

    var reliabilityScore: Int {
        switch self {
        case .explicitLaunchDate: return 4
        case .explicitMentionedDate: return 2
        case .documentCreatedAt: return 1
        case .documentUpdatedAt: return 1
        case .knowledgeCreatedAt: return 1
        }
    }

    var caveat: String {
        switch self {
        case .explicitLaunchDate:
            return "可作为产品事件时间线的强证据，但仍需核对实际发布记录。"
        case .explicitMentionedDate:
            return "文档提到该日期，但未确认是实际上线时间。"
        case .documentCreatedAt:
            return "这是 Confluence 需求文档创建时间，不等于实际产品上线或生效时间，只能作为弱时间线索。"
        case .documentUpdatedAt:
            return "这是 Confluence 需求文档修改时间，不等于实际产品上线或生效时间，只能作为弱时间线索。"
        case .knowledgeCreatedAt:
            return "这是知识库条目创建时间，不等于实际事件发生时间；Confluence 条目不会使用这个时间做匹配。"
        }
    }
}

struct KnowledgeEventTiming {
    var date: Date
    var basis: KnowledgeEventTimingBasis

    var label: String {
        "\(DateFormatting.shortDate.string(from: date))（\(basis.label)）"
    }
}

enum KnowledgeEventAxis {
    static func productEvents(from entries: [KnowledgeEntry]) -> [KnowledgeEntry] {
        entries
            .compactMap { entry -> (entry: KnowledgeEntry, timing: KnowledgeEventTiming)? in
                guard isProductEventCandidate(entry),
                      let timing = eventTimingIfAvailable(for: entry) else {
                    return nil
                }
                return (entry, timing)
            }
            .sorted { lhs, rhs in
                lhs.timing.date > rhs.timing.date
            }
            .map(\.entry)
    }

    static func productEventCount(from entries: [KnowledgeEntry]) -> Int {
        entries.reduce(0) { count, entry in
            guard isProductEventCandidate(entry),
                  eventTimingIfAvailable(for: entry) != nil else {
                return count
            }
            return count + 1
        }
    }

    static func eventDate(for entry: KnowledgeEntry) -> Date {
        eventTiming(for: entry).date
    }

    static func eventTiming(for entry: KnowledgeEntry) -> KnowledgeEventTiming {
        eventTimingIfAvailable(for: entry) ?? KnowledgeEventTiming(date: entry.createdAt, basis: .knowledgeCreatedAt)
    }

    static func eventTimingIfAvailable(for entry: KnowledgeEntry) -> KnowledgeEventTiming? {
        let text = [
            entry.scenario,
            entry.problem,
            entry.action,
            entry.result,
            entry.tags.joined(separator: " ")
        ].joined(separator: " ")

        if let explicit = explicitEventTiming(in: text) {
            return explicit
        }
        if let updatedAt = entry.sourceUpdatedAt {
            return KnowledgeEventTiming(date: updatedAt, basis: .documentUpdatedAt)
        }
        if let createdAt = entry.sourceCreatedAt {
            return KnowledgeEventTiming(date: createdAt, basis: .documentCreatedAt)
        }
        if isConfluenceEntry(entry) {
            return nil
        }
        return KnowledgeEventTiming(date: entry.createdAt, basis: .knowledgeCreatedAt)
    }

    static func title(for entry: KnowledgeEntry) -> String {
        entry.problem.nilIfBlank ?? entry.action.nilIfBlank ?? entry.scenario.nilIfBlank ?? "知识库事件"
    }

    static func subtitle(for entry: KnowledgeEntry) -> String {
        let source = entry.sourceURL == nil ? "知识库" : "Confluence"
        return [entry.scenario.nilIfBlank, source].compactMap { $0 }.joined(separator: " · ")
    }

    static func detail(for entry: KnowledgeEntry) -> String {
        [
            entry.action.nilIfBlank,
            entry.result.nilIfBlank,
            entry.sourceURL.flatMap { $0.nilIfBlank }.map { "来源：\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    static func compactContext(for entry: KnowledgeEntry) -> String {
        let timing = eventTiming(for: entry)
        let sourceURL = entry.sourceURL.flatMap { $0.nilIfBlank }
        let parts = [
            "\(timing.label) [\(entry.scenario)] \(title(for: entry))",
            entry.action.nilIfBlank.map { "动作：\($0)" },
            entry.result.nilIfBlank.map { "说明：\($0)" },
            timing.basis == .explicitLaunchDate ? nil : "时间说明：\(timing.basis.caveat)",
            sourceURL.map { "来源：\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: "；")
        return parts.count > 800 ? String(parts.prefix(800)) : parts
    }

    private static func isProductEventCandidate(_ entry: KnowledgeEntry) -> Bool {
        if entry.sourceID?.hasPrefix("correction-") == true { return false }
        let text = [
            entry.scenario,
            entry.problem,
            entry.action,
            entry.result,
            entry.relatedPackName,
            entry.tags.joined(separator: " ")
        ]
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let normalized = text.normalizedKey
        if normalized.contains("人工纠偏") || normalized.contains("归因修正") {
            return false
        }
        if normalized.contains("报表知识") || normalized.contains("ai问答沉淀") {
            return false
        }
        let analysisArtifactMarkers = [
            "本轮没有检测到显著指标波动",
            "当前分析摘要",
            "产品迭代决策_memo",
            "产品迭代决策memo",
            "归因结论",
            "候选机会",
            "ai_分析",
            "ai分析",
            "纠偏记忆"
        ]
        if analysisArtifactMarkers.contains(where: { normalized.contains($0.normalizedKey) }) {
            return false
        }
        return true
    }

    private static func isConfluenceEntry(_ entry: KnowledgeEntry) -> Bool {
        entry.relatedPackName.normalizedKey.contains("confluence") ||
            entry.sourceURL?.normalizedKey.contains("confluence") == true
    }

    private static func explicitEventTiming(in text: String) -> KnowledgeEventTiming? {
        let nsText = text as NSString

        let matches = explicitDateRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var mentionedDate: Date?
        for match in matches {
            let raw = nsText.substring(with: match.range)
            guard let date = parseChineseDate(raw) else { continue }
            let contextRange = NSRange(
                location: max(0, match.range.location - 24),
                length: min(nsText.length - max(0, match.range.location - 24), match.range.length + 48)
            )
            let context = nsText.substring(with: contextRange).normalizedKey
            if launchKeywords.contains(where: { context.contains($0.normalizedKey) }) {
                return KnowledgeEventTiming(date: date, basis: .explicitLaunchDate)
            }
            if mentionedDate == nil {
                mentionedDate = date
            }
        }
        return mentionedDate.map { KnowledgeEventTiming(date: $0, basis: .explicitMentionedDate) }
    }

    private static func parseChineseDate(_ raw: String) -> Date? {
        let normalized = raw
            .replacingOccurrences(of: "年", with: "/")
            .replacingOccurrences(of: "月", with: "/")
            .replacingOccurrences(of: "日", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "/")
        return DateParsing.parse(normalized)
    }

    private static let launchKeywords = [
        "上线", "发布", "发版", "投产", "生效", "灰度", "全量", "release", "launch", "go_live", "rollout", "ship"
    ]

    private static let explicitDateRegexPattern =
        #"\d{4}\s*(?:年|[-/.])\s*\d{1,2}\s*(?:月|[-/.])\s*\d{1,2}\s*日?"#

    private static let explicitDateRegex: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(pattern: explicitDateRegexPattern) else {
            preconditionFailure("Invalid static regex pattern: \(explicitDateRegexPattern)")
        }
        return regex
    }()
}
