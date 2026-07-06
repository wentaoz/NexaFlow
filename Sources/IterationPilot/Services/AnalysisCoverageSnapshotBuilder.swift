import Foundation

enum AnalysisCoverageSnapshotBuilder {
    static func build(
        userRequest: String,
        reports: [ImportedReport],
        workspace: ProductWorkspace,
        pack: DataPack,
        task: AnalysisTask? = nil,
        contextMode: AnalysisContextMode? = nil,
        sourcePolicy: AnalysisContextSourcePolicy = .fullContext
    ) -> AnalysisCoverageSnapshot {
        let periodIntent = MetricLinkageAnomalyScanner.extractPeriodIntent(
            userRequest: userRequest,
            taskGoal: task?.goal ?? "",
            reports: reports
        )
        let linkageScan = MetricLinkageAnomalyScanner.scan(
            reports: reports,
            task: task,
            periodIntent: periodIntent
        )
        let businessSpace = (task?.businessSpaceID ?? pack.businessSpaceID ?? workspace.selectedBusinessSpaceID)
            .flatMap { id in workspace.businessSpaces.first(where: { $0.id == id }) }
        let externalEvidenceWindow = buildExternalEvidenceWindow(
            periodIntent: linkageScan.periodIntent,
            reports: reports,
            businessSpace: businessSpace
        )
        let businessSpaceID = businessSpace?.id
        let sourceByID = sourcePolicy.includeExternalReferences
            ? Dictionary(uniqueKeysWithValues: workspace.referenceSources.map { ($0.id, $0) })
            : [:]
        let relevantReferences = sourcePolicy.includeExternalReferences
            ? workspace.referenceItems.filter { item in
                item.isRelevant && item.isVisible(in: businessSpaceID, sourceByID: sourceByID)
            }
            : []
        let matchedReferences = sourcePolicy.includeExternalReferences
            ? (externalEvidenceWindow.map { window in
                relevantReferences.filter { window.contains($0) }
            } ?? relevantReferences)
            : []
        let externalEvidenceCoverage = buildExternalEvidenceCoverage(
            contextMode: contextMode,
            sources: sourcePolicy.includeExternalReferences ? workspace.referenceSources : [],
            matchedReferences: matchedReferences,
            sourceByID: sourceByID,
            businessSpaceID: businessSpaceID,
            externalEvidenceWindow: externalEvidenceWindow,
            searchSettings: workspace.searchSettings,
            collectionRuns: sourcePolicy.includeExternalReferences ? workspace.referenceCollectionRuns : []
        )
        let publishedOnlyCount = matchedReferences.filter { $0.resolvedDateBasis == .publishedAt }.count
        let collectedOnlyCount = matchedReferences.filter { $0.resolvedDateBasis == .collectedAt }.count
        let reportSnapshots = reports.map { report -> AnalysisCoverageReportSnapshot in
            let package = TableContextPackageBuilder.build(for: report)
            let periodLabels = periodLabels(in: package)
            let timePeriodCount = max(package.inventory.timeColumns.count, periodLabels.count)
            let periodDiagnostics = periodDiagnostics(for: report)
            let periodCoverage = periodCoverageSummary(for: report, timeColumns: package.inventory.timeColumns)
            let excluded = report.trendSummary.metricTrends
                .flatMap { trend in
                    (trend.excludedPeriods ?? []).map { "\(trend.metricName)：\($0.label)（\($0.reason)）" }
                }
            let coreMetrics = report.trendSummary.metricTrends
                .compactMap { trend in trend.primaryComparison == nil ? nil : trend.metricName }
                .prefix(80)
            var limitations = package.coverage.limitations
            if let metadata = report.sourceMetadata, metadata.sourceType == .tableau {
                limitations.append(metadata.aiContextDescription)
            }
            return AnalysisCoverageReportSnapshot(
                reportID: report.id,
                reportName: report.displayName,
                sourceFormat: report.sourceFormat,
                shape: report.shape,
                kind: report.kind,
                rowCount: report.rowCount,
                columnCount: report.headers.count,
                metricCount: report.firstColumnValues.count,
                timeColumnCount: timePeriodCount,
                sentRows: package.coverage.sentRows,
                sentColumns: package.coverage.sentColumns,
                sentMetrics: package.coverage.sentMetrics,
                dataMode: package.dataPayload.mode,
                rawDataMode: package.coverage.rawDataMode,
                totalRawRows: package.coverage.totalRawRows,
                sentRawRows: package.coverage.sentRawRows,
                rawCoverageDescription: package.coverage.rawCoverageDescription,
                timeAxisSummary: report.timeAxisProfile.summary,
                periodCoverageSummary: periodCoverage,
                latestObservedPeriod: periodDiagnostics.latestObservedPeriod,
                primaryComparisonPeriod: periodDiagnostics.primaryComparisonPeriod,
                downgradedMetricCount: periodDiagnostics.downgradedMetricCount,
                trendAnalysisVersion: report.trendSummary.analysisVersion,
                fieldNames: report.headers,
                metricNames: package.dataPayload.metricSeries.map(\.metricName).isEmpty ? report.firstColumnValues : package.dataPayload.metricSeries.map(\.metricName),
                timeColumnNames: periodLabels.isEmpty ? package.inventory.timeColumns : periodLabels,
                omittedRowsDescription: package.coverage.omittedRowsDescription,
                omittedColumnsDescription: package.coverage.omittedColumnsDescription,
                excludedPeriods: Array(excluded.prefix(120)),
                coreMetricNames: Array(coreMetrics),
                limitations: limitations
            )
        }
        let knownLimitations = reportSnapshots.flatMap(\.limitations).uniqued()
        return AnalysisCoverageSnapshot(
            userRequest: userRequest,
            contextMode: contextMode,
            contextStrategyDescription: contextMode?.technicalDescription,
            reportSnapshots: reportSnapshots,
            periodIntent: linkageScan.periodIntent,
            externalEvidenceWindow: externalEvidenceWindow,
            externalEvidenceMatchedCount: matchedReferences.count,
            externalEvidencePublishedOnlyCount: publishedOnlyCount,
            externalEvidenceCollectedOnlyCount: collectedOnlyCount,
            externalEvidenceCoverage: externalEvidenceCoverage,
            metricLinkageAnomalies: linkageScan.anomalies,
            scannedMetricCount: linkageScan.scannedMetricCount,
            knowledgeEntryCount: workspace.knowledgeEntries.count,
            confluencePageCount: workspace.confluencePages.count,
            jiraProjectEvidenceCount: workspace.jiraProjectEvidences.filter { evidence in
                guard let businessSpaceID else { return true }
                return evidence.businessSpaceID == businessSpaceID
            }.count,
            referenceItemCount: relevantReferences.count,
            correctionMemoryCount: workspace.correctionMemories.filter(\.appliesToFuture).count,
            limitations: knownLimitations + pack.manifest.knownIssues
        )
    }

