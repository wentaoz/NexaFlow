import Foundation

enum AggregationConsistencyValidator {
    private struct AuditFact {
        var report: String
        var metric: String
        var kind: String
        var aggregationRule: String
        var fullPeriodSum: Double?
        var periodAverage: Double?
        var comparisonReport: String
        var fullSumChangePercent: Double?
        var periodAverageChangePercent: Double?
    }

    private struct DerivedFact {
        var report: String
        var metric: String
        var rule: String
        var recomputedValue: Double?
        var periodAverage: Double?
        var comparisonReport: String
        var recomputedChangePercent: Double?
    }

    private struct PeriodComparisonFact {
        var report: String
        var metric: String
        var kind: String
        var baseValue: Double?
        var currentValue: Double?
        var changePercent: Double?
    }

    static func validate(
        output: String,
        userRequest: String,
        reports: [ImportedReport],
        notebookRun: AnalysisNotebookRun?
    ) -> [String] {
        var warnings = unresolvedPlaceholderWarnings(in: output)
        guard let notebookRun else { return warnings.uniqued() }
        let intent = AggregationSemantics.intent(userRequest: userRequest, reports: reports)
        let auditFacts = auditFacts(from: notebookRun)
        let derivedFacts = derivedFacts(from: notebookRun)
        let periodComparisonFacts = periodComparisonFacts(from: notebookRun)
        let normalizedOutput = output.normalizedKey

        if intent == .fileTotalComparison {
            let hasTotalWording = ["全周期", "sum", "总计", "累计", "合计", "总账", "总量", "全量加总"].contains {
                normalizedOutput.contains($0.normalizedKey)
            }
            if !hasTotalWording && auditFacts.contains(where: { $0.kind == MetricAggregationKind.additive.label && $0.comparisonReport.nilIfBlank != nil }) {
                warnings.append("本轮判定为文件/全周期总账对比，但 AI 没有明确声明使用全周期 SUM、总计或累计口径。")
            }
            if output.contains("周均") && !output.contains("补充") && !output.contains("另") && !output.contains("不是总账") {
                warnings.append("本轮主口径是全周期 SUM，AI 不得把周均作为主结论；如讨论周均必须标注为补充视角。")
            }
        }

        if intent == .ambiguousNeedsConfirmation {
            let asksUser = ["请确认", "需要确认", "选择", "SUM", "周均", "总账"].contains { output.localizedCaseInsensitiveContains($0) }
            let hasDefinitiveConclusion = ["结论是", "直接结论", "主要原因", "明确"].contains { output.localizedCaseInsensitiveContains($0) }
            if hasDefinitiveConclusion && !asksUser {
                warnings.append("聚合口径未明确时，AI 必须先请用户确认 SUM 还是周均，不能输出确定业务结论。")
            }
        }

        for fact in auditFacts where fact.kind == MetricAggregationKind.additive.label {
            guard let expectedChange = fact.fullSumChangePercent,
                  fact.comparisonReport.nilIfBlank != nil,
                  abs(expectedChange) >= 10 else { continue }
            let relevantSentences = sentences(in: output, mentioning: fact.metric)
            guard !relevantSentences.isEmpty || output.localizedCaseInsensitiveContains(fact.metric) else { continue }
            let sentencesToCheck = relevantSentences.isEmpty ? sentences(in: output) : relevantSentences
            if expectedChange > 0 {
                if sentencesToCheck.contains(where: containsDownwardClaim) {
                    warnings.append("\(fact.metric) 的本地 SUM 对比为增长 \(formatPercent(expectedChange))%，但 AI 文本出现下降/减少类结论。")
                }
            } else if expectedChange < 0 {
                if sentencesToCheck.contains(where: containsUpwardClaim) {
                    warnings.append("\(fact.metric) 的本地 SUM 对比为下降 \(formatPercent(abs(expectedChange)))%，但 AI 文本出现增长/提升类结论。")
                }
            }
            if abs(expectedChange) >= 15,
               sentencesToCheck.contains(where: containsSmallMovementClaim) {
                warnings.append("\(fact.metric) 的本地 SUM 变化幅度为 \(formatPercent(expectedChange))%，AI 不得写成“小幅”或“不足 2%”一类结论。")
            }
        }

        for fact in periodComparisonFacts where fact.kind == MetricAggregationKind.additive.label {
            guard let expectedChange = fact.changePercent,
                  abs(expectedChange) >= 10 else { continue }
            let relevantSentences = sentences(in: output, mentioning: fact.metric)
            guard !relevantSentences.isEmpty || output.localizedCaseInsensitiveContains(fact.metric) else { continue }
            let sentencesToCheck = relevantSentences.isEmpty ? sentences(in: output) : relevantSentences
            if expectedChange > 0 {
                if sentencesToCheck.contains(where: containsDownwardClaim) {
                    warnings.append("\(fact.metric) 的本地关键周期对比为增长 \(formatPercent(expectedChange))%，但 AI 文本出现下降/减少类结论。")
                }
            } else if expectedChange < 0 {
                if sentencesToCheck.contains(where: containsUpwardClaim) {
                    warnings.append("\(fact.metric) 的本地关键周期对比为下降 \(formatPercent(abs(expectedChange)))%，但 AI 文本出现增长/提升类结论。")
                }
            }
            if abs(expectedChange) >= 15,
               sentencesToCheck.contains(where: containsSmallMovementClaim) {
                warnings.append("\(fact.metric) 的本地关键周期变化幅度为 \(formatPercent(expectedChange))%，AI 不得写成“小幅”或“不足 2%”一类结论。")
            }
        }

        for fact in derivedFacts {
            guard output.localizedCaseInsensitiveContains(fact.metric) else { continue }
            let relatedText = sentences(in: output, mentioning: fact.metric).joined(separator: " ")
            let basisText = relatedText.isEmpty ? output : relatedText
            let mentionsRecompute = ["分子", "分母", "重算", "加权", "÷", "/", "交易金额", "交易人数", "交易笔数"].contains {
                basisText.localizedCaseInsensitiveContains($0)
            }
            if !mentionsRecompute {
                warnings.append("\(fact.metric) 是派生指标，AI 必须说明采用“\(fact.rule)”重算或加权，不能简单平均周期值。")
            }
        }

        return warnings.uniqued()
    }

