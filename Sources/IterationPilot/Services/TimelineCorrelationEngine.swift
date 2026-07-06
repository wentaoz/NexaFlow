import Foundation

enum TimelineCorrelationEngine {
    static func buildSignals(
        pack: DataPack,
        knowledgeEntries: [KnowledgeEntry],
        referenceItems: [ExternalReferenceItem]
    ) -> [AnalysisContextSignal] {
        let activeReports = pack.importedReports.filter { !$0.isIgnoredFromAnalysis }
        guard !activeReports.isEmpty else { return [] }

        let events = timelineEvents(knowledgeEntries: knowledgeEntries, referenceItems: referenceItems)
        guard !events.isEmpty else { return [] }

        var signals: [AnalysisContextSignal] = []
        for report in activeReports {
            for trend in report.trendSummary.metricTrends where trend.direction != .flat {
                guard let window = TrendWindow(report: report, trend: trend) else { continue }
                let matches = events
                    .compactMap { match(event: $0, trend: trend, window: window) }
                    .sorted { lhs, rhs in
                        if lhs.score != rhs.score { return lhs.score > rhs.score }
                        return lhs.event.date > rhs.event.date
                    }
                    .prefix(6)

                guard !matches.isEmpty else { continue }
                let detail = timelineDetail(matches: Array(matches), window: window, trend: trend, report: report)
                let topMatch = matches.first
                let relationReason = "按表格真实时间窗口 \(window.label) 匹配前置/同期/滞后事件；Confluence 只使用需求文档自身创建/修改时间，不使用知识库同步或创建时间，且不默认等同上线时间。"

                signals.append(AnalysisContextSignal(
                    domain: .timeline,
                    title: "\(trend.metricName) 的时间线匹配证据",
                    detail: detail,
                    relatedMetric: trend.metricName,
                    sourceName: report.displayName,
                    sourceURL: matches.first?.event.sourceURL,
                    observedAt: window.endDate,
                    strength: topMatch.map(signalStrength(for:)) ?? 3,
                    relationReason: relationReason,
                    isInferredRelation: true
                ))
            }
        }

        return signals
            .sorted {
                if $0.strength != $1.strength { return $0.strength > $1.strength }
                return ($0.observedAt ?? .distantPast) > ($1.observedAt ?? .distantPast)
            }
            .prefix(16)
            .map { $0 }
    }

    private struct TrendWindow {
        var reportName: String
        var startDate: Date
        var endDate: Date
        var label: String

        init?(report: ImportedReport, trend: ReportMetricTrend) {
            guard let endDate = trend.trendEndDate else { return nil }
            let startDate = trend.trendStartDate ?? endDate
            self.reportName = report.displayName
            self.startDate = min(startDate, endDate)
            self.endDate = max(startDate, endDate)
            let startLabel = trend.trendStartLabel ?? DateFormatting.shortDate.string(from: self.startDate)
            let endLabel = trend.trendEndLabel ?? DateFormatting.shortDate.string(from: self.endDate)
            self.label = startLabel == endLabel ? endLabel : "\(startLabel) 至 \(endLabel)"
        }
    }

    private struct TimelineEvent {
        var domain: AnalysisContextDomain
        var title: String
        var detail: String
        var sourceName: String
        var sourceURL: String?
        var date: Date
        var dateBasis: String
        var caveat: String
        var reliability: Int
        var importance: Int
        var searchableText: String
    }

    private struct TimelineMatch {
        var event: TimelineEvent
        var relation: TimelineRelation
        var dayDistance: Int
        var score: Int
        var metricReason: String
    }

    private enum TimelineRelation {
        case before
        case during
        case after

        var label: String {
            switch self {
            case .before: return "前置"
            case .during: return "同期"
            case .after: return "滞后"
            }
        }

        var implication: String {
            switch self {
            case .before: return "可作为候选前置因素"
            case .during: return "可作为同期干扰或共同背景"
            case .after: return "晚于波动，只能作为反证或后续影响"
            }
        }
    }

