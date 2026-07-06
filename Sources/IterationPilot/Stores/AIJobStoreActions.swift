import Foundation

private enum StreamingMessageFlushPolicy {
    static let reasoningMinimumInterval: TimeInterval = 1.3
    static let reasoningCharacterDelta = 1_600
    static let contentMinimumInterval: TimeInterval = 0.9
    static let contentCharacterDelta = 1_600
}

private enum PersistentAIJobStoragePolicy {
    static let logLimit = 160
}

@MainActor
extension ProductWorkflowStore {
    func recoverInterruptedPersistentAIJobs() {
        var didChange = false
        for index in workspace.persistentAIJobs.indices where workspace.persistentAIJobs[index].status.isActive {
            workspace.persistentAIJobs[index].status = .waiting
            workspace.persistentAIJobs[index].nextRunAt = Date()
            workspace.persistentAIJobs[index].updatedAt = Date()
            workspace.persistentAIJobs[index].lastError = "App 上次退出时任务仍在执行，已恢复为等待重试。"
            workspace.persistentAIJobs[index].logs.append(AIReasoningLogEntry(
                step: workspace.persistentAIJobs[index].kind.label,
                status: .waiting,
                detail: workspace.persistentAIJobs[index].lastError
            ))
            syncPersistentJobRecord(at: index)
            didChange = true
        }
        if didChange {
            workspace.persistentAIJobs.sort { $0.updatedAt > $1.updatedAt }
        }
    }

    func isBlockingAnalysisSessionJob(_ job: PersistentAIJob, sessionID: UUID) -> Bool {
        job.payload.sessionID == sessionID &&
            (job.status == .waiting || job.status.isActive) &&
            (job.kind == .analysisSession || job.kind == .memo || job.kind == .simpleReportGeneration)
    }