    static func correctionPrompt(
        originalPrompt: String,
        output: String,
        warnings: [String],
        notebookRun: AnalysisNotebookRun?
    ) -> String {
        let auditMarkdown = notebookRun?.promptMarkdown.nilIfBlank ?? "本轮没有可用 Notebook 证据。"
        return """
        你的上一版回答没有通过 NexaFlow 本地聚合口径校验。请直接重写完整回答，不要解释你被校验器拦截，也不要保留错误说法。

        必须修正的问题：
        \(warnings.map { "- \($0)" }.joined(separator: "\n"))

        必须遵守：
        - 第一个正文标题必须是“## 直接回答你的问题”，先给结论、关键数值，并在这一段简短写清“资料范围 / 分析口径 / 分析周期 / 对比周期 / 计算方式”。
        - “## AI 读取到的数据”必须放在直接回答和本地事实之后，作为核对信息，不要抢首屏。
        - 文件或全周期对比时，可加指标使用全周期 SUM；周均只能作为补充视角。
        - 人均、笔均、转化率、占比等派生指标必须用分子/分母重算或加权。
        - 所有关键数值优先引用下方 Notebook/SQL 证据，不能与证据方向或幅度冲突。
        - 禁止保留任何模板变量、占位符或示例字段名，例如 [H2_SUM]、[H1_Avg]、[Growth]、{{value}}、<metric_value>、TBD、待填、占位。
        - 禁止把“待计算”“待本地执行”“需全量 SUM 回填”“回填”“= SUM(...)”“SUM(分子)/SUM(分母)”这类计算计划、公式草稿或回填提示当成结果。
        - Markdown 表格单元格只能写真实数值、单位、百分比或明确缺失说明（未覆盖/无法从当前表格计算，并说明缺少哪个字段、指标或周期）。
        - 如果 Notebook/SQL 证据没有对应值，不要猜测，不要输出示例值，必须写明缺失边界。

        原始要求：
        \(originalPrompt)

        上一版错误回答：
        \(output)

        本轮 Notebook/SQL 证据：
        \(auditMarkdown)
        """
    }

