import Foundation

enum AIOpportunityExtractionService {
    static func extract(
        aiOutput: String,
        session: AnalysisSession,
        pack: DataPack,
        task: AnalysisTask?,
        reports: [ImportedReport],
        workspace: ProductWorkspace,
        settings: AISettings
    ) async throws -> (opportunities: [ProductOpportunity], record: AIJobRecord) {
        let prompt = buildPrompt(
            aiOutput: aiOutput,
            session: session,
            pack: pack,
            task: task,
            reports: reports,
            workspace: workspace
        )
        let queue = AIJobQueue(maxAttempts: 6)
        let result = try await queue.runTextJob(
            prompt: prompt,
            settings: settings,
            jobType: "AI 机会评分抽取",
            validation: { raw in
                parse(raw, session: session) == nil ? ["机会评分必须输出 JSON 对象，且包含 opportunities 数组。"] : []
            },
            correctionPrompt: { originalPrompt, output, warnings in
                """
                机会评分 JSON 没有通过校验。请只输出修正后的 JSON，不要输出 Markdown。
                校验问题：\(warnings.joined(separator: "；"))

                原始要求：
                \(originalPrompt)

                上次输出：
                \(output)
                """
            }
        )
        return (parse(result.output, session: session) ?? [], result.record)
    }

    private static func buildPrompt(
        aiOutput: String,
        session: AnalysisSession,
        pack: DataPack,
        task: AnalysisTask?,
        reports: [ImportedReport],
        workspace: ProductWorkspace
    ) -> String {
        let reportText = reports.map { report in
            let trends = report.trendSummary.metricTrends.prefix(24).map { trend in
                if let comparison = trend.primaryComparison {
                    return "\(trend.metricName)：\(comparison.currentLabel) vs \(comparison.previousLabel)，\(comparison.previousValue.compactText) -> \(comparison.currentValue.compactText)，\(comparison.direction.rawValue)"
                }
                return "\(trend.metricName)：\(trend.firstValue.compactText) -> \(trend.lastValue.compactText)，\(trend.direction.rawValue)"
            }.joined(separator: "；")
            return "- \(report.displayName)：\(report.kind.label)，\(report.shape.label)，关键趋势：\(trends.isEmpty ? "暂无趋势" : trends)"
        }.joined(separator: "\n")

        let metricLinks = task?.businessLinkProfile.metricLinks
            .filter { $0.confirmationStatus != .rejected }
            .prefix(20)
            .map { "- \($0.sourceMetric) -> \($0.targetMetric)：\($0.relationType.label)，证据 \($0.evidenceLevel.rawValue)" }
            .joined(separator: "\n") ?? ""

        let linkageAnomalies = task?.businessLinkProfile.metricLinkageAnomalies
            .filter { $0.confirmationStatus != .rejected && $0.confidence >= 0.5 }
            .prefix(20)
            .map { "- [\($0.anomalyType.label)] \($0.sourceMetric) -> \($0.targetMetric)：\($0.changeGapText)，\($0.businessRelation)，证据 \($0.evidenceLevel.rawValue)" }
            .joined(separator: "\n") ?? ""

        let businessSpaceID = session.businessSpaceID ?? task?.businessSpaceID ?? pack.businessSpaceID ?? workspace.selectedBusinessSpaceID
        let sourceByID = Dictionary(uniqueKeysWithValues: workspace.referenceSources.map { ($0.id, $0) })
        let references = workspace.referenceItems
            .filter { $0.isRelevant && $0.isVisible(in: businessSpaceID, sourceByID: sourceByID) }
            .sorted { $0.displayDate > $1.displayDate }
            .prefix(16)
            .map { "- \(DateFormatting.shortDate.string(from: $0.displayDate))（\($0.dateBasisLabel)）[\($0.domain.label)] \($0.title)：\($0.summary)" }
            .joined(separator: "\n")

        return """
        你是产品机会评分抽取器。请把当前 AI 分析结论转换成结构化候选机会，用于产品负责人排序。

        \(FinancialPromptPolicy.coreSystemPrompt)

        严格规则：
        \(FinancialPromptPolicy.opportunityRules)

        - 只基于当前分析任务、当前 AI 回复和下方证据抽取机会，不要编造没有证据的机会。
        - 如果没有足够可行动机会，可以返回空数组。
        - 每个评分维度必须是 1-10 的整数。
        - confidence 必须体现证据强弱；假设型机会不要高于 5。
        - effort 越高表示成本越高；risk 越高表示风险越高。
        - 输出 JSON 对象，不要输出 Markdown。

        输出 JSON：
        {
          "opportunities": [
            {
              "title": "机会标题",
              "problem": "要解决的问题",
              "affected_users": "影响用户/范围",
              "expected_impact": 1,
              "confidence": 1,
              "urgency": 1,
              "effort": 1,
              "risk": 1,
              "strategic_fit": 1,
              "evidence_summary": "关键证据"
            }
          ]
        }

        数据包：\(pack.name)
        当前任务：\(task?.name ?? "未命名任务")
        本次目标：\(session.goal.nilIfBlank ?? task?.goal.nilIfBlank ?? "未填写")

        当前任务报表：
        \(reportText.isEmpty ? "暂无" : reportText)

        指标级联动：
        \(metricLinks.isEmpty ? "暂无" : metricLinks)

        指标联动异常候选：
        \(linkageAnomalies.isEmpty ? "暂无" : linkageAnomalies)

        外部参照：
        \(references.isEmpty ? "暂无" : references)

        最新 AI 分析回复：
        \(clipped(aiOutput, to: 12_000))
        """
    }

