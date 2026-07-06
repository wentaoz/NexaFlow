import Foundation

enum AnalysisContextSynthesizer {
    static func buildSignals(
        pack: DataPack,
        referenceItems: [ExternalReferenceItem],
        referenceSources: [ExternalReferenceSource] = [],
        correctionMemories: [AnalysisCorrectionMemory],
        knowledgeEntries: [KnowledgeEntry]
    ) -> [AnalysisContextSignal] {
        var pack = pack
        pack.importedReports = pack.importedReports.filter { !$0.isIgnoredFromAnalysis }
        let metricCandidates = metricCandidates(for: pack)
        var signals: [AnalysisContextSignal] = []
        signals.append(contentsOf: tableTrendSignals(for: pack))
        signals.append(contentsOf: TimelineCorrelationEngine.buildSignals(
            pack: pack,
            knowledgeEntries: knowledgeEntries,
            referenceItems: referenceItems
        ))
        signals.append(contentsOf: reportKnowledgeSignals(from: knowledgeEntries, metricCandidates: metricCandidates))
        signals.append(contentsOf: knowledgeSignals(from: knowledgeEntries, metricCandidates: metricCandidates))
        signals.append(contentsOf: referenceSignals(from: referenceItems, metricCandidates: metricCandidates, pack: pack))
        signals.append(contentsOf: externalEventImpactSignals(from: pack.externalEventImpacts))
        signals.append(contentsOf: correctionSignals(from: correctionMemories, metricCandidates: metricCandidates, pack: pack))
        signals.append(contentsOf: sourceCoverageSignals(sources: referenceSources, items: referenceItems))
        return rankedDeduped(signals)
    }

    static func topSignals(
        relatedTo metric: String,
        in signals: [AnalysisContextSignal],
        includingTableTrend: Bool = false,
        limit: Int = 5
    ) -> [AnalysisContextSignal] {
        let normalizedMetric = metric.normalizedKey
        return signals
            .filter { signal in
                if !includingTableTrend && signal.domain == .tableTrend { return false }
                if normalizedMetric.isEmpty { return signal.relatedMetric.isEmpty }
                let related = signal.relatedMetric.normalizedKey
                let text = "\(signal.title) \(signal.detail) \(signal.relationReason)".normalizedKey
                return (!related.isEmpty && (related.contains(normalizedMetric) || normalizedMetric.contains(related))) ||
                    text.contains(normalizedMetric)
            }
            .sorted(by: rankSort)
            .prefix(limit)
            .map { $0 }
    }

    static func compactLine(for signal: AnalysisContextSignal) -> String {
        var parts: [String] = []
        if let observedAt = signal.observedAt {
            parts.append(DateFormatting.shortDate.string(from: observedAt))
        }
        parts.append("[\(signal.domain.label)]")
        parts.append(signal.title)
        if !signal.relatedMetric.isEmpty {
            parts.append("关联：\(signal.relatedMetric)")
        }
        if !signal.relationReason.isEmpty {
            parts.append(signal.relationReason)
        }
        if signal.domain == .timeline, !signal.detail.isEmpty {
            parts.append(clipped(signal.detail, limit: 260))
        }
        let source = signal.sourceName.nilIfBlank.map { "来源：\($0)" }
        if let source {
            parts.append(source)
        }
        let joined = parts.joined(separator: "；")
        return clipped(joined, limit: 360)
    }

    static func promptLine(for signal: AnalysisContextSignal) -> String {
        let date = signal.observedAt.map { DateFormatting.shortDate.string(from: $0) } ?? "无日期"
        let relationType = signal.isInferredRelation ? "推断关联" : "事实"
        let source = signal.sourceName.isEmpty ? "未记录来源" : signal.sourceName
        let metric = signal.relatedMetric.isEmpty ? "未限定指标" : signal.relatedMetric
        return "[\(signal.domain.label)/强度 \(signal.strength)/\(relationType)] \(date) \(signal.title)；关联指标：\(metric)；原因：\(signal.relationReason.isEmpty ? "按来源类型和时间顺序纳入上下文" : signal.relationReason)；来源：\(source)；说明：\(clipped(signal.detail, limit: 420))"
    }

