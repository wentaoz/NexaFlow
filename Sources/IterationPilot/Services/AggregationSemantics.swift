import Foundation

enum AnalysisAggregationIntent: String, Codable, Hashable {
    case fileTotalComparison
    case periodAverageTrend
    case ambiguousNeedsConfirmation

    var label: String {
        switch self {
        case .fileTotalComparison: return "全周期 SUM / 文件总账对比"
        case .periodAverageTrend: return "周均/周期平均趋势"
        case .ambiguousNeedsConfirmation: return "聚合口径未明确，需要确认"
        }
    }
}

enum MetricAggregationKind: String, Codable, Hashable {
    case additive
    case derivedAverage
    case ratio
    case nonAdditive

    var label: String {
        switch self {
        case .additive: return "可加指标"
        case .derivedAverage: return "派生均值"
        case .ratio: return "比例指标"
        case .nonAdditive: return "不可直接加总"
        }
    }

    var defaultRule: String {
        switch self {
        case .additive:
            return "多周期/多文件对比默认使用全周期 SUM；周均只能作为单独趋势视角。"
        case .derivedAverage:
            return "必须用分子/分母重新计算或加权，不能简单平均各周均值。"
        case .ratio:
            return "必须使用分子/分母或加权口径，不能简单平均周期比例。"
        case .nonAdditive:
            return "不能直接加总；必须说明采用最新值、分布或补充口径。"
        }
    }
}

struct MetricAggregationClassification: Hashable {
    var metricName: String
    var kind: MetricAggregationKind
    var reason: String
}

enum AggregationSemantics {
    static func intent(userRequest: String, reports: [ImportedReport]) -> AnalysisAggregationIntent {
        let normalized = userRequest.normalizedKey
        let plain = userRequest.trimmingCharacters(in: .whitespacesAndNewlines)

        let averageKeywords = [
            "周均", "日均", "月均", "平均每周", "平均每月", "每周平均", "每月平均",
            "平均值", "趋势", "加速", "放缓", "波动", "连续", "逐周", "按周"
        ]
        let totalKeywords = [
            "文件", "去年文件", "今年文件", "两个文件", "总计", "累计", "合计", "汇总",
            "半年", "全年", "全周期", "总账", "总量", "sum", "所有周", "直接加起来"
        ]
        let asksAverage = containsAny(plain, averageKeywords) || averageKeywords.contains { normalized.contains($0.normalizedKey) }
        let asksTotal = containsAny(plain, totalKeywords) || totalKeywords.contains { normalized.contains($0.normalizedKey) }
        let rejectsAverage = plain.contains("不要周均") || plain.contains("不是周均") || plain.contains("不能周均") || plain.contains("别用周均")

        if rejectsAverage || (asksTotal && !asksAverage) {
            return .fileTotalComparison
        }
        if asksAverage && !asksTotal {
            return .periodAverageTrend
        }
        if asksAverage && asksTotal {
            return .ambiguousNeedsConfirmation
        }
        if reports.count >= 2 {
            return .fileTotalComparison
        }
        return .ambiguousNeedsConfirmation
    }

    static func classify(metricName: String) -> MetricAggregationClassification {
        let name = metricName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = name.normalizedKey

        let ratioHints = ["率", "占比", "比例", "通过率", "转化率", "留存率", "成功率", "失败率", "渗透率", "%"]
        if containsAny(name, ratioHints) || ratioHints.contains(where: { normalized.contains($0.normalizedKey) }) {
            return MetricAggregationClassification(metricName: name, kind: .ratio, reason: "名称包含比例/率类口径")
        }

        let derivedHints = ["人均", "笔均", "件均", "户均", "客单价", "平均", "均值", "arpu", "单均"]
        if containsAny(name, derivedHints) || derivedHints.contains(where: { normalized.contains($0.normalizedKey) }) {
            return MetricAggregationClassification(metricName: name, kind: .derivedAverage, reason: "名称包含均值/单均口径")
        }

        let additiveHints = [
            "金额", "人数", "笔数", "次数", "数量", "用户数", "客户数", "订单数",
            "交易额", "交易量", "gmv", "收入", "成本", "余额", "件数", "申请数", "通过数"
        ]
        if containsAny(name, additiveHints) || additiveHints.contains(where: { normalized.contains($0.normalizedKey) }) {
            return MetricAggregationClassification(metricName: name, kind: .additive, reason: "名称符合金额/人数/笔数/数量类可加指标")
        }

        return MetricAggregationClassification(metricName: name, kind: .nonAdditive, reason: "未命中可加、均值或比例规则")
    }

    static func promptContract(userRequest: String, reports: [ImportedReport]) -> String {
        let detectedIntent = intent(userRequest: userRequest, reports: reports)
        let metricExamples = reports
            .flatMap { $0.firstColumnValues.prefix(12) + $0.trendSummary.metricTrends.prefix(12).map(\.metricName) }
            .uniqued()
            .prefix(18)
            .map { metric in
                let classification = classify(metricName: metric)
                return "- \(metric)：\(classification.kind.label)。\(classification.kind.defaultRule)"
            }
            .joined(separator: "\n")
            .nilIfBlank ?? "- 当前未识别首列指标；仍必须先声明聚合口径。"

        return """
        # 聚合口径契约（防止周均与 SUM 混用）
        - 本轮系统判定口径：\(detectedIntent.label)。
        - 如果口径是“全周期 SUM / 文件总账对比”，交易人数、交易金额、交易笔数等可加指标必须把所有周期直接 SUM 后比较；不得把周均变化当作总账变化。
        - 如果口径是“周均/周期平均趋势”，必须明确写“这是周均/周期趋势，不是全周期总量对比”。
        - 如果口径未明确，需要先请用户选择“全周期总账 SUM”还是“周均/周期平均趋势”，不能输出确定业务结论。
        - 人均、笔均、客单价、通过率、占比等派生指标必须用分子/分母重算或加权；不能简单平均各周值。
        - 回答开头必须写清：分析口径、分析周期、对比周期、计算方式，并优先引用 SQL/Notebook 的“聚合口径审计”。
        - 如果你同时讨论 SUM 和周均，必须分成两个小节，且最终结论不能用周均覆盖 SUM。

        已识别指标默认口径：
        \(metricExamples)
        """
    }

    private static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.localizedCaseInsensitiveContains($0) }
    }
}
