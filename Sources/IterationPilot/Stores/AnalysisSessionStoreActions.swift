import AppKit
import Foundation

@MainActor
extension ProductWorkflowStore {
    func createAnalysisTask(name: String? = nil) {
        updateSelectedPack { pack in
            ensureAnalysisTaskExists(in: &pack)
            let nextIndex = pack.analysisTasks.count + 1
            let space = selectedBusinessSpace
            let task = AnalysisTask.emptyDefault(
                name: name?.nilIfBlank ?? "分析任务 \(nextIndex)",
                businessSpaceID: space?.id,
                businessSpaceSnapshot: space?.snapshot
            )
            pack.analysisTasks.insert(task, at: 0)
            pack.selectedAnalysisTaskID = task.id
            markPackNeedsReview(&pack)
            refreshTaskBusinessLinks(for: &pack, forceReview: true)
        }
        createAnalysisSessionFromCurrentTask()
        statusText = "已创建空白分析任务。下一步：选择本次要分析的表"
    }

    func selectAnalysisTask(taskID: UUID) {
        updateSelectedPack { pack in
            guard pack.analysisTasks.contains(where: { $0.id == taskID }) else { return }
            pack.selectedAnalysisTaskID = taskID
            refreshTaskBusinessLinks(for: &pack, forceReview: false)
            if let task = currentAnalysisTask(in: pack) {
                pack.analysisReport = task.analysisReport.summary.isEmpty ? pack.analysisReport : task.analysisReport
                pack.decisionMemo = task.decisionMemo.markdown.isEmpty ? pack.decisionMemo : task.decisionMemo
                pack.reportRelationshipProfile = task.relationshipProfile
            }
        }
        selectOrCreateAnalysisSessionForCurrentTask()
        statusText = "已切换分析任务。请检查本次分析表和目标"
    }

