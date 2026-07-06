import Foundation

struct UserQuestionMemoryCandidate: Hashable {
    var category: String
    var title: String
    var content: String
    var tags: [String]
}

enum UserQuestionMemoryExtractionService {
    static func shouldExtract(from userText: String) -> Bool {
        let key = userText.normalizedKey
        let explicitMarkers = ["以后", "以后都", "后续", "每次", "默认", "必须", "不要", "不能", "不允许", "记住", "按这个", "按这种", "都要", "统一"]
        return explicitMarkers.contains { key.contains($0.normalizedKey) }
    }

    static func extractCandidates(from userText: String) -> [UserQuestionMemoryCandidate] {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard shouldExtract(from: trimmed) else { return [] }
        let key = trimmed.normalizedKey
        var candidates: [UserQuestionMemoryCandidate] = []

        if containsAny(key, ["最新完整周期", "上一周期", "主比较", "周期", "多表", "联动", "传导", "指标", "漏斗", "归因", "外部事件"]) {
            candidates.append(UserQuestionMemoryCandidate(
                category: "分析偏好",
                title: "用户分析偏好",
                content: trimmed,
                tags: ["提问记忆", "分析偏好"]
            ))
        }

        if containsAny(key, ["报告", "老板", "word", "表格", "结论", "证据", "百分点", "pp", "摘要", "风险", "验证"]) {
            candidates.append(UserQuestionMemoryCandidate(
                category: "报告偏好",
                title: "用户报告偏好",
                content: trimmed,
                tags: ["提问记忆", "报告偏好"]
            ))
        }

        if containsAny(key, ["不要", "不能", "不允许", "不是", "别", "confluence", "上线", "采集时间", "同步时间", "未成熟"]) {
            candidates.append(UserQuestionMemoryCandidate(
                category: "纠偏规则",
                title: "用户纠偏规则",
                content: trimmed,
                tags: ["提问记忆", "纠偏规则"]
            ))
        }

        if containsAny(key, ["口径", "含义", "表示", "越高越好", "越低越好", "成熟窗口", "时滞", "滞后"]) {
            candidates.append(UserQuestionMemoryCandidate(
                category: "指标口径",
                title: "用户指标口径偏好",
                content: trimmed,
                tags: ["提问记忆", "指标口径"]
            ))
        }

        if candidates.isEmpty {
            candidates.append(UserQuestionMemoryCandidate(
                category: "通用偏好",
                title: "用户长期偏好",
                content: trimmed,
                tags: ["提问记忆", "通用偏好"]
            ))
        }
        return candidates.uniqued()
    }

    private static func containsAny(_ normalizedText: String, _ terms: [String]) -> Bool {
        terms.contains { normalizedText.contains($0.normalizedKey) }
    }
}
