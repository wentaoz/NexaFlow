import Foundation

enum MetricLinkageAnomalyScanner {
    struct ScanResult {
        var periodIntent: AnalysisPeriodIntent
        var anomalies: [MetricLinkageAnomaly]
        var scannedMetricCount: Int
    }

    private struct MetricComparison {
        var report: ImportedReport
        var domain: String
        var metricName: String
        var previousLabel: String
        var currentLabel: String
        var previousValue: Double
        var currentValue: Double
        var delta: Double
        var percentChange: Double?
        var direction: ChangeDirection
        var isComparable: Bool
        var incomparabilityReason: String
        var confidence: Double
        var evidenceLevel: EvidenceLevel
        var limitations: [String]

        var absolutePercentChange: Double {
            abs(percentChange ?? 0)
        }
    }

    static func extractPeriodIntent(
        userRequest: String,
        taskGoal: String,
        reports: [ImportedReport]
    ) -> AnalysisPeriodIntent {
        let knownLabels = knownPeriodLabels(from: reports)
        if !excludesLatestPeriod(userRequest),
           let intent = relativePeriodIntent(from: userRequest, reports: reports) {
            return intent
        }
        if let intent = intent(from: userRequest, source: .userMessage, knownLabels: knownLabels) {
            return intent
        }
        if let intent = intent(from: taskGoal, source: .taskGoal, knownLabels: knownLabels) {
            return intent
        }
        return .unspecifiedOverview
    }

    static func scan(
        reports: [ImportedReport],
        task: AnalysisTask?,
        periodIntent: AnalysisPeriodIntent? = nil
    ) -> ScanResult {
        let activeReports = reports.filter { report in
            guard let task else { return true }
            return task.activeReportIDs.contains(report.id) && task.role(for: report.id) != .excluded
        }
        let intent = periodIntent ?? extractPeriodIntent(userRequest: "", taskGoal: task?.goal ?? "", reports: activeReports)
        let scannedMetricCount = activeReports.reduce(0) { total, report in
            total + report.trendSummary.metricTrends.count
        }
        guard intent.requestedPeriods.count >= 2 else {
            return ScanResult(periodIntent: intent, anomalies: [], scannedMetricCount: scannedMetricCount)
        }
        let nodeByID = Dictionary(uniqueKeysWithValues: (task?.businessLinkProfile.nodes ?? []).map { ($0.reportID, $0) })
        let metricComparisons = activeReports.flatMap { report in
            comparisons(for: report, domain: nodeByID[report.id]?.businessDomain ?? inferredDomain(for: report), periodIntent: intent)
        }

        guard metricComparisons.count >= 2 else {
            return ScanResult(periodIntent: intent, anomalies: [], scannedMetricCount: metricComparisons.count)
        }

        var candidates: [MetricLinkageAnomaly] = []
        for sourceIndex in metricComparisons.indices {
            for targetIndex in metricComparisons.indices where targetIndex > sourceIndex {
                let lhs = metricComparisons[sourceIndex]
                let rhs = metricComparisons[targetIndex]
                guard lhs.report.id != rhs.report.id else { continue }
                let ordered = orderedPair(lhs, rhs)
                candidates.append(contentsOf: anomalies(source: ordered.source, target: ordered.target, periodIntent: intent))
            }
        }

        let selected = candidates
            .uniquedByStableKey { anomalyKey($0) }
            .sorted { lhs, rhs in
                if abs(lhs.confidence - rhs.confidence) > 0.02 { return lhs.confidence > rhs.confidence }
                if lhs.evidenceLevel != rhs.evidenceLevel { return lhs.evidenceLevel.rawValue < rhs.evidenceLevel.rawValue }
                return lhs.changeGapText > rhs.changeGapText
            }
            .prefix(80)

        return ScanResult(periodIntent: intent, anomalies: Array(selected), scannedMetricCount: metricComparisons.count)
    }

    static func stableKey(for anomaly: MetricLinkageAnomaly) -> String {
        anomalyKey(anomaly)
    }

    private static func comparisons(
        for report: ImportedReport,
        domain: String,
        periodIntent: AnalysisPeriodIntent
    ) -> [MetricComparison] {
        let package = TableContextPackageBuilder.build(for: report)
        return report.trendSummary.metricTrends.compactMap { trend in
            if let comparison = requestedComparison(for: trend, in: package, requestedPeriods: periodIntent.requestedPeriods) {
                return comparisonValue(report: report, domain: domain, trend: trend, comparison: comparison, periodIntent: periodIntent)
            }
            return nil
        }
    }