    func sessionsForCurrentPack(includeArchived: Bool = false, includeAllHistory: Bool = false) -> [AnalysisSession] {
        let statusFilter: (AnalysisSession) -> Bool = { session in
            includeArchived || session.status != .archived
        }
        if includeAllHistory {
            return workspace.analysisSessions
                .filter { statusFilter($0) && analysisSessionBelongsToSelectedBusinessSpace($0) }
                .sorted { $0.updatedAt > $1.updatedAt }
        }
        guard let selectedPackID else {
            return workspace.analysisSessions
                .filter { statusFilter($0) && analysisSessionBelongsToSelectedBusinessSpace($0) }
                .sorted { $0.updatedAt > $1.updatedAt }
        }
        return workspace.analysisSessions
            .filter { $0.packID == selectedPackID && statusFilter($0) && analysisSessionBelongsToSelectedBusinessSpace($0) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func selectAnalysisSession(sessionID: UUID) {
        guard let session = workspace.analysisSessions.first(where: { $0.id == sessionID }),
              analysisSessionBelongsToSelectedBusinessSpace(session) else {
            statusText = "该会话不属于当前业务空间，已阻止跨空间切换"
            return
        }
        workspace.selectedAnalysisSessionID = session.id
        guard workspace.dataPacks.contains(where: { $0.id == session.packID }) else {
            save()
            statusText = "已切换历史会话，原数据包已删除"
            return
        }
        selectedPackID = session.packID
        if let taskID = session.taskID {
            updateSelectedPack { pack in
                if pack.analysisTasks.contains(where: { $0.id == taskID }) {
                    pack.selectedAnalysisTaskID = taskID
                }
            }
        } else {
            save()
        }
        statusText = "已切换分析会话"
    }

    func archiveAnalysisSession(sessionID: UUID) {
        guard let index = workspace.analysisSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        workspace.analysisSessions[index].status = .archived
        workspace.analysisSessions[index].updatedAt = Date()
        if workspace.selectedAnalysisSessionID == sessionID {
            workspace.selectedAnalysisSessionID = workspace.analysisSessions.first {
                $0.status != .archived && $0.id != sessionID
            }?.id
        }
        save()
        statusText = "已归档分析会话"
    }

    func restoreAnalysisSession(sessionID: UUID) {
        guard let index = workspace.analysisSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        workspace.analysisSessions[index].status = .draft
        workspace.analysisSessions[index].updatedAt = Date()
        workspace.selectedAnalysisSessionID = sessionID
        if workspace.dataPacks.contains(where: { $0.id == workspace.analysisSessions[index].packID }) {
            selectedPackID = workspace.analysisSessions[index].packID
        }
        save()
        statusText = "已恢复分析会话"
    }

    func deleteAnalysisSessionPermanently(sessionID: UUID) {
        guard let session = workspace.analysisSessions.first(where: { $0.id == sessionID }) else { return }
        workspace.analysisSessions.removeAll { $0.id == sessionID }
        if workspace.selectedAnalysisSessionID == sessionID {
            workspace.selectedAnalysisSessionID = workspace.analysisSessions.first { $0.status != .archived }?.id
        }
        save()
        statusText = "已永久删除分析会话：\(session.title)"
    }

    func ensureAnalysisSessionAfterReportImport() {
        let importStatusText = statusText
        updateSelectedPack { pack in
            ensureAnalysisTaskExists(in: &pack)
            refreshTaskRelationshipProfile(for: &pack, forceReview: false)
            refreshTaskBusinessLinks(for: &pack, forceReview: false)
            markPackNeedsReview(&pack)
        }
        guard let pack = selectedPack else { return }
        let currentSession = selectedAnalysisSession
        let currentTask = currentAnalysisTask(in: pack)
        let needsSession = currentSession == nil ||
            currentSession?.packID != pack.id ||
            (currentTask?.id != nil && currentSession?.taskID != currentTask?.id)
        if needsSession {
            createAnalysisSessionFromCurrentTask(initialGoal: currentTask?.goal)
        }
        requestedSidebarSelection = .sessions
        isAnalysisInfoSidebarVisible = false
        statusText = importStatusText
    }

    func createAnalysisSessionFromCurrentTask(initialGoal: String? = nil) {
        guard let selectedPack else {
            statusText = "请先选择或导入数据包"
            return
        }
        let task = currentAnalysisTask(in: selectedPack)
        let reports = task.map { taskReports(in: selectedPack, task: $0) } ?? []
        let goal = initialGoal?.nilIfBlank ?? task?.goal.nilIfBlank ?? ""
        let title = [
            task?.name.nilIfBlank,
            DateFormatting.shortDate.string(from: Date())
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
        let space = businessSpace(for: selectedPack, task: task)
        let session = AnalysisSession(
            packID: selectedPack.id,
            taskID: task?.id,
            businessSpaceID: space?.id,
            businessSpaceSnapshot: space?.snapshot,
            title: title.isEmpty ? "\(selectedPack.name) 分析会话" : title,
            goal: goal,
            selectedReportIDs: reports.map(\.id),
            messages: [
                AnalysisSessionMessage(
                    role: .system,
                    kind: .systemCoverage,
                    content: "已创建分析会话。业务空间：\(space?.name ?? "未设置")。当前任务选择 \(reports.count) 张报表。默认资料范围为“仅表格”，AI 会基于当前选表和本地计算证据回答；如需知识库或外部参照，可在输入框内切换资料范围。"
                )
            ],
            tags: [space?.name ?? "", selectedPack.name, task?.name ?? ""].filter { !$0.isEmpty }
        )
        workspace.analysisSessions.insert(session, at: 0)
        workspace.selectedAnalysisSessionID = session.id
        save()
        statusText = reports.isEmpty ? "已创建分析会话。下一步：选择本次要分析的表" : "已创建分析会话。下一步：在底部输入你要 AI 分析的问题"
    }

    func selectOrCreateAnalysisSessionForCurrentTask() {
        guard let selectedPack else { return }
        let task = currentAnalysisTask(in: selectedPack)
        if let taskID = task?.id,
           let existing = workspace.analysisSessions.first(where: {
               $0.packID == selectedPack.id && $0.taskID == taskID && $0.status != .archived
           }) {
            workspace.selectedAnalysisSessionID = existing.id
            save()
            return
        }
        createAnalysisSessionFromCurrentTask(initialGoal: task?.goal)
    }

    func updateSelectedAnalysisSessionGoal(
        _ goal: String,
        savePolicy: WorkspaceSavePolicy = .immediate,
        touchUpdatedAt: Bool = true
    ) {
        guard let sessionID = selectedAnalysisSession?.id else { return }
        updateAnalysisSessionGoal(
            sessionID: sessionID,
            goal,
            savePolicy: savePolicy,
            touchUpdatedAt: touchUpdatedAt
        )
    }

    func updateAnalysisSessionGoal(
        sessionID: UUID,
        _ goal: String,
        savePolicy: WorkspaceSavePolicy = .immediate,
        touchUpdatedAt: Bool = true
    ) {
        guard let index = workspace.analysisSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        guard workspace.analysisSessions[index].goal != goal else { return }
        workspace.analysisSessions[index].goal = goal
        if touchUpdatedAt {
            workspace.analysisSessions[index].updatedAt = Date()
        }
        let session = workspace.analysisSessions[index]
        if let packIndex = workspace.dataPacks.firstIndex(where: { $0.id == session.packID }) {
            let taskID = session.taskID ?? workspace.dataPacks[packIndex].selectedAnalysisTaskID
            if let taskID,
               let taskIndex = workspace.dataPacks[packIndex].analysisTasks.firstIndex(where: { $0.id == taskID }) {
                workspace.dataPacks[packIndex].analysisTasks[taskIndex].goal = goal
                if touchUpdatedAt {
                    workspace.dataPacks[packIndex].analysisTasks[taskIndex].updatedAt = Date()
                }
            }
        }
        save(policy: savePolicy)
    }

    func archiveSelectedAnalysisSession() {
        guard let sessionID = selectedAnalysisSession?.id else { return }
        archiveAnalysisSession(sessionID: sessionID)
    }

    func sendAnalysisSessionMessage(
        _ content: String,
        mode requestedMode: AnalysisContextMode? = nil,
        sourcePolicy requestedSourcePolicy: AnalysisContextSourcePolicy = .tableOnly,
        replyToMessageID: UUID? = nil
    ) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let createdSessionFromFirstMessage = selectedAnalysisSession == nil
        if createdSessionFromFirstMessage {
            createAnalysisSessionFromCurrentTask(initialGoal: trimmed)
        }
        guard let session = selectedAnalysisSession else { return }
        if createdSessionFromFirstMessage {
            syncAnalysisTaskGoalFromFirstQuestion(trimmed, sessionID: session.id)
        }
        guard hasConfiguredAI else {
            statusText = "请先在 AI 设置中填写 API Key，分析会话不会生成本地伪分析"
            return
        }
        guard blockingAIJob(for: session.id) == nil else {
            statusText = "当前会话正在分析，请等待本轮完成，或点击停止分析"
            return
        }
        guard let context = analysisSessionContext(for: session) else {
            statusText = "分析会话缺少对应数据包或任务"
            return
        }
        guard !context.reports.isEmpty else {
            statusText = "当前任务没有选择报表。请先加入至少 1 张表，再发送给 AI。"
            return
        }
        let referencedMessage = replyToMessageID.flatMap { id in
            session.messages.first { $0.id == id && $0.role == .assistant }
        }
        let effectiveMode = resolveAnalysisContextMode(
            requestedMode,
            userMessage: trimmed,
            session: session,
            pack: context.pack,
            task: context.task,
            reports: context.reports
        )

        let userMessage = AnalysisSessionMessage(
            role: .user,
            kind: .userRequest,
            content: trimmed,
            replyToMessageID: referencedMessage?.id,
            quotedMessageSummary: referencedMessage.map { messageSummary($0.content, limit: 260) }
        )
        appendAnalysisSessionMessage(
            sessionID: session.id,
            userMessage
        )
        if let referencedMessage, userMessageLooksLikeCorrection(trimmed) {
            markAnalysisSessionMessage(
                sessionID: session.id,
                messageID: referencedMessage.id,
                correctionStatus: .challenged,
                supersededByMessageID: nil,
                savedCorrectionMemoryID: nil
            )
        }
        setAnalysisSessionStatus(session.id, .analyzing)
        enqueueAnalysisSessionAIJob(
            userMessage: trimmed,
            userMessageID: userMessage.id,
            sessionID: session.id,
            pack: context.pack,
            task: context.task,
            contextMode: effectiveMode,
            sourcePolicy: requestedSourcePolicy
        )
    }

    func enqueueAnalysisSessionAIJob(
        userMessage: String,
        userMessageID: UUID,
        sessionID: UUID,
        pack: DataPack,
        task: AnalysisTask?,
        contextMode: AnalysisContextMode,
        sourcePolicy: AnalysisContextSourcePolicy = .tableOnly
    ) {
        let refreshedSession = workspace.analysisSessions.first(where: { $0.id == sessionID }) ?? selectedAnalysisSession
        guard let refreshedSession else { return }
        let job = enqueuePersistentAIJob(
            kind: .analysisSession,
            payload: PersistentAIJobPayload(
                userMessage: userMessage,
                messageID: userMessageID,
                sessionID: sessionID,
                packID: pack.id,
                taskID: task?.id,
                targetName: refreshedSession.title,
                contextMode: contextMode,
                contextSourcePolicy: sourcePolicy
            )
        )
        updatePersistentAIJob(job.id) { job in
            job.logs.append(AIReasoningLogEntry(
                step: "已收到追问",
                status: job.status,
                detail: "已收到用户问题，稍后准备分析资料并请求 AI。"
            ))
        }
        statusText = "\(contextMode.label)请求已进入 AI 任务队列，可在“分析资料 > AI 任务”查看进度"
    }

    func coverageChatMessage(for snapshot: AnalysisCoverageSnapshot, mode: AnalysisContextMode) -> String {
        guard !mode.usesFullContext else { return snapshot.summary }
        let externalText: String
        if let coverage = snapshot.externalEvidenceCoverage {
            externalText = coverage.searchTriggered ? "已主动搜索外部证据" : "未主动搜索外部数据"
        } else {
            externalText = "外部证据使用已有缓存"
        }
        let excludedText = snapshot.excludedPeriodCount > 0 ? "；\(snapshot.excludedPeriodCount) 个周期被排除" : ""
        let profileOnlyText = snapshot.profileOnlyReportCount > 0 ? "；\(snapshot.profileOnlyReportCount) 张大表仅用画像/样本" : ""
        return "本轮使用\(mode.label)，读取 \(snapshot.totalReports) 张表 · \(snapshot.totalMetrics) 个指标 · \(snapshot.totalTimeColumns) 个时间周期\(excludedText)\(profileOnlyText)；\(externalText)。详情见「分析资料 > 数据覆盖」。"
    }

    func enqueuePostAnalysisMemoryJobs(
        userMessage: String,
        messageID: UUID?,
        sessionID: UUID,
        packID: UUID,
        taskID: UUID?,
        businessSpaceID: UUID?
    ) {
        if MetricSemanticExtractionService.shouldExtract(from: userMessage) {
            enqueuePersistentAIJob(
                kind: .metricSemanticExtraction,
                payload: PersistentAIJobPayload(
                    userMessage: userMessage,
                    messageID: messageID,
                    sessionID: sessionID,
                    packID: packID,
                    taskID: taskID,
                    businessSpaceID: businessSpaceID,
                    targetName: "指标语义抽取"
                )
            )
        }
        if UserQuestionMemoryExtractionService.shouldExtract(from: userMessage) {
            enqueuePersistentAIJob(
                kind: .userQuestionMemoryExtraction,
                payload: PersistentAIJobPayload(
                    userMessage: userMessage,
                    messageID: messageID,
                    sessionID: sessionID,
                    packID: packID,
                    taskID: taskID,
                    businessSpaceID: businessSpaceID,
                    targetName: "提问记忆抽取"
                )
            )
        }
    }

    func reanalyzeSelectedAnalysisSession(sourcePolicy: AnalysisContextSourcePolicy = .tableOnly) {
        guard let session = selectedAnalysisSession else {
            statusText = "请先创建分析会话"
            return
        }
        let goal = session.goal.nilIfBlank ?? session.messages.last(where: { $0.role == .user })?.content.nilIfBlank ?? "请重新完整分析当前任务。"
        sendAnalysisSessionMessage(
            """
            请重新完整分析当前任务。

            本次分析目标：
            \(goal)

            请重新读取当前任务选中的表和本地计算证据；先直接回答问题，再说明数据覆盖、趋势、多表联动、不确定性和建议。
            """,
            mode: .fullReanalysis,
            sourcePolicy: sourcePolicy
        )
    }

    func regenerateOpportunitiesForSelectedSession() {
        guard let session = selectedAnalysisSession else {
            statusText = "请先创建分析会话并发送分析需求"
            return
        }
        guard hasConfiguredAI else {
            statusText = "请先在 AI 设置中填写 API Key，机会评分由 AI 生成"
            requestedSidebarSelection = .settings
            return
        }
        guard runningAIJobForSelectedAnalysisSession == nil else {
            statusText = "当前会话正在分析，请等待本轮完成，或点击停止分析"
            return
        }
        guard let latest = session.messages.last(where: { $0.role == .assistant && $0.kind == .aiAnalysis }) else {
            statusText = "还没有可抽取机会评分的 AI 分析回复"
            return
        }
        enqueuePersistentAIJob(
            kind: .opportunityExtraction,
            payload: PersistentAIJobPayload(
                aiOutput: latest.content,
                sessionID: session.id,
                packID: session.packID,
                taskID: session.taskID,
                targetName: session.title,
                contextMode: .fullReanalysis
            )
        )
        statusText = "机会评分已进入 AI 任务队列"
    }

    func generateMemoFromSelectedAnalysisSession(scope: ReportGenerationScope = ReportGenerationScope()) {
        guard let session = selectedAnalysisSession else {
            statusText = "请先创建分析会话"
            return
        }
        guard hasConfiguredAI else {
            statusText = "请先在 AI 设置中填写 API Key，完整汇报由 AI 生成"
            return
        }
        guard runningAIJobForSelectedAnalysisSession == nil else {
            statusText = "当前会话正在分析，请等待本轮完成，或点击停止分析"
            return
        }
        guard let context = analysisSessionContext(for: session) else {
            statusText = "分析会话缺少对应数据包或任务"
            return
        }
        guard !context.reports.isEmpty else {
            statusText = "当前任务没有选择报表。请先加入至少 1 张表，再生成完整汇报。"
            return
        }
        let reportRequest = reportGenerationUserRequest(for: session, scope: scope)
        updateAnalysisSession(sessionID: session.id) { session in
            session.status = .analyzing
            session.finalMemoMarkdown = ""
            session.finalReportMarkdown = ""
            session.lastReportGeneratedAt = nil
        }
        enqueuePersistentAIJob(
            kind: .memo,
            payload: PersistentAIJobPayload(
                userMessage: reportRequest,
                sessionID: session.id,
                packID: context.pack.id,
                taskID: context.task?.id,
                targetName: session.title,
                contextMode: .reportGeneration,
                reportScope: scope
            )
        )
        statusText = "完整汇报已进入任务队列：将后台刷新覆盖快照、外部证据和会话需求后生成"
    }

    func generateSimpleReportFromSelectedAnalysisSession(scope: ReportGenerationScope = ReportGenerationScope()) {
        guard let session = selectedAnalysisSession else {
            statusText = "请先创建分析会话"
            return
        }
        guard hasConfiguredAI else {
            statusText = "请先在 AI 设置中填写 API Key，简洁汇报由 AI 生成"
            return
        }
        guard runningAIJobForSelectedAnalysisSession == nil else {
            statusText = "当前会话正在分析，请等待本轮完成，或点击停止分析"
            return
        }
        guard let context = analysisSessionContext(for: session) else {
            statusText = "分析会话缺少对应数据包或任务"
            return
        }
        guard !context.reports.isEmpty else {
            statusText = "当前任务没有选择报表。请先加入至少 1 张表，再生成简洁汇报。"
            return
        }
        let reportRequest = simpleReportGenerationUserRequest(for: session, scope: scope)
        updateAnalysisSession(sessionID: session.id) { session in
            session.status = .analyzing
            session.simpleReportMarkdown = ""
            session.lastSimpleReportGeneratedAt = nil
        }
        enqueuePersistentAIJob(
            kind: .simpleReportGeneration,
            payload: PersistentAIJobPayload(
                userMessage: reportRequest,
                sessionID: session.id,
                packID: context.pack.id,
                taskID: context.task?.id,
                targetName: session.title,
                contextMode: .reportGeneration,
                reportScope: scope
            )
        )
        statusText = "简洁汇报已进入任务队列：将后台全量读取当前任务资料后生成日常汇报"
    }

    func reportGenerationUserRequest(for session: AnalysisSession, scope: ReportGenerationScope = ReportGenerationScope()) -> String {
        let goal = session.goal.nilIfBlank ?? "用户未单独填写目标，请从当前会话首问和后续业务问题中归纳汇报范围。"
        let recentBusinessQuestions = session.messages
            .filter { $0.role == .user && $0.kind == .userRequest }
            .suffix(8)
            .map { "- \($0.content.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .joined(separator: "\n")
            .nilIfBlank ?? "- 当前会话暂无明确业务追问，请按任务选表和业务空间生成汇报。"

        return """
        请按完整汇报模式全量生成当前任务汇报。

        报告必须重新准备当前任务表格、数据覆盖、计算证据、业务空间、知识库、Confluence、外部证据、记忆和纠偏口径；不要按快速问答模式生成。

        本次汇报范围（最高优先级）：
        \(scope.promptMarkdown)

        任务目标：
        \(goal)

        需要覆盖的近期用户业务问题：
        \(recentBusinessQuestions)
        """
    }

    func simpleReportGenerationUserRequest(for session: AnalysisSession, scope: ReportGenerationScope = ReportGenerationScope()) -> String {
        let goal = session.goal.nilIfBlank ?? "用户未单独填写目标，请从当前会话首问和后续业务问题中归纳日常汇报范围。"
        let recentBusinessQuestions = session.messages
            .filter { $0.role == .user && $0.kind == .userRequest }
            .suffix(6)
            .map { "- \($0.content.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .joined(separator: "\n")
            .nilIfBlank ?? "- 当前会话暂无明确业务追问，请按任务选表和业务空间生成日常汇报。"

        return """
        请按简洁汇报模式全量生成当前任务的日常汇报。

        简洁汇报必须重新准备当前任务表格、数据覆盖、计算证据、业务空间、知识库、Confluence、外部证据、记忆和纠偏口径；不要按快速问答模式生成。

        输出只保留三部分：周期内数据变化、原因分析、动作建议。不要输出完整汇报的复杂章节。

        本次汇报范围（最高优先级）：
        \(scope.promptMarkdown)

        任务目标：
        \(goal)

        需要覆盖的近期用户业务问题：
        \(recentBusinessQuestions)
        """
    }

    func enqueueMemoAIJob(
        sessionID: UUID,
        context: (pack: DataPack, task: AnalysisTask?, reports: [ImportedReport]),
        coverageSnapshot: AnalysisCoverageSnapshot
    ) {
        let refreshedSession = workspace.analysisSessions.first(where: { $0.id == sessionID }) ?? selectedAnalysisSession
        guard let refreshedSession else { return }
        enqueuePersistentAIJob(
            kind: .memo,
            payload: PersistentAIJobPayload(
                userMessage: coverageSnapshot.userRequest,
                sessionID: sessionID,
                packID: context.pack.id,
                taskID: context.task?.id,
                targetName: refreshedSession.title,
                coverageSnapshot: coverageSnapshot,
                contextMode: .reportGeneration
            )
        )
        statusText = "完整汇报已进入任务队列，可在“分析资料 > AI 任务”查看进度"
    }

    func prepareDecisionMemoView() {
        guard let session = selectedAnalysisSession,
              let memoMarkdown = session.finalMemoMarkdown.nilIfBlank,
              let packIndex = workspace.dataPacks.firstIndex(where: { $0.id == session.packID }) else {
            return
        }
        let formattedMemoMarkdown = AnalysisOutputTextFormatter.normalizedPercentages(in: memoMarkdown)

        let selectedMemoIsEmpty = selectedPack?.decisionMemo.markdown.nilIfBlank == nil &&
            selectedAnalysisTask?.decisionMemo.markdown.nilIfBlank == nil
        if selectedPackID != session.packID, selectedMemoIsEmpty {
            selectedPackID = session.packID
        }

        var shouldSave = false
        if workspace.dataPacks[packIndex].decisionMemo.markdown.nilIfBlank == nil {
            workspace.dataPacks[packIndex].decisionMemo = DecisionMemo(
                generatedAt: session.lastReportGeneratedAt ?? Date(),
                markdown: formattedMemoMarkdown,
                aiSupplement: ""
            )
            workspace.dataPacks[packIndex].analysisGateStatus = .analyzed
            shouldSave = true
        }
        if let taskID = session.taskID,
           let taskIndex = workspace.dataPacks[packIndex].analysisTasks.firstIndex(where: { $0.id == taskID }),
           workspace.dataPacks[packIndex].analysisTasks[taskIndex].decisionMemo.markdown.nilIfBlank == nil {
            workspace.dataPacks[packIndex].analysisTasks[taskIndex].decisionMemo = DecisionMemo(
                generatedAt: session.lastReportGeneratedAt ?? Date(),
                markdown: formattedMemoMarkdown,
                aiSupplement: ""
            )
            workspace.dataPacks[packIndex].analysisTasks[taskIndex].updatedAt = Date()
            shouldSave = true
        }
        if shouldSave {
            save()
            statusText = "已将当前会话的完整汇报同步到报告草稿"
        }
    }

    func memoMarkdownForCurrentContext() -> String {
        if let selectedPack {
            if let taskMemo = currentAnalysisTask(in: selectedPack)?.decisionMemo.markdown.nilIfBlank {
                return taskMemo
            }
            if let packMemo = selectedPack.decisionMemo.markdown.nilIfBlank {
                return packMemo
            }
        }
        if let sessionMemo = selectedAnalysisSession?.finalMemoMarkdown.nilIfBlank {
            return sessionMemo
        }
        return ""
    }

    func adoptAnalysisSessionMessageAsKnowledge(messageID: UUID) {
        guard let session = selectedAnalysisSession,
              let message = session.messages.first(where: { $0.id == messageID }),
              !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusText = "没有可采纳的会话内容"
            return
        }
        let pack = workspace.dataPacks.first(where: { $0.id == session.packID })
        let packName = pack?.name ?? ""
        let spaceID = session.businessSpaceID ?? pack?.businessSpaceID ?? workspace.selectedBusinessSpaceID
        let entry = KnowledgeEntry(
            id: UUID(),
            createdAt: Date(),
            businessSpaceID: spaceID,
            isGlobal: spaceID == nil,
            scenario: "分析会话沉淀",
            problem: session.title,
            action: "从分析会话采纳 AI 结论",
            result: message.content,
            evidenceLevel: .b,
            relatedPackName: packName,
            sourceID: "analysis-session-\(session.id.uuidString)-\(message.id.uuidString)",
            sourceURL: nil,
            sourceUpdatedAt: Date(),
            tags: ["分析会话", "AI分析沉淀", packName].filter { !$0.isEmpty }
        )
        upsertKnowledgeEntry(entry)
        updateAnalysisSession(sessionID: session.id) { session in
            if let index = session.messages.firstIndex(where: { $0.id == messageID }) {
                session.messages[index].adoptedAs.append("知识库")
                session.messages[index].adoptedAs = session.messages[index].adoptedAs.uniqued()
            }
            session.updatedAt = Date()
        }
        save()
        statusText = "已沉淀进知识库；如需成为纠偏规则，请针对 AI 回复使用“质疑结论”后保存"
    }

    func saveAnalysisSessionMessageAsCorrectionMemory(messageID: UUID) {
        guard let session = selectedAnalysisSession,
              let message = session.messages.first(where: { $0.id == messageID }),
              message.role == .assistant,
              !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusText = "没有可保存的 AI 纠偏回复"
            return
        }
        guard !message.adoptedAs.contains("纠偏记忆") else {
            statusText = "这条回复已保存为纠偏规则"
            return
        }

        let pack = workspace.dataPacks.first(where: { $0.id == session.packID })
        let previousUserMessage = session.messages
            .filter { $0.createdAt < message.createdAt && $0.role == .user }
            .last
        let correction = previousUserMessage?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "从分析会话保存的纠偏说明"
        let revised = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let rule = "以后遇到类似分析场景，优先参考这条纠偏：\(messageSummary(revised, limit: 260))"
        let now = Date()
        let memory = AnalysisCorrectionMemory(
            id: UUID(),
            createdAt: now,
            updatedAt: now,
            packID: pack?.id ?? session.packID,
            packName: pack?.name ?? session.title,
            findingID: nil,
            findingTitle: session.title,
            metric: "",
            scope: "分析会话",
            originalConclusion: message.quotedMessageSummary ?? previousUserMessage?.quotedMessageSummary ?? session.goal,
            userCorrection: correction,
            revisedConclusion: revised,
            reusableRule: rule,
            tags: ["分析会话", "AI纠偏"],
            appliesToFuture: true,
            businessSpaceID: session.businessSpaceID ?? pack?.businessSpaceID ?? workspace.selectedBusinessSpaceID
        )

        workspace.correctionMemories.insert(memory, at: 0)
        workspace.correctionMemories.sort { $0.updatedAt > $1.updatedAt }
        upsertKnowledgeEntry(KnowledgeEntry(
            id: UUID(),
            createdAt: now,
            businessSpaceID: session.businessSpaceID ?? pack?.businessSpaceID ?? workspace.selectedBusinessSpaceID,
            isGlobal: false,
            scenario: "分析会话纠偏",
            problem: session.title,
            action: correction,
            result: [
                "修正后结论：\(revised)",
                "复用规则：\(rule)"
            ].joined(separator: "\n"),
            evidenceLevel: .b,
            relatedPackName: pack?.name ?? session.title,
            sourceID: "correction-\(memory.id.uuidString)",
            sourceUpdatedAt: now,
            tags: ["人工纠偏", "分析会话", "AI纠偏"]
        ))
        updateAnalysisSession(sessionID: session.id) { session in
            if let index = session.messages.firstIndex(where: { $0.id == messageID }) {
                session.messages[index].adoptedAs.append("纠偏记忆")
                session.messages[index].adoptedAs = session.messages[index].adoptedAs.uniqued()
                session.messages[index].correctionStatus = .savedAsCorrectionRule
                session.messages[index].savedCorrectionMemoryID = memory.id
            }
            if let originalID = message.replyToMessageID,
               let originalIndex = session.messages.firstIndex(where: { $0.id == originalID }) {
                session.messages[originalIndex].correctionStatus = .supersededByCorrection
                session.messages[originalIndex].supersededByMessageID = messageID
                session.messages[originalIndex].savedCorrectionMemoryID = memory.id
            }
        }
        statusText = "已保存为纠偏规则，并会用于后续分析"
    }

    func adoptSmartMemoryCandidate(_ candidate: SmartMemoryCandidate) {
        guard let index = workspace.smartMemoryCandidates.firstIndex(where: { $0.id == candidate.id }) else { return }
        let now = Date()
        let packName = selectedPack?.name ?? selectedAnalysisSession?.sourcePackName ?? "分析会话"
        let spaceID = candidate.businessSpaceID ?? selectedBusinessSpace?.id ?? workspace.selectedBusinessSpaceID
        let adoptedID: UUID
        if candidate.kind == .correctionRule {
            let memory = AnalysisCorrectionMemory(
                id: UUID(),
                createdAt: now,
                updatedAt: now,
                packID: selectedPack?.id ?? selectedAnalysisSession?.packID ?? UUID(),
                packName: packName,
                findingID: nil,
                findingTitle: candidate.title,
                metric: "",
                scope: candidate.scope,
                originalConclusion: candidate.rationale,
                userCorrection: candidate.content,
                revisedConclusion: candidate.content,
                reusableRule: candidate.content,
                tags: (candidate.tags + [candidate.kind.label, "智能记忆"]).uniqued(),
                appliesToFuture: true,
                businessSpaceID: spaceID
            )
            workspace.correctionMemories.insert(memory, at: 0)
            workspace.correctionMemories.sort { $0.updatedAt > $1.updatedAt }
            adoptedID = memory.id
        } else if candidate.kind == .metricDefinition,
                  let spaceID,
                  let spaceIndex = workspace.businessSpaces.firstIndex(where: { $0.id == spaceID }) {
            let metricName = metricNameFromCandidate(candidate)
            let semantic = BusinessSpaceMetricSemantic(
                metricName: metricName,
                sourceMessageID: candidate.messageID,
                aliasesText: "",
                businessDomainIDs: [],
                businessStage: inferredStageForMemory(candidate.content),
                directionPreference: inferredDirectionForMemory(candidate.content),
                maturityWindowDays: nil,
                impactLagDays: nil,
                relatedMetricsText: "",
                commonAnomalyExplanationsText: candidate.content,
                isUserConfirmed: true,
                updatedAt: now
            )
            if let semanticIndex = workspace.businessSpaces[spaceIndex].metricSemanticLibrary.firstIndex(where: { $0.metricName.normalizedKey == metricName.normalizedKey }) {
                workspace.businessSpaces[spaceIndex].metricSemanticLibrary[semanticIndex] = semantic
                adoptedID = workspace.businessSpaces[spaceIndex].metricSemanticLibrary[semanticIndex].id
            } else {
                workspace.businessSpaces[spaceIndex].metricSemanticLibrary.insert(semantic, at: 0)
                adoptedID = semantic.id
            }
            workspace.businessSpaces[spaceIndex].updatedAt = now
        } else {
            adoptedID = UUID()
        }

        let entryID = candidate.kind == .knowledgeFact ? candidate.id : adoptedID
        upsertKnowledgeEntry(KnowledgeEntry(
            id: entryID,
            createdAt: now,
            businessSpaceID: spaceID,
            isGlobal: spaceID == nil,
            scenario: candidate.kind.label,
            problem: candidate.title,
            action: "用户采纳的智能记忆，用于后续 AI 分析时动态检索。",
            result: candidate.content,
            evidenceLevel: .b,
            relatedPackName: packName,
            sourceID: "smart-memory-\(candidate.id.uuidString)",
            sourceUpdatedAt: now,
            tags: (candidate.tags + ["智能记忆", candidate.kind.label]).uniqued()
        ))

        workspace.smartMemoryCandidates[index].status = .adopted
        workspace.smartMemoryCandidates[index].updatedAt = now
        workspace.smartMemoryCandidates[index].adoptedMemoryID = adoptedID
        save()
        statusText = "已采纳为\(candidate.kind.label)，后续 AI 分析会动态检索这条记忆"
    }

    func ignoreSmartMemoryCandidate(_ candidate: SmartMemoryCandidate) {
        guard let index = workspace.smartMemoryCandidates.firstIndex(where: { $0.id == candidate.id }) else { return }
        workspace.smartMemoryCandidates[index].status = .ignored
        workspace.smartMemoryCandidates[index].updatedAt = Date()
        save()
        statusText = "已忽略这条记忆候选"
    }

    func archiveSmartMemoryCandidate(_ candidate: SmartMemoryCandidate) {
        guard let index = workspace.smartMemoryCandidates.firstIndex(where: { $0.id == candidate.id }) else { return }
        workspace.smartMemoryCandidates[index].status = .archived
        workspace.smartMemoryCandidates[index].updatedAt = Date()
        save()
        statusText = "已归档这条记忆候选"
    }

    func deleteSmartMemoryCandidate(_ candidate: SmartMemoryCandidate) {
        workspace.smartMemoryCandidates.removeAll { $0.id == candidate.id }
        save()
        statusText = "已删除这条记忆候选"
    }

    func updateSelectedAnalysisTask(name: String? = nil, goal: String? = nil) {
        updateSelectedPack { pack in
            guard let index = currentAnalysisTaskIndex(in: pack) else { return }
            if let name {
                pack.analysisTasks[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? pack.analysisTasks[index].name
            }
            if let goal {
                pack.analysisTasks[index].goal = goal
            }
            pack.analysisTasks[index].updatedAt = Date()
            markPackNeedsReview(&pack)
            refreshTaskBusinessLinks(for: &pack, forceReview: true)
        }
        if let selectedPack {
            syncSelectedAnalysisSessionWithCurrentTask(pack: selectedPack)
        }
        statusText = "已更新分析任务"
    }

    func saveSelectedAnalysisTask(name: String, goal: String) {
        updateSelectedAnalysisTask(name: name, goal: goal)
        if goalRequestsAnalysisTemplate(goal) {
            applyBestAnalysisTemplateToSelectedTask()
        } else {
            statusText = "已保存分析任务。下一步：选择要分析的报表，然后在分析会话里发送给 AI"
        }
    }

    func saveSelectedAnalysisTaskAsTemplate() {
        guard let selectedPack,
              let task = currentAnalysisTask(in: selectedPack) else {
            statusText = "还没有可保存的分析任务"
            return
        }
        let reports = taskReports(in: selectedPack, task: task)
        guard !reports.isEmpty else {
            statusText = "当前任务还没有选择报表。请先加入报表，再保存为模板"
            return
        }

        let reportRules = reports.map { report in
            analysisTemplateReportRule(for: report, role: task.role(for: report.id))
        }
        let metricRules = task.businessLinkProfile.metricLinks
            .filter { $0.confirmationStatus != .rejected }
            .map { link in
                AnalysisTemplateMetricLinkRule(
                    sourceMetric: link.sourceMetric,
                    targetMetric: link.targetMetric,
                    relationType: link.relationType,
                    lagDays: link.lagDays,
                    evidenceLevel: link.evidenceLevel,
                    notes: link.evidence.prefix(2).joined(separator: "；")
                )
            }
        let name = task.name.nilIfBlank.map { "\($0) 模板" } ?? "\(selectedPack.name) 分析模板"
        var template = AnalysisTemplateMemory(
            businessSpaceID: task.businessSpaceID ?? selectedPack.businessSpaceID ?? selectedBusinessSpace?.id,
            name: name,
            goal: task.goal.nilIfBlank ?? "按用户本轮指定周期分析；未指定周期时做全周期概览，并说明关键指标变化、多表指标联动和外部因素。",
            reportRules: reportRules,
            metricLinkRules: metricRules,
            relationshipSummary: task.businessLinkProfile.summary,
            outputInstructions: [
                "先说明数据覆盖和限制。",
                "用户指定周期时严格按指定周期；未指定周期时只做全周期概览，不默认主比较。",
                "再做历史趋势验证。",
                "逐表说趋势，再说指标级多表联动，最后给结论。"
            ],
            sourcePackName: selectedPack.name,
            sourceTaskName: task.name
        )

        if let existingIndex = workspace.analysisTemplateMemories.firstIndex(where: { $0.name.normalizedKey == name.normalizedKey }) {
            template.id = workspace.analysisTemplateMemories[existingIndex].id
            template.createdAt = workspace.analysisTemplateMemories[existingIndex].createdAt
            template.useCount = workspace.analysisTemplateMemories[existingIndex].useCount
            template.lastUsedAt = workspace.analysisTemplateMemories[existingIndex].lastUsedAt
            workspace.analysisTemplateMemories[existingIndex] = template
        } else {
            workspace.analysisTemplateMemories.insert(template, at: 0)
        }
        workspace.analysisTemplateMemories.sort { lhs, rhs in
            if lhs.isArchived != rhs.isArchived { return !lhs.isArchived }
            return lhs.updatedAt > rhs.updatedAt
        }
        save()
        statusText = "已保存分析模板：\(template.name)。下次导入相似报表时可直接套用"
    }

    func recommendedAnalysisTemplates(for pack: DataPack) -> [AnalysisTemplateMemory] {
        workspace.analysisTemplateMemories
            .filter { !$0.isArchived && ($0.businessSpaceID == nil || $0.businessSpaceID == pack.businessSpaceID || $0.businessSpaceID == selectedBusinessSpace?.id) }
            .map { template in
                (template, analysisTemplateMatchScore(template, reports: pack.importedReports))
            }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                if lhs.0.useCount != rhs.0.useCount { return lhs.0.useCount > rhs.0.useCount }
                return lhs.0.updatedAt > rhs.0.updatedAt
            }
            .map { $0.0 }
    }

    func applyBestAnalysisTemplateToSelectedTask() {
        guard let selectedPack else { return }
        guard let template = recommendedAnalysisTemplates(for: selectedPack).first ?? workspace.analysisTemplateMemories.first(where: { !$0.isArchived }) else {
            statusText = "还没有分析模板。请先完成一次任务并点击“保存为模板”"
            return
        }
        applyAnalysisTemplate(templateID: template.id)
    }

    func applyAnalysisTemplate(templateID: UUID) {
        guard let templateIndex = workspace.analysisTemplateMemories.firstIndex(where: { $0.id == templateID }) else {
            statusText = "没有找到该分析模板"
            return
        }
        let template = workspace.analysisTemplateMemories[templateIndex]
        var matchedCount = 0
        var totalRules = template.reportRules.count

        updateSelectedPack { pack in
            ensureAnalysisTaskExists(in: &pack)
            guard let taskIndex = currentAnalysisTaskIndex(in: pack) else { return }
            let matches = matchAnalysisTemplate(template, reports: pack.importedReports)
            matchedCount = matches.count
            totalRules = template.reportRules.count
            guard !matches.isEmpty else { return }

            let selectedIDs = matches.map { $0.report.id }.uniqued()
            var roles: [UUID: AnalysisTaskReportRole] = [:]
            for match in matches {
                roles[match.report.id] = match.role
            }
            pack.analysisTasks[taskIndex].selectedReportIDs = selectedIDs
            pack.analysisTasks[taskIndex].reportRoles = roles
            pack.analysisTasks[taskIndex].name = template.name.replacingOccurrences(of: "模板", with: "分析")
            pack.analysisTasks[taskIndex].goal = template.goal
            pack.analysisTasks[taskIndex].aiObservationGeneratedAt = nil
            pack.analysisTasks[taskIndex].aiObservationSignature = nil
            pack.analysisTasks[taskIndex].updatedAt = Date()
            if let primary = matches.first(where: { $0.role == .primaryBusiness })?.report.id ?? selectedIDs.first {
                pack.analysisTasks[taskIndex].relationshipProfile.primaryReportID = primary
            }
            markPackNeedsReview(&pack)
            refreshTaskRelationshipProfile(for: &pack, forceReview: true)
            refreshTaskBusinessLinks(for: &pack, forceReview: true)
            refreshAuditState(for: &pack)
        }

        if matchedCount > 0 {
            workspace.analysisTemplateMemories[templateIndex].useCount += 1
            workspace.analysisTemplateMemories[templateIndex].lastUsedAt = Date()
            workspace.analysisTemplateMemories[templateIndex].updatedAt = Date()
            if let selectedPack {
                syncSelectedAnalysisSessionWithCurrentTask(pack: selectedPack)
            }
            save()
            statusText = "已套用模板“\(template.name)”：匹配 \(matchedCount)/\(totalRules) 张表。下一步：检查表角色，然后在分析会话里发送给 AI"
        } else {
            statusText = "模板“\(template.name)”没有匹配到当前报表。请先手动加入报表，或保存新的模板"
        }
    }

    func addReportToSelectedTask(reportID: UUID, role: AnalysisTaskReportRole = .evidence) {
        updateSelectedPack { pack in
            ensureAnalysisTaskExists(in: &pack)
            guard let index = currentAnalysisTaskIndex(in: pack),
                  pack.importedReports.contains(where: { $0.id == reportID }) else { return }
            if !pack.analysisTasks[index].selectedReportIDs.contains(reportID) {
                pack.analysisTasks[index].selectedReportIDs.append(reportID)
            }
            pack.analysisTasks[index].reportRoles[reportID] = role
            pack.analysisTasks[index].updatedAt = Date()
            markPackNeedsReview(&pack)
            refreshTaskRelationshipProfile(for: &pack, forceReview: true)
            refreshTaskBusinessLinks(for: &pack, forceReview: true)
        }
        if let selectedPack {
            syncSelectedAnalysisSessionWithCurrentTask(pack: selectedPack)
        }
        statusText = "已加入当前分析任务"
    }

    func removeReportFromSelectedTask(reportID: UUID) {
        updateSelectedPack { pack in
            guard let index = currentAnalysisTaskIndex(in: pack) else { return }
            pack.analysisTasks[index].selectedReportIDs.removeAll { $0 == reportID }
            pack.analysisTasks[index].reportRoles.removeValue(forKey: reportID)
            if pack.analysisTasks[index].relationshipProfile.primaryReportID == reportID {
                pack.analysisTasks[index].relationshipProfile.primaryReportID = nil
            }
            pack.analysisTasks[index].relationshipProfile.supportingReportIDs.removeAll { $0 == reportID }
            pack.analysisTasks[index].relationshipProfile.incompatibleReportIDs.removeAll { $0 == reportID }
            pack.analysisTasks[index].updatedAt = Date()
            markPackNeedsReview(&pack)
            refreshTaskRelationshipProfile(for: &pack, forceReview: true)
            refreshTaskBusinessLinks(for: &pack, forceReview: true)
        }
        if let selectedPack {
            syncSelectedAnalysisSessionWithCurrentTask(pack: selectedPack)
        }
        statusText = "已从当前任务移除"
    }

    func setSelectedTaskReportRole(reportID: UUID, role: AnalysisTaskReportRole) {
        updateSelectedPack { pack in
            ensureAnalysisTaskExists(in: &pack)
            guard let index = currentAnalysisTaskIndex(in: pack) else { return }
            if !pack.analysisTasks[index].selectedReportIDs.contains(reportID) {
                pack.analysisTasks[index].selectedReportIDs.append(reportID)
            }
            pack.analysisTasks[index].reportRoles[reportID] = role
            if role == .primaryBusiness {
                pack.analysisTasks[index].relationshipProfile.primaryReportID = reportID
            }
            pack.analysisTasks[index].updatedAt = Date()
            markPackNeedsReview(&pack)
            refreshTaskRelationshipProfile(for: &pack, forceReview: true)
            refreshTaskBusinessLinks(for: &pack, forceReview: true)
        }
        if let selectedPack {
            syncSelectedAnalysisSessionWithCurrentTask(pack: selectedPack)
        }
        statusText = "已更新报表在当前任务中的角色"
    }

    func refreshSelectedTaskBusinessLinks() {
        updateSelectedPack { pack in
            refreshTaskRelationshipProfile(for: &pack, forceReview: true)
            refreshTaskBusinessLinks(for: &pack, forceReview: true)
            markPackNeedsReview(&pack)
        }
        statusText = "已重新识别当前任务的业务链路"
    }

    func confirmSelectedTaskBusinessLinks() {
        updateSelectedPack { pack in
            guard let index = currentAnalysisTaskIndex(in: pack) else { return }
            pack.analysisTasks[index].businessLinkProfile.confirmationStatus = .confirmed
            for edgeIndex in pack.analysisTasks[index].businessLinkProfile.edges.indices {
                pack.analysisTasks[index].businessLinkProfile.edges[edgeIndex].confirmationStatus = .confirmed
            }
            for linkIndex in pack.analysisTasks[index].businessLinkProfile.metricLinks.indices {
                pack.analysisTasks[index].businessLinkProfile.metricLinks[linkIndex].confirmationStatus = .confirmed
            }
            pack.analysisTasks[index].businessLinkProfile.updatedAt = Date()
            pack.analysisTasks[index].relationshipProfile.confirmationStatus = .confirmed
            pack.analysisTasks[index].relationshipProfile.updatedAt = Date()
            pack.analysisTasks[index].updatedAt = Date()
            pack.reportRelationshipProfile = pack.analysisTasks[index].relationshipProfile
            markPackNeedsReview(&pack)
        }
        statusText = "已确认当前任务业务链路"
    }

    func updateSelectedTaskMetricLink(linkID: UUID, status: BusinessLinkConfirmationStatus) {
        updateSelectedPack { pack in
            guard let taskIndex = currentAnalysisTaskIndex(in: pack),
                  let linkIndex = pack.analysisTasks[taskIndex].businessLinkProfile.metricLinks.firstIndex(where: { $0.id == linkID }) else { return }
            pack.analysisTasks[taskIndex].businessLinkProfile.metricLinks[linkIndex].confirmationStatus = status
            pack.analysisTasks[taskIndex].businessLinkProfile.updatedAt = Date()
            pack.analysisTasks[taskIndex].updatedAt = Date()
            markPackNeedsReview(&pack)
        }
        statusText = status == .rejected ? "已排除该指标联动" : "已更新指标联动状态"
    }

    func confirmReportRelationshipProfile() {
        confirmSelectedTaskBusinessLinks()
    }

    func setPrimaryReport(reportID: UUID?) {
        updateSelectedPack { pack in
            ensureAnalysisTaskExists(in: &pack)
            guard let index = currentAnalysisTaskIndex(in: pack) else { return }
            pack.analysisTasks[index].relationshipProfile.primaryReportID = reportID
            if let reportID {
                if !pack.analysisTasks[index].selectedReportIDs.contains(reportID) {
                    pack.analysisTasks[index].selectedReportIDs.append(reportID)
                }
                pack.analysisTasks[index].reportRoles[reportID] = .primaryBusiness
            }
            pack.analysisTasks[index].relationshipProfile.confirmationStatus = .needsReview
            pack.analysisTasks[index].relationshipProfile.updatedAt = Date()
            pack.analysisTasks[index].updatedAt = Date()
            markPackNeedsReview(&pack)
            refreshTaskRelationshipProfile(for: &pack, forceReview: true)
            refreshTaskBusinessLinks(for: &pack, forceReview: true)
        }
        statusText = "已更新主表"
    }

    func setReportRelationshipParticipation(reportID: UUID, participates: Bool) {
        updateSelectedPack { pack in
            ensureAnalysisTaskExists(in: &pack)
            guard let taskIndex = currentAnalysisTaskIndex(in: pack) else { return }
            if participates {
                if !pack.analysisTasks[taskIndex].selectedReportIDs.contains(reportID) {
                    pack.analysisTasks[taskIndex].selectedReportIDs.append(reportID)
                }
                pack.analysisTasks[taskIndex].relationshipProfile.incompatibleReportIDs.removeAll { $0 == reportID }
                if pack.analysisTasks[taskIndex].relationshipProfile.primaryReportID != reportID {
                    pack.analysisTasks[taskIndex].reportRoles[reportID] = .evidence
                }
            } else {
                pack.analysisTasks[taskIndex].reportRoles[reportID] = .excluded
                if !pack.analysisTasks[taskIndex].selectedReportIDs.contains(reportID) {
                    pack.analysisTasks[taskIndex].selectedReportIDs.append(reportID)
                }
            }
            pack.analysisTasks[taskIndex].relationshipProfile.confirmationStatus = .needsReview
            pack.analysisTasks[taskIndex].relationshipProfile.updatedAt = Date()
            pack.analysisTasks[taskIndex].updatedAt = Date()
            markPackNeedsReview(&pack)
            refreshTaskRelationshipProfile(for: &pack, forceReview: true)
            refreshTaskBusinessLinks(for: &pack, forceReview: true)
            refreshAuditState(for: &pack)
        }
        statusText = participates ? "已设置为参与分析" : "已设置为旁证/不合并"
    }

    func analysisSessionContext(for session: AnalysisSession) -> (pack: DataPack, task: AnalysisTask?, reports: [ImportedReport])? {
        guard let pack = workspace.dataPacks.first(where: { $0.id == session.packID }) else { return nil }
        let task = session.taskID.flatMap { taskID in
            pack.analysisTasks.first(where: { $0.id == taskID })
        } ?? currentAnalysisTask(in: pack)
        let reports: [ImportedReport]
        if let task {
            reports = taskReports(in: pack, task: task)
        } else if !session.selectedReportIDs.isEmpty {
            let ids = Set(session.selectedReportIDs)
            reports = pack.importedReports.filter { ids.contains($0.id) && !$0.isIgnoredFromAnalysis }
        } else {
            reports = []
        }
        return (pack, task, reports)
    }

    @discardableResult
    func refreshTrendMetadataForAnalysisSession(_ sessionID: UUID, force: Bool) -> Bool {
        guard let session = workspace.analysisSessions.first(where: { $0.id == sessionID }),
              let packIndex = workspace.dataPacks.firstIndex(where: { $0.id == session.packID }) else {
            return false
        }
        let pack = workspace.dataPacks[packIndex]
        let task = session.taskID.flatMap { taskID in
            pack.analysisTasks.first(where: { $0.id == taskID })
        } ?? currentAnalysisTask(in: pack)
        let activeReportIDs: Set<UUID>
        if let task {
            activeReportIDs = Set(task.activeReportIDs)
        } else {
            activeReportIDs = Set(session.selectedReportIDs)
        }
        guard !activeReportIDs.isEmpty else { return false }

        var didRefresh = false
        var updatedPack = workspace.dataPacks[packIndex]
        for reportIndex in updatedPack.importedReports.indices {
            guard activeReportIDs.contains(updatedPack.importedReports[reportIndex].id) else { continue }
            let report = updatedPack.importedReports[reportIndex]
            let needsRefresh = force ||
                report.trendSummary.isEmpty ||
                (report.trendSummary.analysisVersion ?? 0) < ReportTrendAnalyzer.currentAnalysisVersion
            guard needsRefresh else { continue }

            var refreshed = DataImportService.reportWithFieldMetadata(report)
            refreshed.timeAxisProfile = ReportTimeAxisDetector.detect(report: refreshed)
            refreshed.trendSummary = ReportTrendAnalyzer.analyze(report: refreshed)
            refreshed.tableContextCoverage = TableContextPackageBuilder.build(for: refreshed).coverage
            updatedPack.importedReports[reportIndex] = refreshed
            didRefresh = true
        }

        guard didRefresh else { return false }
        refreshAuditState(for: &updatedPack)
        workspace.dataPacks[packIndex] = updatedPack
        if let sessionIndex = workspace.analysisSessions.firstIndex(where: { $0.id == sessionID }) {
            workspace.analysisSessions[sessionIndex].contextCache = nil
            workspace.analysisSessions[sessionIndex].updatedAt = Date()
        }
        save()
        return true
    }

    func syncSelectedAnalysisSessionWithCurrentTask(pack: DataPack) {
        guard let sessionID = workspace.selectedAnalysisSessionID,
              let sessionIndex = workspace.analysisSessions.firstIndex(where: { $0.id == sessionID }),
              workspace.analysisSessions[sessionIndex].packID == pack.id,
              let task = currentAnalysisTask(in: pack),
              workspace.analysisSessions[sessionIndex].taskID == task.id else {
            return
        }
        workspace.analysisSessions[sessionIndex].selectedReportIDs = task.activeReportIDs
        workspace.analysisSessions[sessionIndex].goal = task.goal
        workspace.analysisSessions[sessionIndex].updatedAt = Date()
        save()
    }

    func resolveAnalysisContextMode(
        _ requestedMode: AnalysisContextMode?,
        userMessage: String,
        session: AnalysisSession,
        pack: DataPack,
        task: AnalysisTask?,
        reports: [ImportedReport]
    ) -> AnalysisContextMode {
        let hasPreviousAI = session.messages.contains { $0.role == .assistant && ($0.kind == .aiAnalysis || $0.kind == .aiMemo || $0.kind == .simpleReport) }
        let signature = analysisContextSignature(session: session, pack: pack, task: task, reports: reports)
        return AnalysisHarnessRouter.effectiveContextMode(
            requestedMode: requestedMode,
            userMessage: userMessage,
            hasPreviousAI: hasPreviousAI,
            cacheMatches: session.contextCache?.signature == signature
        )
    }

    func analysisContextSignature(
        session: AnalysisSession,
        pack: DataPack,
        task: AnalysisTask?,
        reports: [ImportedReport]
    ) -> String {
        let goal = session.goal.nilIfBlank ?? task?.goal.nilIfBlank ?? ""
        let reportPart = reports
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { report in
                "\(report.id.uuidString):\(report.importedAt.timeIntervalSince1970):\(report.rowCount):\(report.headers.count):\(report.firstColumnValues.count):trend\(report.trendSummary.analysisVersion ?? 0):axis\(report.timeAxisProfile.updatedAt?.timeIntervalSince1970 ?? 0)"
            }
            .joined(separator: "|")
        return [
            "space=\(session.businessSpaceID?.uuidString ?? task?.businessSpaceID?.uuidString ?? pack.businessSpaceID?.uuidString ?? workspace.selectedBusinessSpaceID?.uuidString ?? "none")",
            "pack=\(pack.id.uuidString)",
            "task=\(task?.id.uuidString ?? "none")",
            "goal=\(goal.normalizedKey)",
            "reports=\(reportPart)"
        ].joined(separator: "||")
    }

    func updateAnalysisContextCache(
        sessionID: UUID,
        mode: AnalysisContextMode,
        userRequest: String,
        aiOutput: String,
        coverageSnapshot: AnalysisCoverageSnapshot,
        pack: DataPack,
        task: AnalysisTask?,
        reports: [ImportedReport]
    ) {
        updateAnalysisSession(sessionID: sessionID) { session in
            let signature = analysisContextSignature(session: session, pack: pack, task: task, reports: reports)
            session.contextCache = AnalysisContextCache(
                signature: signature,
                mode: mode,
                coverageSummary: coverageSnapshot.summary,
                reportNames: reports.map(\.displayName),
                lastUserRequest: userRequest,
                lastAssistantSummary: messageSummary(aiOutput, limit: 1_600),
                limitations: coverageSnapshot.limitations
            )
            session.contextSummary = messageSummary(aiOutput, limit: 1_200)
        }
    }

    func messageSummary(_ text: String, limit: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "..."
    }

    func generateOpportunitiesFromAIOutput(
        _ aiOutput: String,
        sessionID: UUID,
        packID: UUID,
        taskID: UUID?,
        targetName: String
    ) async {
        guard let session = workspace.analysisSessions.first(where: { $0.id == sessionID }),
              let context = analysisSessionContext(for: session) else {
            statusText = "AI 分析已完成，但机会评分缺少会话上下文"
            return
        }
        do {
            let result = try await AIOpportunityExtractionService.extract(
                aiOutput: aiOutput,
                session: session,
                pack: context.pack,
                task: context.task,
                reports: context.reports,
                workspace: workspace,
                settings: workspace.aiSettings
            )
            writeOpportunities(result.opportunities, for: packID, taskID: taskID ?? context.task?.id)
            insertAIJobRecord(result.record, packID: packID, targetID: sessionID, targetName: targetName)
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
            statusText = result.opportunities.isEmpty
                ? "AI 分析已完成；本轮未形成可排序机会"
                : "AI 分析和机会评分已完成"
        } catch {
            insertFailedAIJobRecord(error, jobType: "AI 机会评分抽取", packID: packID, targetID: sessionID, targetName: targetName)
            appendAnalysisSessionMessage(
                sessionID: sessionID,
                AnalysisSessionMessage(role: .system, kind: .error, content: "机会评分生成失败：\(error.localizedDescription)。分析结果已保留，可在机会评分页重试。")
            )
            statusText = "AI 分析已完成；机会评分生成失败，可稍后重试"
        }
    }

    func writeOpportunities(_ opportunities: [ProductOpportunity], for packID: UUID, taskID: UUID?) {
        guard let packIndex = workspace.dataPacks.firstIndex(where: { $0.id == packID }) else { return }
        workspace.dataPacks[packIndex].analysisReport.opportunities = opportunities
        workspace.dataPacks[packIndex].analysisReport.generatedAt = Date()
        workspace.dataPacks[packIndex].analysisGateStatus = .analyzed
        if let taskID,
           let taskIndex = workspace.dataPacks[packIndex].analysisTasks.firstIndex(where: { $0.id == taskID }) {
            workspace.dataPacks[packIndex].analysisTasks[taskIndex].analysisReport.opportunities = opportunities
            workspace.dataPacks[packIndex].analysisTasks[taskIndex].analysisReport.generatedAt = Date()
            workspace.dataPacks[packIndex].analysisTasks[taskIndex].lastAnalyzedAt = Date()
            workspace.dataPacks[packIndex].analysisTasks[taskIndex].updatedAt = Date()
        }
        save()
    }

    func updateAnalysisSession(
        sessionID: UUID,
        touchUpdatedAt: Bool = true,
        savePolicy: WorkspaceSavePolicy = .immediate,
        _ transform: (inout AnalysisSession) -> Void
    ) {
        guard let index = workspace.analysisSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        transform(&workspace.analysisSessions[index])
        if touchUpdatedAt {
            workspace.analysisSessions[index].updatedAt = Date()
            workspace.analysisSessions.sort { lhs, rhs in
                if lhs.status == .archived, rhs.status != .archived { return false }
                if lhs.status != .archived, rhs.status == .archived { return true }
                return lhs.updatedAt > rhs.updatedAt
            }
        }
        save(policy: savePolicy)
    }

    func appendAnalysisSessionMessage(sessionID: UUID, _ message: AnalysisSessionMessage) {
        let shouldPromoteFirstQuestion = workspace.analysisSessions.first(where: { $0.id == sessionID })?.goal.isEmpty == true && message.role == .user
        updateAnalysisSession(sessionID: sessionID) { session in
            session.messages.append(message)
            if session.goal.isEmpty, message.role == .user {
                session.goal = message.content
            }
            session.status = message.kind == .error ? .waitingForUser : session.status
        }
        if shouldPromoteFirstQuestion {
            syncAnalysisTaskGoalFromFirstQuestion(message.content, sessionID: sessionID)
        }
    }

    func updateAnalysisSessionMessage(
        sessionID: UUID,
        messageID: UUID,
        touchUpdatedAt: Bool = true,
        savePolicy: WorkspaceSavePolicy = .immediate,
        _ transform: (inout AnalysisSessionMessage) -> Void
    ) {
        updateAnalysisSession(sessionID: sessionID, touchUpdatedAt: touchUpdatedAt, savePolicy: savePolicy) { session in
            guard let index = session.messages.firstIndex(where: { $0.id == messageID }) else { return }
            transform(&session.messages[index])
        }
    }

    func markAnalysisSessionMessage(
        sessionID: UUID,
        messageID: UUID,
        correctionStatus: AnalysisMessageCorrectionStatus,
        supersededByMessageID: UUID?,
        savedCorrectionMemoryID: UUID?
    ) {
        updateAnalysisSession(sessionID: sessionID) { session in
            guard let index = session.messages.firstIndex(where: { $0.id == messageID }) else { return }
            session.messages[index].correctionStatus = correctionStatus
            if let supersededByMessageID {
                session.messages[index].supersededByMessageID = supersededByMessageID
            }
            if let savedCorrectionMemoryID {
                session.messages[index].savedCorrectionMemoryID = savedCorrectionMemoryID
            }
            session.updatedAt = Date()
        }
    }

    func setAnalysisSessionMessageReportInclusion(
        sessionID: UUID,
        messageID: UUID,
        inclusion: AnalysisMessageReportInclusion
    ) {
        updateAnalysisSession(sessionID: sessionID) { session in
            guard let index = session.messages.firstIndex(where: { $0.id == messageID }) else { return }
            session.messages[index].reportInclusion = inclusion
            session.reportRequirementDigest = nil
        }
        statusText = "已更新该问题的汇报范围：\(inclusion.label)。下次生成完整汇报时生效。"
    }

    func userMessageLooksLikeCorrection(_ text: String) -> Bool {
        let key = text.normalizedKey
        return ["质疑", "不对", "错误", "误判", "纠偏", "修正", "不是", "不能", "不要"].contains { key.contains($0.normalizedKey) }
    }

    func metricNameFromCandidate(_ candidate: SmartMemoryCandidate) -> String {
        if let tagged = candidate.tags.first(where: { $0.hasPrefix("指标:") }) {
            return String(tagged.dropFirst("指标:".count)).trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? candidate.title
        }
        let quotedPatterns = [
            #"“([^”]{2,80})”"#,
            #""([^"]{2,80})""#,
            #"「([^」]{2,80})」"#,
            #"`([^`]{2,80})`"#
        ]
        for pattern in quotedPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(candidate.content.startIndex..<candidate.content.endIndex, in: candidate.content)
            if let match = regex.firstMatch(in: candidate.content, range: range),
               let valueRange = Range(match.range(at: 1), in: candidate.content) {
                return String(candidate.content[valueRange])
            }
        }
        return candidate.title
            .replacingOccurrences(of: "候选", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank ?? "未命名指标口径"
    }

    func inferredStageForMemory(_ text: String) -> MetricBusinessStage {
        let key = text.normalizedKey
        if key.contains("注册") { return .registration }
        if key.contains("申请") || key.contains("提交") { return .application }
        if key.contains("授信") || key.contains("审核") || key.contains("审批") { return .creditReview }
        if key.contains("发卡") || key.contains("激活") { return .cardActivation }
        if key.contains("消费") || key.contains("交易") || key.contains("支付") || key.contains("缴费") { return .payment }
        if key.contains("留存") || key.contains("活跃") { return .retention }
        if key.contains("页面") || key.contains("点击") || key.contains("曝光") { return .pageBehavior }
        if key.contains("风险") || key.contains("逾期") || key.contains("投诉") { return .risk }
        return .unknown
    }

    func inferredDirectionForMemory(_ text: String) -> MetricDirectionPreference {
        let key = text.normalizedKey
        if key.contains("越低越好") || key.contains("越少越好") || key.contains("失败") || key.contains("错误") || key.contains("逾期") || key.contains("投诉") {
            return .lowerIsBetter
        }
        if key.contains("越高越好") || key.contains("越多越好") || key.contains("提升") || key.contains("增长") {
            return .higherIsBetter
        }
        return .unknown
    }

    func syncAnalysisTaskGoalFromFirstQuestion(_ goal: String, sessionID: UUID) {
        guard let session = workspace.analysisSessions.first(where: { $0.id == sessionID }),
              let packIndex = workspace.dataPacks.firstIndex(where: { $0.id == session.packID }) else {
            return
        }
        let taskID = session.taskID ?? workspace.dataPacks[packIndex].selectedAnalysisTaskID
        guard let taskID,
              let taskIndex = workspace.dataPacks[packIndex].analysisTasks.firstIndex(where: { $0.id == taskID }),
              workspace.dataPacks[packIndex].analysisTasks[taskIndex].goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        workspace.dataPacks[packIndex].analysisTasks[taskIndex].goal = goal
        workspace.dataPacks[packIndex].analysisTasks[taskIndex].updatedAt = Date()
        save()
    }

    func appendCoverageSnapshot(_ snapshot: AnalysisCoverageSnapshot, to sessionID: UUID) {
        updateAnalysisSession(sessionID: sessionID) { session in
            var snapshots = session.coverageSnapshots ?? []
            snapshots.append(snapshot)
            session.coverageSnapshots = Array(snapshots.suffix(40))
        }
    }

    func appendAnalysisNotebookRun(_ run: AnalysisNotebookRun, to sessionID: UUID) {
        updateAnalysisSession(sessionID: sessionID) { session in
            session.notebookRuns.append(run)
            session.notebookRuns = Array(session.notebookRuns.suffix(40))
        }
    }

    @discardableResult
    func upsertMetricSemanticsFromUserMessage(
        _ text: String,
        messageID: UUID,
        reports: [ImportedReport],
        pack: DataPack,
        task: AnalysisTask?
    ) -> Int {
        guard let spaceID = task?.businessSpaceID ?? pack.businessSpaceID ?? workspace.selectedBusinessSpaceID,
              let spaceIndex = workspace.businessSpaces.firstIndex(where: { $0.id == spaceID }) else {
            return 0
        }
        let extracted = MetricSemanticExtractionService.extractConfirmedSemantics(
            from: text,
            messageID: messageID,
            reports: reports,
            businessSpace: workspace.businessSpaces[spaceIndex]
        )
        guard !extracted.isEmpty else { return 0 }
        var applied = 0
        for semantic in extracted {
            if let existingIndex = workspace.businessSpaces[spaceIndex].metricSemanticLibrary.firstIndex(where: {
                $0.metricName.normalizedKey == semantic.metricName.normalizedKey ||
                    $0.aliasesText.normalizedKey.contains(semantic.metricName.normalizedKey)
            }) {
                let existingID = workspace.businessSpaces[spaceIndex].metricSemanticLibrary[existingIndex].id
                var copy = semantic
                copy.id = existingID
                workspace.businessSpaces[spaceIndex].metricSemanticLibrary[existingIndex] = copy
            } else {
                workspace.businessSpaces[spaceIndex].metricSemanticLibrary.insert(semantic, at: 0)
            }
            applied += 1
        }
        workspace.businessSpaces[spaceIndex].metricSemanticLibrary.sort { $0.updatedAt > $1.updatedAt }
        workspace.businessSpaces[spaceIndex].updatedAt = Date()
        save()
        return applied
    }

    func setAnalysisSessionStatus(_ sessionID: UUID, _ status: AnalysisSessionStatus) {
        updateAnalysisSession(sessionID: sessionID) { session in
            session.status = status
        }
    }

    func insertAIJobRecord(_ record: AIJobRecord, packID: UUID, targetID: UUID?, targetName: String) {
        var updated = record
        updated.targetID = targetID
        updated.targetName = targetName
        workspace.aiJobRecords.removeAll { $0.id == updated.id }
        workspace.aiJobRecords.insert(updated, at: 0)
        workspace.aiJobRecords = Array(workspace.aiJobRecords.prefix(240))
        guard let index = workspace.dataPacks.firstIndex(where: { $0.id == packID }) else {
            save()
            return
        }
        workspace.dataPacks[index].aiJobRecords.removeAll { $0.id == updated.id }
        workspace.dataPacks[index].aiJobRecords.insert(updated, at: 0)
        workspace.dataPacks[index].aiJobRecords = Array(workspace.dataPacks[index].aiJobRecords.prefix(120))
        save()
    }

    func insertFailedAIJobRecord(_ error: Error, jobType: String, packID: UUID, targetID: UUID?, targetName: String) {
        if let queueError = error as? AIJobQueueError {
            insertAIJobRecord(queueError.record, packID: packID, targetID: targetID, targetName: targetName)
        } else {
            var record = AIJobRecord(
                jobType: jobType,
                targetID: targetID,
                targetName: targetName,
                status: .needsUserAction,
                attemptCount: 1,
                maxAttempts: 6,
                lastError: error.localizedDescription
            )
            record.logs.append(AIReasoningLogEntry(step: jobType, status: .needsUserAction, detail: error.localizedDescription))
            insertAIJobRecord(record, packID: packID, targetID: targetID, targetName: targetName)
        }
    }

    func updateAIJobRecord(_ jobID: UUID, _ transform: (inout AIJobRecord) -> Void) {
        if let index = workspace.aiJobRecords.firstIndex(where: { $0.id == jobID }) {
            transform(&workspace.aiJobRecords[index])
        }
        for packIndex in workspace.dataPacks.indices {
            if let jobIndex = workspace.dataPacks[packIndex].aiJobRecords.firstIndex(where: { $0.id == jobID }) {
                transform(&workspace.dataPacks[packIndex].aiJobRecords[jobIndex])
            }
        }
        save()
    }

    func setPackAnalysisGate(_ packID: UUID, _ status: DataPackAnalysisGateStatus) {
        guard let index = workspace.dataPacks.firstIndex(where: { $0.id == packID }) else { return }
        workspace.dataPacks[index].analysisGateStatus = status
        save()
    }

    func writeMemo(_ markdown: String, for packID: UUID, taskID: UUID?) {
        guard let packIndex = workspace.dataPacks.firstIndex(where: { $0.id == packID }) else { return }
        let formattedMarkdown = AnalysisOutputTextFormatter.normalizedPercentages(in: markdown)
        workspace.dataPacks[packIndex].decisionMemo = DecisionMemo(generatedAt: Date(), markdown: formattedMarkdown, aiSupplement: "")
        workspace.dataPacks[packIndex].analysisGateStatus = .analyzed
        if let taskID,
           let taskIndex = workspace.dataPacks[packIndex].analysisTasks.firstIndex(where: { $0.id == taskID }) {
            workspace.dataPacks[packIndex].analysisTasks[taskIndex].decisionMemo = workspace.dataPacks[packIndex].decisionMemo
            workspace.dataPacks[packIndex].analysisTasks[taskIndex].updatedAt = Date()
        }
        save()
    }
}
