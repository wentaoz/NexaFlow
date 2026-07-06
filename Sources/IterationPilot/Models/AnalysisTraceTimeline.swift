import Foundation

enum AnalysisTraceTimelineSource: String, Codable, CaseIterable, Identifiable, Hashable {
    case conversation
    case coverage
    case harness
    case notebook
    case collection
    case aiJob
    case answerTrace

    var id: String { rawValue }

    var label: String {
        switch self {
        case .conversation: return "对话"
        case .coverage: return "读取范围"
        case .harness: return "Harness"
        case .notebook: return "Notebook"
        case .collection: return "采集"
        case .aiJob: return "AI 任务"
        case .answerTrace: return "数字血缘"
        }
    }
}

enum AnalysisTraceTimelineStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case waiting
    case running
    case completed
    case warning
    case failed
    case info

    var id: String { rawValue }

    var label: String {
        switch self {
        case .waiting: return "等待"
        case .running: return "执行中"
        case .completed: return "完成"
        case .warning: return "需关注"
        case .failed: return "失败"
        case .info: return "记录"
        }
    }
}

struct AnalysisTraceTimelineEvent: Identifiable, Codable, Hashable {
    var id: String
    var occurredAt: Date
    var source: AnalysisTraceTimelineSource
    var status: AnalysisTraceTimelineStatus
    var title: String
    var detail: String
    var durationMilliseconds: Int?
    var metadata: [String: String]

    init(
        id: String,
        occurredAt: Date,
        source: AnalysisTraceTimelineSource,
        status: AnalysisTraceTimelineStatus,
        title: String,
        detail: String,
        durationMilliseconds: Int? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.source = source
        self.status = status
        self.title = title
        self.detail = detail
        self.durationMilliseconds = durationMilliseconds
        self.metadata = metadata
    }
}

enum AnalysisTraceTimelineBuilder {
    static func build(
        session: AnalysisSession,
        coverageSnapshot: AnalysisCoverageSnapshot?,
        harnessEvidence: [AnalysisSessionEvidence],
        notebookRuns: [AnalysisNotebookRun],
        collectionRuns: [ExternalReferenceCollectionRun],
        jobs: [PersistentAIJob],
        limit: Int = 80
    ) -> [AnalysisTraceTimelineEvent] {
        var events: [AnalysisTraceTimelineEvent] = []
        events.append(contentsOf: conversationEvents(from: session))
        if let coverageSnapshot {
            events.append(coverageEvent(coverageSnapshot))
        }
        events.append(contentsOf: harnessEvents(from: harnessEvidence))
        events.append(contentsOf: notebookEvents(from: notebookRuns))
        events.append(contentsOf: collectionEvents(from: collectionRuns))
        events.append(contentsOf: jobEvents(from: jobs))

        let sorted = events.sorted {
            if $0.occurredAt != $1.occurredAt { return $0.occurredAt < $1.occurredAt }
            return $0.id < $1.id
        }
        guard sorted.count > limit else { return sorted }
        return Array(sorted.suffix(limit))
    }

    private static func conversationEvents(from session: AnalysisSession) -> [AnalysisTraceTimelineEvent] {
        session.messages.suffix(20).map { message in
            let isUser = message.role == .user
            return AnalysisTraceTimelineEvent(
                id: "message-\(message.id.uuidString)",
                occurredAt: message.createdAt,
                source: .conversation,
                status: message.streamingStatus == nil ? .completed : streamingStatus(message.streamingStatus?.state),
                title: isUser ? "用户提问" : messageKindTitle(message.kind),
                detail: redactedPreview(message.content, limit: isUser ? 160 : 120),
                metadata: [
                    "角色": message.role.rawValue,
                    "类型": message.kind.rawValue,
                    "证据": "\(message.evidence.count)"
                ]
            )
        }
    }

    private static func coverageEvent(_ coverage: AnalysisCoverageSnapshot) -> AnalysisTraceTimelineEvent {
        AnalysisTraceTimelineEvent(
            id: "coverage-\(coverage.id.uuidString)",
            occurredAt: coverage.createdAt,
            source: .coverage,
            status: .completed,
            title: "生成 AI 读取范围",
            detail: "读取 \(coverage.totalReports) 张表、\(coverage.totalRows) 行、\(coverage.totalColumns) 列、\(coverage.totalMetrics) 个指标。",
            metadata: [
                "上下文": coverage.contextMode?.label ?? "未记录",
                "外部证据": "\(coverage.referenceItemCount)",
                "知识库": "\(coverage.knowledgeEntryCount)",
                "限制": "\(coverage.limitations.count)"
            ]
        )
    }

