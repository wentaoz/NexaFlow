import Foundation

@MainActor
extension ProductWorkflowStore {
    func focusMetricResultEvidence(
        messageID: UUID?,
        resultID: UUID?,
        sourceCells: [HarnessSourceCellRef]
    ) {
        selectedAnalysisEvidenceMessageID = messageID
        selectedMetricResultID = resultID
        selectedSourceCellRefs = sourceCells
        analysisInfoSidebarPanelID = "证据"
        isAnalysisInfoSidebarVisible = true
    }

    func prepareTableStructureConfirmation(
        sessionID: UUID?,
        report: ImportedReport,
        confidence: Double,
        reason: String
    ) {
        let headers = report.headers.isEmpty ? (report.rawRows.first ?? []) : report.headers
        let periodCandidates = candidates(in: headers, matching: ["周期", "日期", "时间", "week", "date", "period"])
        let metricNameCandidates = candidates(in: headers, matching: ["指标", "measure names", "metric", "name", "字段"])
        let metricValueCandidates = candidates(in: headers, matching: ["值", "measure values", "value", "amount", "数值"])
        pendingTableStructureConfirmation = TableStructureConfirmationDraft(
            sessionID: sessionID,
            reportID: report.id,
            reportName: report.displayName,
            confidence: confidence,
            reason: reason,
            periodColumnCandidates: periodCandidates.isEmpty ? headers : periodCandidates,
            metricNameColumnCandidates: metricNameCandidates.isEmpty ? headers : metricNameCandidates,
            metricValueColumnCandidates: metricValueCandidates.isEmpty ? headers : metricValueCandidates,
            selectedPeriodColumn: periodCandidates.first,
            selectedMetricNameColumn: metricNameCandidates.first,
            selectedMetricValueColumn: metricValueCandidates.first
        )
    }

    func prepareMetricMappingConfirmation(
        sessionID: UUID?,
        report: ImportedReport,
        requestedMetric: String,
        candidates: [HarnessMetricCatalogEntry]
    ) {
        let ranked = candidates
            .map { entry in
                MetricMappingCandidate(
                    actualMetric: entry.metricName,
                    score: metricSimilarity(requestedMetric, entry.metricName),
                    sampleValues: entry.sampleValues
                )
            }
            .sorted { $0.score > $1.score }
        pendingMetricMappingConfirmation = MetricMappingConfirmationDraft(
            sessionID: sessionID,
            reportID: report.id,
            reportName: report.displayName,
            requestedMetric: requestedMetric,
            candidates: Array(ranked.prefix(8)),
            selectedActualMetric: ranked.first?.actualMetric
        )
    }

    func confirmTableStructure(_ draft: TableStructureConfirmationDraft) {
        guard let packIndex = workspace.dataPacks.firstIndex(where: { pack in
            pack.importedReports.contains(where: { $0.id == draft.reportID })
        }),
              let reportIndex = workspace.dataPacks[packIndex].importedReports.firstIndex(where: { $0.id == draft.reportID }) else {
            pendingTableStructureConfirmation = nil
            return
        }
        var report = workspace.dataPacks[packIndex].importedReports[reportIndex]
        report.semanticStatus = .confirmed
        report.semanticConfidence = max(report.semanticConfidence, draft.confidence, 0.85)
        report.understandingMessages.append(ReportUnderstandingMessage(
            role: .user,
            content: "已确认表格结构：周期列=\(draft.selectedPeriodColumn ?? "未指定")；指标列=\(draft.selectedMetricNameColumn ?? "未指定")；数值列=\(draft.selectedMetricValueColumn ?? "未指定")；周期向下填充=\(draft.fillDownPeriod ? "是" : "否")。"
        ))
        workspace.dataPacks[packIndex].importedReports[reportIndex] = report
        saveTableUnderstandingTemplate(
            report: report,
            periodColumn: draft.selectedPeriodColumn,
            metricNameColumn: draft.selectedMetricNameColumn,
            metricValueColumn: draft.selectedMetricValueColumn,
            fillDownPeriod: draft.fillDownPeriod,
            aliases: [:]
        )
        pendingTableStructureConfirmation = nil
        statusText = "已确认表格结构并保存为模板，正在重新分析"
        reanalyzeSelectedAnalysisSession()
    }

    func confirmMetricMapping(_ draft: MetricMappingConfirmationDraft) {
        guard let actual = draft.selectedActualMetric?.nilIfBlank,
              let packIndex = workspace.dataPacks.firstIndex(where: { pack in
                  pack.importedReports.contains(where: { $0.id == draft.reportID })
              }),
              let report = workspace.dataPacks[packIndex].importedReports.first(where: { $0.id == draft.reportID }) else {
            pendingMetricMappingConfirmation = nil
            return
        }
        if draft.saveAsTemplate {
            saveTableUnderstandingTemplate(
                report: report,
                periodColumn: nil,
                metricNameColumn: nil,
                metricValueColumn: nil,
                fillDownPeriod: true,
                aliases: [draft.requestedMetric: actual]
            )
        }
        pendingMetricMappingConfirmation = nil
        statusText = "已确认指标映射：\(draft.requestedMetric) → \(actual)，正在重新分析"
        reanalyzeSelectedAnalysisSession()
    }

    func dismissHarnessConfirmation() {
        pendingTableStructureConfirmation = nil
        pendingMetricMappingConfirmation = nil
    }

