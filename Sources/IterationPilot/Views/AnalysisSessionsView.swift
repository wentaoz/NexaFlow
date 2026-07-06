import AppKit
import SwiftUI

struct AnalysisSessionsView: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    @State private var inputText = ""
    @State private var contextPanel: SessionContextPanel = .reports
    @State private var selectedAuditReportID: UUID?
    @State private var selectedDictionaryFieldID: UUID?
    @State private var reportDescriptionDraft = ""
    @State private var reportUnderstandingAnswerText = ""
    @State private var reportQAQuestionText = ""
    @State private var dictionaryAnswerText = ""
    @State private var fieldSearchText = ""
    @State private var taskNameDraft = ""
    @State private var taskGoalDraft = ""
    @State private var goalDraftBySessionID: [UUID: String] = [:]
    @State private var lastCommittedGoalBySessionID: [UUID: String] = [:]
    @State private var goalCommitTask: Task<Void, Never>?
    @State private var isUnassignedReportsExpanded = true
    @State private var pendingPermanentDeleteSession: AnalysisSession?
    @State private var replyingToMessageID: UUID?
    @State private var expandedMessageIDs: Set<UUID> = []
    @State private var selectedComposerMode: AnalysisContextMode = .quickFollowUp
    @State private var selectedSourcePolicy: AnalysisContextSourcePolicy = .tableOnly
    @State private var reportScopeKind: ReportGenerationScopeKind = .fullConversation
    @State private var reportScopeQuestionIDs: Set<UUID> = []
    @State private var reportScopeShowsAllQuestions = false
    @State private var reportScopePeriodText = ""
    @State private var pendingReportGenerationKind: PendingReportGenerationKind?
    @State private var composerToolsExpanded = false
    @State private var showComposerReportPicker = false
    @State private var hasPromptedInitialDataSourceChoice = false
    @State private var lastAutoReportSelectionPackID: UUID?
    @State private var coveragePanelSnapshot = AnalysisCoveragePanelSnapshot.empty
    @State private var coveragePanelRevision: AnalysisCoveragePanelRevision?
    @State private var coveragePanelRefreshTask: Task<Void, Never>?
    private let readingModeContentMaxWidth: CGFloat = 1160
    private let readingModeHorizontalPadding: CGFloat = 20
    private let conversationContentMaxWidth: CGFloat = 1280
    private let conversationHorizontalPadding: CGFloat = 16
    private let compactWorkspaceThreshold: CGFloat = 1480

    var body: some View {
        sessionContentRoot
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.16), value: isFocusMode)
        .sheet(item: $pendingReportGenerationKind) { kind in
            if let session = store.selectedAnalysisSession {
                reportScopeSelectionSheet(session: session, kind: kind)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    SemanticLabel(title: kind.title, systemImage: "doc.richtext", role: .ai)
                        .font(.headline)
                    Text("当前没有选中的分析会话，无法生成汇报。")
                        .foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button("关闭") {
                            pendingReportGenerationKind = nil
                        }
                        .buttonStyle(AppHoverButtonStyle(variant: .secondary))
                    }
                }
                .padding(20)
                .frame(width: 420)
            }
        }
        .onChange(of: store.requestedAnalysisReportsPanelToken) { _ in
            consumeRequestedReportsPanelIfNeeded()
        }
        .onChange(of: store.selectedAnalysisSession?.id) { _ in
            flushGoalDraftsToStore(savePolicy: .immediate, touchUpdatedAt: true)
            if contextPanel == .coverage {
                refreshCoveragePanelSnapshot(force: true)
            }
        }
        .onChange(of: store.selectedPackID) { _ in
            if contextPanel == .coverage {
                refreshCoveragePanelSnapshot(force: true)
            }
            promptForReportSelectionAfterPackSwitchIfNeeded()
        }
        .onChange(of: contextPanel) { newValue in
            if newValue == .coverage {
                refreshCoveragePanelSnapshot(force: true)
            }
        }
        .onChange(of: coveragePanelChangeKey) { _ in
            scheduleCoveragePanelRefresh()
        }
        .onAppear {
            consumeRequestedReportsPanelIfNeeded()
            if contextPanel == .coverage {
                refreshCoveragePanelSnapshot(force: true)
            }
            promptForInitialDataSourceIfNeeded()
            promptForReportSelectionAfterPackSwitchIfNeeded()
        }
        .onDisappear {
            flushGoalDraftsToStore(savePolicy: .immediate, touchUpdatedAt: true)
            coveragePanelRefreshTask?.cancel()
            coveragePanelRefreshTask = nil
        }
        .confirmationDialog(
            "永久删除此分析会话？",
            isPresented: Binding(
                get: { pendingPermanentDeleteSession != nil },
                set: { if !$0 { pendingPermanentDeleteSession = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let session = pendingPermanentDeleteSession {
                Button("永久删除“\(session.title)”", role: .destructive) {
                    store.deleteAnalysisSessionPermanently(sessionID: session.id)
                    pendingPermanentDeleteSession = nil
                }
            }
            Button("取消", role: .cancel) {
                pendingPermanentDeleteSession = nil
            }
        } message: {
            Text("永久删除后，这段对话、报告草稿和过程记录无法恢复。已沉淀到知识库或模板里的长期记忆不会被删除。")
        }
    }

    private var isFocusMode: Bool {
        store.isAnalysisReadingMode
    }

    private var coveragePanelChangeKey: AnalysisCoveragePanelChangeKey {
        guard contextPanel == .coverage else {
            return AnalysisCoveragePanelChangeKey(panel: contextPanel, revision: nil)
        }
        return AnalysisCoveragePanelChangeKey(panel: contextPanel, revision: makeCoveragePanelRevision())
    }

    private var sessionContentRoot: some View {
        VStack(spacing: 0) {
            if let session = store.selectedAnalysisSession, isSessionSourceMissing(session) {
                deletedPackSessionWorkspace(session: session)
            } else if let pack = store.selectedPack {
                sessionWorkspaceArea(pack: pack)
            } else {
                NoAnalysisDataSourceStartPanel(
                    importAction: { store.showImportPanel() },
                    tableauAction: { store.showTableauImportSheet() }
                )
            }
        }
        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func promptForInitialDataSourceIfNeeded() {
        hasPromptedInitialDataSourceChoice = true
    }

    private func promptForReportSelectionAfterPackSwitchIfNeeded() {
        guard let pack = store.selectedPack else { return }
        guard lastAutoReportSelectionPackID != pack.id else { return }
        guard !pack.importedReports.filter({ !$0.isIgnoredFromAnalysis }).isEmpty,
              store.reportsForCurrentTask(in: pack).isEmpty,
              store.pendingPostImportConfirmation == nil,
              !store.showingImportSourceChoice,
              !store.showingTableauImportSheet else {
            return
        }
        lastAutoReportSelectionPackID = pack.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            guard store.selectedPack?.id == pack.id,
                  store.reportsForCurrentTask(in: pack).isEmpty,
                  store.pendingPostImportConfirmation == nil else {
                return
            }
            _ = store.presentCurrentPackReportSelectionConfirmation(force: false)
        }
    }

    @ViewBuilder
    private func sessionWorkspaceArea(pack: DataPack) -> some View {
        GeometryReader { proxy in
            let isCompactWorkspace = proxy.size.width < compactWorkspaceThreshold
            sessionWorkspace(pack: pack, isCompactWorkspace: isCompactWorkspace)
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func sessionWorkspace(pack: DataPack, isCompactWorkspace: Bool) -> some View {
        if let session = store.selectedAnalysisSession, session.packID == pack.id {
            if isFocusMode {
                HStack(spacing: 0) {
                    Spacer(minLength: readingModeHorizontalPadding)
                    sessionWorkspaceContent(session: session, pack: pack, isCompactWorkspace: isCompactWorkspace)
                        .frame(maxWidth: readingModeContentMaxWidth, maxHeight: .infinity, alignment: .topLeading)
                    Spacer(minLength: readingModeHorizontalPadding)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                sessionWorkspaceContent(session: session, pack: pack, isCompactWorkspace: isCompactWorkspace)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            SessionStartPanel(
                pack: pack,
                selectedReportCount: store.reportsForCurrentTask(in: pack).count,
                createAction: {
                    store.createAnalysisSessionFromCurrentTask()
                    openReportsPanel()
                },
                chooseReportsAction: {
                    store.createAnalysisSessionFromCurrentTask()
                    openReportsPanel()
                },
                importAction: {
                    store.showImportPanel()
                }
            )
        }
    }

    private func sessionWorkspaceContent(session: AnalysisSession, pack: DataPack, isCompactWorkspace: Bool) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: conversationHorizontalPadding)
            VStack(spacing: 0) {
                if !isFocusMode {
                    workflowStepBar(
                        session: session,
                        pack: pack,
                        state: sessionRenderState(session: session, pack: pack)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                    Divider()
                }
                sessionMainArea(session: session)
                Divider()
                composer(session: session, pack: pack)
            }
            .frame(maxWidth: conversationContentMaxWidth, maxHeight: .infinity, alignment: .topLeading)
            Spacer(minLength: conversationHorizontalPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func openReportsPanel() {
        contextPanel = .reports
        store.analysisInfoSidebarPanelID = "资料"
        store.isAnalysisInfoSidebarVisible = true
        isUnassignedReportsExpanded = true
    }

    private func openEvidencePanel(message: AnalysisSessionMessage? = nil) {
        if message == nil && store.isAnalysisInfoSidebarVisible && store.analysisInfoSidebarPanelID == "证据" {
            store.isAnalysisInfoSidebarVisible = false
            return
        }
        contextPanel = .coverage
        store.analysisInfoSidebarPanelID = "证据"
        store.selectedAnalysisEvidenceMessageID = message?.id
        store.isAnalysisInfoSidebarVisible = true
        refreshCoveragePanelSnapshot(force: true)
    }

    private func toggleReadingMode() {
        let shouldEnable = !store.isAnalysisReadingMode
        withAnimation(.easeInOut(duration: 0.16)) {
            store.isAnalysisReadingMode = shouldEnable
            if shouldEnable {
                store.isAnalysisInfoSidebarVisible = false
                store.isMainSidebarVisible = false
                collapseHistoricalMessageExpansionsForReading()
            } else {
                store.isMainSidebarVisible = true
            }
        }
    }

    private func collapseHistoricalMessageExpansionsForReading() {
        guard let session = store.selectedAnalysisSession else {
            expandedMessageIDs.removeAll()
            return
        }
        if let latestAssistantID = session.messages.last(where: { $0.role == .assistant && $0.kind != .error })?.id,
           expandedMessageIDs.contains(latestAssistantID) {
            expandedMessageIDs = [latestAssistantID]
        } else {
            expandedMessageIDs.removeAll()
        }
    }

    private func consumeRequestedReportsPanelIfNeeded() {
        guard store.requestedAnalysisReportsPanelToken != nil else { return }
        openReportsPanel()
        store.requestedAnalysisReportsPanelToken = nil
    }

    private func goalBinding(for session: AnalysisSession) -> Binding<String> {
        Binding(
            get: { goalDraft(for: session) },
            set: { newValue in
                goalDraftBySessionID[session.id] = newValue
                if lastCommittedGoalBySessionID[session.id] == nil {
                    lastCommittedGoalBySessionID[session.id] = latestGoal(for: session.id) ?? session.goal
                }
                scheduleGoalCommit(newValue, sessionID: session.id)
            }
        )
    }

    private func goalDraft(for session: AnalysisSession) -> String {
        goalDraftBySessionID[session.id] ?? latestGoal(for: session.id) ?? session.goal
    }

    private func latestGoal(for sessionID: UUID) -> String? {
        store.workspace.analysisSessions.first(where: { $0.id == sessionID })?.goal
    }

    private func scheduleGoalCommit(_ goal: String, sessionID: UUID) {
        goalCommitTask?.cancel()
        goalCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled,
                  goalDraftBySessionID[sessionID] == goal else {
                return
            }
            commitGoalDraftToStore(
                goal,
                sessionID: sessionID,
                savePolicy: .deferred,
                touchUpdatedAt: false
            )
            goalCommitTask = nil
        }
    }

    private func flushSelectedGoalDraftToStore(
        savePolicy: WorkspaceSavePolicy = .immediate,
        touchUpdatedAt: Bool = true
    ) {
        guard let sessionID = store.selectedAnalysisSession?.id else { return }
        flushGoalDraft(sessionID: sessionID, savePolicy: savePolicy, touchUpdatedAt: touchUpdatedAt)
    }

    private func flushGoalDraftsToStore(
        savePolicy: WorkspaceSavePolicy = .immediate,
        touchUpdatedAt: Bool = true
    ) {
        let hadDrafts = !goalDraftBySessionID.isEmpty
        goalCommitTask?.cancel()
        goalCommitTask = nil
        for (sessionID, goal) in Array(goalDraftBySessionID) {
            commitGoalDraftToStore(
                goal,
                sessionID: sessionID,
                savePolicy: savePolicy,
                touchUpdatedAt: touchUpdatedAt
            )
        }
        if case .immediate = savePolicy, hadDrafts {
            store.save(policy: .immediate)
            goalDraftBySessionID.removeAll(keepingCapacity: true)
        }
    }

    private func flushGoalDraft(
        sessionID: UUID,
        savePolicy: WorkspaceSavePolicy = .immediate,
        touchUpdatedAt: Bool = true
    ) {
        goalCommitTask?.cancel()
        goalCommitTask = nil
        guard let goal = goalDraftBySessionID[sessionID] else { return }
        _ = commitGoalDraftToStore(
            goal,
            sessionID: sessionID,
            savePolicy: savePolicy,
            touchUpdatedAt: touchUpdatedAt
        )
        if case .immediate = savePolicy {
            store.save(policy: .immediate)
            goalDraftBySessionID.removeValue(forKey: sessionID)
        }
    }

    @discardableResult
    private func commitGoalDraftToStore(
        _ goal: String,
        sessionID: UUID,
        savePolicy: WorkspaceSavePolicy,
        touchUpdatedAt: Bool
    ) -> Bool {
        guard latestGoal(for: sessionID) != goal else {
            lastCommittedGoalBySessionID[sessionID] = goal
            return false
        }
        store.updateAnalysisSessionGoal(
            sessionID: sessionID,
            goal,
            savePolicy: savePolicy,
            touchUpdatedAt: touchUpdatedAt
        )
        lastCommittedGoalBySessionID[sessionID] = goal
        return true
    }

    private func isSessionSourceMissing(_ session: AnalysisSession) -> Bool {
        session.sourcePackDeleted == true ||
            !store.workspace.dataPacks.contains(where: { $0.id == session.packID })
    }

    private func deletedPackSessionWorkspace(session: AnalysisSession) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        deletedPackTitleBlock(session: session)
                        Spacer()
                        deletedPackSessionActions(session: session)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        deletedPackTitleBlock(session: session)
                        deletedPackSessionActions(session: session)
                    }
                }
                WorkflowBlockedBanner(
                    title: "原始资料已删除",
                    detail: "这段会话作为工作记忆保留。你可以查看历史对话、报告和已沉淀内容，但不能继续基于原始表格重算。"
                )
            }
            .padding(16)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !session.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        SectionCard(title: "本次分析目标", systemImage: "target") {
                            Text(session.goal)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    ForEach(session.messages) { message in
                        SessionMessageCard(
                            message: message,
                            renderSnapshot: SessionMessageRenderSnapshot(message: message),
                            isLatestAssistant: false,
                            isStreamingAssistant: false,
                            latestExpansionOverride: nil,
                            isExpanded: expandedMessageIDs.contains(message.id),
                            followUpAction: { startMessageReply(message, prompt: "") },
                            viewEvidenceAction: { openEvidencePanel(message: message) },
                            focusMetricEvidenceAction: { resultID, sourceCells in
                                openEvidencePanel(message: message)
                                store.focusMetricResultEvidence(
                                    messageID: message.id,
                                    resultID: resultID,
                                    sourceCells: sourceCells
                                )
                            },
                            explainEvidenceAction: { startMessageReply(message, prompt: "请解释这条回答的关键证据，分别说明哪些是事实、推断、假设和需补数据。") },
                            challengeAction: { startMessageReply(message, prompt: "我质疑这条结论。请根据我接下来补充的问题，重新判断哪里可能错了，并在最后给出一条可复用的纠偏规则，格式为：误判点 / 修正后结论 / 以后遇到类似情况要检查什么。") },
                            correctionAction: { store.saveAnalysisSessionMessageAsCorrectionMemory(messageID: message.id) },
                            adoptAction: { store.adoptAnalysisSessionMessageAsKnowledge(messageID: message.id) },
                            importSupplementDataAction: { store.importReportsIntoSelectedPack() },
                            markExistingDataAction: { startMessageReply(message, prompt: "我认为当前任务里已经有你补数清单提到的数据。请回到本轮 AI 读取范围和当前任务报表里重新核对：哪些补数项其实已覆盖，分别对应哪张表、哪个字段或指标；仍未覆盖的再保留为补数清单。") },
                            setReportInclusionAction: { inclusion in store.setAnalysisSessionMessageReportInclusion(sessionID: session.id, messageID: message.id, inclusion: inclusion) },
                            generateFullReportAction: { presentReportScopeSheet(.full, session: session) },
                            generateFullReportForQuestionAction: { generateFullReport(for: message) },
                            generateSimpleReportForQuestionAction: { generateSimpleReport(for: message) },
                            toggleExpandedAction: { toggleMessageExpansion(message.id) }
                        )
                        .equatable()
                    }
                    if !session.simpleReportMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        SectionCard(title: "历史简洁汇报", systemImage: "doc.text") {
                            LongTextPreview(
                                text: session.simpleReportMarkdown,
                                previewLimit: 2_400,
                                expandedHeight: 260
                            )
                        }
                    }
                    if !session.finalReportMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        SectionCard(title: "历史完整汇报", systemImage: "doc.richtext") {
                            LongTextPreview(
                                text: session.finalReportMarkdown,
                                previewLimit: 2_400,
                                expandedHeight: 320
                            )
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func deletedPackTitleBlock(session: AnalysisSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(session.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Badge(text: session.status.label, systemImage: nil, tint: session.status == .archived ? .secondary : AppTheme.warning)
                Badge(text: "原始资料已删除", systemImage: nil, tint: AppTheme.warning)
            }
            Text("\(session.businessSpaceSnapshot?.name ?? "未设置业务空间") · \(session.sourcePackName ?? "已删除资料") · 历史会话")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func deletedPackSessionActions(session: AnalysisSession) -> some View {
        HStack(spacing: 8) {
            if session.status == .archived {
                Button {
                    store.restoreAnalysisSession(sessionID: session.id)
                } label: {
                    SemanticLabel(title: "恢复", systemImage: "arrow.uturn.backward", role: .data)
                }
            } else {
                Button {
                    store.archiveAnalysisSession(sessionID: session.id)
                } label: {
                    SemanticLabel(title: "归档", systemImage: "archivebox", role: .knowledge)
                }
            }
            Button(role: .destructive) {
                pendingPermanentDeleteSession = session
            } label: {
                SemanticLabel(title: "永久删除", systemImage: "trash", role: .risk)
            }
        }
    }

    @ViewBuilder
    private func sessionMainArea(session: AnalysisSession) -> some View {
        chatColumn(session: session)
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sessionRenderState(session: AnalysisSession, pack: DataPack) -> SessionHeaderRenderState {
        let currentTask = store.currentAnalysisTask(in: pack) ?? session.taskID.flatMap { id in
            pack.analysisTasks.first { $0.id == id }
        }
        let selectedReportCount = selectedReportCount(for: session, pack: pack, task: currentTask)
        let hasAIReply = session.messages.contains { $0.role == .assistant && $0.kind != .error }
        let hasEvidence = sessionHasEvidence(session)
        return SessionHeaderRenderState(
            selectedReportCount: selectedReportCount,
            hasAIReply: hasAIReply,
            hasAnalysis: session.messages.contains { $0.role == .assistant && $0.kind == .aiAnalysis },
            hasEvidence: hasEvidence,
            hasReport: !session.finalReportMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            hasSimpleReport: !session.simpleReportMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            hasOpportunities: !(currentTask?.analysisReport.opportunities.isEmpty ?? true),
            activeJob: store.blockingAIJob(for: session.id).map(LiveAIJobSnapshot.init),
            reportRequirementCount: ReportRequirementDigestBuilder.questionCount(for: session),
            businessSpaceName: session.businessSpaceSnapshot?.name ?? store.selectedBusinessSpace?.name ?? "未设置业务空间",
            taskName: currentTask?.name ?? "未选择任务",
            hasConfiguredAI: store.hasConfiguredAI
        )
    }

    private func isFirstQuestionPhase(_ state: SessionHeaderRenderState) -> Bool {
        !state.hasAIReply && !state.hasAnalysis
    }

    private func sessionHasEvidence(_ session: AnalysisSession) -> Bool {
        if let snapshots = session.coverageSnapshots, !snapshots.isEmpty {
            return true
        }
        return session.messages.contains { message in
            message.role == .assistant && !message.evidence.isEmpty
        }
    }

    private func sessionHeader(session: AnalysisSession, pack: DataPack, isCompactWorkspace: Bool) -> some View {
        let state = sessionRenderState(session: session, pack: pack)
        return VStack(alignment: .leading, spacing: 10) {
            if isCompactWorkspace {
                VStack(alignment: .leading, spacing: 10) {
                    titleBlock(session: session, pack: pack, state: state)
                    headerActions(session: session, state: state, isCompactWorkspace: true)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    titleBlock(session: session, pack: pack, state: state)
                    Spacer()
                    headerActions(session: session, state: state, isCompactWorkspace: false)
                }
            }

            if isFocusMode {
                compactSessionStatusLine(
                    selectedReportCount: state.selectedReportCount,
                    hasAIReply: state.hasAIReply,
                    hasSimpleReport: state.hasSimpleReport,
                    hasReport: state.hasReport,
                    hasOpportunities: state.hasOpportunities,
                    isAnalysisRunning: state.isAnalysisRunning,
                    isSimpleReportGenerating: state.isSimpleReportGenerating,
                    isReportGenerating: state.isReportGenerating
                )
            } else {
                workflowStepBar(session: session, pack: pack, state: state)
            }
            if let activeJob = state.activeJob {
                LiveAnalysisStatusBar(job: activeJob, reportRequirementCount: state.reportRequirementCount)
            } else if state.hasReport && !isFocusMode {
                ReportRequirementHint(count: state.reportRequirementCount, generatedAt: session.reportRequirementDigest?.generatedAt)
            }
        }
        .padding(16)
    }

    private func workflowStepBar(session: AnalysisSession, pack: DataPack, state: SessionHeaderRenderState) -> some View {
        AnalysisWorkflowStepBar(
            hasImportedReports: !pack.importedReports.isEmpty,
            selectedReportCount: state.selectedReportCount,
            hasAIReply: state.hasAIReply,
            hasEvidence: state.hasEvidence,
            hasReport: state.hasReport,
            isAnalysisRunning: state.isAnalysisRunning,
            isReportGenerating: state.isReportGenerating,
            taskName: state.taskName,
            importAction: { store.showImportPanel() },
            selectReportsAction: {
                if !store.presentCurrentPackReportSelectionConfirmation(force: true) {
                    openReportsPanel()
                }
            },
            focusComposerAction: { store.focusAnalysisComposerToken = UUID() },
            reviewEvidenceAction: { openEvidencePanel() },
            generateReportAction: { presentReportScopeSheet(.full, session: session) }
        )
    }

    private func compactSessionStatusLine(
        selectedReportCount: Int,
        hasAIReply: Bool,
        hasSimpleReport: Bool,
        hasReport: Bool,
        hasOpportunities: Bool,
        isAnalysisRunning: Bool,
        isSimpleReportGenerating: Bool,
        isReportGenerating: Bool
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                compactStatusChip("选表", "\(selectedReportCount) 张", isDone: selectedReportCount > 0)
                compactStatusChip("对话", isAnalysisRunning ? "分析中" : (hasAIReply ? "已开始" : "未开始"), isDone: hasAIReply, isRunning: isAnalysisRunning)
                compactStatusChip("机会评分", hasOpportunities ? "已生成" : "待生成", isDone: hasOpportunities)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                compactStatusChip("选表", "\(selectedReportCount) 张", isDone: selectedReportCount > 0)
                compactStatusChip("对话", isAnalysisRunning ? "分析中" : (hasAIReply ? "已开始" : "未开始"), isDone: hasAIReply, isRunning: isAnalysisRunning)
                compactStatusChip("机会评分", hasOpportunities ? "已生成" : "待生成", isDone: hasOpportunities)
            }
        }
    }

    private func compactStatusChip(_ title: String, _ value: String, isDone: Bool, isRunning: Bool = false) -> some View {
        HStack(spacing: 5) {
            if isRunning {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.55)
                    .frame(width: 12, height: 12)
            } else {
                SemanticIcon(systemName: isDone ? "checkmark.circle.fill" : "circle", role: isDone ? .success : .neutral, size: 12, frameWidth: 14)
            }
            Text("\(title)：\(value)")
                .lineLimit(1)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppTheme.panelStrong.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
    }

    private func titleBlock(session: AnalysisSession, pack: DataPack, state: SessionHeaderRenderState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
		                Text(session.title)
		                    .font(.title2)
		                    .fontWeight(.semibold)
		                    .lineLimit(1)
		                    .minimumScaleFactor(0.75)
		                sessionStatusBadge(session, state: state)
		            }
            Text("\(state.businessSpaceName) · \(pack.name) · \(state.taskName)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func sessionStatusBadge(_ session: AnalysisSession, state: SessionHeaderRenderState) -> some View {
        if let job = state.activeJob {
            LiveJobBadge(job: job)
        } else {
            let shouldShowWaiting = session.status == .analyzing || (session.status == .reportReady && !state.hasReport)
            let label = shouldShowWaiting ? AnalysisSessionStatus.waitingForUser.label : session.status.label
            Badge(
                text: label,
                systemImage: nil,
                tint: session.status == .reportReady && state.hasReport ? AppTheme.success : .secondary
            )
        }
    }

    @ViewBuilder
    private func headerActions(session: AnalysisSession, state: SessionHeaderRenderState, isCompactWorkspace: Bool) -> some View {
        if isCompactWorkspace {
            compactHeaderActions(session: session, state: state)
        } else {
            regularHeaderActions(session: session, state: state)
        }
    }

    private func regularHeaderActions(session: AnalysisSession, state: SessionHeaderRenderState) -> some View {
        let firstQuestionPhase = isFirstQuestionPhase(state)
        return HStack(spacing: 8) {
            if state.hasBlockingAI {
                Button(role: .destructive) {
                    store.cancelCurrentAnalysisSessionAI()
                } label: {
                    SemanticLabel(title: "停止分析", systemImage: "stop.circle", role: .risk)
                }
                .help("停止当前会话正在执行的 AI 任务，迟到结果不会写入会话")
            }

            Button {
                openEvidencePanel()
            } label: {
                SemanticLabel(title: "查看证据", systemImage: "doc.text.magnifyingglass", role: .neutral)
            }
            .buttonStyle(AppHoverButtonStyle(variant: store.isAnalysisInfoSidebarVisible && store.analysisInfoSidebarPanelID == "证据" ? .primary : .secondary))
            .help(state.hasEvidence ? "打开本轮分析证据和本地校验结果" : "打开证据页；当前会话还没有生成分析证据")

            Button {
                flushSelectedGoalDraftToStore(savePolicy: .immediate, touchUpdatedAt: true)
                store.showImportPanel()
            } label: {
                SemanticLabel(title: "导入本地表", systemImage: "tray.and.arrow.down", role: .neutral)
            }
            .disabled(store.isImportingData)
            .buttonStyle(AppHoverButtonStyle(variant: .secondary))
            .help("一次选择多张本地 CSV、TSV、XLSX 或 XLS 表格")

            Button {
                flushSelectedGoalDraftToStore(savePolicy: .immediate, touchUpdatedAt: true)
                store.showTableauImportSheet()
            } label: {
                SemanticLabel(title: "接入 Tableau", systemImage: "chart.bar.doc.horizontal", role: .neutral)
            }
            .disabled(store.isImportingData)
            .buttonStyle(AppHoverButtonStyle(variant: .secondary))
            .help("导入 Tableau View 或 Worksheet 数据")

            Button {
                toggleReadingMode()
            } label: {
                SemanticLabel(title: isFocusMode ? "退出阅读" : "阅读模式", systemImage: isFocusMode ? "rectangle.compress.vertical" : "text.alignleft", role: .neutral)
            }
            .help(isFocusMode ? "恢复主导航和历史会话栏" : "隐藏主导航和历史会话栏，专注阅读当前分析")

            if !firstQuestionPhase {
                Menu {
                    headerMoreMenu(session: session, state: state)
                } label: {
                    SemanticLabel(title: "更多", systemImage: "ellipsis.circle", role: .neutral)
                }
                .hoverControlShell(.pickerShell)
                .help("重分析、机会评分和阅读模式")
            }
        }
    }

    private func compactHeaderActions(session: AnalysisSession, state: SessionHeaderRenderState) -> some View {
        let firstQuestionPhase = isFirstQuestionPhase(state)
        return HStack(spacing: 8) {
            if state.hasBlockingAI {
                Button(role: .destructive) {
                    store.cancelCurrentAnalysisSessionAI()
                } label: {
                    SemanticLabel(title: "停止", systemImage: "stop.circle", role: .risk)
                }
                .help("停止当前会话正在执行的 AI 任务，迟到结果不会写入会话")
            } else if !firstQuestionPhase {
                Button {
                    flushSelectedGoalDraftToStore(savePolicy: .immediate, touchUpdatedAt: true)
                    store.reanalyzeSelectedAnalysisSession(sourcePolicy: selectedSourcePolicy)
                } label: {
                    SemanticLabel(title: "重分析", systemImage: "arrow.clockwise", role: .ai)
                }
                .disabled(!state.hasConfiguredAI || state.selectedReportCount == 0)
                .help(state.selectedReportCount == 0 ? "请先加入至少 1 张表，再重新分析" : "使用重新读取数据分析读取当前任务资料")
            }

            Button {
                openEvidencePanel()
            } label: {
                SemanticLabel(title: "证据", systemImage: "doc.text.magnifyingglass", role: .neutral)
            }
            .buttonStyle(AppHoverButtonStyle(variant: store.isAnalysisInfoSidebarVisible && store.analysisInfoSidebarPanelID == "证据" ? .primary : .secondary))
            .help(state.hasEvidence ? "打开本轮分析证据和本地校验结果" : "打开证据页；当前会话还没有生成分析证据")

            Button {
                flushSelectedGoalDraftToStore(savePolicy: .immediate, touchUpdatedAt: true)
                store.showImportPanel()
            } label: {
                SemanticLabel(title: "导入", systemImage: "tray.and.arrow.down", role: .neutral)
            }
            .disabled(store.isImportingData)
            .help("导入本地表")

            Button {
                flushSelectedGoalDraftToStore(savePolicy: .immediate, touchUpdatedAt: true)
                store.showTableauImportSheet()
            } label: {
                SemanticLabel(title: "Tableau", systemImage: "chart.bar.doc.horizontal", role: .neutral)
            }
            .disabled(store.isImportingData)
            .help("接入 Tableau")

            if !firstQuestionPhase {
                Menu {
                    headerMoreMenu(session: session, state: state)
                } label: {
                    SemanticLabel(title: "更多", systemImage: "ellipsis.circle", role: .neutral)
                }
                .hoverControlShell(.pickerShell)
                .help("更多会话操作")
            }
        }
    }

    @ViewBuilder
    private func headerMoreMenu(session: AnalysisSession, state: SessionHeaderRenderState) -> some View {
        Button {
            flushSelectedGoalDraftToStore(savePolicy: .immediate, touchUpdatedAt: true)
            store.reanalyzeSelectedAnalysisSession(sourcePolicy: selectedSourcePolicy)
        } label: {
            SemanticLabel(title: "重新分析当前任务", systemImage: "arrow.clockwise", role: .neutral)
        }
        .disabled(!state.hasConfiguredAI || state.hasBlockingAI || state.selectedReportCount == 0)

        Divider()

        Button {
            flushSelectedGoalDraftToStore(savePolicy: .immediate, touchUpdatedAt: true)
            store.regenerateOpportunitiesForSelectedSession()
        } label: {
            SemanticLabel(title: "生成机会评分", systemImage: "scope", role: .neutral)
        }
        .disabled(!state.hasConfiguredAI || state.hasBlockingAI)
    }

    private func presentReportScopeSheet(
        _ kind: PendingReportGenerationKind,
        session: AnalysisSession,
        defaultScopeKind: ReportGenerationScopeKind = .fullConversation,
        questionIDs: Set<UUID> = [],
        periodText: String = ""
    ) {
        flushSelectedGoalDraftToStore(savePolicy: .immediate, touchUpdatedAt: true)
        let questionMessages = reportScopeQuestionMessages(in: session, includeExcluded: true)
        reportScopeKind = defaultScopeKind
        if defaultScopeKind.requiresQuestion {
            if !questionIDs.isEmpty {
                reportScopeQuestionIDs = questionIDs
            } else if let lastQuestion = questionMessages.last {
                reportScopeQuestionIDs = [lastQuestion.id]
            } else {
                reportScopeQuestionIDs = []
            }
        } else {
            reportScopeQuestionIDs = []
        }
        reportScopeShowsAllQuestions = false
        reportScopePeriodText = periodText
        pendingReportGenerationKind = kind
    }

    @ViewBuilder
    private func reportScopeSelectionSheet(session: AnalysisSession, kind: PendingReportGenerationKind) -> some View {
        let questionMessages = reportScopeQuestionMessages(in: session, includeExcluded: true)
        let visibleQuestionMessages = reportScopeShowsAllQuestions
            ? questionMessages
            : reportScopeQuestionMessages(in: session, includeExcluded: false)

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                SemanticLabel(title: kind.title, systemImage: kind == .full ? "doc.richtext" : "doc.text", role: kind == .full ? .ai : .knowledge)
                    .font(.headline)
                Spacer()
                Button {
                    pendingReportGenerationKind = nil
                } label: {
                    SemanticIcon(systemName: "xmark", role: .neutral, size: 13, frameWidth: 18)
                }
                .buttonStyle(AppHoverButtonStyle(variant: .ghost))
            }

            Text(kind.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("选择本次汇报范围")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("汇报范围", selection: $reportScopeKind) {
                    ForEach(ReportGenerationScopeKind.allCases) { scopeKind in
                        Text(scopeKind.label).tag(scopeKind)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            if reportScopeKind.requiresQuestion {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("选择问题（可多选）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Toggle("显示全部问题", isOn: $reportScopeShowsAllQuestions)
                            .toggleStyle(.checkbox)
                            .font(.caption)
                    }
                    if questionMessages.isEmpty {
                        Text("当前会话还没有用户业务问题。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(visibleQuestionMessages) { message in
                                    Button {
                                        toggleReportScopeQuestion(message.id)
                                    } label: {
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: reportScopeQuestionIDs.contains(message.id) ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(reportScopeQuestionIDs.contains(message.id) ? AppTheme.accent : AppTheme.mutedText)
                                                .frame(width: 18)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(questionPreview(message.content, limit: 92))
                                                    .font(.callout.weight(.medium))
                                                    .foregroundStyle(.primary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                Text("\(message.createdAt.formatted(date: .numeric, time: .shortened)) · \(message.reportInclusion.label)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(AppHoverButtonStyle(variant: .ghost))
                                }
                            }
                        }
                        .frame(maxHeight: 220)
                    }
                }
            }

            if reportScopeKind.requiresPeriod {
                VStack(alignment: .leading, spacing: 6) {
                    Text("指定周期")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("例如 2026/05/24-2026/05/30、5月最后一周、最近三个月", text: $reportScopePeriodText)
                        .textFieldStyle(.roundedBorder)
                }
            }

            LongTextPreview(
                text: currentReportScopePreview(for: session),
                previewLimit: 900,
                expandedHeight: 140,
                font: .caption,
                foregroundColor: .secondary
            )
                .padding(10)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Button {
                    reportScopeKind = .fullConversation
                    reportScopeQuestionIDs = []
                    reportScopeShowsAllQuestions = false
                    reportScopePeriodText = ""
                } label: {
                    SemanticLabel(title: "重置为当前会话", systemImage: "arrow.counterclockwise", role: .data)
                }
                .buttonStyle(AppHoverButtonStyle(variant: .ghost))

                Spacer()

                Button {
                    pendingReportGenerationKind = nil
                } label: {
                    Text("取消")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .secondary))

                Button {
                    submitReportGeneration(kind, session: session)
                } label: {
                    SemanticLabel(title: kind.title, systemImage: "checkmark", role: .success)
                }
                .buttonStyle(AppHoverButtonStyle(variant: .primary))
            }
        }
        .padding(20)
        .frame(width: 560, alignment: .topLeading)
        .onAppear {
            if reportScopeKind.requiresQuestion, reportScopeQuestionIDs.isEmpty, let lastQuestion = questionMessages.last {
                reportScopeQuestionIDs = [lastQuestion.id]
            }
        }
    }

    private func submitReportGeneration(_ kind: PendingReportGenerationKind, session: AnalysisSession) {
        flushSelectedGoalDraftToStore(savePolicy: .immediate, touchUpdatedAt: true)
        let scope = currentReportScope(for: session)
        pendingReportGenerationKind = nil
        switch kind {
        case .full:
            store.generateMemoFromSelectedAnalysisSession(scope: scope)
        case .simple:
            store.generateSimpleReportFromSelectedAnalysisSession(scope: scope)
        }
    }

    private func currentReportScope(for session: AnalysisSession) -> ReportGenerationScope {
        let selectedQuestions = reportScopeQuestions(in: session)
        let questionTexts = selectedQuestions
            .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let periodText = reportScopePeriodText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch reportScopeKind {
        case .fullConversation:
            return ReportGenerationScope(kind: .fullConversation)
        case .selectedQuestions:
            guard !selectedQuestions.isEmpty else {
                return ReportGenerationScope(kind: .fullConversation)
            }
            return ReportGenerationScope(
                kind: .selectedQuestions,
                selectedQuestionIDs: selectedQuestions.map(\.id),
                selectedQuestionTexts: questionTexts
            )
        case .customPeriod:
            return ReportGenerationScope(
                kind: .customPeriod,
                customPeriodText: periodText
            )
        }
    }

    private func currentReportScopePreview(for session: AnalysisSession) -> String {
        let periodText = reportScopePeriodText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch reportScopeKind {
        case .fullConversation:
            return """
            汇报范围：当前会话全部有效业务问题。
            周期要求：用户未在汇报范围中额外指定周期时，按当前会话和用户问题判断；如仍未指定，必须写明“全周期概览”。
            """
        case .selectedQuestions:
            let selectedQuestions = reportScopeQuestions(in: session)
            let questionPreview = selectedQuestions.prefix(6).enumerated()
                .map { "\($0.offset + 1). \($0.element.content.scopePreviewLine(limit: 180))" }
                .joined(separator: "\n")
            let overflow = selectedQuestions.count > 6 ? "\n…另有 \(selectedQuestions.count - 6) 条问题，生成时会使用完整原文。" : ""
            return """
            汇报范围：只围绕以下用户问题生成汇报，其他会话内容只能作为背景证据。
            指定问题：
            \(questionPreview.isEmpty ? "未找到指定问题，需在汇报中说明范围缺失。" : questionPreview + overflow)
            周期要求：如这些问题未指定周期，必须写明周期来源或全周期概览。
            """
        case .customPeriod:
            return """
            汇报范围：围绕指定周期生成汇报。
            指定周期：\(periodText.isEmpty ? "未填写指定周期，需在汇报中说明范围缺失。" : periodText.scopePreviewLine(limit: 220))
            周期要求：表格分析和外部证据采集必须优先围绕该周期；无法覆盖时写入缺口，不能静默换成其他周期。
            """
        }
    }

    private func reportScopeQuestionMessages(in session: AnalysisSession, includeExcluded: Bool) -> [AnalysisSessionMessage] {
        session.messages.filter { message in
            let inclusionMatches = includeExcluded || message.reportInclusion != .excluded
            return message.role == .user && message.kind == .userRequest && inclusionMatches &&
                !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func reportScopeQuestions(in session: AnalysisSession) -> [AnalysisSessionMessage] {
        let messages = reportScopeQuestionMessages(in: session, includeExcluded: true)
        let selected = messages.filter { reportScopeQuestionIDs.contains($0.id) }
        if !selected.isEmpty { return selected }
        return messages.last.map { [$0] } ?? []
    }

    private func toggleReportScopeQuestion(_ id: UUID) {
        if reportScopeQuestionIDs.contains(id) {
            reportScopeQuestionIDs.remove(id)
        } else {
            reportScopeQuestionIDs.insert(id)
        }
    }

    private func questionPreview(_ text: String, limit: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed.isEmpty ? "未命名问题" : collapsed }
        return String(collapsed.prefix(limit)) + "..."
    }

    private func generateFullReport(for message: AnalysisSessionMessage) {
        guard let session = store.selectedAnalysisSession else {
            store.generateMemoFromSelectedAnalysisSession(scope: ReportGenerationScope(
                kind: .selectedQuestions,
                selectedQuestionIDs: [message.id],
                selectedQuestionTexts: [message.content.trimmingCharacters(in: .whitespacesAndNewlines)]
            ))
            return
        }
        presentReportScopeSheet(.full, session: session, defaultScopeKind: .selectedQuestions, questionIDs: [message.id])
    }

    private func generateSimpleReport(for message: AnalysisSessionMessage) {
        guard let session = store.selectedAnalysisSession else {
            store.generateSimpleReportFromSelectedAnalysisSession(scope: ReportGenerationScope(
                kind: .selectedQuestions,
                selectedQuestionIDs: [message.id],
                selectedQuestionTexts: [message.content.trimmingCharacters(in: .whitespacesAndNewlines)]
            ))
            return
        }
        presentReportScopeSheet(.simple, session: session, defaultScopeKind: .selectedQuestions, questionIDs: [message.id])
    }

    private func chatColumn(session: AnalysisSession) -> some View {
        let latestAssistantID = session.messages.last(where: { $0.role == .assistant && $0.kind != .error })?.id
        let streamingAssistantMessageID = store.blockingAIJob(for: session.id)?.kind == .analysisSession ? latestAssistantID : nil

        return VStack(alignment: .leading, spacing: 0) {
            if !store.hasConfiguredAI {
                WorkflowBlockedBanner(title: "AI 未配置", detail: "分析会话不会生成本地伪分析。请先到 AI 设置填写 API Key、BaseURL 和模型。")
                    .padding(12)
            }
            SessionChatScrollContainer(
                session: session,
                latestAssistantID: latestAssistantID,
                streamingAssistantMessageID: streamingAssistantMessageID,
                expandedMessageIDs: expandedMessageIDs,
                followUpAction: { message in startMessageReply(message, prompt: "") },
                explainEvidenceAction: { message in startMessageReply(message, prompt: "请解释这条回答的关键证据，分别说明哪些是事实、推断、假设和需补数据。") },
                challengeAction: { message in startMessageReply(message, prompt: "我质疑这条结论。请根据我接下来补充的问题，重新判断哪里可能错了，并在最后给出一条可复用的纠偏规则，格式为：误判点 / 修正后结论 / 以后遇到类似情况要检查什么。") },
                correctionAction: { message in store.saveAnalysisSessionMessageAsCorrectionMemory(messageID: message.id) },
                adoptAction: { message in store.adoptAnalysisSessionMessageAsKnowledge(messageID: message.id) },
                importSupplementDataAction: { _ in store.importReportsIntoSelectedPack() },
                markExistingDataAction: { message in startMessageReply(message, prompt: "我认为当前任务里已经有你补数清单提到的数据。请回到本轮 AI 读取范围和当前任务报表里重新核对：哪些补数项其实已覆盖，分别对应哪张表、哪个字段或指标；仍未覆盖的再保留为补数清单。") },
                setReportInclusionAction: { message, inclusion in store.setAnalysisSessionMessageReportInclusion(sessionID: session.id, messageID: message.id, inclusion: inclusion) },
                viewEvidenceAction: { message in openEvidencePanel(message: message) },
                focusMetricEvidenceAction: { message, resultID, sourceCells in
                    openEvidencePanel(message: message)
                    store.focusMetricResultEvidence(
                        messageID: message.id,
                        resultID: resultID,
                        sourceCells: sourceCells
                    )
                },
                generateFullReportAction: { _ in presentReportScopeSheet(.full, session: session) },
                generateFullReportForQuestionAction: { message in generateFullReport(for: message) },
                generateSimpleReportForQuestionAction: { message in generateSimpleReport(for: message) },
                toggleExpandedAction: { id in toggleMessageExpansion(id) }
            )
        }
    }

    private func contextColumn(session: AnalysisSession, pack: DataPack) -> some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                Picker("分析资料分类", selection: $contextPanel) {
                    ForEach(SessionContextPanel.allCases) { panel in
                        Label(panel.rawValue, systemImage: panel.systemImage).tag(panel)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(minWidth: 560, alignment: .leading)
                .hoverControlShell(.segmentedShell)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch contextPanel {
                    case .reports:
                        taskControlSection(session: session, pack: pack)
                        reportSelectionSection(session: session, pack: pack)
                    case .audit:
                        SessionAuditPanel(
                            pack: pack,
                            selectedReportID: $selectedAuditReportID,
                            selectedDictionaryFieldID: $selectedDictionaryFieldID,
                            descriptionDraft: $reportDescriptionDraft,
                            answerText: $reportUnderstandingAnswerText,
                            qaQuestionText: $reportQAQuestionText,
                            dictionaryAnswerText: $dictionaryAnswerText,
                            fieldSearchText: $fieldSearchText,
                            taskNameDraft: $taskNameDraft,
                            taskGoalDraft: $taskGoalDraft
                        )
                    case .quality:
                        DataQualityPanel(pack: pack, showTitle: false)
                    case .coverage:
                        dataCoverageSection(session: session, pack: pack)
                        metricSemanticSection(session: session, pack: pack)
                        SectionCard(title: "记忆策略", systemImage: "brain") {
                            Text("AI 回复默认只保存在当前会话。点击单条 AI 回复下方“沉淀进知识库”，或保存分析模板后，才会进入长期记忆。你可以直接说“按上次一样的指标分析”，系统会先匹配模板再交给 AI。")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    case .computation:
                        notebookEvidenceSection(session: session)
                    case .jobs:
                        aiJobQueueSection(pack: pack)
                    }
                }
                .padding(12)
            }
        }
        .background(AppTheme.window)
    }

    @ViewBuilder
    private func taskControlSection(session: AnalysisSession, pack: DataPack) -> some View {
        SectionCard(title: "1. 选择分析任务", systemImage: "target") {
            if pack.analysisTasks.isEmpty {
                Text("当前还没有分析任务。请新建任务。")
                    .foregroundStyle(.secondary)
            } else {
                Picker("分析任务", selection: Binding(
                    get: { store.currentAnalysisTask(in: pack)?.id ?? pack.analysisTasks.first?.id ?? UUID() },
                    set: {
                        flushSelectedGoalDraftToStore(savePolicy: .immediate, touchUpdatedAt: true)
                        store.selectAnalysisTask(taskID: $0)
                    }
                )) {
                    ForEach(pack.analysisTasks) { task in
                        Text(task.name).tag(task.id)
                    }
                }
                .labelsHidden()
                .hoverControlShell(.pickerShell)
            }
            HStack {
                Button {
                    flushSelectedGoalDraftToStore(savePolicy: .immediate, touchUpdatedAt: true)
                    store.createAnalysisTask()
                    openReportsPanel()
                } label: {
                    SemanticLabel(title: "新建任务", systemImage: "plus", role: .business)
                }
                Button {
                    flushSelectedGoalDraftToStore(savePolicy: .immediate, touchUpdatedAt: true)
                    store.showImportPanel()
                } label: {
                    SemanticLabel(title: "导入本地表", systemImage: "tray.and.arrow.down", role: .data)
                }
                .disabled(store.isImportingData)
                Menu("模板") {
                    Button("按最佳模板选表") {
                        flushSelectedGoalDraftToStore(savePolicy: .immediate, touchUpdatedAt: true)
                        store.applyBestAnalysisTemplateToSelectedTask()
                    }
                    .disabled(store.workspace.analysisTemplateMemories.filter { !$0.isArchived }.isEmpty)
                    Button("把当前任务保存为模板") {
                        flushSelectedGoalDraftToStore(savePolicy: .immediate, touchUpdatedAt: true)
                        store.saveSelectedAnalysisTaskAsTemplate()
                    }
                    .disabled(store.selectedPack.map { store.reportsForCurrentTask(in: $0).isEmpty } ?? true)
                }
                .hoverControlShell(.pickerShell)
            }
            .buttonStyle(AppHoverButtonStyle(variant: .secondary))

            if let task = store.currentAnalysisTask(in: pack) {
                Text("当前任务：\(task.name)。新建任务默认不继承旧任务选表；需要复用上次口径时，请使用“模板”。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("高级：编辑任务目标") {
                    goalEditingSection(session: session)
                }
                .font(.caption)
            }
        }
    }

    private func makeReportSelectionPanelSnapshot(session: AnalysisSession, pack: DataPack) -> ReportSelectionPanelSnapshot {
        let task = store.currentAnalysisTask(in: pack)
        let taskReportIDs = Set(task?.activeReportIDs ?? [])
        let currentReportIDs: Set<UUID>
        if let task = store.currentAnalysisTask(in: pack) ?? session.taskID.flatMap({ id in pack.analysisTasks.first(where: { $0.id == id }) }) {
            currentReportIDs = Set(task.activeReportIDs)
        } else {
            currentReportIDs = Set(session.selectedReportIDs)
        }

        var currentReports: [ImportedReport] = []
        var unassignedVisibleReports: [ImportedReport] = []
        var unassignedCount = 0

        for report in pack.importedReports {
            guard !report.isIgnoredFromAnalysis else { continue }
            if currentReportIDs.contains(report.id) {
                currentReports.append(report)
            }
            if !taskReportIDs.contains(report.id) {
                unassignedCount += 1
                insertReportByImportedAt(report, into: &unassignedVisibleReports, limit: 12)
            }
        }

        return ReportSelectionPanelSnapshot(
            task: task,
            currentReports: currentReports,
            unassignedVisibleReports: unassignedVisibleReports,
            unassignedCount: unassignedCount
        )
    }

    private func insertReportByImportedAt(_ report: ImportedReport, into reports: inout [ImportedReport], limit: Int) {
        guard limit > 0 else { return }
        if reports.count == limit,
           let last = reports.last,
           report.importedAt <= last.importedAt {
            return
        }

        if let index = reports.firstIndex(where: { report.importedAt > $0.importedAt }) {
            reports.insert(report, at: index)
        } else {
            reports.append(report)
        }
        if reports.count > limit {
            reports.removeLast()
        }
    }

    @ViewBuilder
    private func reportSelectionSection(session: AnalysisSession, pack: DataPack) -> some View {
        let selectionSnapshot = makeReportSelectionPanelSnapshot(session: session, pack: pack)
        let task = selectionSnapshot.task
        let currentReports = selectionSnapshot.currentReports
        let unassignedReports = selectionSnapshot.unassignedVisibleReports
        let unassignedCount = selectionSnapshot.unassignedCount

        SectionCard(title: "2. 选择本次分析表", systemImage: "tablecells") {
            reportRoleLegend

            if currentReports.isEmpty {
                Text("还没选表。请在下面“未加入本次分析”里点“加入”，只加入这次要一起联动分析的表。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("AI 只会分析这里的表。选好表后，直接在底部输入你要 AI 分析的问题。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(currentReports) { report in
                    reportTaskRow(report: report, pack: pack, role: task?.role(for: report.id), isInTask: true)
                    Divider()
                }
            }

            if unassignedCount > 0 {
                DisclosureGroup("未加入本次分析 \(unassignedCount) 张", isExpanded: $isUnassignedReportsExpanded) {
                    Text("这些是已导入但未加入本次分析的表；一张表可以被多个任务复用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(unassignedReports) { report in
                        reportTaskRow(report: report, pack: pack, role: nil, isInTask: false)
                        Divider()
                    }
                    if unassignedCount > unassignedReports.count {
                        Text("还有 \(unassignedCount - unassignedReports.count) 张未展开。可继续导入或筛选。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func goalEditingSection(session: AnalysisSession) -> some View {
        return VStack(alignment: .leading, spacing: 8) {
            AdaptiveTextBox(
                text: goalBinding(for: session),
                placeholder: "写清楚你要 AI 回答的问题、比较周期、重点指标或需要联动分析的业务链路。",
                minHeight: 110,
                maxHeight: 260
            )
            Text("目标会同时保存到当前任务和当前会话。目标为空也能开始，AI 会按默认智能分析执行。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    private func reportTaskRow(report: ImportedReport, pack: DataPack, role: AnalysisTaskReportRole?, isInTask: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                reportSummary(report, pack: pack, isInTask: isInTask)
                Spacer(minLength: 8)
                reportRowActions(report: report, role: role, isInTask: isInTask)
            }
            VStack(alignment: .leading, spacing: 8) {
                reportSummary(report, pack: pack, isInTask: isInTask)
                reportRowActions(report: report, role: role, isInTask: isInTask)
            }
        }
        .padding(.vertical, 4)
    }

    private func reportSummary(_ report: ImportedReport, pack: DataPack, isInTask: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(report.displayName)
                    .fontWeight(.medium)
                    .lineLimit(2)
                Badge(
                    text: reportTaskStateLabel(report: report, pack: pack, isInTask: isInTask),
                    systemImage: nil,
                    tint: isInTask ? AppTheme.success : (isReportUsedByOtherTask(report.id, in: pack) ? AppTheme.warning : .secondary)
                )
            }
            Text("\(report.sourceFormat.label) · \(report.shape.label) · \(report.kind.label) · \(report.rowCount) 行 · \(report.headers.count) 列 · 首列指标 \(report.firstColumnValues.count) 个")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reportTaskStateLabel(report: ImportedReport, pack: DataPack, isInTask: Bool) -> String {
        if isInTask { return "已加入当前任务" }
        if isReportUsedByOtherTask(report.id, in: pack) { return "来自其他任务" }
        return "未加入当前任务"
    }

    private func isReportUsedByOtherTask(_ reportID: UUID, in pack: DataPack) -> Bool {
        let currentTaskID = store.currentAnalysisTask(in: pack)?.id
        return pack.analysisTasks.contains { task in
            task.id != currentTaskID && task.activeReportIDs.contains(reportID)
        }
    }

    @ViewBuilder
    private func reportRowActions(report: ImportedReport, role: AnalysisTaskReportRole?, isInTask: Bool) -> some View {
        if isInTask {
            HStack {
                Menu(role?.label ?? "旁证") {
                    ForEach(AnalysisTaskReportRole.allCases) { item in
                        Button(item.label) {
                            flushSelectedGoalDraftToStore(savePolicy: .immediate, touchUpdatedAt: true)
                            store.setSelectedTaskReportRole(reportID: report.id, role: item)
                        }
                        .help(item.explanation)
                    }
                }
                .controlSize(.small)
                .hoverControlShell(.pickerShell)
                .help(role?.explanation ?? AnalysisTaskReportRole.evidence.explanation)

                Button {
                    flushSelectedGoalDraftToStore(savePolicy: .immediate, touchUpdatedAt: true)
                    store.removeReportFromSelectedTask(reportID: report.id)
                } label: {
                    SemanticLabel(title: "移出", systemImage: "minus.circle", role: .risk)
                }
                .buttonStyle(AppHoverButtonStyle(variant: .danger))
                .controlSize(.small)
            }
            .font(.caption)
        } else {
            Button {
                flushSelectedGoalDraftToStore(savePolicy: .immediate, touchUpdatedAt: true)
                let currentCount = store.selectedPack.map { store.reportsForCurrentTask(in: $0).count } ?? 0
                store.addReportToSelectedTask(reportID: report.id, role: currentCount == 0 ? .primaryBusiness : .evidence)
            } label: {
                SemanticLabel(title: "加入本次分析", systemImage: "plus.circle.fill", role: .success)
            }
            .buttonStyle(AppHoverButtonStyle(variant: .primary))
            .controlSize(.small)
            .help("把这张表加入当前分析任务")
        }
    }

    private var reportRoleLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            SemanticLabel(title: "角色只帮助 AI 区分主次和证据用途，不会限制 AI 读取表格里的所有字段和指标。", systemImage: "info.circle", role: .data)
                .fontWeight(.medium)
            ForEach(AnalysisTaskReportRole.allCases) { role in
                HStack(alignment: .top, spacing: 8) {
                    Text(role.label)
                        .fontWeight(.semibold)
                        .frame(width: 76, alignment: .leading)
                    Text(role.explanation)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(8)
        .background(AppTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    private func scheduleCoveragePanelRefresh(delayNanoseconds: UInt64 = 220_000_000) {
        coveragePanelRefreshTask?.cancel()
        coveragePanelRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            refreshCoveragePanelSnapshot(force: false)
            coveragePanelRefreshTask = nil
        }
    }

    private func refreshCoveragePanelSnapshot(force: Bool) {
        let revision = makeCoveragePanelRevision()
        guard force || revision != coveragePanelRevision else { return }
        if let session = store.selectedAnalysisSession,
           let pack = store.selectedPack,
           session.packID == pack.id {
            coveragePanelSnapshot = makeCoveragePanelSnapshot(session: session, pack: pack)
        } else {
            coveragePanelSnapshot = .empty
        }
        coveragePanelRevision = revision
    }

    private func makeCoveragePanelSnapshot(session: AnalysisSession, pack: DataPack) -> AnalysisCoveragePanelSnapshot {
        let reports = selectedReports(for: session, pack: pack)
        let relatedRuns = relatedReferenceCollectionRuns(session: session, pack: pack, limit: 3)
        let requirementDigest = session.reportRequirementDigest ?? ReportRequirementDigestBuilder.build(session: session)
        let spaceID = store.selectedBusinessSpace?.id
        let scopedKnowledgeCount = store.workspace.knowledgeEntries.lazy.filter { entry in
            entry.isGlobal || entry.businessSpaceID == spaceID
        }.count
        let sourceByID = Dictionary(uniqueKeysWithValues: store.workspace.referenceSources.map { ($0.id, $0) })
        let scopedReferenceCount = store.workspace.referenceItems.lazy.filter { item in
            item.isVisible(in: spaceID, sourceByID: sourceByID)
        }.count
        let scopedCorrectionCount = store.workspace.correctionMemories.lazy.filter { memory in
            memory.appliesToFuture && memory.businessSpaceID == spaceID
        }.count
        let scopedCandidateCount = store.workspace.smartMemoryCandidates.lazy.filter { candidate in
            candidate.status == .pending && candidate.businessSpaceID == spaceID
        }.count

        return AnalysisCoveragePanelSnapshot(
            sessionID: session.id,
            packID: pack.id,
            reports: reports,
            relatedRuns: relatedRuns,
            requirementDigest: requirementDigest,
            scopedKnowledgeCount: scopedKnowledgeCount,
            confluencePageCount: store.workspace.confluencePages.count,
            scopedReferenceCount: scopedReferenceCount,
            scopedCorrectionCount: scopedCorrectionCount,
            scopedCandidateCount: scopedCandidateCount
        )
    }

    private func relatedReferenceCollectionRuns(
        session: AnalysisSession,
        pack: DataPack,
        limit: Int
    ) -> [ExternalReferenceCollectionRun] {
        let relatedTaskID = (store.currentAnalysisTask(in: pack) ?? session.taskID.flatMap { id in
            pack.analysisTasks.first(where: { $0.id == id })
        })?.id
        var runs: [ExternalReferenceCollectionRun] = []
        for run in store.workspace.referenceCollectionRuns {
            guard run.sessionID == session.id ||
                run.taskID == relatedTaskID ||
                run.packID == pack.id else {
                continue
            }
            insertReferenceRunByStartedAt(run, into: &runs, limit: limit)
        }
        return runs
    }

    private func insertReferenceRunByStartedAt(
        _ run: ExternalReferenceCollectionRun,
        into runs: inout [ExternalReferenceCollectionRun],
        limit: Int
    ) {
        guard limit > 0 else { return }
        if runs.count == limit,
           let last = runs.last,
           run.startedAt <= last.startedAt {
            return
        }

        if let index = runs.firstIndex(where: { run.startedAt > $0.startedAt }) {
            runs.insert(run, at: index)
        } else {
            runs.append(run)
        }
        if runs.count > limit {
            runs.removeLast()
        }
    }

    private func makeCoveragePanelRevision() -> AnalysisCoveragePanelRevision {
        guard let session = store.selectedAnalysisSession,
              let pack = store.selectedPack,
              session.packID == pack.id else {
            return AnalysisCoveragePanelRevision(
                sessionID: nil,
                packID: nil,
                selectedBusinessSpaceID: store.workspace.selectedBusinessSpaceID,
                sessionHash: 0,
                packHash: 0,
                referenceCollectionRunHash: 0,
                knowledgeHash: 0,
                referenceSourceHash: 0,
                referenceItemHash: 0,
                correctionMemoryHash: 0,
                smartCandidateHash: 0,
                confluencePageCount: store.workspace.confluencePages.count
            )
        }

        var sessionHasher = Hasher()
        sessionHasher.combine(session.id)
        sessionHasher.combine(session.taskID)
        sessionHasher.combine(session.selectedReportIDs)
        sessionHasher.combine(session.reportRequirementDigest)
        sessionHasher.combine(session.goal)
        if let latestCoverage = session.coverageSnapshots?.last {
            sessionHasher.combine(latestCoverage.id)
            sessionHasher.combine(latestCoverage.createdAt)
            sessionHasher.combine(latestCoverage.totalReports)
            sessionHasher.combine(latestCoverage.totalRows)
            sessionHasher.combine(latestCoverage.totalColumns)
            sessionHasher.combine(latestCoverage.totalMetrics)
            sessionHasher.combine(latestCoverage.totalTimeColumns)
            sessionHasher.combine(latestCoverage.referenceItemCount)
        } else {
            sessionHasher.combine(0)
        }
        for message in session.messages {
            sessionHasher.combine(message.id)
            sessionHasher.combine(message.role)
            sessionHasher.combine(message.kind)
            sessionHasher.combine(message.reportInclusion)
            sessionHasher.combine(message.correctionStatus)
            sessionHasher.combine(message.adoptedAs)
            if message.role == .user {
                sessionHasher.combine(message.content)
            }
        }

        var packHasher = Hasher()
        packHasher.combine(pack.id)
        for task in pack.analysisTasks {
            packHasher.combine(task.id)
            packHasher.combine(task.activeReportIDs)
        }
        for report in pack.importedReports {
            packHasher.combine(report.id)
            packHasher.combine(report.importedAt)
            packHasher.combine(report.isIgnoredFromAnalysis)
            packHasher.combine(report.tableContextCoverage)
        }

        var referenceRunHasher = Hasher()
        for run in store.workspace.referenceCollectionRuns {
            referenceRunHasher.combine(run)
        }

        let spaceID = store.selectedBusinessSpace?.id
        var knowledgeHasher = Hasher()
        for entry in store.workspace.knowledgeEntries {
            guard entry.isGlobal || entry.businessSpaceID == spaceID else { continue }
            knowledgeHasher.combine(entry.id)
            knowledgeHasher.combine(entry.businessSpaceID)
            knowledgeHasher.combine(entry.isGlobal)
        }

        var sourceHasher = Hasher()
        for source in store.workspace.referenceSources {
            sourceHasher.combine(source.id)
            sourceHasher.combine(source.isGlobal)
            sourceHasher.combine(source.businessSpaceIDs)
        }

        var referenceItemHasher = Hasher()
        for item in store.workspace.referenceItems {
            referenceItemHasher.combine(item.id)
            referenceItemHasher.combine(item.sourceID)
            referenceItemHasher.combine(item.businessSpaceID)
        }

        var correctionHasher = Hasher()
        for memory in store.workspace.correctionMemories {
            correctionHasher.combine(memory.id)
            correctionHasher.combine(memory.businessSpaceID)
            correctionHasher.combine(memory.appliesToFuture)
        }

        var candidateHasher = Hasher()
        for candidate in store.workspace.smartMemoryCandidates {
            candidateHasher.combine(candidate.id)
            candidateHasher.combine(candidate.businessSpaceID)
            candidateHasher.combine(candidate.status)
        }

        return AnalysisCoveragePanelRevision(
            sessionID: session.id,
            packID: pack.id,
            selectedBusinessSpaceID: store.workspace.selectedBusinessSpaceID,
            sessionHash: sessionHasher.finalize(),
            packHash: packHasher.finalize(),
            referenceCollectionRunHash: referenceRunHasher.finalize(),
            knowledgeHash: knowledgeHasher.finalize(),
            referenceSourceHash: sourceHasher.finalize(),
            referenceItemHash: referenceItemHasher.finalize(),
            correctionMemoryHash: correctionHasher.finalize(),
            smartCandidateHash: candidateHasher.finalize(),
            confluencePageCount: store.workspace.confluencePages.count
        )
    }

    private func dataCoverageSection(session: AnalysisSession, pack: DataPack) -> some View {
        SectionCard(title: "AI 已参考", systemImage: "eye") {
            let panelSnapshot = coveragePanelSnapshot.sessionID == session.id && coveragePanelSnapshot.packID == pack.id
                ? coveragePanelSnapshot
                : .empty
            let reports = panelSnapshot.reports
            if let snapshot = session.coverageSnapshots?.last {
                VStack(alignment: .leading, spacing: 6) {
                    Text("最近一轮覆盖快照")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(snapshot.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup("AI 读取到的数据") {
                        Text(AnalysisCoverageSnapshotBuilder.aiReadRangeMarkdown(snapshot))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), alignment: .leading)], alignment: .leading, spacing: 8) {
                        KeyValueRow(key: "上下文模式", value: snapshot.contextMode?.label ?? "未记录")
                        KeyValueRow(key: "读取表", value: "\(snapshot.totalReports) 张")
                        KeyValueRow(key: "指标", value: "\(snapshot.totalMetrics) 个")
                        KeyValueRow(key: "时间周期", value: "\(snapshot.totalTimeColumns) 个")
                        KeyValueRow(key: "排除周期", value: "\(snapshot.excludedPeriodCount) 个")
                        KeyValueRow(key: "画像/样本表", value: "\(snapshot.profileOnlyReportCount) 张")
                        KeyValueRow(key: "联动异常", value: "\((snapshot.metricLinkageAnomalies ?? []).count) 个")
                        KeyValueRow(key: "外部证据", value: "\(snapshot.externalEvidenceMatchedCount ?? 0) 条")
                        KeyValueRow(key: "外部搜索", value: snapshot.externalEvidenceCoverage?.searchTriggered == true ? "已触发" : "未触发")
                    }
                    if let periodIntent = snapshot.periodIntent {
                        Text("周期口径：\(periodIntent.summary)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let window = snapshot.externalEvidenceWindow {
                        Text("外部证据窗口：\(window.summary)。仅发布时间 \(snapshot.externalEvidencePublishedOnlyCount ?? 0) 条；仅采集时间 \(snapshot.externalEvidenceCollectedOnlyCount ?? 0) 条。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let evidenceCoverage = snapshot.externalEvidenceCoverage {
                        Text("外部搜索状态：\(evidenceCoverage.summary)")
                            .font(.caption)
                            .foregroundStyle(evidenceCoverage.searchTriggered ? AppTheme.success : AppTheme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    let relatedRuns = panelSnapshot.relatedRuns
                    if !relatedRuns.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("本轮关联采集任务")
                                .font(.caption)
                                .fontWeight(.semibold)
                            ForEach(relatedRuns) { run in
                                Text("\(run.trigger.label) · \(run.status.label) · \(DateFormatting.shortDateTime.string(from: run.startedAt)) · \(run.summary)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if let description = snapshot.contextStrategyDescription {
                        Text("模式说明：\(description)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let anomalies = snapshot.metricLinkageAnomalies, !anomalies.isEmpty {
                        let visibleAnomalies = Array(anomalies.sorted { $0.confidence > $1.confidence }.prefix(5))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("指标联动异常候选")
                                .font(.caption)
                                .fontWeight(.semibold)
                            ForEach(visibleAnomalies) { anomaly in
                                Text("[\(anomaly.anomalyType.label)] \(anomaly.sourceMetric) → \(anomaly.targetMetric)：\(anomaly.changeGapText)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if !snapshot.limitations.isEmpty {
                        Text("限制：\(snapshot.limitations.prefix(6).joined(separator: "；"))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider()
            } else {
                Text("还没有生成覆盖快照。发送给 AI 前会自动保存一份，明确本轮看了哪些表、指标、周期和遗漏范围。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
            }
            let requirementDigest = panelSnapshot.requirementDigest
            if requirementDigest.coveredQuestionCount > 0 {
                DisclosureGroup("汇报需求清单 \(requirementDigest.coveredQuestionCount) 个问题") {
                    Text(requirementDigest.markdown)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
            }
            KeyValueRow(key: "任务报表", value: "\(reports.count) 张")
            KeyValueRow(key: "知识库", value: "\(panelSnapshot.scopedKnowledgeCount) 条")
            KeyValueRow(key: "Confluence", value: "\(panelSnapshot.confluencePageCount) 页")
            KeyValueRow(key: "参照数据", value: "\(panelSnapshot.scopedReferenceCount) 条")
            KeyValueRow(key: "纠偏记忆", value: "\(panelSnapshot.scopedCorrectionCount) 条")
            KeyValueRow(key: "智能记忆候选", value: "\(panelSnapshot.scopedCandidateCount) 条待确认")
            Divider()
            if reports.isEmpty {
                Text("当前任务还没有选择表。请在“分析资料”中加入本次要分析的表。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(reports.prefix(8)) { report in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(report.displayName)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Spacer()
                            Badge(text: report.tableContextCoverage == nil ? "待打包" : "已打包", systemImage: nil, tint: report.tableContextCoverage == nil ? AppTheme.warning : AppTheme.success)
                        }
                        if let coverage = report.tableContextCoverage {
                            Text("\(coverage.summary)。\(coverage.omittedRowsDescription)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("\(report.sourceFormat.label) · \(report.shape.label) · \(report.rowCount) 行 · \(report.headers.count) 列 · 首列指标 \(report.firstColumnValues.count) 个")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let analysis = report.aiFirstAnalysis {
                            Text(analysis.readyForAnalysis ? "AI 表格理解已完成：\(analysis.summary)" : "AI 表格理解待补数据：\(analysis.dataAvailability)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    Divider()
                }
            }
            if let snapshots = session.coverageSnapshots, snapshots.count > 1 {
                DisclosureGroup("覆盖快照历史 \(snapshots.count) 条") {
                    ForEach(Array(snapshots.suffix(8).reversed())) { snapshot in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(DateFormatting.shortDateTime.string(from: snapshot.createdAt))
                                .font(.caption)
                                .fontWeight(.medium)
                            Text(snapshot.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    private func notebookEvidenceSection(session: AnalysisSession) -> some View {
        SectionCard(title: "Notebook / SQL 计算证据", systemImage: "function") {
            if session.notebookRuns.isEmpty {
                Text("还没有计算证据。重新读取数据分析时，系统会在后台用 DuckDB 执行只读 SQL，并把计算过程保存在这里。普通用户不需要写 SQL。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("这里展示 AI 后台使用的本地计算证据：读了哪些表、执行了哪些 SQL、结果是什么、哪些计算失败。SQL 只在本机 DuckDB 内存库执行，不联网执行。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(Array(session.notebookRuns.suffix(8).reversed())) { run in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 10) {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 8) {
                                    KeyValueRow(key: "引擎", value: run.engine)
                                    KeyValueRow(key: "触发", value: run.trigger)
                                    KeyValueRow(key: "单元", value: "\(run.cells.count) 个")
                                    KeyValueRow(key: "失败", value: "\(run.failedCount) 个")
                                }
                                if !run.warnings.isEmpty {
                                    Text("限制：\(run.warnings.joined(separator: "；"))")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.warning)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                ForEach(run.cells) { cell in
                                    notebookCellView(cell)
                                }
                            }
                            .padding(.top, 6)
                        } label: {
                            HStack(spacing: 8) {
                                Badge(text: run.failedCount > 0 ? "部分失败" : "已完成", systemImage: nil, tint: run.failedCount > 0 ? AppTheme.warning : AppTheme.success)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(DateFormatting.shortDateTime.string(from: run.createdAt))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text("\(run.skillSummary) · \(run.summary)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        Divider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func notebookCellView(_ cell: AnalysisNotebookCell) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                if !cell.markdown.isEmpty {
                    Text(cell.markdown)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !cell.sql.isEmpty {
                    Text(cell.sql)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                }
                if !cell.columns.isEmpty {
                    notebookResultPreview(columns: cell.columns, rows: cell.rows)
                }
                if let errorMessage = cell.errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(cell.status == .failed ? AppTheme.danger : AppTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 8) {
                Badge(text: cell.status.label, systemImage: nil, tint: cell.status == .failed ? AppTheme.danger : (cell.status == .skipped ? AppTheme.warning : AppTheme.success))
                Text(cell.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(cell.rowCount) 行")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func notebookResultPreview(columns: [String], rows: [[String]]) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(columns, id: \.self) { column in
                        Text(column)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .frame(width: 128, alignment: .leading)
                            .padding(6)
                            .background(.secondary.opacity(0.12))
                    }
                }
                ForEach(Array(rows.prefix(12).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(columns.indices, id: \.self) { index in
                            Text(index < row.count ? row[index] : "")
                                .font(.caption2)
                                .lineLimit(3)
                                .frame(width: 128, alignment: .leading)
                                .padding(6)
                                .border(.separator.opacity(0.35), width: 0.5)
                        }
                    }
                }
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func metricSemanticSection(session: AnalysisSession, pack: DataPack) -> some View {
        let profiles = selectedReports(for: session, pack: pack)
            .flatMap { report in
                report.metricSemanticProfiles.prefix(8).map { (report, $0) }
            }
        SectionCard(title: "指标语义层", systemImage: "point.3.connected.trianglepath.dotted") {
            if profiles.isEmpty {
                Text("暂无指标语义。导入新表、在会话中解释指标，或使用 AI 预读后，系统会为关键指标沉淀业务阶段、好坏方向、成熟窗口、时滞和常见异常解释。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(profiles.prefix(16).enumerated()), id: \.offset) { _, item in
                    let report = item.0
                    let profile = item.1
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(profile.metricName)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Spacer()
                            Badge(text: profile.isUserConfirmed ? "已确认" : "待确认", systemImage: nil, tint: profile.isUserConfirmed ? AppTheme.success : AppTheme.warning)
                        }
                        Text("\(report.displayName) · \(profile.businessStage.label) · \(profile.directionPreference.label) · \(profile.maturityWindowDays.map { "\($0)天成熟" } ?? "无成熟窗口") · \(profile.impactLagDays.map { "\($0)天时滞" } ?? "无明确时滞")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !profile.commonAnomalyExplanations.isEmpty {
                            Text("常见异常：\(profile.commonAnomalyExplanations.prefix(3).joined(separator: "、"))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !profile.isUserConfirmed {
                            Button("确认这个指标语义") {
                                store.confirmMetricSemanticProfile(reportID: report.id, metricName: profile.metricName)
                            }
                            .buttonStyle(AppHoverButtonStyle(variant: .link))
                            .font(.caption)
                        }
                    }
                    Divider()
                }
            }
        }
    }

    private func aiJobQueueSection(pack: DataPack) -> some View {
        SectionCard(title: "AI 任务队列", systemImage: "clock.arrow.circlepath") {
            let jobs = sortedAIJobs(store.latestAIJobRecords(for: pack, limit: 12))
            if jobs.isEmpty {
                Text("暂无 AI 后台任务。发送会话或生成观察后，这里会显示请求、校验、重试和需处理状态。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                aiJobQueueSummary(jobs)
                ForEach(jobs) { job in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 6) {
                            if !job.lastError.isEmpty {
                                Text(job.lastError)
                                    .font(.caption)
                                    .foregroundStyle(job.status == .needsUserAction ? AppTheme.danger : AppTheme.warning)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if job.logs.isEmpty {
                                Text("暂无详细日志。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                let sortedLogs = job.logs.sorted { $0.createdAt < $1.createdAt }
                                ForEach(sortedLogs) { log in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(DateFormatting.shortDateTime.string(from: log.createdAt)) · \(log.status.label)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(log.detail)
                                            .font(.caption)
                                            .textSelection(.enabled)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            HStack {
                                if job.status == .needsUserAction || job.status == .cancelled || job.status == .failed {
                                    Button("重试") {
                                        store.retryAIJob(job.id)
                                    }
                                }
                                if job.status == .waiting || job.status == .requesting || job.status == .validating || job.status == .correcting {
                                    Button("取消") {
                                        store.cancelAIJob(job.id)
                                    }
                                }
                                if !job.lastError.isEmpty {
                                    Button("复制错误") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(job.lastError, forType: .string)
                                    }
                                }
                            }
                            .buttonStyle(AppHoverButtonStyle(variant: .ghost))
                            .font(.caption)
                        }
                        .padding(.top, 4)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(job.jobType)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                Spacer()
                                Badge(text: jobStatusLabel(job), systemImage: nil, tint: jobStatusTint(job.status))
                            }
                            Text(jobMetaText(job))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if !job.lastError.isEmpty && (job.status == .needsUserAction || job.status == .failed) {
                                Text(job.lastError)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.danger)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Divider()
                }
            }
        }
    }

    private func aiJobQueueSummary(_ jobs: [AIJobRecord]) -> some View {
        let needsHandling = jobs.filter { $0.status == .needsUserAction || $0.status == .failed }.count
        let running = jobs.filter { $0.status == .requesting || $0.status == .validating || $0.status == .correcting }.count
        let waitingRetry = jobs.filter { $0.status == .waiting && $0.nextRunAt != nil }.count
        let summary: (String, Color, String) = {
            if needsHandling > 0 {
                return ("有 \(needsHandling) 个任务需要处理", AppTheme.danger, "exclamationmark.circle")
            }
            if running > 0 {
                return ("有 \(running) 个任务正在执行", AppTheme.accent, "arrow.triangle.2.circlepath")
            }
            if waitingRetry > 0 {
                return ("有 \(waitingRetry) 个任务等待自动重试", AppTheme.warning, "clock.arrow.circlepath")
            }
            return ("最近 AI 任务状态正常", AppTheme.success, "checkmark.circle")
        }()

        return HStack(spacing: 8) {
            SemanticIcon(systemName: summary.2, color: summary.1, size: 15, frameWidth: 18)
            Text(summary.0)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(summary.1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(summary.1.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private func sortedAIJobs(_ jobs: [AIJobRecord]) -> [AIJobRecord] {
        jobs.sorted { lhs, rhs in
            let lhsRank = aiJobSortRank(lhs)
            let rhsRank = aiJobSortRank(rhs)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func aiJobSortRank(_ job: AIJobRecord) -> Int {
        switch job.status {
        case .needsUserAction, .failed:
            return 0
        case .requesting, .validating, .correcting:
            return 1
        case .waiting:
            return 2
        case .completed:
            return 3
        case .cancelled:
            return 4
        }
    }

    private func jobStatusLabel(_ job: AIJobRecord) -> String {
        if job.status == .waiting, job.nextRunAt != nil {
            return "等待重试"
        }
        return job.status.label
    }

    private func jobStatusTint(_ status: AIJobStatus) -> Color {
        switch status {
        case .completed: return AppTheme.success
        case .needsUserAction, .failed: return AppTheme.danger
        case .cancelled: return .secondary
        case .waiting: return AppTheme.warning
        case .requesting, .validating, .correcting: return AppTheme.accent
        }
    }

    private func jobMetaText(_ job: AIJobRecord) -> String {
        var parts = [
            job.targetName.nilIfBlank ?? "当前任务",
            "\(job.attemptCount)/\(job.maxAttempts) 次",
            DateFormatting.shortDateTime.string(from: job.updatedAt)
        ]
        if let nextRunAt = job.nextRunAt, job.status == .waiting {
            parts.append("下次重试 \(DateFormatting.shortDateTime.string(from: nextRunAt))")
        }
        return parts.joined(separator: " · ")
    }

    private func composer(session: AnalysisSession, pack: DataPack) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            let state = sessionRenderState(session: session, pack: pack)
            let hasPreviousAI = session.messages.contains { $0.role == .assistant && ($0.kind == .aiAnalysis || $0.kind == .aiMemo || $0.kind == .simpleReport) }
            let activeJob = store.runningBlockingAIJobForSelectedAnalysisSession.map(LiveAIJobSnapshot.init)
            let hasBlockingAI = activeJob != nil
            let hasInput = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasSelectedReports = state.selectedReportCount > 0
            let effectiveSelectedMode = effectiveComposerMode(hasPreviousAI: hasPreviousAI)
            let firstQuestionPhase = isFirstQuestionPhase(state)

            VStack(alignment: .leading, spacing: 9) {
                composerSurfaceHeader(
                    state: state,
                    hasPreviousAI: hasPreviousAI,
                    effectiveSelectedMode: effectiveSelectedMode
                )

                if let quoted = replyingMessage(in: session) {
                    composerQuotedMessage(quoted)
                }

                if let activeJob {
                    InlineThinkingStatusView(
                        job: activeJob,
                        cancelAction: { store.cancelCurrentAnalysisSessionAI() }
                    )
                }

                if !hasSelectedReports {
                    composerReportSelectionWarning()
                }

                composerTextInput

                if composerToolsExpanded && !firstQuestionPhase {
                    composerExpandedToolTray(session: session, state: state)
                }

                if firstQuestionPhase {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            composerAttachmentButton()
                            composerSelectedReportsButton(pack: pack, state: state)
                            composerSourcePolicyMenu(hasBlockingAI: hasBlockingAI)
                            Spacer(minLength: 0)
                            if hasBlockingAI {
                                composerStopToolbarButton()
                            } else {
                                composerSendButton(
                                    hasPreviousAI: hasPreviousAI,
                                    hasInput: hasInput,
                                    hasBlockingAI: hasBlockingAI,
                                    hasSelectedReports: hasSelectedReports,
                                    forceMode: effectiveSelectedMode
                                )
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                composerAttachmentButton()
                                composerSelectedReportsButton(pack: pack, state: state)
                                Spacer(minLength: 0)
                                if hasBlockingAI {
                                    composerStopToolbarButton()
                                } else {
                                    composerSendButton(
                                        hasPreviousAI: hasPreviousAI,
                                        hasInput: hasInput,
                                        hasBlockingAI: hasBlockingAI,
                                        hasSelectedReports: hasSelectedReports,
                                        forceMode: effectiveSelectedMode
                                    )
                                }
                            }
                            composerSourcePolicyMenu(hasBlockingAI: hasBlockingAI)
                        }
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 8) {
                            composerAttachmentButton()
                            composerSelectedReportsButton(pack: pack, state: state)
                            composerModeControls(hasBlockingAI: hasBlockingAI)
                            composerSourcePolicyMenu(hasBlockingAI: hasBlockingAI)
                            Spacer(minLength: 8)
                            composerMoreToggleButton
                            composerSendButton(
                                hasPreviousAI: hasPreviousAI,
                                hasInput: hasInput,
                                hasBlockingAI: hasBlockingAI,
                                hasSelectedReports: hasSelectedReports,
                                forceMode: effectiveSelectedMode
                            )
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                composerAttachmentButton()
                                composerSelectedReportsButton(pack: pack, state: state)
                                composerSourcePolicyMenu(hasBlockingAI: hasBlockingAI)
                                Spacer(minLength: 0)
                                composerSendButton(
                                    hasPreviousAI: hasPreviousAI,
                                    hasInput: hasInput,
                                    hasBlockingAI: hasBlockingAI,
                                    hasSelectedReports: hasSelectedReports,
                                    forceMode: effectiveSelectedMode
                                )
                            }
                            HStack {
                                composerModeControls(hasBlockingAI: hasBlockingAI)
                                Spacer(minLength: 0)
                                composerMoreToggleButton
                            }
                        }
                    }
                }

                Button {
                    selectedComposerMode = .fullReanalysis
                    sendComposerMessage(forceMode: .fullReanalysis)
                } label: {
                    EmptyView()
                }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(!store.hasConfiguredAI || hasBlockingAI || !hasInput || !hasSelectedReports)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
            }
            .padding(12)
            .background(AppTheme.panel.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppTheme.border.opacity(0.58), lineWidth: 1)
            }
        }
        .padding(14)
    }

    private var composerMoreToggleButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.14)) {
                composerToolsExpanded.toggle()
            }
        } label: {
            ComposerToolbarIcon(systemImage: composerToolsExpanded ? "chevron.down.circle" : "ellipsis.circle")
        }
        .buttonStyle(.plain)
                .help(composerToolsExpanded ? "收起会话工具" : "展开重分析、常用问题和更多操作")
    }

    private func composerAttachmentButton() -> some View {
        Button {
            store.showImportPanel()
        } label: {
            ComposerToolbarIcon(systemImage: "paperclip")
        }
        .buttonStyle(.plain)
        .disabled(store.isImportingData)
        .help("导入本地表格文件作为分析资料")
    }

    private func composerSelectedReportsButton(pack: DataPack, state: SessionHeaderRenderState) -> some View {
        Button {
            showComposerReportPicker.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: state.selectedReportCount > 0 ? "tablecells" : "tablecells.badge.ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(state.selectedReportCount > 0 ? "已选 \(state.selectedReportCount) 张表" : "未选表")
                    .font(AppFont.caption(weight: .semibold))
                    .lineLimit(1)
                Image(systemName: showComposerReportPicker ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppTheme.faintText)
            }
            .foregroundStyle(state.selectedReportCount > 0 ? AppTheme.text : AppTheme.warning)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                (state.selectedReportCount > 0 ? AppTheme.panelStrong.opacity(0.46) : AppTheme.warning.opacity(0.10)),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        state.selectedReportCount > 0 ? AppTheme.border.opacity(0.46) : AppTheme.warning.opacity(0.28),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showComposerReportPicker, arrowEdge: .bottom) {
            composerSelectedReportsPopover(pack: pack)
                .frame(width: 430)
                .appThemeRoot()
        }
        .help(state.selectedReportCount > 0 ? "查看或调整本次分析表" : "请先加入至少 1 张表")
    }

    private func composerSelectedReportsPopover(pack: DataPack) -> some View {
        let reports = store.reportsForCurrentTask(in: pack)
        let task = store.currentAnalysisTask(in: pack)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("本次分析表")
                        .font(AppFont.headline())
                    Text(reports.isEmpty ? "还没有选择表，先导入或加入至少 1 张表。" : "\(reports.count) 张表会进入下一次分析。")
                        .font(AppFont.caption())
                        .foregroundStyle(AppTheme.mutedText)
                }
                Spacer(minLength: 0)
                Button {
                    showComposerReportPicker = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.icon)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }

            if reports.isEmpty {
                composerEmptyReportsPopoverState()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(reports) { report in
                            composerSelectedReportRow(
                                report: report,
                                role: task?.role(for: report.id) ?? .evidence
                            )
                            if report.id != reports.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    showComposerReportPicker = false
                    store.showImportPanel()
                } label: {
                    SemanticLabel(title: "导入本地表", systemImage: "tray.and.arrow.down", role: .neutral)
                }
                .buttonStyle(AppHoverButtonStyle(variant: .secondary))
                .controlSize(.small)

                Button {
                    showComposerReportPicker = false
                    store.showTableauImportSheet()
                } label: {
                    SemanticLabel(title: "接入 Tableau", systemImage: "chart.bar.doc.horizontal", role: .neutral)
                }
                .buttonStyle(AppHoverButtonStyle(variant: .secondary))
                .controlSize(.small)

                Spacer(minLength: 0)

                Button {
                    showComposerReportPicker = false
                    openReportsPanel()
                } label: {
                    Text("管理")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .secondary))
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(AppTheme.surface)
    }

    private func composerEmptyReportsPopoverState() -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.warning)
                .frame(width: 18)
            Text("未选择分析表时不能发送给 AI。导入表格后会直接进入确认本次分析表。")
                .font(AppFont.caption())
                .foregroundStyle(AppTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panelStrong.opacity(0.38), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(AppTheme.border.opacity(0.42), lineWidth: 1)
        }
    }

    private func composerSelectedReportRow(report: ImportedReport, role: AnalysisTaskReportRole) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: report.sourceFormat == .tableau ? "chart.bar.doc.horizontal" : "tablecells")
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppTheme.icon)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(report.displayName)
                    .font(AppFont.callout(weight: .semibold))
                    .lineLimit(1)
                Text("\(report.sourceFormat.label) · \(report.rowCount) 行 · \(report.headers.count) 列")
                    .font(AppFont.caption2())
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(1)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Picker("角色", selection: Binding(
                get: { role },
                set: { store.setSelectedTaskReportRole(reportID: report.id, role: $0) }
            )) {
                ForEach(AnalysisTaskReportRole.allCases.filter { $0 != .excluded }) { item in
                    Text(item.label).tag(item)
                }
            }
            .labelsHidden()
            .frame(width: 104)
            .hoverControlShell(.pickerShell)

            Button {
                store.removeReportFromSelectedTask(reportID: report.id)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.icon)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("从本次分析移除")
        }
        .padding(.vertical, 9)
    }

    private func composerExpandedToolTray(session: AnalysisSession, state: SessionHeaderRenderState) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                composerInlineActions(session: session, state: state)
                Spacer(minLength: 0)
                Text("工具默认收起，避免遮挡输入。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 8) {
                composerInlineActions(session: session, state: state)
                Text("工具默认收起，避免遮挡输入。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.panelStrong.opacity(0.42), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.border.opacity(0.42), lineWidth: 1)
        }
    }

    private func composerSurfaceHeader(
        state: SessionHeaderRenderState,
        hasPreviousAI: Bool,
        effectiveSelectedMode: AnalysisContextMode
    ) -> some View {
        let firstQuestionPhase = isFirstQuestionPhase(state)
        let modeTitle = firstQuestionPhase ? "首次全量读表" : composerModeTitle(effectiveSelectedMode)
        let phaseText = state.hasAIReply ? "对话已开始" : "首次提问默认仅表格"
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(modeTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("\(state.selectedReportCount) 张表")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(phaseText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(composerModeExplanation(
                    selectedMode: selectedComposerMode,
                    effectiveMode: effectiveSelectedMode,
                    hasPreviousAI: hasPreviousAI
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(modeTitle) · \(state.selectedReportCount) 张表 · \(phaseText)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(composerModeExplanation(
                    selectedMode: selectedComposerMode,
                    effectiveMode: effectiveSelectedMode,
                    hasPreviousAI: hasPreviousAI
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func composerQuotedMessage(_ quoted: AnalysisSessionMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrowshape.turn.up.left")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text("正在针对这条 AI 回复追问")
                    .font(.caption.weight(.semibold))
                Text(messagePreview(quoted.content, limit: 180))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                replyingToMessageID = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("取消引用这条回复")
        }
        .padding(8)
        .background(AppTheme.panelStrong.opacity(0.36), in: RoundedRectangle(cornerRadius: 8))
    }

    private var composerTextInput: some View {
        ZStack(alignment: .topLeading) {
            WrappingTextEditor(
                text: $inputText,
                font: .systemFont(ofSize: NSFont.systemFontSize),
                minHeight: 76,
                maxHeight: 220,
                focusToken: store.focusAnalysisComposerToken
            )
            .frame(minHeight: 76, maxHeight: 220)

            if inputText.isEmpty {
                Text("直接写你想分析什么，例如：分析 5/11-5/17 本地生活数据变化和异常原因。")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .allowsHitTesting(false)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    private func composerReportSelectionWarning() -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text("请先确认本次分析表，再发送给 AI。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button {
                if !store.presentCurrentPackReportSelectionConfirmation(force: true) {
                    openReportsPanel()
                }
            } label: {
                Label("确认选表", systemImage: "tablecells")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(AppHoverButtonStyle(variant: .secondary))
            .controlSize(.small)
            .help("打开确认页选择本次要一起分析的表")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.panelStrong.opacity(0.38), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(AppTheme.border.opacity(0.46), lineWidth: 1)
        }
    }

    private func composerInlineActions(session: AnalysisSession, state: SessionHeaderRenderState) -> some View {
        HStack(spacing: 6) {
            if state.hasBlockingAI {
                composerStopToolbarButton()
            } else {
                Button {
                    flushSelectedGoalDraftToStore(savePolicy: .immediate, touchUpdatedAt: true)
                    store.reanalyzeSelectedAnalysisSession(sourcePolicy: selectedSourcePolicy)
                } label: {
                    ComposerToolbarIcon(systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(!state.hasConfiguredAI || state.selectedReportCount == 0)
                .help("重分析：按当前资料范围重新读取当前任务资料")
            }

            Menu {
                ForEach(productOpsQuickPrompts, id: \.title) { item in
                    Button {
                        applyQuickPrompt(item, session: session)
                    } label: {
                        Label(item.title, systemImage: item.systemImage)
                    }
                }
            } label: {
                ComposerToolbarIcon(systemImage: "text.bubble")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .help("常用问题")

            Menu {
                Button {
                    flushSelectedGoalDraftToStore(savePolicy: .immediate, touchUpdatedAt: true)
                    store.regenerateOpportunitiesForSelectedSession()
                } label: {
                    Label("生成机会评分", systemImage: "scope")
                }
                .disabled(!state.hasConfiguredAI || state.hasBlockingAI)

                Button {
                    toggleReadingMode()
                } label: {
                    Label(isFocusMode ? "退出阅读" : "阅读模式", systemImage: isFocusMode ? "rectangle.compress.vertical" : "text.alignleft")
                }
            } label: {
                ComposerToolbarIcon(systemImage: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .help("更多")
        }
    }

    private func composerSendButton(
        hasPreviousAI: Bool,
        hasInput: Bool,
        hasBlockingAI: Bool,
        hasSelectedReports: Bool,
        forceMode: AnalysisContextMode? = nil
    ) -> some View {
        Button {
            sendComposerMessage(forceMode: forceMode)
        } label: {
            Image(systemName: hasBlockingAI ? "hourglass" : "paperplane.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(
                    sendButtonColor(
                        hasInput: hasInput,
                        hasBlockingAI: hasBlockingAI,
                        hasSelectedReports: hasSelectedReports
                    ),
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(sendButtonHelp(hasPreviousAI: hasPreviousAI, hasInput: hasInput, hasBlockingAI: hasBlockingAI, hasSelectedReports: hasSelectedReports))
        .disabled(!store.hasConfiguredAI || hasBlockingAI || !hasInput || !hasSelectedReports)
        .keyboardShortcut(.return, modifiers: [.command])
    }

    private func composerStopToolbarButton() -> some View {
        Button(role: .destructive) {
            store.cancelCurrentAnalysisSessionAI()
        } label: {
            ComposerToolbarIcon(systemImage: "stop.circle", tint: AppTheme.danger)
        }
        .buttonStyle(.plain)
        .help("停止当前会话正在执行的 AI 任务，迟到结果不会写入会话")
    }

    private func sendButtonColor(hasInput: Bool, hasBlockingAI: Bool, hasSelectedReports: Bool) -> Color {
        guard store.hasConfiguredAI, hasInput, !hasBlockingAI, hasSelectedReports else {
            return Color.secondary.opacity(0.35)
        }
        return AppTheme.accent
    }

    private func composerTaskControlBar(
        session: AnalysisSession,
        state: SessionHeaderRenderState,
        hasPreviousAI: Bool,
        hasBlockingAI: Bool,
        effectiveSelectedMode: AnalysisContextMode
    ) -> some View {
        let firstQuestionPhase = isFirstQuestionPhase(state)
        return VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    composerTaskContextChip(state: state)
                    composerStatusChips(state: state)
                    Spacer(minLength: 8)
                    if firstQuestionPhase {
                        if hasBlockingAI {
                            composerStopToolbarButton()
                        }
                    } else {
                        composerModeControls(hasBlockingAI: hasBlockingAI)
                        composerPrimaryActions(session: session, state: state)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        composerTaskContextChip(state: state)
                        Spacer(minLength: 0)
                        if firstQuestionPhase {
                            if hasBlockingAI {
                                composerStopToolbarButton()
                            }
                        } else {
                            composerPrimaryActions(session: session, state: state)
                        }
                    }
                    composerStatusChips(state: state)
                    if !firstQuestionPhase {
                        composerModeControls(hasBlockingAI: hasBlockingAI)
                    }
                }
            }

            Text(composerModeExplanation(
                selectedMode: selectedComposerMode,
                effectiveMode: effectiveSelectedMode,
                hasPreviousAI: hasPreviousAI
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(AppTheme.panel.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border.opacity(0.42), lineWidth: 1)
        }
    }

    private func composerTaskContextChip(state: SessionHeaderRenderState) -> some View {
        HStack(spacing: 7) {
            SemanticIcon(systemName: "square.stack.3d.up", role: .data, size: 13, frameWidth: 17)
            VStack(alignment: .leading, spacing: 1) {
                Text(state.taskName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(state.businessSpaceName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(AppTheme.panelStrong.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
        .help("当前分析任务和业务空间")
    }

    private func composerStatusChips(state: SessionHeaderRenderState) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                compactStatusChip("选表", "\(state.selectedReportCount) 张", isDone: state.selectedReportCount > 0)
                compactStatusChip("对话", state.isAnalysisRunning ? "分析中" : (state.hasAIReply ? "已开始" : "未开始"), isDone: state.hasAIReply, isRunning: state.isAnalysisRunning)
                compactStatusChip("机会评分", state.hasOpportunities ? "已生成" : "待生成", isDone: state.hasOpportunities)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    compactStatusChip("选表", "\(state.selectedReportCount) 张", isDone: state.selectedReportCount > 0)
                    compactStatusChip("对话", state.isAnalysisRunning ? "分析中" : (state.hasAIReply ? "已开始" : "未开始"), isDone: state.hasAIReply, isRunning: state.isAnalysisRunning)
                }
                HStack(spacing: 6) {
                    compactStatusChip("机会评分", state.hasOpportunities ? "已生成" : "待生成", isDone: state.hasOpportunities)
                }
            }
        }
    }

    private func composerModeControls(hasBlockingAI: Bool) -> some View {
        HStack(spacing: 8) {
            composerModeChip(
                mode: .quickFollowUp,
                title: "继续追问",
                systemImage: "paperplane.fill",
                isSelected: selectedComposerMode == .quickFollowUp,
                isDisabled: hasBlockingAI
            )
            composerModeChip(
                mode: .fullReanalysis,
                title: "重新读取数据分析",
                systemImage: "sparkles",
                isSelected: selectedComposerMode == .fullReanalysis,
                isDisabled: hasBlockingAI
            )
        }
    }

    private func composerPrimaryActions(session: AnalysisSession, state: SessionHeaderRenderState) -> some View {
        HStack(spacing: 8) {
            if state.hasBlockingAI {
                Button(role: .destructive) {
                    store.cancelCurrentAnalysisSessionAI()
                } label: {
                    SemanticLabel(title: "停止", systemImage: "stop.circle", role: .risk)
                }
                .buttonStyle(AppHoverButtonStyle(variant: .secondary))
                .help("停止当前会话正在执行的 AI 任务，迟到结果不会写入会话")
            } else {
                Button {
                    flushSelectedGoalDraftToStore(savePolicy: .immediate, touchUpdatedAt: true)
                    store.reanalyzeSelectedAnalysisSession(sourcePolicy: selectedSourcePolicy)
                } label: {
                    SemanticLabel(title: "重分析", systemImage: "arrow.clockwise", role: .ai)
                }
                .buttonStyle(AppHoverButtonStyle(variant: .secondary))
                .disabled(!state.hasConfiguredAI || state.selectedReportCount == 0)
                .help(state.selectedReportCount == 0 ? "请先加入至少 1 张表，再重新分析" : "按当前资料范围重新读取当前任务资料")
            }

            Menu {
                ForEach(productOpsQuickPrompts, id: \.title) { item in
                    Button {
                        applyQuickPrompt(item, session: session)
                    } label: {
                        SemanticLabel(title: item.title, systemImage: item.systemImage, role: .ai)
                    }
                }
            } label: {
                SemanticLabel(title: "常用问题", systemImage: "text.bubble", role: .ai)
            }
            .hoverControlShell(.pickerShell)
            .help("产品/运营常用问题。点击后填入输入框。")

            Menu {
                Button {
                    flushSelectedGoalDraftToStore(savePolicy: .immediate, touchUpdatedAt: true)
                    store.regenerateOpportunitiesForSelectedSession()
                } label: {
                    SemanticLabel(title: "生成机会评分", systemImage: "scope", role: .opportunity)
                }
                .disabled(!state.hasConfiguredAI || state.hasBlockingAI)

                Button {
                    toggleReadingMode()
                } label: {
                    SemanticLabel(title: isFocusMode ? "退出阅读" : "阅读模式", systemImage: isFocusMode ? "rectangle.compress.vertical" : "text.alignleft", role: .data)
                }
            } label: {
                SemanticLabel(title: "更多", systemImage: "ellipsis.circle", role: .neutral)
            }
            .hoverControlShell(.pickerShell)
            .help("更多会话操作")
        }
    }

    private func applyQuickPrompt(
        _ item: (title: String, systemImage: String, prompt: String),
        session: AnalysisSession
    ) {
        inputText = item.prompt
    }

    private func sendComposerMessage(forceMode: AnalysisContextMode? = nil) {
        flushSelectedGoalDraftToStore(savePolicy: .immediate, touchUpdatedAt: true)
        guard let pack = store.selectedPack, !store.reportsForCurrentTask(in: pack).isEmpty else {
            store.statusText = "当前任务没有选择报表。请先加入至少 1 张表，再发送给 AI。"
            if !store.presentCurrentPackReportSelectionConfirmation(force: true) {
                openReportsPanel()
            }
            return
        }
        let sent = inputText
        inputText = ""
        let replyID = replyingToMessageID
        replyingToMessageID = nil
        store.sendAnalysisSessionMessage(
            sent,
            mode: forceMode ?? selectedComposerMode,
            sourcePolicy: selectedSourcePolicy,
            replyToMessageID: replyID
        )
    }

    private func effectiveComposerMode(hasPreviousAI: Bool) -> AnalysisContextMode {
        if selectedComposerMode == .fullReanalysis {
            return .fullReanalysis
        }
        return hasPreviousAI ? .quickFollowUp : .fullReanalysis
    }

    private func composerModeTitle(_ mode: AnalysisContextMode) -> String {
        switch mode {
        case .quickFollowUp, .cachedFollowUp:
            return "继续追问"
        case .fullReanalysis:
            return "重新读取数据分析"
        case .reportGeneration:
            return "生成汇报"
        }
    }

    private func composerModeExplanation(
        selectedMode: AnalysisContextMode,
        effectiveMode: AnalysisContextMode,
        hasPreviousAI: Bool
    ) -> String {
        if !hasPreviousAI {
            return "首次提问会读取当前选表和本地计算证据；知识库和外部参照按资料范围手动开启。"
        }
        switch effectiveMode {
        case .quickFollowUp, .cachedFollowUp:
            return "继续追问：调用 AI，只用最近对话和缓存，不重新采集外部数据。"
        case .fullReanalysis:
            return "重新读取数据分析：按当前资料范围重新读取表格、计算证据、知识库或外部参照。"
        case .reportGeneration:
            return "汇报生成会使用完整上下文生成完整汇报。"
        }
    }

    private func sendButtonHelp(
        hasPreviousAI: Bool,
        hasInput: Bool,
        hasBlockingAI: Bool,
        hasSelectedReports: Bool
    ) -> String {
        if hasBlockingAI {
            return "当前会话正在等待 AI 回复，可停止后再发送。"
        }
        if !hasSelectedReports {
            return "当前任务没有选择报表，无法发送。请先加入至少 1 张表。"
        }
        if !hasInput {
            return "先输入你要分析或追问的问题。"
        }
        return composerModeExplanation(
            selectedMode: selectedComposerMode,
            effectiveMode: effectiveComposerMode(hasPreviousAI: hasPreviousAI),
            hasPreviousAI: hasPreviousAI
        )
    }

    private func composerSourcePolicyMenu(hasBlockingAI: Bool) -> some View {
        Menu {
            ForEach(AnalysisContextSourcePolicy.allCases) { policy in
                Button {
                    selectedSourcePolicy = policy
                } label: {
                    Label(
                        policy.label,
                        systemImage: selectedSourcePolicy == policy ? "checkmark.circle.fill" : "circle"
                    )
                }
                .help(policy.shortDescription)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "tray.full")
                    .font(.system(size: 12, weight: .semibold))
                Text("资料：\(selectedSourcePolicy.label)")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppTheme.panelStrong.opacity(0.46), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(AppTheme.border.opacity(0.46), lineWidth: 1)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .disabled(hasBlockingAI)
        .help(selectedSourcePolicy.shortDescription)
    }

    private func composerModeChip(
        mode: AnalysisContextMode,
        title: String,
        systemImage: String,
        isSelected: Bool,
        isDisabled: Bool
    ) -> some View {
        Button {
            selectedComposerMode = mode
        } label: {
            ComposerModeChipLabel(
                title: title,
                systemImage: systemImage,
                isSelected: isSelected,
                isDisabled: isDisabled
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(mode == .quickFollowUp ? "选择继续追问。输入为空时也可以先选择，不会发送。" : "选择重新读取数据分析。输入为空时也可以先选择，不会发送。")
    }

    private var productOpsQuickPrompts: [(title: String, systemImage: String, prompt: String)] {
        [
            ("看本周异常", "waveform.path.ecg", "请帮我找出当前任务表格中异常变化最大的指标，区分事实、推断、假设和需补数据。"),
            ("找转化断点", "arrow.down.right.and.arrow.up.left", "请分析当前任务里的漏斗或业务链路断点，说明哪些环节掉得最明显，以及需要补哪些数据验证原因。"),
            ("分析活动效果", "megaphone", "请分析本轮活动或运营动作对关键指标的影响，区分活动拉动、自然波动、渠道结构和外部因素。"),
            ("判断渠道质量", "person.3.sequence", "请从获客、注册、申请、KYC、交易或留存链路判断渠道质量变化，并说明是否存在量涨质降。"),
            ("排查风控影响", "shield.lefthalf.filled", "请排查风控、KYC、审批、拒绝码或策略变化是否影响了转化和交易，并列出需要补充的明细表。"),
            ("看外部事件影响", "cloud.sun.bolt", "请结合已启用外部证据判断天气、政策、竞品、市场或社会事件是否可能影响本轮指标，只能按证据等级表达。")
        ]
    }

    private func replyingMessage(in session: AnalysisSession) -> AnalysisSessionMessage? {
        guard let replyingToMessageID else { return nil }
        return session.messages.first { $0.id == replyingToMessageID }
    }

    private func startMessageReply(_ message: AnalysisSessionMessage, prompt: String) {
        replyingToMessageID = message.id
        if !prompt.isEmpty {
            inputText = prompt
        } else if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inputText = "请针对这条回答继续展开："
        }
    }

    private func messagePreview(_ text: String, limit: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "..."
    }

    private func toggleMessageExpansion(_ id: UUID) {
        if expandedMessageIDs.contains(id) {
            expandedMessageIDs.remove(id)
        } else {
            expandedMessageIDs.insert(id)
        }
    }

    private func selectedReports(for session: AnalysisSession, pack: DataPack) -> [ImportedReport] {
        if let task = store.currentAnalysisTask(in: pack) ?? session.taskID.flatMap({ id in pack.analysisTasks.first(where: { $0.id == id }) }) {
            let ids = Set(task.activeReportIDs)
            return pack.importedReports.filter { ids.contains($0.id) && !$0.isIgnoredFromAnalysis }
        }
        let ids = Set(session.selectedReportIDs)
        return pack.importedReports.filter { ids.contains($0.id) && !$0.isIgnoredFromAnalysis }
    }

    private func selectedReportCount(for session: AnalysisSession, pack: DataPack, task: AnalysisTask?) -> Int {
        if let task {
            let ids = Set(task.activeReportIDs)
            return pack.importedReports.lazy.filter { ids.contains($0.id) && !$0.isIgnoredFromAnalysis }.count
        }
        let ids = Set(session.selectedReportIDs)
        return pack.importedReports.lazy.filter { ids.contains($0.id) && !$0.isIgnoredFromAnalysis }.count
    }

    private func nextAction(pack: DataPack, state: SessionHeaderRenderState) -> NextActionBanner.ActionState {
        if pack.importedReports.isEmpty {
            return .init(
                title: "下一步：先导入表格",
                detail: "点击“导入本地表”选择 CSV、TSV、XLSX 或 XLS。导入后会直接确认本次分析表。",
                systemImage: "tray.and.arrow.down"
            )
        }
        if state.selectedReportCount == 0 {
            return .init(
                title: "下一步：确认本次要分析的表",
                detail: "导入完成后会弹出确认页；如果已关闭，也可以在“分析资料”里继续加入或调整表角色。",
                systemImage: "tablecells"
            )
        }
        if !state.hasAnalysis {
            return .init(
                title: "下一步：在底部输入你要 AI 分析的问题",
                detail: "第一句话会自动作为本次任务目标。默认只读取当前选表和本地计算证据；知识库或外部参照可在输入框内手动开启。",
                systemImage: "paperplane.fill"
            )
        }
        return .init(
            title: "下一步：继续追问或核对证据",
            detail: "如果结论还不满意，继续像 ChatGPT 一样追问或修正口径；需要沉淀时可保存纠偏规则、知识库或生成机会评分。",
            systemImage: "doc.richtext"
        )
    }
}
