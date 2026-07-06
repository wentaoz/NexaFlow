import Foundation

struct ReportQAOutput {
    var answer: String
    var evidence: [String]
    var uncertainties: [String]
    var suggestedMemories: [ReportQAMemoryCandidate]
    var profilePatch: ReportSemanticProfile?
    var fieldPatches: [ReportQAFieldPatch]
}

enum ReportQAService {
    static func fallbackAnswer(
        question: String,
        report: ImportedReport,
        fieldDefinitions: [ReportFieldDefinition],
        reportMemories: [ReportKnowledgeMemory],
        knowledgeEntries: [KnowledgeEntry]
    ) -> ReportQAOutput {
        let partialTrends = report.trendSummary.metricTrends.filter { $0.latestPointIsPartial == true }
        var answer: [String] = []
        answer.append("我先基于本地解析结果回答。")
        answer.append("这张表是 \(report.sourceFormat.label) 来源，结构识别为 \(report.shape.label)，类型为 \(report.kind.label)，共有 \(report.rowCount) 行、\(report.headers.count) 个表头字段、\(report.firstColumnValues.count) 个首列指标。")
        if let first = report.trendSummary.trendBullets.first {
            answer.append("当前趋势扫描要点：\(first)")
        }
        if !partialTrends.isEmpty {
            let examples = partialTrends.prefix(5).map {
                "\($0.metricName)（\($0.partialLatestLabel ?? "最新周期")：\($0.partialLatestPointReason ?? "未完整")）"
            }.joined(separator: "、")
            answer.append("需要特别注意：\(partialTrends.count) 个指标可能存在滞后或成熟口径；本地不预先排除周期，需结合用户口径判断，包括 \(examples)。")
        }
        if !report.semanticProfile.summary.isEmpty {
            answer.append("已知报表说明：\(report.semanticProfile.summary)")
        }
        if !reportMemories.isEmpty {
            answer.append("已命中 \(reportMemories.count) 条相似报表记忆，可作为后续判断参考。")
        }
        let evidence = [
            "来源格式：\(report.sourceFormat.label)\(report.sheetName.map { " / \($0)" } ?? "")",
            "结构：\(report.shape.label)，类型：\(report.kind.label)",
            "字段预览：\(DataImportService.fieldDefinitionNames(for: report).prefix(12).joined(separator: "，"))",
            report.trendSummary.distributionBullets.first
        ].compactMap { $0?.nilIfBlank }
        let memoryContent = [
            report.semanticProfile.summary.nilIfBlank,
            partialTrends.isEmpty ? nil : "这类报表存在最新周期成熟度风险：\(partialTrends.map(\.metricName).prefix(5).joined(separator: "，")) 需要按完整周期判断趋势。"
        ].compactMap { $0 }.joined(separator: "\n")
        let suggested = memoryContent.isEmpty ? [] : [
            ReportQAMemoryCandidate(
                title: "\(report.kind.label)报表识别规则",
                content: memoryContent,
                scope: "similarReports"
            )
        ]
        return ReportQAOutput(
            answer: answer.joined(separator: "\n\n"),
            evidence: evidence,
            uncertainties: [
                "本地兜底没有调用大模型，只能依据解析结果、趋势摘要和已有记忆回答。",
                "筛选条件、实验组、人群范围和业务口径仍需要你确认。"
            ],
            suggestedMemories: suggested,
            profilePatch: report.semanticProfile,
            fieldPatches: fieldDefinitions
                .filter { $0.reportID == report.id && !$0.meaning.isEmpty }
                .prefix(8)
                .map { ReportQAFieldPatch(fieldName: $0.fieldName, meaning: $0.meaning, notes: $0.notes) }
        )
    }

    static func prompt(
        question: String,
        report: ImportedReport,
        fieldDefinitions: [ReportFieldDefinition],
        reportMemories: [ReportKnowledgeMemory],
        knowledgeEntries: [KnowledgeEntry],
        referenceItems: [ExternalReferenceItem]
    ) -> String {
        let fieldText = fieldDefinitions
            .filter { $0.reportID == report.id || $0.reportName == report.fileName }
            .prefix(80)
            .map { "- \($0.fieldName)：\($0.meaning.isEmpty ? "未填写" : $0.meaning)；类型 \($0.dataType)；样例 \($0.exampleValue)；备注 \($0.notes)" }
            .joined(separator: "\n")
        let memoryText = reportMemories
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(20)
            .map { "- \($0.title)：\($0.content)" }
            .joined(separator: "\n")
        let knowledgeText = knowledgeEntries
            .filter { $0.tags.contains(where: { $0.normalizedKey.contains("报表知识".normalizedKey) }) }
            .prefix(20)
            .map { "- \(KnowledgeEventAxis.compactContext(for: $0))" }
            .joined(separator: "\n")
        let referenceText = referenceItems
            .sorted { $0.displayDate > $1.displayDate }
            .prefix(15)
            .map { "- \(DateFormatting.shortDate.string(from: $0.displayDate))（\($0.dateBasisLabel)，置信度 \(Int($0.resolvedDateConfidence * 100))%）[\($0.domain.label)] \($0.title)：\($0.summary)" }
            .joined(separator: "\n")
        let qaHistory = report.qaMessages
            .suffix(12)
            .map { "\($0.role.label)：\($0.content)" }
            .joined(separator: "\n")
        let examples = report.fieldExamples
            .sorted { $0.key < $1.key }
            .prefix(30)
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "；")

