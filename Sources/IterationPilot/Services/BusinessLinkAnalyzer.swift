import Foundation

enum BusinessLinkAnalyzer {
    static func buildProfile(
        for task: AnalysisTask,
        reports: [ImportedReport],
        preserving existing: BusinessLinkProfile? = nil
    ) -> BusinessLinkProfile {
        let activeReports = reports.filter { task.activeReportIDs.contains($0.id) }
        guard !activeReports.isEmpty else {
            return BusinessLinkProfile(
                nodes: [],
                edges: [],
                metricLinks: [],
                metricLinkageAnomalies: [],
                summary: "当前任务还没有选择报表。",
                confirmationStatus: .needsReview,
                updatedAt: Date()
            )
        }

        let nodes = activeReports.map { node(for: $0, role: task.role(for: $0.id)) }
        let existingEdgesByKey = Dictionary(uniqueKeysWithValues: (existing?.edges ?? []).map { (edgeKey($0), $0) })
        let existingMetricLinksByKey = Dictionary(uniqueKeysWithValues: (existing?.metricLinks ?? []).map { (metricLinkKey($0), $0) })
        let existingAnomaliesByKey = Dictionary(uniqueKeysWithValues: (existing?.metricLinkageAnomalies ?? []).map { (MetricLinkageAnomalyScanner.stableKey(for: $0), $0) })
        var inferredEdges = inferEdges(reports: activeReports, nodes: nodes, task: task).map { edge -> BusinessLinkEdge in
            guard let existing = existingEdgesByKey[edgeKey(edge)] else { return edge }
            var copy = edge
            copy.id = existing.id
            copy.confirmationStatus = existing.confirmationStatus
            return copy
        }
        var inferredMetricLinks = inferMetricLinks(reports: activeReports, nodes: nodes, task: task).map { link -> CrossTableMetricLink in
            guard let existing = existingMetricLinksByKey[metricLinkKey(link)] else { return link }
            var copy = link
            copy.id = existing.id
            copy.confirmationStatus = existing.confirmationStatus
            return copy
        }
        var scanTask = task
        scanTask.businessLinkProfile = BusinessLinkProfile(
            nodes: nodes,
            edges: inferredEdges,
            metricLinks: inferredMetricLinks,
            metricLinkageAnomalies: [],
            summary: "",
            confirmationStatus: existing?.confirmationStatus ?? .needsReview,
            updatedAt: Date()
        )
        let defaultPeriodIntent = MetricLinkageAnomalyScanner.extractPeriodIntent(
            userRequest: "",
            taskGoal: task.goal,
            reports: activeReports
        )
        var inferredAnomalies = MetricLinkageAnomalyScanner
            .scan(reports: activeReports, task: scanTask, periodIntent: defaultPeriodIntent)
            .anomalies
            .map { anomaly -> MetricLinkageAnomaly in
                guard let existing = existingAnomaliesByKey[MetricLinkageAnomalyScanner.stableKey(for: anomaly)] else { return anomaly }
                var copy = anomaly
                copy.id = existing.id
                copy.confirmationStatus = existing.confirmationStatus
                return copy
            }
        if existing?.confirmationStatus == .confirmed {
            for index in inferredEdges.indices where inferredEdges[index].confirmationStatus == .needsReview {
                inferredEdges[index].confirmationStatus = .confirmed
            }
            for index in inferredMetricLinks.indices where inferredMetricLinks[index].confirmationStatus == .needsReview {
                inferredMetricLinks[index].confirmationStatus = .confirmed
            }
            for index in inferredAnomalies.indices where inferredAnomalies[index].confirmationStatus == .needsReview {
                inferredAnomalies[index].confirmationStatus = .confirmed
            }
        }

        let confirmedExisting = existing?.confirmationStatus == .confirmed
        let status: BusinessLinkConfirmationStatus
        if activeReports.count <= 1 {
            status = .confirmed
        } else if confirmedExisting {
            status = .confirmed
        } else {
            status = .needsReview
        }

        return BusinessLinkProfile(
            nodes: nodes,
            edges: inferredEdges,
            metricLinks: inferredMetricLinks,
            metricLinkageAnomalies: inferredAnomalies,
            summary: summary(reports: activeReports, nodes: nodes, edges: inferredEdges, metricLinks: inferredMetricLinks, anomalies: inferredAnomalies),
            confirmationStatus: status,
            updatedAt: Date()
        )
    }