    private static func harnessEvents(from evidenceItems: [AnalysisSessionEvidence]) -> [AnalysisTraceTimelineEvent] {
        evidenceItems.flatMap { evidence -> [AnalysisTraceTimelineEvent] in
            guard let run = evidence.analysisHarnessRun else {
                return [
                    AnalysisTraceTimelineEvent(
                        id: "harness-evidence-\(evidence.id.uuidString)",
                        occurredAt: Date.distantPast,
                        source: .harness,
                        status: .info,
                        title: evidence.title,
                        detail: redactedPreview(evidence.detail, limit: 180),
                        metadata: ["来源": evidence.sourceType]
                    )
                ]
            }
            var events: [AnalysisTraceTimelineEvent] = [
                AnalysisTraceTimelineEvent(
                    id: "harness-run-\(run.id.uuidString)",
                    occurredAt: run.createdAt,
                    source: .harness,
                    status: harnessStatus(run.status),
                    title: "Harness 运行",
                    detail: "本地验证 \(run.verifiedResults.count) 个结果，校验问题 \(run.validationIssues.count) 个。",
                    durationMilliseconds: run.durationMilliseconds,
                    metadata: [
                        "状态": run.status.label,
                        "计划修复": "\(run.repairAttemptsPlan)",
                        "报告修复": "\(run.repairAttemptsReport)"
                    ]
                )
            ]
            events.append(contentsOf: run.auditLog.map { event in
                AnalysisTraceTimelineEvent(
                    id: "harness-audit-\(event.id.uuidString)",
                    occurredAt: event.createdAt,
                    source: .harness,
                    status: auditStatus(event.status),
                    title: event.stage.label,
                    detail: event.summary,
                    durationMilliseconds: event.durationMilliseconds,
                    metadata: event.details
                )
            })
            if let traces = run.answerNumberTraces, !traces.isEmpty {
                events.append(answerTraceEvent(run: run, traces: traces))
            }
            return events
        }
    }

    private static func answerTraceEvent(run: AnalysisHarnessRun, traces: [AnswerNumberTrace]) -> AnalysisTraceTimelineEvent {
        let grouped = Dictionary(grouping: traces, by: \.status)
        let unresolvedCount = (grouped[.unmatched]?.count ?? 0) + (grouped[.ambiguous]?.count ?? 0)
        let matchedCount = (grouped[.matched]?.count ?? 0) + (grouped[.approximateMatched]?.count ?? 0)
        let status: AnalysisTraceTimelineStatus = unresolvedCount > 0 ? .warning : .completed
        return AnalysisTraceTimelineEvent(
            id: "answer-trace-\(run.id.uuidString)",
            occurredAt: run.finishedAt ?? run.createdAt,
            source: .answerTrace,
            status: status,
            title: "追溯回答数字",
            detail: "已追溯 \(matchedCount) 个数字，需关注 \(unresolvedCount) 个。",
            metadata: [
                "已追溯": "\(matchedCount)",
                "歧义": "\(grouped[.ambiguous]?.count ?? 0)",
                "未追溯": "\(grouped[.unmatched]?.count ?? 0)"
            ]
        )
    }

    private static func notebookEvents(from runs: [AnalysisNotebookRun]) -> [AnalysisTraceTimelineEvent] {
        runs.flatMap { run -> [AnalysisTraceTimelineEvent] in
            var events = [
                AnalysisTraceTimelineEvent(
                    id: "notebook-\(run.id.uuidString)",
                    occurredAt: run.createdAt,
                    source: .notebook,
                    status: run.failedCount > 0 ? .warning : .completed,
                    title: run.trigger,
                    detail: run.summary,
                    durationMilliseconds: run.durationMilliseconds,
                    metadata: [
                        "引擎": run.engine,
                        "成功": "\(run.successCount)",
                        "失败": "\(run.failedCount)"
                    ]
                )
            ]
            events.append(contentsOf: run.cells.prefix(10).map { cell in
                AnalysisTraceTimelineEvent(
                    id: "notebook-cell-\(cell.id.uuidString)",
                    occurredAt: cell.createdAt,
                    source: .notebook,
                    status: notebookStatus(cell.status),
                    title: cell.title.nilIfBlank ?? cell.kind.label,
                    detail: cell.errorMessage?.nilIfBlank ?? "\(cell.rowCount) 行结果",
                    durationMilliseconds: cell.durationMilliseconds,
                    metadata: [
                        "类型": cell.kind.label,
                        "列": "\(cell.columns.count)",
                        "来源表": "\(cell.sourceReportIDs.count)"
                    ]
                )
            })
            return events
        }
    }