    static func markdown(_ snapshot: AnalysisCoverageSnapshot) -> String {
        let reports = snapshot.reportSnapshots.map { report in
            """
            - \(report.summary)
              数据模式：\(report.dataMode)
              原始矩阵：\(report.rawCoverageDescription ?? report.rawDataMode ?? "暂无")
              时间口径：\(report.timeAxisSummary ?? "未记录")
              周期覆盖：\(report.periodCoverageSummary ?? "未识别可排序周期覆盖")
              行覆盖：\(report.omittedRowsDescription)
              列覆盖：\(report.omittedColumnsDescription)
              相邻对比候选指标：\(report.coreMetricNames.prefix(30).joined(separator: "、").nilIfBlank ?? "暂无")
              周期风险/用户排除：\(report.excludedPeriods.prefix(12).joined(separator: "；").nilIfBlank ?? "无")
              限制：\(report.limitations.prefix(8).joined(separator: "；").nilIfBlank ?? "无")
            """
        }.joined(separator: "\n")
        let anomalies = (snapshot.metricLinkageAnomalies ?? []).prefix(12).map { anomaly in
            "- [\(anomaly.anomalyType.label)] \(anomaly.sourceMetric)（\(anomaly.sourceChangeText)） -> \(anomaly.targetMetric)（\(anomaly.targetChangeText)）；\(anomaly.changeGapText)；证据 \(anomaly.evidenceLevel.rawValue)，置信度 \(Int(anomaly.confidence * 100))%"
        }.joined(separator: "\n")

        return """
        覆盖摘要：\(snapshot.summary)
        上下文模式：\(snapshot.contextMode?.label ?? "未记录")
        模式说明：\(snapshot.contextStrategyDescription ?? snapshot.contextMode?.technicalDescription ?? "未记录")
        周期口径：\(snapshot.periodIntent?.summary ?? "未指定主分析周期，本轮仅做全周期概览")
        外部证据窗口：\(snapshot.externalEvidenceWindow?.summary ?? "未识别明确周期")
        外部证据覆盖：\(snapshot.externalEvidenceCoverage?.summary ?? "本窗口命中 \(snapshot.externalEvidenceMatchedCount ?? 0) 条；仅发布时间 \(snapshot.externalEvidencePublishedOnlyCount ?? 0) 条；仅采集时间 \(snapshot.externalEvidenceCollectedOnlyCount ?? 0) 条。只有采集时间的证据不能用于高置信归因。")
        知识库：\(snapshot.knowledgeEntryCount) 条；Confluence：\(snapshot.confluencePageCount) 页；Jira 项目证据：\(snapshot.jiraProjectEvidenceCount ?? 0) 条；参照数据：\(snapshot.referenceItemCount) 条；纠偏记忆：\(snapshot.correctionMemoryCount) 条。
        本轮用户需求：\(snapshot.userRequest)

        报表覆盖：
        \(reports.isEmpty ? "当前任务没有选择报表。" : reports)

        总体限制：
        \(snapshot.limitations.prefix(20).map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "无")

        指标联动异常候选：
        \(anomalies.isEmpty ? "暂无高价值候选。" : anomalies)
        """
    }

