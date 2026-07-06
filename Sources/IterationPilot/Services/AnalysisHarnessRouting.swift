import Foundation

enum AnalysisHarnessFeatureFlags {
    static let analysisHarnessEnabled = true
}

enum AnalysisHarnessRouter {
    static func userMessageExplicitlyRequestsFullAnalysis(_ text: String) -> Bool {
        let normalized = text.normalizedKey
        let fullMarkers = ["重新分析", "重算", "完整分析", "全量", "重新读取", "重新看", "从头分析", "深度分析"]
        return fullMarkers.contains { normalized.contains($0.normalizedKey) }
    }

    static func userMessageLooksLikeLightweightTask(_ text: String) -> Bool {
        let normalized = text.normalizedKey
        guard !normalized.isEmpty else { return false }
        if userMessageExplicitlyRequestsFullAnalysis(text) || userMessageLooksLikeTableComputation(text) {
            return false
        }
        let lightweightTerms = [
            "解释一下", "什么意思", "如何理解", "帮我理解", "这句话", "这段话", "上面这段", "上面这句",
            "上一条", "刚才", "改写", "润色", "翻译", "译成", "用英文", "用中文", "总结一下", "概括",
            "精简", "展开说说", "换个说法", "优化表达", "写得更", "转成"
        ]
        let hasLightweightTerm = lightweightTerms.contains { normalized.contains($0.normalizedKey) }
        guard hasLightweightTerm else { return false }
        let deepAnalysisTerms = ["归因", "原因", "为什么", "影响", "异常", "波动", "趋势", "机会", "风险", "策略"]
        let businessMetricTerms = ["交易", "金额", "人数", "笔数", "用户", "订单", "增长", "下降", "上升", "转化", "占比"]
        let looksLikeBusinessAnalysis = deepAnalysisTerms.contains { normalized.contains($0.normalizedKey) } &&
            businessMetricTerms.contains { normalized.contains($0.normalizedKey) }
        return !looksLikeBusinessAnalysis
    }

    static func effectiveContextMode(
        requestedMode: AnalysisContextMode?,
        userMessage: String,
        hasPreviousAI: Bool,
        cacheMatches: Bool
    ) -> AnalysisContextMode {
        if userMessageExplicitlyRequestsFullAnalysis(userMessage) {
            return .fullReanalysis
        }
        if userMessageLooksLikeLightweightTask(userMessage) {
            return cacheMatches ? .cachedFollowUp : .quickFollowUp
        }
        if let requestedMode {
            return requestedMode
        }
        guard hasPreviousAI else {
            return .fullReanalysis
        }
        return cacheMatches ? .cachedFollowUp : .quickFollowUp
    }

    static func userMessageNeedsVerifiedAnalysis(_ text: String, sourcePolicy: AnalysisContextSourcePolicy) -> Bool {
        if userMessageLooksLikeLightweightTask(text) {
            return false
        }
        if userMessageLooksLikeMetricRelationshipExplanation(text) {
            return false
        }
        if userMessageLooksLikeTableComputation(text) {
            return true
        }
        if userMessageLooksLikeContextEvidenceQuestion(text) {
            return sourcePolicy.includeInternalKnowledge || sourcePolicy.includeExternalReferences
        }
        let normalized = text.normalizedKey
        let deepTerms = ["分析", "复盘", "诊断", "归因", "原因", "为什么", "影响", "趋势", "洞察", "建议", "机会", "风险", "异常", "波动"]
        return deepTerms.contains { normalized.contains($0.normalizedKey) }
    }

    static func userMessageLooksLikeMetricRelationshipExplanation(_ text: String) -> Bool {
        let normalized = text.normalizedKey
        guard !normalized.isEmpty else { return false }

        let explanationTerms = ["为什么", "原因", "可能", "是不是", "是否", "怎么会", "怎么", "解释", "口径", "统计上", "统计原因"]
        let relationshipTerms = ["相同", "一样", "一致", "相等", "等于", "接近", "差不多", "重合", "同一个"]
        guard explanationTerms.contains(where: { normalized.contains($0.normalizedKey) }),
              relationshipTerms.contains(where: { normalized.contains($0.normalizedKey) }) else {
            return false
        }

        let metricTerms = ["人数", "笔数", "金额", "订单", "交易", "用户", "客户", "件数", "次数", "指标"]
        let matchedMetricCount = metricTerms.reduce(0) { count, term in
            normalized.contains(term.normalizedKey) ? count + 1 : count
        }
        return matchedMetricCount >= 2 || normalized.contains("指标")
    }

    static func userMessageLooksLikeTableComputation(_ text: String) -> Bool {
        let normalized = text.normalizedKey
        let calculationTerms = [
            "统计", "计算", "算一下", "求和", "总计", "合计", "汇总", "平均", "均值", "人均", "笔均",
            "同比", "环比", "增长", "增长率", "变化率", "差值", "对比", "占比", "比例", "转化率",
            "人数", "金额", "笔数", "订单", "交易", "用户数", "count", "sum", "avg", "average",
            "distinct", "group_by", "group by", "growth", "rate", "ratio", "compare"
        ]
        if calculationTerms.contains(where: { normalized.contains($0.normalizedKey) }) {
            return true
        }
        let numericIntentPattern = #"(多少|几|top\s*\d+|前\s*\d+|排名|最大|最小|最高|最低)"#
        return normalized.range(of: numericIntentPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func userMessageLooksLikeContextEvidenceQuestion(_ text: String) -> Bool {
        let normalized = text.normalizedKey
        let sourceTerms = ["结合", "参考", "外部", "知识库", "confluence", "jira", "钉钉", "政策", "竞品", "市场", "新闻", "文档", "证据", "依据"]
        let causalTerms = ["为什么", "原因", "归因", "影响", "背景", "解释"]
        let businessTerms = ["交易", "金额", "人数", "笔数", "用户", "订单", "增长", "变化", "下降", "上升", "活动", "上线", "需求", "政策", "市场", "竞品"]
        let mentionsSource = sourceTerms.contains { normalized.contains($0.normalizedKey) }
        let mentionsCausalIntent = causalTerms.contains { normalized.contains($0.normalizedKey) }
        let mentionsBusinessContext = businessTerms.contains { normalized.contains($0.normalizedKey) }
        return (mentionsSource && (mentionsCausalIntent || mentionsBusinessContext)) ||
            (mentionsCausalIntent && mentionsBusinessContext)
    }
}

enum AnalysisHarnessError: LocalizedError {
    case infrastructure(String)

    var errorDescription: String? {
        switch self {
        case .infrastructure(let message):
            return message
        }
    }
}
