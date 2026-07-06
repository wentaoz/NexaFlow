import AppKit
import SwiftUI

private enum RootAnalysisInfoPanel: String, CaseIterable, Identifiable {
    case materials = "资料"
    case calibration = "校准"
    case evidence = "证据"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .materials: return "tablecells"
        case .calibration: return "checklist"
        case .evidence: return "function"
        }
    }

    static func mapped(from storedID: String) -> RootAnalysisInfoPanel {
        switch storedID {
        case "资料", "reports":
            return .materials
        case "校准", "audit", "quality", "审核与口径", "数据质检":
            return .calibration
        case "证据", "coverage", "computation", "jobs", "数据覆盖", "计算证据", "AI 任务":
            return .evidence
        default:
            return .materials
        }
    }
}

private struct RelatedAIJobQueuePreview {
    var visibleJobs: [RelatedAIJobRowSnapshot]
    var activeCount: Int
    var issueCount: Int
}

private struct AnalysisInfoReportsPanelSnapshot {
    var currentTask: AnalysisTask?
    var hasReusableTemplate: Bool
    var hasCurrentTaskReports: Bool
    var currentReports: [ImportedReport]
    var unassignedReports: [ImportedReport]
    var unassignedReportCount: Int
    var reportsUsedByOtherTaskIDs: Set<UUID>

    static let empty = AnalysisInfoReportsPanelSnapshot(
        currentTask: nil,
        hasReusableTemplate: false,
        hasCurrentTaskReports: false,
        currentReports: [],
        unassignedReports: [],
        unassignedReportCount: 0,
        reportsUsedByOtherTaskIDs: []
    )
}

private struct AnalysisInfoReportsPanelRevision: Equatable {
    var packID: UUID
    var reportSignature: Int
    var taskSignature: Int
    var templateSignature: Int
    var showAllUnassignedReports: Bool
}

private struct AnalysisInfoReportsPanelChangeKey: Equatable {
    var panelID: String
    var revision: AnalysisInfoReportsPanelRevision?
}

private struct AnalysisInfoActivityPanelSnapshot {
    var sessionID: UUID?
    var packID: UUID?
    var coverageSnapshot: AnalysisCoverageSnapshot?
    var collectionRuns: [ExternalReferenceCollectionRun]
    var notebookRuns: [AnalysisNotebookRun]
    var aiJobPreview: RelatedAIJobQueuePreview
    var traceEvents: [AnalysisTraceTimelineEvent]

    static let empty = AnalysisInfoActivityPanelSnapshot(
        sessionID: nil,
        packID: nil,
        coverageSnapshot: nil,
        collectionRuns: [],
        notebookRuns: [],
        aiJobPreview: RelatedAIJobQueuePreview(visibleJobs: [], activeCount: 0, issueCount: 0),
        traceEvents: []
    )
}

private struct AnalysisInfoActivityPanelRevision: Equatable {
    var panelID: String
    var sessionID: UUID
    var packID: UUID
    var taskID: UUID?
    var coverageSignature: Int
    var messageTraceSignature: Int
    var notebookSignature: Int
    var collectionRunSignature: Int
    var jobSignature: Int
}

private struct AnalysisInfoActivityPanelChangeKey: Equatable {
    var panelID: String
    var revision: AnalysisInfoActivityPanelRevision?
}

private struct AnswerEvidenceSnapshot {
    var messageID: UUID
    var createdAt: Date
    var presentation: AnalysisAnswerPresentation
}

private struct RelatedAIJobRowSnapshot: Identifiable {
    var id: UUID
    var kind: PersistentAIJobKind
    var targetName: String
    var attemptCount: Int
    var maxImmediateAttempts: Int
    var status: AIJobStatus
    var updatedAt: Date
    var lastError: String
    var latestLogs: [AIReasoningLogEntry]

    init(job: PersistentAIJob) {
        id = job.id
        kind = job.kind
        targetName = job.targetName
        attemptCount = job.attemptCount
        maxImmediateAttempts = job.maxImmediateAttempts
        status = job.status
        updatedAt = job.updatedAt
        lastError = job.lastError
        latestLogs = Array(job.logs.suffix(5))
    }
}

private struct AnalysisInfoStatItem: Identifiable {
    let id = UUID()
    var title: String
    var value: String
    var systemImage: String
    var tint: Color = .secondary
}