    private static func tableTrendSignals(for pack: DataPack) -> [AnalysisContextSignal] {
        pack.importedReports.flatMap { report -> [AnalysisContextSignal] in
            report.trendSummary.metricTrends.map { trend in
                let detail = trendBullet(for: trend, in: report) ?? fallbackTrendText(trend, report: report)
                let semanticTrust: String
                switch report.semanticStatus {
                case .confirmed:
                    semanticTrust = "报表说明已人工确认"
                case .autoInferred:
                    semanticTrust = "报表说明已自动识别，语义置信度 \(Int(report.semanticConfidence * 100))%"
                case .needsReview, .inProgress:
                    semanticTrust = "报表说明置信不足，需按低置信趋势使用"
                }
                return AnalysisContextSignal(
                    domain: .tableTrend,
                    title: "\(trend.metricName) \(trend.direction.rawValue)",
                    detail: detail,
                    relatedMetric: trend.metricName,
                    sourceName: report.fileName,
                    sourceURL: nil,
                    observedAt: trend.trendEndDate ?? report.importedAt,
                    strength: trendStrength(trend) + (report.semanticStatus == .confirmed ? 1 : 0),
                    relationReason: "\(report.shape.label)，\(semanticTrust)",
                    isInferredRelation: false
                )
            }
        }
        .sorted(by: rankSort)
        .prefix(24)
        .map { $0 }
    }

    private static func reportKnowledgeSignals(
        from entries: [KnowledgeEntry],
        metricCandidates: [String]
    ) -> [AnalysisContextSignal] {
        entries
            .filter { entry in
                entry.tags.contains { $0.normalizedKey.contains("报表知识".normalizedKey) || $0.normalizedKey.contains("ai问答沉淀".normalizedKey) } &&
                    !entry.tags.contains { $0.normalizedKey == "已归档".normalizedKey }
            }
            .prefix(80)
            .map { entry -> AnalysisContextSignal in
                let text = [
                    entry.problem,
                    entry.action,
                    entry.result,
                    entry.tags.joined(separator: " ")
                ].joined(separator: " ")
                let match = bestMetricMatch(in: text, candidates: metricCandidates)
                return AnalysisContextSignal(
                    domain: .knowledge,
                    title: "报表知识：\(entry.problem)",
                    detail: KnowledgeEventAxis.compactContext(for: entry),
                    relatedMetric: match?.metric ?? "",
                    sourceName: "报表问答知识库",
                    sourceURL: entry.sourceURL,
                    observedAt: entry.sourceUpdatedAt ?? entry.sourceCreatedAt ?? entry.createdAt,
                    strength: min(9, 5 + (match?.score ?? 0)),
                    relationReason: match?.reason ?? "用户从表格 AI 问答采纳的报表解释规则",
                    isInferredRelation: false
                )
            }
            .sorted(by: rankSort)
            .prefix(16)
            .map { $0 }
    }

    private static func knowledgeSignals(
        from entries: [KnowledgeEntry],
        metricCandidates: [String]
    ) -> [AnalysisContextSignal] {
        KnowledgeEventAxis.productEvents(from: entries)
            .filter { !isAnalysisArtifact($0) }
            .prefix(120)
            .map { entry -> AnalysisContextSignal in
                let text = [
                    entry.scenario,
                    entry.problem,
                    entry.action,
                    entry.result,
                    entry.tags.joined(separator: " ")
                ].joined(separator: " ")
                let match = bestMetricMatch(in: text, candidates: metricCandidates)
                return AnalysisContextSignal(
                    domain: .knowledge,
                    title: KnowledgeEventAxis.title(for: entry),
                    detail: KnowledgeEventAxis.compactContext(for: entry),
                    relatedMetric: match?.metric ?? "",
                    sourceName: entry.sourceURL == nil ? "知识库" : "Confluence",
                    sourceURL: entry.sourceURL,
                    observedAt: KnowledgeEventAxis.eventDate(for: entry),
                    strength: min(9, 3 + (match?.score ?? 0) + min(1, evidenceBonus(entry.evidenceLevel))),
                    relationReason: match?.reason ?? "作为知识库产品事件轴纳入多源上下文",
                    isInferredRelation: match != nil
                )
            }
            .sorted(by: rankSort)
            .prefix(18)
            .map { $0 }
    }

