import Foundation

struct AITableFirstAnalysisResult {
    var report: ImportedReport
    var jobRecord: AIJobRecord?
}

enum AITableFirstAnalysisService {
    static func analyze(report: ImportedReport, settings: AISettings) async -> AITableFirstAnalysisResult {
        let package = TableContextPackageBuilder.build(for: report)
        var workingReport = report
        workingReport.tableContextCoverage = package.coverage
        workingReport.metricSemanticProfiles = mergeMetricProfiles(
            existing: report.metricSemanticProfiles,
            inferred: initialMetricProfiles(for: report)
        )

        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let fallback = fallbackAnalysis(for: workingReport, package: package, reason: "未配置 AI API Key，未生成 AI 表格理解。")
            workingReport.aiFirstAnalysis = fallback
            workingReport.aiReasoningLogs.append(AIReasoningLogEntry(step: "AI 表格理解", status: .needsUserAction, detail: "未配置 AI API Key。"))
            return AITableFirstAnalysisResult(report: workingReport, jobRecord: nil)
        }

        var dataRequests: [AIDataRequest] = []
        var supplementalContext: [String] = []
        var lastRecord: AIJobRecord?
        var parsedAnalysis: AITableFirstAnalysis?
        var validationWarnings: [String] = []
        let queue = AIJobQueue(maxAttempts: 6)

        for round in 1...3 {
            let prompt = prompt(
                report: workingReport,
                package: package,
                round: round,
                supplementalContext: supplementalContext,
                previousWarnings: validationWarnings
            )

            do {
                let result = try await queue.runTextJob(
                    prompt: prompt,
                    settings: settings,
                    jobType: "AI 表格理解",
                    validation: { raw in
                        parse(raw) == nil ? ["AI 表格理解必须输出可解析的 JSON 对象。"] : []
                    },
                    correctionPrompt: { originalPrompt, output, warnings in
                        """
                        你刚才的表格分析没有通过本地校验，请只输出修正后的 JSON，不要输出 Markdown。

                        校验问题：
                        \(warnings.map { "- \($0)" }.joined(separator: "\n"))

                        原始要求：
                        \(originalPrompt)

                        你刚才的输出：
                        \(output)
                        """
                    }
                )
                lastRecord = result.record
                parsedAnalysis = parse(result.output)
                validationWarnings = []
            } catch {
                let fallback = fallbackAnalysis(for: workingReport, package: package, reason: error.localizedDescription)
                workingReport.aiFirstAnalysis = fallback
                var record = (error as? AIJobQueueError)?.record ?? lastRecord ?? AIJobRecord(jobType: "AI 表格理解", targetID: report.id, targetName: report.displayName)
                record.targetID = report.id
                record.targetName = report.displayName
                record.status = .needsUserAction
                record.lastError = error.localizedDescription
                record.logs.append(AIReasoningLogEntry(step: "AI 表格理解", status: .needsUserAction, detail: error.localizedDescription))
                workingReport.aiReasoningLogs.append(contentsOf: record.logs)
                return AITableFirstAnalysisResult(report: workingReport, jobRecord: record)
            }

            guard let parsedAnalysis else { break }
            dataRequests = parsedAnalysis.missingDataRequests
            let openRequests = dataRequests.filter { $0.status == .requested }
            if parsedAnalysis.readyForAnalysis || openRequests.isEmpty {
                break
            }

            let fulfilled = openRequests.map { TableContextPackageBuilder.fulfillment(for: $0, report: workingReport) }
            workingReport.aiDataRequests.append(contentsOf: fulfilled)
            supplementalContext.append("第 \(round) 轮 dataRequests 补充结果：\n" + fulfilled.map { "- \($0.kind.rawValue) \(($0.target)): \($0.status.rawValue)；\($0.responseSummary)" }.joined(separator: "\n"))
        }