    private static func unresolvedPlaceholderWarnings(in output: String) -> [String] {
        let examples = unresolvedPlaceholderExamples(in: output)
        guard !examples.isEmpty else { return [] }
        let sampleText = examples.prefix(6).joined(separator: "、")
        return [
            "AI 输出包含未替换的模板占位符或计算占位话术：\(sampleText)。必须用 Notebook/SQL 证据替换为真实数值；没有对应值时写“未覆盖/无法从当前表格计算”，并说明具体缺少的字段、指标或周期。"
        ]
    }

    private static func unresolvedPlaceholderExamples(in text: String) -> [String] {
        var examples: [String] = []
        func addExample(_ raw: String) {
            let trimmed = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            guard !trimmed.isEmpty else { return }
            let formatted = "`\(trimmed)`"
            if !examples.contains(formatted) {
                examples.append(formatted)
            }
        }

        for match in regexMatches(pattern: #"`?\[([A-Za-z][A-Za-z0-9_ .%-]{1,48})\]`?\s*%?"#, in: text) {
            guard let token = match.captures.first, isTemplatePlaceholderToken(token) else { continue }
            addExample(match.full)
        }

        for match in regexMatches(pattern: #"\{\{\s*([^{}\n]{1,80})\s*\}\}"#, in: text) {
            addExample(match.full)
        }

        for match in regexMatches(pattern: #"<([A-Za-z][A-Za-z0-9_ .%-]{1,48})>"#, in: text) {
            guard let token = match.captures.first, isTemplatePlaceholderToken(token) else { continue }
            addExample(match.full)
        }

        for match in regexMatches(pattern: #"\b(TBD|TODO|PLACEHOLDER)\b"#, in: text, options: [.caseInsensitive]) {
            addExample(match.full)
        }

        for keyword in ["待填", "占位", "待计算", "待本地执行", "需全量", "回填"] where text.localizedCaseInsensitiveContains(keyword) {
            addExample(keyword)
        }

        let formulaPatterns = [
            #"(?i)`?\s*=\s*(SUM|AVG|COUNT|MAX|MIN)\s*\([^`\n|]{1,120}\)`?"#,
            #"(?i)`?\s*(SUM|AVG|COUNT)\s*\([^`\n|]{1,80}\)\s*/\s*(SUM|AVG|COUNT)\s*\([^`\n|]{1,80}\)`?"#
        ]
        for pattern in formulaPatterns {
            for match in regexMatches(pattern: pattern, in: text) {
                addExample(match.full)
            }
        }

        return examples.uniqued()
    }

