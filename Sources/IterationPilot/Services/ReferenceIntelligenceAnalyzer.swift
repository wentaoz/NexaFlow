import Foundation

struct ReferenceIntelligenceAnalysis {
    var category: ExternalReferenceIntelligenceCategory
    var summary: String
    var impact: String
    var importance: Int
    var isRelevant: Bool
    var relevanceReason: String
    var eventStartedAt: Date?
    var eventEndedAt: Date?
    var dateBasis: ExternalReferenceDateBasis?
    var dateConfidence: Double?
    var warning: String?
}

struct ReferenceIntelligenceAnalyzer {
    private let client = AIAnalysisService()

    func analyze(
        item: ExternalReferenceItem,
        source: ExternalReferenceSource?,
        settings: AISettings
    ) async -> ReferenceIntelligenceAnalysis {
        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback(item: item, reason: nil)
        }

        var scopedSettings = settings
        scopedSettings.systemPrompt = systemPrompt

        do {
            let response = try await client.runAnalysis(
                prompt: userPrompt(item: item, source: source),
                settings: scopedSettings,
                timeout: NetworkTimeouts.referenceIntelligenceRequest
            )
            return try parse(response, fallbackItem: item)
        } catch {
            return fallback(item: item, reason: error.localizedDescription)
        }
    }

    private var systemPrompt: String {
        """
        你是严谨的竞品/政策/市场情报分析助手。只依据输入内容分析，不要编造。
        \(FinancialPromptPolicy.coreSystemPrompt)
        \(FinancialPromptPolicy.externalEvidenceRules)
        你必须输出 JSON 对象，字段：
        - is_relevant: boolean，只有内容明确与目标竞品、目标市场、政策监管、市场变化或产品决策相关时才为 true
        - relevance_reason: 中文，说明为什么相关或为什么不相关
        - category: product/pricing/marketing/customer/funding/hiring/partnership/risk/technology/policy/market/weather/disaster/energy/holiday/traffic/publicSafety/localEconomy/other
        - summary: 中文，1-3 句话概括事实
        - impact: 中文，说明对我方产品迭代、AI 分析或风险判断的可能影响
        - importance: 1 到 5 的整数
        - event_started_at: 字符串，可解析为 yyyy-MM-dd 或 ISO8601；只有正文明确写出事件真实发生/开始日期时填写，否则为 null
        - event_ended_at: 字符串，可解析为 yyyy-MM-dd 或 ISO8601；只有正文明确写出事件结束日期时填写，否则为 null
        - date_basis: eventTime/publishedAt/collectedAt。只要明确抽取到事件发生时间就用 eventTime；否则如果只有内容发布时间就用 publishedAt；都没有就用 collectedAt
        - date_confidence: 0 到 1。真实事件时间明确时可高于 0.75；只有发布时间时不高于 0.65；只有采集时间时不高于 0.35
        如果内容只是泛泛出现关键词、讲的是无关公司/人物/行业、或无法确认和目标对象有关，is_relevant 必须为 false。
        对天气、灾害、用电、节假日、交通、治安等社会/自然事件，必须优先抽取事件真实发生时间；不能把采集时间当成事件时间。
        不要输出 Markdown，不要输出 JSON 以外的文字。
        """
    }

    private func userPrompt(item: ExternalReferenceItem, source: ExternalReferenceSource?) -> String {
        let competitor = source?.competitorName.nilIfBlank ?? item.sourceName
        let aliases = source?.competitorAliases.joined(separator: ", ") ?? ""
        let keywords = source?.keywords.joined(separator: ", ") ?? item.keywords.joined(separator: ", ")
        let market = source?.tavilyCountry ?? ""
        let queryGroup = source?.tavilyQueryGroup ?? ""
        let sourceProfile = source?.tavilySourceProfile ?? ""
        let content = item.rawContent.nilIfBlank ?? item.summary
        return """
        情报域：\(item.domain.label)
        目标对象/竞品：\(competitor)
        别名：\(aliases)
        关键词：\(keywords)
        重点市场：\(market)
        查询主题组：\(queryGroup)
        信息来源组：\(sourceProfile)
        来源名称：\(item.sourceName)
        标题：\(item.title)
        链接：\(item.url)
        采集时间：\(DateFormatting.shortDateTime.string(from: item.collectedAt))
        内容发布时间：\(item.publishedAt.map { DateFormatting.shortDateTime.string(from: $0) } ?? "未知")
        当前事件时间：\(item.eventStartedAt.map { DateFormatting.shortDateTime.string(from: $0) } ?? "未知")
        正文：
        \(clipped(content, to: 6_000))
        """
    }

    private func parse(_ response: String, fallbackItem: ExternalReferenceItem) throws -> ReferenceIntelligenceAnalysis {
        let json = extractJSONObject(from: response)
        guard let data = json.data(using: .utf8) else {
            throw AIAnalysisError.invalidResponse("情报分析响应无法转为 UTF-8。")
        }
        let payload = try JSONDecoder().decode(AnalysisPayload.self, from: data)
        return ReferenceIntelligenceAnalysis(
            category: ExternalReferenceIntelligenceCategory(rawValue: payload.category ?? "") ?? .other,
            summary: payload.summary?.nilIfBlank ?? clipped(fallbackItem.summary, to: 240),
            impact: payload.impact?.nilIfBlank ?? "建议人工复核其对产品迭代的影响。",
            importance: min(max(payload.importance ?? 2, 1), 5),
            isRelevant: payload.isRelevantValue ?? true,
            relevanceReason: payload.relevanceReasonValue.nilIfBlank ?? "模型未给出相关性原因",
            eventStartedAt: DateParsing.parse(payload.eventStartedAt ?? ""),
            eventEndedAt: DateParsing.parse(payload.eventEndedAt ?? ""),
            dateBasis: payload.dateBasisValue,
            dateConfidence: payload.dateConfidenceValue,
            warning: nil
        )
    }

    private func fallback(item: ExternalReferenceItem, reason: String?) -> ReferenceIntelligenceAnalysis {
        let prefix = reason.map { "AI 分析失败：\($0)。" } ?? ""
        let content = item.rawContent.nilIfBlank ?? item.summary
        return ReferenceIntelligenceAnalysis(
            category: fallbackCategory(for: item),
            summary: prefix + clipped(content, to: 240),
            impact: "建议打开来源链接复核，并按业务相关性人工判断影响。",
            importance: 2,
            isRelevant: true,
            relevanceReason: reason == nil ? "未配置 AI API，保守保留待人工复核" : "AI 分析失败，保守保留待人工复核",
            eventStartedAt: nil,
            eventEndedAt: nil,
            dateBasis: nil,
            dateConfidence: nil,
            warning: reason
        )
    }

    private func fallbackCategory(for item: ExternalReferenceItem) -> ExternalReferenceIntelligenceCategory {
        switch item.domain {
        case .policy: return .policy
        case .market: return .market
        case .externalEvent:
            let text = "\(item.title) \(item.summary) \(item.rawContent) \(item.keywords.joined(separator: " "))".normalizedKey
            if text.contains("clima") || text.contains("weather") || text.contains("huracan") || text.contains("lluvia") || text.contains("calor") { return .weather }
            if text.contains("sismo") || text.contains("volcan") || text.contains("desastre") || text.contains("inundacion") { return .disaster }
            if text.contains("cfe") || text.contains("cenace") || text.contains("energia") || text.contains("electric") || text.contains("apagon") { return .energy }
            if text.contains("feriado") || text.contains("festivo") || text.contains("evento") { return .holiday }
            if text.contains("transporte") || text.contains("carretera") || text.contains("infraestructura") { return .traffic }
            if text.contains("seguridad") || text.contains("huelga") || text.contains("protesta") || text.contains("bloqueo") { return .publicSafety }
            return .localEconomy
        case .competitor, .manual: return .other
        }
    }

    private func extractJSONObject(from value: String) -> String {
        guard let start = value.firstIndex(of: "{"),
              let end = value.lastIndex(of: "}"),
              start <= end else {
            return value
        }
        return String(value[start...end])
    }

    private func clipped(_ value: String, to limit: Int) -> String {
        value.count > limit ? String(value.prefix(limit)) : value
    }
}

