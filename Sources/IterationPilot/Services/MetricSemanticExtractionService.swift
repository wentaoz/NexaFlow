import Foundation

enum MetricSemanticExtractionService {
    static func shouldExtract(from userText: String) -> Bool {
        isExplicitMetricExplanation(userText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func extractConfirmedSemantics(
        from userText: String,
        messageID: UUID,
        reports: [ImportedReport],
        businessSpace: BusinessSpace?
    ) -> [BusinessSpaceMetricSemantic] {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isExplicitMetricExplanation(trimmed) else { return [] }

        let knownMetrics = (reports.flatMap { report in
            report.firstColumnValues + report.headers + report.trendSummary.metricTrends.map(\.metricName)
        } + (businessSpace?.metricSemanticLibrary.map(\.metricName) ?? []))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()

        var metricNames = knownMetrics.filter { metric in
            trimmed.normalizedKey.contains(metric.normalizedKey)
        }
        metricNames.append(contentsOf: quotedMetricNames(in: trimmed))
        metricNames = metricNames.uniqued()
        guard !metricNames.isEmpty else { return [] }

        return metricNames.prefix(12).map { metricName in
            BusinessSpaceMetricSemantic(
                metricName: metricName,
                sourceMessageID: messageID,
                aliasesText: aliasesText(for: metricName, in: trimmed),
                businessDomainIDs: matchingDomainIDs(in: trimmed, businessSpace: businessSpace),
                businessStage: inferredStage(metricName: metricName, text: trimmed),
                directionPreference: inferredDirection(metricName: metricName, text: trimmed),
                maturityWindowDays: inferredMaturityWindow(text: trimmed),
                impactLagDays: inferredLag(text: trimmed),
                relatedMetricsText: relatedMetricsText(metricName: metricName, knownMetrics: knownMetrics, text: trimmed),
                commonAnomalyExplanationsText: trimmed,
                isUserConfirmed: true,
                updatedAt: Date()
            )
        }
    }

    private static func isExplicitMetricExplanation(_ text: String) -> Bool {
        let key = text.normalizedKey
        return key.contains("指标") ||
            key.contains("口径") ||
            key.contains("表示") ||
            key.contains("含义") ||
            key.contains("越高越好") ||
            key.contains("越低越好") ||
            key.contains("以后按") ||
            key.contains("不是")
    }

    private static func quotedMetricNames(in text: String) -> [String] {
        let patterns = [
            #"“([^”]{2,80})”"#,
            #""([^"]{2,80})""#,
            #"「([^」]{2,80})」"#,
            #"`([^`]{2,80})`"#
        ]
        return patterns.flatMap { pattern -> [String] in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.matches(in: text, range: range).compactMap { match in
                guard let range = Range(match.range(at: 1), in: text) else { return nil }
                return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private static func aliasesText(for metricName: String, in text: String) -> String {
        guard text.contains("别名") || text.contains("也叫") else { return "" }
        return text
            .components(separatedBy: CharacterSet(charactersIn: "。；;\n"))
            .first { $0.contains(metricName) && ($0.contains("别名") || $0.contains("也叫")) } ?? ""
    }

    private static func matchingDomainIDs(in text: String, businessSpace: BusinessSpace?) -> [UUID] {
        guard let businessSpace else { return [] }
        return businessSpace.domains.filter { domain in
            text.normalizedKey.contains(domain.name.normalizedKey)
        }.map(\.id)
    }

    private static func inferredStage(metricName: String, text: String) -> MetricBusinessStage {
        let key = "\(metricName) \(text)".normalizedKey
        if key.contains("注册") { return .registration }
        if key.contains("申请") || key.contains("提交") { return .application }
        if key.contains("授信") || key.contains("审核") || key.contains("审批") { return .creditReview }
        if key.contains("发卡") || key.contains("激活") { return .cardActivation }
        if key.contains("消费") || key.contains("交易") || key.contains("缴费") || key.contains("支付") { return .payment }
        if key.contains("留存") || key.contains("活跃") { return .retention }
        if key.contains("曝光") || key.contains("点击") || key.contains("页面") || key.contains("埋点") { return .pageBehavior }
        if key.contains("风险") || key.contains("逾期") || key.contains("拒绝") || key.contains("投诉") || key.contains("失败") { return .risk }
        return .unknown
    }

    private static func inferredDirection(metricName: String, text: String) -> MetricDirectionPreference {
        let key = "\(metricName) \(text)".normalizedKey
        if key.contains("越低越好") || key.contains("越少越好") || key.contains("越小越好") ||
            key.contains("失败") || key.contains("逾期") || key.contains("错误") || key.contains("投诉") {
            return .lowerIsBetter
        }
        if key.contains("越高越好") || key.contains("越多越好") || key.contains("提升") || key.contains("增长") {
            return .higherIsBetter
        }
        return .unknown
    }

    private static func inferredMaturityWindow(text: String) -> Int? {
        inferredDays(in: text, suffixes: ["天成熟", "日成熟", "天窗口", "日窗口"])
    }

    private static func inferredLag(text: String) -> Int? {
        inferredDays(in: text, suffixes: ["天滞后", "日滞后", "天时滞", "日时滞", "天后影响", "日后影响"])
    }

    private static func inferredDays(in text: String, suffixes: [String]) -> Int? {
        for suffix in suffixes {
            let escapedSuffix = NSRegularExpression.escapedPattern(for: suffix)
            guard let regex = try? NSRegularExpression(pattern: "(\\d{1,3})\\s*\(escapedSuffix)") else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, range: range),
               let valueRange = Range(match.range(at: 1), in: text),
               let value = Int(text[valueRange]) {
                return value
            }
        }
        return nil
    }

    private static func relatedMetricsText(metricName: String, knownMetrics: [String], text: String) -> String {
        knownMetrics
            .filter { $0.normalizedKey != metricName.normalizedKey && text.normalizedKey.contains($0.normalizedKey) }
            .prefix(8)
            .joined(separator: ", ")
    }
}