    private static func referenceSignals(
        from items: [ExternalReferenceItem],
        metricCandidates: [String],
        pack: DataPack
    ) -> [AnalysisContextSignal] {
        items
            .filter(\.isRelevant)
            .sorted { $0.displayDate > $1.displayDate }
            .prefix(160)
            .map { item -> AnalysisContextSignal in
                let text = [
                    item.title,
                    item.summary,
                    item.impact,
                    item.relevanceReason,
                    item.sourceName,
                    item.keywords.joined(separator: " ")
                ].joined(separator: " ")
                let match = bestMetricMatch(in: text, candidates: metricCandidates)
                return AnalysisContextSignal(
                    domain: contextDomain(for: item.domain),
                    title: "\(item.title)（\(item.intelligenceCategory.label)，重要性 \(item.importance)/5）",
                    detail: [
                        item.summary,
                        item.impact.nilIfBlank.map { "影响：\($0)" },
                        item.relevanceReason.nilIfBlank.map { "相关性：\($0)" },
                        "时间依据：\(item.dateBasisLabel)，置信度 \(Int(item.resolvedDateConfidence * 100))%",
                        item.dateCaveat.nilIfBlank
                    ]
                        .compactMap { $0 }
                        .joined(separator: "；"),
                    relatedMetric: match?.metric ?? "",
                    sourceName: item.sourceName,
                    sourceURL: item.url.nilIfBlank,
                    observedAt: item.displayDate,
                    strength: min(10, max(1, referenceBaseStrength(item.domain) + item.importance + (match?.score ?? 0) + recencyBonus(item.displayDate, pack: pack) + dateBasisAdjustment(item.resolvedDateBasis))),
                    relationReason: match?.reason ?? "作为\(item.domain.label)参照纳入外部上下文；时间依据：\(item.dateBasisLabel)",
                    isInferredRelation: true
                )
            }
            .sorted(by: rankSort)
            .prefix(28)
            .map { $0 }
    }

    private static func correctionSignals(
        from memories: [AnalysisCorrectionMemory],
        metricCandidates: [String],
        pack: DataPack
    ) -> [AnalysisContextSignal] {
        memories
            .filter { $0.appliesToFuture || $0.packID == pack.id }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(50)
            .map { memory -> AnalysisContextSignal in
                let text = [
                    memory.metric,
                    memory.scope,
                    memory.findingTitle,
                    memory.userCorrection,
                    memory.revisedConclusion,
                    memory.reusableRule,
                    memory.tags.joined(separator: " ")
                ].joined(separator: " ")
                let match = bestMetricMatch(in: text, candidates: metricCandidates)
                let metric = memory.metric.nilIfBlank ?? match?.metric ?? ""
                return AnalysisContextSignal(
                    domain: .correction,
                    title: memory.findingTitle.nilIfBlank ?? (metric.isEmpty ? "历史纠偏规则" : "\(metric) 的历史纠偏规则"),
                    detail: memory.summaryText,
                    relatedMetric: metric,
                    sourceName: memory.packName,
                    sourceURL: nil,
                    observedAt: memory.updatedAt,
                    strength: min(10, 7 + (memory.appliesToFuture ? 1 : 0) + (match == nil ? 0 : 1)),
                    relationReason: memory.appliesToFuture ? "用户确认过可复用到后续分析" : "来自当前分析资料纠偏",
                    isInferredRelation: match != nil && memory.metric.isEmpty
                )
            }
            .sorted(by: rankSort)
            .prefix(10)
            .map { $0 }
    }

