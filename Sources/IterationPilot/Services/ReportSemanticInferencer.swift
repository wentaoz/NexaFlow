import Foundation

struct ReportSemanticInference {
    var status: ImportedReportSemanticStatus
    var confidence: Double
    var profile: ReportSemanticProfile
    var message: ReportUnderstandingMessage?
}

enum ReportSemanticInferencer {
    static func infer(
        fileName: String,
        kind: ImportedReportKind,
        table: CSVTable,
        detectedConfidence: Double,
        trendSummary: ReportTrendSummary
    ) -> ReportSemanticInference {
        let nameSignal = normalizedFileTitle(fileName)
        let context = [
            nameSignal,
            kind.label,
            table.shape.label,
            table.headers.prefix(60).joined(separator: " "),
            table.firstColumnValues.prefix(80).joined(separator: " "),
            table.fieldExamples.prefix(40).map { "\($0.key) \($0.value)" }.joined(separator: " "),
            trendSummary.trendBullets.prefix(8).joined(separator: " ")
        ]
        .joined(separator: " ")

        let keyMetrics = inferredKeyMetrics(table: table, trendSummary: trendSummary)
        let dimensions = inferredDimensions(table: table)
        let businessObject = inferredBusinessObject(kind: kind, context: context)
        let grain = inferredGrain(table: table, context: context)
        let purpose = inferredPurpose(kind: kind, businessObject: businessObject, grain: grain, context: context)
        let filters = inferredFilters(fileTitle: nameSignal, context: context)
        let useCases = inferredUseCases(kind: kind, keyMetrics: keyMetrics)
        var caveats = inferredCaveats(table: table, detectedConfidence: detectedConfidence, trendSummary: trendSummary)
        caveats.append("该说明由系统根据文件名、字段/指标、样例值和趋势自动生成；如存在特殊口径，请手动校准。")

        var openQuestions = inferredOpenQuestions(
            filters: filters,
            keyMetrics: keyMetrics,
            dimensions: dimensions,
            detectedConfidence: detectedConfidence,
            shape: table.shape
        )

        let confidence = semanticConfidence(
            detectedConfidence: detectedConfidence,
            table: table,
            keyMetrics: keyMetrics,
            businessObject: businessObject,
            grain: grain,
            trendSummary: trendSummary
        )
        let status: ImportedReportSemanticStatus = confidence >= 0.66 ? .autoInferred : .needsReview
        if status == .autoInferred {
            openQuestions = Array(openQuestions.prefix(3))
        }

        let summary = summaryText(
            fileTitle: nameSignal,
            kind: kind,
            shape: table.shape,
            businessObject: businessObject,
            grain: grain,
            keyMetrics: keyMetrics
        )

        let profile = ReportSemanticProfile(
            summary: summary,
            purpose: purpose,
            businessObject: businessObject,
            grain: grain,
            keyMetrics: keyMetrics,
            dimensions: dimensions,
            filters: filters,
            useCases: useCases,
            caveats: caveats.uniqued(),
            openQuestions: openQuestions.uniqued(),
            updatedAt: Date()
        )

        let messageText = status == .autoInferred
            ? "已根据文件名、表结构、字段/首列指标、样例值和趋势自动生成报表说明，置信度 \(Int(confidence * 100))%。如口径无误，可直接用于分析；如有特殊筛选或口径，再手动校准。"
            : "已生成低置信报表草稿，置信度 \(Int(confidence * 100))%。建议补充用途、统计粒度、筛选条件和关键指标口径。"

        return ReportSemanticInference(
            status: status,
            confidence: confidence,
            profile: profile,
            message: ReportUnderstandingMessage(role: .system, content: messageText)
        )
    }