private struct AnalysisPayload: Decodable {
    var isRelevant: Bool?
    var isRelevantSnake: Bool?
    var relevanceReason: String?
    var relevanceReasonSnake: String?
    var category: String?
    var summary: String?
    var impact: String?
    var importance: Int?
    var eventStartedAt: String?
    var eventEndedAt: String?
    var dateBasis: String?
    var dateBasisSnake: String?
    var dateConfidence: Double?
    var dateConfidenceSnake: Double?

    var isRelevantValue: Bool? {
        isRelevantSnake ?? isRelevant
    }

    var relevanceReasonValue: String {
        relevanceReasonSnake ?? relevanceReason ?? ""
    }

    var dateBasisValue: ExternalReferenceDateBasis? {
        let raw = (dateBasisSnake ?? dateBasis ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return ExternalReferenceDateBasis(rawValue: raw)
    }

    var dateConfidenceValue: Double? {
        dateConfidenceSnake ?? dateConfidence
    }

    enum CodingKeys: String, CodingKey {
        case isRelevant
        case isRelevantSnake = "is_relevant"
        case relevanceReason
        case relevanceReasonSnake = "relevance_reason"
        case category
        case summary
        case impact
        case importance
        case eventStartedAt = "event_started_at"
        case eventEndedAt = "event_ended_at"
        case dateBasis
        case dateBasisSnake = "date_basis"
        case dateConfidence
        case dateConfidenceSnake = "date_confidence"
    }
}
