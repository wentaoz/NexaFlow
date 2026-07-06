import Foundation

enum ValidationDisplayLevel: String, Hashable {
    case actionRequired
    case answerRisk
    case auditOnly
}

enum ValidationProductLevel: String, Hashable {
    case fatalBlock
    case needsConfirmation
    case autoRepairable
    case warningOnly
    case info

    var blocksFinalOutput: Bool {
        self == .fatalBlock
    }
}

struct ValidationDisplaySummary: Hashable {
    var issuesByDisplayLevel: [ValidationDisplayLevel: [ValidationIssue]]

    var actionRequiredIssues: [ValidationIssue] {
        issuesByDisplayLevel[.actionRequired] ?? []
    }

    var answerRiskIssues: [ValidationIssue] {
        issuesByDisplayLevel[.answerRisk] ?? []
    }

    var auditOnlyIssues: [ValidationIssue] {
        issuesByDisplayLevel[.auditOnly] ?? []
    }

    var hasMainSurfaceIssues: Bool {
        !actionRequiredIssues.isEmpty || !answerRiskIssues.isEmpty
    }

    var affectsSuccessfulStatus: Bool {
        !answerRiskIssues.isEmpty
    }

    var summaryText: String {
        "需确认 \(actionRequiredIssues.count)；影响结论 \(answerRiskIssues.count)；审计提示 \(auditOnlyIssues.count)"
    }

    func chatDetail(runID: UUID, verifiedResultCount: Int) -> String {
        "Run ID：\(runID.uuidString)；本地验证结果 \(verifiedResultCount) 个；\(summaryText)。"
    }
}

struct ValidationDecision: Hashable {
    var issuesByLevel: [ValidationProductLevel: [ValidationIssue]]

    var fatalIssues: [ValidationIssue] {
        issuesByLevel[.fatalBlock] ?? []
    }

    var confirmationIssues: [ValidationIssue] {
        issuesByLevel[.needsConfirmation] ?? []
    }

    var autoRepairableIssues: [ValidationIssue] {
        issuesByLevel[.autoRepairable] ?? []
    }

    var warningIssues: [ValidationIssue] {
        issuesByLevel[.warningOnly] ?? []
    }

    var blocksFinalOutput: Bool {
        !fatalIssues.isEmpty
    }

    var requiresUserAction: Bool {
        !fatalIssues.isEmpty || !confirmationIssues.isEmpty
    }

    var shouldAttemptRepair: Bool {
        !autoRepairableIssues.isEmpty || !fatalIssues.isEmpty
    }

    var productStatusLabel: String {
        if !fatalIssues.isEmpty { return "已阻断" }
        if !confirmationIssues.isEmpty { return "需要确认" }
        if !autoRepairableIssues.isEmpty { return "可自动修复" }
        if !warningIssues.isEmpty { return "保守输出" }
        return "已校验"
    }
}

enum ValidationDecisionEngine {
    static func decision(for issues: [ValidationIssue]) -> ValidationDecision {
        var grouped: [ValidationProductLevel: [ValidationIssue]] = [:]
        for issue in issues {
            grouped[classify(issue), default: []].append(issue)
        }
        return ValidationDecision(issuesByLevel: grouped)
    }

    static func displaySummary(for issues: [ValidationIssue]) -> ValidationDisplaySummary {
        var grouped: [ValidationDisplayLevel: [ValidationIssue]] = [:]
        for issue in issues {
            grouped[displayLevel(for: issue), default: []].append(issue)
        }
        return ValidationDisplaySummary(issuesByDisplayLevel: grouped)
    }

    static func classify(_ issue: ValidationIssue) -> ValidationProductLevel {
        switch issue.code {
        case .placeholderOutput,
             .unverifiedNumber,
             .ambiguousNumberTrace,
             .hiddenWarning,
             .missingField,
             .missingTable,
             .schemaError,
             .unsupportedOperation,
             .unsafeJoin,
             .grainMismatch,
             .rateAggregationError,
             .formulaMismatch,
             .emptyResult,
             .aiIntentParsingFailed:
            return issue.severity == .info ? .info : .fatalBlock

        case .insufficientData:
            if issue.severity == .fatal || issue.severity == .error {
                return .fatalBlock
            }
            return issue.severity == .info ? .info : .warningOnly

        case .ambiguousFieldMapping,
             .missingAssumption,
             .distinctCountRisk,
             .duplicateRecordRisk,
             .dataContractViolation:
            if issue.severity == .fatal { return .fatalBlock }
            if issue.severity == .error { return .needsConfirmation }
            return issue.severity == .info ? .info : .warningOnly

        case .missingMethodology,
             .missingCitation,
             .evidenceBoundaryMissing,
             .causalBoundaryRisk:
            return issue.severity == .info ? .info : .autoRepairable

        case .externalNumberMixedWithLocalMetric,
             .unverifiedClaim:
            return issue.severity == .fatal ? .fatalBlock : .warningOnly
        }
    }