    private static func isTemplatePlaceholderToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return false }
        guard trimmed.range(of: #"^[A-Za-z][A-Za-z0-9_ .%-]{1,48}$"#, options: .regularExpression) != nil else { return false }
        let normalized = trimmed
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "%", with: "")
        if normalized.contains("_") { return true }
        let knownPlaceholderTokens = [
            "H1", "H2", "SUM", "AVG", "AVERAGE", "GROWTH", "VALUE", "METRIC",
            "COUNT", "AMOUNT", "USER", "USERS", "TRANSACTION", "PERIOD", "DATE",
            "RATE", "NUMERATOR", "DENOMINATOR", "TOTAL", "CURRENT", "PREVIOUS"
        ]
        return knownPlaceholderTokens.contains { normalized == $0 || normalized.contains($0) }
    }

    private static func regexMatches(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> [(full: String, captures: [String])] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, options: [], range: range).map { match in
            let full = nsText.substring(with: match.range(at: 0))
            let captures = (1..<match.numberOfRanges).compactMap { index -> String? in
                let captureRange = match.range(at: index)
                guard captureRange.location != NSNotFound else { return nil }
                return nsText.substring(with: captureRange)
            }
            return (full, captures)
        }
    }

    private static func auditFacts(from run: AnalysisNotebookRun) -> [AuditFact] {
        guard let cell = run.cells.first(where: { $0.title == "聚合口径审计" }) else { return [] }
        let columns = Dictionary(uniqueKeysWithValues: cell.columns.enumerated().map { ($0.element, $0.offset) })
        return cell.rows.compactMap { row in
            guard let metric = value("metric", row: row, columns: columns)?.nilIfBlank else { return nil }
            return AuditFact(
                report: value("source_report", row: row, columns: columns) ?? "",
                metric: metric,
                kind: value("metric_kind", row: row, columns: columns) ?? "",
                aggregationRule: value("aggregation_rule", row: row, columns: columns) ?? "",
                fullPeriodSum: doubleValue("full_period_sum", row: row, columns: columns),
                periodAverage: doubleValue("period_average", row: row, columns: columns),
                comparisonReport: value("comparison_report", row: row, columns: columns) ?? "",
                fullSumChangePercent: doubleValue("full_sum_change_percent", row: row, columns: columns),
                periodAverageChangePercent: doubleValue("period_average_change_percent", row: row, columns: columns)
            )
        }
    }

    private static func derivedFacts(from run: AnalysisNotebookRun) -> [DerivedFact] {
        guard let cell = run.cells.first(where: { $0.title == "派生指标重算审计" }) else { return [] }
        let columns = Dictionary(uniqueKeysWithValues: cell.columns.enumerated().map { ($0.element, $0.offset) })
        return cell.rows.compactMap { row in
            guard let metric = value("派生指标", row: row, columns: columns)?.nilIfBlank else { return nil }
            return DerivedFact(
                report: value("报表", row: row, columns: columns) ?? "",
                metric: metric,
                rule: value("正确口径", row: row, columns: columns) ?? "",
                recomputedValue: doubleValue("重算值", row: row, columns: columns),
                periodAverage: doubleValue("周期值均值", row: row, columns: columns),
                comparisonReport: value("对比报表", row: row, columns: columns) ?? "",
                recomputedChangePercent: doubleValue("重算变化%", row: row, columns: columns)
            )
        }
    }

    private static func periodComparisonFacts(from run: AnalysisNotebookRun) -> [PeriodComparisonFact] {
        guard let cell = run.cells.first(where: { $0.title == "关键指标计算结果" }) else { return [] }
        let columns = Dictionary(uniqueKeysWithValues: cell.columns.enumerated().map { ($0.element, $0.offset) })
        return cell.rows.compactMap { row in
            guard let metric = value("metric", row: row, columns: columns)?.nilIfBlank else { return nil }
            return PeriodComparisonFact(
                report: value("source_report", row: row, columns: columns) ?? "",
                metric: metric,
                kind: value("metric_kind", row: row, columns: columns) ?? "",
                baseValue: doubleValue("h2_sum", row: row, columns: columns),
                currentValue: doubleValue("h1_sum", row: row, columns: columns),
                changePercent: doubleValue("relative_change_percent", row: row, columns: columns)
            )
        }
    }

    private static func value(_ column: String, row: [String], columns: [String: Int]) -> String? {
        guard let index = columns[column], row.indices.contains(index) else { return nil }
        return row[index]
    }

    private static func doubleValue(_ column: String, row: [String], columns: [String: Int]) -> Double? {
        value(column, row: row, columns: columns)
            .flatMap { Double($0.replacingOccurrences(of: ",", with: "")) }
    }

    private static func sentences(in text: String, mentioning metric: String? = nil) -> [String] {
        let parts = text.components(separatedBy: CharacterSet(charactersIn: "。！？!?；;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let metric, !metric.isEmpty else { return parts }
        return parts.filter { $0.localizedCaseInsensitiveContains(metric) }
    }

    private static func containsDownwardClaim(_ text: String) -> Bool {
        ["下降", "下滑", "减少", "降低", "回落", "萎缩", "负增长"].contains { text.localizedCaseInsensitiveContains($0) }
    }

    private static func containsUpwardClaim(_ text: String) -> Bool {
        ["增长", "上升", "增加", "提升", "上涨", "扩张", "走高"].contains { text.localizedCaseInsensitiveContains($0) }
    }

    private static func containsSmallMovementClaim(_ text: String) -> Bool {
        if text.localizedCaseInsensitiveContains("小幅") || text.localizedCaseInsensitiveContains("轻微") {
            return true
        }
        let patterns = [
            #"不到\s*2(\.00)?%"#,
            #"不足\s*2(\.00)?%"#,
            #"1\s*[-~到至]\s*2(\.00)?%"#,
            #"1-2(\.00)?%"#,
            #"只下降\s*不到"#,
            #"只增长\s*不到"#
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private static func formatPercent(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
