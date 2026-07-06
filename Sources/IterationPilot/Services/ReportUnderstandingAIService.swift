import Foundation

struct ReportUnderstandingOutput {
    var assistantReply: String
    var nextQuestion: String
    var openQuestions: [String]
    var profileDraft: ReportSemanticProfile
    var readyForConfirmation: Bool
}

enum ReportUnderstandingAIService {
    static func fallbackInitialOutput(for report: ImportedReport) -> ReportUnderstandingOutput {
        let inference = ReportSemanticInferencer.infer(report: report)
        let question = report.semanticStatus == .autoInferred
            ? "我已根据文件名、字段、首列指标、样例值和趋势自动理解这张表。请只校准特殊口径：是否有固定渠道、版本、人群、实验组或不能直接比较的时间区间？"
            : "我已先生成低置信报表草稿。请补充最关键的口径：这张表主要分析什么问题，统计周期/粒度是什么？"
        var profile = report.semanticProfile.summary.isEmpty ? inference.profile : report.semanticProfile
        if profile.openQuestions.isEmpty {
            profile.openQuestions = inference.profile.openQuestions.isEmpty
                ? [
                    "是否有固定渠道、版本、人群或实验组筛选？",
                    "哪些指标可以直接用于归因，哪些只是辅助观察？",
                    "是否存在口径变化或不能跨周期比较的数据？"
                ]
                : inference.profile.openQuestions
        }
        profile.updatedAt = Date()
        return ReportUnderstandingOutput(
            assistantReply: question,
            nextQuestion: question,
            openQuestions: profile.openQuestions,
            profileDraft: profile,
            readyForConfirmation: false
        )
    }

    static func fallbackOutput(for report: ImportedReport, userInput: String) -> ReportUnderstandingOutput {
        var profile = report.semanticProfile
        let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            profile.summary = trimmed
            if profile.purpose.isEmpty { profile.purpose = trimmed }
        }
        profile.openQuestions = [
            "请确认统计粒度和时间窗口。",
            "请确认哪些指标可以直接用于归因，哪些只是辅助观察。",
            "请确认是否存在筛选条件、异常值或不能直接比较的口径。"
        ]
        profile.updatedAt = Date()