    private static func periodLabels(in package: TableContextPackage) -> [String] {
        let labels = package.dataPayload.metricSeries
            .flatMap { $0.points.map(\.label) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !labels.isEmpty else { return [] }

        var byKey: [String: String] = [:]
        for label in labels {
            byKey[label.normalizedKey] = label
        }
        return byKey.values.sorted { lhs, rhs in
            let lhsRange = DateParsing.periodRange(lhs)
            let rhsRange = DateParsing.periodRange(rhs)
            if let lhsDate = lhsRange?.start, let rhsDate = rhsRange?.start, lhsDate != rhsDate {
                return lhsDate < rhsDate
            }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    static func aiReadRangeMarkdown(_ snapshot: AnalysisCoverageSnapshot) -> String {
        let reportRows = snapshot.reportSnapshots.map { report in
            let fields = compactList(report.fieldNames, limit: 36, totalLabel: "\(report.columnCount) 列")
            let metrics = compactList(report.metricNames, limit: 48, totalLabel: "\(report.metricCount) 个指标")
            let timeColumns = compactList(report.timeColumnNames, limit: 28, totalLabel: "\(report.timeColumnCount) 个时间列")
            let rawMode = report.rawCoverageDescription ?? report.rawDataMode ?? "未记录"
            let excluded = report.excludedPeriods.prefix(8).joined(separator: "；").nilIfBlank ?? "无"
            let limits = report.limitations.prefix(6).joined(separator: "；").nilIfBlank ?? "无"
            let primaryPeriod = report.primaryComparisonPeriod ?? "未识别"
            let latestPeriod = report.latestObservedPeriod ?? "未识别"
            let downgraded = report.downgradedMetricCount > 0 ? "\(report.downgradedMetricCount) 个指标存在候选成熟口径提示" : "无候选成熟口径提示"
            return """
            | \(report.reportName) | \(report.sourceFormat.label) / \(report.shape.label) / \(report.kind.label) | \(report.rowCount) 行 / \(report.columnCount) 列 | \(report.sentRows) 行 / \(report.sentColumns) 列 / \(report.sentMetrics) 指标 | \(rawMode) |
            字段：\(fields)
            指标：\(metrics)
            时间列/周期：\(timeColumns)
            时间口径：\(report.timeAxisSummary ?? "未记录")
            周期覆盖事实：\(report.periodCoverageSummary ?? "未识别可排序周期覆盖")
            表格最新出现周期：\(latestPeriod)
            候选相邻对比周期：\(primaryPeriod)
            成熟口径提示：\(downgraded)
            周期风险/用户排除：\(excluded)
            限制：\(limits)
            """
        }.joined(separator: "\n\n")

        let periodText = snapshot.periodIntent?.summary ?? "未指定主分析周期，本轮仅做全周期概览"
        let windowText = snapshot.externalEvidenceWindow?.summary ?? "未识别明确外部证据窗口"
        let externalText = snapshot.externalEvidenceCoverage?.summary ?? "本窗口命中 \(snapshot.externalEvidenceMatchedCount ?? 0) 条；仅发布时间 \(snapshot.externalEvidencePublishedOnlyCount ?? 0) 条；仅采集时间 \(snapshot.externalEvidenceCollectedOnlyCount ?? 0) 条。"
        let missingText = snapshot.limitations.prefix(18).map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "无明确遗漏。"

        return """
        ## AI 读取到的数据
        本轮读取 \(snapshot.totalReports) 张表、\(snapshot.totalRows) 行、\(snapshot.totalColumns) 列、\(snapshot.totalMetrics) 个指标、\(snapshot.totalTimeColumns) 个时间列。
        周期口径：\(periodText)
        外部证据窗口：\(windowText)
        外部证据覆盖：\(externalText)
        知识库：\(snapshot.knowledgeEntryCount) 条；Confluence：\(snapshot.confluencePageCount) 页；Jira 项目证据：\(snapshot.jiraProjectEvidenceCount ?? 0) 条；参照数据：\(snapshot.referenceItemCount) 条；纠偏记忆：\(snapshot.correctionMemoryCount) 条。

        | 报表 | 类型 | 原始规模 | 发送给 AI | 原始矩阵 |
        |---|---|---:|---:|---|
        \(reportRows.isEmpty ? "当前任务没有选择报表。" : reportRows)

        未覆盖或不得下确定结论的数据：
        \(missingText)
        """
    }

    private static func periodDiagnostics(for report: ImportedReport) -> (latestObservedPeriod: String?, primaryComparisonPeriod: String?, downgradedMetricCount: Int) {
        let trends = report.trendSummary.metricTrends
        let downgradedCount = trends.filter { $0.latestPointIsPartial == true }.count

        var labels: [String] = []
        for trend in trends {
            labels.append(contentsOf: [
                trend.trendStartLabel,
                trend.trendEndLabel,
                trend.partialLatestLabel,
                trend.primaryComparison?.currentLabel,
                trend.primaryComparison?.previousLabel
            ].compactMap { $0?.nilIfBlank })
            labels.append(contentsOf: (trend.excludedPeriods ?? []).compactMap { $0.label.nilIfBlank })
        }
        if labels.isEmpty {
            labels = report.headers + report.firstColumnValues
        }
        let latest = labels
            .uniqued()
            .compactMap { label -> (label: String, end: Date)? in
                if let range = DateParsing.periodRange(label) {
                    return (label, range.end)
                }
                if let date = DateParsing.parse(label) {
                    return (label, date)
                }
                return nil
            }
            .sorted { lhs, rhs in
                if lhs.end == rhs.end {
                    return lhs.label.localizedStandardCompare(rhs.label) == .orderedDescending
                }
                return lhs.end > rhs.end
            }
            .first?
            .label

        let comparisonCounts = trends.reduce(into: [String: Int]()) { result, trend in
            guard let comparison = trend.primaryComparison else { return }
            result["\(comparison.currentLabel) vs \(comparison.previousLabel)", default: 0] += 1
        }
        let primary = comparisonCounts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
                }
                return lhs.value > rhs.value
            }
            .first?
            .key

        return (latest, primary, downgradedCount)
    }

    private static func periodCoverageSummary(for report: ImportedReport, timeColumns: [String]) -> String? {
        let rows = report.storedDataRows.isEmpty ? report.sampleRows : report.storedDataRows
        guard !rows.isEmpty else { return nil }

        var candidateHeaders: [String] = []
        if let primary = report.timeAxisProfile.primaryDateColumn {
            candidateHeaders.append(primary)
        }
        candidateHeaders.append(contentsOf: report.timeAxisProfile.candidateDateColumns.map(\.columnName))
        candidateHeaders.append(contentsOf: timeColumns)
        candidateHeaders.append(contentsOf: report.headers.filter { header in
            let key = header.normalizedKey
            return key.contains("周期") ||
                key.contains("period") ||
                key.contains("week") ||
                key.contains("semana") ||
                key.contains("日期") ||
                key.contains("date") ||
                key.contains("时间")
        })
        if candidateHeaders.isEmpty {
            candidateHeaders = report.headers
        }

        struct ParsedPeriod {
            var label: String
            var start: Date
            var end: Date
        }
        struct CandidateCoverage {
            var header: String
            var parsedRowCount: Int
            var nonEmptyRowCount: Int
            var uniquePeriods: [ParsedPeriod]
        }

        let candidates: [CandidateCoverage] = candidateHeaders.uniqued().compactMap { header in
            guard report.headers.contains(header) else { return nil }
            let values = rows.compactMap { row in
                row[header]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            }
            guard !values.isEmpty else { return nil }
            let parsed = values.compactMap { value -> ParsedPeriod? in
                if let range = DateParsing.periodRange(value) {
                    return ParsedPeriod(label: value, start: range.start, end: range.end)
                }
                if let date = DateParsing.parse(value) {
                    return ParsedPeriod(label: value, start: date, end: date)
                }
                return nil
            }
            guard parsed.count >= 2 else { return nil }
            var byLabel: [String: ParsedPeriod] = [:]
            for period in parsed {
                byLabel[period.label.normalizedKey] = period
            }
            let unique = byLabel.values.sorted { lhs, rhs in
                if lhs.end == rhs.end {
                    return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
                }
                return lhs.end < rhs.end
            }
            guard !unique.isEmpty else { return nil }
            return CandidateCoverage(
                header: header,
                parsedRowCount: parsed.count,
                nonEmptyRowCount: values.count,
                uniquePeriods: unique
            )
        }

        guard let best = candidates.sorted(by: { lhs, rhs in
            if lhs.uniquePeriods.count == rhs.uniquePeriods.count {
                return lhs.parsedRowCount > rhs.parsedRowCount
            }
            return lhs.uniquePeriods.count > rhs.uniquePeriods.count
        }).first,
              let first = best.uniquePeriods.first,
              let last = best.uniquePeriods.last else {
            return nil
        }

        let ratioText = "\(best.parsedRowCount)/\(best.nonEmptyRowCount)"
        if best.uniquePeriods.count == 1 {
            return "时间列「\(best.header)」覆盖 1 个唯一周期（\(ratioText) 行可解析）：\(first.label)。"
        }
        return "时间列「\(best.header)」覆盖 \(best.uniquePeriods.count) 个唯一周期（\(ratioText) 行可解析），范围 \(first.label) 至 \(last.label)。该范围表示表格中存在这些周期；只有具体指标或维度缺行时，才可写为指标/维度缺失，不得写成整段周期完全缺失。"
    }

    private static func buildExternalEvidenceWindow(
        periodIntent: AnalysisPeriodIntent,
        reports: [ImportedReport],
        businessSpace: BusinessSpace?
    ) -> ExternalEvidenceWindow? {
        let timeZone = BusinessTimeZoneResolver.resolve(
            timeZoneIdentifier: businessSpace?.timeZoneIdentifier,
            countryRegion: businessSpace?.countryRegion,
            businessBackground: businessSpace?.businessBackground,
            businessSpaceName: businessSpace?.name
        )
        let requestedRanges = periodIntent.requestedPeriods.compactMap { dateRange(from: $0) }
        if let first = requestedRanges.first {
            let second = requestedRanges.dropFirst().first
            return ExternalEvidenceWindow(
                analysisStartDate: first.start,
                analysisEndDate: first.end,
                comparisonStartDate: second?.start,
                comparisonEndDate: second?.end,
                userSpecifiedPeriod: periodIntent.isUserSpecified,
                timeZone: timeZone
            )
        }

        let trendDates = reports.flatMap(\.trendSummary.metricTrends).flatMap { trend in
            [trend.trendStartDate, trend.trendEndDate].compactMap { $0 }
        }
        guard let start = trendDates.min(), let end = trendDates.max() else { return nil }
        return ExternalEvidenceWindow(
            analysisStartDate: start,
            analysisEndDate: end,
            comparisonStartDate: nil,
            comparisonEndDate: nil,
            userSpecifiedPeriod: false,
            timeZone: timeZone
        )
    }

    private static func buildExternalEvidenceCoverage(
        contextMode: AnalysisContextMode?,
        sources: [ExternalReferenceSource],
        matchedReferences: [ExternalReferenceItem],
        sourceByID: [UUID: ExternalReferenceSource],
        businessSpaceID: UUID?,
        externalEvidenceWindow: ExternalEvidenceWindow?,
        searchSettings: SearchAPISettings,
        collectionRuns: [ExternalReferenceCollectionRun]
    ) -> ExternalEvidenceCoverageSnapshot {
        let scopedSources = sources.filter { source in
            source.isVisible(in: businessSpaceID)
        }
        let enabledSources = scopedSources.filter { $0.enabled && $0.lifecycleStatus != .ignored }
        let healthBySourceID = Dictionary(uniqueKeysWithValues: enabledSources.map { source in
            (
                source.id,
                ReferenceSourceHealthEvaluator.evaluate(
                    source: source,
                    searchSettings: searchSettings,
                    collectionRuns: collectionRuns
                )
            )
        })
        let collectableSources = enabledSources.filter { healthBySourceID[$0.id]?.isCollectable == true }
        let skippedSources = enabledSources.filter { healthBySourceID[$0.id]?.isCollectable != true }
        let skippedReasons = skippedSources.map { source in
            "\(source.name)：\(healthBySourceID[source.id]?.status.label ?? "不可采集")"
        }
        let candidateSources = scopedSources.filter { source in
            !source.enabled && (source.lifecycleStatus == .candidate || source.lifecycleStatus == .needsConfirmation || source.lifecycleStatus == .tested)
        }
        let tavilySources = collectableSources.filter { $0.collectorType == .tavilySearch }
        let mode = contextMode ?? .fullReanalysis
        let needsTavily = !tavilySources.isEmpty
        let hasTavilyKey = !searchSettings.tavilyAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let reason: String
        let triggered: Bool
        if !mode.usesFullContext {
            triggered = false
            reason = "\(mode.label)只使用已有缓存，不主动刷新外部数据"
        } else if enabledSources.isEmpty {
            triggered = false
            reason = candidateSources.isEmpty ? "没有启用的参照数据源" : "只有候选源未启用，本轮不会搜索这些来源"
        } else if collectableSources.isEmpty {
            triggered = false
            reason = "已启用源均不可采集，本轮不会搜索这些来源"
        } else if externalEvidenceWindow == nil {
            triggered = false
            reason = "未识别到本轮分析周期，外部数据只作为缓存线索"
        } else if needsTavily && !hasTavilyKey {
            triggered = false
            reason = "Tavily API Key 未配置，Tavily 数据源无法采集"
        } else {
            triggered = true
            reason = "\(mode.label)会按本轮分析周期采集已启用来源"
        }

        let recentCutoff = Date().addingTimeInterval(-10 * 60)
        let recentCount = matchedReferences.filter { $0.collectedAt >= recentCutoff }.count
        let newsLikeCount = matchedReferences.filter { item in
            guard let source = sourceByID[item.sourceID] else { return item.sourceName.localizedCaseInsensitiveContains("news") }
            return source.tavilySourceProfile.localizedCaseInsensitiveContains("news") ||
                source.tavilySourceProfile.localizedCaseInsensitiveContains("finance") ||
                source.tavilyQueryGroup.localizedCaseInsensitiveContains("news") ||
                source.name.localizedCaseInsensitiveContains("news")
        }.count

        return ExternalEvidenceCoverageSnapshot(
            searchTriggered: triggered,
            reason: reason,
            enabledSourceCount: enabledSources.count,
            collectableSourceCount: collectableSources.count,
            skippedSourceCount: skippedSources.count,
            skippedSourceReasons: skippedReasons,
            candidateSourceCount: candidateSources.count,
            tavilySourceCount: tavilySources.count,
            cachedMatchedItemCount: matchedReferences.count,
            recentCollectedItemCount: recentCount,
            competitorItemCount: matchedReferences.filter { $0.domain == .competitor }.count,
            newsLikeItemCount: newsLikeCount,
            policyItemCount: matchedReferences.filter { $0.domain == .policy }.count,
            marketItemCount: matchedReferences.filter { $0.domain == .market }.count,
            externalEventItemCount: matchedReferences.filter { $0.domain == .externalEvent }.count,
            sourceNames: collectableSources.map(\.name)
        )
    }

    private static func dateRange(from value: String) -> (start: Date, end: Date)? {
        DateParsing.periodRange(value)
    }

    private static func compactList(_ values: [String], limit: Int, totalLabel: String) -> String {
        let cleaned = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
        guard !cleaned.isEmpty else { return "未识别" }
        let text = cleaned.prefix(limit).joined(separator: "、")
        let more = cleaned.count > limit ? "，另有 \(cleaned.count - limit) 项未展开" : ""
        return "\(totalLabel)：\(text)\(more)"
    }
}