        var final = parsedAnalysis ?? fallbackAnalysis(for: workingReport, package: package, reason: "AI 没有返回可用分析。")
        final.validationWarnings = validationWarnings + final.validationWarnings
        final.coverageSummary = package.coverage.summary
        workingReport.aiFirstAnalysis = final
        workingReport.aiDataRequests = (workingReport.aiDataRequests + final.missingDataRequests).uniquedByStableKey()
        if let lastRecord {
            workingReport.aiReasoningLogs.append(contentsOf: lastRecord.logs)
        }
        workingReport.aiReasoningLogs.append(AIReasoningLogEntry(
            step: "AI 数据覆盖",
            status: .completed,
            detail: "\(package.coverage.summary)；\(package.coverage.limitations.joined(separator: "；"))"
        ))
        return AITableFirstAnalysisResult(report: workingReport, jobRecord: lastRecord)
    }

    static func fallbackAnalysis(for report: ImportedReport, package: TableContextPackage, reason: String) -> AITableFirstAnalysis {
        return AITableFirstAnalysis(
            generatedAt: Date(),
            readyForAnalysis: false,
            summary: "未生成 AI 表格理解：\(report.displayName)。\(reason)",
            dataAvailability: "\(package.coverage.summary)。\(package.coverage.limitations.joined(separator: "；"))",
            primaryComparison: [],
            historicalTrend: [],
            keyChanges: [],
            anomalies: report.trendSummary.warnings,
            missingDataRequests: [],
            metricLinkCandidates: [],
            externalEventHypotheses: [],
            validationWarnings: reason.isEmpty ? [] : [reason],
            coverageSummary: package.coverage.summary
        )
    }

    private static func prompt(
        report: ImportedReport,
        package: TableContextPackage,
        round: Int,
        supplementalContext: [String],
        previousWarnings: [String]
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let packageJSON = (try? String(data: encoder.encode(package), encoding: .utf8)) ?? "{}"
        let semantic = report.semanticProfile.summary.nilIfBlank ?? "未确认"
        return """
        你是 AI-first 产品数据分析引擎的第一步。你必须严谨、保守、可校验。

        规则：
        1. 你必须优先读取 rawMatrix 原始二维表。manifest、inventory、structureCandidates、dataPayload 是本地候选解释，不是最终口径。
        2. 如果 rawMatrix.mode = full_raw_matrix，说明原始单元格已全量给你，你要自己判断多表头、时间顺序、字段含义和周期完整性。
        3. 如果 rawMatrix.mode = indexed_raw_matrix，说明首轮没有全量原始单元格；涉及未覆盖区域、复杂表头、精确周期或细分原因时，必须输出 data_requests 请求 getRawRange 或 getFullSheet。
        4. 先判断数据是否足够，不足就输出 data_requests，不要硬下结论。
        5. 小表或透视宽表必须覆盖全部指标；如果 coverage 显示没有覆盖，不允许对未覆盖数据下结论。
        6. 不要默认输出“最新完整周期 vs 上一周期”。如果用户或报表说明没有指定周期，只做全周期概览；如果识别到相邻周期差异，只能标为候选观察。
        7. 你负责业务理解、指标语义、候选联动和外部事件假设；数值方向必须服从输入事实。
        8. 页面埋点只能作为用户行为路径解释，不能单独证明业务结果原因。
        9. Confluence 只允许使用需求文档自身创建/修改时间，不能使用知识库同步或创建时间；这些时间不是上线时间，不能单独作为因果证据。

        输出必须是 JSON 对象，不要 Markdown，不要 JSON 以外文字：
        {
          "ready_for_analysis": true,
          "summary": "中文摘要",
          "data_availability": "你看到了什么、没看到什么",
          "primary_comparison": ["用户指定周期对比或相邻周期候选观察"],
          "historical_trend": ["历史趋势验证"],
          "key_changes": ["关键指标变化"],
          "anomalies": ["异常、未成熟周期、口径风险"],
          "data_requests": [{"kind":"getMetricSeries|getColumns|getRows|getAggregate|getComparisonWindow|getRawRange|getFullSheet","target":"指标/字段/条件/rowStart=1,rowEnd=80,colStart=1,colEnd=20","reason":"为什么需要"}],
          "metric_link_candidates": ["可进入多表联动的指标候选"],
          "external_event_hypotheses": ["可能需要匹配的社会/自然/能源/节假日等外部事件"]
        }

        轮次：\(round)
        报表人工/自动含义：\(semantic)
        之前校验问题：
        \(previousWarnings.map { "- \($0)" }.joined(separator: "\n"))

        已补充数据：
        \(supplementalContext.joined(separator: "\n\n"))

        表格上下文包：
        \(packageJSON)
        """
    }

    private static func parse(_ raw: String) -> AITableFirstAnalysis? {
        guard let data = extractJSONObject(from: raw).data(using: .utf8) else { return nil }
        guard let payload = try? JSONDecoder().decode(AITableAnalysisPayload.self, from: data) else { return nil }
        return AITableFirstAnalysis(
            generatedAt: Date(),
            readyForAnalysis: payload.readyForAnalysis ?? true,
            summary: payload.summary ?? "",
            dataAvailability: payload.dataAvailability ?? "",
            primaryComparison: payload.primaryComparison ?? [],
            historicalTrend: payload.historicalTrend ?? [],
            keyChanges: payload.keyChanges ?? [],
            anomalies: payload.anomalies ?? [],
            missingDataRequests: (payload.dataRequests ?? []).compactMap { request in
                guard let kind = AIDataRequestKind(rawValue: request.kind ?? "") else { return nil }
                return AIDataRequest(kind: kind, target: request.target ?? "", reason: request.reason ?? "")
            },
            metricLinkCandidates: payload.metricLinkCandidates ?? [],
            externalEventHypotheses: payload.externalEventHypotheses ?? [],
            validationWarnings: [],
            coverageSummary: ""
        )
    }

    private static func extractJSONObject(from value: String) -> String {
        guard let start = value.firstIndex(of: "{"),
              let end = value.lastIndex(of: "}"),
              start <= end else {
            return value
        }
        return String(value[start...end])
    }

    static func initialMetricProfiles(for report: ImportedReport) -> [MetricSemanticProfile] {
        let names = (report.firstColumnValues + report.trendSummary.metricTrends.map(\.metricName)).uniqued()
        return names.prefix(200).map { name in
            MetricSemanticProfile(
                metricName: name,
                aliases: aliases(for: name),
                businessStage: stage(for: name, report: report),
                directionPreference: directionPreference(for: name),
                maturityWindowDays: maturityWindowDays(for: name),
                impactLagDays: impactLagDays(for: name),
                relatedMetrics: [],
                commonAnomalyExplanations: commonAnomalyExplanations(for: name, report: report),
                source: "local_semantic_inference",
                confidence: 0.62,
                isUserConfirmed: false,
                updatedAt: Date()
            )
        }
    }

    private static func mergeMetricProfiles(existing: [MetricSemanticProfile], inferred: [MetricSemanticProfile]) -> [MetricSemanticProfile] {
        var result = existing
        let existingKeys = Set(existing.map { $0.metricName.normalizedKey })
        result.append(contentsOf: inferred.filter { !existingKeys.contains($0.metricName.normalizedKey) })
        return result
    }

    private static func aliases(for name: String) -> [String] {
        let normalized = name.normalizedKey
        if normalized.contains("注册") { return ["register", "signup", "registration"] }
        if normalized.contains("授信") || normalized.contains("审核") { return ["credit", "approval", "risk_review"] }
        if normalized.contains("消费") || normalized.contains("交易") { return ["purchase", "payment", "transaction"] }
        if normalized.contains("点击") { return ["click", "tap"] }
        if normalized.contains("曝光") { return ["view", "impression", "exposure"] }
        return []
    }

    private static func stage(for name: String, report: ImportedReport) -> MetricBusinessStage {
        let text = "\(name) \(report.fileName) \(report.kind.label)".normalizedKey
        if text.contains("页面") || text.contains("埋点") || text.contains("点击") || text.contains("曝光") || text.contains("event") { return .pageBehavior }
        if text.contains("投放") || text.contains("广告") { return .acquisition }
        if text.contains("安装") || text.contains("install") { return .install }
        if text.contains("注册") || text.contains("signup") || text.contains("register") { return .registration }
        if text.contains("申请") || text.contains("提审") || text.contains("提交") { return .application }
        if text.contains("授信") || text.contains("审核") || text.contains("审批") { return .creditReview }
        if text.contains("发卡") || text.contains("激活") { return .cardActivation }
        if text.contains("消费") || text.contains("交易") || text.contains("支付") { return .payment }
        if text.contains("留存") || text.contains("活跃") { return .retention }
        if text.contains("错误") || text.contains("失败") || text.contains("风险") { return .risk }
        return .unknown
    }

    private static func directionPreference(for name: String) -> MetricDirectionPreference {
        if name.normalizedKey.contains("错误") || name.normalizedKey.contains("失败") || name.normalizedKey.contains("耗时") || name.normalizedKey.contains("流失") {
            return .lowerIsBetter
        }
        return .higherIsBetter
    }

    private static func maturityWindowDays(for name: String) -> Int? {
        let text = name.normalizedKey
        if text.contains("30日") || text.contains("30d") { return 30 }
        if text.contains("14日") || text.contains("14d") { return 14 }
        if text.contains("7日") || text.contains("7d") { return 7 }
        if text.contains("3日") || text.contains("3d") { return 3 }
        return nil
    }

    private static func impactLagDays(for name: String) -> Int? {
        switch stage(for: name, report: ImportedReport(
            id: UUID(),
            fileName: "",
            kind: .generic,
            importedAt: Date(),
            rowCount: 0,
            headers: [],
            sampleRows: []
        )) {
        case .payment, .retention: return 7
        case .creditReview, .cardActivation: return 3
        case .registration, .application, .pageBehavior: return 0
        default: return nil
        }
    }

    private static func commonAnomalyExplanations(for name: String, report: ImportedReport) -> [String] {
        let text = "\(name) \(report.displayName) \(report.kind.label)".normalizedKey
        if text.contains("注册") || text.contains("signup") || text.contains("register") {
            return ["投放流量结构变化", "注册页埋点点击/错误变化", "短信或验证码链路异常", "渠道或设备版本变化"]
        }
        if text.contains("授信") || text.contains("审核") || text.contains("审批") {
            return ["风控策略调整", "KYC/短信/三方服务波动", "注册质量变化", "节假日审核产能变化"]
        }
        if text.contains("消费") || text.contains("交易") || text.contains("缴费") || text.contains("支付") {
            return ["节假日或账单周期影响", "能源/用电/停电影响", "支付成功率或三方通道波动", "活动或价格策略影响"]
        }
        if text.contains("点击") || text.contains("曝光") || text.contains("页面") || text.contains("event") {
            return ["页面流量入口变化", "页面性能或报错变化", "按钮位置或文案变化", "埋点口径变化"]
        }
        if text.contains("错误") || text.contains("失败") || text.contains("耗时") {
            return ["服务端异常", "三方依赖超时", "网络或地区基础设施波动", "版本发布引入问题"]
        }
        return ["渠道/人群结构变化", "统计口径变化", "时间周期未完整", "外部事件或竞品动作影响"]
    }
}