    private static func timelineEvents(
        knowledgeEntries: [KnowledgeEntry],
        referenceItems: [ExternalReferenceItem]
    ) -> [TimelineEvent] {
        let knowledgeEvents = KnowledgeEventAxis.productEvents(from: knowledgeEntries)
            .prefix(120)
            .map { entry -> TimelineEvent in
                let timing = KnowledgeEventAxis.eventTiming(for: entry)
                let sourceName = entry.sourceURL == nil ? "知识库" : "Confluence"
                let searchable = [
                    entry.scenario,
                    entry.problem,
                    entry.action,
                    entry.result,
                    entry.tags.joined(separator: " ")
                ].joined(separator: " ")
                return TimelineEvent(
                    domain: .knowledge,
                    title: KnowledgeEventAxis.title(for: entry),
                    detail: KnowledgeEventAxis.compactContext(for: entry),
                    sourceName: sourceName,
                    sourceURL: entry.sourceURL,
                    date: timing.date,
                    dateBasis: timing.basis.label,
                    caveat: timing.basis.caveat,
                    reliability: timing.basis.reliabilityScore,
                    importance: timing.basis == .explicitLaunchDate ? 4 : 2,
                    searchableText: searchable
                )
            }

        let referenceEvents = referenceItems
            .filter(\.isRelevant)
            .sorted { $0.displayDate > $1.displayDate }
            .prefix(180)
            .map { item -> TimelineEvent in
                let basis = item.resolvedDateBasis
                let detail = [
                    item.summary.nilIfBlank,
                    item.impact.nilIfBlank.map { "影响：\($0)" },
                    item.relevanceReason.nilIfBlank.map { "相关性：\($0)" },
                    item.eventStartedAt.map { "事件开始：\(DateFormatting.shortDate.string(from: $0))" },
                    item.eventEndedAt.map { "事件结束：\(DateFormatting.shortDate.string(from: $0))" },
                    item.publishedAt.map { "内容发布时间：\(DateFormatting.shortDate.string(from: $0))" },
                    "采集时间：\(DateFormatting.shortDateTime.string(from: item.collectedAt))"
                ].compactMap { $0 }.joined(separator: "；")
                return TimelineEvent(
                    domain: contextDomain(for: item.domain),
                    title: item.title,
                    detail: detail,
                    sourceName: item.sourceName,
                    sourceURL: item.url.nilIfBlank,
                    date: item.displayDate,
                    dateBasis: basis.label,
                    caveat: basis.caveat,
                    reliability: basis.reliabilityScore,
                    importance: item.importance,
                    searchableText: [item.title, item.summary, item.impact, item.relevanceReason, item.keywords.joined(separator: " ")].joined(separator: " ")
                )
            }

        return Array(knowledgeEvents) + Array(referenceEvents)
    }

    private static func match(event: TimelineEvent, trend: ReportMetricTrend, window: TrendWindow) -> TimelineMatch? {
        guard let relation = relation(of: event.date, to: window) else { return nil }
        let distance = dayDistance(event.date, window: window, relation: relation)
        let metricMatch = metricMatchScore(text: event.searchableText, metric: trend.metricName)
        let relationScore: Int
        switch relation {
        case .before:
            relationScore = distance <= 7 ? 3 : 2
        case .during:
            relationScore = 3
        case .after:
            relationScore = 1
        }
        let score = relationScore + event.reliability + metricMatch.score + min(3, max(0, event.importance))
        let isCloseToWindow = relation == .during || distance <= 7
        let hasMetricMatch = metricMatch.score > 0
        let minimumScore: Int
        if hasMetricMatch {
            minimumScore = event.reliability <= 1 ? 7 : 6
        } else if isCloseToWindow && event.importance >= 3 {
            minimumScore = event.reliability <= 1 ? 5 : 4
        } else {
            minimumScore = 8
        }
        guard score >= minimumScore else { return nil }
        return TimelineMatch(
            event: event,
            relation: relation,
            dayDistance: distance,
            score: score,
            metricReason: metricMatch.reason.nilIfBlank ?? broadTimelineReason(for: event, relation: relation)
        )
    }

    private static func signalStrength(for match: TimelineMatch) -> Int {
        var strength = min(10, match.score)
        if match.metricReason.contains("未命中指标关键词") {
            strength -= 1
        }
        if match.relation == .after {
            strength -= 1
        }
        if match.event.reliability <= 1 {
            strength -= 1
        }
        return min(10, max(3, strength))
    }

