import Foundation

enum ExternalEventImpactAIService {
    static func analyze(
        pack: DataPack,
        referenceItems: [ExternalReferenceItem],
        settings: AISettings
    ) async -> (records: [ExternalEventImpactRecord], jobRecord: AIJobRecord?) {
        let eventItems = referenceItems
            .filter { $0.domain == .externalEvent || eventLikeCategory($0.intelligenceCategory) }
            .sorted { $0.displayDate > $1.displayDate }
            .prefix(24)
        guard !eventItems.isEmpty else { return ([], nil) }

        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (fallbackRecords(pack: pack, items: Array(eventItems), reason: "未配置 AI API Key"), nil)
        }

        let prompt = prompt(pack: pack, items: Array(eventItems))
        let queue = AIJobQueue(maxAttempts: 6)
        do {
            let result = try await queue.runTextJob(
                prompt: prompt,
                settings: settings,
                jobType: "外部事件影响分析",
                validation: { raw in
                    parse(raw, sourceItems: Array(eventItems)) == nil ? ["外部事件影响分析必须输出 JSON 对象。"] : []
                },
                correctionPrompt: { originalPrompt, output, warnings in
                    """
                    外部事件影响分析没有通过校验，请只输出修正后的 JSON。
                    校验问题：\(warnings.joined(separator: "；"))
                    原始要求：
                    \(originalPrompt)
                    上次输出：
                    \(output)
                    """
                }
            )
            let records = parse(result.output, sourceItems: Array(eventItems)) ?? fallbackRecords(pack: pack, items: Array(eventItems), reason: "AI JSON 缺少 impacts。")
            return (records, result.record)
        } catch {
            return (fallbackRecords(pack: pack, items: Array(eventItems), reason: error.localizedDescription), (error as? AIJobQueueError)?.record)
        }
    }

    private static func prompt(pack: DataPack, items: [ExternalReferenceItem]) -> String {
        let reports = pack.importedReports.filter { !$0.isIgnoredFromAnalysis }
        let trends = reports.flatMap { report in
            report.trendSummary.metricTrends.prefix(40).map { trend -> String in
                if let comparison = trend.primaryComparison {
                    return "\(report.displayName) / \(trend.metricName)：\(comparison.currentLabel) vs \(comparison.previousLabel)，\(comparison.previousValue.compactText) -> \(comparison.currentValue.compactText)，\(comparison.direction.rawValue)，未成熟：\(trend.latestPointIsPartial == true ? "是" : "否")"
                }
                return "\(report.displayName) / \(trend.metricName)：\(trend.firstValue.compactText) -> \(trend.lastValue.compactText)，\(trend.direction.rawValue)"
            }
        }
        let itemText = items.map { item in
            """
            - id=\(item.id.uuidString)
              类型：\(item.domain.label)/\(item.intelligenceCategory.label)
              分析日期：\(DateFormatting.shortDate.string(from: item.displayDate))
              时间依据：\(item.dateBasisLabel)，置信度：\(Int(item.resolvedDateConfidence * 100))%
              事件开始：\(item.eventStartedAt.map { DateFormatting.shortDate.string(from: $0) } ?? "未知")
              事件结束：\(item.eventEndedAt.map { DateFormatting.shortDate.string(from: $0) } ?? "未知")
              内容发布时间：\(item.publishedAt.map { DateFormatting.shortDate.string(from: $0) } ?? "未知")
              采集时间：\(DateFormatting.shortDateTime.string(from: item.collectedAt))
              标题：\(item.title)
              摘要：\(item.summary)
              影响：\(item.impact)
              链接：\(item.url)
            """
        }.joined(separator: "\n")

        return """
        你是外部社会/自然事件影响归因助手。请直接分析天气、自然灾害、能源/用电/停电、节假日/大型活动、交通/基础设施、治安/罢工/抗议、宏观消费事件是否可能影响产品指标。

        \(FinancialPromptPolicy.coreSystemPrompt)

        严格规则：
        \(FinancialPromptPolicy.externalEvidenceRules)

        - 只把事件作为候选影响因素，不能机械断言因果。
        - 必须匹配事件时间、地区、人群、影响机制、指标波动窗口。
        - 事件晚于指标波动窗口时只能作为反证或后续影响。
        - 如果候选事件只有“采集时间”，没有事件发生时间或内容发布时间，证据等级只能给 D/E。
        - 如果只有“内容发布时间”，没有事件真实发生时间，不能给 B 以上。
        - 输出证据等级：A/B/C/D/E。没有表格窗口重合只能给 D/E。

        输出 JSON：
        {
          "impacts": [
            {
              "source_item_id": "UUID",
              "event_title": "事件名",
              "region": "地区",
              "affected_audience": "可能影响人群",
              "mechanism": "影响机制",
              "related_metrics": ["指标"],
              "event_date": "yyyy-MM-dd 或 null",
              "overlap": "和表格时间窗口的重合度",
              "evidence_level": "B|C|D|E",
              "confidence": 0.0
            }
          ]
        }

        数据包：\(pack.name) / \(pack.period)
        表格趋势：
        \(trends.prefix(120).map { "- \($0)" }.joined(separator: "\n"))

        外部事件候选：
        \(itemText)
        """
    }

    private static func parse(_ raw: String, sourceItems: [ExternalReferenceItem]) -> [ExternalEventImpactRecord]? {
        guard let data = extractJSONObject(from: raw).data(using: .utf8) else { return nil }
        guard let payload = try? JSONDecoder().decode(EventImpactPayload.self, from: data) else { return nil }
        let itemsByID = Dictionary(uniqueKeysWithValues: sourceItems.map { ($0.id, $0) })
        return payload.records(sourceItemsByID: itemsByID)
    }

    private static func fallbackRecords(pack: DataPack, items: [ExternalReferenceItem], reason: String) -> [ExternalEventImpactRecord] {
        let metrics = pack.importedReports
            .flatMap { $0.trendSummary.metricTrends.map(\.metricName) }
            .uniqued()
            .prefix(8)
        return items.prefix(8).map { item in
            ExternalEventImpactRecord(
                eventTitle: item.title,
                eventDomain: item.domain,
                eventDate: item.displayDate,
                region: item.keywords.first { $0.localizedCaseInsensitiveContains("Mexico") } ?? "Mexico",
                affectedAudience: "需人工复核",
                mechanism: "AI 事件影响分析未完成：\(reason)",
                relatedMetrics: Array(metrics),
                overlapWithDataWindow: "未完成 AI 时间窗口匹配",
                evidenceLevel: .d,
                confidence: 0.35,
                sourceItemID: item.id,
                sourceURL: item.url.nilIfBlank,
                isUserAccepted: false
            )
        }
    }

    private static func eventLikeCategory(_ category: ExternalReferenceIntelligenceCategory) -> Bool {
        switch category {
        case .weather, .disaster, .energy, .holiday, .traffic, .publicSafety, .localEconomy:
            return true
        default:
            return false
        }
    }

    private static func extractJSONObject(from value: String) -> String {
        guard let start = value.firstIndex(of: "{"),
              let end = value.lastIndex(of: "}"),
              start <= end else {
            return value
        }
        return String(value[start...end])
    }
}