    private static func comparisonValue(
        report: ImportedReport,
        domain: String,
        trend: ReportMetricTrend,
        comparison: PrimaryMetricComparison,
        periodIntent: AnalysisPeriodIntent
    ) -> MetricComparison {
        var limitations: [String] = []
        if !comparison.isComparable {
            limitations.append(comparison.incomparabilityReason.nilIfBlank ?? "周期不可比")
        }
        if trend.latestPointIsPartial == true {
            limitations.append(trend.partialLatestPointReason ?? "最新周期未完整")
        }
        if periodIntent.isUserSpecified, periodIntent.allowsIncompletePeriod {
            limitations.append("用户指定观察周期可能包含未完整周期，需由 AI 复核完整性。")
        }
        return MetricComparison(
            report: report,
            domain: domain,
            metricName: trend.metricName,
            previousLabel: comparison.previousLabel,
            currentLabel: comparison.currentLabel,
            previousValue: comparison.previousValue,
            currentValue: comparison.currentValue,
            delta: comparison.delta,
            percentChange: comparison.percentChange,
            direction: comparison.direction,
            isComparable: comparison.isComparable,
            incomparabilityReason: comparison.incomparabilityReason,
            confidence: comparison.confidence,
            evidenceLevel: comparison.evidenceLevel,
            limitations: limitations
        )
    }

    private static func requestedComparison(
        for trend: ReportMetricTrend,
        in package: TableContextPackage,
        requestedPeriods: [String]
    ) -> PrimaryMetricComparison? {
        guard requestedPeriods.count >= 2 else { return nil }
        guard let series = package.dataPayload.metricSeries.first(where: { $0.metricName.normalizedKey == trend.metricName.normalizedKey }) else {
            return nil
        }
        guard let current = series.points.first(where: { periodMatches($0.label, requestedPeriods[0]) }),
              let previous = series.points.first(where: { periodMatches($0.label, requestedPeriods[1]) }),
              let currentValue = current.value,
              let previousValue = previous.value else {
            return nil
        }
        let delta = currentValue - previousValue
        let percentChange = previousValue == 0 ? nil : delta / abs(previousValue)
        let direction: ChangeDirection
        if abs(delta) < max(0.000001, abs(previousValue) * 0.005) {
            direction = .flat
        } else {
            direction = delta > 0 ? .up : .down
        }
        return PrimaryMetricComparison(
            previousLabel: previous.label,
            currentLabel: current.label,
            previousValue: previousValue,
            currentValue: currentValue,
            delta: delta,
            percentChange: percentChange,
            direction: direction,
            isComparable: true,
            incomparabilityReason: "",
            confidence: current.isPartial || previous.isPartial ? 0.52 : 0.74,
            evidenceLevel: current.isPartial || previous.isPartial ? .d : .c
        )
    }

