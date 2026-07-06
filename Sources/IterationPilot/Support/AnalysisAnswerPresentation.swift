import Foundation

struct AnalysisAnswerPresentation: Hashable {
    var answerMarkdown: String
    var supportingSections: [AnalysisAnswerSupportingSection]
    var rawMarkdown: String

    private static let parseCache = AnalysisAnswerPresentationCache()

    var hasSupportingSections: Bool {
        !supportingSections.isEmpty
    }

    var supportSummaryText: String {
        let labels = supportingSections.map(\.summaryLabel).uniqued()
        guard !labels.isEmpty else {
            return "依据详情待核对"
        }
        return "依据：\(labels.joined(separator: " · "))"
    }

    static func parse(_ markdown: String) -> AnalysisAnswerPresentation? {
        let normalizedMarkdown = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMarkdown.isEmpty else { return nil }
        if let cached = parseCache.value(for: normalizedMarkdown) {
            return cached
        }

        let parsed = PerformanceTrace.measure(
            "analysisAnswer.parse",
            metadata: "chars=\(normalizedMarkdown.utf8.count)"
        ) {
            splitSections(in: normalizedMarkdown)
        }
        guard let answerIndex = parsed.firstIndex(where: { section in
            section.kind == .directAnswer
        }) else {
            return nil
        }

        let answer = parsed[answerIndex].body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return nil }

        let supporting = parsed.enumerated().compactMap { index, section -> AnalysisAnswerSupportingSection? in
            guard index != answerIndex else { return nil }
            let body = section.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
            return AnalysisAnswerSupportingSection(
                kind: section.kind.supportingKind,
                title: section.title,
                bodyMarkdown: body
            )
        }

        let presentation = AnalysisAnswerPresentation(
            answerMarkdown: answer,
            supportingSections: supporting,
            rawMarkdown: normalizedMarkdown
        )
        parseCache.set(presentation, for: normalizedMarkdown)
        return presentation
    }

    private static func splitSections(in markdown: String) -> [ParsedSection] {
        let lines = markdown.components(separatedBy: .newlines)
        var sections: [ParsedSection] = []
        var currentTitle: String?
        var currentKind: ParsedSectionKind = .preamble
        var currentLines: [String] = []

        func flush() {
            guard currentTitle != nil || !currentLines.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                currentLines.removeAll(keepingCapacity: true)
                return
            }
            let title = currentTitle ?? "其它说明"
            sections.append(ParsedSection(
                title: title,
                kind: currentKind,
                body: currentLines.joined(separator: "\n")
            ))
            currentLines.removeAll(keepingCapacity: true)
        }

        for line in lines {
            if let heading = parseHeading(line) {
                flush()
                currentTitle = heading
                currentKind = ParsedSectionKind(title: heading)
            } else {
                currentLines.append(line)
            }
        }
        flush()
        return sections
    }

    private static func parseHeading(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("##") else { return nil }
        guard !trimmed.hasPrefix("###") else { return nil }
        return trimmed
            .drop(while: { $0 == "#" || $0 == " " })
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
    }
}

private final class AnalysisAnswerPresentationCache {
    private final class Box {
        let value: AnalysisAnswerPresentation

        init(_ value: AnalysisAnswerPresentation) {
            self.value = value
        }
    }

    private let cache = NSCache<NSString, Box>()

    init() {
        cache.countLimit = 64
        cache.totalCostLimit = 600_000
    }

    func value(for markdown: String) -> AnalysisAnswerPresentation? {
        cache.object(forKey: markdown as NSString)?.value
    }

    func set(_ value: AnalysisAnswerPresentation, for markdown: String) {
        cache.setObject(Box(value), forKey: markdown as NSString, cost: markdown.count)
    }
}

struct AnalysisAnswerSupportingSection: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case localFacts
        case calculationEvidence
        case materialEvidence
        case readScope
        case limitations
        case other
    }

    var id: String { "\(kind.rawValue):\(title)" }
    var kind: Kind
    var title: String
    var bodyMarkdown: String

    var markdownWithHeading: String {
        "## \(title)\n\(bodyMarkdown)"
    }

    var summaryLabel: String {
        switch kind {
        case .localFacts:
            return "本地校验"
        case .calculationEvidence:
            return "口径/计算"
        case .materialEvidence:
            return "资料证据"
        case .readScope:
            return "读取范围"
        case .limitations:
            return "限制"
        case .other:
            return title
        }
    }

    var systemImage: String {
        switch kind {
        case .localFacts:
            return "checklist.checked"
        case .calculationEvidence:
            return "function"
        case .materialEvidence:
            return "doc.text.magnifyingglass"
        case .readScope:
            return "tablecells"
        case .limitations:
            return "exclamationmark.triangle"
        case .other:
            return "text.alignleft"
        }
    }
}

private struct ParsedSection: Hashable {
    var title: String
    var kind: ParsedSectionKind
    var body: String
}

private enum ParsedSectionKind: Hashable {
    case preamble
    case directAnswer
    case localFacts
    case calculationEvidence
    case materialEvidence
    case readScope
    case limitations
    case other

    init(title: String) {
        let normalized = title
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "：", with: ":")
            .lowercased()
        let directAnswerSynonyms = [
            "直接回答你的问题",
            "直接回答",
            "直接结论",
            "核心结论",
            "核心判断",
            "结论",
            "回答",
            "结论摘要"
        ]
        if directAnswerSynonyms.contains(where: { normalized == $0 }) {
            self = .directAnswer
        } else if normalized.contains("本地已校验事实") || normalized.contains("已校验事实") {
            self = .localFacts
        } else if normalized.contains("关键数据证据") || normalized.contains("计算口径") || normalized.contains("计算证据") {
            self = .calculationEvidence
        } else if normalized.contains("资料证据") {
            self = .materialEvidence
        } else if normalized.contains("ai读取到的数据") || normalized.contains("读取到的数据") || normalized.contains("读取范围") {
            self = .readScope
        } else if normalized.contains("未覆盖") || normalized.contains("需补数据") || normalized.contains("限制") || normalized.contains("缺口") {
            self = .limitations
        } else {
            self = .other
        }
    }

    var supportingKind: AnalysisAnswerSupportingSection.Kind {
        switch self {
        case .localFacts:
            return .localFacts
        case .calculationEvidence:
            return .calculationEvidence
        case .materialEvidence:
            return .materialEvidence
        case .readScope:
            return .readScope
        case .limitations:
            return .limitations
        case .preamble, .directAnswer, .other:
            return .other
        }
    }
}