private struct AITableAnalysisPayload: Decodable {
    var readyForAnalysis: Bool?
    var summary: String?
    var dataAvailability: String?
    var primaryComparison: [String]?
    var historicalTrend: [String]?
    var keyChanges: [String]?
    var anomalies: [String]?
    var dataRequests: [DataRequestPayload]?
    var metricLinkCandidates: [String]?
    var externalEventHypotheses: [String]?

    enum CodingKeys: String, CodingKey {
        case readyForAnalysis = "ready_for_analysis"
        case summary
        case dataAvailability = "data_availability"
        case primaryComparison = "primary_comparison"
        case historicalTrend = "historical_trend"
        case keyChanges = "key_changes"
        case anomalies
        case dataRequests = "data_requests"
        case metricLinkCandidates = "metric_link_candidates"
        case externalEventHypotheses = "external_event_hypotheses"
    }

    struct DataRequestPayload: Decodable {
        var kind: String?
        var target: String?
        var reason: String?
    }
}

private extension Array where Element == AIDataRequest {
    func uniquedByStableKey() -> [AIDataRequest] {
        var seen = Set<String>()
        return filter { request in
            seen.insert("\(request.kind.rawValue)|\(request.target.normalizedKey)|\(request.reason.normalizedKey)").inserted
        }
    }
}