    func normalizeStaleAnalysisSessionStatuses() {
        let blockingSessionIDs = Set(
            workspace.persistentAIJobs.compactMap { job -> UUID? in
                guard let sessionID = job.payload.sessionID,
                      isBlockingAnalysisSessionJob(job, sessionID: sessionID) else {
                    return nil
                }
                return sessionID
            }
        )
        var didChange = false
        for index in workspace.analysisSessions.indices where workspace.analysisSessions[index].status == .analyzing {
            let session = workspace.analysisSessions[index]
            guard !blockingSessionIDs.contains(session.id) else { continue }
            if !session.finalReportMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                workspace.analysisSessions[index].status = .reportReady
            } else if session.messages.contains(where: { $0.role == .assistant && ($0.kind == .aiAnalysis || $0.kind == .aiMemo || $0.kind == .simpleReport) }) {
                workspace.analysisSessions[index].status = .waitingForUser
            } else if session.messages.contains(where: { $0.role == .user }) {
                workspace.analysisSessions[index].status = .waitingForUser
            } else {
                workspace.analysisSessions[index].status = .draft
            }
            workspace.analysisSessions[index].updatedAt = Date()
            didChange = true
        }
        if didChange {
            statusText = "已修复历史会话中残留的分析中状态"
        }
    }

    @discardableResult
    func enqueuePersistentAIJob(kind: PersistentAIJobKind, payload: PersistentAIJobPayload) -> PersistentAIJob {
        let fingerprint = persistentAIJobFingerprint(kind: kind, payload: payload)
        if let existing = workspace.persistentAIJobs.first(where: { job in
            (job.status == .waiting || job.status.isActive) &&
                persistentAIJobFingerprint(kind: job.kind, payload: job.payload) == fingerprint
        }) {
            statusText = "已有相同 AI 任务在队列中，已复用现有任务"
            schedulePersistentAIJobs()
            return existing
        }

        var job = PersistentAIJob(kind: kind, payload: payload)
        job.logs.append(AIReasoningLogEntry(
            step: kind.label,
            status: .waiting,
            detail: "任务已入队，等待后台调度。"
        ))
        if let evidenceCoverage = payload.coverageSnapshot?.externalEvidenceCoverage {
            job.logs.append(AIReasoningLogEntry(
                step: "外部证据覆盖",
                status: .waiting,
                detail: evidenceCoverage.summary
            ))
        }
        trimPersistentAIJobLogs(&job)
        job.record.logs = job.logs
        workspace.persistentAIJobs.insert(job, at: 0)
        workspace.persistentAIJobs = Array(workspace.persistentAIJobs.prefix(240))
        save()
        schedulePersistentAIJobs()
        return job
    }

    func syncPersistentJobRecord(at index: Int) {
        guard workspace.persistentAIJobs.indices.contains(index) else { return }
        trimPersistentAIJobLogs(&workspace.persistentAIJobs[index])
        workspace.persistentAIJobs[index].record.jobType = workspace.persistentAIJobs[index].kind.label
        workspace.persistentAIJobs[index].record.targetID = workspace.persistentAIJobs[index].targetID
        workspace.persistentAIJobs[index].record.targetName = workspace.persistentAIJobs[index].targetName
        workspace.persistentAIJobs[index].record.status = workspace.persistentAIJobs[index].status
        workspace.persistentAIJobs[index].record.attemptCount = workspace.persistentAIJobs[index].attemptCount
        workspace.persistentAIJobs[index].record.maxAttempts = workspace.persistentAIJobs[index].maxImmediateAttempts
        workspace.persistentAIJobs[index].record.nextRunAt = workspace.persistentAIJobs[index].nextRunAt
        workspace.persistentAIJobs[index].record.lastError = workspace.persistentAIJobs[index].lastError
        workspace.persistentAIJobs[index].record.logs = workspace.persistentAIJobs[index].logs
        workspace.persistentAIJobs[index].record.updatedAt = workspace.persistentAIJobs[index].updatedAt
    }

    private func persistentAIJobFingerprint(kind: PersistentAIJobKind, payload: PersistentAIJobPayload) -> String {
        PersistentAIJobFingerprintBuilder.fingerprint(kind: kind, payload: payload)
    }

    private func trimPersistentAIJobLogs(_ job: inout PersistentAIJob) {
        if job.logs.count > PersistentAIJobStoragePolicy.logLimit {
            job.logs = Array(job.logs.suffix(PersistentAIJobStoragePolicy.logLimit))
        }
        if job.record.logs.count > PersistentAIJobStoragePolicy.logLimit {
            job.record.logs = Array(job.record.logs.suffix(PersistentAIJobStoragePolicy.logLimit))
        }
    }

    func updatePersistentAIJob(_ jobID: UUID, saveImmediately: Bool = true, _ transform: (inout PersistentAIJob) -> Void) {
        guard let index = workspace.persistentAIJobs.firstIndex(where: { $0.id == jobID }) else { return }
        transform(&workspace.persistentAIJobs[index])
        workspace.persistentAIJobs[index].updatedAt = Date()
        syncPersistentJobRecord(at: index)
        workspace.persistentAIJobs.sort { $0.updatedAt > $1.updatedAt }
        save(policy: saveImmediately ? .immediate : .deferred)
    }

    func schedulePersistentAIJobs() {
        guard runningPersistentAIJobID == nil else { return }
        schedulerWakeTask?.cancel()
        schedulerWakeTask = nil

        let now = Date()
        let waitingJobs = workspace.persistentAIJobs
            .filter { $0.status == .waiting }
            .sorted { lhs, rhs in
                (lhs.nextRunAt ?? lhs.createdAt) < (rhs.nextRunAt ?? rhs.createdAt)
            }
        guard let next = waitingJobs.first else { return }
        let nextRunAt = next.nextRunAt ?? now
        if nextRunAt <= now {
            startPersistentAIJob(next.id)
        } else {
            let delay = max(0.5, nextRunAt.timeIntervalSince(now))
            schedulerWakeTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await MainActor.run {
                    self?.schedulePersistentAIJobs()
                }
            }
        }
    }

    func startPersistentAIJob(_ jobID: UUID) {
        guard runningPersistentAIJobID == nil,
              let index = workspace.persistentAIJobs.firstIndex(where: { $0.id == jobID }),
              workspace.persistentAIJobs[index].status == .waiting else {
            return
        }
        runningPersistentAIJobID = jobID
        isRunningAI = true
        workspace.persistentAIJobs[index].status = .requesting
        workspace.persistentAIJobs[index].updatedAt = Date()
        workspace.persistentAIJobs[index].nextRunAt = nil
        workspace.persistentAIJobs[index].logs.append(AIReasoningLogEntry(
            step: workspace.persistentAIJobs[index].kind.label,
            status: .requesting,
            detail: "后台调度器已开始执行任务。"
        ))
        syncPersistentJobRecord(at: index)
        save()

        let task = Task { [weak self] in
            guard let self else { return }
            await self.runPersistentAIJob(jobID)
        }
        persistentAIJobTasks[jobID] = task
    }

    func runPersistentAIJob(_ jobID: UUID) async {
        defer {
            persistentAIJobTasks[jobID] = nil
            if runningPersistentAIJobID == jobID {
                runningPersistentAIJobID = nil
            }
            isRunningAI = false
            schedulePersistentAIJobs()
        }

        guard let job = workspace.persistentAIJobs.first(where: { $0.id == jobID }) else { return }
        do {
            switch job.kind {
            case .analysisSession:
                try await executeAnalysisSessionJob(job)
            case .memo:
                try await executeMemoJob(job)
            case .simpleReportGeneration:
                try await executeMemoJob(job)
            case .opportunityExtraction:
                try await executeOpportunityJob(job)
            case .businessSpaceProfile:
                try await executeBusinessSpaceProfileJob(job)
            case .businessMap:
                try await executeBusinessMapJob(job)
            case .referenceSourceRecommendation:
                try await executeReferenceSourceRecommendationJob(job)
            case .externalEventImpact:
                try await executeExternalEventImpactJob(job)
            case .tableFirstAnalysis:
                try await executeTableFirstAnalysisJob(job)
            case .metricSemanticExtraction:
                try await executeMetricSemanticExtractionJob(job)
            case .userQuestionMemoryExtraction:
                try await executeUserQuestionMemoryExtractionJob(job)
            }
        } catch {
            if isPersistentAIJobCancelled(jobID) || error is CancellationError {
                return
            }
            handlePersistentAIJobFailure(jobID, error: error)
        }
    }

    func isPersistentAIJobCancelled(_ jobID: UUID) -> Bool {
        workspace.persistentAIJobs.first(where: { $0.id == jobID })?.status == .cancelled
    }

    func executeAnalysisSessionJob(_ job: PersistentAIJob) async throws {
        guard let sessionID = job.payload.sessionID,
              var session = workspace.analysisSessions.first(where: { $0.id == sessionID }),
              var context = analysisSessionContext(for: session) else {
            throw AIAnalysisError.invalidResponse("分析会话任务缺少会话或数据包。")
        }
        let requestedContextMode = job.payload.contextMode ?? .fullReanalysis
        let sourcePolicy = job.payload.contextSourcePolicy ?? .tableOnly
        let triggeringUserMessage = session.messages.first(where: { $0.id == job.payload.messageID })
        let referencedMessage = triggeringUserMessage?.replyToMessageID.flatMap { messageID in
            session.messages.first { $0.id == messageID && $0.role == .assistant }
        }
        let hasPreviousAI = session.messages.contains { $0.role == .assistant && ($0.kind == .aiAnalysis || $0.kind == .aiMemo || $0.kind == .simpleReport) }
        let signature = analysisContextSignature(session: session, pack: context.pack, task: context.task, reports: context.reports)
        let contextMode = AnalysisHarnessRouter.effectiveContextMode(
            requestedMode: requestedContextMode,
            userMessage: job.payload.userMessage,
            hasPreviousAI: hasPreviousAI,
            cacheMatches: session.contextCache?.signature == signature
        )
        if contextMode != requestedContextMode {
            updatePersistentAIJob(job.id, saveImmediately: false) { job in
                job.payload.contextMode = contextMode
                job.logs.append(AIReasoningLogEntry(
                    step: "任务路由降级",
                    status: .requesting,
                    detail: "检测到本轮是简单任务，已从 \(requestedContextMode.label) 降级为 \(contextMode.label)，避免触发表格重算和严格校验。"
                ))
            }
        }
        if contextMode.usesFullContext {
            updatePersistentAIJob(job.id, saveImmediately: false) { job in
                job.logs.append(AIReasoningLogEntry(
                    step: "正在检查周期画像",
                    status: .requesting,
                    detail: "正在检查当前任务报表周期缓存；仅在缺失或版本过旧时刷新，避免发送后阻塞界面。"
                ))
            }
            if refreshTrendMetadataForAnalysisSession(sessionID, force: false),
               let refreshedSession = workspace.analysisSessions.first(where: { $0.id == sessionID }),
               let refreshedContext = analysisSessionContext(for: refreshedSession) {
                session = refreshedSession
                context = refreshedContext
            }
        }
        var coverageSnapshot = job.payload.coverageSnapshot
        var prompt = job.payload.prompt
        var notebookRun: AnalysisNotebookRun?

        if coverageSnapshot == nil || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updatePersistentAIJob(job.id, saveImmediately: false) { job in
                job.logs.append(AIReasoningLogEntry(
                    step: "正在准备上下文",
                    status: .requesting,
                    detail: "正在读取当前任务表格、缓存和本轮选择的资料范围：\(sourcePolicy.label)。"
                ))
            }

            let workspaceSnapshot = workspace
            let packSnapshot = context.pack
            let taskSnapshot = context.task
            let reportsSnapshot = context.reports
            let userMessage = job.payload.userMessage
            let preparedCoverage = await Task.detached(priority: .userInitiated) {
                AnalysisCoverageSnapshotBuilder.build(
                    userRequest: userMessage,
                    reports: reportsSnapshot,
                    workspace: workspaceSnapshot,
                    pack: packSnapshot,
                    task: taskSnapshot,
                    contextMode: contextMode,
                    sourcePolicy: sourcePolicy
                )
            }.value
            guard !isPersistentAIJobCancelled(job.id) else { return }

            let evidenceSources = contextMode.usesFullContext && sourcePolicy.refreshExternalReferences ? enabledReferenceSourcesForCurrentSpace() : []
            if let evidenceWindow = preparedCoverage.externalEvidenceWindow,
               !evidenceSources.isEmpty {
                startBackgroundReferenceCollectionForAnalysis(
                    sources: evidenceSources,
                    evidenceWindow: evidenceWindow,
                    trigger: .analysisFullContext,
                    sessionID: sessionID,
                    packID: context.pack.id,
                    taskID: context.task?.id,
                    contextMode: contextMode,
                    jobID: job.id
                )
            }
            guard !isPersistentAIJobCancelled(job.id) else { return }

            if job.payload.coverageSnapshot == nil {
                appendCoverageSnapshot(preparedCoverage, to: sessionID)
                appendAnalysisSessionMessage(
                    sessionID: sessionID,
                    AnalysisSessionMessage(
                        role: .system,
                        kind: .systemCoverage,
                        content: coverageChatMessage(for: preparedCoverage, mode: contextMode)
                    )
                )
                if let refreshedSession = workspace.analysisSessions.first(where: { $0.id == sessionID }),
                   let refreshedContext = analysisSessionContext(for: refreshedSession) {
                    session = refreshedSession
                    context = refreshedContext
                }
            }

            if contextMode.usesFullContext {
                updatePersistentAIJob(job.id, saveImmediately: false) { job in
                    job.logs.append(AIReasoningLogEntry(
                        step: "正在执行 SQL 计算",
                        status: .requesting,
                        detail: "正在用 DuckDB 生成本轮 Notebook 计算证据，供 AI 引用并供用户回溯。"
                    ))
                }
                let notebookWorkspace = workspace
                let notebookPack = context.pack
                let notebookTask = context.task
                let notebookReports = context.reports
                let notebookMessageID = job.payload.messageID
                notebookRun = await Task.detached(priority: .userInitiated) {
                    AnalysisSQLRuntime.buildNotebookRun(
                        userRequest: userMessage,
                        reports: notebookReports,
                        workspace: notebookWorkspace,
                        pack: notebookPack,
                        task: notebookTask,
                        sessionID: sessionID,
                        messageID: notebookMessageID,
                        trigger: contextMode.label,
                        contextMode: contextMode
                    )
                }.value
                if let notebookRun {
                    appendAnalysisNotebookRun(notebookRun, to: sessionID)
                    if let refreshedSession = workspace.analysisSessions.first(where: { $0.id == sessionID }),
                       let refreshedContext = analysisSessionContext(for: refreshedSession) {
                        session = refreshedSession
                        context = refreshedContext
                    }
                }
                guard !isPersistentAIJobCancelled(job.id) else { return }
            }

            updatePersistentAIJob(job.id, saveImmediately: false) { job in
                job.logs.append(AIReasoningLogEntry(
                    step: "正在生成 Prompt",
                    status: .requesting,
                    detail: "正在组装本轮问题、表格事实包、缓存和记忆。"
                ))
            }
            let promptSession = session
            let promptContext = context
            let promptWorkspace = workspace
            prompt = await Task.detached(priority: .userInitiated) {
                AnalysisSessionAIService.buildChatPrompt(
                    userMessage: userMessage,
                    session: promptSession,
                    pack: promptContext.pack,
                    task: promptContext.task,
                    reports: promptContext.reports,
                    workspace: promptWorkspace,
                    contextMode: contextMode,
                    sourcePolicy: sourcePolicy,
                    referencedMessage: referencedMessage
                )
            }.value
            if let notebookRun {
                prompt += "\n\n\(notebookRun.promptMarkdown)"
            }
            coverageSnapshot = preparedCoverage
            updatePersistentAIJob(job.id, saveImmediately: false) { job in
                job.payload.prompt = prompt
                job.payload.coverageSnapshot = preparedCoverage
            }
        }

        guard let coverageSnapshot,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIAnalysisError.invalidResponse("分析会话任务未能生成 Prompt 或覆盖快照。")
        }

        if shouldUseAnalysisHarness(
            contextMode: contextMode,
            sourcePolicy: sourcePolicy,
            userMessage: job.payload.userMessage,
            referencedMessage: referencedMessage,
            selectedReportCount: context.reports.count
        ) {
            updatePersistentAIJob(job.id, saveImmediately: false) { job in
                job.logs.append(AIReasoningLogEntry(
                    step: "本地校验",
                    status: .requesting,
                    detail: contextMode == .fullReanalysis
                        ? "正在执行表格理解、分析计划、本地计算、资料证据和回答校验链路。"
                        : "检测到快速问答需要可验证计算/资料引用，正在执行轻量校验链路。"
                ))
            }
            let assistantMessageID = UUID()
            appendAnalysisSessionMessage(
                sessionID: sessionID,
                AnalysisSessionMessage(
                    id: assistantMessageID,
                    role: .assistant,
                    kind: .aiAnalysis,
                    content: "",
                    streamingStatus: AnalysisMessageStreamingStatus(
                        state: .reasoning,
                        title: "正在校验证据",
                        detail: "正在准备本地计算、资料证据和报告校验。"
                    ),
                    replyToMessageID: triggeringUserMessage?.replyToMessageID,
                    quotedMessageSummary: triggeringUserMessage?.quotedMessageSummary
                )
            )
            do {
                let harnessReports = context.reports
                let harnessUserQuery = job.payload.userMessage
                let harnessSettings = workspace.aiSettings
                var lastHarnessContentFlush = Date.distantPast
                var lastHarnessContentLength = 0
                let harnessRun = try await AnalysisHarnessOrchestrator().run(
                    userQuery: harnessUserQuery,
                    reports: harnessReports,
                    workspace: workspace,
                    pack: context.pack,
                    task: context.task,
                    session: session,
                    sourcePolicy: sourcePolicy,
                    settings: harnessSettings,
                    onProgress: { event in
                        await MainActor.run {
                            guard !self.isPersistentAIJobCancelled(job.id) else { return }
                            self.updatePersistentAIJob(job.id, saveImmediately: false) { job in
                                job.logs.append(AIReasoningLogEntry(
                                    step: event.stage.label,
                                    status: event.status.jobStatus,
                                    detail: event.summary
                                ))
                            }
                            self.updateAnalysisSessionMessage(
                                sessionID: sessionID,
                                messageID: assistantMessageID,
                                touchUpdatedAt: false,
                                savePolicy: .deferred
                            ) { message in
                                if message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    message.streamingStatus = AnalysisMessageStreamingStatus(
                                        state: .reasoning,
                                        title: event.stage.label,
                                        detail: event.summary
                                    )
                                }
                            }
                        }
                    },
                    onReportDelta: { accumulatedText in
                        let now = Date()
                        let lengthDelta = accumulatedText.count - lastHarnessContentLength
                        guard now.timeIntervalSince(lastHarnessContentFlush) >= StreamingMessageFlushPolicy.contentMinimumInterval ||
                            lengthDelta >= StreamingMessageFlushPolicy.contentCharacterDelta ||
                            lastHarnessContentLength == 0 else { return }
                        lastHarnessContentFlush = now
                        lastHarnessContentLength = accumulatedText.count
                        await MainActor.run {
                            guard !self.isPersistentAIJobCancelled(job.id) else { return }
                            self.updateAnalysisSessionMessage(
                                sessionID: sessionID,
                                messageID: assistantMessageID,
                                touchUpdatedAt: false,
                                savePolicy: .deferred
                            ) { message in
                                message.content = accumulatedText
                                message.streamingStatus = AnalysisMessageStreamingStatus(
                                    state: .reasoning,
                                    title: "正在输出回答",
                                    detail: "已完成本地计算，正在输出解释回答。"
                                )
                            }
                        }
                    }
                )
                guard !isPersistentAIJobCancelled(job.id) else { return }
                updatePersistentAIJob(job.id, saveImmediately: false) { job in
                    for event in harnessRun.auditLog {
                        job.logs.append(AIReasoningLogEntry(
                            step: event.stage.label,
                            status: event.status.jobStatus,
                            detail: event.summary
                        ))
                    }
                }

                let formattedOutput = AnalysisOutputTextFormatter.normalizedPercentages(in: harnessRun.reportMarkdown)
                let harnessDisplaySummary = ValidationDecisionEngine.displaySummary(for: harnessRun.validationIssues)
                let assistantCorrectionStatus: AnalysisMessageCorrectionStatus = triggeringUserMessage?.replyToMessageID != nil && userMessageLooksLikeCorrection(job.payload.userMessage)
                    ? .candidateGenerated
                    : .none
                let memoryEvidence = smartMemoryEvidence(
                    pack: context.pack,
                    task: context.task,
                    session: session,
                    reports: context.reports,
                    userText: job.payload.userMessage
                )
                let notebookEvidence = notebookRun.map { run in
                    AnalysisSessionEvidence(
                        sourceType: "计算证据",
                        title: "本轮 Notebook/SQL 计算证据",
                        detail: run.evidenceMarkdown,
                        sourceID: run.id.uuidString
                    )
                }
                updateAnalysisSessionMessage(
                    sessionID: sessionID,
                    messageID: assistantMessageID
                ) { message in
                    message.content = formattedOutput
                    message.streamingStatus = AnalysisMessageStreamingStatus(
                        state: harnessRun.status == .blocked ? .fallback : .completed,
                        title: harnessRun.status == .blocked ? "需要确认分析资料" : "本地校验\(harnessRun.status.label)",
                        detail: harnessDisplaySummary.chatDetail(
                            runID: harnessRun.id,
                            verifiedResultCount: harnessRun.verifiedResults.count
                        )
                    )
                    message.evidence = AnalysisSessionAIService.evidence(
                            for: context.reports,
                            workspace: workspace,
                            businessSpaceID: context.task?.businessSpaceID ?? context.pack.businessSpaceID ?? session.businessSpaceID
                        ) + memoryEvidence + (notebookEvidence.map { [$0] } ?? []) + [
                            AnalysisSessionEvidence(
                                sourceType: "数据覆盖",
                                title: "本轮 AI 读取范围",
                                detail: AnalysisCoverageSnapshotBuilder.aiReadRangeMarkdown(coverageSnapshot),
                                sourceID: coverageSnapshot.id.uuidString
                            ),
                            AnalysisSessionEvidence(
                                sourceType: "Analysis Harness",
                                title: "本轮 Analysis Harness 审计",
                                detail: harnessRun.evidenceMarkdown,
                                sourceID: harnessRun.id.uuidString,
                                analysisHarnessRun: harnessRun
                            )
                        ]
                    message.replyToMessageID = triggeringUserMessage?.replyToMessageID
                    message.quotedMessageSummary = triggeringUserMessage?.quotedMessageSummary
                    message.correctionStatus = assistantCorrectionStatus
                }
                presentHarnessConfirmationIfNeeded(
                    run: harnessRun,
                    sessionID: sessionID,
                    reports: harnessReports
                )
                updateAnalysisContextCache(
                    sessionID: sessionID,
                    mode: contextMode,
                    userRequest: job.payload.userMessage,
                    aiOutput: formattedOutput,
                    coverageSnapshot: coverageSnapshot,
                    pack: context.pack,
                    task: context.task,
                    reports: context.reports
                )
                var record = AIJobRecord(
                    id: job.id,
                    jobType: job.kind.label,
                    targetID: sessionID,
                    targetName: job.targetName,
                    status: harnessRun.status == .blocked ? .needsUserAction : .completed,
                    attemptCount: 1,
                    maxAttempts: job.maxImmediateAttempts,
                    lastError: harnessRun.status == .blocked ? "Analysis Harness blocked output" : "",
                    logs: harnessRun.auditLog.map { event in
                        AIReasoningLogEntry(step: event.stage.label, status: event.status.jobStatus, detail: event.summary)
                    }
                )
                record.updatedAt = Date()
                insertAIJobRecord(record, packID: context.pack.id, targetID: sessionID, targetName: job.targetName)
                markPersistentAIJobCompleted(
                    job.id,
                    record: record,
                    detail: harnessRun.status == .blocked ? "需要确认分析资料，已停止输出未校验数字。" : "已完成本地校验并写入当前会话。"
                )
                setPackAnalysisGate(context.pack.id, harnessRun.status == .blocked ? .readyForAnalysis : .analyzed)
                setAnalysisSessionStatus(sessionID, .waitingForUser)
                if harnessRun.status != .blocked {
                    if contextMode == .fullReanalysis {
                        enqueuePersistentAIJob(
                            kind: .opportunityExtraction,
                            payload: PersistentAIJobPayload(
                                aiOutput: formattedOutput,
                                sessionID: sessionID,
                                packID: context.pack.id,
                                taskID: context.task?.id,
                                targetName: job.targetName,
                                contextMode: .fullReanalysis
                            )
                        )
                        statusText = "本地校验已完成，机会评分已进入后台任务队列"
                    } else {
                        statusText = "轻量 Harness 统计已完成；本轮未触发机会评分"
                    }
                    enqueuePostAnalysisMemoryJobs(
                        userMessage: job.payload.userMessage,
                        messageID: job.payload.messageID,
                        sessionID: sessionID,
                        packID: context.pack.id,
                        taskID: context.task?.id,
                        businessSpaceID: context.task?.businessSpaceID ?? context.pack.businessSpaceID ?? workspace.selectedBusinessSpaceID
                    )
                } else {
                    statusText = "需要确认分析资料；请查看回答和分析资料中的证据信息"
                }
                return
            } catch {
                guard !isPersistentAIJobCancelled(job.id) else { return }
                updateAnalysisSession(
                    sessionID: sessionID,
                    touchUpdatedAt: false,
                    savePolicy: .deferred
                ) { session in
                    session.messages.removeAll { $0.id == assistantMessageID }
                }
                updatePersistentAIJob(job.id, saveImmediately: false) { job in
                    job.logs.append(AIReasoningLogEntry(
                        step: "本地校验回退",
                        status: .waiting,
                        detail: "Harness 基础设施异常，回退旧 AI 直答链路：\(error.localizedDescription)"
                    ))
                }
            }
        }

        updatePersistentAIJob(job.id, saveImmediately: false) { job in
            job.logs.append(AIReasoningLogEntry(
                step: "正在请求模型",
                status: .requesting,
                detail: "分析资料已准备完成，正在等待 AI 回复。"
            ))
        }

        let assistantMessageID = UUID()
        appendAnalysisSessionMessage(
            sessionID: sessionID,
            AnalysisSessionMessage(
                id: assistantMessageID,
                role: .assistant,
                kind: .aiAnalysis,
                content: "",
                streamingStatus: AnalysisMessageStreamingStatus(
                    state: .reasoning,
                    title: "正在连接 AI",
                    detail: "已发送请求，等待模型开始推理和输出。"
                ),
                replyToMessageID: triggeringUserMessage?.replyToMessageID,
                quotedMessageSummary: triggeringUserMessage?.quotedMessageSummary
            )
        )

        let queue = AIJobQueue(maxAttempts: job.maxImmediateAttempts)
        let validationReports = context.reports
        let validationUserRequest = job.payload.userMessage
        let analysisValidation: (String) -> [String] = { output in
            AggregationConsistencyValidator.validate(
                output: output,
                userRequest: validationUserRequest,
                reports: validationReports,
                notebookRun: notebookRun
            )
        }
        let analysisCorrectionPrompt: (_ originalPrompt: String, _ output: String, _ warnings: [String]) -> String = { originalPrompt, output, warnings in
            AggregationConsistencyValidator.correctionPrompt(
                originalPrompt: originalPrompt,
                output: output,
                warnings: warnings,
                notebookRun: notebookRun
            )
        }
        var result: (output: String, record: AIJobRecord)
        do {
            var lastStreamingFlush = Date.distantPast
            var lastStreamingFlushLength = 0
            var lastStreamingProgressFlush = Date.distantPast
            var lastRenderedReasoningLength = 0
            var latestStreamingReasoningText = ""
            result = try await AIJobQueue(maxAttempts: 1).runStreamingTextJob(
                prompt: prompt,
                settings: workspace.aiSettings,
                jobType: job.kind.label,
                validation: { _ in [] },
                onProgress: { progressText in
                    latestStreamingReasoningText = progressText
                    guard lastStreamingFlushLength == 0 else { return }
                    let now = Date()
                    let lengthDelta = progressText.count - lastRenderedReasoningLength
                    guard lengthDelta > 0 else { return }
                    guard now.timeIntervalSince(lastStreamingProgressFlush) >= StreamingMessageFlushPolicy.reasoningMinimumInterval ||
                        lengthDelta >= StreamingMessageFlushPolicy.reasoningCharacterDelta else { return }
                    lastStreamingProgressFlush = now
                    lastRenderedReasoningLength = progressText.count
                    await MainActor.run {
                        guard !self.isPersistentAIJobCancelled(job.id) else { return }
                        self.updateAnalysisSessionMessage(
                            sessionID: sessionID,
                            messageID: assistantMessageID,
                            touchUpdatedAt: false,
                            savePolicy: .deferred
                        ) { message in
                            message.streamingStatus = AnalysisMessageStreamingStatus(
                                state: .reasoning,
                                title: "正在思考",
                                detail: progressText
                            )
                        }
                    }
                },
                onDelta: { accumulatedText in
                    let now = Date()
                    let lengthDelta = accumulatedText.count - lastStreamingFlushLength
                    guard now.timeIntervalSince(lastStreamingFlush) >= StreamingMessageFlushPolicy.contentMinimumInterval ||
                        lengthDelta >= StreamingMessageFlushPolicy.contentCharacterDelta else { return }
                    lastStreamingFlush = now
                    lastStreamingFlushLength = accumulatedText.count
                    await MainActor.run {
                        guard !self.isPersistentAIJobCancelled(job.id) else { return }
                        self.updateAnalysisSessionMessage(
                            sessionID: sessionID,
                            messageID: assistantMessageID,
                            touchUpdatedAt: false,
                            savePolicy: .deferred
                        ) { message in
                            if message.streamingStatus?.state == .reasoning {
                                let reasoningDetail = latestStreamingReasoningText.nilIfBlank ??
                                    message.streamingStatus?.detail.nilIfBlank ??
                                    "模型已完成思考过程传输。"
                                message.streamingStatus = AnalysisMessageStreamingStatus(
                                    state: .completed,
                                    title: "已完成思考",
                                    detail: reasoningDetail
                                )
                            }
                            message.content = accumulatedText
                        }
                    }
                }
            )
            let validationWarnings = analysisValidation(result.output)
            if !validationWarnings.isEmpty {
                let warningText = validationWarnings.joined(separator: "；")
                updatePersistentAIJob(job.id, saveImmediately: false) { job in
                    job.logs.append(AIReasoningLogEntry(
                        step: "事实校验修正",
                        status: .correcting,
                        detail: "流式回答已收到，但未通过本地事实校验：\(warningText)。正在自动要求 AI 重写。"
                    ))
                }
                updateAnalysisSessionMessage(
                    sessionID: sessionID,
                    messageID: assistantMessageID,
                    touchUpdatedAt: false,
                    savePolicy: .deferred
                ) { message in
                    let reasoningDetail = message.streamingStatus?.detail.nilIfBlank
                    let detail = [
                        "发现问题：\(warningText)",
                        reasoningDetail.map { "已保留的思考过程：\n\($0)" }
                    ]
                    .compactMap { $0 }
                    .joined(separator: "\n\n")
                    message.streamingStatus = AnalysisMessageStreamingStatus(
                        state: .correcting,
                        title: "回答未通过本地事实校验，正在自动修正",
                        detail: detail
                    )
                }
                result = try await queue.runTextJob(
                    prompt: analysisCorrectionPrompt(prompt, result.output, validationWarnings),
                    settings: workspace.aiSettings,
                    jobType: job.kind.label,
                    validation: analysisValidation,
                    correctionPrompt: analysisCorrectionPrompt
                )
            }
        } catch {
            guard !isPersistentAIJobCancelled(job.id) else { return }
            updatePersistentAIJob(job.id, saveImmediately: false) { job in
                job.logs.append(AIReasoningLogEntry(
                    step: "流式降级",
                    status: .waiting,
                    detail: "流式输出不可用或中断，已降级为普通请求：\(error.localizedDescription)"
                ))
            }
            let fallbackReason = streamingFallbackReason(from: error)
            updateAnalysisSessionMessage(sessionID: sessionID, messageID: assistantMessageID) { message in
                let reasoningDetail = message.streamingStatus?.detail.nilIfBlank
                let detail = [
                    "降级原因：\(fallbackReason)",
                    reasoningDetail.map { "降级前已收到的思考过程：\n\($0)" }
                ]
                .compactMap { $0 }
                .joined(separator: "\n\n")
                message.streamingStatus = AnalysisMessageStreamingStatus(
                    state: .fallback,
                    title: "流式输出已降级为普通请求",
                    detail: detail
                )
                message.content = "正在等待普通请求返回..."
            }
            result = try await queue.runTextJob(
                prompt: prompt,
                settings: workspace.aiSettings,
                jobType: job.kind.label,
                validation: analysisValidation,
                correctionPrompt: analysisCorrectionPrompt
            )
        }
        guard !isPersistentAIJobCancelled(job.id) else { return }
        updatePersistentAIJob(job.id, saveImmediately: false) { job in
            job.logs.append(AIReasoningLogEntry(
                step: "已收到模型回复",
                status: .validating,
                detail: "正在整理回答并写入当前会话。"
            ))
        }
        let formattedOutput = AnalysisOutputTextFormatter.normalizedPercentages(in: result.output)
        let assistantCorrectionStatus: AnalysisMessageCorrectionStatus = triggeringUserMessage?.replyToMessageID != nil && userMessageLooksLikeCorrection(job.payload.userMessage)
            ? .candidateGenerated
            : .none
        let memoryEvidence = smartMemoryEvidence(
            pack: context.pack,
            task: context.task,
            session: session,
            reports: context.reports,
            userText: job.payload.userMessage
        )
        let notebookEvidence = notebookRun.map { run in
            AnalysisSessionEvidence(
                sourceType: "计算证据",
                title: "本轮 Notebook/SQL 计算证据",
                detail: run.evidenceMarkdown,
                sourceID: run.id.uuidString
            )
        }
        updateAnalysisSessionMessage(sessionID: sessionID, messageID: assistantMessageID) { message in
            message.content = formattedOutput
            message.streamingStatus = AnalysisMessageStreamingStatus(
                state: .completed,
                title: contextMode.usesFullContext ? "AI 分析已完成" : "快速回答已完成",
                detail: contextMode.usesFullContext
                    ? "已完成模型回答和本地聚合一致性检查。"
                    : "本轮按轻量任务处理，未重新读取全量表格或触发严格 Harness 校验。"
            )
            message.evidence = AnalysisSessionAIService.evidence(
                    for: context.reports,
                    workspace: workspace,
                    businessSpaceID: context.task?.businessSpaceID ?? context.pack.businessSpaceID ?? session.businessSpaceID
                ) + memoryEvidence + (notebookEvidence.map { [$0] } ?? []) + [
                    AnalysisSessionEvidence(
                        sourceType: "数据覆盖",
                        title: "本轮 AI 读取范围",
                        detail: AnalysisCoverageSnapshotBuilder.aiReadRangeMarkdown(coverageSnapshot),
                        sourceID: coverageSnapshot.id.uuidString
                    )
                ]
            message.replyToMessageID = triggeringUserMessage?.replyToMessageID
            message.quotedMessageSummary = triggeringUserMessage?.quotedMessageSummary
            message.correctionStatus = assistantCorrectionStatus
        }
        updateAnalysisContextCache(
            sessionID: sessionID,
            mode: contextMode,
            userRequest: job.payload.userMessage,
            aiOutput: formattedOutput,
            coverageSnapshot: coverageSnapshot,
            pack: context.pack,
            task: context.task,
            reports: context.reports
        )
        var record = result.record
        record.id = job.id
        insertAIJobRecord(record, packID: context.pack.id, targetID: sessionID, targetName: job.targetName)
        markPersistentAIJobCompleted(job.id, record: record, detail: "分析会话已生成并写入当前会话。")
        setPackAnalysisGate(context.pack.id, .analyzed)
        setAnalysisSessionStatus(sessionID, .waitingForUser)
        if contextMode == .fullReanalysis {
            enqueuePersistentAIJob(
                kind: .opportunityExtraction,
                payload: PersistentAIJobPayload(
                    aiOutput: result.output,
                    sessionID: sessionID,
                    packID: context.pack.id,
                    taskID: context.task?.id,
                    targetName: job.targetName,
                    contextMode: .fullReanalysis
                )
            )
            statusText = "完整分析已完成，机会评分已进入后台任务队列"
        } else {
            statusText = "AI 追问已完成；需要机会评分时可手动生成，或点击重新分析当前任务"
        }
        enqueuePostAnalysisMemoryJobs(
            userMessage: job.payload.userMessage,
            messageID: job.payload.messageID,
            sessionID: sessionID,
            packID: context.pack.id,
            taskID: context.task?.id,
            businessSpaceID: context.task?.businessSpaceID ?? context.pack.businessSpaceID ?? workspace.selectedBusinessSpaceID
        )
    }

    private func streamingFallbackReason(from error: Error) -> String {
        let rawReason = error.localizedDescription
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawReason.isEmpty else {
            return "流式响应为空或连接被提前关闭。"
        }
        if rawReason.count > 280 {
            return String(rawReason.prefix(280)) + "..."
        }
        return rawReason
    }

    func executeMemoJob(_ job: PersistentAIJob) async throws {
        guard let sessionID = job.payload.sessionID,
              var session = workspace.analysisSessions.first(where: { $0.id == sessionID }),
              var context = analysisSessionContext(for: session) else {
            throw AIAnalysisError.invalidResponse("报告任务缺少会话或数据包。")
        }
        let isSimpleReport = job.kind == .simpleReportGeneration
        let reportKindName = isSimpleReport ? "简洁汇报" : "完整汇报"
        let contextMode: AnalysisContextMode = .reportGeneration
        let reportScope = job.payload.reportScope ?? ReportGenerationScope()
        let reportRequest = job.payload.userMessage.nilIfBlank ?? (isSimpleReport ? simpleReportGenerationUserRequest(for: session, scope: reportScope) : reportGenerationUserRequest(for: session, scope: reportScope))

        updatePersistentAIJob(job.id, saveImmediately: false) { job in
            job.logs.append(AIReasoningLogEntry(
                step: isSimpleReport ? "正在准备简洁汇报资料" : "正在准备完整汇报资料",
                status: .requesting,
                detail: isSimpleReport
                    ? "简洁汇报会全量读取当前任务表格、会话问题、记忆、知识库和外部证据，但输出仅保留日常汇报三段。"
                    : "完整汇报模式会重新读取当前任务表格、会话问题、记忆、知识库和外部证据，不复用旧汇报正文。"
            ))
        }
        if refreshTrendMetadataForAnalysisSession(sessionID, force: false),
           let refreshedSession = workspace.analysisSessions.first(where: { $0.id == sessionID }),
           let refreshedContext = analysisSessionContext(for: refreshedSession) {
            session = refreshedSession
            context = refreshedContext
        }
        guard !isPersistentAIJobCancelled(job.id) else { return }

        let requirementDigest = ReportRequirementDigestBuilder.build(session: session)
        updateAnalysisSession(sessionID: sessionID) { session in
            session.reportRequirementDigest = requirementDigest
            session.status = .analyzing
        }
        if let refreshedSession = workspace.analysisSessions.first(where: { $0.id == sessionID }),
           let refreshedContext = analysisSessionContext(for: refreshedSession) {
            session = refreshedSession
            context = refreshedContext
        }

        updatePersistentAIJob(job.id, saveImmediately: false) { job in
            job.logs.append(AIReasoningLogEntry(
                step: "正在生成覆盖快照",
                status: .requesting,
                detail: "正在生成 AI 读取范围、周期画像和外部证据窗口。"
            ))
        }
        let initialWorkspaceSnapshot = workspace
        let initialPackSnapshot = context.pack
        let initialTaskSnapshot = context.task
        let initialReportsSnapshot = context.reports
        var coverageSnapshot = await Task.detached(priority: .userInitiated) {
            AnalysisCoverageSnapshotBuilder.build(
                userRequest: reportRequest,
                reports: initialReportsSnapshot,
                workspace: initialWorkspaceSnapshot,
                pack: initialPackSnapshot,
                task: initialTaskSnapshot,
                contextMode: contextMode
            )
        }.value
        guard !isPersistentAIJobCancelled(job.id) else { return }

        if let evidenceWindow = coverageSnapshot.externalEvidenceWindow {
            let evidenceSources = enabledReferenceSourcesForCurrentSpace()
            let selectedSources = analysisBackgroundReferenceSources(
                from: evidenceSources,
                limit: NetworkTimeouts.reportGenerationSourceLimit
            )
            let skippedCount = max(evidenceSources.count - selectedSources.count, 0)
            if selectedSources.isEmpty {
                updatePersistentAIJob(job.id, saveImmediately: false) { job in
                    job.logs.append(AIReasoningLogEntry(
                        step: "外部证据未采集",
                        status: .requesting,
                        detail: evidenceSources.isEmpty
                            ? "当前业务空间没有可采集的已启用外部数据源，报告将标注外部证据覆盖不足。"
                            : "已启用外部数据源均不可采集，报告将标注跳过原因。"
                    ))
                }
            } else if isCollectingReferences {
                updatePersistentAIJob(job.id, saveImmediately: false) { job in
                    job.logs.append(AIReasoningLogEntry(
                        step: "外部采集使用缓存",
                        status: .requesting,
                        detail: "已有外部采集任务正在运行，本轮报告使用当前缓存，并在报告中标注外部证据覆盖限制。"
                    ))
                }
            } else {
                updatePersistentAIJob(job.id, saveImmediately: false) { job in
                    job.logs.append(AIReasoningLogEntry(
                        step: "正在采集外部证据",
                        status: .requesting,
                        detail: "按本轮周期限时采集 \(selectedSources.count) 个高优先级已启用源，跳过 \(skippedCount) 个低优先级源。报告最多等待 \(Int(NetworkTimeouts.reportReferenceCollectionWaitBudget)) 秒，周期：\(evidenceWindow.summary)"
                    ))
                }
                _ = await collectReferenceSources(
                    sources: selectedSources,
                    autoRecompute: false,
                    silent: true,
                    evidenceWindow: evidenceWindow,
                    trigger: .reportGeneration,
                    sessionID: sessionID,
                    packID: context.pack.id,
                    taskID: context.task?.id,
                    contextMode: contextMode,
                    timeBudget: NetworkTimeouts.reportReferenceCollectionWaitBudget
                )
                guard !isPersistentAIJobCancelled(job.id) else { return }
                if let refreshedSession = workspace.analysisSessions.first(where: { $0.id == sessionID }),
                   let refreshedContext = analysisSessionContext(for: refreshedSession) {
                    session = refreshedSession
                    context = refreshedContext
                }
                updatePersistentAIJob(job.id, saveImmediately: false) { job in
                    job.logs.append(AIReasoningLogEntry(
                        step: "正在重建覆盖快照",
                        status: .requesting,
                        detail: "外部证据采集结束，正在用最新情报和采集日志更新报告事实包。"
                    ))
                }
                let refreshedWorkspaceSnapshot = workspace
                let refreshedPackSnapshot = context.pack
                let refreshedTaskSnapshot = context.task
                let refreshedReportsSnapshot = context.reports
                coverageSnapshot = await Task.detached(priority: .userInitiated) {
                    AnalysisCoverageSnapshotBuilder.build(
                        userRequest: reportRequest,
                        reports: refreshedReportsSnapshot,
                        workspace: refreshedWorkspaceSnapshot,
                        pack: refreshedPackSnapshot,
                        task: refreshedTaskSnapshot,
                        contextMode: contextMode
                    )
                }.value
            }
        } else {
            updatePersistentAIJob(job.id, saveImmediately: false) { job in
                job.logs.append(AIReasoningLogEntry(
                    step: "外部证据窗口未确定",
                    status: .requesting,
                    detail: "当前表格或用户问题没有形成明确周期窗口，报告将说明外部证据只能作为背景或弱线索。"
                ))
            }
        }
        guard !isPersistentAIJobCancelled(job.id) else { return }

        appendCoverageSnapshot(coverageSnapshot, to: sessionID)
        if let refreshedSession = workspace.analysisSessions.first(where: { $0.id == sessionID }),
           let refreshedContext = analysisSessionContext(for: refreshedSession) {
            session = refreshedSession
            context = refreshedContext
        }

        updatePersistentAIJob(job.id, saveImmediately: false) { job in
            job.logs.append(AIReasoningLogEntry(
                step: "正在执行 SQL 计算",
                status: .requesting,
                detail: "正在为\(reportKindName)生成 DuckDB Notebook 计算证据。"
            ))
        }
        let notebookWorkspace = workspace
        let notebookPack = context.pack
        let notebookTask = context.task
        let notebookReports = context.reports
        let notebookRun = await Task.detached(priority: .userInitiated) {
            AnalysisSQLRuntime.buildNotebookRun(
                userRequest: reportRequest,
                reports: notebookReports,
                workspace: notebookWorkspace,
                pack: notebookPack,
                task: notebookTask,
                sessionID: sessionID,
                messageID: job.payload.messageID,
                trigger: contextMode.label,
                contextMode: contextMode
            )
        }.value
        appendAnalysisNotebookRun(notebookRun, to: sessionID)
        if let refreshedSession = workspace.analysisSessions.first(where: { $0.id == sessionID }),
           let refreshedContext = analysisSessionContext(for: refreshedSession) {
            session = refreshedSession
            context = refreshedContext
        }
        guard !isPersistentAIJobCancelled(job.id) else { return }

        updatePersistentAIJob(job.id, saveImmediately: false) { job in
            job.logs.append(AIReasoningLogEntry(
                step: "正在生成 Prompt",
                status: .requesting,
                detail: "正在组装汇报需求清单、AI 读取范围、外部证据、记忆和当前任务表格事实。"
            ))
        }
        let promptSession = session
        let promptContext = context
        let promptWorkspace = workspace
        let prompt = await Task.detached(priority: .userInitiated) {
            if isSimpleReport {
                AnalysisSessionAIService.buildSimpleReportPrompt(
                    session: promptSession,
                    pack: promptContext.pack,
                    task: promptContext.task,
                    reports: promptContext.reports,
                    workspace: promptWorkspace,
                    contextMode: contextMode,
                    reportScope: reportScope
                )
            } else {
                AnalysisSessionAIService.buildMemoPrompt(
                    session: promptSession,
                    pack: promptContext.pack,
                    task: promptContext.task,
                    reports: promptContext.reports,
                    workspace: promptWorkspace,
                    contextMode: contextMode,
                    reportScope: reportScope
                )
            }
        }.value + "\n\n\(notebookRun.promptMarkdown)"
        updatePersistentAIJob(job.id, saveImmediately: false) { job in
            job.payload.prompt = prompt
            job.payload.coverageSnapshot = coverageSnapshot
        }
        guard !isPersistentAIJobCancelled(job.id) else { return }

        updatePersistentAIJob(job.id, saveImmediately: false) { job in
            job.logs.append(AIReasoningLogEntry(
                step: isSimpleReport ? "正在生成简洁汇报" : "正在生成完整汇报",
                status: .requesting,
                detail: "报告资料已准备完成，正在请求 AI 生成\(reportKindName)。"
            ))
        }

        let queue = AIJobQueue(maxAttempts: job.maxImmediateAttempts)
        let validationReports = context.reports
        let validationUserRequest = reportRequest
        let reportValidation: (String) -> [String] = { output in
            AggregationConsistencyValidator.validate(
                output: output,
                userRequest: validationUserRequest,
                reports: validationReports,
                notebookRun: notebookRun
            )
        }
        let reportCorrectionPrompt: (_ originalPrompt: String, _ output: String, _ warnings: [String]) -> String = { originalPrompt, output, warnings in
            AggregationConsistencyValidator.correctionPrompt(
                originalPrompt: originalPrompt,
                output: output,
                warnings: warnings,
                notebookRun: notebookRun
            )
        }
        let result = try await queue.runTextJob(
            prompt: prompt,
            settings: workspace.aiSettings,
            jobType: job.kind.label,
            validation: reportValidation,
            correctionPrompt: reportCorrectionPrompt
        )
        guard !isPersistentAIJobCancelled(job.id) else { return }
        let formattedOutput = AnalysisOutputTextFormatter.normalizedPercentages(in: result.output)
        let memoryEvidence = smartMemoryEvidence(
            pack: context.pack,
            task: context.task,
            session: session,
            reports: context.reports,
            userText: job.payload.userMessage.nilIfBlank ?? session.reportRequirementDigest?.markdown ?? session.goal
        )
        updateAnalysisSession(sessionID: sessionID) { session in
            if isSimpleReport {
                session.simpleReportMarkdown = formattedOutput
                session.lastSimpleReportGeneratedAt = Date()
                session.status = session.finalReportMarkdown.nilIfBlank == nil ? .waitingForUser : .reportReady
            } else {
                session.finalMemoMarkdown = formattedOutput
                session.finalReportMarkdown = formattedOutput
                session.lastReportGeneratedAt = Date()
                session.status = .reportReady
            }
            session.messages.append(AnalysisSessionMessage(
                role: .assistant,
                kind: isSimpleReport ? .simpleReport : .aiMemo,
                content: formattedOutput,
                evidence: AnalysisSessionAIService.evidence(
                    for: context.reports,
                    workspace: workspace,
                    businessSpaceID: context.task?.businessSpaceID ?? context.pack.businessSpaceID ?? session.businessSpaceID
                ) + memoryEvidence + [
                    AnalysisSessionEvidence(
                        sourceType: "计算证据",
                        title: "本轮 Notebook/SQL 计算证据",
                        detail: notebookRun.evidenceMarkdown,
                        sourceID: notebookRun.id.uuidString
                    ),
                    AnalysisSessionEvidence(
                        sourceType: "数据覆盖",
                        title: "本轮 AI 读取范围",
                        detail: AnalysisCoverageSnapshotBuilder.aiReadRangeMarkdown(coverageSnapshot),
                        sourceID: coverageSnapshot.id.uuidString
                    )
                ]
            ))
        }
        var record = result.record
        record.id = job.id
        insertAIJobRecord(record, packID: context.pack.id, targetID: sessionID, targetName: job.targetName)
        if isSimpleReport {
            markPersistentAIJobCompleted(job.id, record: record, detail: "简洁汇报已生成并写入当前会话。")
            statusText = "简洁汇报已生成，可点击导出简洁汇报，导出后会自动定位文件"
        } else {
            writeMemo(formattedOutput, for: context.pack.id, taskID: context.task?.id)
            markPersistentAIJobCompleted(job.id, record: record, detail: "完整汇报已生成并写入当前任务。")
            enqueuePersistentAIJob(
                kind: .opportunityExtraction,
                payload: PersistentAIJobPayload(
                    aiOutput: formattedOutput,
                    sessionID: sessionID,
                    packID: context.pack.id,
                    taskID: context.task?.id,
                    targetName: job.targetName,
                    contextMode: .reportGeneration
                )
            )
            statusText = "完整汇报已生成，可点击导出完整汇报，导出后会自动定位文件；机会评分已进入后台任务队列"
        }
    }

    func executeOpportunityJob(_ job: PersistentAIJob) async throws {
        guard let sessionID = job.payload.sessionID,
              let session = workspace.analysisSessions.first(where: { $0.id == sessionID }),
              let context = analysisSessionContext(for: session) else {
            throw AIAnalysisError.invalidResponse("机会评分任务缺少会话上下文。")
        }
        let result = try await AIOpportunityExtractionService.extract(
            aiOutput: job.payload.aiOutput,
            session: session,
            pack: context.pack,
            task: context.task,
            reports: context.reports,
            workspace: workspace,
            settings: workspace.aiSettings
        )
        guard !isPersistentAIJobCancelled(job.id) else { return }
        writeOpportunities(result.opportunities, for: context.pack.id, taskID: job.payload.taskID ?? context.task?.id)
        var record = result.record
        record.id = job.id
        insertAIJobRecord(record, packID: context.pack.id, targetID: sessionID, targetName: job.targetName)
        appendAnalysisSessionMessage(
            sessionID: sessionID,
            AnalysisSessionMessage(
                role: .system,
                kind: .systemCoverage,
                content: result.opportunities.isEmpty
                    ? "AI 已完成机会评分抽取：本轮未形成可排序机会。可以继续追问，或补充数据后重试。"
                    : "AI 已生成 \(result.opportunities.count) 个结构化机会评分，已同步到机会评分页和当前任务。"
            )
        )
        if workspace.analysisSessions.first(where: { $0.id == sessionID })?.status == .analyzing {
            setAnalysisSessionStatus(sessionID, .waitingForUser)
        }
        markPersistentAIJobCompleted(job.id, record: record, detail: "机会评分已写入当前任务。")
        statusText = result.opportunities.isEmpty ? "AI 分析已完成；本轮未形成可排序机会" : "AI 分析和机会评分已完成"
    }

    func executeBusinessSpaceProfileJob(_ job: PersistentAIJob) async throws {
        guard let spaceID = job.payload.businessSpaceID,
              let space = workspace.businessSpaces.first(where: { $0.id == spaceID }) else {
            throw AIAnalysisError.invalidResponse("业务空间识别任务缺少业务空间。")
        }
        let queue = AIJobQueue(maxAttempts: job.maxImmediateAttempts)
        let result = try await queue.runTextJob(
            prompt: job.payload.prompt,
            settings: workspace.aiSettings,
            jobType: job.kind.label,
            validation: { raw in
                BusinessSpaceAIService.parseProfileDraft(raw, fallback: space) == nil ? ["业务空间识别必须输出可解析 JSON 对象。"] : []
            },
            correctionPrompt: { originalPrompt, output, warnings in
                """
                业务空间识别结果没有通过校验，请只输出修正后的 JSON 对象。
                校验问题：\(warnings.joined(separator: "；"))

                原始要求：
                \(originalPrompt)

                上次输出：
                \(output)
                """
            }
        )
        guard let profile = BusinessSpaceAIService.parseProfileDraft(result.output, fallback: space),
              let index = workspace.businessSpaces.firstIndex(where: { $0.id == spaceID }) else {
            throw AIAnalysisError.invalidResponse("AI 业务空间识别结果无法解析。")
        }
        let map = profile.mapDraft
        workspace.businessSpaces[index].name = profile.name
        workspace.businessSpaces[index].countryRegion = profile.countryRegion
        workspace.businessSpaces[index].timeZoneIdentifier = BusinessTimeZoneResolver.resolve(
            timeZoneIdentifier: profile.timeZoneIdentifier,
            countryRegion: profile.countryRegion,
            businessBackground: workspace.businessSpaces[index].businessBackground,
            businessSpaceName: profile.name
        )
        workspace.businessSpaces[index].currencyCode = profile.currencyCode
        workspace.businessSpaces[index].primaryLanguagesText = profile.primaryLanguagesText
        workspace.businessSpaces[index].domains = map.domains
        workspace.businessSpaces[index].domainLinks = map.links
        workspace.businessSpaces[index].metricClassificationRulesText = map.metricRules
        workspace.businessSpaces[index].anomalyRulesText = map.anomalyRules
        workspace.businessSpaces[index].analysisGuardrailsText = map.guardrails
        workspace.businessSpaces[index].recommendedSourceCategories = map.sourceCategories
        workspace.businessSpaces[index].generatedSummary = "AI 已识别基础配置：\(map.summary)"
        workspace.businessSpaces[index].updatedAt = Date()
        save()
        var record = result.record
        record.id = job.id
        markPersistentAIJobCompleted(job.id, record: record, detail: "AI 已识别国家、时区、币种、语言和业务地图。")
        statusText = "AI 已识别业务空间基础配置，可展开检查并继续配置数据源"
    }

    func executeBusinessMapJob(_ job: PersistentAIJob) async throws {
        guard let spaceID = job.payload.businessSpaceID else {
            throw AIAnalysisError.invalidResponse("业务地图任务缺少业务空间 ID。")
        }
        let queue = AIJobQueue(maxAttempts: job.maxImmediateAttempts)
        let result = try await queue.runTextJob(
            prompt: job.payload.prompt,
            settings: workspace.aiSettings,
            jobType: job.kind.label,
            validation: { _ in [] },
            correctionPrompt: { originalPrompt, output, _ in "\(originalPrompt)\n\n上次输出：\(output)" }
        )
        guard let index = workspace.businessSpaces.firstIndex(where: { $0.id == spaceID }) else {
            throw AIAnalysisError.invalidResponse("业务空间不存在或已被删除。")
        }
        workspace.businessSpaces[index].generatedSummary = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        workspace.businessSpaces[index].updatedAt = Date()
        save()
        var record = result.record
        record.id = job.id
        markPersistentAIJobCompleted(job.id, record: record, detail: "AI 业务地图摘要已写入业务空间。")
        statusText = "AI 业务地图已生成，可继续手动编辑业务域、链路和规则"
    }

    func executeReferenceSourceRecommendationJob(_ job: PersistentAIJob) async throws {
        guard let spaceID = job.payload.businessSpaceID,
              let space = workspace.businessSpaces.first(where: { $0.id == spaceID }) else {
            throw AIAnalysisError.invalidResponse("数据源推荐任务缺少业务空间上下文。")
        }
        let queue = AIJobQueue(maxAttempts: job.maxImmediateAttempts)
        let result = try await queue.runTextJob(
            prompt: job.payload.prompt,
            settings: workspace.aiSettings,
            jobType: job.kind.label,
            validation: { _ in [] },
            correctionPrompt: { originalPrompt, output, _ in "\(originalPrompt)\n\n上次输出：\(output)" }
        )
        let aiCandidates = BusinessSpaceAIService.parseReferenceSourceRecommendations(result.output, for: space)
        guard !aiCandidates.isEmpty else {
            throw AIAnalysisError.invalidResponse("AI 未返回可解析的数据源候选。")
        }
        let aiResult = mergeReferenceSources(aiCandidates)
        save()
        var record = result.record
        record.id = job.id
        markPersistentAIJobCompleted(job.id, record: record, detail: "已补充 \(aiResult.added) 个候选数据源，更新 \(aiResult.updated) 个。")
        statusText = "AI 已补充 \(aiResult.added) 个 RivalRadar 风格候选数据源，更新 \(aiResult.updated) 个。请测试此源或手动启用"
    }

    func executeExternalEventImpactJob(_ job: PersistentAIJob) async throws {
        guard let packID = job.payload.packID,
              let pack = workspace.dataPacks.first(where: { $0.id == packID }) else {
            throw AIAnalysisError.invalidResponse("外部事件影响任务缺少数据包。")
        }
        let sourceByID = Dictionary(uniqueKeysWithValues: workspace.referenceSources.map { ($0.id, $0) })
        let businessSpaceID = pack.businessSpaceID ?? selectedBusinessSpace?.id
        let scopedReferenceItems = workspace.referenceItems.filter {
            $0.isVisible(in: businessSpaceID, sourceByID: sourceByID)
        }
        let result = await ExternalEventImpactAIService.analyze(
            pack: currentTaskAnalysisPack(from: pack),
            referenceItems: scopedReferenceItems,
            settings: workspace.aiSettings
        )
        if let packIndex = workspace.dataPacks.firstIndex(where: { $0.id == packID }) {
            workspace.dataPacks[packIndex].externalEventImpacts = result.records.sorted { $0.confidence > $1.confidence }
            save()
        }
        if let record = result.jobRecord {
            var updatedRecord = record
            updatedRecord.id = job.id
            insertAIJobRecord(updatedRecord, packID: packID, targetID: packID, targetName: pack.name)
            markPersistentAIJobCompleted(job.id, record: updatedRecord, detail: "外部事件影响分析已写入数据包。")
        } else {
            var record = AIJobRecord(jobType: job.kind.label, targetID: packID, targetName: pack.name, status: .completed, attemptCount: 1, maxAttempts: job.maxImmediateAttempts)
            record.logs.append(AIReasoningLogEntry(step: job.kind.label, status: .completed, detail: "没有可分析的外部事件，或使用本地兜底结果。"))
            markPersistentAIJobCompleted(job.id, record: record, detail: "外部事件影响分析已完成。")
        }
    }

    func executeTableFirstAnalysisJob(_ job: PersistentAIJob) async throws {
        guard let packID = job.payload.packID,
              let reportID = job.payload.reportID,
              let packIndex = workspace.dataPacks.firstIndex(where: { $0.id == packID }),
              let report = workspace.dataPacks[packIndex].importedReports.first(where: { $0.id == reportID }) else {
            throw AIAnalysisError.invalidResponse("AI 表格理解任务缺少数据包或报表。")
        }
        let result = await AITableFirstAnalysisService.analyze(report: report, settings: workspace.aiSettings)
        guard let updatedPackIndex = workspace.dataPacks.firstIndex(where: { $0.id == packID }),
              let reportIndex = workspace.dataPacks[updatedPackIndex].importedReports.firstIndex(where: { $0.id == reportID }) else {
            throw AIAnalysisError.invalidResponse("AI 表格理解完成后，目标报表已不存在。")
        }
        workspace.dataPacks[updatedPackIndex].importedReports[reportIndex] = result.report
        refreshAuditState(for: &workspace.dataPacks[updatedPackIndex])

        if let taskID = job.payload.taskID,
           let taskIndex = workspace.dataPacks[updatedPackIndex].analysisTasks.firstIndex(where: { $0.id == taskID }) {
            let reports = taskReports(in: workspace.dataPacks[updatedPackIndex], task: workspace.dataPacks[updatedPackIndex].analysisTasks[taskIndex])
            let allObserved = !reports.isEmpty && reports.allSatisfy { $0.aiFirstAnalysis != nil }
            if allObserved {
                workspace.dataPacks[updatedPackIndex].analysisTasks[taskIndex].aiObservationGeneratedAt = Date()
                workspace.dataPacks[updatedPackIndex].analysisTasks[taskIndex].aiObservationSignature = aiObservationSignature(
                    for: workspace.dataPacks[updatedPackIndex].analysisTasks[taskIndex],
                    reports: reports
                )
                workspace.dataPacks[updatedPackIndex].analysisTasks[taskIndex].updatedAt = Date()
                refreshTaskBusinessLinks(for: &workspace.dataPacks[updatedPackIndex], forceReview: false)
                refreshAuditState(for: &workspace.dataPacks[updatedPackIndex])
                statusText = "AI 预读已生成。可以继续校准任务，或在分析会话发送给 AI"
            }
        }
        save()

        if let record = result.jobRecord {
            var updatedRecord = record
            updatedRecord.id = job.id
            insertAIJobRecord(updatedRecord, packID: packID, targetID: reportID, targetName: report.displayName)
            markPersistentAIJobCompleted(job.id, record: updatedRecord, detail: "AI 表格理解已写入报表。")
        } else {
            var record = AIJobRecord(jobType: job.kind.label, targetID: reportID, targetName: report.displayName, status: .completed, attemptCount: 1, maxAttempts: job.maxImmediateAttempts)
            record.id = job.id
            record.logs.append(AIReasoningLogEntry(step: job.kind.label, status: .completed, detail: "AI 表格理解已完成。"))
            markPersistentAIJobCompleted(job.id, record: record, detail: "AI 表格理解已写入报表。")
        }
    }

    func executeMetricSemanticExtractionJob(_ job: PersistentAIJob) async throws {
        guard let packID = job.payload.packID,
              let pack = workspace.dataPacks.first(where: { $0.id == packID }) else {
            throw AIAnalysisError.invalidResponse("指标语义抽取任务缺少数据包。")
        }
        let task = job.payload.taskID.flatMap { taskID in
            pack.analysisTasks.first(where: { $0.id == taskID })
        }
        let reports: [ImportedReport]
        if let sessionID = job.payload.sessionID,
           let session = workspace.analysisSessions.first(where: { $0.id == sessionID }),
           let context = analysisSessionContext(for: session) {
            reports = context.reports
        } else if let task {
            reports = taskReports(in: pack, task: task)
        } else {
            reports = pack.importedReports
        }

        let extractedCount = upsertMetricSemanticsFromUserMessage(
            job.payload.userMessage,
            messageID: job.payload.messageID ?? job.id,
            reports: reports,
            pack: pack,
            task: task
        )
        if extractedCount > 0, let sessionID = job.payload.sessionID {
            appendAnalysisSessionMessage(
                sessionID: sessionID,
                AnalysisSessionMessage(role: .system, kind: .adoption, content: "已从你的说明中沉淀 \(extractedCount) 条指标语义到当前业务空间。")
            )
        }
        var record = AIJobRecord(
            jobType: job.kind.label,
            targetID: job.payload.businessSpaceID ?? job.payload.packID,
            targetName: job.payload.targetName.isEmpty ? job.kind.label : job.payload.targetName,
            status: .completed,
            attemptCount: 1,
            maxAttempts: job.maxImmediateAttempts
        )
        record.id = job.id
        record.logs.append(AIReasoningLogEntry(
            step: job.kind.label,
            status: .completed,
            detail: extractedCount > 0 ? "已沉淀 \(extractedCount) 条指标语义。" : "本轮没有检测到明确的指标口径说明。"
        ))
        markPersistentAIJobCompleted(job.id, record: record, detail: "指标语义抽取已完成。")
    }

    func executeUserQuestionMemoryExtractionJob(_ job: PersistentAIJob) async throws {
        guard let packID = job.payload.packID,
              let pack = workspace.dataPacks.first(where: { $0.id == packID }) else {
            throw AIAnalysisError.invalidResponse("提问记忆抽取任务缺少数据包。")
        }
        let reports: [ImportedReport]
        if let taskID = job.payload.taskID,
           let task = pack.analysisTasks.first(where: { $0.id == taskID }) {
            reports = pack.importedReports.filter { task.activeReportIDs.contains($0.id) }
        } else {
            reports = pack.importedReports
        }
        let candidates = SmartMemoryExtractionService.extractCandidates(
            from: job.payload.userMessage,
            sessionID: job.payload.sessionID,
            messageID: job.payload.messageID,
            businessSpaceID: job.payload.businessSpaceID ?? pack.businessSpaceID ?? workspace.selectedBusinessSpaceID,
            reports: reports
        )
        for candidate in candidates {
            upsertSmartMemoryCandidate(candidate)
        }
        if !candidates.isEmpty, let sessionID = job.payload.sessionID {
            appendAnalysisSessionMessage(
                sessionID: sessionID,
                AnalysisSessionMessage(
                    role: .system,
                    kind: .adoption,
                    content: "已从你的明确要求中识别 \(candidates.count) 条智能记忆候选。未采纳前只作为当前会话提示，不会污染长期记忆；可在“记忆中心”采纳、忽略或编辑。"
                )
            )
        }
        var record = AIJobRecord(
            jobType: job.kind.label,
            targetID: job.payload.businessSpaceID ?? job.payload.packID,
            targetName: job.payload.targetName.isEmpty ? job.kind.label : job.payload.targetName,
            status: .completed,
            attemptCount: 1,
            maxAttempts: job.maxImmediateAttempts
        )
        record.id = job.id
        record.logs.append(AIReasoningLogEntry(
            step: job.kind.label,
            status: .completed,
            detail: candidates.isEmpty ? "本轮没有检测到明确长期偏好。" : "已生成 \(candidates.count) 条智能记忆候选。"
        ))
        markPersistentAIJobCompleted(job.id, record: record, detail: "提问记忆抽取已完成。")
    }

    func upsertSmartMemoryCandidate(_ candidate: SmartMemoryCandidate) {
        let key = "\(candidate.kind.rawValue)|\(candidate.businessSpaceID?.uuidString ?? "global")|\(candidate.title.normalizedKey)|\(candidate.content.normalizedKey)"
        if let index = workspace.smartMemoryCandidates.firstIndex(where: { existing in
            "\(existing.kind.rawValue)|\(existing.businessSpaceID?.uuidString ?? "global")|\(existing.title.normalizedKey)|\(existing.content.normalizedKey)" == key
        }) {
            workspace.smartMemoryCandidates[index].updatedAt = Date()
            workspace.smartMemoryCandidates[index].confidence = max(workspace.smartMemoryCandidates[index].confidence, candidate.confidence)
            workspace.smartMemoryCandidates[index].status = workspace.smartMemoryCandidates[index].status == .ignored ? .ignored : candidate.status
        } else {
            workspace.smartMemoryCandidates.insert(candidate, at: 0)
        }
        workspace.smartMemoryCandidates = Array(workspace.smartMemoryCandidates.sorted { $0.updatedAt > $1.updatedAt }.prefix(400))
        save()
    }

    func markPersistentAIJobCompleted(_ jobID: UUID, record: AIJobRecord, detail: String) {
        var completedJob: PersistentAIJob?
        updatePersistentAIJob(jobID) { job in
            var updatedRecord = record
            updatedRecord.id = job.id
            updatedRecord.targetID = job.targetID
            updatedRecord.targetName = job.targetName
            job.status = .completed
            job.attemptCount = updatedRecord.attemptCount
            job.lastError = ""
            job.record = updatedRecord
            job.logs.append(contentsOf: updatedRecord.logs)
            job.logs.append(AIReasoningLogEntry(step: job.kind.label, status: .completed, detail: detail))
            job.record.status = .completed
            job.record.logs = job.logs
            completedJob = job
        }
        if let completedJob {
            notifyPersistentAIJobCompletionIfNeeded(completedJob)
        }
    }

    func handlePersistentAIJobFailure(_ jobID: UUID, error: Error) {
        let queueRecord = (error as? AIJobQueueError)?.record
        let retryable = AIJobQueue.isRetryable(error)
        let message = error.localizedDescription
        let failedJob = workspace.persistentAIJobs.first { $0.id == jobID }
        updatePersistentAIJob(jobID) { job in
            if let queueRecord {
                var updatedRecord = queueRecord
                updatedRecord.id = job.id
                updatedRecord.targetID = job.targetID
                updatedRecord.targetName = job.targetName
                job.attemptCount = queueRecord.attemptCount
                job.record = updatedRecord
                job.logs.append(contentsOf: updatedRecord.logs)
            }
            job.lastError = message
            if retryable {
                job.delayedRetryCount += 1
                job.status = .waiting
                job.nextRunAt = Date().addingTimeInterval(delayedRetryInterval(for: job.delayedRetryCount))
                job.logs.append(AIReasoningLogEntry(
                    step: job.kind.label,
                    status: .waiting,
                    detail: "可恢复错误：\(message)。已安排后台延迟重试。"
                ))
            } else {
                job.status = .needsUserAction
                job.nextRunAt = nil
                job.logs.append(AIReasoningLogEntry(
                    step: job.kind.label,
                    status: .needsUserAction,
                    detail: message
                ))
            }
        }
        if !retryable,
           let sessionID = failedJob?.payload.sessionID,
           let failedKind = failedJob?.kind,
           failedKind == .analysisSession || failedKind == .memo || failedKind == .simpleReportGeneration {
            setAnalysisSessionStatus(sessionID, .waitingForUser)
        }
        statusText = retryable ? "AI 任务失败，已进入后台重试队列：\(message)" : "AI 任务需要用户处理：\(message)"
    }

    func delayedRetryInterval(for retryCount: Int) -> TimeInterval {
        switch retryCount {
        case 1: return 5 * 60
        case 2: return 15 * 60
        case 3: return 30 * 60
        case 4: return 60 * 60
        case 5: return 2 * 60 * 60
        default: return 6 * 60 * 60
        }
    }

    func latestAIJobRecords(for pack: DataPack?, limit: Int = 12) -> [AIJobRecord] {
        let packRecords = pack?.aiJobRecords ?? []
        let persistentRecords = workspace.persistentAIJobs.map(\.record)
        var seen = Set<UUID>()
        return (persistentRecords + workspace.aiJobRecords + packRecords)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }

    func cancelAIJob(_ jobID: UUID) {
        if let job = workspace.persistentAIJobs.first(where: { $0.id == jobID }) {
            persistentAIJobTasks[jobID]?.cancel()
            persistentAIJobTasks[jobID] = nil
            if runningPersistentAIJobID == jobID {
                runningPersistentAIJobID = nil
                isRunningAI = false
            }
            updatePersistentAIJob(jobID) { job in
                job.status = .cancelled
                job.nextRunAt = nil
                job.lastError = "用户已取消此任务。"
                job.logs.append(AIReasoningLogEntry(step: job.kind.label, status: .cancelled, detail: job.lastError))
            }
            if let sessionID = job.payload.sessionID,
               job.kind == .analysisSession || job.kind == .memo || job.kind == .simpleReportGeneration || job.kind == .opportunityExtraction {
                setAnalysisSessionStatus(sessionID, .waitingForUser)
                appendAnalysisSessionMessage(
                    sessionID: sessionID,
                    AnalysisSessionMessage(
                        role: .system,
                        kind: .systemCoverage,
                        content: "本轮 AI 分析已由用户停止，未生成结论。输入内容已保留，可以修改后继续发送。"
                    )
                )
            }
            statusText = "已取消 AI 任务"
            schedulePersistentAIJobs()
            return
        }
        updateAIJobRecord(jobID) { record in
            record.status = .cancelled
            record.updatedAt = Date()
            record.lastError = "用户已取消此任务。正在执行中的网络请求可能仍会返回，但该记录不会再作为待处理任务展示。"
            record.logs.append(AIReasoningLogEntry(step: record.jobType, status: .cancelled, detail: record.lastError))
        }
        statusText = "已取消 AI 任务记录"
    }

    func cancelCurrentAnalysisSessionAI() {
        guard let job = runningAIJobForSelectedAnalysisSession else {
            statusText = "当前会话没有正在执行的 AI 任务"
            return
        }
        cancelAIJob(job.id)
    }

    func retryAIJob(_ jobID: UUID) {
        if workspace.persistentAIJobs.contains(where: { $0.id == jobID }) {
            updatePersistentAIJob(jobID) { job in
                job.status = .waiting
                job.nextRunAt = Date()
                job.lastError = ""
                job.logs.append(AIReasoningLogEntry(step: job.kind.label, status: .waiting, detail: "用户手动重试，使用原始任务 payload 重新执行。"))
            }
            statusText = "AI 任务已重新入队"
            schedulePersistentAIJobs()
            return
        }
        guard let job = workspace.aiJobRecords.first(where: { $0.id == jobID }) ??
            workspace.dataPacks.flatMap(\.aiJobRecords).first(where: { $0.id == jobID }) else {
            statusText = "未找到 AI 任务"
            return
        }
        guard !isRunningAI else {
            statusText = "AI 正在执行，请等待当前任务完成后再重试"
            return
        }
        if let sessionID = job.targetID,
           let session = workspace.analysisSessions.first(where: { $0.id == sessionID }) {
            workspace.selectedAnalysisSessionID = session.id
            selectedPackID = session.packID
            save()
            if job.jobType.contains("Memo") || job.jobType.contains("报告") {
                generateMemoFromSelectedAnalysisSession()
                return
            }
            if job.jobType.contains("机会") {
                regenerateOpportunitiesForSelectedSession()
                return
            }
            if let latestUserMessage = session.messages.last(where: { $0.role == .user && $0.kind == .userRequest }) {
                sendAnalysisSessionMessage(latestUserMessage.content)
                return
            }
        }
        statusText = "这个 AI 任务暂不支持一键重试，请在分析会话中重新发送需求"
    }

    func confirmMetricSemanticProfile(reportID: UUID, metricName: String) {
        updateImportedReport(reportID: reportID) { report in
            if let index = report.metricSemanticProfiles.firstIndex(where: { $0.metricName.normalizedKey == metricName.normalizedKey }) {
                report.metricSemanticProfiles[index].isUserConfirmed = true
                report.metricSemanticProfiles[index].updatedAt = Date()
                report.metricSemanticProfiles[index].source = "user_confirmed"
                report.metricSemanticProfiles[index].confidence = max(report.metricSemanticProfiles[index].confidence, 0.9)
            } else {
                report.metricSemanticProfiles.append(MetricSemanticProfile(
                    metricName: metricName,
                    source: "user_confirmed",
                    confidence: 0.9,
                    isUserConfirmed: true,
                    updatedAt: Date()
                ))
            }
        }
        statusText = "已确认指标语义：\(metricName)"
    }

    func currentTaskAIObservationIsCurrent(in pack: DataPack) -> Bool {
        guard let task = currentAnalysisTask(in: pack) else { return false }
        let reports = taskReports(in: pack, task: task)
        guard !reports.isEmpty,
              let generatedAt = task.aiObservationGeneratedAt,
              task.aiObservationSignature == aiObservationSignature(for: task, reports: reports) else {
            return false
        }
        return reports.allSatisfy { report in
            guard let analysis = report.aiFirstAnalysis else { return false }
            return analysis.generatedAt >= generatedAt.addingTimeInterval(-1)
        }
    }

    func currentTaskAIObservationNeedsUpdate(in pack: DataPack) -> Bool {
        guard let task = currentAnalysisTask(in: pack) else { return false }
        let reports = taskReports(in: pack, task: task)
        guard !reports.isEmpty, task.aiObservationGeneratedAt != nil else { return false }
        return !currentTaskAIObservationIsCurrent(in: pack)
    }

    func currentTaskAIObservationStatusText(in pack: DataPack) -> String {
        guard let task = currentAnalysisTask(in: pack) else { return "无分析任务" }
        let reports = taskReports(in: pack, task: task)
        guard !reports.isEmpty else { return "未选择报表" }
        if currentTaskAIObservationIsCurrent(in: pack) {
            return "已生成"
        }
        if task.aiObservationGeneratedAt != nil {
            return "需要更新"
        }
        return "未生成"
    }

    func aiObservationWarningText(for pack: DataPack?) -> String? {
        guard let pack,
              let task = currentAnalysisTask(in: pack) else { return nil }
        let reports = taskReports(in: pack, task: task)
        guard !reports.isEmpty else { return nil }
        guard !currentTaskAIObservationIsCurrent(in: pack) else { return nil }
        if task.aiObservationGeneratedAt == nil {
            return "AI 预读尚未生成。可以直接发送给 AI 分析；如需先让 AI 预读表格，请点击“生成 AI 预读”。"
        }
        return "AI 预读需要更新。当前任务的报表、角色或本次分析目标已变化；可以直接发送给 AI 分析，或重新生成预读。"
    }

    func unconfirmedReportCount(in pack: DataPack?) -> Int {
        pack?.importedReports.filter { semanticNeedsHumanReview($0) }.count ?? 0
    }

    func shouldUseAnalysisHarness(
        contextMode: AnalysisContextMode,
        sourcePolicy: AnalysisContextSourcePolicy,
        userMessage: String,
        referencedMessage: AnalysisSessionMessage?,
        selectedReportCount: Int
    ) -> Bool {
        guard AnalysisHarnessFeatureFlags.analysisHarnessEnabled,
              selectedReportCount > 0,
              referencedMessage == nil else {
            return false
        }
        switch contextMode {
        case .fullReanalysis:
            return AnalysisHarnessRouter.userMessageNeedsVerifiedAnalysis(userMessage, sourcePolicy: sourcePolicy)
        case .quickFollowUp, .cachedFollowUp:
            return AnalysisHarnessRouter.userMessageNeedsVerifiedAnalysis(userMessage, sourcePolicy: sourcePolicy)
        case .reportGeneration:
            return false
        }
    }

    func userMessageLooksLikeTableComputation(_ text: String) -> Bool {
        AnalysisHarnessRouter.userMessageLooksLikeTableComputation(text)
    }
}