    static func infer(report: ImportedReport) -> ReportSemanticInference {
        let table = CSVTable(
            headers: report.headers,
            rows: report.sampleRows,
            firstColumnValues: report.firstColumnValues,
            fieldExamples: report.fieldExamples,
            shape: report.shape,
            sourceFormat: report.sourceFormat,
            sheetName: report.sheetName,
            sheetIndex: report.sheetIndex,
            parseWarnings: report.parseWarnings,
            originalEncoding: report.originalEncoding,
            delimiter: report.delimiter,
            workbookWarnings: [],
            cellTypeHints: report.cellTypeHints,
            rawRows: report.rawRows
        )
        return infer(
            fileName: report.fileName,
            kind: report.kind,
            table: table,
            detectedConfidence: report.detectedConfidence,
            trendSummary: report.trendSummary
        )
    }

    private static func normalizedFileTitle(_ fileName: String) -> String {
        (fileName as NSString)
            .deletingPathExtension
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func inferredKeyMetrics(table: CSVTable, trendSummary: ReportTrendSummary) -> [String] {
        var result: [String] = []
        var seen = Set<String>()

        func append(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isMetricCandidate(trimmed), seen.insert(trimmed.normalizedKey).inserted else { return }
            result.append(trimmed)
        }

        for trend in trendSummary.metricTrends {
            append(trend.metricName)
        }
        if table.shape == .pivotWide {
            for value in table.firstColumnValues {
                append(value)
            }
        } else {
            for header in table.headers where looksNumericField(header, examples: table.fieldExamples) {
                append(header)
            }
        }
        return Array(result.prefix(14))
    }

    private static func inferredDimensions(table: CSVTable) -> [String] {
        var dimensions: [String] = []
        var seen = Set<String>()

        func append(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.normalizedKey).inserted else { return }
            dimensions.append(trimmed)
        }

        if table.shape == .pivotWide {
            if let first = table.headers.first {
                append(first)
            }
            if table.headers.dropFirst().contains(where: isTemporalLabel) {
                append("横向时间周期")
            } else if table.headers.count > 1 {
                append("横向分组列")
            }
        }

        for header in table.headers {
            let key = header.normalizedKey
            if ["date", "day", "week", "month", "time", "channel", "platform", "segment", "status", "source", "version", "country", "event"].contains(where: { key.contains($0) }) ||
                ["日期", "时间", "周", "月", "渠道", "平台", "分群", "状态", "来源", "版本", "国家", "事件"].contains(where: { header.contains($0) }) {
                append(header)
            }
        }
        return Array(dimensions.prefix(10))
    }

    private static func inferredBusinessObject(kind: ImportedReportKind, context: String) -> String {
        let key = context.normalizedKey
        switch kind {
        case .productUpdates:
            return "产品更新/迭代记录"
        case .eventTracking:
            return "埋点事件与用户行为"
        case .userFeedback:
            return "用户反馈/客服工单"
        case .contextEvents:
            return "运营、技术或外部上下文事件"
        case .funnelMetrics:
            if containsAny(key, ["授信", "credit", "approval", "approve"]) { return "授信/审批转化流程" }
            if containsAny(key, ["开户", "account_open", "open_account"]) { return "开户转化流程" }
            if containsAny(key, ["申请", "apply", "application"]) { return "申请转化流程" }
            return "注册/转化漏斗"
        case .coreMetrics:
            return "核心业务指标"
        case .generic:
            if containsAny(key, ["注册", "转化", "漏斗", "授信", "申请"]) { return "转化指标" }
            return "业务报表"
        }
    }

    private static func inferredGrain(table: CSVTable, context: String) -> String {
        if table.shape == .pivotWide {
            let horizontal = table.headers.dropFirst()
            if horizontal.contains(where: { $0.contains("周") || $0.normalizedKey.contains("week") }) {
                return "透视宽表：第一列为指标，横向列为周/时间区间"
            }
            if horizontal.contains(where: { $0.contains("月") || $0.normalizedKey.contains("month") }) {
                return "透视宽表：第一列为指标，横向列为月/时间区间"
            }
            if horizontal.contains(where: isTemporalLabel) {
                return "透视宽表：第一列为指标，横向列为时间周期"
            }
            return "透视宽表：第一列为指标，横向列为分组"
        }

        let dateHeaders = table.headers.filter { isTemporalLabel($0) }
        if let first = dateHeaders.first {
            return "明细/聚合表：按 \(first) 记录"
        }
        if context.contains("周") || context.normalizedKey.contains("week") {
            return "周粒度"
        }
        if context.contains("月") || context.normalizedKey.contains("month") {
            return "月粒度"
        }
        return "统计粒度待确认"
    }