private struct EventImpactPayload: Decodable {
    var impacts: [ImpactPayload]

    func records(sourceItemsByID: [UUID: ExternalReferenceItem]) -> [ExternalEventImpactRecord] {
        impacts.map { payload in
            let sourceID = payload.sourceItemID.flatMap(UUID.init(uuidString:))
            let sourceItem = sourceID.flatMap { sourceItemsByID[$0] }
            let requestedEventDate = DateParsing.parse(payload.eventDate ?? "")
            let basis = sourceItem?.resolvedDateBasis ?? .collectedAt
            let rawLevel = EvidenceLevel(rawValue: payload.evidenceLevel ?? "D") ?? .d
            let cappedLevel = Self.cappedEvidenceLevel(rawLevel, basis: basis)
            let rawConfidence = min(max(payload.confidence ?? 0.45, 0), 1)
            let cappedConfidence = basis == .collectedAt ? min(rawConfidence, 0.35) : (basis == .publishedAt ? min(rawConfidence, 0.65) : rawConfidence)
            return ExternalEventImpactRecord(
                eventTitle: payload.eventTitle ?? "外部事件",
                eventDomain: .externalEvent,
                eventDate: requestedEventDate ?? sourceItem?.displayDate,
                region: payload.region ?? "",
                affectedAudience: payload.affectedAudience ?? "",
                mechanism: payload.mechanism ?? "",
                relatedMetrics: payload.relatedMetrics ?? [],
                overlapWithDataWindow: payload.overlap ?? "",
                evidenceLevel: cappedLevel,
                confidence: cappedConfidence,
                sourceItemID: sourceID,
                sourceURL: sourceItem?.url.nilIfBlank,
                isUserAccepted: false
            )
        }
    }

    private static func cappedEvidenceLevel(_ level: EvidenceLevel, basis: ExternalReferenceDateBasis) -> EvidenceLevel {
        switch basis {
        case .eventTime:
            return level
        case .publishedAt:
            return level == .a || level == .b ? .c : level
        case .collectedAt:
            return level == .e ? .e : .d
        }
    }

    struct ImpactPayload: Decodable {
        var sourceItemID: String?
        var eventTitle: String?
        var region: String?
        var affectedAudience: String?
        var mechanism: String?
        var relatedMetrics: [String]?
        var eventDate: String?
        var overlap: String?
        var evidenceLevel: String?
        var confidence: Double?

        enum CodingKeys: String, CodingKey {
            case sourceItemID = "source_item_id"
            case eventTitle = "event_title"
            case region
            case affectedAudience = "affected_audience"
            case mechanism
            case relatedMetrics = "related_metrics"
            case eventDate = "event_date"
            case overlap
            case evidenceLevel = "evidence_level"
            case confidence
        }
    }
}
