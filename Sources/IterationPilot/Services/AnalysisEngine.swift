import Foundation

enum AnalysisEngine {
    static func buildQualityReport(
        for pack: DataPack,
        knowledgeEntries: [KnowledgeEntry] = []
    ) -> QualityReport {
        var issues: [DataQualityIssue] = []
        let knowledgeEvents = KnowledgeEventAxis.productEvents(from: knowledgeEntries)

        if pack.productUpdates.isEmpty && knowledgeEvents.isEmpty {
            issues.append(DataQualityIssue(
                id: UUID(),
                severity: .warning,
                title: "缺少产品事件轴",
                detail: "知识库里还没有可参考的产品文档或事件记录，AI 分析只能输出弱相关性判断。",
                recommendedAction: "先同步 Confluence 或沉淀知识库；暂时不要求手动导入 product_updates.csv。"
            ))
        } else if pack.productUpdates.isEmpty {
            issues.append(DataQualityIssue(
                id: UUID(),
                severity: .info,
                title: "产品事件轴来自知识库",
                detail: "当前没有手动导入产品更新 CSV，系统会参考 \(knowledgeEvents.count) 条知识库/Confluence 条目生成产品文档事件轴；Confluence 只使用需求文档自身创建/修改时间，不使用知识库同步或创建时间，且不等于实际产品上线。",
                recommendedAction: "如需高置信归因，请在 Confluence 正文或知识库条目里补充实际上线/发布/生效日期；无需单独维护产品事件 CSV。"
            ))
        }

        let dates = Set(pack.metrics.map { Calendar.current.startOfDay(for: $0.date) })
        if dates.count < 7 && !pack.metrics.isEmpty {
            issues.append(DataQualityIssue(
                id: UUID(),
                severity: .warning,
                title: "指标观察窗口偏短",
                detail: "当前分析资料只有 \(dates.count) 个指标日期，难以区分真实趋势和短期噪声。",
                recommendedAction: "建议至少导入 14 天数据，最好覆盖更新前后各 7 天。"
            ))
        }

        let missingFields = pack.productUpdates.filter {
            $0.expectedMetric == "未声明" || $0.releaseNote == "未填写更新说明" || $0.targetUser == "全量"
        }
        if !missingFields.isEmpty {
            issues.append(DataQualityIssue(
                id: UUID(),
                severity: .info,
                title: "部分产品更新缺少决策字段",
                detail: "\(missingFields.count) 条产品更新没有完整声明预期指标、目标用户或更新说明。",
                recommendedAction: "复盘时补齐这些字段，否则 AI 只能做粗粒度归因。"
            ))
        }

        let negativeValues = pack.metrics.filter { $0.value < 0 }
        if !negativeValues.isEmpty {
            issues.append(DataQualityIssue(
                id: UUID(),
                severity: .warning,
                title: "发现负数指标值",
                detail: "\(negativeValues.count) 条指标记录为负数，可能是退款/净增指标，也可能是导出异常。",
                recommendedAction: "确认指标口径，并在 manifest 的 known_issues 中标注。"
            ))
        }

        let gaps = metricDateGaps(in: pack.metrics)
        for gap in gaps.prefix(4) {
            issues.append(DataQualityIssue(
                id: UUID(),
                severity: .warning,
                title: "指标日期不连续",
                detail: gap,
                recommendedAction: "确认是否漏导出日期；如果是数据平台延迟，请在 manifest 记录。"
            ))
        }

        for knownIssue in pack.manifest.knownIssues {
            issues.append(DataQualityIssue(
                id: UUID(),
                severity: .info,
                title: "Manifest 已知问题",
                detail: knownIssue,
                recommendedAction: "归因时将该问题作为干扰因素处理。"
            ))
        }

        let criticalCount = issues.filter { $0.severity == .critical }.count
        let warningCount = issues.filter { $0.severity == .warning }.count
        let verdict: QualityVerdict
        if criticalCount > 0 {
            verdict = .blocked
        } else if warningCount > 0 {
            verdict = .caution
        } else {
            verdict = .usable
        }

        return QualityReport(
            generatedAt: Date(),
            verdict: verdict,
            issues: issues,
            stats: QualityStats(
                updateCount: pack.productUpdates.count + knowledgeEvents.count,
                metricCount: pack.metrics.count,
                eventCount: pack.events.count,
                feedbackCount: pack.feedback.count,
                metricDateCount: dates.count
            )
        )
    }

    static func analyze(
        pack: DataPack,
        referenceItems: [ExternalReferenceItem] = [],
        referenceSources: [ExternalReferenceSource] = [],
        correctionMemories: [AnalysisCorrectionMemory] = [],
        knowledgeEntries: [KnowledgeEntry] = []
    ) -> AnalysisReport {
        var pack = pack
        pack.importedReports = pack.importedReports.filter { !$0.isIgnoredFromAnalysis }
        let insights = buildMetricInsights(from: pack.metrics)
        let tableTrendOverview = ReportTrendAnalyzer.combinedTrendOverview(for: pack.importedReports)
        let tableTrendBullets = ReportTrendAnalyzer.combinedTrendBullets(for: pack.importedReports)
        let contextSignals = AnalysisContextSynthesizer.buildSignals(
            pack: pack,
            referenceItems: referenceItems,
            referenceSources: referenceSources,
            correctionMemories: correctionMemories,
            knowledgeEntries: knowledgeEntries
        )
        var findings = insights.map {
            buildAttributionFinding(
                for: $0,
                pack: pack,
                referenceItems: referenceItems,
                correctionMemories: correctionMemories,
                knowledgeEntries: knowledgeEntries
            )
        }
        findings.append(contentsOf: buildTrendContextFindings(
            pack: pack,
            contextSignals: contextSignals,
            maxCount: insights.isEmpty ? 6 : max(0, 4 - findings.count)
        ))
        let opportunities = buildOpportunities(from: insights, findings: findings, pack: pack)
        let summary = buildSummary(
            insights: insights,
            findings: findings,
            opportunities: opportunities,
            pack: pack,
            contextSignals: contextSignals
        )

        return AnalysisReport(
            generatedAt: Date(),
            summary: summary,
            tableTrendOverview: tableTrendOverview,
            tableTrendBullets: tableTrendBullets,
            contextSignals: contextSignals,
            metricInsights: insights,
            attributionFindings: findings,
            opportunities: opportunities
        )
    }