    private static func node(for report: ImportedReport, role: AnalysisTaskReportRole) -> BusinessLinkNode {
        let text = searchableText(for: report)
        let domain = domain(for: text, kind: report.kind)
        let object = report.semanticProfile.businessObject.nilIfBlank ?? objectText(for: domain, report: report)
        let grain = report.semanticProfile.grain.nilIfBlank ?? report.shape.label
        let period = periodText(for: report)
        let maturity = maturityText(for: report)
        let confidence = min(0.96, max(report.detectedConfidence, report.semanticConfidence, domain.confidence) + (report.semanticStatus == .confirmed ? 0.08 : 0))
        return BusinessLinkNode(
            reportID: report.id,
            businessDomain: domain.label,
            businessObject: object,
            metricRole: role.label,
            grain: grain,
            period: period,
            maturityWindow: maturity,
            confidence: confidence,
            notes: domain.reason
        )
    }

    private static func inferEdges(
        reports: [ImportedReport],
        nodes: [BusinessLinkNode],
        task: AnalysisTask
    ) -> [BusinessLinkEdge] {
        guard reports.count > 1 else { return [] }
        let nodeByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.reportID, $0) })
        let orderedReports = reports.sorted { lhs, rhs in
            let lhsRank = domainRank(nodeByID[lhs.id]?.businessDomain ?? "")
            let rhsRank = domainRank(nodeByID[rhs.id]?.businessDomain ?? "")
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if task.role(for: lhs.id) == .impactSource { return true }
            if task.role(for: rhs.id) == .outcome { return true }
            return lhs.displayName < rhs.displayName
        }

        var edges: [BusinessLinkEdge] = []
        for pair in zip(orderedReports, orderedReports.dropFirst()) {
            let source = pair.0
            let target = pair.1
            guard task.role(for: source.id) != .excluded, task.role(for: target.id) != .excluded else { continue }
            let sourceNode = nodeByID[source.id]
            let targetNode = nodeByID[target.id]
            let relation = relationText(sourceDomain: sourceNode?.businessDomain ?? "", targetDomain: targetNode?.businessDomain ?? "")
            let evidence = edgeEvidence(source: source, target: target, sourceNode: sourceNode, targetNode: targetNode)
            let confidence = edgeConfidence(source: source, target: target, evidenceCount: evidence.count)
            edges.append(BusinessLinkEdge(
                sourceReportID: source.id,
                targetReportID: target.id,
                relationType: relation,
                hypothesis: "\(source.displayName) 的 \(sourceNode?.businessDomain ?? "上游指标") 可能影响 \(target.displayName) 的 \(targetNode?.businessDomain ?? "下游指标")，需要结合时间顺序、周期完整性和外部事件验证。",
                lagDays: lagDays(sourceDomain: sourceNode?.businessDomain ?? "", targetDomain: targetNode?.businessDomain ?? ""),
                confidence: confidence,
                evidence: evidence,
                confirmationStatus: confidence >= 0.72 ? .needsReview : .needsReview
            ))
        }

        if edges.isEmpty, let first = reports.first, let last = reports.last, first.id != last.id {
            edges.append(BusinessLinkEdge(
                sourceReportID: first.id,
                targetReportID: last.id,
                relationType: "业务相关",
                hypothesis: "这些表被放入同一任务，但系统没有识别出明确上下游，需要人工校准关系。",
                lagDays: nil,
                confidence: 0.45,
                evidence: ["同一分析任务内人工选择"],
                confirmationStatus: .needsReview
            ))
        }
        return edges
    }

    private static func inferMetricLinks(
        reports: [ImportedReport],
        nodes: [BusinessLinkNode],
        task: AnalysisTask
    ) -> [CrossTableMetricLink] {
        guard reports.count > 1 else { return [] }
        let nodeByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.reportID, $0) })
        let orderedReports = reports
            .filter { task.role(for: $0.id) != .excluded && !$0.trendSummary.metricTrends.isEmpty }
            .sorted { lhs, rhs in
                let lhsRole = task.role(for: lhs.id)
                let rhsRole = task.role(for: rhs.id)
                if lhsRole == .impactSource, rhsRole != .impactSource { return true }
                if rhsRole == .outcome, lhsRole != .outcome { return true }
                let lhsRank = domainRank(nodeByID[lhs.id]?.businessDomain ?? "")
                let rhsRank = domainRank(nodeByID[rhs.id]?.businessDomain ?? "")
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.displayName < rhs.displayName
            }

        var links: [CrossTableMetricLink] = []
        for sourceIndex in orderedReports.indices {
            for targetIndex in orderedReports.indices where targetIndex > sourceIndex {
                let source = orderedReports[sourceIndex]
                let target = orderedReports[targetIndex]
                let sourceNode = nodeByID[source.id]
                let targetNode = nodeByID[target.id]
                links.append(contentsOf: candidateMetricLinks(
                    source: source,
                    target: target,
                    sourceNode: sourceNode,
                    targetNode: targetNode
                ))
            }
        }

        return Array(links
            .sorted { lhs, rhs in
                let confidenceDelta = lhs.confidence - rhs.confidence
                if abs(confidenceDelta) > 0.02 { return lhs.confidence > rhs.confidence }
                let lhsRank = metricLinkRankingScore(lhs)
                let rhsRank = metricLinkRankingScore(rhs)
                if lhsRank != rhsRank { return lhsRank > rhsRank }
                return lhs.evidence.count > rhs.evidence.count
            }
            .prefix(32))
    }

    private static func candidateMetricLinks(
        source: ImportedReport,
        target: ImportedReport,
        sourceNode: BusinessLinkNode?,
        targetNode: BusinessLinkNode?
    ) -> [CrossTableMetricLink] {
        let sourceTrends = source.trendSummary.metricTrends
            .sorted { metricImpactScore($0) > metricImpactScore($1) }
            .prefix(40)
        let targetTrends = target.trendSummary.metricTrends
            .sorted { metricImpactScore($0) > metricImpactScore($1) }
            .prefix(40)
        var links: [CrossTableMetricLink] = []

        for sourceTrend in sourceTrends {
            for targetTrend in targetTrends {
                let relation = metricRelationScore(
                    sourceMetric: sourceTrend.metricName,
                    targetMetric: targetTrend.metricName,
                    sourceDomain: sourceNode?.businessDomain ?? "",
                    targetDomain: targetNode?.businessDomain ?? ""
                )
                guard relation.score >= 4 else { continue }

                let period = periodCompatibility(sourceTrend: sourceTrend, targetTrend: targetTrend)
                let alignment = directionAlignment(sourceTrend: sourceTrend, targetTrend: targetTrend)
                var confidence = min(source.detectedConfidence, target.detectedConfidence) * 0.35 + Double(min(relation.score, 14)) * 0.04
                if alignment.isSupportive { confidence += 0.1 } else { confidence -= 0.08 }
                if period.isCompatible { confidence += 0.07 } else { confidence -= 0.12 }
                if sourceTrend.latestPointIsPartial == true || targetTrend.latestPointIsPartial == true { confidence -= 0.08 }
                if (sourceTrend.completePointCount ?? sourceTrend.pointCount) < 4 || (targetTrend.completePointCount ?? targetTrend.pointCount) < 4 {
                    confidence -= 0.08
                }
                confidence = min(0.92, max(0.32, confidence))
                guard confidence >= 0.44 else { continue }

                let evidenceLevel: EvidenceLevel
                if period.isCompatible, alignment.isSupportive, confidence >= 0.74 {
                    evidenceLevel = .b
                } else if confidence >= 0.56 {
                    evidenceLevel = .c
                } else {
                    evidenceLevel = .d
                }
                let relationType = metricRelationType(
                    sourceDomain: sourceNode?.businessDomain ?? "",
                    targetDomain: targetNode?.businessDomain ?? "",
                    relationScore: relation.score
                )
                let evidence = [
                    "指标语义：\(relation.reason)",
                    "方向关系：\(alignment.text)",
                    period.reason,
                    sourceTrend.latestPointIsPartial == true || targetTrend.latestPointIsPartial == true ? "至少一个指标存在最新周期成熟度提醒" : nil
                ].compactMap { $0 }

                links.append(CrossTableMetricLink(
                    sourceReportID: source.id,
                    sourceMetric: sourceTrend.metricName,
                    targetReportID: target.id,
                    targetMetric: targetTrend.metricName,
                    relationType: relationType,
                    lagDays: metricLagDays(sourceDomain: sourceNode?.businessDomain ?? "", targetDomain: targetNode?.businessDomain ?? ""),
                    directionAlignment: alignment.text,
                    evidenceLevel: evidenceLevel,
                    confidence: confidence,
                    evidence: evidence.uniqued(),
                    confirmationStatus: .needsReview
                ))
            }
        }

        let sorted = links.sorted { lhs, rhs in
            let confidenceDelta = lhs.confidence - rhs.confidence
            if abs(confidenceDelta) > 0.02 { return lhs.confidence > rhs.confidence }
            let lhsRank = metricLinkRankingScore(lhs)
            let rhsRank = metricLinkRankingScore(rhs)
            if lhsRank != rhsRank { return lhsRank > rhsRank }
            if lhs.evidenceLevel != rhs.evidenceLevel { return lhs.evidenceLevel.rawValue < rhs.evidenceLevel.rawValue }
            if lhs.sourceMetric != rhs.sourceMetric { return lhs.sourceMetric < rhs.sourceMetric }
            return lhs.targetMetric < rhs.targetMetric
        }
        return diversifiedMetricLinks(sorted, limit: 10, maxPerSourceMetric: 3, maxPerTargetMetric: 2)
    }

    private static func diversifiedMetricLinks(
        _ links: [CrossTableMetricLink],
        limit: Int,
        maxPerSourceMetric: Int,
        maxPerTargetMetric: Int
    ) -> [CrossTableMetricLink] {
        var selected: [CrossTableMetricLink] = []
        var sourceCounts: [String: Int] = [:]
        var targetCounts: [String: Int] = [:]
        var seenKeys = Set<String>()

        func appendIfAllowed(_ link: CrossTableMetricLink, enforceCaps: Bool) {
            guard selected.count < limit else { return }
            let key = metricLinkKey(link)
            guard seenKeys.insert(key).inserted else { return }
            let sourceKey = link.sourceMetric.normalizedKey
            let targetKey = link.targetMetric.normalizedKey
            if enforceCaps {
                guard (sourceCounts[sourceKey] ?? 0) < maxPerSourceMetric,
                      (targetCounts[targetKey] ?? 0) < maxPerTargetMetric else { return }
            }
            selected.append(link)
            sourceCounts[sourceKey, default: 0] += 1
            targetCounts[targetKey, default: 0] += 1
        }

        for link in links {
            appendIfAllowed(link, enforceCaps: true)
        }
        for link in links where selected.count < limit {
            appendIfAllowed(link, enforceCaps: false)
        }
        return selected
    }

    private static func searchableText(for report: ImportedReport) -> String {
        [
            report.fileName,
            report.userReportAlias,
            report.kind.label,
            report.semanticProfile.summary,
            report.semanticProfile.purpose,
            report.semanticProfile.businessObject,
            report.semanticProfile.keyMetrics.joined(separator: " "),
            report.headers.joined(separator: " "),
            report.firstColumnValues.joined(separator: " "),
            report.trendSummary.trendBullets.joined(separator: " ")
        ].joined(separator: " ").normalizedKey
    }

    private struct DomainMatch {
        var label: String
        var confidence: Double
        var reason: String
    }

    private static func domain(for text: String, kind: ImportedReportKind) -> DomainMatch {
        let pageEventKeywords = ["页面", "埋点", "事件", "按钮", "提交", "报错", "停留", "event", "track", "page", "view", "click", "tap", "submit", "error", "duration"]
        if kind == .eventTracking || pageEventKeywords.filter({ text.contains($0.normalizedKey) }).count >= 2 {
            return DomainMatch(label: "页面埋点", confidence: kind == .eventTracking ? 0.72 : 0.64, reason: "命中页面/行为埋点特征")
        }

        let candidates: [(label: String, rank: Int, keywords: [String])] = [
            ("投放/安装", 10, ["投放", "广告", "渠道", "安装", "install", "campaign", "source", "曝光", "点击"]),
            ("页面埋点", 15, ["页面", "埋点", "事件", "按钮", "提交", "报错", "停留", "event", "track", "page", "view", "click", "tap", "submit", "error", "duration"]),
            ("注册", 20, ["注册", "signup", "register", "开户", "申请"]),
            ("授信/审核", 30, ["授信", "审核", "审批", "额度", "credit", "approve", "risk", "风控"]),
            ("发卡/激活", 40, ["发卡", "激活", "绑卡", "card", "activate"]),
            ("消费/交易", 50, ["消费", "交易", "支付", "订单", "gmv", "purchase", "payment"]),
            ("留存/活跃", 60, ["留存", "活跃", "dau", "mau", "retention", "复访"]),
            ("用户反馈", 70, ["反馈", "投诉", "客服", "评价", "sentiment", "nps"])
        ]

        var best: (label: String, rank: Int, hits: Int, keyword: String)? = nil
        for candidate in candidates {
            let hits = candidate.keywords.filter { text.contains($0.normalizedKey) }
            guard !hits.isEmpty else { continue }
            let current = (label: candidate.label, rank: candidate.rank, hits: hits.count, keyword: hits.first ?? candidate.label)
            if best == nil || current.hits > best!.hits || (current.hits == best!.hits && current.rank < best!.rank) {
                best = current
            }
        }

        if let best {
            return DomainMatch(
                label: best.label,
                confidence: min(0.92, 0.62 + Double(best.hits) * 0.08),
                reason: "命中关键词「\(best.keyword)」"
            )
        }

        switch kind {
        case .eventTracking:
            return DomainMatch(label: "页面埋点", confidence: 0.66, reason: "根据报表类型识别为页面/行为埋点")
        case .funnelMetrics:
            return DomainMatch(label: "转化漏斗", confidence: 0.62, reason: "根据报表类型识别为漏斗")
        case .userFeedback:
            return DomainMatch(label: "用户反馈", confidence: 0.62, reason: "根据报表类型识别为用户反馈")
        case .coreMetrics:
            return DomainMatch(label: "核心指标", confidence: 0.58, reason: "根据报表类型识别为核心指标")
        default:
            return DomainMatch(label: "未确认业务域", confidence: 0.42, reason: "未命中明确业务关键词")
        }
    }

    private static func objectText(for domain: DomainMatch, report: ImportedReport) -> String {
        if let metric = report.firstColumnValues.first?.nilIfBlank {
            return "\(domain.label)：\(metric)"
        }
        if let header = report.headers.first?.nilIfBlank {
            return "\(domain.label)：\(header)"
        }
        return domain.label
    }

    private static func periodText(for report: ImportedReport) -> String {
        let temporalHeaders = report.headers.filter { header in
            DateParsing.parse(header) != nil ||
                header.normalizedKey.contains("week") ||
                header.normalizedKey.contains("month") ||
                header.contains("周") ||
                header.contains("月")
        }
        if !temporalHeaders.isEmpty {
            return temporalHeaders.prefix(4).joined(separator: " / ")
        }
        return report.semanticProfile.grain.nilIfBlank ?? "未确认周期"
    }

    private static func maturityText(for report: ImportedReport) -> String {
        let partial = report.trendSummary.metricTrends.first { $0.latestPointIsPartial == true }
        if let partial {
            return partial.partialLatestPointReason ?? "最新周期未完整"
        }
        let text = searchableText(for: report)
        if text.contains("7日") || text.contains("7d") {
            return "包含 7 日成熟窗口指标"
        }
        if text.contains("3日") || text.contains("3d") {
            return "包含 3 日成熟窗口指标"
        }
        return "未发现特殊成熟窗口"
    }

    private static func domainRank(_ domain: String) -> Int {
        if domain.contains("投放") || domain.contains("安装") { return 10 }
        if domain.contains("页面") || domain.contains("埋点") { return 15 }
        if domain.contains("注册") { return 20 }
        if domain.contains("授信") || domain.contains("审核") { return 30 }
        if domain.contains("发卡") || domain.contains("激活") { return 40 }
        if domain.contains("消费") || domain.contains("交易") { return 50 }
        if domain.contains("留存") || domain.contains("活跃") { return 60 }
        if domain.contains("反馈") { return 70 }
        return 90
    }

    private static func relationText(sourceDomain: String, targetDomain: String) -> String {
        let sourceRank = domainRank(sourceDomain)
        let targetRank = domainRank(targetDomain)
        if sourceRank < targetRank { return "上游影响下游" }
        if sourceRank > targetRank { return "下游反映上游质量" }
        return "同业务域联动"
    }

    private static func lagDays(sourceDomain: String, targetDomain: String) -> Int? {
        let sourceRank = domainRank(sourceDomain)
        let targetRank = domainRank(targetDomain)
        guard sourceRank < targetRank else { return nil }
        if targetDomain.contains("消费") || targetDomain.contains("留存") { return 7 }
        if targetDomain.contains("授信") || targetDomain.contains("审核") { return 3 }
        return 1
    }

    private static func metricLagDays(sourceDomain: String, targetDomain: String) -> Int? {
        if sourceDomain.contains("页面") || sourceDomain.contains("埋点") { return 0 }
        return lagDays(sourceDomain: sourceDomain, targetDomain: targetDomain)
    }

    private static func metricRelationType(sourceDomain: String, targetDomain: String, relationScore: Int) -> CrossTableMetricRelationType {
        if sourceDomain.contains("页面") || sourceDomain.contains("埋点") {
            return .pageBehaviorImpact
        }
        let sourceRank = domainRank(sourceDomain)
        let targetRank = domainRank(targetDomain)
        if sourceRank < targetRank { return .upstreamDriver }
        if sourceRank > targetRank { return .downstreamOutcome }
        if relationScore >= 7 { return .sameFunnelStep }
        return .evidence
    }

    private static func metricRelationScore(
        sourceMetric: String,
        targetMetric: String,
        sourceDomain: String,
        targetDomain: String
    ) -> (score: Int, reason: String) {
        let source = sourceMetric.normalizedKey
        let target = targetMetric.normalizedKey
        guard !source.isEmpty, !target.isEmpty else { return (0, "指标名称为空") }

        var score = 0
        var reasons: [String] = []
        let sourceStages = businessStages(in: sourceMetric)
        let metricTargetStages = businessStages(in: targetMetric)
        let targetStages = metricTargetStages.isEmpty ? businessStages(in: targetDomain) : metricTargetStages
        let stageAffinity = stageAffinity(sourceStages: sourceStages, targetStages: targetStages)
        if source.contains(target) || target.contains(source) {
            score += 6
            reasons.append("指标名直接包含")
        }

        let overlap = tokens(in: source).intersection(tokens(in: target)).filter { !genericMetricTokens.contains($0) }
        if !overlap.isEmpty {
            score += min(3, overlap.count)
            reasons.append("共享关键词 \(overlap.sorted().prefix(3).joined(separator: "、"))")
        }

        var semanticHits: [String] = []
        for group in metricSemanticGroups {
            let sourceHit = group.contains { source.contains($0.normalizedKey) }
            let targetHit = group.contains { target.contains($0.normalizedKey) }
            if sourceHit, targetHit {
                score += 3
                semanticHits.append(group.first ?? "")
            }
        }
        if !semanticHits.isEmpty {
            reasons.append("同业务语义 \(semanticHits.prefix(2).joined(separator: "、"))")
        }

        if isPageBehaviorMetric(sourceMetric) && isBusinessOutcomeMetric(targetMetric, domain: targetDomain) {
            score += 2 + stageAffinity.score
            if stageAffinity.score > 0 {
                reasons.append("页面行为指标可作为业务结果上游，业务阶段匹配：\(stageAffinity.reason)")
            } else if sourceStages.isEmpty {
                reasons.append("页面行为指标可作为业务结果上游")
            } else {
                reasons.append("页面行为指标与目标业务阶段较远，仅作弱旁证")
            }
        }
        if domainRank(sourceDomain) < domainRank(targetDomain) {
            score += 1
            reasons.append("业务域顺序 \(sourceDomain) → \(targetDomain)")
        }

        return (score, reasons.isEmpty ? "同一分析任务内的候选指标" : reasons.joined(separator: "；"))
    }

    private static func directionAlignment(sourceTrend: ReportMetricTrend, targetTrend: ReportMetricTrend) -> (text: String, isSupportive: Bool) {
        if sourceTrend.direction == .flat || targetTrend.direction == .flat {
            return ("一方趋势平稳，只能作为弱旁证", false)
        }
        let negativeBehavior = containsAny(sourceTrend.metricName, ["错误", "失败", "报错", "crash", "error", "fail", "退出", "跳出", "bounce", "流失"])
        if negativeBehavior {
            let supportive = sourceTrend.direction != targetTrend.direction
            return supportive
                ? ("负向行为指标与业务结果反向变化，符合故障/流失解释", true)
                : ("负向行为指标与业务结果同向变化，需要排查口径或人群结构", false)
        }
        let supportive = sourceTrend.direction == targetTrend.direction
        return supportive
            ? ("上游行为与下游业务指标同向变化", true)
            : ("上游行为与下游业务指标反向变化，可作为反证或结构变化线索", false)
    }

    private static func periodCompatibility(sourceTrend: ReportMetricTrend, targetTrend: ReportMetricTrend) -> (isCompatible: Bool, reason: String) {
        let sourceLabel = sourceTrend.primaryComparison?.currentLabel.nilIfBlank ?? sourceTrend.trendEndLabel?.nilIfBlank
        let targetLabel = targetTrend.primaryComparison?.currentLabel.nilIfBlank ?? targetTrend.trendEndLabel?.nilIfBlank
        guard let sourceLabel, let targetLabel else {
            return (false, "周期可比性：缺少可比较的最新完整周期标签")
        }
        if sourceLabel.normalizedKey == targetLabel.normalizedKey {
            return (true, "周期可比性：最新完整周期一致（\(sourceLabel)）")
        }
        if DateParsing.parse(sourceLabel) != nil, DateParsing.parse(targetLabel) != nil {
            return (sourceLabel.normalizedKey == targetLabel.normalizedKey, "周期可比性：日期标签不一致（\(sourceLabel) vs \(targetLabel)）")
        }
        return (false, "周期可比性：周期标签不一致（\(sourceLabel) vs \(targetLabel)）")
    }

    private static func metricImpactScore(_ trend: ReportMetricTrend) -> Double {
        let primary = trend.primaryComparison?.percentChange ?? trend.percentChange
        if let primary {
            return abs(primary) * 100 + min(abs(trend.delta), 1_000) / 1_000
        }
        return min(abs(trend.delta), 10_000) / 1_000
    }

    private static func tokens(in text: String) -> Set<String> {
        let separators = CharacterSet(charactersIn: " _-/|:：,，;；()（）[]【】{}<>《》.+")
        return Set(text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).normalizedKey }
            .filter { $0.count >= 2 })
    }

    private static func isPageBehaviorMetric(_ value: String) -> Bool {
        containsAny(value, ["页面", "埋点", "曝光", "点击", "按钮", "提交", "停留", "报错", "event", "track", "page", "view", "click", "tap", "submit", "duration", "error"])
    }

    private static func isBusinessOutcomeMetric(_ value: String, domain: String) -> Bool {
        containsAny(value + " " + domain, ["注册", "申请", "开户", "授信", "审核", "审批", "发卡", "激活", "消费", "交易", "留存", "register", "signup", "apply", "submit", "credit", "approve", "activate", "purchase", "payment", "retention"])
    }

    private static func businessStages(in value: String) -> Set<String> {
        let normalized = value.normalizedKey
        let groups: [(stage: String, keywords: [String])] = [
            ("注册", ["注册", "register", "registration", "signup", "sign_up"]),
            ("申请", ["申请", "提审", "提交", "开户", "apply", "application", "submit", "open_account"]),
            ("授信/审核", ["授信", "审核", "审批", "额度", "credit", "approve", "approval", "risk"]),
            ("发卡/激活", ["发卡", "激活", "绑卡", "card", "activate", "activation"]),
            ("消费/交易", ["消费", "交易", "支付", "订单", "purchase", "payment", "gmv"]),
            ("留存/活跃", ["留存", "活跃", "复访", "retention", "active", "dau", "mau"])
        ]
        return Set(groups.compactMap { group in
            group.keywords.contains { normalized.contains($0.normalizedKey) } ? group.stage : nil
        })
    }

    private static func stageAffinity(sourceStages: Set<String>, targetStages: Set<String>) -> (score: Int, reason: String) {
        guard !sourceStages.isEmpty, !targetStages.isEmpty else { return (0, "缺少明确业务阶段") }
        let overlap = sourceStages.intersection(targetStages)
        if !overlap.isEmpty {
            return (5, overlap.sorted().joined(separator: "、"))
        }
        let order = ["注册", "申请", "授信/审核", "发卡/激活", "消费/交易", "留存/活跃"]
        let sourceRanks = sourceStages.compactMap { order.firstIndex(of: $0) }
        let targetRanks = targetStages.compactMap { order.firstIndex(of: $0) }
        guard let sourceRank = sourceRanks.min(), let targetRank = targetRanks.min() else {
            return (0, "业务阶段不可排序")
        }
        let distance = targetRank - sourceRank
        if distance == 1 {
            return (4, "\(order[sourceRank]) → \(order[targetRank])")
        }
        if distance == 2 {
            return (2, "\(order[sourceRank]) → \(order[targetRank])，存在中间环节")
        }
        if distance > 2 {
            return (0, "\(order[sourceRank]) → \(order[targetRank])，跨度较远")
        }
        return (0, "目标指标不是来源指标的下游阶段")
    }

    private static func metricLinkRankingScore(_ link: CrossTableMetricLink) -> Int {
        let source = link.sourceMetric.normalizedKey
        let target = link.targetMetric.normalizedKey
        let affinity = stageAffinity(
            sourceStages: businessStages(in: link.sourceMetric),
            targetStages: businessStages(in: link.targetMetric)
        )
        var score = affinity.score * 10

        if target.contains("注册用户数") { score += 18 }
        if target.contains("注册数") { score += 14 }
        if target.contains("提审核") || target.contains("提审") || target.contains("提交") { score += 12 }
        if target.contains("授信完成") || target.contains("授信") || target.contains("审核") { score += 10 }
        if target.contains("申请") { score += 6 }
        if target.contains("消费") || target.contains("交易") { score -= 8 }
        if target.contains("实体卡") || target.contains("虚拟卡") { score -= 4 }

        if source.contains("曝光"), target.contains("注册") { score += 10 }
        if (source.contains("点击") || source.contains("提交")),
           target.contains("注册") || target.contains("提审核") || target.contains("提审") || target.contains("申请") {
            score += 10
        }
        if source.contains("报错") || source.contains("错误") || source.contains("失败") {
            if target.contains("注册") || target.contains("提审核") || target.contains("授信") || target.contains("审核") {
                score += 8
            }
            if target.contains("消费") || target.contains("实体卡") {
                score -= 4
            }
        }
        return score
    }

    private static func containsAny(_ value: String, _ keywords: [String]) -> Bool {
        let normalized = value.normalizedKey
        return keywords.contains { normalized.contains($0.normalizedKey) }
    }

    private static func edgeEvidence(
        source: ImportedReport,
        target: ImportedReport,
        sourceNode: BusinessLinkNode?,
        targetNode: BusinessLinkNode?
    ) -> [String] {
        var evidence: [String] = []
        if let sourceNode, let targetNode {
            evidence.append("业务域顺序：\(sourceNode.businessDomain) → \(targetNode.businessDomain)")
        }
        let overlappingMetrics = Set(source.firstColumnValues.map(\.normalizedKey))
            .intersection(Set(target.firstColumnValues.map(\.normalizedKey)))
            .filter { !$0.isEmpty }
        if !overlappingMetrics.isEmpty {
            evidence.append("存在同名或相近指标标签 \(overlappingMetrics.prefix(3).joined(separator: "、"))")
        }
        if source.trendSummary.metricTrends.contains(where: { $0.latestPointIsPartial == true }) ||
            target.trendSummary.metricTrends.contains(where: { $0.latestPointIsPartial == true }) {
            evidence.append("至少一张表存在最新周期成熟度提醒")
        }
        if source.shape == target.shape {
            evidence.append("表格结构同为 \(source.shape.label)")
        }
        return evidence.isEmpty ? ["同一分析任务内人工选择"] : evidence.uniqued()
    }

    private static func edgeConfidence(source: ImportedReport, target: ImportedReport, evidenceCount: Int) -> Double {
        let base = min(source.detectedConfidence, target.detectedConfidence)
        return min(0.92, max(0.45, base * 0.72 + Double(evidenceCount) * 0.08))
    }

    private static func summary(
        reports: [ImportedReport],
        nodes: [BusinessLinkNode],
        edges: [BusinessLinkEdge],
        metricLinks: [CrossTableMetricLink],
        anomalies: [MetricLinkageAnomaly]
    ) -> String {
        let domains = nodes.map(\.businessDomain).uniqued()
        if reports.count == 1 {
            return "当前任务为单表分析：\(reports[0].displayName)，业务域识别为 \(domains.first ?? "未确认")。"
        }
        let edgeText = edges.isEmpty ? "暂无明确影响边" : "\(edges.count) 条候选影响边"
        let metricText = metricLinks.isEmpty ? "未发现可靠指标联动" : "\(metricLinks.count) 条候选指标联动"
        let anomalyText = anomalies.isEmpty ? "未发现高价值指标联动异常" : "\(anomalies.count) 个指标联动异常候选"
        return "当前任务包含 \(reports.count) 张表，覆盖 \(domains.joined(separator: "、"))，已生成 \(edgeText)、\(metricText)、\(anomalyText)，确认后会作为 AI 分析证据。"
    }

    private static func edgeKey(_ edge: BusinessLinkEdge) -> String {
        "\(edge.sourceReportID.uuidString)|\(edge.targetReportID.uuidString)|\(edge.relationType.normalizedKey)"
    }

    private static func metricLinkKey(_ link: CrossTableMetricLink) -> String {
        [
            link.sourceReportID.uuidString,
            link.sourceMetric.normalizedKey,
            link.targetReportID.uuidString,
            link.targetMetric.normalizedKey,
            link.relationType.rawValue
        ].joined(separator: "|")
    }

    private static let metricSemanticGroups: [[String]] = [
        ["注册", "register", "registration", "signup", "sign_up"],
        ["转化", "conversion", "funnel", "漏斗"],
        ["申请", "application", "apply", "submit", "提交"],
        ["开户", "account_open", "open_account"],
        ["激活", "activation", "activate"],
        ["授信", "credit", "approval", "approve", "审批", "审核"],
        ["曝光", "impression", "exposure", "view", "pv"],
        ["点击", "click", "tap", "ctr"],
        ["停留", "duration", "stay"],
        ["错误", "error", "crash", "失败", "fail", "报错"],
        ["发卡", "card", "issue"],
        ["消费", "purchase", "payment", "交易", "gmv"],
        ["留存", "retention", "return", "活跃"]
    ]

    private static let genericMetricTokens: Set<String> = [
        "指标", "数据", "字段", "名称", "日期", "时间", "周期", "区间", "维度", "类型",
        "metric", "metrics", "data", "field", "name", "date", "time", "period", "dimension", "type",
        "week", "month", "day", "value", "count"
    ]
}
