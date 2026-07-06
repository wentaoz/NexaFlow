import Foundation

enum AIAnalysisValidator {
    static func validateTableAnalysis(
        rawOutput: String,
        parsed: AITableFirstAnalysis?,
        report: ImportedReport,
        package: TableContextPackage
    ) -> [String] {
        var warnings: [String] = []
        guard let parsed else {
            return ["AI 输出不是可解析的 JSON，必须按指定结构重新输出。"]
        }

        let knownMetrics = Set((report.firstColumnValues + report.trendSummary.metricTrends.map(\.metricName)).map(\.normalizedKey))
        let knownHeaders = Set(report.headers.map(\.normalizedKey))
        let outputText = [
            parsed.summary,
            parsed.dataAvailability,
            parsed.primaryComparison.joined(separator: " "),
            parsed.historicalTrend.joined(separator: " "),
            parsed.keyChanges.joined(separator: " "),
            parsed.anomalies.joined(separator: " "),
            parsed.metricLinkCandidates.joined(separator: " "),
            parsed.externalEventHypotheses.joined(separator: " ")
        ].joined(separator: " ").normalizedKey

        if package.manifest.shape == .pivotWide, !knownMetrics.isEmpty {
            let mentionedMetricCount = knownMetrics.filter { !$0.isEmpty && outputText.contains($0) }.count
            if mentionedMetricCount == 0 {
                warnings.append("AI 没有引用任何已知首列指标，可能漏看表格指标。")
            }
        }

        if package.coverage.totalRows > package.coverage.sentRows,
           !outputText.contains("未发送") && !outputText.contains("未覆盖") && !outputText.contains("需要补充") {
            warnings.append("首轮未覆盖全部明细行，AI 必须声明未覆盖范围或请求补充数据。")
        }
        if package.rawMatrix?.mode == "indexed_raw_matrix" {
            let hasRawRequest = parsed.missingDataRequests.contains { request in
                request.kind == .getRawRange || request.kind == .getFullSheet
            }
            let mentionsRawLimit = outputText.contains("原始") ||
                outputText.contains("未覆盖") ||
                outputText.contains("预览") ||
                outputText.contains("补充") ||
                outputText.contains("需补")
            if !hasRawRequest && !mentionsRawLimit {
                warnings.append("原始二维表未全量发送，AI 必须说明 rawMatrix 只覆盖预览，或请求 getRawRange/getFullSheet 补数。")
            }
        }
        if let risks = package.rawMatrix?.structureRisks, !risks.isEmpty {
            let mentionsStructureRisk = outputText.contains("表头") ||
                outputText.contains("结构") ||
                outputText.contains("口径") ||
                outputText.contains("不确定") ||
                outputText.contains("风险")
            if !mentionsStructureRisk {
                warnings.append("表格存在结构或口径风险，AI 必须说明如何处理表头、日期顺序或指标口径不确定性。")
            }
        }

        let partialLabels = report.trendSummary.metricTrends
            .flatMap { $0.excludedPeriods ?? [] }
            .map(\.label.normalizedKey)
            .filter { !$0.isEmpty }
        if partialLabels.contains(where: { outputText.contains($0) }),
           parsed.primaryComparison.joined(separator: " ").normalizedKey.contains("主比较") {
            warnings.append("AI 可能把候选周期风险写成确定主比较；请改为用户指定周期或全周期概览口径。")
        }

        if !knownHeaders.isEmpty, package.manifest.shape != .pivotWide {
            let mentionedHeaderCount = knownHeaders.filter { !$0.isEmpty && outputText.contains($0) }.count
            if mentionedHeaderCount == 0 {
                warnings.append("AI 没有引用任何已知字段，必须基于字段清单说明数据可用性。")
            }
        }

        if rawOutput.normalizedKey.contains("confluence") &&
            rawOutput.contains("上线") &&
            !rawOutput.contains("不等于") &&
            !rawOutput.contains("不能单独") {
            warnings.append("AI 提到 Confluence 时必须说明文档自身创建/修改时间不等于真实上线时间。")
        }
        if rawOutput.normalizedKey.contains("confluence") &&
            (rawOutput.contains("知识库同步时间") || rawOutput.contains("知识库创建时间")) &&
            !rawOutput.contains("不能使用") &&
            !rawOutput.contains("不允许使用") {
            warnings.append("Confluence 归因不能使用知识库同步时间或知识库条目创建时间，必须使用文档自身创建/修改时间。")
        }
        if rawOutput.contains("pp") {
            warnings.append("输出中包含未解释的 pp，比例指标绝对差值必须写成“百分点”。")
        }

        return warnings.uniqued()
    }
}
