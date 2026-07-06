import SwiftUI

private struct SessionAuditPanelSnapshot {
    var currentTask: AnalysisTask?
    var currentTaskReports: [ImportedReport]
    var visibleReports: [ImportedReport]
    var hasMoreReports: Bool
    var currentReport: ImportedReport?
    var activeReportCount: Int
    var totalReportCount: Int
    var unresolvedIssueCount: Int
    var blockedIssueCount: Int
    var acceptedRiskCount: Int
    var reportDefinitions: [ReportFieldDefinition]
    var visibleDefinitions: [ReportFieldDefinition]
    var currentDefinition: ReportFieldDefinition?
    var latestAssistantQAMessage: ReportQAMessage?

    static let empty = SessionAuditPanelSnapshot(
        currentTask: nil,
        currentTaskReports: [],
        visibleReports: [],
        hasMoreReports: false,
        currentReport: nil,
        activeReportCount: 0,
        totalReportCount: 0,
        unresolvedIssueCount: 0,
        blockedIssueCount: 0,
        acceptedRiskCount: 0,
        reportDefinitions: [],
        visibleDefinitions: [],
        currentDefinition: nil,
        latestAssistantQAMessage: nil
    )
}

private struct SessionAuditPanelRevision: Equatable {
    var packID: UUID
    var reportSignature: Int
    var fieldDefinitionSignature: Int
    var currentTaskSignature: Int
    var selectedReportID: UUID?
    var selectedDictionaryFieldID: UUID?
    var fieldSearchText: String
    var showAllReports: Bool
}