    private static func collectionEvents(from runs: [ExternalReferenceCollectionRun]) -> [AnalysisTraceTimelineEvent] {
        runs.map { run in
            AnalysisTraceTimelineEvent(
                id: "collection-\(run.id.uuidString)",
                occurredAt: run.startedAt,
                source: .collection,
                status: collectionStatus(run.status),
                title: "外部参照采集",
                detail: "启用 \(run.enabledSourceCount) 个源，入库 \(run.insertedItemCount) 条，失败源 \(run.failedSourceCount) 个。",
                durationMilliseconds: run.endedAt.map { Int($0.timeIntervalSince(run.startedAt) * 1_000) },
                metadata: [
                    "状态": run.status.label,
                    "阶段": run.phase ?? "",
                    "原始条目": "\(run.rawItemCount)",
                    "知识条目": "\(run.knowledgeEntryCount)"
                ]
            )
        }
    }

    private static func jobEvents(from jobs: [PersistentAIJob]) -> [AnalysisTraceTimelineEvent] {
        jobs.flatMap { job -> [AnalysisTraceTimelineEvent] in
            var events = [
                AnalysisTraceTimelineEvent(
                    id: "job-\(job.id.uuidString)",
                    occurredAt: job.updatedAt,
                    source: .aiJob,
                    status: jobStatus(job.status),
                    title: job.kind.label,
                    detail: job.lastError.nilIfBlank ?? "任务 \(job.attemptCount)/\(job.maxImmediateAttempts) 次尝试，当前状态：\(job.status.label)。",
                    metadata: [
                        "目标": redactedPreview(job.targetName, limit: 80),
                        "状态": job.status.label,
                        "尝试": "\(job.attemptCount)/\(job.maxImmediateAttempts)"
                    ]
                )
            ]
            events.append(contentsOf: job.logs.suffix(12).map { log in
                AnalysisTraceTimelineEvent(
                    id: "job-log-\(job.id.uuidString)-\(log.id.uuidString)",
                    occurredAt: log.createdAt,
                    source: .aiJob,
                    status: jobStatus(log.status),
                    title: log.step,
                    detail: redactedPreview(log.detail, limit: 220),
                    metadata: [
                        "任务": job.kind.label,
                        "状态": log.status.label
                    ]
                )
            })
            return events
        }
    }

    private static func streamingStatus(_ state: AnalysisMessageStreamingStatusState?) -> AnalysisTraceTimelineStatus {
        switch state {
        case .reasoning, .correcting: return .running
        case .completed: return .completed
        case .fallback: return .warning
        case nil: return .completed
        }
    }

    private static func messageKindTitle(_ kind: AnalysisSessionMessageKind) -> String {
        switch kind {
        case .userRequest: return "用户提问"
        case .aiAnalysis: return "AI 分析回答"
        case .aiMemo: return "完整汇报"
        case .simpleReport: return "简洁汇报"
        case .systemCoverage: return "读取范围记录"
        case .adoption: return "采纳记录"
        case .error: return "错误记录"
        }
    }

    private static func harnessStatus(_ status: AnalysisHarnessStatus) -> AnalysisTraceTimelineStatus {
        switch status {
        case .success: return .completed
        case .successWithWarnings, .blocked: return .warning
        case .failed: return .failed
        }
    }

    private static func auditStatus(_ status: AuditEventStatus) -> AnalysisTraceTimelineStatus {
        switch status {
        case .started: return .running
        case .completed: return .completed
        case .warning: return .warning
        case .failed: return .failed
        }
    }

    private static func notebookStatus(_ status: AnalysisNotebookCellStatus) -> AnalysisTraceTimelineStatus {
        switch status {
        case .success: return .completed
        case .failed: return .failed
        case .skipped: return .warning
        }
    }

    private static func collectionStatus(_ status: ExternalReferenceCollectionStatus) -> AnalysisTraceTimelineStatus {
        switch status {
        case .running: return .running
        case .succeeded: return .completed
        case .partialFailed: return .warning
        case .failed, .cancelled: return .failed
        }
    }

    private static func jobStatus(_ status: AIJobStatus) -> AnalysisTraceTimelineStatus {
        switch status {
        case .waiting: return .waiting
        case .requesting, .validating, .correcting: return .running
        case .completed: return .completed
        case .needsUserAction: return .warning
        case .cancelled, .failed: return .failed
        }
    }

    private static func redactedPreview(_ value: String, limit: Int) -> String {
        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return "未记录详情" }
        guard let boundary = collapsed.index(collapsed.startIndex, offsetBy: limit, limitedBy: collapsed.endIndex),
              boundary < collapsed.endIndex else {
            return collapsed
        }
        return String(collapsed[..<boundary]) + "..."
    }
}