struct AnalysisInfoSidebarRootView: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    @State private var selectedAuditReportID: UUID?
    @State private var selectedDictionaryFieldID: UUID?
    @State private var reportDescriptionDraft = ""
    @State private var reportUnderstandingAnswerText = ""
    @State private var reportQAQuestionText = ""
    @State private var dictionaryAnswerText = ""
    @State private var fieldSearchText = ""
    @State private var taskNameDraft = ""
    @State private var taskGoalDraft = ""
    @State private var isUnassignedReportsExpanded = true
    @State private var showAllUnassignedReports = false
    @State private var auditDetailsExpanded = false
    @State private var qualityDetailsExpanded = false
    @State private var manifestExpanded = false
    @State private var traceTimelineExpanded = true
    @State private var coverageExpanded = true
    @State private var harnessExpanded = false
    @State private var notebookExpanded = false
    @State private var collectionLogExpanded = false
    @State private var aiJobsExpanded = false
    @State private var dataSourceSettingsExpanded = false
    @State private var reportsSnapshot = AnalysisInfoReportsPanelSnapshot.empty
    @State private var reportsRevision: AnalysisInfoReportsPanelRevision?
    @State private var reportsRefreshTask: Task<Void, Never>?
    @State private var activitySnapshot = AnalysisInfoActivityPanelSnapshot.empty
    @State private var activityRevision: AnalysisInfoActivityPanelRevision?
    @State private var activityRefreshTask: Task<Void, Never>?
    private let topChromePadding: CGFloat = 26

    private var selectedPanel: Binding<RootAnalysisInfoPanel> {
        Binding(
            get: { RootAnalysisInfoPanel.mapped(from: store.analysisInfoSidebarPanelID) },
            set: { store.analysisInfoSidebarPanelID = $0.rawValue }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            panelPicker
            Divider()
            content
        }
        .padding(.top, topChromePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.surface)
        .onAppear {
            refreshReportsSnapshot(force: true)
            refreshActivitySnapshot(force: true)
        }
        .onChange(of: reportsChangeKey) { _ in
            scheduleReportsSnapshotRefresh()
        }
        .onChange(of: activityChangeKey) { _ in
            scheduleActivitySnapshotRefresh()
        }
        .onChange(of: store.analysisInfoSidebarPanelID) { _ in
            refreshReportsSnapshot(force: true)
            refreshActivitySnapshot(force: true)
        }
        .onChange(of: showAllUnassignedReports) { _ in
            refreshReportsSnapshot(force: true)
        }
        .onDisappear {
            reportsRefreshTask?.cancel()
            reportsRefreshTask = nil
            activityRefreshTask?.cancel()
            activityRefreshTask = nil
        }
    }

    private var reportsChangeKey: AnalysisInfoReportsPanelChangeKey {
        guard selectedPanel.wrappedValue == .materials,
              let pack = store.selectedPack else {
            return AnalysisInfoReportsPanelChangeKey(panelID: selectedPanel.wrappedValue.rawValue, revision: nil)
        }
        return AnalysisInfoReportsPanelChangeKey(
            panelID: selectedPanel.wrappedValue.rawValue,
            revision: makeReportsRevision(pack: pack)
        )
    }

    private var activityChangeKey: AnalysisInfoActivityPanelChangeKey {
        guard isActivityPanelSelected(),
              let pack = store.selectedPack,
              let session = store.selectedAnalysisSession,
              session.packID == pack.id else {
            return AnalysisInfoActivityPanelChangeKey(panelID: selectedPanel.wrappedValue.rawValue, revision: nil)
        }
        let currentTask = store.currentAnalysisTask(in: pack)
        return AnalysisInfoActivityPanelChangeKey(
            panelID: selectedPanel.wrappedValue.rawValue,
            revision: makeActivityRevision(
                session: session,
                pack: pack,
                taskID: currentTask?.id
            )
        )
    }

    private var panelPicker: some View {
        HStack(spacing: 0) {
            ForEach(Array(RootAnalysisInfoPanel.allCases.enumerated()), id: \.element.id) { index, panel in
                Button {
                    selectedPanel.wrappedValue = panel
                } label: {
                    Text(panel.rawValue)
                        .font(AppFont.callout(weight: .semibold))
                        .fontWeight(.semibold)
                        .foregroundStyle(selectedPanel.wrappedValue == panel ? AppTheme.accentStrong : AppTheme.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .contentShape(Rectangle())
                        .background {
                            if selectedPanel.wrappedValue == panel {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(AppTheme.accent.opacity(0.10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7)
                                            .stroke(AppTheme.accent.opacity(0.36), lineWidth: 1)
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)

                if index < RootAnalysisInfoPanel.allCases.count - 1 {
                    Rectangle()
                        .fill(AppTheme.divider)
                        .frame(width: 1, height: 18)
                }
            }
        }
        .padding(3)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(AppTheme.border.opacity(0.54), lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .background(AppTheme.surface)
    }

    @ViewBuilder
    private var content: some View {
        if let pack = store.selectedPack,
           let session = store.selectedAnalysisSession,
           session.packID == pack.id {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch selectedPanel.wrappedValue {
                    case .materials:
                        materialsPanel(session: session, pack: pack, snapshot: reportsSnapshot)
                    case .calibration:
                        calibrationPanel(session: session, pack: pack)
                    case .evidence:
                        evidencePanel(session: session, pack: pack, snapshot: currentActivitySnapshot(session: session, pack: pack))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        } else {
            EmptyStateView(
                title: "暂无分析资料",
                detail: "创建或选择一个分析会话后，可以查看本次分析表、口径、质检、数据覆盖和 AI 任务。",
                systemImage: "sidebar.right"
            )
            .padding(18)
        }
    }

    private var sidebarHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("分析资料")
                    .font(AppFont.title(size: 20))
                Text(materialSummaryText)
                    .font(AppFont.caption())
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                store.isAnalysisInfoSidebarVisible = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(AppHoverButtonStyle(variant: .ghost))
            .accessibilityLabel("关闭分析资料")
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(AppTheme.surface)
    }

    private var materialSummaryText: String {
        guard let pack = store.selectedPack else { return "尚未导入分析表" }
        let selectedCount = store.reportsForCurrentTask(in: pack).count
        return "本次分析表 \(selectedCount) 张 · 已导入本地表 \(pack.localReportCount) 张 · 已导入 Tableau \(pack.tableauReportCount) 张"
    }

    @ViewBuilder
    private func materialsPanel(session: AnalysisSession, pack: DataPack, snapshot: AnalysisInfoReportsPanelSnapshot) -> some View {
        materialsSummaryStrip(pack: pack, snapshot: snapshot)

        if pack.importedReports.isEmpty {
            HStack(spacing: 8) {
                dataAccessButton(title: "导入本地表", systemImage: "square.and.arrow.down") {
                    store.importReportsIntoSelectedPack()
                }
                dataAccessButton(title: "接入 Tableau", systemImage: "sparkles") {
                    store.showTableauImportSheet()
                }
                .disabled(store.isImportingData)
            }
            mutedText("还没有可分析表。导入后会直接弹出确认页，不需要再到侧栏里手动找。")
        }

        Divider()
            .padding(.vertical, 4)

        materialsReportSection(snapshot: snapshot)

        DisclosureGroup(isExpanded: $dataSourceSettingsExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                materialsTaskMenu(pack: pack, snapshot: snapshot)
                HStack(spacing: 8) {
                    dataAccessButton(title: "导入本地表", systemImage: "square.and.arrow.down") {
                        store.importReportsIntoSelectedPack()
                    }
                    dataAccessButton(title: "接入 Tableau", systemImage: "sparkles") {
                        store.showTableauImportSheet()
                    }
                    .disabled(store.isImportingData)
                }
                mutedText("低频的数据导入、任务切换和模板操作放在这里；日常分析只需要在上方确认本次分析表。")
            }
            .padding(.top, 8)
        } label: {
            disclosureLabel("导入与任务设置", count: nil)
        }
    }

    @ViewBuilder
    private func calibrationPanel(session: AnalysisSession, pack: DataPack) -> some View {
        let reports = currentTaskReports(in: pack)
        let stats = auditStats(for: reports)
        infoSection(title: "校准摘要", detail: "\(reports.count) 张当前任务表") {
            compactStatGrid([
                AnalysisInfoStatItem(title: "待确认", value: "\(stats.unresolved)", systemImage: "circle", tint: stats.unresolved > 0 ? AppTheme.warning : .secondary),
                AnalysisInfoStatItem(title: "阻塞", value: "\(stats.blocked)", systemImage: "xmark.circle", tint: stats.blocked > 0 ? AppTheme.danger : .secondary),
                AnalysisInfoStatItem(title: "已确认", value: "\(stats.confirmed)", systemImage: "checkmark.circle", tint: AppTheme.success),
                AnalysisInfoStatItem(title: "质检", value: pack.qualityReport.verdict.rawValue, systemImage: pack.qualityReport.verdict.systemImage, tint: qualityTint(pack.qualityReport.verdict))
            ])
            Button {
                store.recomputeSelectedPack()
            } label: {
                Label("重新质检", systemImage: "arrow.clockwise")
            }
            .buttonStyle(AppHoverButtonStyle(variant: .secondary))
        }

        infoSection(title: "审核与口径", detail: stats.unresolved > 0 ? "\(stats.unresolved) 项需要处理" : "当前没有阻塞项") {
            compactAuditReportList(reports)
            DisclosureGroup(isExpanded: $auditDetailsExpanded) {
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
                .padding(.top, 8)
            } label: {
                disclosureLabel("查看完整审核工具", count: nil)
            }
        }

        infoSection(title: "数据质检", detail: "\(pack.qualityReport.issues.count) 个问题") {
            qualityIssuePreview(pack)
            DisclosureGroup(isExpanded: $qualityDetailsExpanded) {
                qualityIssueList(pack)
                    .padding(.top, 6)
            } label: {
                disclosureLabel("展开质检问题", count: pack.qualityReport.issues.count)
            }
            DisclosureGroup(isExpanded: $manifestExpanded) {
                manifestRows(pack)
                    .padding(.top, 6)
            } label: {
                disclosureLabel("Manifest", count: pack.manifest.sources.count)
            }
        }
    }

    @ViewBuilder
    private func evidencePanel(session: AnalysisSession, pack: DataPack, snapshot activitySnapshot: AnalysisInfoActivityPanelSnapshot) -> some View {
        let coverage = activitySnapshot.coverageSnapshot
        let harnessItems = harnessAuditEvidence(session: session)
        if let answerEvidence = selectedAnswerEvidence(session: session) {
            answerEvidenceSection(answerEvidence)
        }

        infoSection(title: "证据摘要", detail: coverage?.createdAt.formatted(date: .numeric, time: .shortened) ?? "等待深度分析生成") {
            if let coverage {
                compactStatGrid([
                    AnalysisInfoStatItem(title: "读取表", value: "\(coverage.totalReports)", systemImage: "tablecells"),
                    AnalysisInfoStatItem(title: "指标", value: "\(coverage.totalMetrics)", systemImage: "number"),
                    AnalysisInfoStatItem(title: "周期", value: "\(coverage.totalTimeColumns)", systemImage: "calendar"),
                    AnalysisInfoStatItem(title: "外部证据", value: "\(coverage.referenceItemCount)", systemImage: "link")
                ])
                mutedText(coverage.contextStrategyDescription?.nilIfBlank ?? coverage.summary)
            } else {
                mutedText("发送深度分析或生成完整汇报后，这里会记录 AI 实际读取范围、SQL/Notebook 和外部采集日志。")
            }
        }

        traceTimelineSection(activitySnapshot.traceEvents)

        infoSection(title: "表格理解与计算证据", detail: harnessItems.isEmpty ? "等待本地校验链路运行" : "\(harnessItems.count) 次运行") {
            if let focusedHarness = focusedHarnessEvidence(from: harnessItems) {
                selectedSourceTraceSection(pack: pack, run: focusedHarness.analysisHarnessRun)
                harnessEvidenceOverview(focusedHarness)
            } else {
                mutedText("还没有 Harness 审计。默认在“仅表格 + 深度分析”路径运行：AI 先生成计划，本地执行指标，再由 AI 解释并由本地校验报告。")
            }
            DisclosureGroup(isExpanded: $harnessExpanded) {
                harnessAuditList(harnessItems)
                    .padding(.top, 6)
            } label: {
                disclosureLabel("高级审计", count: harnessItems.count)
            }
        }

        infoSection(title: "AI 读取范围", detail: coverage.map { "\($0.totalRows) 行 · \($0.totalColumns) 列" } ?? "未生成") {
            DisclosureGroup(isExpanded: $coverageExpanded) {
                coverageDetails(coverage)
                    .padding(.top, 6)
            } label: {
                disclosureLabel("查看读取范围与限制", count: coverage?.reportSnapshots.count)
            }
        }

        infoSection(title: "SQL / Notebook", detail: "\(activitySnapshot.notebookRuns.count) 次运行") {
            DisclosureGroup(isExpanded: $notebookExpanded) {
                notebookRunList(activitySnapshot.notebookRuns)
                    .padding(.top, 6)
            } label: {
                disclosureLabel("查看计算证据", count: activitySnapshot.notebookRuns.count)
            }
        }

        infoSection(title: "采集日志", detail: "\(activitySnapshot.collectionRuns.count) 条") {
            DisclosureGroup(isExpanded: $collectionLogExpanded) {
                collectionRunList(activitySnapshot.collectionRuns)
                    .padding(.top, 6)
            } label: {
                disclosureLabel("查看外部采集", count: activitySnapshot.collectionRuns.count)
            }
        }

        infoSection(title: "AI 任务", detail: aiJobSummary(activitySnapshot.aiJobPreview)) {
            DisclosureGroup(isExpanded: $aiJobsExpanded) {
                aiJobList(activitySnapshot.aiJobPreview)
                    .padding(.top, 6)
            } label: {
                disclosureLabel("查看任务队列", count: activitySnapshot.aiJobPreview.visibleJobs.count)
            }
        }
    }

    @ViewBuilder
    private func traceTimelineSection(_ events: [AnalysisTraceTimelineEvent]) -> some View {
        infoSection(title: "执行时间线", detail: events.isEmpty ? "等待事件" : "\(events.count) 个事件") {
            if events.isEmpty {
                mutedText("还没有可视化 trace。开始一次深度分析后，这里会按时间合并提问、读取范围、Harness、Notebook、采集和 AI 任务日志。")
            } else {
                let primaryEvents = Array(events.prefix(12))
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(primaryEvents) { event in
                        traceTimelineRow(event, isLast: event.id == primaryEvents.last?.id && (!traceTimelineExpanded || events.count <= primaryEvents.count))
                    }
                    if events.count > primaryEvents.count {
                        DisclosureGroup(isExpanded: $traceTimelineExpanded) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(events.dropFirst(primaryEvents.count))) { event in
                                    traceTimelineRow(event, isLast: event.id == events.last?.id)
                                }
                            }
                            .padding(.top, 6)
                        } label: {
                            disclosureLabel("查看完整 trace timeline", count: events.count)
                        }
                        .padding(.top, 8)
                    }
                }
            }
        }
    }

    private func traceTimelineRow(_ event: AnalysisTraceTimelineEvent, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle()
                    .fill(traceStatusColor(event.status))
                    .frame(width: 9, height: 9)
                    .overlay {
                        Circle()
                            .stroke(traceStatusColor(event.status).opacity(0.25), lineWidth: 4)
                    }
                    .padding(.top, 6)
                if !isLast {
                    Rectangle()
                        .fill(AppTheme.border.opacity(0.55))
                        .frame(width: 1)
                        .frame(minHeight: 48)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(event.source.label, systemImage: traceSourceIcon(event.source))
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(traceStatusColor(event.status))
                        .lineLimit(1)
                    Text(event.title)
                        .font(AppFont.callout(weight: .semibold))
                        .foregroundStyle(AppTheme.text)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(event.occurredAt.formatted(date: .omitted, time: .shortened))
                        .font(AppFont.caption())
                        .foregroundStyle(AppTheme.mutedText)
                }
                HStack(spacing: 6) {
                    Text(event.status.label)
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(traceStatusColor(event.status))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(traceStatusColor(event.status).opacity(0.13), in: Capsule())
                    if let duration = event.durationMilliseconds {
                        Text(traceDurationText(duration))
                            .font(AppFont.caption())
                            .foregroundStyle(AppTheme.mutedText)
                    }
                }
                Text(event.detail)
                    .font(AppFont.caption())
                    .foregroundStyle(AppTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
                let metadata = Array(event.metadata.filter { !$0.value.isEmpty }.sorted { $0.key < $1.key }.prefix(4))
                if !metadata.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            ForEach(metadata, id: \.key) { item in
                                traceMetadataChip(key: item.key, value: item.value)
                            }
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(metadata, id: \.key) { item in
                                traceMetadataChip(key: item.key, value: item.value)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func traceMetadataChip(key: String, value: String) -> some View {
        Text("\(key) \(value)")
            .font(AppFont.caption())
            .foregroundStyle(AppTheme.mutedText)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(AppTheme.panelStrong.opacity(0.45), in: Capsule())
    }

    private func traceStatusColor(_ status: AnalysisTraceTimelineStatus) -> Color {
        switch status {
        case .waiting: return AppTheme.mutedText
        case .running: return AppTheme.accent
        case .completed: return AppTheme.success
        case .warning: return AppTheme.warning
        case .failed: return AppTheme.danger
        case .info: return AppTheme.icon
        }
    }

    private func traceSourceIcon(_ source: AnalysisTraceTimelineSource) -> String {
        switch source {
        case .conversation: return "text.bubble"
        case .coverage: return "eye"
        case .harness: return "checkmark.seal"
        case .notebook: return "function"
        case .collection: return "arrow.down.doc"
        case .aiJob: return "sparkles"
        case .answerTrace: return "number"
        }
    }

    private func traceDurationText(_ durationMilliseconds: Int) -> String {
        if durationMilliseconds < 1_000 {
            return "\(durationMilliseconds) ms"
        }
        let seconds = Double(durationMilliseconds) / 1_000
        return String(format: "%.1f s", seconds)
    }

    private func selectedAnswerEvidence(session: AnalysisSession) -> AnswerEvidenceSnapshot? {
        let candidates = session.messages.compactMap { message -> AnswerEvidenceSnapshot? in
            guard message.role == .assistant,
                  message.kind == .aiAnalysis || message.kind == .aiMemo || message.kind == .simpleReport,
                  let presentation = AnalysisAnswerPresentation.parse(message.content),
                  presentation.hasSupportingSections else {
                return nil
            }
            return AnswerEvidenceSnapshot(
                messageID: message.id,
                createdAt: message.createdAt,
                presentation: presentation
            )
        }
        if let selectedID = store.selectedAnalysisEvidenceMessageID,
           let selected = candidates.first(where: { $0.messageID == selectedID }) {
            return selected
        }
        return candidates.last
    }

    @ViewBuilder
    private func answerEvidenceSection(_ snapshot: AnswerEvidenceSnapshot) -> some View {
        infoSection(title: "当前回答依据", detail: DateFormatting.shortDateTime.string(from: snapshot.createdAt)) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    ForEach(snapshot.presentation.supportingSections.map(\.summaryLabel).uniqued(), id: \.self) { label in
                        compactPill(label, tint: AppTheme.icon)
                    }
                    Spacer(minLength: 0)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 6) {
                    ForEach(snapshot.presentation.supportingSections.map(\.summaryLabel).uniqued(), id: \.self) { label in
                        compactPill(label, tint: AppTheme.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            mutedText("主回答留在对话区；这里保留口径、事实、读取范围、限制说明和完整原文。")

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(snapshot.presentation.supportingSections.enumerated()), id: \.offset) { _, section in
                    DisclosureGroup {
                        MarkdownMessageRenderer(section.markdownWithHeading)
                            .textSelection(.enabled)
                            .padding(.top, 6)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: section.systemImage)
                                .font(.caption)
                                .foregroundStyle(AppTheme.icon)
                                .frame(width: 16)
                            Text(section.title)
                                .font(AppFont.callout(weight: .medium))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(section.summaryLabel)
                                .font(AppFont.caption2(weight: .medium))
                                .foregroundStyle(AppTheme.mutedText)
                        }
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Divider() }
                }

                DisclosureGroup {
                    Text(snapshot.presentation.rawMarkdown)
                        .font(AppFont.caption().monospaced())
                        .foregroundStyle(AppTheme.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                        .padding(.top, 6)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.plaintext")
                            .font(.caption)
                            .foregroundStyle(AppTheme.icon)
                            .frame(width: 16)
                        Text("高级审计 / 完整原文")
                            .font(AppFont.callout(weight: .medium))
                        Spacer(minLength: 0)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func materialsSummaryStrip(pack: DataPack, snapshot: AnalysisInfoReportsPanelSnapshot) -> some View {
        HStack(spacing: 7) {
            Text("当前任务")
                .fontWeight(.semibold)
            Text("·")
                .foregroundStyle(.tertiary)
            Text("\(snapshot.currentReports.count) 张表")
            if pack.tableauReportCount > 0 {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("Tableau \(pack.tableauReportCount) 张")
            }
        }
        .font(AppFont.caption())
        .foregroundStyle(AppTheme.mutedText)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.border.opacity(0.45), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func materialsTaskMenu(pack: DataPack, snapshot: AnalysisInfoReportsPanelSnapshot) -> some View {
        if pack.analysisTasks.isEmpty {
            mutedText("当前还没有分析任务。请新建任务。")
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        } else {
            Menu {
                ForEach(pack.analysisTasks) { task in
                    Button(task.name) {
                        store.selectAnalysisTask(taskID: task.id)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(snapshot.currentTask?.name ?? pack.analysisTasks.first?.name ?? "选择分析任务")
                        .font(AppFont.callout(weight: .medium))
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.icon)
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .frame(maxWidth: .infinity)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                        .stroke(AppTheme.border.opacity(0.66), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func dataAccessButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.callout)
                    .frame(width: 16)
                Text(title)
                    .font(AppFont.caption(weight: .semibold))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(AppTheme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.border.opacity(0.62), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func materialsReportSection(snapshot: AnalysisInfoReportsPanelSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("本次分析表")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(snapshot.currentReports.count) 张")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)

            if snapshot.currentReports.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    mutedText(snapshot.unassignedReportCount > 0 ? "还没选表。请选择本轮要一起分析的表。" : "还没选表，且当前没有可加入的表。请先导入本地表或 Tableau。")
                    if snapshot.unassignedReportCount > 0 {
                        Button {
                            _ = store.presentCurrentPackReportSelectionConfirmation(force: true)
                        } label: {
                            Label("选择分析表", systemImage: "tablecells")
                        }
                        .buttonStyle(AppHoverButtonStyle(variant: .primary))
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 10)
            } else {
                ForEach(Array(snapshot.currentReports.enumerated()), id: \.element.id) { index, report in
                    materialsReportRow(
                        report,
                        role: displayRole(for: report, snapshot: snapshot, index: index),
                        isInTask: true,
                        isUsedByOtherTask: false
                    )
                }
            }

            Divider()
                .padding(.vertical, 8)

            DisclosureGroup(isExpanded: $isUnassignedReportsExpanded) {
                if snapshot.unassignedReportCount == 0 {
                    mutedText("没有未加入本次分析的报表。")
                        .padding(.top, 8)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(snapshot.unassignedReports) { report in
                            materialsReportRow(
                                report,
                                role: nil,
                                isInTask: false,
                                isUsedByOtherTask: snapshot.reportsUsedByOtherTaskIDs.contains(report.id)
                            )
                        }
                        if snapshot.unassignedReports.count < snapshot.unassignedReportCount {
                            Button("显示全部 \(snapshot.unassignedReportCount) 张") {
                                showAllUnassignedReports = true
                            }
                            .buttonStyle(AppHoverButtonStyle(variant: .link))
                            .padding(.top, 8)
                        }
                    }
                }
            } label: {
                HStack {
                    Text("可加入的表 \(snapshot.unassignedReportCount) 张")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                }
                .foregroundStyle(.primary)
            }
        }
    }

    private func materialsReportRow(
        _ report: ImportedReport,
        role: AnalysisTaskReportRole?,
        isInTask: Bool,
        isUsedByOtherTask: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "tablecells")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(report.displayName)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(2)
                    Text(materialsReportMeta(report, isUsedByOtherTask: isUsedByOtherTask))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Spacer(minLength: 34)
                if isInTask {
                    Menu {
                        ForEach(AnalysisTaskReportRole.allCases.filter { $0 != .excluded }) { role in
                            Button(role.label) {
                                store.setSelectedTaskReportRole(reportID: report.id, role: role)
                            }
                        }
                    } label: {
                        Text(materialsRoleLabel(role ?? .evidence))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(materialsRoleTint(role ?? .evidence))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(materialsRoleTint(role ?? .evidence).opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button("移出") {
                        store.removeReportFromSelectedTask(reportID: report.id)
                    }
                    .font(.caption)
                    .buttonStyle(AppHoverButtonStyle(variant: .secondary))
                } else {
                    Button("加入") {
                        let defaultRole: AnalysisTaskReportRole
                        if let pack = store.selectedPack, store.reportsForCurrentTask(in: pack).isEmpty {
                            defaultRole = .primaryBusiness
                        } else {
                            defaultRole = .evidence
                        }
                        store.addReportToSelectedTask(reportID: report.id, role: defaultRole)
                    }
                    .font(.caption)
                    .buttonStyle(AppHoverButtonStyle(variant: .secondary))
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private func infoSection<Content: View>(
        title: String,
        detail: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer(minLength: 8)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            content()
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            Divider().offset(y: 8)
        }
        .padding(.bottom, 8)
    }

    private func taskSelector(pack: DataPack, snapshot: AnalysisInfoReportsPanelSnapshot) -> some View {
        Group {
            if pack.analysisTasks.isEmpty {
                mutedText("当前还没有分析任务。请新建任务。")
            } else {
                Picker("分析任务", selection: Binding(
                    get: { snapshot.currentTask?.id ?? pack.analysisTasks.first?.id ?? UUID() },
                    set: { store.selectAnalysisTask(taskID: $0) }
                )) {
                    ForEach(pack.analysisTasks) { task in
                        Text(task.name).tag(task.id)
                    }
                }
                .labelsHidden()
                .hoverControlShell(.pickerShell)
            }
        }
    }

    private func compactTaskActions(session: AnalysisSession, snapshot: AnalysisInfoReportsPanelSnapshot) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                taskActionButtons(snapshot: snapshot)
            }
            VStack(alignment: .leading, spacing: 8) {
                taskActionButtons(snapshot: snapshot)
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private func taskActionButtons(snapshot: AnalysisInfoReportsPanelSnapshot) -> some View {
        Button {
            store.createAnalysisTask()
            store.analysisInfoSidebarPanelID = RootAnalysisInfoPanel.materials.rawValue
        } label: {
            Label("新建任务", systemImage: "plus")
        }
        .buttonStyle(AppHoverButtonStyle(variant: .secondary))

        Button {
            store.showImportPanel()
        } label: {
            Label("导入本地表", systemImage: "tray.and.arrow.down")
        }
        .buttonStyle(AppHoverButtonStyle(variant: .secondary))
        .disabled(store.isImportingData)

        Button {
            store.showTableauImportSheet()
        } label: {
            Label("接入 Tableau", systemImage: "chart.bar.doc.horizontal")
        }
        .buttonStyle(AppHoverButtonStyle(variant: .secondary))
        .disabled(store.isImportingData)

        Menu {
            Button("按最佳模板选表") {
                store.applyBestAnalysisTemplateToSelectedTask()
            }
            .disabled(!snapshot.hasReusableTemplate)
            Button("把当前任务保存为模板") {
                store.saveSelectedAnalysisTaskAsTemplate()
            }
            .disabled(!snapshot.hasCurrentTaskReports)
        } label: {
            Label("模板", systemImage: "doc.text.magnifyingglass")
        }
        .buttonStyle(AppHoverButtonStyle(variant: .secondary))
    }

    private func goalEditingDisclosure(session: AnalysisSession) -> some View {
        DisclosureGroup("任务目标") {
            mutedText(session.goal.nilIfBlank ?? "首条用户问题会自动成为任务目标。")
                .padding(.top, 4)
        }
        .font(.caption)
    }

    private func compactReportList(reports: [ImportedReport], snapshot: AnalysisInfoReportsPanelSnapshot, isInTask: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(reports) { report in
                compactReportRow(
                    report,
                    role: snapshot.currentTask?.reportRoles[report.id],
                    isInTask: isInTask,
                    isUsedByOtherTask: snapshot.reportsUsedByOtherTaskIDs.contains(report.id)
                )
            }
        }
    }

    private func compactReportRow(
        _ report: ImportedReport,
        role: AnalysisTaskReportRole?,
        isInTask: Bool,
        isUsedByOtherTask: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(report.displayName)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(2)
                if isUsedByOtherTask && !isInTask {
                    compactPill("其它任务", tint: .secondary)
                }
                Spacer(minLength: 8)
            }

            Text(reportMeta(report))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                if isInTask {
                    Picker("报表角色", selection: Binding(
                        get: { role ?? .evidence },
                        set: { store.setSelectedTaskReportRole(reportID: report.id, role: $0) }
                    )) {
                        ForEach(AnalysisTaskReportRole.allCases.filter { $0 != .excluded }) { role in
                            Text(role.label).tag(role)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 116)
                    .hoverControlShell(.pickerShell)

                    Button {
                        store.removeReportFromSelectedTask(reportID: report.id)
                    } label: {
                        Label("移出", systemImage: "minus.circle")
                    }
                    .buttonStyle(AppHoverButtonStyle(variant: .secondary))
                } else {
                    Button {
                        let defaultRole: AnalysisTaskReportRole
                        if let pack = store.selectedPack, store.reportsForCurrentTask(in: pack).isEmpty {
                            defaultRole = .primaryBusiness
                        } else {
                            defaultRole = .evidence
                        }
                        store.addReportToSelectedTask(reportID: report.id, role: defaultRole)
                    } label: {
                        Label("加入", systemImage: "plus.circle")
                    }
                    .buttonStyle(AppHoverButtonStyle(variant: .primary))
                }
                Spacer(minLength: 0)
            }
            .font(.caption)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func compactAuditReportList(_ reports: [ImportedReport]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if reports.isEmpty {
                mutedText("当前任务还没有选表。")
            } else {
                ForEach(reports.prefix(8)) { report in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle()
                            .fill(auditTint(for: report))
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(report.displayName)
                                .font(.callout)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text("\(report.sourceFormat.label) · 问题 \(report.unresolvedAuditSteps.count) · 字段 \(report.headers.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Divider() }
                }
                if reports.count > 8 {
                    mutedText("还有 \(reports.count - 8) 张表可在完整审核工具中查看。")
                        .padding(.top, 6)
                }
            }
        }
    }

    @ViewBuilder
    private func qualityIssuePreview(_ pack: DataPack) -> some View {
        if pack.qualityReport.issues.isEmpty {
            mutedText("没有发现阻塞性质量问题。")
        } else {
            let issue = pack.qualityReport.issues[0]
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: issue.severity.systemImage)
                    .foregroundStyle(issueTint(issue.severity))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(issue.title)
                        .font(.callout)
                        .fontWeight(.medium)
                    Text(issue.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
    }

    @ViewBuilder
    private func qualityIssueList(_ pack: DataPack) -> some View {
        if pack.qualityReport.issues.isEmpty {
            mutedText("没有质检问题。")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(pack.qualityReport.issues) { issue in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: issue.severity.systemImage)
                                .foregroundStyle(issueTint(issue.severity))
                                .frame(width: 18)
                            Text(issue.title)
                                .font(.callout)
                                .fontWeight(.medium)
                        }
                        Text(issue.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("建议：\(issue.recommendedAction)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Divider() }
                }
            }
        }
    }

    private func manifestRows(_ pack: DataPack) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            compactKeyValue("周期", pack.manifest.period.nilIfBlank ?? "未记录")
            compactKeyValue("导出人", pack.manifest.exportedBy.nilIfBlank ?? "未记录")
            compactKeyValue("导出时间", pack.manifest.exportedAt.map { DateFormatting.shortDate.string(from: $0) } ?? "未记录")
            if !pack.manifest.sources.isEmpty {
                Divider()
                ForEach(pack.manifest.sources) { source in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(source.name)
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("\(source.platform) · \(source.dateRange) · \(source.exportMethod)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    @ViewBuilder
    private func coverageDetails(_ snapshot: AnalysisCoverageSnapshot?) -> some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(snapshot.reportSnapshots.prefix(8).enumerated()), id: \.element.id) { index, report in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("#\(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .leading)
                            Text(report.reportName)
                                .font(.callout)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(report.sourceFormat.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(report.rowCount) 行 · \(report.columnCount) 列 · \(report.metricCount) 指标 · \(report.timeColumnCount) 周期 · \(coverageModeLabel(report.dataMode))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .padding(.leading, 32)
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Divider() }
                }
                if !snapshot.limitations.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("限制说明")
                            .font(.caption)
                            .fontWeight(.semibold)
                        ForEach(snapshot.limitations.prefix(8), id: \.self) { limitation in
                            Text("· \(limitation)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        } else {
            mutedText("还没有覆盖快照。")
        }
    }

    private func harnessAuditEvidence(session: AnalysisSession) -> [AnalysisSessionEvidence] {
        Array(
            session.messages
                .flatMap(\.evidence)
                .filter { evidence in
                    evidence.sourceType.localizedCaseInsensitiveContains("Analysis Harness") ||
                        evidence.title.localizedCaseInsensitiveContains("Analysis Harness")
                }
                .suffix(8)
                .reversed()
        )
    }

    private func focusedHarnessEvidence(from items: [AnalysisSessionEvidence]) -> AnalysisSessionEvidence? {
        if let resultID = store.selectedMetricResultID,
           let matched = items.first(where: { evidence in
               evidence.analysisHarnessRun?.verifiedResults.contains(where: { $0.id == resultID }) == true
           }) {
            return matched
        }
        return items.first
    }

    @ViewBuilder
    private func harnessEvidenceOverview(_ evidence: AnalysisSessionEvidence) -> some View {
        let understanding = harnessSectionLines(in: evidence.detail, titles: ["表格理解"])
        let facts = harnessSectionLines(in: evidence.detail, titles: ["标准事实表预览", "Table Understanding / Normalized Facts"])
        let results = harnessSectionLines(in: evidence.detail, titles: ["关键指标结果", "Verified Results"])
        VStack(alignment: .leading, spacing: 8) {
            compactKeyValue("Run", evidence.sourceID.map { String($0.prefix(8)) } ?? "latest")
            harnessEvidenceBlock(
                title: "表格理解",
                systemImage: "tablecells.badge.ellipsis",
                lines: understanding,
                emptyText: "本轮还没有输出表格理解。"
            )
            harnessEvidenceBlock(
                title: "标准事实表",
                systemImage: "list.bullet.rectangle",
                lines: facts,
                emptyText: "本轮还没有标准事实表预览。"
            )
            harnessEvidenceBlock(
                title: "关键结果",
                systemImage: "number.square",
                lines: results,
                emptyText: "本轮还没有已验证结果。"
            )
        }
    }

    private func harnessEvidenceBlock(
        title: String,
        systemImage: String,
        lines: [String],
        emptyText: String,
        limit: Int = 6
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(width: 14)
                Text(title)
                    .font(AppFont.caption(weight: .semibold))
                Spacer(minLength: 0)
                if !lines.isEmpty {
                    Text("\(lines.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(AppTheme.mutedText)
                }
            }
            if lines.isEmpty {
                mutedText(emptyText)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.prefix(limit).enumerated()), id: \.offset) { _, line in
                        Text(harnessCleanListLine(line))
                            .font(AppFont.caption())
                            .foregroundStyle(AppTheme.text)
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                    if lines.count > limit {
                        Text("还有 \(lines.count - limit) 条，展开高级审计查看。")
                            .font(AppFont.caption())
                            .foregroundStyle(AppTheme.mutedText)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func selectedSourceTraceSection(pack: DataPack, run: AnalysisHarnessRun?) -> some View {
        if let resultID = store.selectedMetricResultID,
           let run,
           let result = run.verifiedResults.first(where: { $0.id == resultID }) {
            let sourceCells = store.selectedSourceCellRefs.isEmpty ? (result.source.sourceCells ?? []) : store.selectedSourceCellRefs
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                HStack(spacing: 7) {
                    Image(systemName: "scope")
                        .font(.caption)
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 14)
                    Text("数字血缘定位")
                        .font(AppFont.caption(weight: .semibold))
                    Spacer(minLength: 0)
                    Text(result.displayValue)
                        .font(AppFont.caption(weight: .semibold).monospacedDigit())
                        .foregroundStyle(AppTheme.accentStrong)
                }
                Text(result.label)
                    .font(AppFont.callout(weight: .medium))
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(2)
                Text(result.source.methodology)
                    .font(AppFont.caption())
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(3)
                if sourceCells.isEmpty {
                    mutedText("这项结果没有记录到具体原始单元格。")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 6)], spacing: 6) {
                        ForEach(Array(sourceCells.prefix(8).enumerated()), id: \.offset) { _, cell in
                            compactPill("\(cell.sheetName)!\(cell.a1Address)", tint: AppTheme.accent)
                        }
                    }
                    if let report = reportForSourceTrace(pack: pack, run: run, result: result, sourceCells: sourceCells) {
                        RawTableSnapshotView(
                            report: report,
                            highlightedCells: sourceCells,
                            focusLabel: result.label
                        )
                    } else {
                        mutedText("未能在当前分析资料中定位原始表。")
                    }
                    SourceCellListView(
                        sourceCells: sourceCells,
                        expectedCount: result.source.factRowCount ?? result.source.rowCount
                    )
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.panel.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func reportForSourceTrace(
        pack: DataPack,
        run: AnalysisHarnessRun,
        result: MetricResult,
        sourceCells: [HarnessSourceCellRef]
    ) -> ImportedReport? {
        if let byID = pack.importedReports.first(where: { $0.id.uuidString == result.source.tableID }) {
            return byID
        }
        if let byManifest = run.tableManifest.first(where: { $0.id == result.source.tableID }),
           let report = pack.importedReports.first(where: { $0.id == byManifest.reportID }) {
            return report
        }
        let sheetNames = Set(sourceCells.map { $0.sheetName.normalizedKey })
        if let bySheet = pack.importedReports.first(where: { report in
            let names = [
                report.sheetName,
                report.displayName,
                report.fileName,
                report.sourceFileName
            ].compactMap { $0?.normalizedKey }
            return names.contains { sheetNames.contains($0) }
        }) {
            return bySheet
        }
        return pack.importedReports.first
    }

    private func harnessSectionLines(in detail: String, titles: [String]) -> [String] {
        let allLines = detail.components(separatedBy: .newlines)
        var isCapturing = false
        var captured: [String] = []
        for rawLine in allLines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("## ") {
                let heading = line
                    .replacingOccurrences(of: "#", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                isCapturing = titles.contains { heading.localizedCaseInsensitiveContains($0) }
                continue
            }
            if line.hasPrefix("# ") {
                isCapturing = false
                continue
            }
            if isCapturing {
                captured.append(line)
            }
        }
        return captured.filter { line in
            let cleaned = harnessCleanListLine(line)
            return !cleaned.isEmpty && cleaned != "未生成标准事实表。" && cleaned != "未产生已验证结果。"
        }
    }

    private func harnessCleanListLine(_ line: String) -> String {
        line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^-\\s*", with: "", options: .regularExpression)
    }

    @ViewBuilder
    private func harnessAuditList(_ items: [AnalysisSessionEvidence]) -> some View {
        if items.isEmpty {
            mutedText("还没有 Harness 审计。默认在“仅表格 + 深度分析”路径运行：AI 先生成计划，本地执行指标，再由 AI 解释并由本地校验报告。")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { evidence in
                    DisclosureGroup {
                        Text(evidence.detail)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppTheme.text)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                            .padding(.top, 6)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(evidence.title)
                                    .font(AppFont.callout(weight: .medium))
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(evidence.sourceID.map { String($0.prefix(8)) } ?? "audit")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(AppTheme.mutedText)
                            }
                            Text(harnessAuditSummary(evidence.detail))
                                .font(AppFont.caption())
                                .foregroundStyle(AppTheme.mutedText)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Divider() }
                }
            }
        }
    }

    private func harnessAuditSummary(_ detail: String) -> String {
        let lines = detail
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let status = lines.first(where: { $0.contains("状态：") })?
            .replacingOccurrences(of: "- ", with: "") ?? "状态未记录"
        let resultLine = lines.first(where: { $0.contains("本地验证结果") || $0.contains("Verified Results") })
        return "\(status) · \(resultLine == nil ? "等待 verified results" : "已记录 verified results")"
    }

    @ViewBuilder
    private func notebookRunList(_ runs: [AnalysisNotebookRun]) -> some View {
        if runs.isEmpty {
            mutedText("还没有计算证据。")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(runs) { run in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            mutedText(run.skillSummary.nilIfBlank ?? run.summary)
                            ForEach(run.resultCells.prefix(4)) { cell in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(cell.title.nilIfBlank ?? cell.kind.label)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    if !cell.sql.isEmpty {
                                        Text(cell.sql)
                                            .font(.caption.monospaced())
                                            .textSelection(.enabled)
                                            .padding(8)
                                            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 6))
                                    }
                                    Text("\(cell.status.label) · \(cell.rows.count) 行结果")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        HStack {
                            Text(run.trigger)
                                .font(.callout)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(run.successCount)/\(run.cells.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Divider() }
                }
            }
        }
    }

    @ViewBuilder
    private func collectionRunList(_ runs: [ExternalReferenceCollectionRun]) -> some View {
        if runs.isEmpty {
            mutedText("当前会话还没有关联的外部采集任务。")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(runs) { run in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(run.trigger.label)
                                .font(.callout)
                                .fontWeight(.medium)
                            Spacer(minLength: 8)
                            compactPill(run.status.label, tint: statusColor(run.status))
                        }
                        Text("\(run.startedAt.formatted(date: .numeric, time: .shortened)) · 命中 \(run.rawItemCount) · 新增 \(run.insertedItemCount) · 失败源 \(run.failedSourceCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Divider() }
                }
            }
        }
    }

    @ViewBuilder
    private func aiJobList(_ preview: RelatedAIJobQueuePreview) -> some View {
        if preview.visibleJobs.isEmpty {
            mutedText("当前会话没有 AI 任务记录。")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(preview.visibleJobs) { job in
                    jobRow(job)
                }
            }
        }
    }

    private func compactStatGrid(_ items: [AnalysisInfoStatItem]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 10)], spacing: 8) {
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: item.systemImage)
                        .font(.caption2)
                        .foregroundStyle(item.tint)
                        .frame(width: 14)
                    Text(item.value)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(item.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func compactKeyValue(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.caption)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private func disclosureLabel(_ title: String, count: Int?) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
            if let count {
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.secondary)
    }

    private func mutedText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func compactPill(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.10), in: Capsule())
    }

    private func currentTaskSummary(pack: DataPack, snapshot: AnalysisInfoReportsPanelSnapshot) -> String {
        let taskName = snapshot.currentTask?.name ?? pack.analysisTasks.first?.name ?? "未选择任务"
        return "\(taskName) · \(pack.reportSourceSummary)"
    }

    private func reportMeta(_ report: ImportedReport) -> String {
        "\(report.sourceFormat.label) · \(report.shape.label) · \(report.kind.label) · \(report.rowCount) 行 · \(report.headers.count) 列"
    }

    private func materialsReportMeta(_ report: ImportedReport, isUsedByOtherTask: Bool) -> String {
        var parts = [
            "\(report.rowCount) 行",
            "\(report.headers.count) 列",
            report.sourceFormat.label
        ]
        if isUsedByOtherTask {
            parts.append("其它任务")
        }
        return parts.joined(separator: " · ")
    }

    private func displayRole(
        for report: ImportedReport,
        snapshot: AnalysisInfoReportsPanelSnapshot,
        index: Int
    ) -> AnalysisTaskReportRole {
        if snapshot.currentReports.count == 1 {
            return .primaryBusiness
        }
        if let role = snapshot.currentTask?.reportRoles[report.id] {
            return role
        }
        return index == 0 ? .primaryBusiness : .evidence
    }

    private func materialsRoleLabel(_ role: AnalysisTaskReportRole) -> String {
        switch role {
        case .primaryBusiness:
            return "主表"
        case .impactSource, .outcome:
            return "关联"
        case .evidence:
            return "辅助"
        case .excluded:
            return "排除"
        }
    }

    private func materialsRoleTint(_ role: AnalysisTaskReportRole) -> Color {
        switch role {
        case .primaryBusiness:
            return AppTheme.accent
        case .impactSource, .outcome:
            return .secondary
        case .evidence:
            return .secondary
        case .excluded:
            return AppTheme.danger
        }
    }

    private func coverageModeLabel(_ mode: String) -> String {
        switch mode {
        case "full_rows":
            return "完整行"
        case "profile_only":
            return "画像"
        case "sample_rows":
            return "样本行"
        default:
            return mode
        }
    }

    private func currentTaskReports(in pack: DataPack) -> [ImportedReport] {
        let task = store.currentAnalysisTask(in: pack)
        let activeIDs = Set(task?.activeReportIDs ?? [])
        return pack.importedReports.filter { activeIDs.contains($0.id) && !$0.isIgnoredFromAnalysis }
    }

    private func auditStats(for reports: [ImportedReport]) -> (unresolved: Int, blocked: Int, accepted: Int, confirmed: Int) {
        var unresolved = 0
        var blocked = 0
        var accepted = 0
        var confirmed = 0
        for report in reports {
            unresolved += report.unresolvedAuditSteps.count
            blocked += report.blockingAuditSteps.count
            accepted += report.acceptedRiskAuditSteps.count
            if report.canEnterAnalysis {
                confirmed += 1
            }
        }
        return (unresolved, blocked, accepted, confirmed)
    }

    private func auditTint(for report: ImportedReport) -> Color {
        if !report.blockingAuditSteps.isEmpty { return AppTheme.danger }
        if !report.unresolvedAuditSteps.isEmpty { return AppTheme.warning }
        if !report.acceptedRiskAuditSteps.isEmpty { return .secondary }
        return AppTheme.success
    }

    private func qualityTint(_ verdict: QualityVerdict) -> Color {
        switch verdict {
        case .usable: return AppTheme.success
        case .caution: return AppTheme.warning
        case .blocked: return AppTheme.danger
        }
    }

    private func issueTint(_ severity: IssueSeverity) -> Color {
        switch severity {
        case .info: return .secondary
        case .warning: return AppTheme.warning
        case .critical: return AppTheme.danger
        }
    }

    private func aiJobSummary(_ preview: RelatedAIJobQueuePreview) -> String {
        if preview.issueCount > 0 { return "\(preview.issueCount) 个异常" }
        if preview.activeCount > 0 { return "\(preview.activeCount) 个进行中" }
        if preview.visibleJobs.isEmpty { return "暂无记录" }
        return "状态正常"
    }

    @ViewBuilder
    private func taskControlSection(session: AnalysisSession, pack: DataPack, snapshot: AnalysisInfoReportsPanelSnapshot) -> some View {
        SectionCard(title: "1. 选择分析任务", systemImage: "target") {
            if pack.analysisTasks.isEmpty {
                Text("当前还没有分析任务。请新建任务。")
                    .foregroundStyle(.secondary)
            } else {
                Picker("分析任务", selection: Binding(
                    get: { snapshot.currentTask?.id ?? pack.analysisTasks.first?.id ?? UUID() },
                    set: { store.selectAnalysisTask(taskID: $0) }
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
                    store.createAnalysisTask()
                    store.analysisInfoSidebarPanelID = RootAnalysisInfoPanel.materials.rawValue
                } label: {
                    SemanticLabel(title: "新建任务", systemImage: "plus", role: .business)
                }
                Button {
                    store.showImportPanel()
                } label: {
                    SemanticLabel(title: "导入本地表", systemImage: "tray.and.arrow.down", role: .data)
                }
                .disabled(store.isImportingData)
                Button {
                    store.showTableauImportSheet()
                } label: {
                    SemanticLabel(title: "接入 Tableau", systemImage: "chart.bar.doc.horizontal", role: .data)
                }
                .disabled(store.isImportingData)
                Menu {
                    Button("按最佳模板选表") {
                        store.applyBestAnalysisTemplateToSelectedTask()
                    }
                    .disabled(!snapshot.hasReusableTemplate)
                    Button("把当前任务保存为模板") {
                        store.saveSelectedAnalysisTaskAsTemplate()
                    }
                    .disabled(!snapshot.hasCurrentTaskReports)
                } label: {
                    SemanticLabel(title: "模板", systemImage: "doc.text.magnifyingglass", role: .knowledge)
                }
                .hoverControlShell(.pickerShell)
            }
            .buttonStyle(AppHoverButtonStyle(variant: .secondary))

            Text("当前任务：\(snapshot.currentTask?.name ?? "未选择")。新建任务默认不继承旧任务选表；需要复用上次口径时，请使用“模板”。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup("高级：编辑任务目标") {
                goalEditingSection(session: session)
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func reportSelectionSection(snapshot: AnalysisInfoReportsPanelSnapshot) -> some View {
        SectionCard(title: "2. 选择本次分析表", systemImage: "tablecells") {
            roleLegend

            if snapshot.currentReports.isEmpty {
                Text("还没选表。请在下面“未加入本次分析”里点“加入”，只加入这次要一起联动分析的表。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(snapshot.currentReports) { report in
                        reportRow(report, role: snapshot.currentTask?.reportRoles[report.id], isInTask: true, isUsedByOtherTask: false)
                    }
                }
            }

            DisclosureGroup(isExpanded: $isUnassignedReportsExpanded) {
                if snapshot.unassignedReportCount == 0 {
                    Text("没有未加入本次分析的报表。")
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(snapshot.unassignedReports) { report in
                            reportRow(
                                report,
                                role: nil,
                                isInTask: false,
                                isUsedByOtherTask: snapshot.reportsUsedByOtherTaskIDs.contains(report.id)
                            )
                        }
                        if snapshot.unassignedReports.count < snapshot.unassignedReportCount {
                            Button("显示全部 \(snapshot.unassignedReportCount) 张未加入报表") {
                                showAllUnassignedReports = true
                            }
                            .buttonStyle(AppHoverButtonStyle(variant: .link))
                            .padding(.vertical, 8)
                        }
                    }
                }
            } label: {
                Text("未加入本次分析 \(snapshot.unassignedReportCount) 张")
                    .font(.headline)
            }
        }
    }

    private var roleLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("角色只帮助 AI 区分主次和证据用途，不会限制 AI 读取表格里的所有字段和指标。", systemImage: "info.circle")
                .font(AppFont.caption())
                .foregroundStyle(AppTheme.mutedText)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(AnalysisTaskReportRole.allCases.filter { $0 != .excluded }) { role in
                    GridRow {
                        Text(role.label)
                            .font(AppFont.caption(weight: .semibold))
                            .fontWeight(.semibold)
                        Text(role.explanation)
                            .font(AppFont.caption())
                            .foregroundStyle(AppTheme.mutedText)
                    }
                }
            }
        }
        .padding(10)
        .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    private func reportRow(_ report: ImportedReport, role: AnalysisTaskReportRole?, isInTask: Bool, isUsedByOtherTask: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(report.displayName)
                    .font(AppFont.headline())
                    .lineLimit(2)
                if isInTask {
                    Text("已加入当前任务")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.success)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.success.opacity(0.14), in: Capsule())
                } else if isUsedByOtherTask {
                    Text("来自其他任务")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.warning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.warning.opacity(0.14), in: Capsule())
                }
                Spacer(minLength: 8)
            }

            Text("\(report.sourceFormat.label) · \(report.shape.label) · \(report.kind.label) · \(report.rowCount) 行 · \(report.headers.count) 列 · 首列指标 \(report.firstColumnValues.count) 个")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if isInTask {
                    Picker("报表角色", selection: Binding(
                        get: { role ?? .evidence },
                        set: { store.setSelectedTaskReportRole(reportID: report.id, role: $0) }
                    )) {
                        ForEach(AnalysisTaskReportRole.allCases.filter { $0 != .excluded }) { role in
                            Text(role.label).tag(role)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 132)
                    .hoverControlShell(.pickerShell)

                    Button {
                        store.removeReportFromSelectedTask(reportID: report.id)
                    } label: {
                        SemanticLabel(title: "移出", systemImage: "minus.circle", role: .risk)
                    }
                    .buttonStyle(AppHoverButtonStyle(variant: .danger))
                } else {
                    Button {
                        let defaultRole: AnalysisTaskReportRole
                        if let pack = store.selectedPack, store.reportsForCurrentTask(in: pack).isEmpty {
                            defaultRole = .primaryBusiness
                        } else {
                            defaultRole = .evidence
                        }
                        store.addReportToSelectedTask(reportID: report.id, role: defaultRole)
                    } label: {
                        SemanticLabel(title: "加入本次分析", systemImage: "plus.circle", role: .data)
                    }
                    .buttonStyle(AppHoverButtonStyle(variant: .primary))
                }
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private func goalEditingSection(session: AnalysisSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.goal.nilIfBlank ?? "首条用户问题会自动成为任务目标。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func dataCoverageSection(snapshot activitySnapshot: AnalysisInfoActivityPanelSnapshot) -> some View {
        let snapshot = activitySnapshot.coverageSnapshot
        SectionCard(title: "AI 读取到的数据", systemImage: "eye") {
            if let snapshot {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("报表")
                        Text("\(snapshot.totalReports) 张")
                    }
                    GridRow {
                        Text("行列")
                        Text("\(snapshot.totalRows) 行 · \(snapshot.totalColumns) 列")
                    }
                    GridRow {
                        Text("指标/周期")
                        Text("\(snapshot.totalMetrics) 个指标 · \(snapshot.totalTimeColumns) 个时间周期")
                    }
                    GridRow {
                        Text("外部证据")
                        Text("\(snapshot.referenceItemCount) 条")
                    }
                }
                .font(.caption)

                ForEach(snapshot.reportSnapshots.prefix(8)) { report in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(report.reportName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("\(report.rowCount) 行 · \(report.columnCount) 列 · \(report.metricCount) 指标 · \(report.timeColumnCount) 周期 · \(report.dataMode)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    Divider()
                }

                if !snapshot.limitations.isEmpty {
                    DisclosureGroup("限制说明 \(snapshot.limitations.count) 条") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(snapshot.limitations, id: \.self) { limitation in
                                Text("· \(limitation)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Text("还没有覆盖快照。发送深度分析或生成汇报后，系统会记录 AI 实际读取了哪些表、字段、指标和外部证据。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        SectionCard(title: "采集日志", systemImage: "clock.arrow.circlepath") {
            let runs = activitySnapshot.collectionRuns
            if runs.isEmpty {
                Text("当前会话还没有关联的外部采集任务。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(runs) { run in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(run.trigger.label)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(run.status.label)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(statusColor(run.status).opacity(0.16), in: Capsule())
                                .foregroundStyle(statusColor(run.status))
                        }
                        Text("\(run.startedAt.formatted(date: .numeric, time: .shortened)) · 命中 \(run.rawItemCount) · 新增 \(run.insertedItemCount) · 失败源 \(run.failedSourceCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func notebookEvidenceSection(snapshot activitySnapshot: AnalysisInfoActivityPanelSnapshot) -> some View {
        SectionCard(title: "计算证据", systemImage: "function") {
            let recentRuns = activitySnapshot.notebookRuns
            if recentRuns.isEmpty {
                Text("还没有计算证据。深度分析或汇报生成时，AI 可请求本地 SQL/Notebook 执行可验证计算。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentRuns) { run in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(run.skillSummary.nilIfBlank ?? run.summary)
                                .foregroundStyle(.secondary)
                            ForEach(run.resultCells.prefix(6)) { cell in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(cell.title.nilIfBlank ?? cell.kind.label)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    if !cell.sql.isEmpty {
                                        Text(cell.sql)
                                            .font(.caption.monospaced())
                                            .textSelection(.enabled)
                                            .padding(8)
                                            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 6))
                                    }
                                    Text("\(cell.status.label) · \(cell.rows.count) 行结果")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        HStack {
                            Text(run.trigger)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(run.successCount)/\(run.cells.count) 成功")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func aiJobQueueSection(snapshot activitySnapshot: AnalysisInfoActivityPanelSnapshot) -> some View {
        let preview = activitySnapshot.aiJobPreview
        SectionCard(title: "AI 任务队列", systemImage: "clock.badge.checkmark") {
            if preview.visibleJobs.isEmpty {
                Text("当前会话没有 AI 任务记录。")
                    .foregroundStyle(.secondary)
            } else {
                Text(preview.issueCount > 0 ? "有 \(preview.issueCount) 个任务需要处理" : (preview.activeCount > 0 ? "有 \(preview.activeCount) 个任务正在执行" : "最近 AI 任务状态正常"))
                    .foregroundStyle(preview.issueCount > 0 ? AppTheme.danger : AppTheme.mutedText)

                ForEach(preview.visibleJobs) { job in
                    jobRow(job)
                }
            }
        }
    }

    private func activeReportIDsUsedByOtherTasks(in pack: DataPack, excluding currentTaskID: UUID?) -> Set<UUID> {
        var reportIDs = Set<UUID>()
        for task in pack.analysisTasks where task.id != currentTaskID {
            reportIDs.formUnion(task.activeReportIDs)
        }
        return reportIDs
    }

    private func currentActivitySnapshot(session: AnalysisSession, pack: DataPack) -> AnalysisInfoActivityPanelSnapshot {
        guard activitySnapshot.sessionID == session.id,
              activitySnapshot.packID == pack.id else {
            return .empty
        }
        return activitySnapshot
    }

    private func isActivityPanelSelected() -> Bool {
        selectedPanel.wrappedValue == .evidence
    }

    private func scheduleActivitySnapshotRefresh(delayNanoseconds: UInt64 = 220_000_000) {
        guard isActivityPanelSelected() else { return }
        activityRefreshTask?.cancel()
        activityRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            refreshActivitySnapshot(force: false)
            activityRefreshTask = nil
        }
    }

    private func refreshActivitySnapshot(force: Bool) {
        guard isActivityPanelSelected(),
              let pack = store.selectedPack,
              let session = store.selectedAnalysisSession,
              session.packID == pack.id else {
            return
        }
        let currentTask = store.currentAnalysisTask(in: pack)
        let revision = makeActivityRevision(
            session: session,
            pack: pack,
            taskID: currentTask?.id
        )
        guard force || revision != activityRevision else { return }
        activitySnapshot = makeActivitySnapshot(
            session: session,
            pack: pack,
            taskID: currentTask?.id
        )
        activityRevision = revision
    }

    private func makeActivitySnapshot(
        session: AnalysisSession,
        pack: DataPack,
        taskID: UUID?
    ) -> AnalysisInfoActivityPanelSnapshot {
        let coverageSnapshot = session.coverageSnapshots?.last
        let collectionRuns = relatedCollectionRuns(
            session: session,
            pack: pack,
            taskID: taskID,
            limit: 8
        )
        let notebookRuns = recentNotebookRuns(in: session, limit: 8)
        let relatedJobs = relatedPersistentAIJobs(
            session: session,
            pack: pack,
            taskID: taskID,
            limit: 24
        )
        let aiJobPreview = relatedAIJobQueuePreview(
            session: session,
            pack: pack,
            taskID: taskID,
            limit: 12
        )
        return AnalysisInfoActivityPanelSnapshot(
            sessionID: session.id,
            packID: pack.id,
            coverageSnapshot: coverageSnapshot,
            collectionRuns: collectionRuns,
            notebookRuns: notebookRuns,
            aiJobPreview: aiJobPreview,
            traceEvents: AnalysisTraceTimelineBuilder.build(
                session: session,
                coverageSnapshot: coverageSnapshot,
                harnessEvidence: harnessAuditEvidence(session: session),
                notebookRuns: notebookRuns,
                collectionRuns: collectionRuns,
                jobs: relatedJobs
            )
        )
    }

    private func makeActivityRevision(
        session: AnalysisSession,
        pack: DataPack,
        taskID: UUID?
    ) -> AnalysisInfoActivityPanelRevision {
        AnalysisInfoActivityPanelRevision(
            panelID: selectedPanel.wrappedValue.rawValue,
            sessionID: session.id,
            packID: pack.id,
            taskID: taskID,
            coverageSignature: coverageSignature(session),
            messageTraceSignature: messageTraceSignature(session),
            notebookSignature: notebookSignature(session),
            collectionRunSignature: collectionRunSignature(session: session, pack: pack, taskID: taskID),
            jobSignature: aiJobSignature(session: session, pack: pack, taskID: taskID)
        )
    }

    private func coverageSignature(_ session: AnalysisSession) -> Int {
        var hasher = Hasher()
        guard let snapshot = session.coverageSnapshots?.last else {
            hasher.combine(0)
            return hasher.finalize()
        }
        hasher.combine(snapshot.id)
        hasher.combine(snapshot.createdAt)
        hasher.combine(snapshot.totalReports)
        hasher.combine(snapshot.totalRows)
        hasher.combine(snapshot.totalColumns)
        hasher.combine(snapshot.totalMetrics)
        hasher.combine(snapshot.totalTimeColumns)
        hasher.combine(snapshot.referenceItemCount)
        hasher.combine(snapshot.reportSnapshots.count)
        hasher.combine(snapshot.limitations.count)
        return hasher.finalize()
    }

    private func messageTraceSignature(_ session: AnalysisSession) -> Int {
        var hasher = Hasher()
        hasher.combine(session.messages.count)
        for message in session.messages.suffix(20) {
            hasher.combine(message.id)
            hasher.combine(message.createdAt)
            hasher.combine(message.role)
            hasher.combine(message.kind)
            hasher.combine(message.content.utf8.count)
            hasher.combine(message.streamingStatus?.state)
            hasher.combine(message.streamingStatus?.updatedAt)
            hasher.combine(message.evidence.count)
            for evidence in message.evidence {
                hasher.combine(evidence.id)
                hasher.combine(evidence.sourceType)
                hasher.combine(evidence.sourceID)
                hasher.combine(evidence.analysisHarnessRun?.id)
                hasher.combine(evidence.analysisHarnessRun?.auditLog.count)
                hasher.combine(evidence.analysisHarnessRun?.answerNumberTraces?.count)
            }
        }
        return hasher.finalize()
    }

    private func notebookSignature(_ session: AnalysisSession) -> Int {
        var hasher = Hasher()
        hasher.combine(session.notebookRuns.count)
        for run in recentNotebookRuns(in: session, limit: 8) {
            hasher.combine(run.id)
            hasher.combine(run.createdAt)
            hasher.combine(run.cells.count)
            hasher.combine(run.successCount)
            hasher.combine(run.warnings.count)
        }
        return hasher.finalize()
    }

    private func collectionRunSignature(session: AnalysisSession, pack: DataPack, taskID: UUID?) -> Int {
        var hasher = Hasher()
        for run in store.workspace.referenceCollectionRuns where isRelated(run: run, session: session, pack: pack, taskID: taskID) {
            hasher.combine(run.id)
            hasher.combine(run.status)
            hasher.combine(run.startedAt)
            hasher.combine(run.endedAt)
            hasher.combine(run.rawItemCount)
            hasher.combine(run.insertedItemCount)
            hasher.combine(run.failedSourceCount)
            hasher.combine(run.phase)
            hasher.combine(run.completedSourceCount)
        }
        return hasher.finalize()
    }

    private func aiJobSignature(session: AnalysisSession, pack: DataPack, taskID: UUID?) -> Int {
        var hasher = Hasher()
        for job in store.workspace.persistentAIJobs where isRelated(job: job, session: session, pack: pack, taskID: taskID) {
            hasher.combine(job.id)
            hasher.combine(job.status)
            hasher.combine(job.updatedAt)
            hasher.combine(job.attemptCount)
            hasher.combine(job.maxImmediateAttempts)
            hasher.combine(job.lastError)
            hasher.combine(job.logs.count)
        }
        return hasher.finalize()
    }

    private func scheduleReportsSnapshotRefresh(delayNanoseconds: UInt64 = 220_000_000) {
        guard selectedPanel.wrappedValue == .materials else { return }
        reportsRefreshTask?.cancel()
        reportsRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            refreshReportsSnapshot(force: false)
            reportsRefreshTask = nil
        }
    }

    private func refreshReportsSnapshot(force: Bool) {
        guard selectedPanel.wrappedValue == .materials,
              let pack = store.selectedPack else {
            return
        }
        let revision = makeReportsRevision(pack: pack)
        guard force || revision != reportsRevision else { return }
        reportsSnapshot = makeReportsSnapshot(pack: pack)
        reportsRevision = revision
    }

    private func makeReportsSnapshot(pack: DataPack) -> AnalysisInfoReportsPanelSnapshot {
        let currentTask = store.currentAnalysisTask(in: pack)
        let selectedIDs = Set(currentTask?.activeReportIDs ?? [])
        let currentTaskID = currentTask?.id
        let reportsUsedByOtherTaskIDs = activeReportIDsUsedByOtherTasks(in: pack, excluding: currentTaskID)
        let currentReports = pack.importedReports.filter { selectedIDs.contains($0.id) }
        let unassignedPreview = unassignedReportPreview(
            in: pack,
            selectedIDs: selectedIDs,
            showAll: showAllUnassignedReports,
            limit: 80
        )

        return AnalysisInfoReportsPanelSnapshot(
            currentTask: currentTask,
            hasReusableTemplate: store.workspace.analysisTemplateMemories.contains { !$0.isArchived },
            hasCurrentTaskReports: currentTask?.activeReportIDs.isEmpty == false,
            currentReports: currentReports,
            unassignedReports: unassignedPreview.reports,
            unassignedReportCount: unassignedPreview.totalCount,
            reportsUsedByOtherTaskIDs: reportsUsedByOtherTaskIDs
        )
    }

    private func makeReportsRevision(pack: DataPack) -> AnalysisInfoReportsPanelRevision {
        AnalysisInfoReportsPanelRevision(
            packID: pack.id,
            reportSignature: reportsSignature(pack),
            taskSignature: tasksSignature(pack),
            templateSignature: templatesSignature(),
            showAllUnassignedReports: showAllUnassignedReports
        )
    }

    private func reportsSignature(_ pack: DataPack) -> Int {
        var hasher = Hasher()
        for report in pack.importedReports {
            hasher.combine(report.id)
            hasher.combine(report.importedAt)
            hasher.combine(report.userReportAlias)
            hasher.combine(report.kind)
            hasher.combine(report.isIgnoredFromAnalysis)
        }
        return hasher.finalize()
    }

    private func tasksSignature(_ pack: DataPack) -> Int {
        var hasher = Hasher()
        hasher.combine(pack.selectedAnalysisTaskID)
        for task in pack.analysisTasks {
            hasher.combine(task.id)
            hasher.combine(task.name)
            hasher.combine(task.goal)
            hasher.combine(task.updatedAt)
            for reportID in task.activeReportIDs {
                hasher.combine(reportID)
                hasher.combine(task.role(for: reportID))
            }
        }
        return hasher.finalize()
    }

    private func templatesSignature() -> Int {
        var hasher = Hasher()
        for template in store.workspace.analysisTemplateMemories {
            hasher.combine(template.id)
            hasher.combine(template.isArchived)
            hasher.combine(template.updatedAt)
        }
        return hasher.finalize()
    }

    private func unassignedReportPreview(
        in pack: DataPack,
        selectedIDs: Set<UUID>,
        showAll: Bool,
        limit: Int
    ) -> (reports: [ImportedReport], totalCount: Int) {
        var totalCount = 0
        var reports: [ImportedReport] = []
        reports.reserveCapacity(showAll ? min(pack.importedReports.count, 256) : limit)

        for report in pack.importedReports where !selectedIDs.contains(report.id) && !report.isIgnoredFromAnalysis {
            totalCount += 1
            if showAll {
                reports.append(report)
            } else {
                insertReportByImportedAt(report, into: &reports, limit: limit)
            }
        }

        if showAll {
            reports.sort { $0.importedAt > $1.importedAt }
        }
        return (reports, totalCount)
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

    private func recentNotebookRuns(in session: AnalysisSession, limit: Int) -> [AnalysisNotebookRun] {
        var runs: [AnalysisNotebookRun] = []
        runs.reserveCapacity(limit)

        for run in session.notebookRuns {
            if runs.count == limit,
               let last = runs.last,
               run.createdAt <= last.createdAt {
                continue
            }
            if let index = runs.firstIndex(where: { run.createdAt > $0.createdAt }) {
                runs.insert(run, at: index)
            } else {
                runs.append(run)
            }
            if runs.count > limit {
                runs.removeLast()
            }
        }
        return runs
    }

    private func jobRow(_ job: RelatedAIJobRowSnapshot) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                if !job.lastError.isEmpty {
                    Text(job.lastError)
                        .font(.caption)
                        .foregroundStyle(AppTheme.danger)
                        .textSelection(.enabled)
                }
                ForEach(job.latestLogs) { log in
                    Text("\(log.createdAt.formatted(date: .omitted, time: .shortened)) · \(log.step)：\(log.detail)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 10) {
                Text(job.kind.label)
                    .fontWeight(.semibold)
                Text("\(job.targetName.nilIfBlank ?? "当前任务") · \(job.attemptCount)/\(job.maxImmediateAttempts) 次")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(job.status.label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(jobStatusColor(job.status))
                    .background(jobStatusColor(job.status).opacity(0.16), in: Capsule())
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func relatedCollectionRuns(
        session: AnalysisSession,
        pack: DataPack,
        taskID: UUID?,
        limit: Int
    ) -> [ExternalReferenceCollectionRun] {
        var runs: [ExternalReferenceCollectionRun] = []
        runs.reserveCapacity(limit)

        for run in store.workspace.referenceCollectionRuns where isRelated(run: run, session: session, pack: pack, taskID: taskID) {
            insertCollectionRun(run, into: &runs, limit: limit)
        }

        return runs
    }

    private func relatedPersistentAIJobs(
        session: AnalysisSession,
        pack: DataPack,
        taskID: UUID?,
        limit: Int
    ) -> [PersistentAIJob] {
        Array(
            store.workspace.persistentAIJobs
                .filter { isRelated(job: $0, session: session, pack: pack, taskID: taskID) }
                .sorted { lhs, rhs in lhs.updatedAt > rhs.updatedAt }
                .prefix(limit)
        )
    }

    private func isRelated(
        run: ExternalReferenceCollectionRun,
        session: AnalysisSession,
        pack: DataPack,
        taskID: UUID?
    ) -> Bool {
        run.sessionID == session.id ||
        run.packID == pack.id ||
        (taskID != nil && run.taskID == taskID)
    }

    private func insertCollectionRun(
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

    private func relatedAIJobQueuePreview(
        session: AnalysisSession,
        pack: DataPack,
        taskID: UUID?,
        limit: Int
    ) -> RelatedAIJobQueuePreview {
        var visibleJobs: [RelatedAIJobRowSnapshot] = []
        visibleJobs.reserveCapacity(limit)
        var activeCount = 0
        var issueCount = 0

        for job in store.workspace.persistentAIJobs where isRelated(job: job, session: session, pack: pack, taskID: taskID) {
            if job.status.isActive || job.status == .waiting {
                activeCount += 1
            }
            if job.status == .failed || job.status == .needsUserAction {
                issueCount += 1
            }

            insertRelatedAIJob(RelatedAIJobRowSnapshot(job: job), into: &visibleJobs, limit: limit)
        }

        return RelatedAIJobQueuePreview(
            visibleJobs: visibleJobs,
            activeCount: activeCount,
            issueCount: issueCount
        )
    }

    private func isRelated(
        job: PersistentAIJob,
        session: AnalysisSession,
        pack: DataPack,
        taskID: UUID?
    ) -> Bool {
        job.payload.sessionID == session.id ||
        job.payload.packID == pack.id ||
        (taskID != nil && job.payload.taskID == taskID)
    }

    private func insertRelatedAIJob(
        _ job: RelatedAIJobRowSnapshot,
        into jobs: inout [RelatedAIJobRowSnapshot],
        limit: Int
    ) {
        guard limit > 0 else { return }
        if jobs.count == limit,
           let last = jobs.last,
           !relatedAIJobSortsBefore(job, last) {
            return
        }

        if let index = jobs.firstIndex(where: { relatedAIJobSortsBefore(job, $0) }) {
            jobs.insert(job, at: index)
        } else {
            jobs.append(job)
        }
        if jobs.count > limit {
            jobs.removeLast()
        }
    }

    private func relatedAIJobSortsBefore(_ lhs: RelatedAIJobRowSnapshot, _ rhs: RelatedAIJobRowSnapshot) -> Bool {
        let lhsRank = jobSortRank(lhs.status)
        let rhsRank = jobSortRank(rhs.status)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private func jobSortRank(_ status: AIJobStatus) -> Int {
        switch status {
        case .failed, .needsUserAction: return 0
        case .requesting, .validating, .correcting: return 1
        case .waiting: return 2
        case .completed: return 3
        case .cancelled: return 4
        }
    }

    private func jobStatusColor(_ status: AIJobStatus) -> Color {
        switch status {
        case .failed, .needsUserAction: return AppTheme.danger
        case .waiting: return AppTheme.warning
        case .requesting, .validating, .correcting: return AppTheme.accent
        case .completed: return AppTheme.success
        case .cancelled: return .secondary
        }
    }

    private func statusColor(_ status: ExternalReferenceCollectionStatus) -> Color {
        switch status {
        case .running: return AppTheme.accent
        case .succeeded: return AppTheme.success
        case .partialFailed: return AppTheme.warning
        case .failed: return AppTheme.danger
        case .cancelled: return .secondary
        }
    }
}

private struct SourceCellListView: View {
    var sourceCells: [HarnessSourceCellRef]
    var expectedCount: Int
    @State private var isExpanded = false
    private let recordLimit = 5_000

    private var sortedCells: [HarnessSourceCellRef] {
        sourceCells.sorted { lhs, rhs in
            if lhs.sheetName != rhs.sheetName {
                return lhs.sheetName.localizedStandardCompare(rhs.sheetName) == .orderedAscending
            }
            if lhs.row != rhs.row { return lhs.row < rhs.row }
            return lhs.column < rhs.column
        }
    }

    private var uniqueCells: [HarnessSourceCellRef] {
        var seen = Set<String>()
        var result: [HarnessSourceCellRef] = []
        for cell in sortedCells {
            let key = "\(cell.sheetName)|\(cell.row)|\(cell.column)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(cell)
        }
        return result
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                Text(sourceCountText)
                    .font(AppFont.caption())
                    .foregroundStyle(AppTheme.mutedText)
                ScrollView([.vertical, .horizontal], showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        headerRow
                        ForEach(Array(uniqueCells.enumerated()), id: \.offset) { _, cell in
                            sourceRow(cell)
                        }
                    }
                    .background(AppTheme.card.opacity(0.50), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.border.opacity(0.45), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxHeight: 300)
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.caption)
                    .foregroundStyle(AppTheme.icon)
                Text(title)
                    .font(AppFont.caption(weight: .semibold))
                Spacer(minLength: 0)
                Text("\(uniqueCells.count) 条")
                    .font(AppFont.caption2().monospacedDigit())
                    .foregroundStyle(AppTheme.mutedText)
            }
        }
        .tint(AppTheme.accent)
        .padding(.top, 2)
    }

    private var title: String {
        if expectedCount > uniqueCells.count {
            return "查看已记录来源行"
        }
        return "查看全部来源行"
    }

    private var sourceCountText: String {
        if expectedCount > recordLimit, uniqueCells.count >= recordLimit {
            return "已记录 \(uniqueCells.count) 条来源单元格，已达到记录保护上限；其余来源可通过原始表快照继续核对。"
        }
        if expectedCount > uniqueCells.count {
            return "当前结果涉及 \(expectedCount) 条标准事实行，已保存 \(uniqueCells.count) 条可点击来源单元格。旧分析结果可能只保存了代表性来源；重新分析后会记录更多来源。"
        }
        return "已保存全部 \(uniqueCells.count) 条可点击来源单元格。"
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            tableCell("Sheet", width: 120, isHeader: true)
            tableCell("单元格", width: 86, isHeader: true)
            tableCell("行", width: 58, isHeader: true)
            tableCell("列", width: 58, isHeader: true)
            tableCell("值", width: 180, isHeader: true)
        }
    }

    private func sourceRow(_ cell: HarnessSourceCellRef) -> some View {
        HStack(spacing: 0) {
            tableCell(cell.sheetName, width: 120)
            tableCell(cell.a1Address, width: 86)
            tableCell("\(cell.row)", width: 58)
            tableCell(HarnessSourceCellRef.columnLabel(cell.column), width: 58)
            tableCell(cell.value.nilIfBlank ?? " ", width: 180)
        }
    }

    private func tableCell(_ text: String, width: CGFloat, isHeader: Bool = false) -> some View {
        Text(text)
            .font(isHeader ? AppFont.caption2(weight: .semibold) : AppFont.caption())
            .foregroundStyle(isHeader ? AppTheme.mutedText : AppTheme.text)
            .lineLimit(2)
            .textSelection(.enabled)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(isHeader ? AppTheme.panelStrong.opacity(0.58) : AppTheme.card.opacity(0.32))
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(AppTheme.border.opacity(0.42))
                    .frame(width: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AppTheme.border.opacity(0.36))
                    .frame(height: 1)
            }
    }
}

private struct RawTableSnapshotView: View {
    var report: ImportedReport
    var highlightedCells: [HarnessSourceCellRef]
    var focusLabel: String

    private let maxVisibleRows = 18
    private let maxVisibleColumns = 8
    private let cellWidth: CGFloat = 118
    private let rowHeaderWidth: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: "tablecells")
                    .font(.caption)
                    .foregroundStyle(AppTheme.icon)
                Text("原始表快照")
                    .font(AppFont.caption(weight: .semibold))
                Spacer(minLength: 0)
                Text(snapshotRangeText)
                    .font(AppFont.caption2().monospacedDigit())
                    .foregroundStyle(AppTheme.mutedText)
            }
            if rows.isEmpty {
                Text("这张表没有可展示的原始行。")
                    .font(AppFont.caption())
                    .foregroundStyle(AppTheme.mutedText)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        tableRow(rowNumber: 0, values: columnHeaderValues, isColumnHeader: true)
                        ForEach(visibleRowNumbers, id: \.self) { rowNumber in
                            tableRow(
                                rowNumber: rowNumber,
                                values: values(for: rowNumber),
                                isColumnHeader: false
                            )
                        }
                    }
                    .background(AppTheme.card.opacity(0.64), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.border.opacity(0.55), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxHeight: 250)
            }
        }
        .padding(.top, 2)
        .help("来自 \(report.displayName)：\(focusLabel)")
    }

    private var rows: [[String]] {
        report.rawRows
    }

    private var focusRow: Int {
        highlightedCells.first?.row ?? 1
    }

    private var focusColumn: Int {
        highlightedCells.first?.column ?? 1
    }

    private var visibleRowNumbers: [Int] {
        guard !rows.isEmpty else { return [] }
        let total = rows.count
        let highlightedRows = Array(Set(highlightedCells.map(\.row).filter { $0 >= 1 && $0 <= total })).sorted()
        if highlightedRows.count > 1 {
            if highlightedRows.count > maxVisibleRows {
                return representativeRows(from: highlightedRows, limit: maxVisibleRows)
            }
            var selected = Set<Int>()
            func add(_ row: Int) {
                guard row >= 1, row <= total, selected.count < maxVisibleRows else { return }
                selected.insert(row)
            }
            for row in highlightedRows {
                add(row)
            }
            var radius = 1
            while selected.count < maxVisibleRows && radius <= 2 {
                for row in highlightedRows where selected.count < maxVisibleRows {
                    add(row - radius)
                    add(row + radius)
                }
                radius += 1
            }
            return selected.sorted()
        }
        let half = maxVisibleRows / 2
        let start = max(1, min(max(1, focusRow - half), max(1, total - maxVisibleRows + 1)))
        let end = min(total, start + maxVisibleRows - 1)
        return Array(start...end)
    }

    private func representativeRows(from rows: [Int], limit: Int) -> [Int] {
        guard rows.count > limit else { return rows }
        var selected = Set<Int>()
        func add(_ index: Int) {
            guard rows.indices.contains(index), selected.count < limit else { return }
            selected.insert(rows[index])
        }
        let anchors = [
            0,
            rows.count / 4,
            rows.count / 2,
            rows.count * 3 / 4,
            rows.count - 1
        ]
        for anchor in anchors {
            add(anchor)
        }
        var offset = 1
        while selected.count < limit && offset < rows.count {
            for anchor in anchors where selected.count < limit {
                add(anchor + offset)
                add(anchor - offset)
            }
            offset += 1
        }
        return selected.sorted()
    }

    private var visibleColumnNumbers: [Int] {
        let total = max(rows.map(\.count).max() ?? 0, report.headers.count)
        guard total > 0 else { return [] }
        let half = maxVisibleColumns / 2
        let start = max(1, min(max(1, focusColumn - half), max(1, total - maxVisibleColumns + 1)))
        let end = min(total, start + maxVisibleColumns - 1)
        return Array(start...end)
    }

    private var highlightedKeys: Set<String> {
        Set(highlightedCells.map { "\($0.row):\($0.column)" })
    }

    private var snapshotRangeText: String {
        guard let firstRow = visibleRowNumbers.first,
              let lastRow = visibleRowNumbers.last,
              let firstColumn = visibleColumnNumbers.first,
              let lastColumn = visibleColumnNumbers.last else {
            return "无窗口"
        }
        let rowText: String
        if visibleRowNumbers.count == lastRow - firstRow + 1 {
            rowText = "R\(firstRow)-R\(lastRow)"
        } else {
            rowText = "R\(firstRow)-R\(lastRow) 抽样"
        }
        return "\(rowText) · \(HarnessSourceCellRef.columnLabel(firstColumn))-\(HarnessSourceCellRef.columnLabel(lastColumn))"
    }

    private var columnHeaderValues: [String] {
        visibleColumnNumbers.map { column in
            let letter = HarnessSourceCellRef.columnLabel(column)
            if let header = value(row: 1, column: column).nilIfBlank {
                return "\(letter) · \(header)"
            }
            return letter
        }
    }

    private func values(for rowNumber: Int) -> [String] {
        visibleColumnNumbers.map { value(row: rowNumber, column: $0) }
    }

    private func value(row rowNumber: Int, column columnNumber: Int) -> String {
        guard rowNumber > 0,
              rowNumber <= rows.count,
              columnNumber > 0,
              columnNumber <= rows[rowNumber - 1].count else {
            return ""
        }
        return rows[rowNumber - 1][columnNumber - 1]
    }

    private func tableRow(rowNumber: Int, values: [String], isColumnHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(isColumnHeader ? "#" : "\(rowNumber)")
                .font(AppFont.caption2(weight: .semibold).monospacedDigit())
                .foregroundStyle(AppTheme.mutedText)
                .frame(width: rowHeaderWidth, alignment: .trailing)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(AppTheme.panelStrong.opacity(0.58))
            ForEach(Array(values.enumerated()), id: \.offset) { index, text in
                let columnNumber = visibleColumnNumbers[index]
                let highlighted = highlightedKeys.contains("\(rowNumber):\(columnNumber)")
                Text(text.nilIfBlank ?? " ")
                    .font(isColumnHeader ? AppFont.caption(weight: .semibold) : AppFont.caption())
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .frame(width: cellWidth, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(cellBackground(isHeader: isColumnHeader, isHighlighted: highlighted))
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(AppTheme.border.opacity(0.45))
                            .frame(width: 1)
                    }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.border.opacity(0.42))
                .frame(height: 1)
        }
    }

    private func cellBackground(isHeader: Bool, isHighlighted: Bool) -> Color {
        if isHighlighted {
            return AppTheme.accent.opacity(0.24)
        }
        if isHeader {
            return AppTheme.panelStrong.opacity(0.58)
        }
        return AppTheme.card.opacity(0.42)
    }
}

private extension HarnessSourceCellRef {
    static func columnLabel(_ column: Int) -> String {
        guard column > 0 else { return "?" }
        var number = column
        var result = ""
        while number > 0 {
            let remainder = (number - 1) % 26
            result = String(UnicodeScalar(65 + remainder)!) + result
            number = (number - 1) / 26
        }
        return result
    }
}