    private static func anomalies(
        source: MetricComparison,
        target: MetricComparison,
        periodIntent: AnalysisPeriodIntent
    ) -> [MetricLinkageAnomaly] {
        let relation = relationScore(source: source, target: target)
        let periodCompatible = source.currentLabel.normalizedKey == target.currentLabel.normalizedKey &&
            source.previousLabel.normalizedKey == target.previousLabel.normalizedKey
        var result: [MetricLinkageAnomaly] = []

        if !periodCompatible || !source.isComparable || !target.isComparable {
            if relation.score >= 2 {
                result.append(makeAnomaly(
                    type: .periodOrDefinitionMismatch,
                    source: source,
                    target: target,
                    relation: relation.text,
                    confidence: 0.42,
                    explanations: ["周期、口径或人群可能不可比，需要 AI 基于原始表格和业务背景复核。"],
                    limitations: ["来源周期：\(source.previousLabel) -> \(source.currentLabel)", "目标周期：\(target.previousLabel) -> \(target.currentLabel)"] + source.limitations + target.limitations
                ))
            }
            return result
        }

        let sourceAbs = source.absolutePercentChange
        let targetAbs = target.absolutePercentChange
        let gap = abs(sourceAbs - targetAbs)
        let sourceBigMove = sourceAbs >= 0.15
        let targetBigMove = targetAbs >= 0.15
        let targetNotFollowing = targetAbs <= 0.05
        let oppositeDirection = source.direction != .flat && target.direction != .flat && source.direction != target.direction

        if sourceBigMove, targetNotFollowing, gap >= 0.10, relation.score >= 2 {
            result.append(makeAnomaly(
                type: relation.isCrossDomain ? .crossDomainHandoffGap : .growthNotTransmitted,
                source: source,
                target: target,
                relation: relation.text,
                confidence: confidence(base: 0.62, source: source, target: target, relationScore: relation.score, periodIntent: periodIntent),
                explanations: [
                    "上游或相关指标变化明显，但目标指标没有同步变化。",
                    relation.isCrossDomain ? "可能是跨业务承接不足，也可能是业务域、人群或入口不一致。" : "可能是链路中间环节断点或口径差异。"
                ],
                limitations: source.limitations + target.limitations + periodWarnings(periodIntent)
            ))
        }

        if oppositeDirection, (sourceBigMove || targetBigMove), relation.score >= 2 {
            result.append(makeAnomaly(
                type: .directionConflict,
                source: source,
                target: target,
                relation: relation.text,
                confidence: confidence(base: 0.58, source: source, target: target, relationScore: relation.score, periodIntent: periodIntent),
                explanations: ["两个理论相关指标方向相反，可能是反证、结构变化、渠道变化或口径不可比。"],
                limitations: source.limitations + target.limitations + periodWarnings(periodIntent)
            ))
        }

        if isRatioDecoupling(source.metricName, target.metricName), gap >= 0.10, relation.score >= 1 {
            result.append(makeAnomaly(
                type: .ratioDecoupling,
                source: source,
                target: target,
                relation: relation.text,
                confidence: confidence(base: 0.56, source: source, target: target, relationScore: relation.score, periodIntent: periodIntent),
                explanations: ["分子、分母或比例指标变化不同步，需要拆解构成项和样本结构。"],
                limitations: source.limitations + target.limitations + periodWarnings(periodIntent)
            ))
        }

        if isAdjacentFunnel(source: source, target: target), sourceBigMove, target.direction != .up {
            result.append(makeAnomaly(
                type: .funnelBreak,
                source: source,
                target: target,
                relation: relation.text,
                confidence: confidence(base: 0.64, source: source, target: target, relationScore: relation.score + 2, periodIntent: periodIntent),
                explanations: ["漏斗前段增长没有传到后段，可能存在中间环节转化断点。"],
                limitations: source.limitations + target.limitations + periodWarnings(periodIntent)
            ))
        }

        if isMixShiftMetric(source.metricName) || isMixShiftMetric(target.metricName) || isMixShiftMetric(source.report.displayName) || isMixShiftMetric(target.report.displayName) {
            if sourceBigMove || targetBigMove || oppositeDirection {
                result.append(makeAnomaly(
                    type: .mixShiftOrCohortMismatch,
                    source: source,
                    target: target,
                    relation: relation.text,
                    confidence: confidence(base: 0.48, source: source, target: target, relationScore: relation.score, periodIntent: periodIntent),
                    explanations: ["指标可能受渠道、人群、版本、供应商或 cohort 结构变化影响。"],
                    limitations: source.limitations + target.limitations + periodWarnings(periodIntent)
                ))
            }
        }

        if isExternalDriverCandidate(source.metricName + source.report.displayName) || isExternalDriverCandidate(target.metricName + target.report.displayName) {
            if sourceBigMove || targetBigMove {
                result.append(makeAnomaly(
                    type: .externalIndependentDriver,
                    source: source,
                    target: target,
                    relation: relation.text,
                    confidence: confidence(base: 0.44, source: source, target: target, relationScore: relation.score, periodIntent: periodIntent),
                    explanations: ["该指标可能由天气、用电、节假日、政策、竞品或其他外部事件独立驱动，需要匹配外部事件发生时间。"],
                    limitations: source.limitations + target.limitations + periodWarnings(periodIntent)
                ))
            }
        }

        return result
    }

    private static func makeAnomaly(
        type: MetricLinkageAnomalyType,
        source: MetricComparison,
        target: MetricComparison,
        relation: String,
        confidence: Double,
        explanations: [String],
        limitations: [String]
    ) -> MetricLinkageAnomaly {
        let evidenceLevel: EvidenceLevel
        if confidence >= 0.74 {
            evidenceLevel = .b
        } else if confidence >= 0.56 {
            evidenceLevel = .c
        } else {
            evidenceLevel = .d
        }
        return MetricLinkageAnomaly(
            anomalyType: type,
            sourceReportID: source.report.id,
            sourceReportName: source.report.displayName,
            sourceMetric: source.metricName,
            targetReportID: target.report.id,
            targetReportName: target.report.displayName,
            targetMetric: target.metricName,
            sourceChangeText: changeText(source),
            targetChangeText: changeText(target),
            comparisonPeriod: "\(source.currentLabel) vs \(source.previousLabel)",
            changeGapText: gapText(source, target),
            businessRelation: relation,
            possibleExplanations: explanations,
            evidenceLevel: evidenceLevel,
            confidence: confidence,
            limitations: limitations.uniqued()
        )
    }