    private static func broadTimelineReason(for event: TimelineEvent, relation: TimelineRelation) -> String {
        switch relation {
        case .before:
            return "未命中指标关键词，作为波动前的\(event.domain.label)背景线索，不能单独归因"
        case .during:
            return "未命中指标关键词，作为同期\(event.domain.label)背景线索，需结合业务口径验证"
        case .after:
            return "未命中指标关键词且晚于波动窗口，只能作为后续市场参照或反证"
        }
    }

    private static func relation(of date: Date, to window: TrendWindow) -> TimelineRelation? {
        if date >= window.startDate && date <= window.endDate {
            return .during
        }
        let calendar = Calendar.current
        if date < window.startDate {
            let days = calendar.dateComponents([.day], from: date, to: window.startDate).day ?? 999
            return days <= 30 ? .before : nil
        }
        let days = calendar.dateComponents([.day], from: window.endDate, to: date).day ?? 999
        return days <= 14 ? .after : nil
    }

    private static func dayDistance(_ date: Date, window: TrendWindow, relation: TimelineRelation) -> Int {
        let calendar = Calendar.current
        switch relation {
        case .before:
            return max(0, calendar.dateComponents([.day], from: date, to: window.startDate).day ?? 0)
        case .during:
            return 0
        case .after:
            return max(0, calendar.dateComponents([.day], from: window.endDate, to: date).day ?? 0)
        }
    }

    private static func timelineDetail(
        matches: [TimelineMatch],
        window: TrendWindow,
        trend: ReportMetricTrend,
        report: ImportedReport
    ) -> String {
        var lines = [
            "\(report.displayName)：\(trend.metricName) 的趋势窗口为 \(window.label)，趋势方向为 \(trend.direction.rawValue)。"
        ]
        if trend.latestPointIsPartial == true {
            let label = trend.partialLatestLabel ?? "最新周期"
            let reason = trend.partialLatestPointReason ?? "未完整"
            lines.append("最新周期 \(label) \(reason)，不作为主趋势结论。")
        }
        for match in matches {
            let date = DateFormatting.shortDate.string(from: match.event.date)
            let distanceText: String
            switch match.relation {
            case .before:
                distanceText = "早于窗口 \(match.dayDistance) 天"
            case .during:
                distanceText = "落在趋势窗口内"
            case .after:
                distanceText = "晚于窗口 \(match.dayDistance) 天"
            }
            var line = "\(match.relation.label)：\(date) [\(match.event.domain.label)/\(match.event.sourceName)] \(match.event.title)；\(distanceText)；时间依据：\(match.event.dateBasis)；\(match.relation.implication)。"
            if !match.metricReason.isEmpty {
                line += " \(match.metricReason)。"
            }
            if !match.event.caveat.isEmpty {
                line += " 注意：\(match.event.caveat)"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    private static func metricMatchScore(text: String, metric: String) -> (score: Int, reason: String) {
        let normalizedText = text.normalizedKey
        let normalizedMetric = metric.normalizedKey
        guard !normalizedText.isEmpty, !normalizedMetric.isEmpty else { return (0, "") }
        if normalizedText.contains(normalizedMetric) {
            return (4, "文本直接命中指标「\(metric)」")
        }

        let metricTokens = tokens(in: normalizedMetric)
        let textTokens = tokens(in: normalizedText)
        let overlap = metricTokens.intersection(textTokens)
        if !overlap.isEmpty {
            return (min(3, overlap.count + 1), "文本命中指标关键词：\(overlap.sorted().prefix(3).joined(separator: "、"))")
        }

        for group in semanticGroups {
            let metricHit = group.contains { normalizedMetric.contains($0.normalizedKey) }
            let textHit = group.contains { normalizedText.contains($0.normalizedKey) }
            if metricHit && textHit {
                return (2, "文本与指标属于相近业务语义")
            }
        }
        return (0, "")
    }

    private static func tokens(in text: String) -> Set<String> {
        let separators = CharacterSet(charactersIn: " _-/|:：,，;；()（）[]【】{}<>《》.+")
        return Set(text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 })
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
}
