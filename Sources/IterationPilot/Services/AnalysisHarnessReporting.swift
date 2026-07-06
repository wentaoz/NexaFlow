import Foundation

struct HarnessReportGenerator {
    func generate(
        userQuery: String,
        sourcePolicy: AnalysisContextSourcePolicy,
        plan: AnalysisPlan,
        manifests: [TableManifest],
        contextEvidence: ContextEvidenceManifest?,
        results: [MetricResult],
        issues: [ValidationIssue],
        settings: AISettings,
        onDelta: ((_ accumulatedText: String) async -> Void)? = nil
    ) async -> String {
        let deterministic = Self.deterministicReport(
            userQuery: userQuery,
            sourcePolicy: sourcePolicy,
            plan: plan,
            manifests: manifests,
            contextEvidence: contextEvidence,
            results: results,
            issues: issues
        )
        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await Self.emitDeterministicReport(deterministic, onDelta: onDelta)
            return deterministic
        }
        let prompt = Self.reportPrompt(
            userQuery: userQuery,
            sourcePolicy: sourcePolicy,
            plan: plan,
            manifests: manifests,
            contextEvidence: contextEvidence,
            results: results,
            issues: issues
        )
        do {
            let streamingResult = try await AIStreamingService().runStreamingAnalysis(
                prompt: prompt,
                settings: settings,
                onProgress: { _ in },
                onDelta: { accumulated in
                    await onDelta?(accumulated)
                }
            )
            let output = streamingResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if streamingResult.didReceiveStreamDeltas, !output.isEmpty {
                return streamingResult.output
            }
            await Self.emitDeterministicReport(deterministic, onDelta: onDelta)
            return deterministic
        } catch {
            await Self.emitDeterministicReport(deterministic, onDelta: onDelta)
            return deterministic
        }
    }

    static func deterministicReport(
        userQuery: String,
        sourcePolicy: AnalysisContextSourcePolicy,
        plan: AnalysisPlan,
        manifests: [TableManifest],
        contextEvidence: ContextEvidenceManifest?,
        results: [MetricResult],
        issues: [ValidationIssue]
    ) -> String {
        let methodology = plan.assumptions.first { $0.label != "意图解析" }?.detail
            ?? "默认对可加指标使用 SUM；比例/派生指标需由分子分母重算。"
        let primaryResults = results.filter { $0.presentationRole.isPrimaryAnswerRole }
        let supportingResults = results.filter { !$0.presentationRole.isPrimaryAnswerRole }
        let resultRows = primaryResults.prefix(30).map { result in
            "| \(result.label) | \(result.displayValue) | \(result.source.methodology) | \(result.source.tableName) |"
        }.joined(separator: "\n")
        let supportingRows = supportingResults.prefix(30).map { result in
            "| \(result.label) | \(result.displayValue) | \(result.source.methodology) | \(result.source.tableName) |"
        }.joined(separator: "\n")
        let warningLines = issues
            .filter { $0.severity != .info }
            .map { "- \( $0.severity.label ) \( $0.code.rawValue)：\($0.message)" }
            .joined(separator: "\n")
        let manifestLines = manifests.map { manifest in
            "- \(manifest.displayName)：\(manifest.rowCount) 行 × \(manifest.columnCount) 列；\(manifest.sourceType)；粒度 \(manifest.detectedGrain.kind.rawValue)。"
        }.joined(separator: "\n")
        let contextLines = contextEvidence?.items.prefix(12).map { item in
            "- [\(item.citationLabel)] \(item.sourceType.label)：\(item.title) — \(item.summary)"
        }.joined(separator: "\n") ?? ""
        let contextWarningLines = contextEvidence?.warnings.map { "- \($0)" }.joined(separator: "\n") ?? ""
        let contextSection: String
        if contextLines.isEmpty, contextWarningLines.isEmpty {
            contextSection = "- 本轮未启用知识库/外部参照；非表格资料没有参与本地数值计算。"
        } else {
            contextSection = [
                contextLines.nilIfBlank,
                contextWarningLines.nilIfBlank
            ]
            .compactMap { $0 }
            .joined(separator: "\n")
        }
        let directSentence: String
        if primaryResults.isEmpty {
            directSentence = "当前选表没有产生可验证数值，因此不输出业务结论。"
        } else {
            let sample = primaryResults.prefix(6).map { "\($0.label)：\($0.displayValue)" }.joined(separator: "；")
            directSentence = "本地 Harness 已完成可验证计算，直接回答如下：\(sample)。"
        }
        return """
        ## 直接回答你的问题
        资料范围：\(sourcePolicy.label)。分析口径：\(methodology)

        \(directSentence)

        ## 本地已校验事实
        | 指标 | 本地计算结果 | 计算方式 | 来源 |
        |---|---:|---|---|
        \(resultRows.isEmpty ? "| 未覆盖 | 未覆盖 | 当前表无法计算指定指标 | 当前选表 |" : resultRows)

        ## 计算依赖
        | 指标 | 本地计算结果 | 计算方式 | 来源 |
        |---|---:|---|---|
        \(supportingRows.isEmpty ? "| 无需额外依赖 | - | 本轮主指标可直接计算 | 当前选表 |" : supportingRows)

        ## 关键数据证据
        \(warningLines.isEmpty ? "- 本轮未发现阻断性校验问题。" : warningLines)

        ## 资料证据
        \(contextSection)

        ## AI 读取到的数据
        \(manifestLines.isEmpty ? "- 当前任务没有选表。" : manifestLines)

        ## 未覆盖/需补数据
        \(plan.limitations.isEmpty ? "- 无额外缺口。" : plan.limitations.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    private static func reportPrompt(
        userQuery: String,
        sourcePolicy: AnalysisContextSourcePolicy,
        plan: AnalysisPlan,
        manifests: [TableManifest],
        contextEvidence: ContextEvidenceManifest?,
        results: [MetricResult],
        issues: [ValidationIssue]
    ) -> String {
        let planJSON = (try? String(data: JSONEncoder.harnessEncoder.encode(plan), encoding: .utf8)) ?? "{}"
        let manifestJSON = (try? String(data: JSONEncoder.harnessEncoder.encode(manifests), encoding: .utf8)) ?? "[]"
        let contextEvidenceJSON = (try? String(data: JSONEncoder.harnessEncoder.encode(contextEvidence), encoding: .utf8)) ?? "null"
        let resultJSON = (try? String(data: JSONEncoder.harnessEncoder.encode(results), encoding: .utf8)) ?? "[]"
        let issueJSON = (try? String(data: JSONEncoder.harnessEncoder.encode(issues), encoding: .utf8)) ?? "[]"
        return """
        你是 Analysis Harness 的报告解释层。只能解释 verified_results 中的表格数字，不能新增任何未验证数字。
        输出 Markdown，第一段必须是：
        ## 直接回答你的问题
        然后先直接回答用户问题，再依次给：
        ## 本地已校验事实
        ## 关键数据证据
        ## 资料证据
        ## AI 读取到的数据
        ## 未覆盖/需补数据

        verified_results 中 presentationRole 的使用规则：
        - 直接回答只展示 requested 和 derived_requested。
        - supporting 只用于解释分子/分母和计算依赖，不能替代用户请求指标出现在直接回答里。
        - diagnostic 只用于补充校验或诊断，用户未要求时不要放进直接回答。
        - 如果 requested / derived_requested 为空，必须说明未能计算用户请求指标，不能用 supporting 冒充答案。

        禁止输出 [H2_SUM]、[Growth]、TBD、待计算、需回填、= SUM(...) 等占位或公式计划。
        对所有 warning 必须展示，不能隐藏。
        如果引用知识库、Confluence、Jira、钉钉或外部参照，必须使用 context_evidence 中的 citationLabel，例如 [K1]、[C2]、[E1]。
        非表格资料只允许用于解释、限制和建议，不允许把外部资料数字混成本地表格指标。
        若 context_evidence 为空或没有命中资料，必须明确写“本轮未启用/未命中资料证据”，不要编造来源。
        如果回答原因/归因类问题，本版本只能写“候选原因”“贡献分解”“弱信号”或“无法高置信归因”；没有反证覆盖时禁止写“导致”“根因”“主因”“确认由”等因果定论。

        用户问题：
        \(userQuery)

        资料范围：\(sourcePolicy.label)

        AnalysisPlan JSON：
        \(planJSON)

        TableManifest JSON：
        \(manifestJSON)

        context_evidence JSON：
        \(contextEvidenceJSON)

        verified_results JSON：
        \(resultJSON)

        validation_issues JSON：
        \(issueJSON)
        """
    }

    private static func emitDeterministicReport(_ report: String, onDelta: ((_ accumulatedText: String) async -> Void)?) async {
        guard let onDelta else { return }
        var accumulated = ""
        let chunks = report.components(separatedBy: "\n\n")
        for chunk in chunks {
            accumulated += accumulated.isEmpty ? chunk : "\n\n\(chunk)"
            await onDelta(accumulated)
            try? await Task.sleep(nanoseconds: 12_000_000)
        }
    }
}

struct ReportValidator {
    static func validate(
        report: String,
        verifiedResults: [MetricResult],
        contextEvidence: ContextEvidenceManifest?,
        issues: [ValidationIssue]
    ) -> [ValidationIssue] {
        var validationIssues: [ValidationIssue] = []
        let trimmed = report.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.hasPrefix("## 直接回答你的问题") {
            validationIssues.append(ValidationIssue(
                severity: .fatal,
                code: .missingMethodology,
                stage: .reportValidation,
                message: "报告没有先用“## 直接回答你的问题”开头。"
            ))
        }
        if report.range(of: "AI 读取到的数据") == nil {
            validationIssues.append(ValidationIssue(
                severity: .warning,
                code: .missingMethodology,
                stage: .reportValidation,
                message: "报告缺少 AI 读取范围说明。"
            ))
        }
        let placeholderPatterns = [
            #"\[[A-Za-z0-9]+_[A-Za-z0-9_]+\]"#,
            #"\[(Growth|Metric|Value|Period|Amount|Count|Rate)[A-Za-z0-9_]*\]"#,
            #"\{\{[^}]+\}\}"#,
            #"<[A-Za-z0-9_]+>"#,
            #"TBD"#,
            #"待计算"#,
            #"待填"#,
            #"占位"#,
            #"需全量\s*SUM\s*回填"#,
            #"=\s*SUM\s*\("#
        ]
        let placeholderProbe = placeholderValidationText(in: report)
        for pattern in placeholderPatterns where placeholderProbe.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
            validationIssues.append(ValidationIssue(
                severity: .fatal,
                code: .placeholderOutput,
                stage: .reportValidation,
                message: "报告包含未替换模板变量、占位符或计算计划：\(pattern)。"
            ))
            break
        }

        let blockingIssueCodes = Set(issues.filter { $0.severity.blocksOutput || $0.severity == .warning }.map(\.code.rawValue))
        for code in blockingIssueCodes where !report.contains(code) && issues.contains(where: { $0.code.rawValue == code && $0.severity.blocksOutput }) {
            validationIssues.append(ValidationIssue(
                severity: .fatal,
                code: .hiddenWarning,
                stage: .reportValidation,
                message: "报告隐藏了阻断性校验问题：\(code)。"
            ))
        }

        if let contextEvidence, !contextEvidence.items.isEmpty {
            let citationLabels = contextEvidence.items.map(\.citationLabel)
            let hasCitation = citationLabels.contains { report.contains("[\($0)]") }
            let mentionsContextSource = Self.contextKeywords.contains { keyword in
                report.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
            if mentionsContextSource, !hasCitation {
                validationIssues.append(ValidationIssue(
                    severity: .fatal,
                    code: .missingCitation,
                    stage: .reportValidation,
                    message: "报告引用了知识库/外部资料类判断，但没有使用 [K1]/[C1]/[E1] 等资料证据引用。",
                    fixHint: "所有非表格证据判断必须标注 context_evidence 中的 citationLabel。"
                ))
            }
            if contextEvidence.sourcePolicy != .tableOnly,
               report.range(of: "资料证据") == nil,
               !hasCitation {
                validationIssues.append(ValidationIssue(
                    severity: .warning,
                    code: .evidenceBoundaryMissing,
                    stage: .reportValidation,
                    message: "报告没有说明非表格资料证据的使用边界。",
                    fixHint: "增加“资料证据”段，并声明非表格资料只用于解释、限制和建议。"
                ))
            }
        }

        let traceReport = AnswerNumberTracer.trace(report: report, verifiedResults: verifiedResults)
        let blockingTraces = traceReport.blockingTraces
        if !blockingTraces.isEmpty, !verifiedResults.isEmpty {
            let ambiguous = blockingTraces.filter { $0.status == .ambiguous }
            let code: AnalysisHarnessValidationCode = ambiguous.isEmpty ? .unverifiedNumber : .ambiguousNumberTrace
            validationIssues.append(ValidationIssue(
                severity: .fatal,
                code: code,
                stage: .reportValidation,
                message: "报告主回答出现未能可靠追溯的数字：\(blockingTraces.prefix(5).map(\.rawText).joined(separator: "、"))。",
                fixHint: "解释层只能使用 verified_results 中可追溯数字；歧义数字必须改写或删除。",
                evidence: [
                    "traces": blockingTraces.prefix(5).map { "\($0.rawText):\($0.status.rawValue):\($0.reason)" }.joined(separator: " | ")
                ]
            ))
            if contextEvidence?.sourcePolicy.includeExternalReferences == true,
               Self.contextKeywords.contains(where: { report.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }) {
                validationIssues.append(ValidationIssue(
                    severity: .warning,
                    code: .externalNumberMixedWithLocalMetric,
                    stage: .reportValidation,
                    message: "报告同时出现外部资料语境和未验证数字，可能把外部数字混成本地指标。",
                    fixHint: "表格指标数字只能来自 verified_results；外部数字必须标注来源并说明不能作为本地表格指标。"
                ))
            }
        }
        let causalTerms = ["导致", "根因", "主因", "是因为", "确认由", "确定由"]
        let hasHardCausalClaim = causalTerms.contains { report.contains($0) }
        let hasBoundary = report.contains("候选原因") || report.contains("贡献分解") || report.contains("非因果")
        if hasHardCausalClaim, !hasBoundary {
            validationIssues.append(ValidationIssue(
                severity: .fatal,
                code: .causalBoundaryRisk,
                stage: .reportValidation,
                message: "报告包含强因果表述，但没有声明候选原因/贡献分解边界。",
                fixHint: "根因调查 v1 只能输出候选原因和贡献分解，不得输出因果定论。"
            ))
        }
        return validationIssues
    }

    static func repair(
        userQuery: String,
        sourcePolicy: AnalysisContextSourcePolicy,
        plan: AnalysisPlan,
        manifests: [TableManifest],
        contextEvidence: ContextEvidenceManifest?,
        results: [MetricResult],
        issues: [ValidationIssue]
    ) -> String {
        HarnessReportGenerator.deterministicReport(
            userQuery: userQuery,
            sourcePolicy: sourcePolicy,
            plan: plan,
            manifests: manifests,
            contextEvidence: contextEvidence,
            results: results,
            issues: issues
        )
    }

    private static let contextKeywords = [
        "知识库", "Confluence", "Jira", "钉钉", "外部", "政策", "竞品", "新闻", "市场", "文档",
        "活动", "上线", "需求", "资料", "参照", "证据"
    ]

    private static func placeholderValidationText(in report: String) -> String {
        let excludedHeadingKeywords = [
            "用户问题",
            "原始问题",
            "原始要求",
            "引用原文",
            "字段",
            "AI读取到的数据",
            "AI 读取到的数据"
        ]
        let normalizedExcluded = excludedHeadingKeywords.map {
            $0.replacingOccurrences(of: " ", with: "").lowercased()
        }
        var keepCurrentSection = true
        var retainedLines: [String] = []

        for line in report.components(separatedBy: .newlines) {
            if let heading = headingTitle(line) {
                let normalizedHeading = heading.replacingOccurrences(of: " ", with: "").lowercased()
                keepCurrentSection = !normalizedExcluded.contains { normalizedHeading.contains($0) }
            }
            if keepCurrentSection {
                retainedLines.append(line)
            }
        }

        return retainedLines.joined(separator: "\n")
    }

    private static func headingTitle(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("##"), !trimmed.hasPrefix("###") else { return nil }
        return trimmed
            .drop(while: { $0 == "#" || $0 == " " })
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
    }
}