    private static func externalEventImpactSignals(from records: [ExternalEventImpactRecord]) -> [AnalysisContextSignal] {
        records
            .sorted {
                if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
                return $0.createdAt > $1.createdAt
            }
            .prefix(24)
            .map { record in
                AnalysisContextSignal(
                    domain: .externalEvent,
                    title: record.eventTitle,
                    detail: [
                        record.mechanism.nilIfBlank.map { "机制：\($0)" },
                        record.affectedAudience.nilIfBlank.map { "影响人群：\($0)" },
                        record.overlapWithDataWindow.nilIfBlank.map { "时间窗口：\($0)" },
                        "证据等级：\(record.evidenceLevel.label)"
                    ].compactMap { $0 }.joined(separator: "；"),
                    relatedMetric: record.relatedMetrics.prefix(4).joined(separator: "，"),
                    sourceName: record.region.nilIfBlank ?? record.eventDomain.label,
                    sourceURL: record.sourceURL,
                    observedAt: record.eventDate ?? record.createdAt,
                    strength: min(10, max(3, Int(record.confidence * 10) + evidenceBonus(record.evidenceLevel))),
                    relationReason: "AI 根据事件时间、地区、人群和影响机制匹配；未人工采纳前只能作为候选外部影响。",
                    isInferredRelation: !record.isUserAccepted
                )
            }
    }

    private static func sourceCoverageSignals(
        sources: [ExternalReferenceSource],
        items: [ExternalReferenceItem]
    ) -> [AnalysisContextSignal] {
        let enabledSources = sources.filter(\.enabled)
        guard !enabledSources.isEmpty else { return [] }
        let itemsBySource = Dictionary(grouping: items, by: \.sourceID)
        let staleThreshold = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()

        return enabledSources.compactMap { source -> AnalysisContextSignal? in
            let sourceItems = itemsBySource[source.id] ?? []
            if sourceItems.isEmpty {
                return AnalysisContextSignal(
                    domain: .sourceCoverage,
                    title: "\(source.name) 尚未采集到参照结果",
                    detail: "该数据源已启用，类型为 \(source.collectorType.label)，领域为 \(source.domain.label)。分析会把它作为参照缺口，而不是事实证据。",
                    relatedMetric: "",
                    sourceName: source.name,
                    sourceURL: source.url.nilIfBlank,
                    observedAt: source.lastFetchedAt,
                    strength: 2,
                    relationReason: "参照数据源覆盖缺口",
                    isInferredRelation: false
                )
            }
            guard let lastFetchedAt = source.lastFetchedAt, lastFetchedAt < staleThreshold else { return nil }
            return AnalysisContextSignal(
                domain: .sourceCoverage,
                title: "\(source.name) 采集结果可能过期",
                detail: "最近采集时间为 \(DateFormatting.shortDateTime.string(from: lastFetchedAt))，建议刷新后再做高置信归因。",
                relatedMetric: "",
                sourceName: source.name,
                sourceURL: source.url.nilIfBlank,
                observedAt: lastFetchedAt,
                strength: 3,
                relationReason: "参照数据源时效性提醒",
                isInferredRelation: false
            )
        }
        .sorted(by: rankSort)
        .prefix(8)
        .map { $0 }
    }

    private static func metricCandidates(for pack: DataPack) -> [String] {
        var result: [String] = []
        var seen = Set<String>()

        func append(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.normalizedKey
            guard !trimmed.isEmpty,
                  !genericMetricKeys.contains(key),
                  seen.insert(key).inserted else { return }
            result.append(trimmed)
        }

        for metric in pack.metrics.map(\.metric) {
            append(metric)
        }
        for report in pack.importedReports {
            for trend in report.trendSummary.metricTrends {
                append(trend.metricName)
            }
            for metric in report.semanticProfile.keyMetrics {
                append(metric)
            }
            for field in DataImportService.fieldDefinitionNames(for: report) {
                append(field)
            }
        }
        for definition in pack.fieldDefinitions {
            append(definition.fieldName)
            append(definition.meaning)
        }
        if result.isEmpty {
            for fallback in ["注册", "转化", "漏斗", "申请", "开户", "激活", "授信", "曝光", "点击", "留存", "收入", "投诉", "错误"] {
                append(fallback)
            }
        }
        return result
    }