    static func displayLevel(for issue: ValidationIssue) -> ValidationDisplayLevel {
        let productLevel = classify(issue)
        if productLevel == .fatalBlock || productLevel == .needsConfirmation {
            return .actionRequired
        }

        switch issue.code {
        case .externalNumberMixedWithLocalMetric,
             .unverifiedClaim,
             .missingCitation,
             .causalBoundaryRisk,
             .distinctCountRisk,
             .duplicateRecordRisk:
            return issue.severity == .info ? .auditOnly : .answerRisk

        case .ambiguousFieldMapping,
             .dataContractViolation:
            return issue.severity == .warning || issue.severity == .info ? .auditOnly : .actionRequired

        case .missingAssumption,
             .missingMethodology,
             .evidenceBoundaryMissing:
            return .auditOnly

        case .placeholderOutput,
             .unverifiedNumber,
             .ambiguousNumberTrace,
             .hiddenWarning,
             .missingField,
             .missingTable,
             .schemaError,
             .unsupportedOperation,
             .unsafeJoin,
             .grainMismatch,
             .rateAggregationError,
             .formulaMismatch,
             .emptyResult,
             .aiIntentParsingFailed:
            return .actionRequired

        case .insufficientData:
            if issue.severity == .fatal || issue.severity == .error {
                return .actionRequired
            }
            return issue.severity == .warning ? .answerRisk : .auditOnly
        }
    }
}

enum AnalysisOutputRepairer {
    static func repair(
        _ report: String,
        contextEvidence: ContextEvidenceManifest?,
        issues: [ValidationIssue]
    ) -> String {
        var repaired = normalizeDirectAnswerHeading(report)
        if issues.contains(where: { $0.code == .causalBoundaryRisk }) {
            repaired = downgradeHardCausalClaims(in: repaired)
        }
        if issues.contains(where: { $0.code == .missingCitation }),
           let contextEvidence,
           !contextEvidence.items.isEmpty {
            repaired = addMissingCitation(in: repaired, using: contextEvidence)
        }
        if issues.contains(where: { $0.code == .evidenceBoundaryMissing }),
           let contextEvidence {
            repaired = ensureEvidenceBoundary(in: repaired, contextEvidence: contextEvidence)
        }
        return repaired
    }

    static func normalizeDirectAnswerHeading(_ report: String) -> String {
        var lines = report.components(separatedBy: .newlines)
        guard let headingIndex = lines.firstIndex(where: { parseHeading($0) != nil }) else {
            let trimmed = report.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return report }
            return "## 直接回答你的问题\n\(trimmed)"
        }

        guard let heading = parseHeading(lines[headingIndex]),
              isDirectAnswerSynonym(heading),
              normalizedHeading(heading) != normalizedHeading("直接回答你的问题") else {
            return report
        }
        lines[headingIndex] = "## 直接回答你的问题"
        return lines.joined(separator: "\n")
    }

    static func downgradeHardCausalClaims(in report: String) -> String {
        var output = report
        let replacements: [(String, String)] = [
            ("根因是", "候选原因是"),
            ("主因是", "可能贡献因素是"),
            ("主要原因是", "候选原因是"),
            ("确认由", "可能与"),
            ("确定由", "可能与")
        ]
        for (from, to) in replacements {
            output = output.replacingOccurrences(of: from, with: to)
        }
        output = output.replacingOccurrences(of: #"(?<!不)导致"#, with: "可能影响", options: .regularExpression)
        if !output.contains("候选原因") && !output.contains("贡献分解") && !output.contains("需验证") {
            output += "\n\n## 归因边界\n- 上述归因仅作为候选原因和贡献分解线索，仍需结合反证、分层数据或业务动作日志验证。"
        }
        return output
    }

    static func addMissingCitation(in report: String, using contextEvidence: ContextEvidenceManifest) -> String {
        guard let firstLabel = contextEvidence.items.first?.citationLabel.nilIfBlank else { return report }
        let citation = "[\(firstLabel)]"
        if report.contains(citation) { return report }

        var lines = report.components(separatedBy: .newlines)
        let keywords = ["知识库", "Confluence", "Jira", "钉钉", "外部", "政策", "竞品", "新闻", "资料", "证据"]
        if let index = lines.firstIndex(where: { line in
            keywords.contains { line.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }) {
            lines[index] = lines[index].trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(citation)
                ? lines[index]
                : "\(lines[index]) \(citation)"
            return lines.joined(separator: "\n")
        }
        return report + "\n\n## 资料证据\n- 本轮资料证据已按引用边界使用：\(citation)。"
    }

    static func ensureEvidenceBoundary(in report: String, contextEvidence: ContextEvidenceManifest) -> String {
        if report.range(of: "资料证据") != nil || report.range(of: "证据边界") != nil {
            return report
        }
        let labels = contextEvidence.items.map { "[\($0.citationLabel)]" }.joined(separator: "、")
        let labelText = labels.nilIfBlank ?? "本轮未命中资料证据"
        return report + "\n\n## 资料证据\n- 非表格资料只用于解释、限制和建议，不参与本地表格指标计算。证据：\(labelText)。"
    }

    private static func parseHeading(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("##"), !trimmed.hasPrefix("###") else { return nil }
        return trimmed
            .drop(while: { $0 == "#" || $0 == " " })
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
    }

    private static func isDirectAnswerSynonym(_ heading: String) -> Bool {
        let normalized = normalizedHeading(heading)
        let synonyms = [
            "直接回答你的问题",
            "直接回答",
            "直接结论",
            "核心结论",
            "核心判断",
            "结论",
            "回答",
            "结论摘要"
        ]
        return synonyms.contains { normalized == normalizedHeading($0) }
    }

    private static func normalizedHeading(_ heading: String) -> String {
        heading
            .replacingOccurrences(of: #"^\d+[\.\、]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "：", with: ":")
            .lowercased()
    }
}