    private static func inferredPurpose(
        kind: ImportedReportKind,
        businessObject: String,
        grain: String,
        context: String
    ) -> String {
        switch kind {
        case .funnelMetrics:
            return "用于观察\(businessObject)在\(grain)下的规模、转化率和阶段变化。"
        case .eventTracking:
            return "用于分析埋点事件触发、曝光、点击或行为路径变化。"
        case .coreMetrics:
            return "用于监控核心业务指标的时间趋势、异常波动和跨维度差异。"
        case .userFeedback:
            return "用于归纳用户反馈、投诉或客服问题对产品体验的影响。"
        case .productUpdates:
            return "用于沉淀产品更新、上线内容和预期影响指标。"
        case .contextEvents:
            return "用于记录可能影响数据波动的运营、技术或外部事件。"
        case .generic:
            if containsAny(context.normalizedKey, ["注册", "转化", "授信", "申请"]) {
                return "用于观察转化链路相关指标的变化。"
            }
            return "用于补充当前分析资料的业务事实和分析上下文。"
        }
    }

    private static func inferredFilters(fileTitle: String, context: String) -> String {
        var filters: [String] = []
        let text = "\(fileTitle) \(context)"
        if containsAny(text.normalizedKey, ["ios"]) { filters.append("可能包含 iOS 平台") }
        if containsAny(text.normalizedKey, ["android"]) { filters.append("可能包含 Android 平台") }
        if containsAny(text, ["A12", "a12"]) { filters.append("文件名包含 A12，可能是内部报表编号或分组") }
        if containsAny(text, ["新用户", "new_user"]) { filters.append("可能聚焦新用户") }
        if containsAny(text, ["老用户", "existing_user"]) { filters.append("可能聚焦老用户") }
        return filters.isEmpty ? "未从文件名或字段中识别明确筛选条件；如有固定渠道、版本、人群或实验组需补充。" : filters.joined(separator: "；")
    }

    private static func inferredUseCases(kind: ImportedReportKind, keyMetrics: [String]) -> [String] {
        var cases: [String] = []
        switch kind {
        case .funnelMetrics:
            cases.append(contentsOf: ["转化漏斗趋势观察", "定位转化断点", "评估产品更新对注册/申请/授信链路的影响"])
        case .eventTracking:
            cases.append(contentsOf: ["埋点质量检查", "用户行为路径分析", "曝光点击触发变化观察"])
        case .coreMetrics:
            cases.append(contentsOf: ["核心指标趋势监控", "异常波动识别", "跨周期对比"])
        case .userFeedback:
            cases.append(contentsOf: ["用户问题归因", "体验风险识别"])
        case .productUpdates:
            cases.append(contentsOf: ["产品事件轴补充", "更新影响复盘"])
        case .contextEvents:
            cases.append(contentsOf: ["排除运营/技术/外部干扰", "归因背景补充"])
        case .generic:
            cases.append(contentsOf: ["业务上下文补充", "辅助 AI 分析"])
        }
        if !keyMetrics.isEmpty {
            cases.append("重点跟踪：\(keyMetrics.prefix(4).joined(separator: "、"))")
        }
        return cases.uniqued()
    }

    private static func inferredCaveats(
        table: CSVTable,
        detectedConfidence: Double,
        trendSummary: ReportTrendSummary
    ) -> [String] {
        var caveats = table.parseWarnings
        caveats.append(contentsOf: trendSummary.warnings)
        if detectedConfidence < 0.66 {
            caveats.append("报表类型识别置信度偏低，需要人工确认业务用途。")
        }
        if table.shape == .pivotWide {
            caveats.append("透视宽表按首列指标和横向列推断趋势；如果横向列不是时间，请修正说明。")
        }
        return caveats
    }