        let reply = "已记录你的报表说明。当前未配置 AI API Key，我先按你的原始描述保存草稿；你可以继续补充，也可以在确认无误后点击“确认报表说明”。"
        return ReportUnderstandingOutput(
            assistantReply: reply,
            nextQuestion: profile.openQuestions.first ?? "",
            openQuestions: profile.openQuestions,
            profileDraft: profile,
            readyForConfirmation: !trimmed.isEmpty
        )
    }

    static func prompt(for report: ImportedReport, userInput: String?) -> String {
        let messages = report.understandingMessages
            .suffix(12)
            .map { "\($0.role.label)：\($0.content)" }
            .joined(separator: "\n")
        let examples = report.fieldExamples
            .sorted { $0.key < $1.key }
            .prefix(20)
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "；")
        let profile = report.semanticProfile

        return """
        你是产品数据报表理解助手，目标是像计划模式一样，通过多轮对话把一张数据报表的业务含义确认清楚。

        规则：
        - 不要直接确认完成，只能给出草稿、疑问点和下一步问题。
        - 如果信息不足，要明确追问，不要靠字段名臆测。
        - 输出必须是 JSON，不要 Markdown，不要代码块。
        - JSON schema:
        {
          "assistant_reply": "对用户的回复，包含你理解到的内容和仍需确认的点",
          "next_question": "下一轮最应该问用户的一个问题；没有就为空字符串",
          "open_questions": ["还未确认的问题"],
          "ready_for_confirmation": false,
          "profile_draft": {
            "summary": "人类可读的报表说明",
            "purpose": "报表用途",
            "business_object": "业务对象，如用户/订单/申请/埋点事件",
            "grain": "统计周期或粒度，如日/周/事件级/用户级",
            "key_metrics": ["关键指标"],
            "dimensions": ["关键维度"],
            "filters": "筛选条件或样本范围",
            "use_cases": ["适用分析场景"],
            "caveats": ["注意事项、不可直接解读的限制"]
          }
        }

        报表：\(report.fileName)
        来源格式：\(report.sourceFormat.label)
        Sheet：\(report.sheetName ?? "无")
        报表类型：\(report.kind.label)
        表格结构：\(report.shape.label)
        数据趋势摘要：\(report.trendSummary.overview.isEmpty ? "无" : report.trendSummary.overview)
        数据趋势要点：\(report.trendSummary.trendBullets.prefix(8).joined(separator: "；"))
        分布观察：\(report.trendSummary.distributionBullets.prefix(5).joined(separator: "；"))
        行数：\(report.rowCount)
        字段数：\(report.headers.count)
        首列字段数：\(report.firstColumnValues.count)
        类型识别置信度：\(Int(report.detectedConfidence * 100))%
        原始编码：\(report.originalEncoding.isEmpty ? "未知" : report.originalEncoding)
        分隔符：\(report.delimiter)
        解析提醒：\(report.parseWarnings.isEmpty ? "无" : report.parseWarnings.joined(separator: "；"))
        第一行字段：\(report.headers.prefix(60).joined(separator: "，"))
        第一列字段：\(report.firstColumnValues.prefix(80).joined(separator: "，"))
        样例值：\(examples.isEmpty ? "无" : examples)

        当前草稿：
        - 摘要：\(profile.summary.isEmpty ? "无" : profile.summary)
        - 用途：\(profile.purpose.isEmpty ? "无" : profile.purpose)
        - 业务对象：\(profile.businessObject.isEmpty ? "无" : profile.businessObject)
        - 粒度：\(profile.grain.isEmpty ? "无" : profile.grain)
        - 关键指标：\(profile.keyMetrics.isEmpty ? "无" : profile.keyMetrics.joined(separator: "，"))
        - 维度：\(profile.dimensions.isEmpty ? "无" : profile.dimensions.joined(separator: "，"))
        - 筛选条件：\(profile.filters.isEmpty ? "无" : profile.filters)
        - 注意事项：\(profile.caveats.isEmpty ? "无" : profile.caveats.joined(separator: "，"))

        最近对话：
        \(messages.isEmpty ? "暂无" : messages)

        用户本轮输入：
        \(userInput?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "用户要求你继续追问或整理当前草稿")
        """
    }

    static func parse(_ output: String, fallback: ReportUnderstandingOutput) -> ReportUnderstandingOutput {
        guard let json = jsonObjectString(from: output),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            var copy = fallback
            if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                copy.assistantReply = output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return copy
        }

        let profile = decoded.profileDraft?.merged(into: fallback.profileDraft) ?? fallback.profileDraft
        return ReportUnderstandingOutput(
            assistantReply: decoded.assistantReply?.nilIfBlank ?? fallback.assistantReply,
            nextQuestion: decoded.nextQuestion?.nilIfBlank ?? fallback.nextQuestion,
            openQuestions: decoded.openQuestions ?? fallback.openQuestions,
            profileDraft: profile.with(openQuestions: decoded.openQuestions ?? fallback.openQuestions),
            readyForConfirmation: decoded.readyForConfirmation ?? fallback.readyForConfirmation
        )
    }

    private static func jsonObjectString(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else {
            return nil
        }
        return String(text[start...end])
    }

    private struct Response: Decodable {
        var assistantReply: String?
        var nextQuestion: String?
        var openQuestions: [String]?
        var readyForConfirmation: Bool?
        var profileDraft: ProfileDraft?

        enum CodingKeys: String, CodingKey {
            case assistantReply = "assistant_reply"
            case assistantReplyCamel = "assistantReply"
            case nextQuestion = "next_question"
            case nextQuestionCamel = "nextQuestion"
            case openQuestions = "open_questions"
            case openQuestionsCamel = "openQuestions"
            case readyForConfirmation = "ready_for_confirmation"
            case readyForConfirmationCamel = "readyForConfirmation"
            case profileDraft = "profile_draft"
            case profileDraftCamel = "profileDraft"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            assistantReply = try container.decodeIfPresent(String.self, forKey: .assistantReply)
                ?? container.decodeIfPresent(String.self, forKey: .assistantReplyCamel)
            nextQuestion = try container.decodeIfPresent(String.self, forKey: .nextQuestion)
                ?? container.decodeIfPresent(String.self, forKey: .nextQuestionCamel)
            openQuestions = try container.decodeIfPresent([String].self, forKey: .openQuestions)
                ?? container.decodeIfPresent([String].self, forKey: .openQuestionsCamel)
            readyForConfirmation = try container.decodeIfPresent(Bool.self, forKey: .readyForConfirmation)
                ?? container.decodeIfPresent(Bool.self, forKey: .readyForConfirmationCamel)
            profileDraft = try container.decodeIfPresent(ProfileDraft.self, forKey: .profileDraft)
                ?? container.decodeIfPresent(ProfileDraft.self, forKey: .profileDraftCamel)
        }
    }

    private struct ProfileDraft: Decodable {
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

        func merged(into existing: ReportSemanticProfile) -> ReportSemanticProfile {
            ReportSemanticProfile(
                summary: summary?.nilIfBlank ?? existing.summary,
                purpose: purpose?.nilIfBlank ?? existing.purpose,
                businessObject: businessObject?.nilIfBlank ?? existing.businessObject,
                grain: grain?.nilIfBlank ?? existing.grain,
                keyMetrics: keyMetrics ?? existing.keyMetrics,
                dimensions: dimensions ?? existing.dimensions,
                filters: filters?.nilIfBlank ?? existing.filters,
                useCases: useCases ?? existing.useCases,
                caveats: caveats ?? existing.caveats,
                openQuestions: existing.openQuestions,
                updatedAt: Date()
            )
        }
    }
}

private extension ReportSemanticProfile {
    func with(openQuestions: [String]) -> ReportSemanticProfile {
        var copy = self
        copy.openQuestions = openQuestions
        copy.updatedAt = Date()
        return copy
    }
}
