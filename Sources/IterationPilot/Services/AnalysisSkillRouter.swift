import Foundation

enum AnalysisSkillType: String, Codable, CaseIterable, Identifiable, Hashable {
    case metricDiagnostics
    case productBusinessAnalysis
    case kpiReporting
    case kpiDesign
    case dataQualityReasoning
    case visualizationRecommendation

    var id: String { rawValue }

    var label: String {
        switch self {
        case .metricDiagnostics: return "指标诊断"
        case .productBusinessAnalysis: return "产品经营分析"
        case .kpiReporting: return "KPI 汇报"
        case .kpiDesign: return "指标体系设计"
        case .dataQualityReasoning: return "数据质量推理"
        case .visualizationRecommendation: return "可视化建议"
        }
    }

    var strategy: String {
        switch self {
        case .metricDiagnostics:
            return "复现指标变化、比较周期、异常点和可能断点，优先用 SQL 计算关键差异。"
        case .productBusinessAnalysis:
            return "把指标变化翻译成产品/运营问题、影响范围、机会和建议动作。"
        case .kpiReporting:
            return "组织完整汇报摘要、关键事实、风险、机会和下一步验证。"
        case .kpiDesign:
            return "识别主指标、护栏指标、分群指标和后续监控建议。"
        case .dataQualityReasoning:
            return "检查缺失、重复、口径、粒度、日期列和数值异常，避免结论建立在脏数据上。"
        case .visualizationRecommendation:
            return "推荐趋势、漏斗、贡献拆解、分群对比等图表或表格呈现方式。"
        }
    }
}

struct AnalysisSkillPlan: Codable, Hashable {
    var skills: [AnalysisSkillType]
    var summary: String
    var computationFocus: [String]

    var promptMarkdown: String {
        let skillLines = skills.map { "- \($0.label)：\($0.strategy)" }.joined(separator: "\n")
        let focusLines = computationFocus.map { "- \($0)" }.joined(separator: "\n")
        return """
        ## 本轮分析 Skill 路由
        \(summary)

        \(skillLines)

        计算重点：
        \(focusLines.isEmpty ? "- 暂无专项计算重点，优先生成数据覆盖、质量和可比趋势证据。" : focusLines)
        """
    }
}

enum AnalysisSkillRouter {
    static func route(
        userRequest: String,
        contextMode: AnalysisContextMode,
        reports: [ImportedReport]
    ) -> AnalysisSkillPlan {
        let key = userRequest.normalizedKey
        var skills: [AnalysisSkillType] = [.metricDiagnostics, .productBusinessAnalysis, .dataQualityReasoning]
        var focus: [String] = [
            "读取当前任务选中的全部报表，不混入未选表。",
            "生成表级行列数、字段、指标和周期覆盖证据。",
            "优先计算可复现的指标变化、缺失率和宽表长表化结果。"
        ]

        if contextMode == .reportGeneration || key.contains("报告") || key.contains("汇报") || key.contains("老板") {
            skills.append(.kpiReporting)
            focus.append("为完整汇报准备关键指标变化表、证据表和限制说明。")
        }
        if key.contains("指标") || key.contains("口径") || key.contains("监控") || key.contains("体系") {
            skills.append(.kpiDesign)
            focus.append("识别主指标、护栏指标、好坏方向和后续监控口径。")
        }
        if key.contains("图") || key.contains("可视化") || key.contains("趋势图") || key.contains("漏斗图") {
            skills.append(.visualizationRecommendation)
            focus.append("给出适合产品/运营复盘的图表或表格建议。")
        }
        if key.contains("漏斗") || key.contains("断点") || key.contains("转化") {
            focus.append("计算漏斗相邻环节变化，定位可能断点。")
        }
        if key.contains("渠道") || key.contains("获客") || key.contains("投放") {
            focus.append("检查渠道质量、渠道结构和获客到业务结果的传导。")
        }
        if key.contains("风控") || key.contains("拒绝") || key.contains("审核") || key.contains("授信") {
            focus.append("检查风控/审核相关指标对通过率、交易或留存的影响。")
        }
        if reports.contains(where: { $0.shape == .pivotWide }) {
            focus.append("透视宽表需要生成 metric / period / value 的长表证据。")
        }
        if reports.contains(where: { $0.shape == .detail }) {
            focus.append("明细表需要生成字段画像、缺失率、日期候选列和数值列聚合。")
        }

        skills = skills.uniqued()
        return AnalysisSkillPlan(
            skills: skills,
            summary: "本轮使用 \(skills.map(\.label).joined(separator: "、"))，SQL 只作为后台可验证计算证据，不要求用户写 SQL。",
            computationFocus: focus.uniqued()
        )
    }
}