struct SessionAuditPanel: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    var pack: DataPack
    @Binding var selectedReportID: UUID?
    @Binding var selectedDictionaryFieldID: UUID?
    @Binding var descriptionDraft: String
    @Binding var answerText: String
    @Binding var qaQuestionText: String
    @Binding var dictionaryAnswerText: String
    @Binding var fieldSearchText: String
    @Binding var taskNameDraft: String
    @Binding var taskGoalDraft: String

    @State private var showAllReports = false
    @State private var processingExpanded = false
    @State private var coverageExpanded = false
    @State private var semanticExpanded = false
    @State private var fieldsExpanded = false
    @State private var qaExpanded = false
    @State private var snapshot = SessionAuditPanelSnapshot.empty
    @State private var snapshotRevision: SessionAuditPanelRevision?
    @State private var snapshotRefreshTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            summarySection(snapshot)
            reportListSection(snapshot)
            if let report = snapshot.currentReport {
                selectedReportSection(report, snapshot: snapshot)
            } else {
                SectionCard(title: "审核与口径", systemImage: "checklist.checked") {
                    Text("当前分析资料还没有可用表。请先导入本地表或接入 Tableau，并确认加入本次分析。")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            ensureSelection()
            refreshSnapshot(force: true)
        }
        .onChange(of: pack.id) { _ in
            selectedReportID = nil
            selectedDictionaryFieldID = nil
            descriptionDraft = ""
            answerText = ""
            qaQuestionText = ""
            dictionaryAnswerText = ""
            fieldSearchText = ""
            ensureSelection()
            refreshSnapshot(force: true)
        }
        .onChange(of: selectedReportID) { _ in
            let latestSnapshot = makeSnapshot()
            snapshot = latestSnapshot
            snapshotRevision = makeSnapshotRevision()
            descriptionDraft = latestSnapshot.currentReport?.semanticProfile.summary ?? ""
            answerText = ""
            qaQuestionText = ""
            dictionaryAnswerText = ""
            selectedDictionaryFieldID = nil
        }
        .onChange(of: selectedDictionaryFieldID) { _ in
            refreshSnapshot(force: true)
        }
        .onChange(of: fieldSearchText) { _ in
            scheduleSnapshotRefresh(delayNanoseconds: 120_000_000)
        }
        .onChange(of: showAllReports) { _ in
            refreshSnapshot(force: true)
        }
        .onReceive(store.$workspace) { _ in
            scheduleSnapshotRefresh()
        }
        .onDisappear {
            snapshotRefreshTask?.cancel()
            snapshotRefreshTask = nil
        }
    }

    private func makeSnapshot() -> SessionAuditPanelSnapshot {
        let currentTask = store.currentAnalysisTask(in: pack)
        let activeIDs = Set(currentTask?.activeReportIDs ?? [])
        let reportLimit = showAllReports ? 80 : 16
        let ranked = rankedReportPreview(
            activeIDs: activeIDs,
            selectedReportID: selectedReportID,
            hasCurrentTask: currentTask != nil,
            limit: reportLimit
        )
        let currentTaskReports = ranked.currentTaskReports
        let selectedReport = ranked.selectedReport
        let visibleReports = ranked.visibleReports
        let currentReport: ImportedReport?
        if let selectedReport {
            currentReport = selectedReport
        } else {
            currentReport = currentTaskReports.first ?? visibleReports.first
        }
        let auditStats = activeAuditStats(currentTaskReports: currentTaskReports)
        let reportDefinitions: [ReportFieldDefinition]
        if let currentReport {
            reportDefinitions = pack.fieldDefinitions.filter { $0.reportID == currentReport.id }
        } else {
            reportDefinitions = []
        }
        let query = fieldSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filteredDefinitions: [ReportFieldDefinition]
        if query.isEmpty {
            filteredDefinitions = reportDefinitions
        } else {
            filteredDefinitions = reportDefinitions.filter {
                "\($0.fieldName) \($0.meaning) \($0.notes)".lowercased().contains(query)
            }
        }
        let currentDefinition: ReportFieldDefinition?
        if let selectedDictionaryFieldID,
           let definition = reportDefinitions.first(where: { $0.id == selectedDictionaryFieldID }) {
            currentDefinition = definition
        } else {
            currentDefinition = reportDefinitions.first { !$0.isConfirmed } ?? reportDefinitions.first
        }
        return SessionAuditPanelSnapshot(
            currentTask: currentTask,
            currentTaskReports: currentTaskReports,
            visibleReports: visibleReports,
            hasMoreReports: pack.importedReports.count > visibleReports.count,
            currentReport: currentReport,
            activeReportCount: auditStats.activeReportCount,
            totalReportCount: pack.importedReports.count,
            unresolvedIssueCount: auditStats.unresolvedIssueCount,
            blockedIssueCount: auditStats.blockedIssueCount,
            acceptedRiskCount: auditStats.acceptedRiskCount,
            reportDefinitions: reportDefinitions,
            visibleDefinitions: Array(filteredDefinitions.prefix(query.isEmpty ? 50 : 80)),
            currentDefinition: currentDefinition,
            latestAssistantQAMessage: currentReport?.qaMessages.reversed().first { $0.role == .assistant }
        )
    }

    private func scheduleSnapshotRefresh(delayNanoseconds: UInt64 = 220_000_000) {
        snapshotRefreshTask?.cancel()
        snapshotRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            refreshSnapshot(force: false)
            snapshotRefreshTask = nil
        }
    }

    private func refreshSnapshot(force: Bool) {
        let revision = makeSnapshotRevision()
        guard force || revision != snapshotRevision else { return }
        snapshot = makeSnapshot()
        snapshotRevision = revision
    }

    private func makeSnapshotRevision() -> SessionAuditPanelRevision {
        SessionAuditPanelRevision(
            packID: pack.id,
            reportSignature: reportSignature(),
            fieldDefinitionSignature: fieldDefinitionSignature(),
            currentTaskSignature: currentTaskSignature(),
            selectedReportID: selectedReportID,
            selectedDictionaryFieldID: selectedDictionaryFieldID,
            fieldSearchText: fieldSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            showAllReports: showAllReports
        )
    }

    private func reportSignature() -> Int {
        var hasher = Hasher()
        for report in pack.importedReports {
            hasher.combine(report.id)
            hasher.combine(report.importedAt)
            hasher.combine(report.userReportAlias)
            hasher.combine(report.kind)
            hasher.combine(report.isIgnoredFromAnalysis)
            hasher.combine(report.auditSteps.count)
            hasher.combine(report.unresolvedAuditSteps.count)
            hasher.combine(report.blockingAuditSteps.count)
            hasher.combine(report.acceptedRiskAuditSteps.count)
            hasher.combine(report.understandingMessages.count)
            hasher.combine(report.qaMessages.count)
            hasher.combine(report.semanticProfile.summary)
        }
        return hasher.finalize()
    }

    private func fieldDefinitionSignature() -> Int {
        var hasher = Hasher()
        for definition in pack.fieldDefinitions {
            hasher.combine(definition.id)
            hasher.combine(definition.reportID)
            hasher.combine(definition.fieldName)
            hasher.combine(definition.meaning)
            hasher.combine(definition.notes)
            hasher.combine(definition.isConfirmed)
            hasher.combine(definition.updatedAt)
        }
        return hasher.finalize()
    }

    private func currentTaskSignature() -> Int {
        var hasher = Hasher()
        if let task = store.currentAnalysisTask(in: pack) {
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

    private func summarySection(_ snapshot: SessionAuditPanelSnapshot) -> some View {
        SectionCard(title: "审核摘要", systemImage: "checklist.checked") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                MetricTile(title: "报表", value: "\(snapshot.activeReportCount)/\(snapshot.totalReportCount)", systemImage: "tablecells")
                MetricTile(title: "待确认", value: "\(snapshot.unresolvedIssueCount)", systemImage: "exclamationmark.bubble")
                MetricTile(title: "阻塞", value: "\(snapshot.blockedIssueCount)", systemImage: "xmark.octagon")
                MetricTile(title: "已接受风险", value: "\(snapshot.acceptedRiskCount)", systemImage: "checkmark.circle.trianglebadge.exclamationmark")
            }
            Text("这里是会话侧栏的轻量审核视图，只展示当前任务相关问题。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reportListSection(_ snapshot: SessionAuditPanelSnapshot) -> some View {
        SectionCard(title: "报表列表", systemImage: "list.bullet.rectangle") {
            if snapshot.visibleReports.isEmpty {
                Text("当前分析资料还没有可用表。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.visibleReports) { report in
                    Button {
                        selectedReportID = report.id
                    } label: {
                        SessionAuditReportRow(
                            report: report,
                            isSelected: report.id == snapshot.currentReport?.id,
                            role: snapshot.currentTask?.role(for: report.id),
                            isInCurrentTask: snapshot.currentTask?.activeReportIDs.contains(report.id) == true
                        )
                    }
                    .buttonStyle(AppHoverButtonStyle(variant: .ghost))
                    Divider()
                }
                if snapshot.hasMoreReports {
                    Button(showAllReports ? "收起报表列表" : "显示更多报表") {
                        showAllReports.toggle()
                    }
                    .buttonStyle(AppHoverButtonStyle(variant: .link))
                    .font(.caption)
                }
            }
        }
    }

    private func selectedReportSection(_ report: ImportedReport, snapshot: SessionAuditPanelSnapshot) -> some View {
        SectionCard(title: "当前报表", systemImage: "doc.text.magnifyingglass") {
            VStack(alignment: .leading, spacing: 12) {
                reportHeader(report)
                requiredIssuesSection(report)
                lazyDisclosure("处理过程", systemImage: "clock.arrow.circlepath", isExpanded: $processingExpanded) {
                    ForEach(report.auditSteps) { step in
                        SessionAuditStepRow(reportID: report.id, step: step)
                        Divider()
                    }
                }
                lazyDisclosure("AI 数据覆盖", systemImage: "eye", isExpanded: $coverageExpanded) {
                    aiCoverageContent(report)
                }
                lazyDisclosure("表格含义", systemImage: "text.badge.checkmark", isExpanded: $semanticExpanded) {
                    semanticContent(report)
                }
                lazyDisclosure("字段与口径", systemImage: "character.book.closed", isExpanded: $fieldsExpanded) {
                    fieldContent(report, snapshot: snapshot)
                }
                lazyDisclosure("表格问答", systemImage: "bubble.left.and.text.bubble.right", isExpanded: $qaExpanded) {
                    qaContent(report, latestAssistantQAMessage: snapshot.latestAssistantQAMessage)
                }
            }
        }
    }

    private func reportHeader(_ report: ImportedReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(report.displayName)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(report.sourceFormat.label) · \(report.shape.label) · \(report.kind.label) · \(report.rowCount) 行 · \(report.headers.count) 列 · 首列指标 \(report.firstColumnValues.count) 个")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    store.ignoreReportFromAnalysis(reportID: report.id, ignored: !report.isIgnoredFromAnalysis)
                } label: {
                    SemanticLabel(title: report.isIgnoredFromAnalysis ? "恢复" : "忽略", systemImage: report.isIgnoredFromAnalysis ? "arrow.uturn.backward" : "nosign", role: report.isIgnoredFromAnalysis ? .data : .risk)
                }
                .controlSize(.small)
            }
            ResponsiveFormRow("显示名", labelWidth: 52) {
                AdaptiveTextField(placeholder: "可选：给这张表起一个更清楚的名称", text: Binding(
                    get: { report.userReportAlias },
                    set: { store.updateReportAlias(reportID: report.id, alias: $0) }
                ), minLines: 1, maxLines: 2)
            }
        }
    }

    private func requiredIssuesSection(_ report: ImportedReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SemanticLabel(title: "需要确认", systemImage: "exclamationmark.bubble", role: .risk)
                .font(.subheadline)
                .fontWeight(.semibold)
            let issues = report.unresolvedAuditSteps
            if issues.isEmpty {
                Text(report.isIgnoredFromAnalysis ? "该表已忽略，不进入分析。" : "没有必须处理的问题。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(issues) { step in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(step.warnings.first ?? step.kind.label)
                            .fontWeight(.medium)
                        Text(step.details)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        issueActions(report: report, step: step)
                    }
                    .padding(10)
                    .background((step.status == .blocked ? AppTheme.danger : AppTheme.warning).opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func issueActions(report: ImportedReport, step: ImportAuditStep) -> some View {
        ResponsiveStack(compactBreakpoint: 520, spacing: 8) {
            if step.kind == .typeDetection {
                Picker("修正类型", selection: Binding(
                    get: { report.kind },
                    set: { store.updateImportedReportKind(reportID: report.id, kind: $0) }
                )) {
                    ForEach(ImportedReportKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .frame(maxWidth: 180)
                .hoverControlShell(.pickerShell)
            }
            if step.kind == .reportSemantic {
                Button {
                    store.askReportUnderstandingQuestion(reportID: report.id)
                } label: {
                    SemanticLabel(title: "提问 AI", systemImage: "sparkles", role: .ai)
                }
                .disabled(store.isRunningReportUnderstandingAI)
            }
            if step.status == .needsConfirmation {
                Button {
                    store.acceptAuditRisk(reportID: report.id, stepID: step.id)
                } label: {
                    SemanticLabel(title: "接受风险", systemImage: "checkmark.circle", role: .success)
                }
            }
            Button {
                store.ignoreReportFromAnalysis(reportID: report.id)
            } label: {
                SemanticLabel(title: "忽略此表", systemImage: "nosign", role: .risk)
            }
        }
    }

    private func aiCoverageContent(_ report: ImportedReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let coverage = report.tableContextCoverage {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                    MetricTile(title: "行覆盖", value: "\(coverage.sentRows)/\(coverage.totalRows)", systemImage: "table.rows")
                    MetricTile(title: "列覆盖", value: "\(coverage.sentColumns)/\(coverage.totalColumns)", systemImage: "table.columns")
                    MetricTile(title: "指标覆盖", value: "\(coverage.sentMetrics)/\(coverage.totalMetrics)", systemImage: "chart.line.uptrend.xyaxis")
                }
                Text("\(coverage.omittedRowsDescription) \(coverage.omittedColumnsDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(coverage.limitations.prefix(4), id: \.self) { warning in
                    Text("• \(warning)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("尚未生成 AI 数据覆盖包。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func semanticContent(_ report: ImportedReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AdaptiveTextBox(text: $descriptionDraft, placeholder: "写清楚这张表的用途、口径、时间范围和注意事项。", minHeight: 84, maxHeight: 220)
            ResponsiveStack(compactBreakpoint: 520, spacing: 8) {
                Button {
                    store.updateReportSemanticDescription(descriptionDraft, reportID: report.id)
                } label: {
                    SemanticLabel(title: "保存含义", systemImage: "square.and.arrow.down", role: .knowledge)
                }
                .disabled(descriptionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button {
                    store.askReportUnderstandingQuestion(reportID: report.id)
                } label: {
                    SemanticLabel(title: store.isRunningReportUnderstandingAI ? "追问中" : "提问 AI", systemImage: "sparkles", role: .ai)
                }
                .disabled(store.isRunningReportUnderstandingAI)
                Button {
                    store.updateReportSemanticDescription(descriptionDraft, reportID: report.id)
                    store.confirmReportUnderstanding(reportID: report.id)
                } label: {
                    SemanticLabel(title: "确认口径", systemImage: "checkmark.seal", role: .success)
                }
                .disabled(report.semanticStatus == .confirmed)
            }
            if !report.semanticProfile.summary.isEmpty {
                Text(report.semanticProfile.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if !report.understandingMessages.isEmpty {
                ForEach(report.understandingMessages.suffix(4)) { message in
                    Text("\(message.role.label)：\(message.content)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func fieldContent(_ report: ImportedReport, snapshot: SessionAuditPanelSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AdaptiveTextField(placeholder: "搜索当前表字段", text: $fieldSearchText, minLines: 1, maxLines: 2)
            if let definition = snapshot.currentDefinition {
                VStack(alignment: .leading, spacing: 4) {
                    Text(definition.fieldName)
                        .fontWeight(.medium)
                    Text(definition.meaning.nilIfBlank ?? "暂未填写字段含义")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !definition.notes.isEmpty {
                        Text(definition.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                AdaptiveTextBox(text: $dictionaryAnswerText, placeholder: "补充这个字段的业务含义、统计口径、触发时机或注意事项。", minHeight: 72, maxHeight: 180)
                ResponsiveStack(compactBreakpoint: 520, spacing: 8) {
                    Button {
                        selectedDictionaryFieldID = definition.id
                        store.askFieldDictionaryQuestion(fieldID: definition.id)
                    } label: {
                        SemanticLabel(title: store.isRunningFieldDictionaryAI ? "提问中" : "让 AI 问字段", systemImage: "sparkles", role: .ai)
                    }
                    .disabled(store.isRunningFieldDictionaryAI)
                    Button {
                        let answer = dictionaryAnswerText
                        dictionaryAnswerText = ""
                        store.saveFieldDictionaryAnswer(answer, fieldID: definition.id)
                    } label: {
                        SemanticLabel(title: "保存解释", systemImage: "checkmark.seal", role: .success)
                    }
                    .disabled(dictionaryAnswerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if snapshot.visibleDefinitions.isEmpty {
                Text("没有匹配字段。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.visibleDefinitions) { definition in
                    Button {
                        selectedDictionaryFieldID = definition.id
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            SemanticIcon(systemName: definition.isConfirmed ? "checkmark.circle.fill" : "circle", role: definition.isConfirmed ? .success : .neutral, size: 13, frameWidth: 16)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(definition.fieldName)
                                    .fontWeight(.medium)
                                Text(definition.meaning.nilIfBlank ?? "未确认含义")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .buttonStyle(AppHoverButtonStyle(variant: .ghost))
                    Divider()
                }
                if snapshot.reportDefinitions.count > snapshot.visibleDefinitions.count {
                    Text("已显示前 \(snapshot.visibleDefinitions.count) 个字段，可搜索缩小范围。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func qaContent(_ report: ImportedReport, latestAssistantQAMessage: ReportQAMessage?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AdaptiveTextBox(text: $qaQuestionText, placeholder: "向 AI 询问这张表的趋势、口径、异常指标或需要补充的数据。", minHeight: 72, maxHeight: 180)
            ResponsiveStack(compactBreakpoint: 520, spacing: 8) {
                Button {
                    let question = qaQuestionText
                    qaQuestionText = ""
                    store.askReportQuestion(question, reportID: report.id)
                } label: {
                    SemanticLabel(title: store.isRunningReportQAI ? "回答中" : "提问这张表", systemImage: "sparkles", role: .ai)
                }
                .disabled(store.isRunningReportQAI || qaQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button {
                    store.adoptReportQAAsProfile(reportID: report.id, messageID: latestAssistantQAMessage?.id)
                } label: {
                    SemanticLabel(title: "更新表格含义", systemImage: "checkmark.seal", role: .success)
                }
                .disabled(latestAssistantQAMessage == nil)
                Button {
                    store.saveReportQAToKnowledge(reportID: report.id, messageID: latestAssistantQAMessage?.id)
                } label: {
                    SemanticLabel(title: "沉淀进知识库", systemImage: "books.vertical", role: .knowledge)
                }
                .disabled(latestAssistantQAMessage == nil)
            }
            ForEach(report.qaMessages.suffix(5)) { message in
                Text("\(message.role.label)：\(message.content)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func lazyDisclosure<Content: View>(
        _ title: String,
        systemImage: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            if isExpanded.wrappedValue {
                content()
                    .padding(.top, 6)
            }
        } label: {
            SemanticLabel(title: title, systemImage: systemImage, role: SemanticIconRole.inferred(from: systemImage))
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }

    private func ensureSelection() {
        let snapshot = makeSnapshot()
        if selectedReportID == nil || !pack.importedReports.contains(where: { $0.id == selectedReportID }) {
            selectedReportID = snapshot.currentTaskReports.first?.id ?? snapshot.visibleReports.first?.id
        }
        if descriptionDraft.isEmpty {
            descriptionDraft = snapshot.currentReport?.semanticProfile.summary ?? ""
        }
        if taskNameDraft.isEmpty {
            taskNameDraft = snapshot.currentTask?.name ?? ""
        }
        if taskGoalDraft.isEmpty {
            taskGoalDraft = snapshot.currentTask?.goal ?? ""
        }
    }

    private func reportSortScore(_ report: ImportedReport, activeIDs: Set<UUID>) -> Int {
        if activeIDs.contains(report.id) { return 1_000 }
        if report.isIgnoredFromAnalysis { return 0 }
        if !report.blockingAuditSteps.isEmpty { return 500 }
        if !report.unresolvedAuditSteps.isEmpty { return 400 }
        if !report.acceptedRiskAuditSteps.isEmpty { return 200 }
        return 100
    }

    private func rankedReportPreview(
        activeIDs: Set<UUID>,
        selectedReportID: UUID?,
        hasCurrentTask: Bool,
        limit: Int
    ) -> (visibleReports: [ImportedReport], currentTaskReports: [ImportedReport], selectedReport: ImportedReport?) {
        var ranked: [(report: ImportedReport, score: Int)] = []
        ranked.reserveCapacity(limit + 1)
        var currentTaskReports: [ImportedReport] = []
        var selectedReport: ImportedReport?

        for report in pack.importedReports {
            if hasCurrentTask, activeIDs.contains(report.id), !report.isIgnoredFromAnalysis {
                currentTaskReports.append(report)
            }
            if report.id == selectedReportID {
                selectedReport = report
            }
            insertRankedReport(
                (report: report, score: reportSortScore(report, activeIDs: activeIDs)),
                into: &ranked,
                limit: limit
            )
        }

        var visibleReports = ranked.map(\.report)
        if let selectedReport,
           !visibleReports.contains(where: { $0.id == selectedReport.id }) {
            visibleReports.append(selectedReport)
        }
        return (visibleReports, currentTaskReports, selectedReport)
    }

    private func insertRankedReport(
        _ candidate: (report: ImportedReport, score: Int),
        into ranked: inout [(report: ImportedReport, score: Int)],
        limit: Int
    ) {
        guard limit > 0 else { return }
        if ranked.count == limit,
           let last = ranked.last,
           !rankedReport(candidate, precedes: last) {
            return
        }

        if let index = ranked.firstIndex(where: { rankedReport(candidate, precedes: $0) }) {
            ranked.insert(candidate, at: index)
        } else {
            ranked.append(candidate)
        }
        if ranked.count > limit {
            ranked.removeLast()
        }
    }

    private func rankedReport(
        _ lhs: (report: ImportedReport, score: Int),
        precedes rhs: (report: ImportedReport, score: Int)
    ) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        return lhs.report.importedAt > rhs.report.importedAt
    }

    private func activeAuditStats(currentTaskReports: [ImportedReport]) -> (activeReportCount: Int, unresolvedIssueCount: Int, blockedIssueCount: Int, acceptedRiskCount: Int) {
        var activeReportCount = 0
        var unresolvedIssueCount = 0
        var blockedIssueCount = 0
        var acceptedRiskCount = 0

        let reports: [ImportedReport]
        if currentTaskReports.isEmpty {
            reports = pack.importedReports
        } else {
            reports = currentTaskReports
        }

        for report in reports where !report.isIgnoredFromAnalysis {
            activeReportCount += 1
            unresolvedIssueCount += report.unresolvedAuditSteps.count
            blockedIssueCount += report.blockingAuditSteps.count
            acceptedRiskCount += report.acceptedRiskAuditSteps.count
        }
        return (activeReportCount, unresolvedIssueCount, blockedIssueCount, acceptedRiskCount)
    }
}

struct SessionAuditReportRow: View {
    var report: ImportedReport
    var isSelected: Bool
    var role: AnalysisTaskReportRole?
    var isInCurrentTask: Bool

    private var status: ImportAuditStepStatus {
        if report.isIgnoredFromAnalysis { return .acceptedRisk }
        if !report.blockingAuditSteps.isEmpty { return .blocked }
        if !report.unresolvedAuditSteps.isEmpty { return .needsConfirmation }
        if !report.acceptedRiskAuditSteps.isEmpty { return .acceptedRisk }
        return .completed
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            SemanticIcon(systemName: isSelected ? "checkmark.circle.fill" : "tablecells", role: isSelected ? .success : .data, size: 15, frameWidth: 18)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(report.displayName)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(report.sourceFormat.label) · \(report.shape.label) · \(report.kind.label) · 问题 \(report.unresolvedAuditSteps.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    Badge(text: status.label, systemImage: nil, tint: statusColor)
                    if isInCurrentTask {
                        Badge(text: role?.label ?? "当前任务", systemImage: nil, tint: AppTheme.success)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch status {
        case .completed: return AppTheme.success
        case .needsConfirmation: return AppTheme.warning
        case .acceptedRisk: return AppTheme.accent
        case .blocked: return AppTheme.danger
        }
    }
}

struct SessionAuditStepRow: View {
    var reportID: UUID
    var step: ImportAuditStep

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            SemanticIcon(systemName: statusIcon, color: statusColor, size: 15, frameWidth: 18)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(step.kind.label)
                        .fontWeight(.medium)
                    Badge(text: step.status.label, systemImage: nil, tint: statusColor)
                }
                Text("置信度 \(Int((step.confidence ?? 0) * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(step.details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(step.warnings.prefix(3), id: \.self) { warning in
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(AppTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch step.status {
        case .completed: return AppTheme.success
        case .needsConfirmation: return AppTheme.warning
        case .acceptedRisk: return AppTheme.accent
        case .blocked: return AppTheme.danger
        }
    }

    private var statusIcon: String {
        switch step.status {
        case .completed: return "checkmark.circle"
        case .needsConfirmation: return "exclamationmark.circle"
        case .acceptedRisk: return "checkmark.circle.trianglebadge.exclamationmark"
        case .blocked: return "xmark.octagon"
        }
    }
}