    func presentHarnessConfirmationIfNeeded(
        run: AnalysisHarnessRun,
        sessionID: UUID?,
        reports: [ImportedReport]
    ) {
        guard pendingTableStructureConfirmation == nil,
              pendingMetricMappingConfirmation == nil else { return }
        guard run.status == .blocked || run.validationIssues.contains(where: { $0.severity.blocksOutput }) else { return }

        let blockingIssues = run.validationIssues.filter(\.severity.blocksOutput)
        if let missingFieldIssue = blockingIssues.first(where: { $0.code == .missingField }),
           let requestedMetric = requestedMetricName(from: missingFieldIssue.message),
           let report = bestReportForMetricConfirmation(reports: reports, run: run),
           !run.normalizedFactTables.flatMap(\.metricCatalog).isEmpty {
            prepareMetricMappingConfirmation(
                sessionID: sessionID,
                report: report,
                requestedMetric: requestedMetric,
                candidates: run.normalizedFactTables.flatMap(\.metricCatalog)
            )
            return
        }

        guard let structureIssue = blockingIssues.first(where: { issue in
            issue.code == .ambiguousFieldMapping && issue.stage == .tableUnderstanding
        }) else {
            return
        }

        let lowConfidenceManifest = run.tableManifest.first { manifest in
            (manifest.understanding?.confidence ?? 0) < AnalysisHarnessTrustTuning.contractPassThreshold ||
                manifest.understanding?.periodColumn == nil ||
                manifest.understanding?.metricNameColumn == nil ||
                manifest.understanding?.metricValueColumn == nil
        }
        let report = lowConfidenceManifest.flatMap { manifest in
            reports.first { $0.id == manifest.reportID || $0.id.uuidString == manifest.id }
        } ?? reports.first
        guard let report else { return }
        let confidence = lowConfidenceManifest?.understanding?.confidence ?? report.semanticConfidence
        let reason = structureIssue.message
        prepareTableStructureConfirmation(
            sessionID: sessionID,
            report: report,
            confidence: confidence,
            reason: reason
        )
    }

    func disableTableUnderstandingTemplate(_ templateID: UUID) {
        guard let index = workspace.analysisTableUnderstandingTemplates.firstIndex(where: { $0.id == templateID }) else { return }
        workspace.analysisTableUnderstandingTemplates[index].isDisabled = true
        workspace.analysisTableUnderstandingTemplates[index].updatedAt = Date()
        save()
    }

    private func saveTableUnderstandingTemplate(
        report: ImportedReport,
        periodColumn: String?,
        metricNameColumn: String?,
        metricValueColumn: String?,
        fillDownPeriod: Bool,
        aliases: [String: String]
    ) {
        let templateName = "\(report.displayName) 表格理解"
        let headerSignature = (report.headers.isEmpty ? (report.rawRows.first ?? []) : report.headers)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let existingIndex = workspace.analysisTableUnderstandingTemplates.firstIndex(where: { template in
            template.name.normalizedKey == templateName.normalizedKey ||
                (!template.headerSignature.isEmpty && template.headerSignature.map(\.normalizedKey) == headerSignature.map(\.normalizedKey))
        }) {
            var existing = workspace.analysisTableUnderstandingTemplates[existingIndex]
            existing.periodColumn = periodColumn ?? existing.periodColumn
            existing.metricNameColumn = metricNameColumn ?? existing.metricNameColumn
            existing.metricValueColumn = metricValueColumn ?? existing.metricValueColumn
            existing.fillDownPeriod = fillDownPeriod
            existing.metricAliases.merge(aliases) { _, new in new }
            existing.updatedAt = Date()
            workspace.analysisTableUnderstandingTemplates[existingIndex] = existing
        } else {
            workspace.analysisTableUnderstandingTemplates.insert(AnalysisTableUnderstandingTemplate(
                businessSpaceID: selectedBusinessSpace?.id,
                name: templateName,
                sourceFingerprintHint: report.sourceFingerprint,
                headerSignature: headerSignature,
                shape: report.shape.label,
                periodColumn: periodColumn,
                metricNameColumn: metricNameColumn,
                metricValueColumn: metricValueColumn,
                fillDownPeriod: fillDownPeriod,
                metricAliases: aliases
            ), at: 0)
        }
        workspace.analysisTableUnderstandingTemplates = Array(workspace.analysisTableUnderstandingTemplates.prefix(80))
        save()
    }

    private func candidates(in headers: [String], matching needles: [String]) -> [String] {
        headers.filter { header in
            let key = header.normalizedKey
            return needles.contains { key.contains($0.normalizedKey) }
        }
    }

    private func metricSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let left = lhs.normalizedKey
        let right = rhs.normalizedKey
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        if left == right { return 1 }
        if left.contains(right) || right.contains(left) { return 0.82 }
        let leftSet = Set(left.map(String.init))
        let rightSet = Set(right.map(String.init))
        let intersection = leftSet.intersection(rightSet).count
        let union = max(1, leftSet.union(rightSet).count)
        return Double(intersection) / Double(union)
    }

    private func requestedMetricName(from message: String) -> String? {
        let patterns = [
            #"请求指标[:：]\s*([^。；;，,\n]+)"#,
            #"未找到请求指标[:：]\s*([^。；;，,\n]+)"#,
            #"指标[:：]\s*([^。；;，,\n]+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(message.startIndex..<message.endIndex, in: message)
            guard let match = regex.firstMatch(in: message, range: range),
                  match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: message) else { continue }
            let value = String(message[valueRange])
                .replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = value.nilIfBlank { return value }
        }
        return nil
    }

    private func bestReportForMetricConfirmation(
        reports: [ImportedReport],
        run: AnalysisHarnessRun
    ) -> ImportedReport? {
        if let firstFactTable = run.normalizedFactTables.first,
           let report = reports.first(where: { $0.id.uuidString == firstFactTable.tableID || $0.displayName == firstFactTable.tableName }) {
            return report
        }
        if let firstManifest = run.tableManifest.first,
           let report = reports.first(where: { $0.id == firstManifest.reportID || $0.id.uuidString == firstManifest.id }) {
            return report
        }
        return reports.first
    }
}
