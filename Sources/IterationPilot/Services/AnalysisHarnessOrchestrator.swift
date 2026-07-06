import Foundation

struct AnalysisHarnessOrchestrator {
    func run(
        userQuery: String,
        reports: [ImportedReport],
        workspace: ProductWorkspace? = nil,
        pack: DataPack? = nil,
        task: AnalysisTask? = nil,
        session: AnalysisSession? = nil,
        sourcePolicy: AnalysisContextSourcePolicy,
        settings: AISettings,
        onProgress: ((_ event: AuditEvent) async -> Void)? = nil,
        onReportDelta: ((_ accumulatedText: String) async -> Void)? = nil
    ) async throws -> AnalysisHarnessRun {
        let startedAt = Date()
        var audit: [AuditEvent] = []
        func elapsed() -> Int { Int(Date().timeIntervalSince(startedAt) * 1000) }
        func recordEvent(_ event: AuditEvent) async {
            audit.append(event)
            await onProgress?(event)
        }

        await recordEvent(AuditEvent(stage: .manifestBuilding, status: .started, summary: "开始构建表画像。"))
        let manifests = TableManifestBuilder.build(reports: reports)
        await recordEvent(AuditEvent(stage: .manifestBuilding, status: .completed, summary: "已构建 \(manifests.count) 张表画像。", durationMilliseconds: elapsed()))
        await recordEvent(AuditEvent(stage: .dataContractValidation, status: .started, summary: "开始执行数据契约软校验。"))
        let dataContractValidation = DataContractValidator.validate(manifests: manifests)
        await recordEvent(AuditEvent(
            stage: .dataContractValidation,
            status: dataContractValidation.issues.contains(where: { $0.severity.blocksOutput }) ? .failed : (dataContractValidation.issues.isEmpty ? .completed : .warning),
            summary: "数据契约校验完成：\(dataContractValidation.summary.status.label)，问题 \(dataContractValidation.issues.count) 个。",
            details: [
                "contractVersionID": dataContractValidation.summary.contractVersionID,
                "thresholds": "confirm<\(dataContractValidation.summary.confirmationThreshold), pass>=\(dataContractValidation.summary.warningThreshold)"
            ],
            durationMilliseconds: elapsed()
        ))
        await recordEvent(AuditEvent(stage: .tableUnderstanding, status: .started, summary: "开始生成标准事实表。"))
        let normalizedFactTables = NormalizedFactTableBuilder.build(
            reports: reports,
            manifests: manifests,
            templates: workspace?.analysisTableUnderstandingTemplates ?? []
        )
        let factRowCount = normalizedFactTables.reduce(0) { $0 + $1.rows.count }
        await recordEvent(AuditEvent(
            stage: .tableUnderstanding,
            status: normalizedFactTables.isEmpty ? .warning : .completed,
            summary: "标准事实表生成完成：\(normalizedFactTables.count) 张，\(factRowCount) 行事实。",
            details: [
                "tables": normalizedFactTables.map { "\($0.tableName): \($0.shape.label), \($0.rows.count) 行" }.joined(separator: "；")
            ],
            durationMilliseconds: elapsed()
        ))
        let tableUnderstandingIssues = TableUnderstandingConfidenceGate.validate(
            userQuery: userQuery,
            manifests: manifests,
            factTables: normalizedFactTables
        )

        guard !manifests.isEmpty else {
            let issue = ValidationIssue(
                severity: .fatal,
                code: .insufficientData,
                stage: .manifestBuilding,
                message: "当前任务没有可分析表。"
            )
            let blocked = BlockedAnalysisOutput(
                title: "缺少选表",
                reason: issue.message,
                issues: [issue],
                nextSteps: ["在分析资料中加入至少 1 张表后重新发送问题。"]
            )
            await onReportDelta?(blocked.markdown)
            return AnalysisHarnessRun(
                finishedAt: Date(),
                status: .blocked,
                userQuery: userQuery,
                tableManifest: manifests,
                normalizedFactTables: normalizedFactTables,
                analysisPlan: nil,
                verifiedResults: [],
                validationIssues: [issue],
                auditLog: audit,
                reportMarkdown: blocked.markdown,
                repairAttemptsPlan: 0,
                repairAttemptsReport: 0,
                durationMilliseconds: elapsed(),
                dataContractSummary: dataContractValidation.summary
            )
        }
        if dataContractValidation.issues.contains(where: { $0.severity.blocksOutput }) {
            let blocked = BlockedAnalysisOutput(
                title: "需要确认数据契约",
                reason: "当前选表未通过数据契约前置校验，系统不会在字段映射或结构置信度不足时输出业务数字。",
                issues: dataContractValidation.issues,
                nextSteps: ["确认表格字段、周期列、指标列和值列后重新分析。"]
            )
            await onReportDelta?(blocked.markdown)
            return AnalysisHarnessRun(
                finishedAt: Date(),
                status: .blocked,
                userQuery: userQuery,
                tableManifest: manifests,
                normalizedFactTables: normalizedFactTables,
                analysisPlan: nil,
                verifiedResults: [],
                validationIssues: dataContractValidation.issues,
                auditLog: audit,
                reportMarkdown: blocked.markdown,
                repairAttemptsPlan: 0,
                repairAttemptsReport: 0,
                durationMilliseconds: elapsed(),
                dataContractSummary: dataContractValidation.summary
            )
        }
        if tableUnderstandingIssues.contains(where: { $0.severity.blocksOutput }) {
            let blocked = BlockedAnalysisOutput(
                title: "需要确认表格结构",
                reason: "当前表格结构置信度不足，系统不会在未确认周期列、指标列、数值列时输出业务数字。",
                issues: tableUnderstandingIssues,
                nextSteps: [
                    "确认周期列、指标列、数值列和周归属规则。",
                    "确认后可保存为分析模板，下次同结构表会自动复用并继续校验。"
                ]
            )
            await onReportDelta?(blocked.markdown)
            return AnalysisHarnessRun(
                finishedAt: Date(),
                status: .blocked,
                userQuery: userQuery,
                tableManifest: manifests,
                normalizedFactTables: normalizedFactTables,
                analysisPlan: nil,
                verifiedResults: [],
                validationIssues: tableUnderstandingIssues,
                auditLog: audit,
                reportMarkdown: blocked.markdown,
                repairAttemptsPlan: 0,
                repairAttemptsReport: 0,
                durationMilliseconds: elapsed(),
                dataContractSummary: dataContractValidation.summary
            )
        }

        await recordEvent(AuditEvent(stage: .intentParsing, status: .started, summary: "开始解析用户分析意图。"))
        let analysisIntent: NormalizedFactMetricAnalyzer.AnalysisIntent
        do {
            analysisIntent = try await NormalizedFactMetricAnalyzer.AnalysisIntentParser().parse(
                userQuery: userQuery,
                factTables: normalizedFactTables,
                settings: settings
            )
        } catch {
            let message = error.localizedDescription
            let issue = ValidationIssue(
                severity: .fatal,
                code: .aiIntentParsingFailed,
                stage: .intentParsing,
                message: message,
                expected: "AI 返回可映射到当前指标目录的主请求指标和公式依赖。",
                actual: "意图解析未完成。",
                fixHint: "检查 AI 设置/API Key，或把问题中的目标指标写得更明确后重试。"
            )
            await recordEvent(AuditEvent(
                stage: .intentParsing,
                status: .failed,
                summary: "意图解析失败：\(message)",
                durationMilliseconds: elapsed()
            ))
            let issues = dataContractValidation.issues + tableUnderstandingIssues + [issue]
            let blocked = BlockedAnalysisOutput(
                title: "需要 AI 解析分析目标",
                reason: message,
                issues: [issue],
                nextSteps: [
                    "在 AI 设置中确认 API Key、模型和 endpoint 可用。",
                    "重新发送问题，让 AI 先明确主请求指标、依赖指标和公式口径。",
                    "如果 AI 返回的指标名不在表格目录中，请补充指标映射或改用表内指标名称。"
                ]
            )
            await onReportDelta?(blocked.markdown)
            return AnalysisHarnessRun(
                finishedAt: Date(),
                status: .blocked,
                userQuery: userQuery,
                tableManifest: manifests,
                normalizedFactTables: normalizedFactTables,
                analysisPlan: nil,
                verifiedResults: [],
                validationIssues: issues,
                auditLog: audit,
                reportMarkdown: blocked.markdown,
                repairAttemptsPlan: 0,
                repairAttemptsReport: 0,
                durationMilliseconds: elapsed(),
                dataContractSummary: dataContractValidation.summary
            )
        }
        await recordEvent(AuditEvent(
            stage: .intentParsing,
            status: analysisIntent.confidence < 0.75 ? .warning : .completed,
            summary: "意图解析完成：主请求 \(analysisIntent.requestedMetrics.joined(separator: "、"))；依赖 \(analysisIntent.supportingMetrics.joined(separator: "、"))；来源 \(analysisIntent.source.rawValue)。",
            details: [
                "confidence": String(format: "%.2f", analysisIntent.confidence),
                "aggregationMode": analysisIntent.aggregationMode,
                "wantsGrowthRate": "\(analysisIntent.wantsGrowthRate)",
                "notes": analysisIntent.notes.joined(separator: "；")
            ],
            durationMilliseconds: elapsed()
        ))

        let factAnalysis = NormalizedFactMetricAnalyzer.analyze(
            userQuery: userQuery,
            factTables: normalizedFactTables,
            intent: analysisIntent
        )
        await recordEvent(AuditEvent(stage: .planGeneration, status: .started, summary: factAnalysis == nil ? "开始生成分析计划。" : "标准事实表可直接回答，使用本地事实表计划。"))
        var plan: AnalysisPlan
        if let factAnalysis {
            plan = factAnalysis.plan
        } else {
            plan = try await AnalysisPlannerClient().generatePlan(userQuery: userQuery, manifests: manifests, settings: settings)
        }
        await recordEvent(AuditEvent(stage: .planGeneration, status: .completed, summary: "已生成分析计划：\(plan.metrics.count) 个指标；来源 \(plan.createdBy)。", durationMilliseconds: elapsed()))

        await recordEvent(AuditEvent(stage: .planValidation, status: .started, summary: "开始校验分析计划。"))
        var planIssues = PlanValidator.validate(plan: plan, manifests: manifests)
        await recordEvent(AuditEvent(
            stage: .planValidation,
            status: planIssues.contains(where: { $0.severity.blocksOutput }) ? .warning : .completed,
            summary: "计划校验完成：\(planIssues.count) 个问题。",
            durationMilliseconds: elapsed()
        ))
        var planRepairAttempts = 0
        if planIssues.contains(where: { $0.severity.blocksOutput }) {
            await recordEvent(AuditEvent(stage: .planRepair, status: .started, summary: "计划未通过，开始本地修复。"))
            let repaired = PlanRepairLoop.repair(plan: plan, issues: planIssues, manifests: manifests, userQuery: userQuery)
            plan = repaired.plan
            planRepairAttempts = repaired.attempts
            planIssues = repaired.issues
            await recordEvent(AuditEvent(
                stage: .planRepair,
                status: planIssues.contains(where: { $0.severity.blocksOutput }) ? .failed : .completed,
                summary: "计划修复完成：\(planRepairAttempts) 次；剩余 \(planIssues.count) 个问题。",
                durationMilliseconds: elapsed()
            ))
        }
        if planIssues.contains(where: { $0.severity.blocksOutput }) {
            let blocked = BlockedAnalysisOutput(
                title: "分析计划被阻断",
                reason: "计划引用了不存在字段、不安全 join 或不可执行口径。",
                issues: planIssues,
                nextSteps: ["检查选表、字段名和指标口径。", "如果需要跨表分析，请补充可验证主键或关系说明。"]
            )
            await onReportDelta?(blocked.markdown)
            return AnalysisHarnessRun(
                finishedAt: Date(),
                status: .blocked,
                userQuery: userQuery,
                tableManifest: manifests,
                normalizedFactTables: normalizedFactTables,
                analysisPlan: plan,
                verifiedResults: [],
                validationIssues: planIssues,
                auditLog: audit,
                reportMarkdown: blocked.markdown,
                repairAttemptsPlan: planRepairAttempts,
                repairAttemptsReport: 0,
                durationMilliseconds: elapsed(),
                dataContractSummary: dataContractValidation.summary
            )
        }

        await recordEvent(AuditEvent(stage: .metricExecution, status: .started, summary: "开始执行本地指标。"))
        let results = factAnalysis?.results ?? MetricExecutor.execute(plan: plan, reports: reports, manifests: manifests)
        await recordEvent(AuditEvent(stage: .metricExecution, status: .completed, summary: "已产出 \(results.count) 个本地指标结果。", durationMilliseconds: elapsed()))

        await recordEvent(AuditEvent(stage: .resultValidation, status: .started, summary: "开始校验计算结果。"))
        let resultIssues = ResultValidator.validate(results: results, plan: plan, manifests: manifests)
        await recordEvent(AuditEvent(
            stage: .resultValidation,
            status: resultIssues.contains(where: { $0.severity.blocksOutput }) ? .failed : (resultIssues.isEmpty ? .completed : .warning),
            summary: "结果校验完成：\(resultIssues.count) 个问题。",
            durationMilliseconds: elapsed()
        ))
        let factIssues = factAnalysis?.issues ?? []
        let allPreReportIssues = dataContractValidation.issues + tableUnderstandingIssues + planIssues + factIssues + resultIssues
        if resultIssues.contains(where: { $0.severity.blocksOutput }) {
            let blocked = BlockedAnalysisOutput(
                title: "需要重新读取表格结构",
                reason: "当前表格没有生成可用于回答问题的已校验指标。",
                issues: allPreReportIssues,
                nextSteps: [
                    "重新读取并分析当前表。",
                    "如果表格是合并周期或指标/值混合结构，请确认周期列、指标列和值列。",
                    "如果指标名称与问题中的叫法不同，请确认指标映射后重试。"
                ]
            )
            await onReportDelta?(blocked.markdown)
            return AnalysisHarnessRun(
                finishedAt: Date(),
                status: .blocked,
                userQuery: userQuery,
                tableManifest: manifests,
                normalizedFactTables: normalizedFactTables,
                analysisPlan: plan,
                verifiedResults: results,
                validationIssues: allPreReportIssues,
                auditLog: audit,
                reportMarkdown: blocked.markdown,
                repairAttemptsPlan: planRepairAttempts,
                repairAttemptsReport: 0,
                durationMilliseconds: elapsed(),
                dataContractSummary: dataContractValidation.summary
            )
        }

        var investigationRun: InvestigationRun?
        if AnalysisHarnessRouter.userMessageLooksLikeContextEvidenceQuestion(userQuery) {
            await recordEvent(AuditEvent(stage: .rootCauseInvestigation, status: .started, summary: "开始执行受控根因候选调查。"))
            investigationRun = RootCauseInvestigator.investigate(
                userQuery: userQuery,
                results: results,
                factTables: normalizedFactTables
            )
            await recordEvent(AuditEvent(
                stage: .rootCauseInvestigation,
                status: investigationRun == nil ? .warning : .completed,
                summary: investigationRun?.summary ?? "未产出可验证贡献分解；不会输出因果定论。",
                durationMilliseconds: elapsed()
            ))
        }

        var contextEvidenceManifest: ContextEvidenceManifest?
        if sourcePolicy.includeInternalKnowledge || sourcePolicy.includeExternalReferences {
            await recordEvent(AuditEvent(stage: .contextEvidenceBuilding, status: .started, summary: "开始构建本轮资料证据；资料只进入解释层，不参与本地指标计算。"))
            if let workspace, let pack, let session {
                contextEvidenceManifest = ContextEvidenceManifestBuilder.build(
                    userQuery: userQuery,
                    workspace: workspace,
                    pack: pack,
                    task: task,
                    session: session,
                    sourcePolicy: sourcePolicy
                )
            } else {
                contextEvidenceManifest = ContextEvidenceManifest(
                    sourcePolicy: sourcePolicy,
                    items: [],
                    warnings: ["本轮启用了“\(sourcePolicy.label)”，但缺少 workspace/session 快照，无法构建资料证据。"]
                )
            }
            let evidenceCount = contextEvidenceManifest?.items.count ?? 0
            let warningCount = contextEvidenceManifest?.warnings.count ?? 0
            await recordEvent(AuditEvent(
                stage: .contextEvidenceBuilding,
                status: warningCount > 0 ? .warning : .completed,
                summary: "资料证据构建完成：\(evidenceCount) 条；警告 \(warningCount) 条。",
                durationMilliseconds: elapsed()
            ))
            await recordEvent(AuditEvent(
                stage: .contextEvidenceValidation,
                status: warningCount > 0 ? .warning : .completed,
                summary: "已确认非表格资料只作为引用证据，不参与本地表格指标计算。",
                durationMilliseconds: elapsed()
            ))
        }

        await recordEvent(AuditEvent(stage: .reportGeneration, status: .started, summary: "开始生成解释报告。"))
        var report = await HarnessReportGenerator().generate(
            userQuery: userQuery,
            sourcePolicy: sourcePolicy,
            plan: plan,
            manifests: manifests,
            contextEvidence: contextEvidenceManifest,
            results: results,
            issues: allPreReportIssues,
            settings: settings,
            onDelta: nil
        )
        await recordEvent(AuditEvent(stage: .reportGeneration, status: .completed, summary: "解释报告已生成。", durationMilliseconds: elapsed()))

        await recordEvent(AuditEvent(stage: .reportValidation, status: .started, summary: "开始校验解释报告。"))
        var reportIssues = ReportValidator.validate(
            report: report,
            verifiedResults: results,
            contextEvidence: contextEvidenceManifest,
            issues: allPreReportIssues
        )
        var reportRepairAttempts = 0
        var reportDecision = ValidationDecisionEngine.decision(for: reportIssues)
        if reportDecision.shouldAttemptRepair {
            reportRepairAttempts = 1
            let locallyRepairedReport = AnalysisOutputRepairer.repair(
                report,
                contextEvidence: contextEvidenceManifest,
                issues: reportIssues
            )
            let locallyRepairedIssues = ReportValidator.validate(
                report: locallyRepairedReport,
                verifiedResults: results,
                contextEvidence: contextEvidenceManifest,
                issues: allPreReportIssues
            )
            let locallyRepairedDecision = ValidationDecisionEngine.decision(for: locallyRepairedIssues)
            if !locallyRepairedDecision.blocksFinalOutput {
                report = locallyRepairedReport
                reportIssues = locallyRepairedIssues
                reportDecision = locallyRepairedDecision
            } else {
                let combinedReportIssues: [ValidationIssue] = allPreReportIssues + reportIssues
                report = ReportValidator.repair(
                    userQuery: userQuery,
                    sourcePolicy: sourcePolicy,
                    plan: plan,
                    manifests: manifests,
                    contextEvidence: contextEvidenceManifest,
                    results: results,
                    issues: combinedReportIssues
                )
                reportIssues = ReportValidator.validate(
                    report: report,
                    verifiedResults: results,
                    contextEvidence: contextEvidenceManifest,
                    issues: allPreReportIssues
                )
                reportDecision = ValidationDecisionEngine.decision(for: reportIssues)
            }
        }
        let reportDisplaySummary = ValidationDecisionEngine.displaySummary(for: reportIssues)
        await recordEvent(AuditEvent(
            stage: .reportValidation,
            status: reportDecision.requiresUserAction ? .failed : (reportDisplaySummary.hasMainSurfaceIssues ? .warning : .completed),
            summary: "报告校验完成：\(reportDisplaySummary.summaryText)；产品状态 \(reportDecision.productStatusLabel)；修复 \(reportRepairAttempts) 次。",
            durationMilliseconds: elapsed()
        ))
        let finalIssues = allPreReportIssues + reportIssues
        let finalDecision = ValidationDecisionEngine.decision(for: finalIssues)
        let finalDisplaySummary = ValidationDecisionEngine.displaySummary(for: finalIssues)
        let status: AnalysisHarnessStatus = finalDecision.requiresUserAction
            ? .blocked
            : (finalDisplaySummary.affectsSuccessfulStatus ? .successWithWarnings : .success)
        let finalReport: String
        if status == .blocked {
            finalReport = BlockedAnalysisOutput(
                title: "解释报告被阻断",
                reason: "报告仍包含未验证数字、隐藏阻断问题、占位内容或不可执行的数据问题。",
                issues: finalIssues,
                nextSteps: ["请在分析资料中查看 Harness 审计。", "必要时缩小问题范围或补充字段。"]
            ).markdown
        } else {
            finalReport = report
        }
        await recordEvent(AuditEvent(stage: .answerNumberTracing, status: .started, summary: "开始生成回答数字血缘。"))
        let answerNumberTraceReport = AnswerNumberTracer.trace(report: finalReport, verifiedResults: results)
        await recordEvent(AuditEvent(
            stage: .answerNumberTracing,
            status: answerNumberTraceReport.hasBlockingTrace ? .warning : .completed,
            summary: "回答数字追溯完成：\(answerNumberTraceReport.traces.count) 个数字，阻断候选 \(answerNumberTraceReport.blockingTraces.count) 个。",
            durationMilliseconds: elapsed()
        ))
        await onReportDelta?(finalReport)
        await recordEvent(AuditEvent(stage: .completed, status: status == .blocked ? .failed : .completed, summary: status.label, durationMilliseconds: elapsed()))
        return AnalysisHarnessRun(
            finishedAt: Date(),
            status: status,
            userQuery: userQuery,
            tableManifest: manifests,
            normalizedFactTables: normalizedFactTables,
            contextEvidenceManifest: contextEvidenceManifest,
            analysisPlan: plan,
            verifiedResults: results,
            validationIssues: finalIssues,
            auditLog: audit,
            reportMarkdown: finalReport,
            repairAttemptsPlan: planRepairAttempts,
            repairAttemptsReport: reportRepairAttempts,
            durationMilliseconds: elapsed(),
            answerNumberTraces: answerNumberTraceReport.traces,
            dataContractSummary: dataContractValidation.summary,
            investigationRun: investigationRun
        )
    }
}