    private static func parse(_ raw: String, session: AnalysisSession) -> [ProductOpportunity]? {
        guard let data = extractJSONObject(from: raw).data(using: .utf8),
              let payload = try? JSONDecoder().decode(OpportunityPayload.self, from: data) else {
            return nil
        }
        return payload.opportunities.prefix(20).map { item in
            ProductOpportunity(
                title: item.title.nilIfBlank ?? "未命名机会",
                problem: item.problem.nilIfBlank ?? "AI 未说明问题",
                affectedUsers: item.affectedUsersValue.nilIfBlank ?? "未限定",
                expectedImpact: item.expectedImpactValue ?? 3,
                confidence: item.confidence ?? 3,
                urgency: item.urgency ?? 3,
                effort: item.effort ?? 5,
                risk: item.risk ?? 5,
                strategicFit: item.strategicFitValue ?? 5,
                sourceSessionID: session.id,
                sourceSessionTitle: session.title,
                generatedAt: Date(),
                isAIGenerated: true,
                isUserConfirmed: false,
                evidenceSummary: item.evidenceSummaryValue.nilIfBlank ?? ""
            )
        }
    }

    private static func extractJSONObject(from value: String) -> String {
        guard let start = value.firstIndex(of: "{"),
              let end = value.lastIndex(of: "}"),
              start <= end else {
            return value
        }
        return String(value[start...end])
    }

    private static func clipped(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n...[已截断]"
    }
}

private struct OpportunityPayload: Decodable {
    var opportunities: [OpportunityItem]
}

private struct OpportunityItem: Decodable {
    var title: String
    var problem: String
    var affectedUsers: String?
    var affectedUsersSnake: String?
    var expectedImpact: Int?
    var expectedImpactSnake: Int?
    var confidence: Int?
    var urgency: Int?
    var effort: Int?
    var risk: Int?
    var strategicFit: Int?
    var strategicFitSnake: Int?
    var evidenceSummary: String?
    var evidenceSummarySnake: String?

    var affectedUsersValue: String { affectedUsersSnake ?? affectedUsers ?? "" }
    var expectedImpactValue: Int? { expectedImpactSnake ?? expectedImpact }
    var strategicFitValue: Int? { strategicFitSnake ?? strategicFit }
    var evidenceSummaryValue: String { evidenceSummarySnake ?? evidenceSummary ?? "" }

    enum CodingKeys: String, CodingKey {
        case title
        case problem
        case affectedUsers
        case affectedUsersSnake = "affected_users"
        case expectedImpact
        case expectedImpactSnake = "expected_impact"
        case confidence
        case urgency
        case effort
        case risk
        case strategicFit
        case strategicFitSnake = "strategic_fit"
        case evidenceSummary
        case evidenceSummarySnake = "evidence_summary"
    }
}