    private static func bestMetricMatch(in text: String, candidates: [String]) -> (metric: String, score: Int, reason: String)? {
        let normalizedText = text.normalizedKey
        guard !normalizedText.isEmpty else { return nil }

        var best: (metric: String, score: Int, reason: String)?
        for candidate in candidates {
            let score = semanticMatchScore(text: normalizedText, metric: candidate)
            guard score >= 3 else { continue }
            let reason = normalizedText.contains(candidate.normalizedKey)
                ? "文本直接命中指标/字段「\(candidate)」"
                : "文本与「\(candidate)」属于相近业务语义"
            if best == nil || score > best!.score {
                best = (candidate, score, reason)
            }
        }
        return best
    }

    private static func semanticMatchScore(text normalizedText: String, metric: String) -> Int {
        let normalizedMetric = metric.normalizedKey
        guard !normalizedMetric.isEmpty else { return 0 }

        var score = 0
        let hasDirectMetricMatch = normalizedText.contains(normalizedMetric)
        if hasDirectMetricMatch {
            score += 6
        }

        let metricTokens = tokens(in: normalizedMetric)
        let textTokens = tokens(in: normalizedText)
        let overlap = metricTokens.intersection(textTokens)
        if !overlap.isEmpty {
            score += min(3, overlap.count)
        }

        var semanticGroupHitCount = 0
        for group in semanticGroups {
            let groupMatchesMetric = group.contains { normalizedMetric.contains($0.normalizedKey) }
            let groupMatchesText = group.contains { normalizedText.contains($0.normalizedKey) }
            if groupMatchesMetric && groupMatchesText {
                semanticGroupHitCount += 1
            }
        }
        score += min(4, semanticGroupHitCount * 2)

        if !hasDirectMetricMatch && normalizedMetric.contains("/") && semanticGroupHitCount == 1 {
            score = min(score, 3)
        }
        return score
    }