    private static func confidence(
        base: Double,
        source: MetricComparison,
        target: MetricComparison,
        relationScore: Int,
        periodIntent: AnalysisPeriodIntent
    ) -> Double {
        var value = base + Double(min(relationScore, 8)) * 0.035
        value += min(source.confidence, target.confidence) * 0.12
        if periodIntent.isUserSpecified, periodIntent.allowsIncompletePeriod { value -= 0.1 }
        if !source.limitations.isEmpty || !target.limitations.isEmpty { value -= 0.08 }
        return min(0.9, max(0.32, value))
    }

    private static func orderedPair(_ lhs: MetricComparison, _ rhs: MetricComparison) -> (source: MetricComparison, target: MetricComparison) {
        let lhsRank = domainRank(lhs.domain)
        let rhsRank = domainRank(rhs.domain)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank ? (lhs, rhs) : (rhs, lhs)
        }
        if lhs.absolutePercentChange != rhs.absolutePercentChange {
            return lhs.absolutePercentChange > rhs.absolutePercentChange ? (lhs, rhs) : (rhs, lhs)
        }
        return lhs.metricName < rhs.metricName ? (lhs, rhs) : (rhs, lhs)
    }

    private static func relationScore(source: MetricComparison, target: MetricComparison) -> (score: Int, text: String, isCrossDomain: Bool) {
        var score = 0
        var reasons: [String] = []
        if source.domain != target.domain {
            score += 2
            reasons.append("\(source.domain) → \(target.domain)")
        } else {
            score += 1
            reasons.append("同业务域 \(source.domain)")
        }
        let affinity = stageAffinity(sourceStages: businessStages(in: source.metricName + source.domain), targetStages: businessStages(in: target.metricName + target.domain))
        score += affinity.score
        if affinity.score > 0 { reasons.append(affinity.reason) }
        let overlap = tokens(in: source.metricName).intersection(tokens(in: target.metricName)).filter { !genericTokens.contains($0) }
        if !overlap.isEmpty {
            score += min(3, overlap.count)
            reasons.append("共享关键词 \(overlap.sorted().prefix(3).joined(separator: "、"))")
        }
        if isPageBehaviorMetric(source.metricName) && isBusinessOutcomeMetric(target.metricName + target.domain) {
            score += 3
            reasons.append("页面行为可作为业务结果上游")
        }
        return (score, reasons.joined(separator: "；").nilIfBlank ?? "当前任务内候选关系", source.domain != target.domain)
    }

    private static func intent(from text: String, source: AnalysisPeriodIntentSource, knownLabels: [String]) -> AnalysisPeriodIntent? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let orderedKnown = orderedLabelMatches(in: trimmed, labels: knownLabels)
        let dateRanges = dateRangeMatches(in: trimmed)
        let requested = (orderedKnown + dateRanges).uniqued()
        let excludesLatest = excludesLatestPeriod(trimmed)
        guard !requested.isEmpty || excludesLatest else { return nil }
        let incomplete = requested.contains { containsAny($0, ["未完整", "不完整", "仅", "最新"]) } || containsAny(trimmed, ["强制", "也看", "观察最新", "未完整"])
        let summary: String
        if requested.count >= 2 {
            summary = "\(source.label)：\(requested[0]) vs \(requested[1])。"
        } else if requested.count == 1 {
            summary = "\(source.label)：观察 \(requested[0])。"
        } else {
            summary = "\(source.label)：用户要求排除部分周期，但未指定明确分析期；本轮只做全周期概览。"
        }
        return AnalysisPeriodIntent(
            source: source,
            summary: summary,
            requestedPeriods: requested,
            excludedPeriods: excludesLatest ? ["最新周期"] : [],
            isUserSpecified: source == .userMessage,
            allowsIncompletePeriod: incomplete,
            warnings: incomplete ? ["用户指定周期可能未完整，AI 必须标注完整性和置信限制。"] : []
        )
    }

    private static func relativePeriodIntent(from text: String, reports: [ImportedReport]) -> AnalysisPeriodIntent? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard containsLatestPeriodRequest(trimmed) else { return nil }

        let periods = latestComparablePeriods(from: reports)
        if periods.count >= 2 {
            let requested = Array(periods.prefix(2))
            return AnalysisPeriodIntent(
                source: .userMessage,
                summary: "用户本轮指定周期：表内最新周期 \(requested[0]) vs 上一周期 \(requested[1])。",
                requestedPeriods: requested,
                excludedPeriods: [],
                isUserSpecified: true,
                allowsIncompletePeriod: true,
                warnings: ["用户要求分析最新周期，已按当前选表中可排序周期解析；如果最新周期未完整，AI 必须标注完整性和置信限制。"]
            )
        }
        if let latest = periods.first {
            return AnalysisPeriodIntent(
                source: .userMessage,
                summary: "用户本轮指定周期：观察表内最新周期 \(latest)。",
                requestedPeriods: [latest],
                excludedPeriods: [],
                isUserSpecified: true,
                allowsIncompletePeriod: true,
                warnings: ["用户要求分析最新周期，但当前选表只识别到 1 个可排序周期，AI 不能沿用任务目标里的旧周期。"]
            )
        }
        return AnalysisPeriodIntent(
            source: .userMessage,
            summary: "用户本轮要求分析最新周期，但当前选表未识别到可排序周期；本轮不能沿用任务目标里的旧周期。",
            requestedPeriods: [],
            excludedPeriods: [],
            isUserSpecified: true,
            allowsIncompletePeriod: true,
            warnings: ["用户要求最新周期，但当前选表未识别到可排序周期；请让用户确认周期字段或先刷新表格时间画像。"]
        )
    }

    private static func containsLatestPeriodRequest(_ text: String) -> Bool {
        let normalized = text.normalizedKey
        guard !normalized.isEmpty else { return false }
        if containsAny(text, [
            "最新周期", "最近周期", "最新一期", "最近一期", "最新一周期", "最近一周期",
            "最新一个周期", "最近一个周期", "最新月份", "最近月份", "最新一周", "最近一周",
            "latest period", "latest cycle", "latest window", "most recent period"
        ]) {
            return true
        }
        let hasRelative = containsAny(text, ["最新", "最近", "本期", "当前周期", "当前月份", "当前周"])
        let hasPeriodNoun = containsAny(text, ["周期", "一期", "月份", "月", "周", "时间", "数据", "period", "cycle", "window"])
        return hasRelative && hasPeriodNoun
    }

    private static func excludesLatestPeriod(_ text: String) -> Bool {
        containsAny(text, ["不要看最新", "不看最新", "排除最新", "剔除最新", "不要用最新"])
    }

    private static func latestComparablePeriods(from reports: [ImportedReport]) -> [String] {
        let candidates = periodCandidates(from: reports)
        var seen: Set<String> = []
        var result: [String] = []
        for candidate in candidates.sorted(by: periodCandidateSortDescending) {
            let key = simplifiedPeriod(candidate.label).normalizedKey
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(candidate.label)
        }
        return result
    }

    private static func periodCandidateSortDescending(
        _ lhs: (label: String, start: Date, end: Date),
        _ rhs: (label: String, start: Date, end: Date)
    ) -> Bool {
        if lhs.end != rhs.end { return lhs.end > rhs.end }
        if lhs.start != rhs.start { return lhs.start > rhs.start }
        return lhs.label.localizedStandardCompare(rhs.label) == .orderedDescending
    }

    private static func periodCandidates(from reports: [ImportedReport]) -> [(label: String, start: Date, end: Date)] {
        var candidates: [(label: String, start: Date, end: Date)] = []

        func add(_ label: String?, fallbackStart: Date? = nil, fallbackEnd: Date? = nil) {
            guard let label = label?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !label.isEmpty,
                  let range = sortablePeriodRange(label, fallbackStart: fallbackStart, fallbackEnd: fallbackEnd) else {
                return
            }
            candidates.append((label: label, start: range.start, end: range.end))
        }

        for report in reports {
            for trend in report.trendSummary.metricTrends {
                add(trend.trendStartLabel, fallbackStart: trend.trendStartDate, fallbackEnd: trend.trendStartDate)
                add(trend.trendEndLabel, fallbackStart: trend.trendEndDate, fallbackEnd: trend.trendEndDate)
                add(trend.partialLatestLabel)
                add(trend.primaryComparison?.currentLabel)
                add(trend.primaryComparison?.previousLabel)
                for excluded in trend.excludedPeriods ?? [] {
                    add(excluded.label)
                }
            }
            for header in report.headers {
                add(header)
            }
            for value in report.firstColumnValues {
                add(value)
            }
        }

        return candidates
    }

    private static func sortablePeriodRange(
        _ label: String,
        fallbackStart: Date? = nil,
        fallbackEnd: Date? = nil
    ) -> (start: Date, end: Date)? {
        if let range = DateParsing.periodRange(label) {
            return range
        }
        if let halfYear = halfYearRange(label) {
            return halfYear
        }
        if let quarter = quarterRange(label) {
            return quarter
        }
        if let month = monthRange(label) {
            return month
        }
        if let date = DateParsing.parse(label) {
            return (date, date)
        }
        if let start = fallbackStart ?? fallbackEnd,
           let end = fallbackEnd ?? fallbackStart {
            return start <= end ? (start, end) : (end, start)
        }
        return nil
    }

    private static func halfYearRange(_ label: String) -> (start: Date, end: Date)? {
        let normalized = label
            .replacingOccurrences(of: "年", with: " ")
            .replacingOccurrences(of: "上半年", with: " H1")
            .replacingOccurrences(of: "下半年", with: " H2")
        let patterns = [
            #"(?i)(\d{4})\s*[-_/]?\s*H\s*([12])"#,
            #"(?i)H\s*([12])\s*[-_/]?\s*(\d{4})"#
        ]
        for pattern in patterns {
            guard let groups = regexGroups(pattern, in: normalized) else { continue }
            let yearText: String
            let halfText: String
            if pattern.hasPrefix("(?i)(\\d{4})") {
                yearText = groups[0]
                halfText = groups[1]
            } else {
                halfText = groups[0]
                yearText = groups[1]
            }
            guard let year = Int(yearText),
                  let half = Int(halfText) else { continue }
            let startMonth = half == 1 ? 1 : 7
            let endMonth = half == 1 ? 6 : 12
            guard let start = date(year: year, month: startMonth, day: 1),
                  let end = lastDay(year: year, month: endMonth) else { continue }
            return (start, end)
        }
        return nil
    }

    private static func quarterRange(_ label: String) -> (start: Date, end: Date)? {
        let normalized = label
            .replacingOccurrences(of: "年", with: " ")
            .replacingOccurrences(of: "季度", with: "Q")
            .replacingOccurrences(of: "第", with: "")
        let patterns = [
            #"(?i)(\d{4})\s*[-_/]?\s*Q\s*([1-4])"#,
            #"(?i)Q\s*([1-4])\s*[-_/]?\s*(\d{4})"#
        ]
        for pattern in patterns {
            guard let groups = regexGroups(pattern, in: normalized) else { continue }
            let yearText: String
            let quarterText: String
            if pattern.hasPrefix("(?i)(\\d{4})") {
                yearText = groups[0]
                quarterText = groups[1]
            } else {
                quarterText = groups[0]
                yearText = groups[1]
            }
            guard let year = Int(yearText),
                  let quarter = Int(quarterText) else { continue }
            let startMonth = (quarter - 1) * 3 + 1
            let endMonth = startMonth + 2
            guard let start = date(year: year, month: startMonth, day: 1),
                  let end = lastDay(year: year, month: endMonth) else { continue }
            return (start, end)
        }
        return nil
    }

    private static func monthRange(_ label: String) -> (start: Date, end: Date)? {
        let normalized = label
            .replacingOccurrences(of: "年", with: "-")
            .replacingOccurrences(of: "月", with: "")
        guard let groups = regexGroups(#"(?<!\d)(\d{4})[-/.](\d{1,2})(?![-/.\d])"#, in: normalized),
              let year = Int(groups[0]),
              let month = Int(groups[1]),
              let start = date(year: year, month: month, day: 1),
              let end = lastDay(year: year, month: month) else {
            return nil
        }
        return (start, end)
    }

    private static func regexGroups(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let valueRange = Range(match.range(at: index), in: text) else { return nil }
            return String(text[valueRange])
        }
    }

    private static func date(year: Int, month: Int, day: Int) -> Date? {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func lastDay(year: Int, month: Int) -> Date? {
        let calendar = Calendar(identifier: .gregorian)
        guard let start = date(year: year, month: month, day: 1),
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: start),
              let end = calendar.date(byAdding: .day, value: -1, to: nextMonth) else {
            return nil
        }
        return end
    }

    private static func knownPeriodLabels(from reports: [ImportedReport]) -> [String] {
        reports.flatMap { report in
            let trendLabels = report.trendSummary.metricTrends.flatMap { trend in
                [
                    trend.primaryComparison?.currentLabel,
                    trend.primaryComparison?.previousLabel,
                    trend.trendStartLabel,
                    trend.trendEndLabel,
                    trend.partialLatestLabel
                ].compactMap { $0 }
            }
            let headerLabels = report.headers.filter { header in
                sortablePeriodRange(header) != nil || containsAny(header, ["202"])
            }
            return trendLabels + headerLabels
        }.uniqued()
    }

    private static func orderedLabelMatches(in text: String, labels: [String]) -> [String] {
        let normalizedText = simplifiedPeriod(text).normalizedKey
        let matches = labels.compactMap { label -> (String, String.Index)? in
            let simplified = simplifiedPeriod(label).normalizedKey
            guard !simplified.isEmpty,
                  let range = normalizedText.range(of: simplified) else { return nil }
            return (label, range.lowerBound)
        }
        return matches.sorted { $0.1 < $1.1 }.map(\.0)
    }

    private static func dateRangeMatches(in text: String) -> [String] {
        let pattern = #"\d{4}[/-]\d{1,2}[/-]\d{1,2}\s*(?:-|~|至|到|—|–)\s*(?:\d{4}[/-])?\d{1,2}[/-]\d{1,2}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let valueRange = Range(match.range, in: text) else { return nil }
            return String(text[valueRange])
        }
    }

    private static func simplifiedPeriod(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"（[^）]*）"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func periodMatches(_ lhs: String, _ rhs: String) -> Bool {
        let left = simplifiedPeriod(lhs).normalizedKey
        let right = simplifiedPeriod(rhs).normalizedKey
        return left == right || left.contains(right) || right.contains(left)
    }

    private static func periodWarnings(_ intent: AnalysisPeriodIntent) -> [String] {
        intent.warnings + (intent.excludedPeriods.isEmpty ? [] : ["用户要求排除：\(intent.excludedPeriods.joined(separator: "、"))"])
    }

    private static func changeText(_ value: MetricComparison) -> String {
        if let percent = value.percentChange {
            return "\(value.previousValue.compactText) -> \(value.currentValue.compactText)，\(percentText(percent))，\(value.direction.rawValue)"
        }
        return "\(value.previousValue.compactText) -> \(value.currentValue.compactText)，变化 \(value.delta.compactText)，\(value.direction.rawValue)"
    }

    private static func gapText(_ source: MetricComparison, _ target: MetricComparison) -> String {
        let gap = abs(source.absolutePercentChange - target.absolutePercentChange)
        return "相对变化差 \(percentText(gap))（\(source.metricName)：\(percentText(source.percentChange ?? 0))；\(target.metricName)：\(percentText(target.percentChange ?? 0))）"
    }

    private static func percentText(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(DateFormatting.percent.string(from: NSNumber(value: value)) ?? value.compactText)"
    }

    private static func anomalyKey(_ anomaly: MetricLinkageAnomaly) -> String {
        [
            anomaly.anomalyType.rawValue,
            anomaly.sourceReportID.uuidString,
            anomaly.sourceMetric.normalizedKey,
            anomaly.targetReportID.uuidString,
            anomaly.targetMetric.normalizedKey,
            anomaly.comparisonPeriod.normalizedKey
        ].joined(separator: "|")
    }

    private static func inferredDomain(for report: ImportedReport) -> String {
        let text = [report.fileName, report.kind.label, report.semanticProfile.summary, report.headers.joined(separator: " "), report.firstColumnValues.joined(separator: " ")].joined(separator: " ")
        if containsAny(text, ["埋点", "事件", "页面", "点击", "曝光", "event", "page", "click"]) { return "页面埋点" }
        if containsAny(text, ["投放", "广告", "安装", "install", "campaign"]) { return "投放/安装" }
        if containsAny(text, ["注册", "signup", "register"]) { return "注册" }
        if containsAny(text, ["申请", "提审", "提交"]) { return "申请/提交" }
        if containsAny(text, ["授信", "审核", "审批", "credit", "approve"]) { return "授信/审核" }
        if containsAny(text, ["消费", "交易", "支付", "缴费", "payment", "purchase"]) { return "消费/交易" }
        if containsAny(text, ["留存", "活跃", "retention"]) { return "留存/活跃" }
        return report.kind.label
    }

    private static func domainRank(_ domain: String) -> Int {
        if containsAny(domain, ["投放", "安装"]) { return 10 }
        if containsAny(domain, ["页面", "埋点"]) { return 15 }
        if containsAny(domain, ["注册"]) { return 20 }
        if containsAny(domain, ["申请", "提交"]) { return 25 }
        if containsAny(domain, ["授信", "审核"]) { return 30 }
        if containsAny(domain, ["发卡", "激活"]) { return 40 }
        if containsAny(domain, ["消费", "交易", "支付", "缴费"]) { return 50 }
        if containsAny(domain, ["留存", "活跃"]) { return 60 }
        return 80
    }

    private static func businessStages(in value: String) -> Set<String> {
        let normalized = value.normalizedKey
        let groups: [(stage: String, keywords: [String])] = [
            ("注册", ["注册", "register", "registration", "signup"]),
            ("申请", ["申请", "提审", "提交", "开户", "apply", "submit"]),
            ("授信/审核", ["授信", "审核", "审批", "额度", "credit", "approve", "risk"]),
            ("发卡/激活", ["发卡", "激活", "绑卡", "card", "activate"]),
            ("消费/交易", ["消费", "交易", "支付", "缴费", "订单", "purchase", "payment", "gmv"]),
            ("留存/活跃", ["留存", "活跃", "复访", "retention", "active", "dau", "mau"])
        ]
        return Set(groups.compactMap { group in
            group.keywords.contains { normalized.contains($0.normalizedKey) } ? group.stage : nil
        })
    }

    private static func stageAffinity(sourceStages: Set<String>, targetStages: Set<String>) -> (score: Int, reason: String) {
        guard !sourceStages.isEmpty, !targetStages.isEmpty else { return (0, "缺少明确业务阶段") }
        let overlap = sourceStages.intersection(targetStages)
        if !overlap.isEmpty { return (5, overlap.sorted().joined(separator: "、")) }
        let order = ["注册", "申请", "授信/审核", "发卡/激活", "消费/交易", "留存/活跃"]
        let sourceRanks = sourceStages.compactMap { order.firstIndex(of: $0) }
        let targetRanks = targetStages.compactMap { order.firstIndex(of: $0) }
        guard let sourceRank = sourceRanks.min(), let targetRank = targetRanks.min() else { return (0, "业务阶段不可排序") }
        let distance = targetRank - sourceRank
        if distance == 1 { return (4, "\(order[sourceRank]) → \(order[targetRank])") }
        if distance == 2 { return (2, "\(order[sourceRank]) → \(order[targetRank])，存在中间环节") }
        if distance > 2 { return (1, "\(order[sourceRank]) → \(order[targetRank])，跨度较远") }
        return (0, "目标指标不是来源指标的下游阶段")
    }

    private static func isAdjacentFunnel(source: MetricComparison, target: MetricComparison) -> Bool {
        stageAffinity(sourceStages: businessStages(in: source.metricName + source.domain), targetStages: businessStages(in: target.metricName + target.domain)).score >= 4
    }

    private static func isRatioDecoupling(_ lhs: String, _ rhs: String) -> Bool {
        let ratioKeywords = ["率", "占比", "%", "/", "rate", "ratio", "conversion"]
        let lhsRatio = containsAny(lhs, ratioKeywords)
        let rhsRatio = containsAny(rhs, ratioKeywords)
        guard lhsRatio != rhsRatio else { return false }
        let overlap = tokens(in: lhs).intersection(tokens(in: rhs)).filter { !genericTokens.contains($0) }
        return !overlap.isEmpty || businessStages(in: lhs).intersection(businessStages(in: rhs)).isEmpty == false
    }

    private static func isMixShiftMetric(_ value: String) -> Bool {
        containsAny(value, ["渠道", "版本", "人群", "cohort", "供应商", "provider", "segment", "source", "campaign", "app_version"])
    }

    private static func isExternalDriverCandidate(_ value: String) -> Bool {
        containsAny(value, ["电费", "天气", "用电", "停电", "节假日", "政策", "竞品", "灾害", "火山", "地震", "cfe", "weather", "holiday", "policy"])
    }

    private static func isPageBehaviorMetric(_ value: String) -> Bool {
        containsAny(value, ["页面", "埋点", "曝光", "点击", "按钮", "提交", "停留", "报错", "event", "track", "page", "view", "click", "tap", "submit", "duration", "error"])
    }

    private static func isBusinessOutcomeMetric(_ value: String) -> Bool {
        containsAny(value, ["注册", "申请", "开户", "授信", "审核", "审批", "发卡", "激活", "消费", "交易", "留存", "缴费", "register", "signup", "apply", "submit", "credit", "approve", "activate", "purchase", "payment", "retention"])
    }

    private static func tokens(in text: String) -> Set<String> {
        let separators = CharacterSet(charactersIn: " _-/|:：,，;；()（）[]【】{}<>《》.+")
        return Set(text.components(separatedBy: separators).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).normalizedKey }.filter { $0.count >= 2 })
    }

    private static let genericTokens: Set<String> = ["人数", "用户", "次数", "数量", "指标", "数据", "total", "count", "rate", "ratio"]

    private static func containsAny(_ value: String, _ keywords: [String]) -> Bool {
        let normalized = value.normalizedKey
        return keywords.contains { normalized.contains($0.normalizedKey) }
    }
}

private extension Array {
    func uniquedByStableKey(_ key: (Element) -> String) -> [Element] {
        var seen = Set<String>()
        return filter { seen.insert(key($0)).inserted }
    }
}