    static func generateMemo(
        for pack: DataPack,
        referenceItems: [ExternalReferenceItem] = [],
        referenceSources: [ExternalReferenceSource] = [],
        correctionMemories: [AnalysisCorrectionMemory] = [],
        knowledgeEntries: [KnowledgeEntry] = []
    ) -> String {
        let report = pack.analysisReport
        let topInsights = report.metricInsights.prefix(5)
        let topFindings = report.attributionFindings.prefix(5)
        let topOpportunities = report.opportunities.sorted { $0.score > $1.score }.prefix(5)
        let topContextSignals = report.contextSignals.prefix(12)
        let timelineSignals = report.contextSignals.filter { $0.domain == .timeline }.prefix(8)
        let latestKnowledgeEvents = KnowledgeEventAxis.productEvents(from: knowledgeEntries).prefix(8)
        let latestReferences = referenceItems.sorted { $0.displayDate > $1.displayDate }.prefix(8)
        let enabledSourceCount = referenceSources.filter(\.enabled).count
        let task = currentTask(in: pack)
        let businessLinkLines = businessLinkMemoLines(pack: pack, task: task)
        let metricLinkLines = metricLinkMemoLines(pack: pack, task: task)
        let relevantMemories = correctionMemories
            .filter { memory in
                memory.packID == pack.id || report.metricInsights.contains { memoryMatches($0, memory: memory) }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(6)

        var lines: [String] = []
        lines.append("# NexaFlow 完整汇报 - \(pack.period)")
        lines.append("")
        lines.append("生成时间：\(DateFormatting.shortDateTime.string(from: Date()))")
        lines.append("分析任务：\(task?.name ?? "默认分析任务")")
        if let goal = task?.goal.nilIfBlank {
            lines.append("本次分析目标：\(goal)")
        } else {
            lines.append("本次分析目标：未填写明确目标，按默认智能分析执行。")
        }
        if let task {
            lines.append("AI 预读状态：\(aiObservationStatusText(pack: pack, task: task))")
        }
        lines.append("数据范围：\(pack.dateRangeText)")
        lines.append("数据质量：\(pack.qualityReport.verdict.rawValue)")
        lines.append("")
        lines.append("## 1. 表格数据趋势")
        if report.tableTrendBullets.isEmpty {
            lines.append("- \(report.tableTrendOverview.isEmpty ? "暂无表格趋势摘要。" : report.tableTrendOverview)")
        } else {
            lines.append(report.tableTrendOverview)
            for item in report.tableTrendBullets.prefix(80) {
                lines.append("- \(item)")
            }
        }
        lines.append("")
        lines.append("## 2. AI 数据覆盖与限制")
        let activeReportsForCoverage = pack.importedReports.filter { !$0.isIgnoredFromAnalysis }
        if activeReportsForCoverage.isEmpty {
            lines.append("- 当前任务没有参与报表。")
        } else {
            for report in activeReportsForCoverage.prefix(20) {
                let coverage = report.tableContextCoverage?.summary ?? "未生成覆盖包"
                let aiStatus = report.aiFirstAnalysis.map { $0.readyForAnalysis ? "AI 已理解" : "AI 待补数据" } ?? "AI 未运行"
                let requests = report.aiDataRequests.isEmpty ? "" : "；追问 \(report.aiDataRequests.count) 项"
                lines.append("- \(report.displayName)：\(coverage)；\(aiStatus)\(requests)。")
            }
        }
        lines.append("")
        lines.append("## 3. 业务链路影响图")
        if businessLinkLines.isEmpty {
            lines.append("- 当前任务未形成跨业务链路；单表场景只做本表趋势分析。")
        } else {
            for line in businessLinkLines {
                lines.append("- \(line)")
            }
        }
        lines.append("")
        lines.append("## 4. 指标级多表联动")
        if metricLinkLines.isEmpty {
            lines.append("- 当前任务未发现可靠的指标级联动；如导入了页面埋点表和业务结果表，请确认它们是否已加入同一分析任务。")
        } else {
            for line in metricLinkLines {
                lines.append("- \(line)")
            }
            lines.append("- 解释规则：页面埋点只能解释用户行为路径，不能单独证明业务结果原因；低置信联动必须作为待验证假设。")
        }
        lines.append("")
        lines.append("## 5. 综合上下文信号")
        if topContextSignals.isEmpty {
            lines.append("- 暂无已合成的多源上下文信号。")
        } else {
            for signal in topContextSignals {
                lines.append("- \(AnalysisContextSynthesizer.compactLine(for: signal))")
            }
        }
        if enabledSourceCount > 0 {
            lines.append("- 已启用参照源：\(enabledSourceCount) 个；已采集参照条目：\(referenceItems.count) 条。")
        }
        lines.append("")
        lines.append("## 6. 时间线匹配证据")
        if timelineSignals.isEmpty {
            lines.append("- 暂未形成表格时间段与知识库/外部情报的结构化匹配。")
        } else {
            for signal in timelineSignals {
                lines.append("- \(AnalysisContextSynthesizer.compactLine(for: signal))")
            }
            lines.append("- 注意：Confluence 只使用需求文档自身创建/修改时间，不使用知识库同步或创建时间；这些时间不等于实际产品上线时间，只有文档内明确写出的上线/发布/生效日期才可作为较强时间证据。")
        }
        lines.append("")
        lines.append("## 7. 外部事件影响")
        if pack.externalEventImpacts.isEmpty {
            lines.append("- 暂无 AI 外部事件影响匹配。")
        } else {
            for record in pack.externalEventImpacts.prefix(10) {
                lines.append("- \(record.eventTitle)：关联 \(record.relatedMetrics.joined(separator: "，"))；\(record.mechanism)；窗口：\(record.overlapWithDataWindow)；证据 \(record.evidenceLevel.rawValue)，置信度 \(Int(record.confidence * 100))%。")
            }
        }
        lines.append("")
        lines.append("## 8. 关键数据变化")
        if topInsights.isEmpty {
            lines.append("- 未检测到显著波动，或观察窗口不足。")
        } else {
            for insight in topInsights {
                lines.append("- \(insight.metric)（\(insight.scope)）：\(insight.direction.rawValue) \(insight.formattedChange)，从 \(insight.previousAverage.compactText) 到 \(insight.currentAverage.compactText)。")
            }
        }
        lines.append("")
        lines.append("## 9. 知识库产品文档/事件轴")
        if latestKnowledgeEvents.isEmpty {
            lines.append("- 暂无知识库产品文档/事件。同步 Confluence 后会自动补充，不需要手动导入产品更新 CSV。")
        } else {
            for entry in latestKnowledgeEvents {
                lines.append("- \(KnowledgeEventAxis.compactContext(for: entry))")
            }
        }
        lines.append("")
        lines.append("## 10. 竞品/政策/市场/社会事件参照")
        if latestReferences.isEmpty {
            lines.append("- 暂无外部参照数据。")
        } else {
            for item in latestReferences {
                lines.append("- \(referenceTimingText(item)) [\(item.domain.label)] \(item.title)：\(item.summary)")
            }
        }
        lines.append("")
        lines.append("## 11. 已应用纠偏记忆")
        if relevantMemories.isEmpty {
            lines.append("- 暂无。")
        } else {
            for memory in relevantMemories {
                lines.append("- \(memory.metric.isEmpty ? "整体分析" : memory.metric)：\(memory.summaryText)")
            }
        }
        lines.append("")
        lines.append("## 12. 仍需补充的数据")
        let nextData = report.attributionFindings.flatMap(\.recommendedNextData).uniqued().prefix(6)
        if nextData.isEmpty {
            lines.append("- 暂无。")
        } else {
            for item in nextData {
                lines.append("- \(item)")
            }
        }
        lines.append("")
        lines.append("## 13. 验证方式")
        lines.append("- 主指标：选择与机会点直接对应的转化、留存、收入或质量指标。")
        lines.append("- 护栏指标：投诉率、错误率、加载耗时、付费转化或留存等不可被牺牲的指标。")
        lines.append("- 观察窗口：至少 7 天；如果流量低，延长到 14 天。")
        lines.append("- 回滚条件：主指标显著下降或护栏指标恶化超过预设阈值。")
        lines.append("")
        lines.append("## 14. 最后结论")
        lines.append(report.summary.isEmpty ? "当前已完成表格趋势扫描；如需形成归因结论，可继续补充报表语义、知识库事件轴或外部参照。" : report.summary)
        if topFindings.isEmpty {
            lines.append("- 暂无可用归因。")
        } else {
            for finding in topFindings {
                lines.append("- \(finding.title)")
                lines.append("  - 证据等级：\(finding.evidenceLevel.label)")
                lines.append("  - 主要判断：\(finding.primaryCause)")
                lines.append("  - 置信度：\(finding.confidence)/10")
            }
        }
        if topOpportunities.isEmpty {
            lines.append("- 可选产品方案：暂无高可信机会，建议优先补数据。")
        } else {
            lines.append("- 可选产品方案：")
            for opportunity in topOpportunities {
                lines.append("  - \(opportunity.title)：优先级 \(opportunity.priorityLabel)，评分 \(opportunity.score.compactText)；问题：\(opportunity.problem)；影响用户：\(opportunity.affectedUsers)")
            }
        }
        if let best = topOpportunities.first {
            lines.append("- 推荐方案：优先推进 \(best.title)。原因是影响、紧急度和证据置信度综合评分最高。")
        } else {
            lines.append("- 推荐方案：本轮先保留为趋势观察，不直接进入开发决策；如需归因，可继续补充报表语义、知识库事件轴或外部参照。")
        }
        lines.append("")
        lines.append("## 15. 人工决策")
        lines.append("- 决策结论：待确认")
        lines.append("- 决策人：")
        lines.append("- 计划上线时间：")
        lines.append("- 复盘时间：")
        return lines.joined(separator: "\n")
    }

    static func buildAIPrompt(
        for pack: DataPack,
        referenceItems: [ExternalReferenceItem] = [],
        referenceSources: [ExternalReferenceSource] = [],
        correctionMemories: [AnalysisCorrectionMemory] = [],
        knowledgeEntries: [KnowledgeEntry] = []
    ) -> String {
        var pack = pack
        pack.importedReports = pack.importedReports.filter { !$0.isIgnoredFromAnalysis }
        let task = currentTask(in: pack)
        var payload: [String] = []
        payload.append("请基于以下数据包做产品迭代决策分析。要求：区分事实/推断/假设；每条归因必须给证据等级 A/B/C/D/E；输出推荐方案、风险、验证方式和需补数据项。")
        payload.append("输出顺序必须严格遵守：先写「表格数据趋势」；用户指定周期时严格按指定周期，未指定周期时只做全周期概览；再写「指标级多表联动」和「业务链路影响图」；所有原因判断、产品建议和推荐方案必须放在最后的「最后结论」部分。")
        payload.append("多表分析必须基于当前分析任务内的表和指标关系。业务功能表与页面埋点表联动时，只能把曝光/点击/提交/报错/停留等埋点作为行为路径证据，不能单独证明业务结果原因；方向冲突要作为反证或结构变化线索。")
        payload.append("「综合上下文信号」必须直接用于最后结论：它已经把表格趋势、知识库、竞品舆情、政策/监管、市场参照和历史纠偏做过关联评分。不要机械罗列信号；请说明它们如何支持、削弱或干扰判断。")
        payload.append("必须优先使用「时间线匹配证据」：只把发生在波动前或同期、且业务语义相关的事件作为候选原因；晚于波动的事件只能作为反证或后续影响。Confluence 只能使用需求文档自身创建/修改时间，不能使用知识库同步或创建时间；这些时间不等于实际产品上线时间，不能单独作为上线因果证据。")
        payload.append("必须优先遵守“历史纠偏记忆”：如果当前结论与记忆冲突，要说明冲突并按记忆规则重新判断。")
        payload.append("")
        payload.append("数据包：\(pack.name) / \(pack.period)")
        payload.append("当前分析任务：\(task?.name ?? "默认分析任务")")
        if let goal = task?.goal.nilIfBlank {
            payload.append("本次分析目标：\(goal)")
            payload.append("请优先回应本次分析目标，再补充你从表格、外部事件和知识库中自动发现的重要问题。")
        } else {
            payload.append("本次分析目标：未填写明确目标，按默认智能分析执行。")
        }
        if let task {
            payload.append("AI 预读状态：\(aiObservationStatusText(pack: pack, task: task))。如果状态不是“已生成”，请在报告中标记“未使用最新 AI 预读”，并基于完整事实包说明限制。")
        }
        payload.append("数据质量：\(pack.qualityReport.verdict.rawValue)")
        payload.append("数据范围：\(pack.dateRangeText)")
        payload.append("")
        payload.append("当前任务参与报表：")
        if pack.importedReports.isEmpty {
            payload.append("- 未选择报表；只能使用 Data Pack 内置指标、知识库和外部参照。")
        } else {
            for report in pack.importedReports {
                let role = task?.role(for: report.id).label ?? "参与分析"
                payload.append("- [\(role)] \(report.displayName)：\(report.kind.label)，\(report.shape.label)，\(report.rowCount) 行，首列指标 \(report.firstColumnValues.count) 个。")
            }
        }
        payload.append("")
        payload.append("多表关系说明：")
        let relationship = task?.relationshipProfile ?? pack.reportRelationshipProfile
        let reportNamesByID = Dictionary(uniqueKeysWithValues: pack.importedReports.map { ($0.id, $0.displayName) })
        if pack.importedReports.count <= 1 {
            payload.append("- 单表或无额外报表，不需要跨表合并关系。")
        } else {
            let primaryName = relationship.primaryReportID.flatMap { reportNamesByID[$0] } ?? "未确认"
            let supportingNames = relationship.supportingReportIDs.compactMap { reportNamesByID[$0] }
            let incompatibleNames = relationship.incompatibleReportIDs.compactMap { reportNamesByID[$0] }
            payload.append("- 主表：\(primaryName)")
            payload.append("- 辅助表：\(supportingNames.isEmpty ? "未设置" : supportingNames.joined(separator: "，"))")
            payload.append("- 不可合并/仅旁证：\(incompatibleNames.isEmpty ? "无" : incompatibleNames.joined(separator: "，"))")
            payload.append("- 周期一致性：\(relationship.periodConsistency)")
            payload.append("- 人群一致性：\(relationship.audienceConsistency)")
            payload.append("- 渠道一致性：\(relationship.channelConsistency)")
            payload.append("- 版本一致性：\(relationship.versionConsistency)")
            payload.append("- 实验组一致性：\(relationship.experimentConsistency)")
            payload.append("- 确认状态：\(relationship.confirmationStatus.label)")
        }
        payload.append("")
        payload.append("业务链路影响图（已确认优先；未确认边只能作为假设）：")
        let businessLines = businessLinkMemoLines(pack: pack, task: task)
        if businessLines.isEmpty {
            payload.append("- 暂无业务链路影响图。")
        } else {
            for line in businessLines.prefix(30) {
                payload.append("- \(line)")
            }
        }
        payload.append("")
        payload.append("指标级多表联动（业务功能指标 ↔ 页面埋点/上游行为指标）：")
        let metricLinkLines = metricLinkMemoLines(pack: pack, task: task)
        if metricLinkLines.isEmpty {
            payload.append("- 暂无可靠指标级联动。不要强行把多张表互相归因；可提示需要把页面埋点表和业务结果表加入同一分析任务并确认周期口径。")
        } else {
            for line in metricLinkLines.prefix(40) {
                payload.append("- \(line)")
            }
            payload.append("- 解释规则：页面埋点只能解释用户行为路径，不能单独证明业务结果原因；低置信联动写为待验证假设；方向冲突要作为反证或结构变化线索。")
        }
        payload.append("")
        payload.append("表格数据趋势（先读这里；只描述数据走势，不做结论）：")
        payload.append("- \(pack.analysisReport.tableTrendOverview.isEmpty ? "暂无表格趋势摘要。" : pack.analysisReport.tableTrendOverview)")
        for item in pack.analysisReport.tableTrendBullets.prefix(100) {
            payload.append("- \(item)")
        }
        payload.append("")
        payload.append("AI 数据覆盖与表格首轮理解（防止漏看数据；没有覆盖的数据不能下结论）：")
        if pack.importedReports.isEmpty {
            payload.append("- 暂无报表覆盖信息。")
        } else {
            for report in pack.importedReports.prefix(30) {
                let coverage = report.tableContextCoverage
                payload.append("- \(report.displayName)：\(coverage?.summary ?? "未生成覆盖包")；\(coverage?.omittedRowsDescription ?? "")")
                if let ai = report.aiFirstAnalysis {
                    payload.append("  - AI 首轮理解：\(ai.summary)")
                    if !ai.dataAvailability.isEmpty {
                        payload.append("  - 数据可用性：\(ai.dataAvailability)")
                    }
                    for line in ai.primaryComparison.prefix(8) {
                        payload.append("  - 相邻周期候选：\(line)")
                    }
                    if !ai.validationWarnings.isEmpty {
                        payload.append("  - 校验提醒：\(ai.validationWarnings.joined(separator: "；"))")
                    }
                    if !report.aiDataRequests.isEmpty {
                        payload.append("  - AI 追问数据：\(report.aiDataRequests.prefix(8).map { "\($0.kind.rawValue): \($0.target) -> \($0.status.rawValue)" }.joined(separator: "；"))")
                    }
                } else {
                    payload.append("  - AI 预读未运行；请基于完整事实包分析，并说明限制。")
                }
            }
        }
        payload.append("")
        payload.append("外部社会/自然事件影响匹配（AI 直接分析；只能作为候选影响，不能机械归因）：")
        if pack.externalEventImpacts.isEmpty {
            payload.append("- 暂无事件影响匹配。")
        } else {
            for record in pack.externalEventImpacts.prefix(20) {
                payload.append("- \(record.eventTitle)：地区 \(record.region)，关联指标 \(record.relatedMetrics.joined(separator: "，"))，机制：\(record.mechanism)，窗口：\(record.overlapWithDataWindow)，证据 \(record.evidenceLevel.rawValue)，置信度 \(Int(record.confidence * 100))%。")
            }
        }
        payload.append("")
        payload.append("时间线匹配证据（确定性证据层；优先于散乱上下文）：")
        let timelineSignals = pack.analysisReport.contextSignals.filter { $0.domain == .timeline }
        if timelineSignals.isEmpty {
            payload.append("- 暂无表格时间段与知识库/外部情报的结构化匹配。")
        } else {
            for signal in timelineSignals.prefix(20) {
                payload.append("- \(AnalysisContextSynthesizer.promptLine(for: signal))")
            }
            payload.append("- 解释规则：前置/同期事件可作为候选原因或干扰；滞后事件不能作为主因。Confluence 只使用需求文档自身创建/修改时间，不使用知识库同步或创建时间；除非文档正文明确写出上线/发布/生效日期，否则只能作为弱线索。")
        }
        payload.append("")
        payload.append("综合上下文信号（多源合成；事实和推断已标注，必须在最后结论中结合）：")
        if pack.analysisReport.contextSignals.isEmpty {
            payload.append("- 暂无已合成上下文信号。")
        } else {
            for signal in pack.analysisReport.contextSignals.prefix(40) {
                payload.append("- \(AnalysisContextSynthesizer.promptLine(for: signal))")
            }
        }
        payload.append("")
        payload.append("手动产品更新 CSV（可选补充）：")
        if pack.productUpdates.isEmpty {
            payload.append("- 未手动导入；本轮产品事件轴直接参考知识库。")
        } else {
            for update in pack.productUpdates.prefix(20) {
                payload.append("- \(DateFormatting.shortDate.string(from: update.date)) \(update.module) \(update.changeType)：\(update.releaseNote)，目标用户：\(update.targetUser)，预期指标：\(update.expectedMetric)")
            }
        }
        payload.append("")
        payload.append("知识库产品文档/事件轴（来自 Confluence/知识库；Confluence 只使用需求文档自身创建/修改时间，不使用知识库同步或创建时间）：")
        let knowledgeEvents = KnowledgeEventAxis.productEvents(from: knowledgeEntries)
        if knowledgeEvents.isEmpty {
            payload.append("- 暂无知识库产品文档/事件。")
        } else {
            for entry in knowledgeEvents.prefix(30) {
                payload.append("- \(KnowledgeEventAxis.compactContext(for: entry))")
            }
        }
        payload.append("")
        payload.append("报表知识库条目（来自表格 AI 问答沉淀；用于解释口径，不作为产品事件）：")
        let reportKnowledgeEntries = knowledgeEntries
            .filter {
                $0.tags.contains { $0.normalizedKey.contains("报表知识".normalizedKey) || $0.normalizedKey.contains("ai问答沉淀".normalizedKey) } &&
                    !$0.tags.contains { $0.normalizedKey == "已归档".normalizedKey }
            }
            .sorted { ($0.sourceUpdatedAt ?? $0.sourceCreatedAt ?? $0.createdAt) > ($1.sourceUpdatedAt ?? $1.sourceCreatedAt ?? $1.createdAt) }
        if reportKnowledgeEntries.isEmpty {
            payload.append("- 暂无报表知识沉淀。")
        } else {
            for entry in reportKnowledgeEntries.prefix(30) {
                payload.append("- \(KnowledgeEventAxis.compactContext(for: entry))")
            }
        }
        payload.append("")
        payload.append("上下文事件：")
        for event in pack.events.prefix(20) {
            payload.append("- \(DateFormatting.shortDate.string(from: event.date)) [\(event.eventType)] \(event.title)，范围：\(event.scope)，说明：\(event.note)")
        }
        payload.append("")
        payload.append("已检测指标波动：")
        for insight in pack.analysisReport.metricInsights.prefix(12) {
            payload.append("- \(insight.metric) / \(insight.scope)：\(insight.direction.rawValue) \(insight.formattedChange)，\(insight.previousAverage.compactText) -> \(insight.currentAverage.compactText)")
        }
        payload.append("")
        payload.append("用户反馈样本：")
        for item in pack.feedback.prefix(20) {
            payload.append("- \(DateFormatting.shortDate.string(from: item.date)) [\(item.source)/\(item.sentiment)] \(item.module)：\(item.text)")
        }
        payload.append("")
        payload.append("已导入报表：")
        if pack.importedReports.isEmpty {
            payload.append("- 暂无额外报表")
        } else {
            for report in pack.importedReports.prefix(30) {
                let fields = DataImportService.fieldDefinitionNames(for: report).prefix(16).joined(separator: ", ")
                let warningText = report.parseWarnings.isEmpty ? "" : "，解析提醒：\(report.parseWarnings.prefix(2).joined(separator: "；"))"
                payload.append("- \(report.fileName) [\(report.sourceFormat.label)/\(report.kind.label)/\(report.shape.label)/\(report.semanticStatus.label)]：\(report.rowCount) 行，字段 \(report.headers.count) 个，首列指标 \(report.firstColumnValues.count) 个，识别置信度 \(Int(report.detectedConfidence * 100))%，Sheet \(report.sheetName ?? "无")，编码 \(report.originalEncoding)，分隔符 \(report.delimiter)\(warningText)。字段/指标：\(fields)")
            }
        }
        payload.append("")
        payload.append("报表说明（已确认优先；未确认/低置信只能作为假设）：")
        if pack.importedReports.isEmpty {
            payload.append("- 暂无报表说明。")
        } else {
            for report in pack.importedReports.prefix(30) {
                let profile = report.semanticProfile
                let trust: String = switch report.semanticStatus {
                case .confirmed: "人工确认"
                case .autoInferred: "自动识别（语义置信度 \(Int(report.semanticConfidence * 100))%）"
                case .needsReview, .inProgress: "低置信待补充"
                }
                payload.append("- \(report.fileName)：\(profile.summary.isEmpty ? "未填写摘要" : profile.summary)")
                payload.append("  - 可信状态：\(trust)；结构：\(report.shape.label)；类型置信度：\(Int(report.detectedConfidence * 100))%")
                payload.append("  - 用途：\(profile.purpose.isEmpty ? "未记录" : profile.purpose)")
                payload.append("  - 业务对象：\(profile.businessObject.isEmpty ? "未记录" : profile.businessObject)")
                payload.append("  - 粒度：\(profile.grain.isEmpty ? "未记录" : profile.grain)")
                payload.append("  - 关键指标：\(profile.keyMetrics.isEmpty ? "未记录" : profile.keyMetrics.joined(separator: "，"))")
                payload.append("  - 关键维度：\(profile.dimensions.isEmpty ? "未记录" : profile.dimensions.joined(separator: "，"))")
                payload.append("  - 筛选条件：\(profile.filters.isEmpty ? "未记录" : profile.filters)")
                payload.append("  - 注意事项：\(profile.caveats.isEmpty ? "未记录" : profile.caveats.joined(separator: "，"))")
            }
        }
        payload.append("")
        payload.append("报表字段字典：")
        if pack.fieldDefinitions.isEmpty {
            payload.append("- 暂无")
        } else {
            for definition in pack.fieldDefinitions.prefix(120) {
                let meaning = definition.meaning.isEmpty ? "未填写" : definition.meaning
                let example = definition.exampleValue.isEmpty ? "" : "，样例：\(definition.exampleValue)"
                let notes = definition.notes.isEmpty ? "" : "，备注：\(definition.notes)"
                payload.append("- \(definition.reportName).\(definition.fieldName) [\(definition.reportKind.label)/\(definition.dataType)]：\(meaning)\(example)\(notes)")
            }
        }
        payload.append("")
        payload.append("竞品舆情/政策/市场参照：")
        if referenceItems.isEmpty {
            payload.append("- 暂无")
        } else {
            for item in referenceItems.sorted(by: { $0.displayDate > $1.displayDate }).prefix(30) {
                payload.append("- \(referenceTimingText(item)) [\(item.domain.label)/\(item.sourceName)] \(item.title)：\(item.summary)")
            }
        }
        payload.append("")
        payload.append("已配置参照数据源状态：")
        let enabledSources = referenceSources.filter(\.enabled)
        if enabledSources.isEmpty {
            payload.append("- 暂无启用的数据源。")
        } else {
            for source in enabledSources.prefix(30) {
                let lastFetched = source.lastFetchedAt.map { DateFormatting.shortDateTime.string(from: $0) } ?? "未采集"
                payload.append("- [\(source.domain.label)/\(source.collectorType.label)] \(source.name)：最近采集 \(lastFetched)，关键词：\(source.keywords.prefix(8).joined(separator: "，"))")
            }
        }
        payload.append("")
        payload.append("历史纠偏记忆：")
        let applicableMemories = correctionMemories
            .filter { $0.appliesToFuture || $0.packID == pack.id }
            .sorted { $0.updatedAt > $1.updatedAt }
        if applicableMemories.isEmpty {
            payload.append("- 暂无")
        } else {
            for memory in applicableMemories.prefix(30) {
                payload.append("- \(DateFormatting.shortDate.string(from: memory.updatedAt)) [\(memory.metric)/\(memory.scope)] 原判断：\(memory.originalConclusion)；修正：\(memory.revisedConclusion)；复用规则：\(memory.reusableRule)")
            }
        }
        return payload.joined(separator: "\n")
    }

    static func buildCorrectionPrompt(
        for pack: DataPack,
        finding: AttributionFinding?,
        userMessage: String,
        correctionMemories: [AnalysisCorrectionMemory]
    ) -> String {
        var payload: [String] = []
        payload.append("你正在和产品负责人进行归因纠偏对话。目标：承认可能错误的分析，基于用户指出的问题修正判断，并提炼可复用的纠偏记忆。")
        payload.append("输出格式必须包含：")
        payload.append("1. 修正后结论")
        payload.append("2. 为什么原分析可能错")
        payload.append("3. 还需要验证的数据")
        payload.append("4. 可沉淀记忆规则")
        payload.append("")
        payload.append("数据包：\(pack.name) / \(pack.period)")
        payload.append("当前分析摘要：\(pack.analysisReport.summary)")
        if let finding {
            payload.append("")
            payload.append("被纠偏的归因结论：")
            payload.append("- 标题：\(finding.title)")
            payload.append("- 指标：\(finding.relatedMetric) / \(finding.relatedScope)")
            payload.append("- 原主因：\(finding.primaryCause)")
            payload.append("- 证据等级：\(finding.evidenceLevel.label)")
            payload.append("- 支持信号：\(finding.supportingSignals.joined(separator: "；"))")
            payload.append("- 反证干扰：\(finding.counterSignals.joined(separator: "；"))")
        }
        payload.append("")
        payload.append("历史纠偏记忆：")
        let memories = correctionMemories
            .filter { $0.appliesToFuture || $0.packID == pack.id }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(12)
        if memories.isEmpty {
            payload.append("- 暂无")
        } else {
            for memory in memories {
                payload.append("- [\(memory.metric)/\(memory.scope)] \(memory.summaryText)")
            }
        }
        payload.append("")
        payload.append("用户纠偏输入：")
        payload.append(userMessage)
        return payload.joined(separator: "\n")
    }

    private static func currentTask(in pack: DataPack) -> AnalysisTask? {
        if let selectedID = pack.selectedAnalysisTaskID,
           let task = pack.analysisTasks.first(where: { $0.id == selectedID }) {
            return task
        }
        return pack.analysisTasks.first
    }

    private static func aiObservationStatusText(pack: DataPack, task: AnalysisTask) -> String {
        let reports = pack.importedReports.filter { report in
            task.activeReportIDs.contains(report.id) && !report.isIgnoredFromAnalysis
        }
        guard !reports.isEmpty else { return "未选择报表" }
        guard let generatedAt = task.aiObservationGeneratedAt,
              task.aiObservationSignature == aiObservationSignature(for: task, reports: reports) else {
            return task.aiObservationGeneratedAt == nil ? "未生成" : "需要更新"
        }
        let allReportsObserved = reports.allSatisfy { report in
            guard let analysis = report.aiFirstAnalysis else { return false }
            return analysis.generatedAt >= generatedAt.addingTimeInterval(-1)
        }
        return allReportsObserved ? "已生成" : "需要更新"
    }

    private static func aiObservationSignature(for task: AnalysisTask, reports: [ImportedReport]) -> String {
        let goalPart = task.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let reportPart = reports
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { report in
                let role = task.role(for: report.id).rawValue
                let importedAt = String(format: "%.3f", report.importedAt.timeIntervalSince1970)
                return "\(report.id.uuidString):\(role):\(importedAt)"
            }
            .joined(separator: "|")
        return "goal=\(goalPart)|reports=\(reportPart)"
    }

    private static func businessLinkMemoLines(pack: DataPack, task: AnalysisTask?) -> [String] {
        guard let task else { return [] }
        let profile = task.businessLinkProfile
        guard !profile.nodes.isEmpty || !profile.edges.isEmpty else { return [] }
        let reportNames = Dictionary(uniqueKeysWithValues: pack.importedReports.map { ($0.id, $0.displayName) })
        var lines: [String] = []
        lines.append("任务「\(task.name)」：\(profile.summary)；确认状态：\(profile.confirmationStatus.label)。")
        for node in profile.nodes.prefix(12) {
            let name = reportNames[node.reportID] ?? "未知报表"
            let confidence = Int(node.confidence * 100)
            lines.append("\(name)：业务域 \(node.businessDomain)，角色 \(node.metricRole)，对象 \(node.businessObject)，粒度 \(node.grain)，成熟窗口 \(node.maturityWindow)，置信度 \(confidence)%。")
        }
        for edge in profile.edges.prefix(12) {
            let source = reportNames[edge.sourceReportID] ?? "上游报表"
            let target = reportNames[edge.targetReportID] ?? "下游报表"
            let lag = edge.lagDays.map { "，滞后约 \($0) 天" } ?? ""
            let confidence = Int(edge.confidence * 100)
            let evidence = edge.evidence.isEmpty ? "" : " 证据：\(edge.evidence.prefix(3).joined(separator: "；"))。"
            lines.append("\(source) → \(target)：\(edge.relationType)\(lag)，置信度 \(confidence)%，状态 \(edge.confirmationStatus.label)。\(edge.hypothesis)\(evidence)")
        }
        return lines
    }

    private static func metricLinkMemoLines(pack: DataPack, task: AnalysisTask?) -> [String] {
        guard let task else { return [] }
        let links = task.businessLinkProfile.metricLinks.filter { $0.confirmationStatus != .rejected }
        guard !links.isEmpty else { return [] }
        let reportNames = Dictionary(uniqueKeysWithValues: pack.importedReports.map { ($0.id, $0.displayName) })
        return links.prefix(24).map { link in
            let source = reportNames[link.sourceReportID] ?? "上游表"
            let target = reportNames[link.targetReportID] ?? "下游表"
            let lag = link.lagDays.map { "，滞后约 \($0) 天" } ?? ""
            let evidence = link.evidence.isEmpty ? "" : "证据：\(link.evidence.prefix(3).joined(separator: "；"))"
            return "\(source).\(link.sourceMetric) → \(target).\(link.targetMetric)：\(link.relationType.label)\(lag)，\(link.directionAlignment)，证据\(link.evidenceLevel.rawValue)，置信度 \(Int(link.confidence * 100))%，状态 \(link.confirmationStatus.label)。\(evidence)"
        }
    }

    private static func buildMetricInsights(from metrics: [MetricPoint]) -> [MetricInsight] {
        let grouped = Dictionary(grouping: metrics) { metric in
            "\(metric.metric)|\(metric.scopeKey.isEmpty ? "全量" : metric.scopeKey)"
        }

        return grouped.compactMap { _, values -> MetricInsight? in
            let sorted = values.sorted { $0.date < $1.date }
            guard sorted.count >= 4 else { return nil }

            let window = min(7, max(2, sorted.count / 2))
            let previous = Array(sorted.dropLast(window).suffix(window))
            let current = Array(sorted.suffix(window))
            guard !previous.isEmpty, !current.isEmpty else { return nil }

            let previousAverage = average(previous.map(\.value))
            let currentAverage = average(current.map(\.value))
            let absoluteDelta = currentAverage - previousAverage
            let denominator = abs(previousAverage) < 0.0001 ? 1 : abs(previousAverage)
            let percentChange = absoluteDelta / denominator
            guard abs(percentChange) >= 0.08 || abs(absoluteDelta) >= 5 else { return nil }

            let direction: ChangeDirection = absoluteDelta > 0 ? .up : .down
            let severity: InsightSeverity
            if abs(percentChange) >= 0.25 {
                severity = .high
            } else if abs(percentChange) >= 0.12 {
                severity = .medium
            } else {
                severity = .low
            }

            let sample = current.last ?? sorted.last!
            return MetricInsight(
                id: UUID(),
                metric: sample.metric,
                scope: sample.scopeKey.isEmpty ? "全量" : sample.scopeKey,
                previousAverage: previousAverage,
                currentAverage: currentAverage,
                absoluteDelta: absoluteDelta,
                percentChange: percentChange,
                direction: direction,
                severity: severity,
                startDate: current.first?.date ?? sample.date,
                endDate: current.last?.date ?? sample.date
            )
        }
        .sorted { lhs, rhs in
            abs(lhs.percentChange) == abs(rhs.percentChange)
                ? lhs.metric < rhs.metric
                : abs(lhs.percentChange) > abs(rhs.percentChange)
        }
    }

    private static func buildAttributionFinding(
        for insight: MetricInsight,
        pack: DataPack,
        referenceItems: [ExternalReferenceItem],
        correctionMemories: [AnalysisCorrectionMemory],
        knowledgeEntries: [KnowledgeEntry]
    ) -> AttributionFinding {
        let nearbyUpdates = pack.productUpdates
            .filter { abs(Calendar.current.dateComponents([.day], from: $0.date, to: insight.endDate).day ?? 999) <= 10 }
            .sorted { score(update: $0, insight: insight) > score(update: $1, insight: insight) }

        let nearbyKnowledgeEvents = KnowledgeEventAxis.productEvents(from: knowledgeEntries)
            .filter { abs(Calendar.current.dateComponents([.day], from: KnowledgeEventAxis.eventDate(for: $0), to: insight.endDate).day ?? 999) <= 30 }
            .sorted { score(knowledgeEntry: $0, insight: insight) > score(knowledgeEntry: $1, insight: insight) }

        let nearbyEvents = pack.events
            .filter { abs(Calendar.current.dateComponents([.day], from: $0.date, to: insight.endDate).day ?? 999) <= 10 }
            .sorted { abs(Calendar.current.dateComponents([.day], from: $0.date, to: insight.endDate).day ?? 999) < abs(Calendar.current.dateComponents([.day], from: $1.date, to: insight.endDate).day ?? 999) }

        let bestUpdate = nearbyUpdates.first
        let eventCount = nearbyEvents.count
        let nearbyReferences = referenceItems.filter {
            abs(Calendar.current.dateComponents([.day], from: $0.displayDate, to: insight.endDate).day ?? 999) <= 14
        }
        .sorted { $0.displayDate > $1.displayDate }

        var supportingSignals: [String] = []
        var counterSignals: [String] = []
        var recommendedNextData = [
            "按用户分群拆解 \(insight.metric)",
            "补充该指标对应漏斗的上一环节和下一环节",
            "确认同期是否有运营、渠道、技术事故或口径变化"
        ]

        if !nearbyReferences.isEmpty {
            recommendedNextData.append("评估竞品/政策/市场事件对目标用户、渠道和转化路径的影响范围")
        }

        var evidence: EvidenceLevel
        var confidence: Int
        var primaryCause: String
        let title: String

        if let update = bestUpdate {
            let updateScore = score(update: update, insight: insight)
            supportingSignals.append("波动窗口与 \(DateFormatting.shortDate.string(from: update.date)) 的产品更新接近。")
            supportingSignals.append("更新模块：\(update.module)，目标用户：\(update.targetUser)，预期指标：\(update.expectedMetric)。")

            if textMatches(update.expectedMetric, insight.metric) {
                supportingSignals.append("预期指标与当前波动指标名称匹配。")
            } else {
                counterSignals.append("产品更新声明的预期指标与当前波动指标不完全一致。")
            }

            if scopeMatches(update.targetUser, insight.scope) {
                supportingSignals.append("目标用户与波动范围基本一致。")
            } else {
                counterSignals.append("目标用户与波动范围匹配度不足。")
            }

            if eventCount > 0 {
                counterSignals.append("同期还有 \(eventCount) 个运营/技术/竞品事件，归因需要排除干扰。")
            }
            for entry in nearbyKnowledgeEvents.prefix(3) {
                let timing = KnowledgeEventAxis.eventTiming(for: entry)
                supportingSignals.append("知识库事件轴参照：\(KnowledgeEventAxis.title(for: entry))（\(timing.label)）。")
                if timing.basis != .explicitLaunchDate {
                    counterSignals.append("知识库条目「\(KnowledgeEventAxis.title(for: entry))」的时间依据是\(timing.basis.label)，不能单独视为实际上线时间。")
                }
            }
            for item in nearbyReferences.prefix(3) {
                switch item.domain {
                case .competitor:
                    counterSignals.append("同期竞品舆情参照：\(item.sourceName) - \(item.title)；\(referenceTimingText(item))。")
                case .policy:
                    counterSignals.append("同期政策/监管参照：\(item.sourceName) - \(item.title)；\(referenceTimingText(item))。")
                case .market:
                    counterSignals.append("同期市场参照：\(item.sourceName) - \(item.title)；\(referenceTimingText(item))。")
                case .externalEvent:
                    counterSignals.append("同期社会/自然事件参照：\(item.sourceName) - \(item.title)；\(referenceTimingText(item))。需通过时间、地区和影响机制验证，不能机械归因。")
                case .manual:
                    counterSignals.append("同期人工参照：\(item.sourceName) - \(item.title)；\(referenceTimingText(item))。")
                }
                if !item.dateCaveat.isEmpty {
                    counterSignals.append(item.dateCaveat)
                }
            }

            evidence = updateScore >= 5 && eventCount <= 1 && nearbyReferences.count <= 1 ? .b : .c
            confidence = min(9, max(4, updateScore + 2 - eventCount - min(2, nearbyReferences.count)))
            primaryCause = "较可能与「\(update.releaseNote)」有关，但仍需用分群和护栏指标验证。"
            title = "\(insight.metric) \(insight.direction.rawValue) 与 \(update.module) 更新的关系"
            recommendedNextData.append("补充 \(update.module) 更新前后的曝光、点击、完成率或错误率")
        } else if let entry = nearbyKnowledgeEvents.first {
            let entryScore = score(knowledgeEntry: entry, insight: insight)
            let timing = KnowledgeEventAxis.eventTiming(for: entry)
            supportingSignals.append("波动窗口附近命中知识库产品事件：\(KnowledgeEventAxis.title(for: entry))。")
            supportingSignals.append("知识库场景：\(entry.scenario)，时间依据：\(timing.label)。")
            if timing.basis != .explicitLaunchDate {
                counterSignals.append(timing.basis.caveat)
            }
            if entryScore >= 5 {
                supportingSignals.append("知识库条目的场景、标题或说明与当前波动指标存在文本匹配。")
            } else {
                counterSignals.append("知识库条目未明确声明目标指标，只能作为产品事件线索。")
            }
            if eventCount > 0 {
                counterSignals.append("同期还有 \(eventCount) 个运营/技术/竞品事件，归因需要排除干扰。")
            }
            for item in nearbyReferences.prefix(3) {
                counterSignals.append("同期外部参照：[\(item.domain.label)] \(item.sourceName) - \(item.title)；\(referenceTimingText(item))。")
                if !item.dateCaveat.isEmpty {
                    counterSignals.append(item.dateCaveat)
                }
            }
            let timingPenalty = timing.basis == .explicitLaunchDate ? 0 : 2
            evidence = entryScore >= 5 && eventCount <= 1 && timing.basis == .explicitLaunchDate ? .c : .d
            confidence = min(7, max(3, entryScore + 1 - eventCount - min(2, nearbyReferences.count) - timingPenalty))
            primaryCause = "可能与知识库事件轴中的「\(KnowledgeEventAxis.title(for: entry))」有关，但该线索来自文档沉淀，仍需用实际发布记录、分群和护栏指标验证。"
            title = "\(insight.metric) \(insight.direction.rawValue) 与知识库产品事件的关系"
            recommendedNextData.append("补充或校准知识库条目的实际上线日期、目标用户和预期指标")
        } else if let event = nearbyEvents.first {
            supportingSignals.append("波动窗口附近存在 \(event.eventType)：\(event.title)。")
            evidence = .c
            confidence = 4
            primaryCause = "可能受上下文事件「\(event.title)」影响，尚不能归因为产品更新。"
            title = "\(insight.metric) \(insight.direction.rawValue) 与上下文事件的关系"
        } else if let reference = nearbyReferences.first {
            supportingSignals.append("波动窗口附近存在外部参照：[\(reference.domain.label)] \(reference.title)；\(referenceTimingText(reference))。")
            if !reference.dateCaveat.isEmpty {
                counterSignals.append(reference.dateCaveat)
            }
            if reference.resolvedDateBasis == .collectedAt {
                evidence = .d
                confidence = 2
                primaryCause = "外部参照「\(reference.title)」只有采集时间，不能作为同期事件归因依据，只能作为待复核线索。"
            } else if reference.resolvedDateBasis == .publishedAt {
                evidence = .c
                confidence = 3
                primaryCause = "外部参照「\(reference.title)」发布时间接近波动窗口，但尚未确认真实事件发生时间，只能作为弱相关候选因素。"
            } else {
                evidence = .c
                confidence = 4
                primaryCause = "可能受竞品、政策或市场外部因素「\(reference.title)」影响，尚不能归因为产品更新。"
            }
            title = "\(insight.metric) \(insight.direction.rawValue) 与外部参照的关系"
        } else {
            evidence = .d
            confidence = 2
            primaryCause = "缺少可匹配的产品更新或上下文事件，只能作为待验证异常处理。"
            title = "\(insight.metric) \(insight.direction.rawValue) 的待验证异常"
            counterSignals.append("没有发现时间接近的产品更新或上下文事件。")
        }

        if referenceItems.isEmpty {
            recommendedNextData.append("补充竞品舆情、政策监管和市场参照数据源")
        }

        let matchedMemories = correctionMemories
            .filter { $0.appliesToFuture && memoryMatches(insight, memory: $0) }
            .sorted { $0.updatedAt > $1.updatedAt }
        if let memory = matchedMemories.first {
            primaryCause += " 历史纠偏记忆提醒：\(memory.summaryText)"
            supportingSignals.append("已命中历史纠偏记忆：\(memory.summaryText)")
            recommendedNextData.append("按历史纠偏记忆复核：\(memory.reusableRule)")
            confidence = max(confidence, 5)
            if evidence == .d {
                evidence = .c
            }
        }
        for memory in matchedMemories.dropFirst().prefix(2) {
            counterSignals.append("其他相关纠偏记忆：\(memory.summaryText)")
        }

        return AttributionFinding(
            id: UUID(),
            title: title,
            evidenceLevel: evidence,
            confidence: confidence,
            relatedMetric: insight.metric,
            relatedScope: insight.scope,
            primaryCause: primaryCause,
            supportingSignals: supportingSignals,
            counterSignals: counterSignals,
            recommendedNextData: recommendedNextData.uniqued()
        )
    }

    private static func buildTrendContextFindings(
        pack: DataPack,
        contextSignals: [AnalysisContextSignal],
        maxCount: Int
    ) -> [AttributionFinding] {
        guard maxCount > 0 else { return [] }

        let trendRows = pack.importedReports.flatMap { report in
            report.trendSummary.metricTrends.map { trend in
                (report: report, trend: trend)
            }
        }
        .filter { $0.trend.direction != .flat }
        .sorted { trendImpactScore($0.trend) > trendImpactScore($1.trend) }

        var findings: [AttributionFinding] = []
        var seenMetrics = Set<String>()
        for row in trendRows {
            let metricKey = "\(row.report.fileName.normalizedKey)|\(row.trend.metricName.normalizedKey)"
            guard seenMetrics.insert(metricKey).inserted else { continue }

            let directlyRelated = AnalysisContextSynthesizer.topSignals(
                relatedTo: row.trend.metricName,
                in: contextSignals,
                includingTableTrend: false,
                limit: 5
            )
            let contextualFallback = Array(contextSignals
                .filter { signal in
                    switch signal.domain {
                    case .knowledge, .competitor, .policy, .market, .externalEvent, .manual, .correction, .timeline:
                        return !directlyRelated.contains(where: { $0.id == signal.id })
                    case .tableTrend, .sourceCoverage:
                        return false
                    }
                }
                .sorted { $0.strength > $1.strength }
                .prefix(directlyRelated.isEmpty ? 3 : 1))
            let relatedSignals = Array((directlyRelated + contextualFallback).prefix(6))
            let signalLines = relatedSignals.map { AnalysisContextSynthesizer.compactLine(for: $0) }
            let relatedMetricLinks = metricLinkEvidenceLines(for: row.trend.metricName, reportID: row.report.id, pack: pack)

            var supportingSignals = [
                "表格趋势事实：\(trendFactText(row.trend, report: row.report))"
            ]
            supportingSignals.append(contentsOf: signalLines)
            supportingSignals.append(contentsOf: relatedMetricLinks.lines)

            var counterSignals: [String] = []
            if row.report.semanticStatus == .needsReview || row.report.semanticStatus == .inProgress {
                counterSignals.append("「\(row.report.fileName)」的报表业务说明置信不足，该趋势只能作为低置信线索。")
            } else if row.report.semanticStatus == .autoInferred {
                counterSignals.append("「\(row.report.fileName)」的报表说明由系统自动识别，语义置信度 \(Int(row.report.semanticConfidence * 100))%；如有特殊口径仍需人工校准。")
            }
            if !row.report.parseWarnings.isEmpty {
                counterSignals.append("表格解析/识别提醒：\(row.report.parseWarnings.prefix(2).joined(separator: "；"))")
            }
            let hasExternalSignal = relatedSignals.contains { [.competitor, .policy, .market, .externalEvent, .manual].contains($0.domain) }
            if !hasExternalSignal {
                counterSignals.append("暂未命中可直接解释该指标的竞品、舆情、政策或市场参照，不能把趋势直接归因为外部因素。")
            }
            if !relatedSignals.contains(where: { $0.domain == .knowledge }) {
                counterSignals.append("暂未命中明确对应的知识库产品事件，需要核对 Confluence 记录中的上线时间和影响范围。")
            }

            let hasDirectContextMatch = !directlyRelated.isEmpty
            let semanticUsable = row.report.semanticStatus == .confirmed || row.report.semanticStatus == .autoInferred
            let evidence: EvidenceLevel
            if relatedMetricLinks.bestEvidence == .b && semanticUsable {
                evidence = .b
            } else if (hasDirectContextMatch || relatedMetricLinks.bestEvidence == .c) && semanticUsable {
                evidence = .c
            } else {
                evidence = .d
            }
            let confidence = min(
                7,
                max(
                    2,
                    2 + directlyRelated.count + (hasDirectContextMatch ? 1 : 0) + relatedMetricLinks.confidenceBonus + (row.report.semanticStatus == .confirmed ? 1 : row.report.semanticStatus == .autoInferred ? 0 : -1) - min(2, row.report.parseWarnings.count)
                )
            )
            let primaryCause: String
            if relatedSignals.isEmpty {
                primaryCause = "\(row.trend.metricName) 已出现明确表格趋势，但当前没有足够的知识库或外部参照解释原因；本条应先作为待验证异常/机会线索。"
            } else if !hasDirectContextMatch {
                let domains = relatedSignals.map(\.domain.label).uniqued().joined(separator: "、")
                primaryCause = "\(row.trend.metricName) 已出现明确表格趋势；当前只补充了 \(domains) 的广义上下文，还没有命中该指标的直接解释信号，因此只能作为干扰因素和排查方向。"
            } else {
                let domains = directlyRelated.map(\.domain.label).uniqued().joined(separator: "、")
                primaryCause = "\(row.trend.metricName) 的表格趋势已与 \(domains) 信号形成相关性，但这些信号仍是上下文证据；最终原因需要用分群、漏斗上下游和上线时间进一步验证。"
            }

            let nextData = [
                "确认 \(row.report.fileName) 中 \(row.trend.metricName) 的业务口径、统计周期和去重方式",
                "按渠道、平台、用户类型拆解 \(row.trend.metricName)",
                "补充该指标上一环节和下一环节的漏斗数据",
                "刷新并核对竞品舆情、政策监管和市场参照数据源"
            ]

            findings.append(AttributionFinding(
                id: UUID(),
                title: "\(row.trend.metricName) \(row.trend.direction.rawValue) 的多源上下文观察",
                evidenceLevel: evidence,
                confidence: confidence,
                relatedMetric: row.trend.metricName,
                relatedScope: row.report.fileName,
                primaryCause: primaryCause,
                supportingSignals: supportingSignals.uniqued(),
                counterSignals: counterSignals.uniqued(),
                recommendedNextData: nextData
            ))

            if findings.count >= maxCount {
                break
            }
        }
        return findings
    }

    private static func buildOpportunities(
        from insights: [MetricInsight],
        findings: [AttributionFinding],
        pack: DataPack
    ) -> [ProductOpportunity] {
        var opportunities = zip(insights, findings).map { insight, finding in
            let isNegative = insight.direction == .down
            let impact = min(10, max(3, Int(abs(insight.percentChange) * 30)))
            let urgency = isNegative ? min(10, max(5, impact + 1)) : min(8, max(3, impact - 1))
            let confidence = max(2, finding.confidence)
            let effort = effortEstimate(for: finding, pack: pack)
            let risk = isNegative ? 4 : 5
            let title = isNegative
                ? "修复 \(insight.scope) 的 \(insight.metric) 下滑"
                : "放大 \(insight.scope) 的 \(insight.metric) 提升"

            return ProductOpportunity(
                id: UUID(),
                title: title,
                problem: "\(insight.metric) 在 \(insight.scope) 出现 \(insight.formattedChange) 的\(insight.direction.rawValue)。",
                affectedUsers: insight.scope,
                expectedImpact: impact,
                confidence: confidence,
                urgency: urgency,
                effort: effort,
                risk: risk,
                strategicFit: 7
            )
        }

        if insights.isEmpty {
            opportunities.append(contentsOf: findings.prefix(5).map { finding in
                let isNegative = finding.title.contains("下降") || finding.primaryCause.contains("下滑")
                let title = isNegative
                    ? "排查 \(finding.relatedMetric) 下滑"
                    : "验证 \(finding.relatedMetric) 提升是否可放大"
                return ProductOpportunity(
                    id: UUID(),
                    title: title,
                    problem: finding.primaryCause,
                    affectedUsers: finding.relatedScope,
                    expectedImpact: max(3, min(8, finding.confidence + 1)),
                    confidence: max(2, finding.confidence),
                    urgency: isNegative ? 7 : 5,
                    effort: finding.evidenceLevel == .d ? 4 : 6,
                    risk: finding.evidenceLevel == .d ? 6 : 4,
                    strategicFit: 6
                )
            })
        }

        return opportunities
        .sorted { $0.score > $1.score }
    }

    private static func buildSummary(
        insights: [MetricInsight],
        findings: [AttributionFinding],
        opportunities: [ProductOpportunity],
        pack: DataPack,
        contextSignals: [AnalysisContextSignal]
    ) -> String {
        guard !insights.isEmpty else {
            if pack.importedReports.contains(where: { !$0.trendSummary.isEmpty }) {
                let trendCount = pack.importedReports.reduce(0) { $0 + $1.trendSummary.metricTrends.count }
                let metricLinkCount = currentTask(in: pack)?.businessLinkProfile.metricLinks.filter { $0.confirmationStatus != .rejected }.count ?? 0
                let externalCount = contextSignals.filter { [.competitor, .policy, .market, .externalEvent, .manual].contains($0.domain) }.count
                let knowledgeCount = contextSignals.filter { $0.domain == .knowledge }.count
                let reliableFindings = findings.filter { $0.evidenceLevel == .c || $0.evidenceLevel == .b || $0.evidenceLevel == .a }.count
                let linkText = metricLinkCount > 0 ? "，并识别 \(metricLinkCount) 条指标级多表联动" : ""
                return "本轮基于 \(pack.importedReports.count) 张报表识别 \(trendCount) 个趋势点\(linkText)，并结合 \(knowledgeCount) 条知识库信号、\(externalCount) 条竞品/舆情/政策/市场/社会自然事件参照形成多源观察；其中 \(reliableFindings) 条达到 C 级以上相关性证据，仍需确认报表口径和关键分群后再定最终方案。"
            }
            return "本轮暂无可分析的数据趋势。"
        }

        let highCount = insights.filter { $0.severity == .high }.count
        let reliableCount = findings.filter { $0.evidenceLevel == .a || $0.evidenceLevel == .b }.count
        let top = opportunities.first?.title ?? "补充关键数据"
        let contextCount = contextSignals.filter { $0.domain != .tableTrend && $0.domain != .sourceCoverage }.count
        let metricLinkCount = currentTask(in: pack)?.businessLinkProfile.metricLinks.filter { $0.confirmationStatus != .rejected }.count ?? 0
        let linkText = metricLinkCount > 0 ? "，并纳入 \(metricLinkCount) 条指标级联动" : ""
        return "本轮检测到 \(insights.count) 个显著指标波动，其中 \(highCount) 个为高强度波动；已结合 \(contextCount) 条知识库、竞品舆情、政策/市场和纠偏信号\(linkText)，\(reliableCount) 条归因达到 B 级以上证据。建议优先处理「\(top)」。"
    }

    private static func metricLinkEvidenceLines(
        for metric: String,
        reportID: UUID,
        pack: DataPack
    ) -> (lines: [String], bestEvidence: EvidenceLevel, confidenceBonus: Int) {
        guard let task = currentTask(in: pack) else { return ([], .d, 0) }
        let reportNames = Dictionary(uniqueKeysWithValues: pack.importedReports.map { ($0.id, $0.displayName) })
        let metricKey = metric.normalizedKey
        let links = task.businessLinkProfile.metricLinks
            .filter { $0.confirmationStatus != .rejected }
            .filter { link in
                let sourceMatched = link.sourceReportID == reportID && (link.sourceMetric.normalizedKey.contains(metricKey) || metricKey.contains(link.sourceMetric.normalizedKey))
                let targetMatched = link.targetReportID == reportID && (link.targetMetric.normalizedKey.contains(metricKey) || metricKey.contains(link.targetMetric.normalizedKey))
                return sourceMatched || targetMatched
            }
            .sorted { $0.confidence > $1.confidence }
            .prefix(4)
        guard !links.isEmpty else { return ([], .d, 0) }

        let lines = links.map { link in
            let source = reportNames[link.sourceReportID] ?? "上游表"
            let target = reportNames[link.targetReportID] ?? "下游表"
            return "指标级联动：\(source).\(link.sourceMetric) → \(target).\(link.targetMetric)，\(link.relationType.label)，\(link.directionAlignment)，证据\(link.evidenceLevel.rawValue)，置信度 \(Int(link.confidence * 100))%。"
        }
        let best = links.contains(where: { $0.evidenceLevel == .b }) ? EvidenceLevel.b : (links.contains(where: { $0.evidenceLevel == .c }) ? .c : .d)
        let bonus = links.contains(where: { $0.confidence >= 0.72 }) ? 2 : 1
        return (Array(lines), best, bonus)
    }

    private static func trendImpactScore(_ trend: ReportMetricTrend) -> Double {
        if let percentChange = trend.percentChange {
            return abs(percentChange) * 100 + min(abs(trend.delta), 1_000) / 1_000
        }
        return min(abs(trend.delta), 10_000) / 1_000
    }

    private static func trendFactText(_ trend: ReportMetricTrend, report: ImportedReport) -> String {
        if let comparison = trend.primaryComparison {
            let percentText = comparison.percentChange
                .flatMap { DateFormatting.percent.string(from: NSNumber(value: $0)) }
                ?? "无相对变化"
            let deltaText = comparison.delta >= 0 ? "+\(comparison.delta.compactText)" : comparison.delta.compactText
            let caveat = comparison.incomparabilityReason.isEmpty ? "" : "；\(comparison.incomparabilityReason)"
            return "\(report.fileName) / \(report.shape.label)：\(trend.metricName) 相邻周期候选 \(comparison.currentLabel) vs \(comparison.previousLabel)，\(comparison.previousValue.compactText) -> \(comparison.currentValue.compactText)，\(comparison.direction.rawValue) \(deltaText)（\(percentText)），证据\(comparison.evidenceLevel.rawValue)，置信度 \(Int(comparison.confidence * 100))%\(caveat)。历史模式：\(trend.historicalPattern ?? "未判断")。"
        }
        let percentText = trend.percentChange
            .flatMap { DateFormatting.percent.string(from: NSNumber(value: $0)) }
            ?? "无相对变化"
        let deltaText = trend.delta >= 0 ? "+\(trend.delta.compactText)" : trend.delta.compactText
        let windowText: String
        if let start = trend.trendStartDate, let end = trend.trendEndDate {
            let startLabel = trend.trendStartLabel ?? DateFormatting.shortDate.string(from: start)
            let endLabel = trend.trendEndLabel ?? DateFormatting.shortDate.string(from: end)
            windowText = startLabel == endLabel ? "，观察期 \(endLabel)" : "，观察期 \(startLabel) 至 \(endLabel)"
        } else {
            windowText = ""
        }
        var text = "\(report.fileName) / \(report.shape.label)：\(trend.metricName) 从 \(trend.firstValue.compactText) 到 \(trend.lastValue.compactText)，\(trend.direction.rawValue) \(deltaText)（\(percentText)），共 \(trend.pointCount) 个完整观察点\(windowText)。"
        if trend.latestPointIsPartial == true {
            let label = trend.partialLatestLabel ?? "最新周期"
            let valueText = trend.partialLatestValue.map(\.compactText) ?? "未知值"
            let reason = trend.partialLatestPointReason ?? "未完整"
            text += " \(label) 的最新值 \(valueText) 存在候选成熟口径提示：\(reason)。"
        }
        return text
    }

    private static func metricDateGaps(in metrics: [MetricPoint]) -> [String] {
        let grouped = Dictionary(grouping: metrics, by: \.metric)
        var result: [String] = []
        for (metric, values) in grouped {
            let days = Array(Set(values.map { Calendar.current.startOfDay(for: $0.date) })).sorted()
            guard days.count >= 3 else { continue }
            for pair in zip(days, days.dropFirst()) {
                let gap = Calendar.current.dateComponents([.day], from: pair.0, to: pair.1).day ?? 0
                if gap > 1 {
                    result.append("\(metric) 在 \(DateFormatting.shortDate.string(from: pair.0)) 到 \(DateFormatting.shortDate.string(from: pair.1)) 之间缺少 \(gap - 1) 天数据。")
                    break
                }
            }
        }
        return result
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func score(update: ProductUpdate, insight: MetricInsight) -> Int {
        var score = 0
        if textMatches(update.expectedMetric, insight.metric) { score += 3 }
        if textMatches(update.module, insight.metric) { score += 1 }
        if scopeMatches(update.targetUser, insight.scope) { score += 2 }
        let days = abs(Calendar.current.dateComponents([.day], from: update.date, to: insight.endDate).day ?? 30)
        if days <= 3 { score += 3 } else if days <= 7 { score += 2 } else { score += 1 }
        return score
    }

    private static func score(knowledgeEntry: KnowledgeEntry, insight: MetricInsight) -> Int {
        let text = [
            knowledgeEntry.scenario,
            knowledgeEntry.problem,
            knowledgeEntry.action,
            knowledgeEntry.result,
            knowledgeEntry.tags.joined(separator: " ")
        ]
        .joined(separator: " ")
        var score = 0
        if textMatches(text, insight.metric) { score += 3 }
        if scopeMatches(text, insight.scope) { score += 2 }
        let timing = KnowledgeEventAxis.eventTiming(for: knowledgeEntry)
        let days = abs(Calendar.current.dateComponents([.day], from: timing.date, to: insight.endDate).day ?? 60)
        if days <= 7 { score += 3 } else if days <= 14 { score += 2 } else { score += 1 }
        score += max(0, timing.basis.reliabilityScore - 2)
        if timing.basis == .documentUpdatedAt || timing.basis == .knowledgeCreatedAt {
            score = max(0, score - 2)
        }
        return score
    }

    private static func textMatches(_ lhs: String, _ rhs: String) -> Bool {
        let lhs = lhs.normalizedKey
        let rhs = rhs.normalizedKey
        return !lhs.isEmpty && !rhs.isEmpty && (lhs.contains(rhs) || rhs.contains(lhs))
    }

    private static func scopeMatches(_ lhs: String, _ rhs: String) -> Bool {
        let lhs = lhs.normalizedKey
        let rhs = rhs.normalizedKey
        if lhs.contains("全量") || rhs.contains("全量") { return true }
        return !lhs.isEmpty && !rhs.isEmpty && (lhs.contains(rhs) || rhs.contains(lhs))
    }

    private static func referenceTimingText(_ item: ExternalReferenceItem) -> String {
        "时间 \(DateFormatting.shortDate.string(from: item.displayDate))（\(item.dateBasisLabel)，置信度 \(Int(item.resolvedDateConfidence * 100))%）"
    }

    private static func memoryMatches(_ insight: MetricInsight, memory: AnalysisCorrectionMemory) -> Bool {
        let metricMatched = memory.metric.isEmpty || textMatches(memory.metric, insight.metric)
        let scopeMatched = memory.scope.isEmpty || scopeMatches(memory.scope, insight.scope)
        if metricMatched && scopeMatched { return true }

        let memoryText = [
            memory.findingTitle,
            memory.originalConclusion,
            memory.userCorrection,
            memory.revisedConclusion,
            memory.reusableRule,
            memory.tags.joined(separator: " ")
        ]
        .joined(separator: " ")
        .normalizedKey
        let insightText = "\(insight.metric) \(insight.scope)".normalizedKey
        return !memoryText.isEmpty && !insightText.isEmpty && memoryText.contains(insightText)
    }

    private static func effortEstimate(for finding: AttributionFinding, pack: DataPack) -> Int {
        if finding.evidenceLevel == .d { return 3 }
        if finding.relatedMetric.normalizedKey.contains("error") || finding.relatedMetric.contains("错误") { return 4 }
        return 6
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