    private static func tokens(in text: String) -> Set<String> {
        let separators = CharacterSet(charactersIn: " _-/|:：,，;；()（）[]【】{}<>《》.+")
        return Set(text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 })
    }

    private static let semanticGroups: [[String]] = [
        ["注册", "register", "registration", "signup", "sign_up"],
        ["转化", "conversion", "funnel", "漏斗"],
        ["申请", "application", "apply", "submit"],
        ["开户", "account_open", "open_account"],
        ["激活", "activation", "activate"],
        ["授信", "credit", "approval", "approve"],
        ["曝光", "impression", "exposure"],
        ["点击", "click", "tap", "ctr"],
        ["留存", "retention", "return"],
        ["收入", "revenue", "gmv", "sales", "付费"],
        ["投诉", "complaint", "舆情", "negative"],
        ["错误", "error", "crash", "失败", "fail"]
    ]

    private static let genericMetricKeys: Set<String> = [
        "指标", "数据", "字段", "名称", "日期", "时间", "周期", "区间", "维度", "类型",
        "metric", "metrics", "data", "field", "name", "date", "time", "period", "dimension", "type",
        "week_of_date", "week", "month", "day"
    ]

    private static func isAnalysisArtifact(_ entry: KnowledgeEntry) -> Bool {
        let text = [
            entry.scenario,
            entry.problem,
            entry.action,
            entry.result,
            entry.relatedPackName,
            entry.tags.joined(separator: " ")
        ]
        .joined(separator: " ")
        .normalizedKey
        if entry.sourceID?.hasPrefix("correction-") == true { return true }
        let markers = [
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
        return markers.contains { text.contains($0.normalizedKey) }
    }

    private static func trendBullet(for trend: ReportMetricTrend, in report: ImportedReport) -> String? {
        let metricKey = trend.metricName.normalizedKey
        return report.trendSummary.trendBullets.first {
            $0.normalizedKey.contains(metricKey)
        }
    }

    private static func fallbackTrendText(_ trend: ReportMetricTrend, report: ImportedReport) -> String {
        let percent = trend.percentChange.map { DateFormatting.percent.string(from: NSNumber(value: $0)) ?? "\($0)" } ?? "无百分比"
        let windowText: String
        if let start = trend.trendStartDate, let end = trend.trendEndDate {
            let startLabel = trend.trendStartLabel ?? DateFormatting.shortDate.string(from: start)
            let endLabel = trend.trendEndLabel ?? DateFormatting.shortDate.string(from: end)
            windowText = startLabel == endLabel ? "观察期 \(endLabel)，" : "观察期 \(startLabel) 至 \(endLabel)，"
        } else {
            windowText = ""
        }
        var text = "\(report.fileName)：\(windowText)\(trend.metricName) 从 \(trend.firstValue.compactText) 到 \(trend.lastValue.compactText)，\(trend.direction.rawValue)，变化 \(trend.delta.compactText)，相对变化 \(percent)。"
        if trend.latestPointIsPartial == true {
            let label = trend.partialLatestLabel ?? "最新周期"
            let reason = trend.partialLatestPointReason ?? "未完整"
            text += "\(label) 存在候选成熟口径提示：\(reason)。"
        }
        return text
    }

    private static func trendStrength(_ trend: ReportMetricTrend) -> Int {
        if trend.direction == .flat { return 3 }
        guard let percent = trend.percentChange else {
            return abs(trend.delta) >= 100 ? 6 : 4
        }
        let absPercent = abs(percent)
        if absPercent >= 0.5 { return 9 }
        if absPercent >= 0.25 { return 8 }
        if absPercent >= 0.12 { return 7 }
        if absPercent >= 0.05 { return 5 }
        return 4
    }

    private static func contextDomain(for domain: ExternalReferenceDomain) -> AnalysisContextDomain {
        switch domain {
        case .competitor: return .competitor
        case .policy: return .policy
        case .market: return .market
        case .externalEvent: return .externalEvent
        case .manual: return .manual
        }
    }

    private static func referenceBaseStrength(_ domain: ExternalReferenceDomain) -> Int {
        switch domain {
        case .competitor: return 4
        case .policy: return 5
        case .market: return 4
        case .externalEvent: return 5
        case .manual: return 3
        }
    }

    private static func evidenceBonus(_ level: EvidenceLevel) -> Int {
        switch level {
        case .a: return 3
        case .b: return 2
        case .c: return 1
        case .d: return 0
        case .e: return 0
        }
    }

    private static func recencyBonus(_ date: Date, pack: DataPack) -> Int {
        let days = abs(Calendar.current.dateComponents([.day], from: date, to: pack.importedAt).day ?? 365)
        if days <= 7 { return 2 }
        if days <= 30 { return 1 }
        return 0
    }

    private static func dateBasisAdjustment(_ basis: ExternalReferenceDateBasis) -> Int {
        switch basis {
        case .eventTime: return 1
        case .publishedAt: return 0
        case .collectedAt: return -3
        }
    }

    private static func rankedDeduped(_ signals: [AnalysisContextSignal]) -> [AnalysisContextSignal] {
        var seen = Set<String>()
        let deduped = signals
            .sorted(by: rankSort)
            .filter { signal in
                let key = [
                    signal.domain.rawValue,
                    signal.title.normalizedKey,
                    signal.relatedMetric.normalizedKey,
                    signal.sourceName.normalizedKey
                ].joined(separator: "|")
                return seen.insert(key).inserted
            }

        let timelineSignals = deduped.filter { $0.domain == .timeline }.prefix(16)
        let reservedTimelineIDs = Set(timelineSignals.map(\.id))
        let remainingLimit = max(0, 70 - timelineSignals.count)
        let remaining = deduped
            .filter { $0.domain != .timeline || !reservedTimelineIDs.contains($0.id) }
            .prefix(remainingLimit)

        return Array(timelineSignals + remaining).sorted(by: rankSort)
    }

    private static func rankSort(_ lhs: AnalysisContextSignal, _ rhs: AnalysisContextSignal) -> Bool {
        if lhs.strength != rhs.strength {
            return lhs.strength > rhs.strength
        }
        let lhsDate = lhs.observedAt ?? .distantPast
        let rhsDate = rhs.observedAt ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func clipped(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit)) + "..."
    }
}