    private static func inferredOpenQuestions(
        filters: String,
        keyMetrics: [String],
        dimensions: [String],
        detectedConfidence: Double,
        shape: CSVTableShape
    ) -> [String] {
        var questions: [String] = []
        if detectedConfidence < 0.66 {
            questions.append("这张表最核心的业务用途是什么？")
        }
        if filters.contains("未从") {
            questions.append("这张表是否固定筛选了渠道、平台、版本、人群或实验组？")
        }
        if keyMetrics.isEmpty {
            questions.append("哪些字段或首列指标是后续归因必须重点参考的？")
        }
        if dimensions.isEmpty {
            questions.append("这张表可以按哪些维度拆解，例如平台、渠道、用户类型或版本？")
        }
        if shape == .pivotWide {
            questions.append("横向列是否表示从早到晚的时间周期，还是导出时最近周期在最左侧？")
        }
        return questions
    }

    private static func semanticConfidence(
        detectedConfidence: Double,
        table: CSVTable,
        keyMetrics: [String],
        businessObject: String,
        grain: String,
        trendSummary: ReportTrendSummary
    ) -> Double {
        var score = detectedConfidence * 0.38
        if table.shape != .unknown { score += 0.16 }
        if !keyMetrics.isEmpty { score += min(0.2, Double(keyMetrics.count) * 0.035) }
        if !businessObject.contains("业务报表") { score += 0.1 }
        if !grain.contains("待确认") { score += 0.1 }
        if !trendSummary.metricTrends.isEmpty { score += 0.12 }
        if !table.parseWarnings.isEmpty { score -= min(0.18, Double(table.parseWarnings.count) * 0.04) }
        return min(0.98, max(0.2, score))
    }

    private static func summaryText(
        fileTitle: String,
        kind: ImportedReportKind,
        shape: CSVTableShape,
        businessObject: String,
        grain: String,
        keyMetrics: [String]
    ) -> String {
        let metricText = keyMetrics.isEmpty ? "关键指标待确认" : "关键指标包括 \(keyMetrics.prefix(6).joined(separator: "、"))"
        return "\(fileTitle)：识别为\(kind.label)\(shape.label)，业务对象为\(businessObject)，粒度为\(grain)，\(metricText)。"
    }

    private static func isMetricCandidate(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 100 else { return false }
        let key = value.normalizedKey
        if ["date", "day", "week", "month", "time", "name", "type", "status", "日期", "时间", "名称", "类型", "状态"].contains(key) {
            return false
        }
        if DateParsing.parse(value) != nil { return false }
        if Double(value.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "%", with: "")) != nil { return false }
        return true
    }

    private static func looksNumericField(_ header: String, examples: [String: String]) -> Bool {
        let key = header.normalizedKey
        if ["date", "time", "channel", "platform", "segment", "user_id", "event"].contains(where: { key.contains($0) }) {
            return false
        }
        guard let example = examples.first(where: { $0.key.normalizedKey == key })?.value else {
            return containsAny(key, ["count", "value", "rate", "ratio", "amount", "次数", "数", "率", "金额"])
        }
        let cleaned = example.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "%", with: "")
        return Double(cleaned) != nil || containsAny(key, ["count", "value", "rate", "ratio", "amount", "次数", "数", "率", "金额"])
    }

    private static func isTemporalLabel(_ value: String) -> Bool {
        let key = value.normalizedKey
        if DateParsing.parse(value) != nil { return true }
        if value.range(of: #"\d{4}[-/.]\d{1,2}[-/.]\d{1,2}"#, options: .regularExpression) != nil {
            return true
        }
        return key.contains("date") ||
            key.contains("day") ||
            key.contains("week") ||
            key.contains("month") ||
            value.contains("日期") ||
            value.contains("时间") ||
            value.contains("周") ||
            value.contains("月")
    }

    private static func containsAny(_ context: String, _ keywords: [String]) -> Bool {
        keywords.contains { context.contains($0) }
    }
}