        return """
        你是产品数据表格问答助手。请只围绕当前报表回答用户问题，并且尽量基于事实，不确定的地方必须说清楚。

        输出必须是 JSON，不要 Markdown，不要代码块。schema:
        {
          "answer": "直接回答用户问题，说明依据和限制",
          "evidence": ["可验证依据"],
          "uncertainties": ["仍不确定或需要用户确认的点"],
          "suggested_memories": [{"title":"可沉淀规则标题","content":"可复用规则内容","scope":"currentReport 或 similarReports 或 knowledgeOnly","related_field_name":""}],
          "profile_patch": {
            "summary": "可选：更新后的报表摘要",
            "purpose": "可选",
            "business_object": "可选",
            "grain": "可选",
            "key_metrics": ["可选"],
            "dimensions": ["可选"],
            "filters": "可选",
            "use_cases": ["可选"],
            "caveats": ["可选"]
          },
          "field_patches": [{"field_name":"字段名","meaning":"字段含义","notes":"备注"}]
        }

        规则：
        - 优先参考“用户确认过的报表说明”和“已采纳报表记忆”。
        - 对时间区间、候选成熟口径、7日/14日滞后解释要显式说明，但不要替用户预先排除周期。
        - 不要把报表知识误当成产品上线事件。
        - 如果问题需要竞品/政策/舆情，可以引用参照数据；没有足够数据时明确说缺口。
        - suggested_memories 只能给候选，不能替用户确认。

        当前问题：
        \(question)

        报表：
        - 文件：\(report.fileName)
        - 来源格式：\(report.sourceFormat.label)
        - Sheet：\(report.sheetName ?? "无")
        - 类型：\(report.kind.label)
        - 结构：\(report.shape.label)
        - 行数：\(report.rowCount)
        - 表头：\(report.headers.prefix(80).joined(separator: "，"))
        - 首列指标：\(report.firstColumnValues.prefix(120).joined(separator: "，"))
        - 样例值：\(examples.isEmpty ? "无" : examples)
        - 解析提醒：\(report.parseWarnings.isEmpty ? "无" : report.parseWarnings.joined(separator: "；"))
        - 趋势总览：\(report.trendSummary.overview.isEmpty ? "无" : report.trendSummary.overview)
        - 趋势要点：\(report.trendSummary.trendBullets.prefix(12).joined(separator: "；"))
        - 分布要点：\(report.trendSummary.distributionBullets.prefix(8).joined(separator: "；"))

        报表说明：
        - 摘要：\(report.semanticProfile.summary.isEmpty ? "未填写" : report.semanticProfile.summary)
        - 用途：\(report.semanticProfile.purpose.isEmpty ? "未填写" : report.semanticProfile.purpose)
        - 粒度：\(report.semanticProfile.grain.isEmpty ? "未填写" : report.semanticProfile.grain)
        - 关键指标：\(report.semanticProfile.keyMetrics.joined(separator: "，"))
        - 注意事项：\(report.semanticProfile.caveats.joined(separator: "，"))

        字段字典：
        \(fieldText.isEmpty ? "暂无" : fieldText)

        已采纳报表记忆：
        \(memoryText.isEmpty ? "暂无" : memoryText)

        知识库中的报表知识：
        \(knowledgeText.isEmpty ? "暂无" : knowledgeText)

        竞品/政策/舆情参照：
        \(referenceText.isEmpty ? "暂无" : referenceText)

        最近问答：
        \(qaHistory.isEmpty ? "暂无" : qaHistory)
        """
    }

    static func parse(_ output: String, fallback: ReportQAOutput) -> ReportQAOutput {
        guard let json = jsonObjectString(from: output),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return fallback }
            var copy = fallback
            copy.answer = trimmed
            return copy
        }
        return ReportQAOutput(
            answer: decoded.answer?.nilIfBlank ?? fallback.answer,
            evidence: decoded.evidence ?? fallback.evidence,
            uncertainties: decoded.uncertainties ?? fallback.uncertainties,
            suggestedMemories: decoded.suggestedMemories?.map {
                ReportQAMemoryCandidate(
                    title: $0.title?.nilIfBlank ?? "报表知识规则",
                    content: $0.content?.nilIfBlank ?? "",
                    scope: $0.scope?.nilIfBlank ?? "similarReports",
                    relatedFieldName: $0.relatedFieldName?.nilIfBlank
                )
            }.filter { !$0.content.isEmpty } ?? fallback.suggestedMemories,
            profilePatch: decoded.profilePatch?.semanticProfile(),
            fieldPatches: decoded.fieldPatches?.compactMap { patch in
                guard let fieldName = patch.fieldName?.nilIfBlank,
                      let meaning = patch.meaning?.nilIfBlank else { return nil }
                return ReportQAFieldPatch(fieldName: fieldName, meaning: meaning, notes: patch.notes?.nilIfBlank ?? "")
            } ?? fallback.fieldPatches
        )
    }

    private static func jsonObjectString(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else { return nil }
        return String(text[start...end])
    }

    private struct Response: Decodable {
        var answer: String?
        var evidence: [String]?
        var uncertainties: [String]?
        var suggestedMemories: [Memory]?
        var profilePatch: ProfilePatch?
        var fieldPatches: [FieldPatch]?

        enum CodingKeys: String, CodingKey {
            case answer
            case evidence
            case uncertainties
            case suggestedMemories = "suggested_memories"
            case suggestedMemoriesCamel = "suggestedMemories"
            case profilePatch = "profile_patch"
            case profilePatchCamel = "profilePatch"
            case fieldPatches = "field_patches"
            case fieldPatchesCamel = "fieldPatches"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            answer = try container.decodeIfPresent(String.self, forKey: .answer)
            evidence = try container.decodeIfPresent([String].self, forKey: .evidence)
            uncertainties = try container.decodeIfPresent([String].self, forKey: .uncertainties)
            suggestedMemories = try container.decodeIfPresent([Memory].self, forKey: .suggestedMemories)
                ?? container.decodeIfPresent([Memory].self, forKey: .suggestedMemoriesCamel)
            profilePatch = try container.decodeIfPresent(ProfilePatch.self, forKey: .profilePatch)
                ?? container.decodeIfPresent(ProfilePatch.self, forKey: .profilePatchCamel)
            fieldPatches = try container.decodeIfPresent([FieldPatch].self, forKey: .fieldPatches)
                ?? container.decodeIfPresent([FieldPatch].self, forKey: .fieldPatchesCamel)
        }
    }

    private struct Memory: Decodable {
        var title: String?
        var content: String?
        var scope: String?
        var relatedFieldName: String?

        enum CodingKeys: String, CodingKey {
            case title
            case content
            case scope
            case relatedFieldName = "related_field_name"
            case relatedFieldNameCamel = "relatedFieldName"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            content = try container.decodeIfPresent(String.self, forKey: .content)
            scope = try container.decodeIfPresent(String.self, forKey: .scope)
            relatedFieldName = try container.decodeIfPresent(String.self, forKey: .relatedFieldName)
                ?? container.decodeIfPresent(String.self, forKey: .relatedFieldNameCamel)
        }
    }

    private struct FieldPatch: Decodable {
        var fieldName: String?
        var meaning: String?
        var notes: String?

        enum CodingKeys: String, CodingKey {
            case fieldName = "field_name"
            case fieldNameCamel = "fieldName"
            case meaning
            case notes
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            fieldName = try container.decodeIfPresent(String.self, forKey: .fieldName)
                ?? container.decodeIfPresent(String.self, forKey: .fieldNameCamel)
            meaning = try container.decodeIfPresent(String.self, forKey: .meaning)
            notes = try container.decodeIfPresent(String.self, forKey: .notes)
        }
    }

    private struct ProfilePatch: Decodable {
        var summary: String?
        var purpose: String?
        var businessObject: String?
        var grain: String?
        var keyMetrics: [String]?
        var dimensions: [String]?
        var filters: String?
        var useCases: [String]?
        var caveats: [String]?

        enum CodingKeys: String, CodingKey {
            case summary
            case purpose
            case businessObject = "business_object"
            case businessObjectCamel = "businessObject"
            case grain
            case keyMetrics = "key_metrics"
            case keyMetricsCamel = "keyMetrics"
            case dimensions
            case filters
            case useCases = "use_cases"
            case useCasesCamel = "useCases"
            case caveats
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            summary = try container.decodeIfPresent(String.self, forKey: .summary)
            purpose = try container.decodeIfPresent(String.self, forKey: .purpose)
            businessObject = try container.decodeIfPresent(String.self, forKey: .businessObject)
                ?? container.decodeIfPresent(String.self, forKey: .businessObjectCamel)
            grain = try container.decodeIfPresent(String.self, forKey: .grain)
            keyMetrics = try container.decodeIfPresent([String].self, forKey: .keyMetrics)
                ?? container.decodeIfPresent([String].self, forKey: .keyMetricsCamel)
            dimensions = try container.decodeIfPresent([String].self, forKey: .dimensions)
            filters = try container.decodeIfPresent(String.self, forKey: .filters)
            useCases = try container.decodeIfPresent([String].self, forKey: .useCases)
                ?? container.decodeIfPresent([String].self, forKey: .useCasesCamel)
            caveats = try container.decodeIfPresent([String].self, forKey: .caveats)
        }

        func semanticProfile() -> ReportSemanticProfile {
            ReportSemanticProfile(
                summary: summary ?? "",
                purpose: purpose ?? "",
                businessObject: businessObject ?? "",
                grain: grain ?? "",
                keyMetrics: keyMetrics ?? [],
                dimensions: dimensions ?? [],
                filters: filters ?? "",
                useCases: useCases ?? [],
                caveats: caveats ?? [],
                openQuestions: [],
                updatedAt: Date()
            )
        }
    }
}
