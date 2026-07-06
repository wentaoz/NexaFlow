import SwiftUI

struct DataPacksView: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    @State private var fieldSearchText = ""
    @State private var selectedDictionaryFieldID: UUID?
    @State private var dictionaryAnswerText = ""
    @State private var selectedUnderstandingReportID: UUID?
    @State private var selectedAuditReportID: UUID?
    @State private var reportDescriptionDraft = ""
    @State private var reportUnderstandingAnswerText = ""
    @State private var reportQAQuestionText = ""
    @State private var taskNameDraft = ""
    @State private var taskGoalDraft = ""
    @State private var showFullAuditDesk = false
    @State private var isConfirmingDeleteSelectedPack = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                SectionCard(title: "数据包高级管理", systemImage: "folder.badge.gearshape") {
                    Text("这里是数据包高级管理页，只负责导入、选择、删除和恢复数据包。选表、审核、质检、AI 对话和报告生成请在“分析会话”完成。")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button {
                            store.showImportSourceChoice()
                        } label: {
                            Label("导入", systemImage: "tray.and.arrow.down")
                        }
                        .accessibilityLabel("导入")
                        .disabled(store.isImportingData)
                        Button {
                            store.importReportsIntoSelectedPack()
                        } label: {
                            Label("追加报表文件", systemImage: "doc.badge.plus")
                        }
                        .accessibilityLabel("追加报表文件")
                        .disabled(store.selectedPack == nil || store.isImportingData)
                        Button {
                            store.showTableauImportSheet()
                        } label: {
                            Label("从 Tableau 导入", systemImage: "chart.bar.doc.horizontal")
                        }
                        .accessibilityLabel("从 Tableau 导入")
                        .disabled(store.isImportingData)
                        Button("恢复示例数据") {
                            store.resetToSampleData()
                        }
                        .accessibilityLabel("恢复示例数据")
                        .disabled(store.isImportingData)
                        Spacer()
                        Button {
                            store.requestAnalysisSessionNavigation()
                        } label: {
                            Label("进入分析会话", systemImage: "bubble.left.and.text.bubble.right")
                        }
                    }
                }

                SectionCard(title: "已导入数据包", systemImage: "tray.full") {
                    let currentSpacePacks = store.packsForSelectedBusinessSpace
                    if currentSpacePacks.isEmpty {
                        Text("当前业务空间还没有数据包，请导入表格。")
                            .foregroundStyle(.secondary)
                    } else {
                        if let space = store.selectedBusinessSpace {
                            Text("当前业务空间：\(space.name)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(currentSpacePacks) { pack in
                            DataPackRow(pack: pack, isSelected: store.selectedPack?.id == pack.id)
                                .contentShape(Rectangle())
                                .onTapGesture { store.select(pack: pack) }
                            Divider()
                        }
                        Button(role: .destructive) {
                            isConfirmingDeleteSelectedPack = true
                        } label: {
                            Label("删除当前数据包", systemImage: "trash")
                        }
                        .disabled(store.selectedPack == nil)
                    }
                }

                if !store.unboundDataPacks.isEmpty {
                    SectionCard(title: "未绑定业务空间的数据包", systemImage: "link.badge.plus") {
                        Text("这些是旧 workspace 或历史导入留下的未绑定数据。默认不会混入当前业务空间；需要继续使用时，可以绑定到当前业务空间。")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(store.unboundDataPacks) { pack in
                            HStack(alignment: .top, spacing: 12) {
                                DataPackRow(pack: pack, isSelected: false)
                                Spacer()
                                Button {
                                    store.bindDataPackToCurrentBusinessSpace(pack)
                                } label: {
                                    Label("绑定到当前空间", systemImage: "link")
                                }
                                .disabled(store.selectedBusinessSpace == nil)
                            }
                            Divider()
                        }
                    }
                }

                if let pack = store.selectedPack {
                    SectionCard(title: "下一步", systemImage: "arrow.right.circle") {
                        Text("\(pack.importedReports.count) 张报表已保存在当前数据包。请进入“分析会话”选择本次要联动分析的表、填写目标，并和 AI 对话生成分析与机会评分。")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            store.requestAnalysisSessionNavigation()
                        } label: {
                            Label("去分析会话", systemImage: "sparkles")
                        }
                    }

                    SectionCard(title: "完整导入审核台（高级）", systemImage: "checklist.checked") {
                        DisclosureGroup("展开完整审核台", isExpanded: $showFullAuditDesk) {
                            if showFullAuditDesk {
                                ImportAuditDesk(
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
                            }
                        }
                        Text("默认不展开完整审核台，避免进入数据包管理时一次性渲染所有报表、字段和审核步骤。普通选表和口径确认建议在“分析会话 > 分析资料”完成。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(18)
        }
        .confirmationDialog(
            "删除当前数据包？",
            isPresented: $isConfirmingDeleteSelectedPack,
            titleVisibility: .visible
        ) {
            Button("删除当前数据包", role: .destructive) {
                store.deleteSelectedPack()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后，该数据包内的报表、字段审核状态和关联会话引用会被移除。")
        }
    }

    private func filteredDefinitions(in pack: DataPack) -> [ReportFieldDefinition] {
        let query = fieldSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return pack.fieldDefinitions }
        return pack.fieldDefinitions.filter { definition in
            [
                definition.reportName,
                definition.reportKind.label,
                definition.fieldName,
                definition.meaning,
                definition.notes
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }
}

struct ImportAuditDesk: View {
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
    @State private var showAllReportPool = false

    private func makeSnapshot() -> ImportAuditDeskSnapshot {
        let currentTask = store.currentAnalysisTask(in: pack)
        let currentTaskReportIDs = Set(currentTask?.selectedReportIDs ?? [])
        let activeReportIDs = Set(currentTask?.activeReportIDs ?? [])
        var currentTaskReports: [ImportedReport] = []
        var activeReports: [ImportedReport] = []
        var reportPool: [ImportedReport] = []
        var reportByID: [UUID: ImportedReport] = [:]
        var reportDisplayNamesByID: [UUID: String] = [:]
        var unresolvedAuditStepCount = 0
        var confirmedReportCount = 0
        var readyReportCount = 0
        var acceptableRiskCount = 0

        for report in pack.importedReports {
            reportByID[report.id] = report
            reportDisplayNamesByID[report.id] = report.displayName
            if !currentTaskReportIDs.contains(report.id) {
                reportPool.append(report)
            }
            guard !report.isIgnoredFromAnalysis else { continue }
            if currentTaskReportIDs.contains(report.id) {
                currentTaskReports.append(report)
            }
            if activeReportIDs.contains(report.id) {
                activeReports.append(report)
                unresolvedAuditStepCount += report.unresolvedAuditSteps.count
                if report.unresolvedAuditSteps.isEmpty {
                    confirmedReportCount += 1
                }
                if report.canEnterAnalysis {
                    readyReportCount += 1
                }
                acceptableRiskCount += report.auditSteps.lazy.filter { $0.status == .needsConfirmation }.count
            }
        }

        let sortedReports = pack.importedReports.sorted { lhs, rhs in
            let lhsScore = reportSortScore(lhs)
            let rhsScore = reportSortScore(rhs)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return lhs.importedAt > rhs.importedAt
        }
        let sortedTaskReports = currentTaskReports.sorted { reportSortScore($0) > reportSortScore($1) }
        let sortedPoolReports = sortedReportPool(reportPool, showAll: showAllReportPool, limit: 80)
        let selectedReport = selectedReportID.flatMap { reportByID[$0] }
        let currentReport: ImportedReport?
        if let selectedReport,
           currentTaskReportIDs.isEmpty || currentTaskReportIDs.contains(selectedReport.id) {
            currentReport = selectedReport
        } else {
            currentReport = currentTaskReports.first ?? sortedReports.first
        }

        let relationshipIssueCount = activeReports.count > 1 && currentTask?.businessLinkProfile.confirmationStatus != .confirmed ? 1 : 0
        let aiObservation = aiObservationState(task: currentTask, activeReports: activeReports)
        let activeMetricLinks = currentTask?.businessLinkProfile.metricLinks.filter { $0.confirmationStatus != .rejected } ?? []
        return ImportAuditDeskSnapshot(
            currentTask: currentTask,
            currentTaskReportIDs: currentTaskReportIDs,
            currentTaskReports: currentTaskReports,
            sortedTaskReports: sortedTaskReports,
            reportPool: reportPool,
            sortedPoolReports: sortedPoolReports,
            activeReports: activeReports,
            sortedReports: sortedReports,
            currentReport: currentReport,
            reportDisplayNamesByID: reportDisplayNamesByID,
            unresolvedIssueCount: unresolvedAuditStepCount + relationshipIssueCount,
            relationshipIssueCount: relationshipIssueCount,
            confirmedReportCount: confirmedReportCount,
            readyReportCount: readyReportCount,
            acceptableRiskCount: acceptableRiskCount,
            importReviewBlockerText: importReviewBlockerText(currentTask: currentTask, activeReports: activeReports),
            aiObservationWarningText: aiObservation.warningText,
            aiObservationStatusText: aiObservation.statusText,
            activeMetricLinks: activeMetricLinks,
            recommendedTemplates: store.recommendedAnalysisTemplates(for: pack),
            hasAvailableTemplates: store.workspace.analysisTemplateMemories.contains { !$0.isArchived }
        )
    }

    private func importReviewBlockerText(currentTask: AnalysisTask?, activeReports: [ImportedReport]) -> String? {
        guard let currentTask else {
            return "当前分析资料还没有分析任务，请先创建或选择一个分析任务。"
        }
        if activeReports.isEmpty && !pack.importedReports.isEmpty {
            return "当前分析任务还没有选择表。请在分析资料中加入本次要联动分析的表。"
        }
        let blockedSteps = activeReports.flatMap(\.blockingAuditSteps)
        if !blockedSteps.isEmpty {
            let reasons = blockedSteps.flatMap(\.warnings).prefix(3).joined(separator: "；")
            return "\(blockedSteps.count) 个问题无法进入分析\(reasons.isEmpty ? "" : "：\(reasons)")。请修正或忽略对应报表。"
        }
        let unresolvedSteps = activeReports.flatMap(\.unresolvedAuditSteps)
        if !unresolvedSteps.isEmpty {
            let reasons = unresolvedSteps.flatMap(\.warnings).prefix(3).joined(separator: "；")
            return "\(unresolvedSteps.count) 个问题需要确认\(reasons.isEmpty ? "" : "：\(reasons)")。可以修正类型、确认口径、提问 AI 或接受低风险。"
        }
        if activeReports.count > 1 && currentTask.businessLinkProfile.confirmationStatus != .confirmed {
            return "当前任务的业务链路尚未确认。请确认主业务、影响来源、结果指标和上下游关系后再进入分析。"
        }
        return nil
    }

    private func aiObservationState(task: AnalysisTask?, activeReports: [ImportedReport]) -> (statusText: String, warningText: String?) {
        guard let task else { return ("无分析任务", nil) }
        guard !activeReports.isEmpty else { return ("未选择报表", nil) }
        let isCurrent = currentTaskAIObservationIsCurrent(task: task, activeReports: activeReports)
        if isCurrent {
            return ("已生成", nil)
        }
        if task.aiObservationGeneratedAt != nil {
            return ("需要更新", "AI 预读需要更新。当前任务的报表、角色或本次分析目标已变化；可以直接发送给 AI 分析，或重新生成预读。")
        }
        return ("未生成", "AI 预读尚未生成。可以直接发送给 AI 分析；如需先让 AI 预读表格，请点击“生成 AI 预读”。")
    }

    private func currentTaskAIObservationIsCurrent(task: AnalysisTask, activeReports: [ImportedReport]) -> Bool {
        guard !activeReports.isEmpty,
              let generatedAt = task.aiObservationGeneratedAt,
              task.aiObservationSignature == store.aiObservationSignature(for: task, reports: activeReports) else {
            return false
        }
        return activeReports.allSatisfy { report in
            guard let analysis = report.aiFirstAnalysis else { return false }
            return analysis.generatedAt >= generatedAt.addingTimeInterval(-1)
        }
    }

    var body: some View {
        SectionCard(title: "导入审核台", systemImage: "checklist.checked") {
            let snapshot = makeSnapshot()
            if pack.importedReports.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    auditWorkflowPanel(snapshot)
                    auditActions(snapshot)
                    Text("当前数据包还没有报表。可以点击“追加报表”导入 CSV、XLSX 或 XLS；如只使用知识库和外部参照，也可以按当前目标生成分析。")
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    auditWorkflowPanel(snapshot)
                    auditHeader(snapshot)
                    taskPanel(snapshot)
                    auditContentLayout(snapshot)
                    businessLinkPanel(snapshot)
                    aiObservationPanel(snapshot)
                    auditActions(snapshot)
                }
                .onAppear(perform: ensureSelection)
                .onChange(of: pack.id) { _ in
                    selectedReportID = nil
                    selectedDictionaryFieldID = nil
                    descriptionDraft = ""
                    answerText = ""
                    qaQuestionText = ""
                    dictionaryAnswerText = ""
                    taskNameDraft = store.currentAnalysisTask(in: pack)?.name ?? ""
                    taskGoalDraft = store.currentAnalysisTask(in: pack)?.goal ?? ""
                    showAllReportPool = false
                    ensureSelection()
                }
                .onChange(of: pack.selectedAnalysisTaskID) { _ in
                    let snapshot = makeSnapshot()
                    taskNameDraft = snapshot.currentTask?.name ?? ""
                    taskGoalDraft = snapshot.currentTask?.goal ?? ""
                    selectedReportID = snapshot.currentTaskReports.first?.id ?? snapshot.sortedReports.first?.id
                    descriptionDraft = snapshot.currentReport?.semanticProfile.summary ?? ""
                    showAllReportPool = false
                }
                .onChange(of: selectedReportID) { _ in
                    descriptionDraft = makeSnapshot().currentReport?.semanticProfile.summary ?? ""
                    answerText = ""
                    qaQuestionText = ""
                    dictionaryAnswerText = ""
                }
                .onDisappear {
                    store.commitFieldDefinitionEdits()
                }
            }
        }
    }

    private func auditHeader(_ snapshot: ImportAuditDeskSnapshot) -> some View {
        ResponsiveStack(compactBreakpoint: 720, spacing: 10) {
            MetricTile(title: "待处理问题", value: "\(snapshot.unresolvedIssueCount)", systemImage: "exclamationmark.triangle")
            MetricTile(title: "可进入分析的表", value: "\(snapshot.readyReportCount)", systemImage: "checkmark.circle")
            MetricTile(title: "已确认表", value: "\(snapshot.confirmedReportCount)", systemImage: "checkmark.seal")
        }
    }

    private func auditWorkflowPanel(_ snapshot: ImportAuditDeskSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let action = nextWorkflowAction(snapshot)
            HStack {
                Label("当前流程", systemImage: "list.number")
                    .font(.headline)
                Spacer()
                Badge(text: action.title, systemImage: action.systemImage, tint: action.tint)
            }
            ActionHintBox(
                title: "现在请做",
                message: nextWorkflowInstruction(snapshot),
                systemImage: action.systemImage ?? "arrow.right.circle",
                tint: action.tint
            )
            ResponsiveStack(compactBreakpoint: 860, spacing: 8, horizontalAlignment: .top) {
                ForEach(workflowSteps(snapshot)) { step in
                    WorkflowStepChip(step: step)
                }
            }
        }
        .padding(10)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    private func workflowSteps(_ snapshot: ImportAuditDeskSnapshot) -> [AuditWorkflowStep] {
        [
            AuditWorkflowStep(
                number: 1,
                title: "选报表",
                detail: snapshot.currentTaskReports.isEmpty ? "从未加入列表选择" : "\(snapshot.currentTaskReports.count) 张",
                state: snapshot.currentTaskReports.isEmpty ? .current : .done
            ),
            AuditWorkflowStep(
                number: 2,
                title: "写目标",
                detail: snapshot.taskGoalIsEmpty ? "建议补充" : "已填写",
                state: snapshot.currentTaskReports.isEmpty ? .pending : (snapshot.taskGoalIsEmpty ? .current : .done)
            ),
            AuditWorkflowStep(
                number: 3,
                title: "校准链路",
                detail: snapshot.relationshipReady ? "已确认" : "待确认",
                state: snapshot.currentTaskReports.isEmpty ? .pending : (snapshot.relationshipReady ? .done : .current)
            ),
            AuditWorkflowStep(
                number: 4,
                title: "生成分析",
                detail: pack.analysisGateStatus.label,
                state: pack.analysisGateStatus == .analyzed ? .done : .pending
            )
        ]
    }

    private func nextWorkflowAction(_ snapshot: ImportAuditDeskSnapshot) -> (title: String, systemImage: String?, tint: Color) {
        if snapshot.currentTaskReports.isEmpty {
            return ("先选报表", "tablecells", AppTheme.warning)
        }
        if snapshot.taskGoalIsEmpty {
            return ("补充目标", "text.cursor", AppTheme.warning)
        }
        if !snapshot.relationshipReady {
            return ("确认链路", "point.3.connected.trianglepath.dotted", AppTheme.warning)
        }
        if snapshot.importReviewBlockerText != nil {
            return ("处理问题", "exclamationmark.triangle", AppTheme.warning)
        }
        return ("生成分析", "play.circle", AppTheme.success)
    }

    private func nextWorkflowInstruction(_ snapshot: ImportAuditDeskSnapshot) -> String {
        if snapshot.currentTaskReports.isEmpty {
            return "从“未加入当前任务”列表里点“加入当前任务”。只加入本次要联动分析的业务表，不要把无关任务的表放进来。"
        }
        if snapshot.taskGoalIsEmpty {
            return "在“本次分析目标”里写清楚要回答的问题。也可以写“按上次一样的指标分析”，然后点击“套用最佳模板”。"
        }
        if !snapshot.relationshipReady {
            return "检查“业务链路影响图”。确认主业务表、上下游关系和指标联动后，点击“确认链路”。"
        }
        if let blocker = snapshot.importReviewBlockerText {
            return blocker
        }
        return "点击“按当前目标生成分析”。报告会按当前任务的表、目标和外部参照生成；AI 预读只是可选辅助。"
    }

    private func auditActions(_ snapshot: ImportAuditDeskSnapshot) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                auditActionButtons(snapshot)
                Spacer()
                Badge(text: pack.analysisGateStatus.label, systemImage: nil, tint: pack.analysisGateStatus == .analyzed ? AppTheme.success : AppTheme.warning)
            }
            VStack(alignment: .leading, spacing: 8) {
                auditActionButtons(snapshot)
                Badge(text: pack.analysisGateStatus.label, systemImage: nil, tint: pack.analysisGateStatus == .analyzed ? AppTheme.success : AppTheme.warning)
            }
        }
    }

    @ViewBuilder
    private func auditActionButtons(_ snapshot: ImportAuditDeskSnapshot) -> some View {
        Button {
            store.confirmSelectedPackForAnalysis()
        } label: {
            Label("按当前目标生成分析", systemImage: "play.circle")
        }
        .disabled(snapshot.importReviewBlockerText != nil)
        if snapshot.aiObservationWarningText != nil {
            Button {
                store.confirmSelectedPackForAnalysis(skipAIObservationWarning: true)
            } label: {
                Label("跳过观察直接分析", systemImage: "forward.circle")
            }
            .disabled(snapshot.importReviewBlockerText != nil)
        }
        Button {
            store.saveSelectedPackWithoutAnalysis()
        } label: {
            Label("仅保存，不分析", systemImage: "tray")
        }
        if snapshot.acceptableRiskCount > 0 {
            Button {
                store.acceptAllImportReviewRisks()
            } label: {
                Label("接受全部低风险", systemImage: "checkmark.circle")
            }
        }
        Button {
            selectFirstIssue()
        } label: {
            Label("逐张校准", systemImage: "slider.horizontal.3")
        }
    }

    @ViewBuilder
    private func taskPanel(_ snapshot: ImportAuditDeskSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    taskTitle
                    Spacer()
                    taskPicker(snapshot)
                    newTaskButton
                    saveTaskButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    taskTitle
                    HStack(spacing: 8) {
                        taskPicker(snapshot)
                        newTaskButton
                        saveTaskButton
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("任务名称")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                AdaptiveTextField(placeholder: "任务名称", text: Binding(
                    get: { snapshot.currentTask?.name ?? "" },
                    set: {
                        taskNameDraft = $0
                        store.updateSelectedAnalysisTask(name: $0, goal: nil)
                    }
                ), minLines: 1, maxLines: 3)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("本次分析目标")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                AdaptiveTextBox(
                    text: Binding(
                        get: { snapshot.currentTask?.goal ?? "" },
                        set: {
                            taskGoalDraft = $0
                            store.updateSelectedAnalysisTask(name: nil, goal: $0)
                        }
                    ),
                    placeholder: "例如：分析 2026/05/11-2026/05/17 相比上一完整周期的注册转化变化，并判断页面埋点、短信/KYC、授信、电费缴费之间是否有关联。",
                    minHeight: 118,
                    maxHeight: 300
                )
            }

            analysisTemplatePanel(snapshot)

            let selectedCount = snapshot.currentTaskReports.count
            let poolCount = snapshot.reportPool.count
            Text("当前任务已选择 \(selectedCount) 张表，未加入当前任务 \(poolCount) 张。每个任务只分析自己选择的表，同一张表可以加入多个任务。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .onAppear {
            taskNameDraft = snapshot.currentTask?.name ?? ""
            taskGoalDraft = snapshot.currentTask?.goal ?? ""
        }
    }

    private var taskTitle: some View {
        Label("分析任务", systemImage: "square.stack.3d.up")
            .font(.headline)
    }

    private func taskPicker(_ snapshot: ImportAuditDeskSnapshot) -> some View {
        Picker("当前任务", selection: Binding(
            get: { snapshot.currentTask?.id ?? pack.analysisTasks.first?.id ?? UUID() },
            set: { store.selectAnalysisTask(taskID: $0) }
        )) {
            ForEach(pack.analysisTasks) { task in
                Text(task.name).tag(task.id)
            }
        }
        .labelsHidden()
        .hoverControlShell(.pickerShell)
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)
    }

    private var newTaskButton: some View {
        Button {
            store.createAnalysisTask()
        } label: {
            Label("新建任务", systemImage: "plus")
        }
    }

    private var saveTaskButton: some View {
        Button {
            store.saveSelectedAnalysisTask(name: taskNameDraft, goal: taskGoalDraft)
        } label: {
            Label("保存任务", systemImage: "square.and.arrow.down")
        }
    }

    private func analysisTemplatePanel(_ snapshot: ImportAuditDeskSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    templateTitle
                    Spacer()
                    templateButtons(snapshot)
                }
                VStack(alignment: .leading, spacing: 8) {
                    templateTitle
                    templateButtons(snapshot)
                }
            }

            if snapshot.recommendedTemplates.isEmpty {
                Text("还没有可匹配模板。完成一次分析任务后点“保存为模板”，下次导入相似报表就能直接沿用指标、表角色和分析目标。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(snapshot.recommendedTemplates.prefix(3)) { template in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(template.name)
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text("\(template.reportRules.count) 张表规则 · 已套用 \(template.useCount) 次 · 来源：\(template.sourceTaskName.nilIfBlank ?? template.sourcePackName)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("套用") {
                            store.applyAnalysisTemplate(templateID: template.id)
                        }
                        .buttonStyle(AppHoverButtonStyle(variant: .ghost))
                    }
                    .padding(8)
                    .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(10)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    private var templateTitle: some View {
        Label("分析模板记忆", systemImage: "bookmark")
            .font(.subheadline)
            .fontWeight(.medium)
    }

    @ViewBuilder
    private func templateButtons(_ snapshot: ImportAuditDeskSnapshot) -> some View {
        HStack(spacing: 8) {
            Button {
                store.applyBestAnalysisTemplateToSelectedTask()
            } label: {
                Label("套用最佳模板", systemImage: "wand.and.stars")
            }
            .disabled(!snapshot.hasAvailableTemplates)
            Button {
                store.saveSelectedAnalysisTaskAsTemplate()
            } label: {
                Label("保存为模板", systemImage: "bookmark.fill")
            }
            .disabled(snapshot.currentTaskReports.isEmpty)
        }
    }

    private func aiObservationActions(_ snapshot: ImportAuditDeskSnapshot) -> some View {
        Button {
            store.generateAIObservationForSelectedTask()
        } label: {
            Label("生成 AI 预读", systemImage: "sparkles")
        }
        .disabled(snapshot.currentTaskReports.isEmpty || store.isRunningAIFirstAnalysis || !store.hasConfiguredAI)
        .help("可选：先让 AI 预读当前任务已选择的报表，不会分析整个 Data Pack。")
    }

    private func aiObservationStatusBadge(_ snapshot: ImportAuditDeskSnapshot) -> some View {
        let status = snapshot.aiObservationStatusText
        let tint: Color = switch status {
        case "已生成": AppTheme.success
        case "需要更新": AppTheme.warning
        case "未生成": .secondary
        default: .secondary
        }
        return Badge(text: "AI 预读：\(status)", systemImage: nil, tint: tint)
    }

    @ViewBuilder
    private func aiObservationPanel(_ snapshot: ImportAuditDeskSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("AI 预读（可选）", systemImage: "sparkles")
                    .font(.headline)
                aiObservationStatusBadge(snapshot)
                Spacer()
                aiObservationActions(snapshot)
            }

            if snapshot.currentTaskReports.isEmpty {
                    Text("第 1 步还没完成：请先从“未加入当前任务”里把本次要分析的表加入任务。加入后可以选择是否先让 AI 预读。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if let warning = snapshot.aiObservationWarningText {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(AppTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(snapshot.currentTaskReports.prefix(8)) { report in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(report.displayName)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Spacer()
                            Badge(text: report.aiFirstAnalysis == nil ? "未观察" : "已观察", systemImage: nil, tint: report.aiFirstAnalysis == nil ? .secondary : AppTheme.success)
                        }
                        Text("\(report.sourceFormat.label) · \(report.shape.label) · \(report.kind.label) · \(report.rowCount) 行 · \(report.headers.count) 列 · 首列指标 \(report.firstColumnValues.count) 个")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if let coverage = report.tableContextCoverage {
                            Text("覆盖：\(coverage.summary)。\(coverage.omittedRowsDescription)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let analysis = report.aiFirstAnalysis {
                            Text(analysis.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                            ForEach(analysis.primaryComparison.prefix(3), id: \.self) { item in
                                Text("• \(item)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            ForEach(analysis.anomalies.prefix(3), id: \.self) { item in
                                Text("• \(item)")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.warning)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            Text("等待你点击“生成 AI 预读”。这是可选步骤；也可以直接回到分析会话发送给 AI。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                }

                if snapshot.currentTaskReports.count > 8 {
                    Text("还有 \(snapshot.currentTaskReports.count - 8) 张任务报表未在此处展开。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    @ViewBuilder
    private func businessLinkPanel(_ snapshot: ImportAuditDeskSnapshot) -> some View {
        if let task = snapshot.currentTask, snapshot.activeReports.count > 1 {
            let profile = task.businessLinkProfile
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("业务链路影响图", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.headline)
                    Badge(
                        text: profile.confirmationStatus.label,
                        systemImage: nil,
                        tint: profile.confirmationStatus == .confirmed ? AppTheme.success : AppTheme.warning
                    )
                    Spacer()
                    Menu("设置主业务表") {
                        ForEach(snapshot.activeReports) { report in
                            Button(report.displayName) {
                                store.setPrimaryReport(reportID: report.id)
                            }
                        }
                    }
                    .hoverControlShell(.pickerShell)
                    Button {
                        store.refreshSelectedTaskBusinessLinks()
                    } label: {
                        Label("重新识别", systemImage: "sparkles")
                    }
                    Button {
                        store.confirmSelectedTaskBusinessLinks()
                    } label: {
                        Label("确认链路", systemImage: "checkmark.seal")
                    }
                }

                Text(profile.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                KeyValueRow(key: "主业务", value: task.relationshipProfile.primaryReportID.flatMap { snapshot.displayName(for: $0) } ?? "未确认")
                KeyValueRow(key: "周期", value: task.relationshipProfile.periodConsistency)
                KeyValueRow(key: "人群/渠道", value: "\(task.relationshipProfile.audienceConsistency)；\(task.relationshipProfile.channelConsistency)")

                ForEach(profile.edges.prefix(8)) { edge in
                    let sourceName = snapshot.displayName(for: edge.sourceReportID) ?? "上游表"
                    let targetName = snapshot.displayName(for: edge.targetReportID) ?? "下游表"
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(sourceName) → \(targetName)")
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Spacer()
                            Badge(text: "\(Int(edge.confidence * 100))%", systemImage: nil, tint: edge.confidence >= 0.72 ? AppTheme.success : AppTheme.warning)
                        }
                        Text("\(edge.relationType)：\(edge.hypothesis)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                }

                if !profile.metricLinks.isEmpty {
                    Divider()
                    HStack {
                        Label("指标级多表联动", systemImage: "arrow.triangle.branch")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                    Text("\(snapshot.activeMetricLinks.count) 条候选")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(snapshot.activeMetricLinks.prefix(10)) { link in
                        let sourceName = snapshot.displayName(for: link.sourceReportID) ?? "上游表"
                        let targetName = snapshot.displayName(for: link.targetReportID) ?? "下游表"
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(sourceName).\(link.sourceMetric) → \(targetName).\(link.targetMetric)")
                                    .fontWeight(.medium)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Badge(text: link.relationType.label, systemImage: nil, tint: link.relationType == .pageBehaviorImpact ? AppTheme.accent : AppTheme.info)
                                Badge(text: "证据\(link.evidenceLevel.rawValue)", systemImage: nil, tint: link.evidenceLevel == .b ? AppTheme.success : AppTheme.warning)
                            }
                            Text("\(link.directionAlignment)，置信度 \(Int(link.confidence * 100))%。\(link.evidence.prefix(2).joined(separator: "；"))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack {
                                Button("确认") {
                                    store.updateSelectedTaskMetricLink(linkID: link.id, status: .confirmed)
                                }
                                .disabled(link.confirmationStatus == .confirmed)
                            Button("排除") {
                                store.updateSelectedTaskMetricLink(linkID: link.id, status: .rejected)
                            }
                        }
                        .buttonStyle(AppHoverButtonStyle(variant: .ghost))
                        }
                        .padding(8)
                        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    }
                } else {
                    Text("暂未发现可靠的指标级联动。若要分析页面埋点对业务功能的影响，请把相关埋点表和业务结果表加入同一分析任务。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
    }

    private func reportList(_ snapshot: ImportAuditDeskSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当前任务报表")
                .font(.headline)
            let taskReports = snapshot.currentTaskReports
            let selectedReport = snapshot.currentReport
            if taskReports.isEmpty {
                Text("第 1 步：从下面“未加入当前任务”的列表中，点击“加入当前任务”。只选本次要一起分析的表。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.sortedTaskReports) { report in
                    ReportAuditListRow(
                        report: report,
                        isSelected: selectedReport?.id == report.id,
                        role: snapshot.currentTask?.role(for: report.id)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedReportID = report.id
                        descriptionDraft = report.semanticProfile.summary
                    }
                    ReportTaskRoleControls(report: report, role: snapshot.currentTask?.role(for: report.id) ?? .evidence)
                    Divider()
                }
            }

            if !snapshot.sortedPoolReports.isEmpty {
                Text("未加入当前任务")
                    .font(.headline)
                    .padding(.top, 6)
                Text("这些表已导入，但不会参与当前任务分析。需要联动分析哪张，就点它下面的“加入当前任务”。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(snapshot.sortedPoolReports) { report in
                    ReportAuditListRow(
                        report: report,
                        isSelected: selectedReport?.id == report.id,
                        role: nil
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedReportID = report.id
                        descriptionDraft = report.semanticProfile.summary
                    }
                    Button {
                        store.addReportToSelectedTask(reportID: report.id, role: taskReports.isEmpty ? .primaryBusiness : .evidence)
                    } label: {
                        Label("加入当前任务", systemImage: "plus.circle")
                    }
                    .buttonStyle(AppHoverButtonStyle(variant: .link))
                    Divider()
                }
                if snapshot.sortedPoolReports.count < snapshot.reportPool.count {
                    Button {
                        showAllReportPool = true
                    } label: {
                        Label("显示全部 \(snapshot.reportPool.count) 张未加入报表", systemImage: "list.bullet")
                    }
                    .buttonStyle(AppHoverButtonStyle(variant: .link))
                }
            }
        }
    }

    private func ReportTaskRoleControls(report: ImportedReport, role: AnalysisTaskReportRole) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                taskRoleButtons(report: report, role: role)
            }
            VStack(alignment: .leading, spacing: 6) {
                taskRoleButtons(report: report, role: role)
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private func taskRoleButtons(report: ImportedReport, role: AnalysisTaskReportRole) -> some View {
        Menu(role.label) {
            ForEach(AnalysisTaskReportRole.allCases) { item in
                Button(item.label) {
                    store.setSelectedTaskReportRole(reportID: report.id, role: item)
                }
                .help(item.explanation)
            }
        }
        .help(role.explanation)
        .hoverControlShell(.pickerShell)
        Button {
            store.removeReportFromSelectedTask(reportID: report.id)
        } label: {
            Label("移出", systemImage: "minus.circle")
        }
        .buttonStyle(AppHoverButtonStyle(variant: .danger))
    }

    @ViewBuilder
    private func auditContentLayout(_ snapshot: ImportAuditDeskSnapshot) -> some View {
        ResponsiveStack(compactBreakpoint: 820, spacing: 16, horizontalAlignment: .top) {
            reportList(snapshot)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
            Divider()
            if let report = snapshot.currentReport {
                ReportAuditDetail(
                    pack: pack,
                    report: report,
                    selectedDictionaryFieldID: $selectedDictionaryFieldID,
                    descriptionDraft: $descriptionDraft,
                    answerText: $answerText,
                    qaQuestionText: $qaQuestionText,
                    dictionaryAnswerText: $dictionaryAnswerText,
                    fieldSearchText: $fieldSearchText
                )
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func ensureSelection() {
        let snapshot = makeSnapshot()
        if taskNameDraft.isEmpty {
            taskNameDraft = snapshot.currentTask?.name ?? ""
        }
        if taskGoalDraft.isEmpty {
            taskGoalDraft = snapshot.currentTask?.goal ?? ""
        }
        guard selectedReportID == nil || !pack.importedReports.contains(where: { $0.id == selectedReportID }) else {
            descriptionDraft = snapshot.currentReport?.semanticProfile.summary ?? descriptionDraft
            return
        }
        selectedReportID = (snapshot.currentTaskReports.first ?? snapshot.sortedReports.first)?.id
        descriptionDraft = snapshot.currentReport?.semanticProfile.summary ?? ""
    }

    private func selectFirstIssue() {
        let snapshot = makeSnapshot()
        if let report = snapshot.currentTaskReports.first(where: { !$0.unresolvedAuditSteps.isEmpty }) ?? snapshot.sortedReports.first(where: { !$0.unresolvedAuditSteps.isEmpty }) {
            selectedReportID = report.id
            descriptionDraft = report.semanticProfile.summary
        }
    }

    private func sortedReportPool(_ reports: [ImportedReport], showAll: Bool, limit: Int) -> [ImportedReport] {
        guard !showAll, reports.count > limit else {
            return reports.sorted { $0.importedAt > $1.importedAt }
        }

        var visibleReports: [ImportedReport] = []
        visibleReports.reserveCapacity(limit)
        for report in reports {
            insertReportByImportedAt(report, into: &visibleReports, limit: limit)
        }
        return visibleReports
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

    private func reportSortScore(_ report: ImportedReport) -> Int {
        if report.isIgnoredFromAnalysis { return 0 }
        if !report.blockingAuditSteps.isEmpty { return 400 }
        if report.unresolvedAuditSteps.contains(where: { $0.kind == .typeDetection }) { return 320 }
        if !report.unresolvedAuditSteps.isEmpty { return 260 }
        if !report.acceptedRiskAuditSteps.isEmpty { return 160 }
        return 80
    }
}

private struct ImportAuditDeskSnapshot {
    var currentTask: AnalysisTask?
    var currentTaskReportIDs: Set<UUID>
    var currentTaskReports: [ImportedReport]
    var sortedTaskReports: [ImportedReport]
    var reportPool: [ImportedReport]
    var sortedPoolReports: [ImportedReport]
    var activeReports: [ImportedReport]
    var sortedReports: [ImportedReport]
    var currentReport: ImportedReport?
    var reportDisplayNamesByID: [UUID: String]
    var unresolvedIssueCount: Int
    var relationshipIssueCount: Int
    var confirmedReportCount: Int
    var readyReportCount: Int
    var acceptableRiskCount: Int
    var importReviewBlockerText: String?
    var aiObservationWarningText: String?
    var aiObservationStatusText: String
    var activeMetricLinks: [CrossTableMetricLink]
    var recommendedTemplates: [AnalysisTemplateMemory]
    var hasAvailableTemplates: Bool

    var taskGoalIsEmpty: Bool {
        (currentTask?.goal ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var relationshipReady: Bool {
        activeReports.count <= 1 || currentTask?.businessLinkProfile.confirmationStatus == .confirmed
    }

    func displayName(for reportID: UUID) -> String? {
        reportDisplayNamesByID[reportID]
    }
}

private struct AuditWorkflowStep: Identifiable {
    enum State {
        case done
        case current
        case pending
    }

    var number: Int
    var title: String
    var detail: String
    var state: State

    var id: Int { number }
}

private struct WorkflowStepChip: View {
    var step: AuditWorkflowStep

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle()
                    .fill(tint.opacity(step.state == .pending ? 0.12 : 0.18))
                if step.state == .done {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .fontWeight(.bold)
                } else {
                    Text("\(step.number)")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }
            .foregroundStyle(tint)
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.caption)
                    .fontWeight(step.state == .current ? .semibold : .medium)
                    .foregroundStyle(step.state == .pending ? .secondary : .primary)
                    .lineLimit(1)
                Text(step.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .frame(minWidth: 132, maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 8))
    }

    private var tint: Color {
        switch step.state {
        case .done: return AppTheme.success
        case .current: return AppTheme.accent
        case .pending: return .secondary
        }
    }

    private var background: Color {
        switch step.state {
        case .done: return AppTheme.success.opacity(0.08)
        case .current: return AppTheme.accent.opacity(0.10)
        case .pending: return Color.secondary.opacity(0.08)
        }
    }
}

private struct ActionHintBox: View {
    var title: String
    var message: String
    var systemImage: String
    var tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ReportAuditListRow: View {
    var report: ImportedReport
    var isSelected: Bool
    var role: AnalysisTaskReportRole?

    private var status: ImportAuditStepStatus {
        if report.isIgnoredFromAnalysis { return .acceptedRisk }
        if !report.blockingAuditSteps.isEmpty { return .blocked }
        if !report.unresolvedAuditSteps.isEmpty { return .needsConfirmation }
        if !report.acceptedRiskAuditSteps.isEmpty { return .acceptedRisk }
        return .completed
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : report.sourceFormat == .csv ? "doc.text" : "tablecells")
                .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.icon)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(report.displayName)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    Badge(text: report.sourceFormat.label, systemImage: nil, tint: .secondary)
                    Badge(text: report.shape.label, systemImage: nil, tint: AppTheme.info)
                    Badge(text: report.kind.label, systemImage: nil, tint: AppTheme.accent)
                }
                HStack(spacing: 6) {
                    Badge(text: status.label, systemImage: nil, tint: statusColor)
                    if let role {
                        Badge(text: role.label, systemImage: nil, tint: role == .primaryBusiness ? AppTheme.success : .secondary)
                    }
                    Text("问题 \(report.unresolvedAuditSteps.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 5)
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

private struct ReportAuditDetail: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    var pack: DataPack
    var report: ImportedReport
    @Binding var selectedDictionaryFieldID: UUID?
    @Binding var descriptionDraft: String
    @Binding var answerText: String
    @Binding var qaQuestionText: String
    @Binding var dictionaryAnswerText: String
    @Binding var fieldSearchText: String

    private func makeSnapshot() -> ReportAuditDetailSnapshot {
        let reportDefinitions = pack.fieldDefinitions.filter { $0.reportID == report.id }
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
        return ReportAuditDetailSnapshot(
            filteredDefinitions: filteredDefinitions,
            visibleDefinitions: Array(filteredDefinitions.prefix(120)),
            currentDefinition: currentDefinition,
            latestAssistantQAMessage: report.qaMessages.reversed().first { $0.role == .assistant }
        )
    }

    var body: some View {
        let snapshot = makeSnapshot()
        VStack(alignment: .leading, spacing: 14) {
            header
            requiredIssuesSection
            processingSection
            aiCoverageSection
            semanticSection(snapshot)
            fieldSection(snapshot)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            ResponsiveStack(compactBreakpoint: 560, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Text("\(report.sourceFileName) · \(report.sheetName ?? "无 Sheet") · \(report.rowCount) 行 · 表头列 \(report.headers.count) 个 · 首列指标 \(report.firstColumnValues.count) 个")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    store.ignoreReportFromAnalysis(reportID: report.id, ignored: !report.isIgnoredFromAnalysis)
                } label: {
                    Label(report.isIgnoredFromAnalysis ? "恢复此表" : "忽略此表", systemImage: report.isIgnoredFromAnalysis ? "arrow.uturn.backward" : "nosign")
                }
            }

            ResponsiveFormRow("显示名", labelWidth: 56) {
                AdaptiveTextField(placeholder: "可选：给这张表起一个更清楚的名称", text: Binding(
                    get: { report.userReportAlias },
                    set: { store.updateReportAlias(reportID: report.id, alias: $0) }
                ), minLines: 1, maxLines: 3)
            }
        }
    }

    private var processingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("处理过程", systemImage: "clock.arrow.circlepath")
                .font(.headline)
            ForEach(report.auditSteps) { step in
                AuditStepRow(reportID: report.id, step: step)
                Divider()
            }
        }
    }

    private var aiCoverageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AI 数据覆盖", systemImage: "eye")
                .font(.headline)
            if let coverage = report.tableContextCoverage {
                ResponsiveStack(compactBreakpoint: 620, spacing: 8) {
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

            if let analysis = report.aiFirstAnalysis {
                Divider()
                Label("AI 首轮表格分析", systemImage: "sparkles")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(analysis.summary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if !analysis.primaryComparison.isEmpty {
                    ForEach(Array(analysis.primaryComparison.prefix(10)), id: \.self) { item in
                        Text("• \(item)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !analysis.missingDataRequests.isEmpty {
                    Text("AI 追问数据")
                        .font(.caption)
                        .fontWeight(.medium)
                    ForEach(analysis.missingDataRequests.prefix(8)) { request in
                        Text("• \(request.kind.rawValue)：\(request.target)；\(request.reason)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text(store.hasConfiguredAI ? "点击“生成 AI 预读”后会运行 AI-first 表格理解；也可以直接在分析会话发送给 AI。" : "请先到 AI 设置填写 API Key。未配置 AI 时不会生成本地伪分析。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !report.aiReasoningLogs.isEmpty {
                DisclosureGroup("AI 推理日志") {
                    ForEach(report.aiReasoningLogs.suffix(12)) { log in
                        HStack(alignment: .top, spacing: 8) {
                            Badge(text: log.status.label, systemImage: nil, tint: log.status == .completed ? AppTheme.success : log.status == .needsUserAction ? AppTheme.danger : AppTheme.warning)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(log.step)
                                    .fontWeight(.medium)
                                Text(log.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Divider()
                }
            }
        }
    }
}

    @ViewBuilder
    private var requiredIssuesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("需要确认", systemImage: "exclamationmark.bubble")
                .font(.headline)
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
                        issueActions(for: step)
                    }
                    .padding(10)
                    .background(issueBackground(for: step.status), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func semanticSection(_ snapshot: ReportAuditDetailSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("表格含义", systemImage: "text.badge.checkmark")
                .font(.headline)

            AdaptiveTextBox(text: $descriptionDraft, placeholder: "写清楚这张表的用途、口径、时间范围和注意事项。内容较长时输入框会增高，超过上限后可上下滚动。", minHeight: 96, maxHeight: 300)

            ResponsiveStack(compactBreakpoint: 620, spacing: 8) {
                Button {
                    store.updateReportSemanticDescription(descriptionDraft, reportID: report.id)
                } label: {
                    Label("保存含义", systemImage: "square.and.arrow.down")
                }
                .disabled(descriptionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    store.askReportUnderstandingQuestion(reportID: report.id)
                } label: {
                    Label(store.isRunningReportUnderstandingAI ? "追问中" : "提问 AI", systemImage: "sparkles")
                }
                .disabled(store.isRunningReportUnderstandingAI)

                Button {
                    store.updateReportSemanticDescription(descriptionDraft, reportID: report.id)
                    store.confirmReportUnderstanding(reportID: report.id)
                } label: {
                    Label("确认口径", systemImage: "checkmark.seal")
                }
                .disabled(report.semanticStatus == .confirmed)
            }

            ReportSemanticProfilePreview(profile: report.semanticProfile)
            ReportUnderstandingMessageList(messages: report.understandingMessages)

            Divider()
            Label("表格问答", systemImage: "bubble.left.and.text.bubble.right")
                .font(.headline)
            AdaptiveTextBox(text: $qaQuestionText, placeholder: "向 AI 询问这张表的趋势、口径、异常指标或需要补充的数据。", minHeight: 76, maxHeight: 240)
            ResponsiveStack(compactBreakpoint: 620, spacing: 8) {
                Button {
                    let question = qaQuestionText
                    qaQuestionText = ""
                    store.askReportQuestion(question, reportID: report.id)
                } label: {
                    Label(store.isRunningReportQAI ? "回答中" : "提问这张表", systemImage: "sparkles")
                }
                .disabled(store.isRunningReportQAI || qaQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    store.adoptReportQAAsProfile(reportID: report.id, messageID: snapshot.latestAssistantQAMessage?.id)
                } label: {
                    Label("更新表格含义", systemImage: "checkmark.seal")
                }
                .disabled(snapshot.latestAssistantQAMessage == nil)

                Button {
                    store.adoptReportQAAsMemory(reportID: report.id, messageID: snapshot.latestAssistantQAMessage?.id, alsoSaveKnowledge: false)
                } label: {
                    Label("生成同类规则", systemImage: "brain")
                }
                .disabled(snapshot.latestAssistantQAMessage == nil)

                Button {
                    store.applyReportQAFieldPatches(reportID: report.id, messageID: snapshot.latestAssistantQAMessage?.id)
                } label: {
                    Label("更新字段解释", systemImage: "character.book.closed")
                }
                .disabled(snapshot.latestAssistantQAMessage?.fieldPatches.isEmpty != false)

                Button {
                    store.saveReportQAToKnowledge(reportID: report.id, messageID: snapshot.latestAssistantQAMessage?.id)
                } label: {
                    Label("沉淀进知识库", systemImage: "books.vertical")
                }
                .disabled(snapshot.latestAssistantQAMessage == nil)
            }

            if !report.qaMessages.isEmpty {
                ReportQAMessageList(messages: report.qaMessages)
            }
        }
    }

    private func fieldSection(_ snapshot: ReportAuditDetailSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("字段与口径", systemImage: "character.book.closed")
                .font(.headline)
            AdaptiveTextField(placeholder: "搜索当前表字段", text: $fieldSearchText, minLines: 1, maxLines: 2)

            if let definition = snapshot.currentDefinition {
                CurrentFieldDefinitionCard(definition: definition)
                AdaptiveTextBox(text: $dictionaryAnswerText, placeholder: "补充这个字段的业务含义、统计口径、触发时机或注意事项。", minHeight: 76, maxHeight: 220)
                ResponsiveStack(compactBreakpoint: 620, spacing: 8) {
                    Button {
                        selectedDictionaryFieldID = definition.id
                        store.askFieldDictionaryQuestion(fieldID: definition.id)
                    } label: {
                        Label(store.isRunningFieldDictionaryAI ? "提问中" : "让 AI 问字段", systemImage: "sparkles")
                    }
                    .disabled(store.isRunningFieldDictionaryAI)

                    Button {
                        let answer = dictionaryAnswerText
                        dictionaryAnswerText = ""
                        store.saveFieldDictionaryAnswer(answer, fieldID: definition.id)
                    } label: {
                        Label("保存字段回答", systemImage: "square.and.arrow.down")
                    }
                    .disabled(store.isRunningFieldDictionaryAI || dictionaryAnswerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Text("当前表没有字段字典。")
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup("完整字段字典") {
                ForEach(snapshot.visibleDefinitions) { definition in
                    FieldDefinitionRow(definition: definition)
                    Divider()
                }
                if snapshot.filteredDefinitions.count > 120 {
                    Text("已显示前 120 个字段，请搜索缩小范围。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func issueActions(for step: ImportAuditStep) -> some View {
        ResponsiveStack(compactBreakpoint: 560, spacing: 8) {
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
                    Label("提问 AI", systemImage: "sparkles")
                }
                .disabled(store.isRunningReportUnderstandingAI)
            }

            if step.status == .needsConfirmation {
                Button {
                    store.acceptAuditRisk(reportID: report.id, stepID: step.id)
                } label: {
                    Label("接受风险", systemImage: "checkmark.circle")
                }
            }

            Button {
                store.ignoreReportFromAnalysis(reportID: report.id)
            } label: {
                Label("忽略此表", systemImage: "nosign")
            }
        }
    }

    private func issueBackground(for status: ImportAuditStepStatus) -> Color {
        status == .blocked ? AppTheme.danger.opacity(0.12) : AppTheme.warning.opacity(0.12)
    }
}

private struct ReportAuditDetailSnapshot {
    var filteredDefinitions: [ReportFieldDefinition]
    var visibleDefinitions: [ReportFieldDefinition]
    var currentDefinition: ReportFieldDefinition?
    var latestAssistantQAMessage: ReportQAMessage?
}

private struct AuditStepRow: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    var reportID: UUID
    var step: ImportAuditStep

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ResponsiveStack(compactBreakpoint: 560, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                        .frame(width: 18)
                    Text(step.kind.label)
                        .fontWeight(.medium)
                    Badge(text: step.status.label, systemImage: nil, tint: tint)
                }
                if let confidence = step.confidence {
                    Text("置信度 \(Int(confidence * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(step.details)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(step.warnings.prefix(3), id: \.self) { warning in
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(step.status == .blocked ? AppTheme.danger : AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private var tint: Color {
        switch step.status {
        case .completed: return AppTheme.success
        case .needsConfirmation: return AppTheme.warning
        case .acceptedRisk: return AppTheme.accent
        case .blocked: return AppTheme.danger
        }
    }

    private var icon: String {
        switch step.status {
        case .completed: return "checkmark.circle"
        case .needsConfirmation: return "questionmark.circle"
        case .acceptedRisk: return "checkmark.circle.trianglebadge.exclamationmark"
        case .blocked: return "xmark.octagon"
        }
    }
}

private struct ReportRecognitionRow: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    var report: ImportedReport

    private var needsReview: Bool {
        report.detectedConfidence < 0.65 || !actionableWarnings.isEmpty || report.kind == .generic
    }

    private var actionableWarnings: [String] {
        report.parseWarnings.filter {
            !$0.contains("识别为透视宽表") &&
                !$0.contains("已标准化 CSV 换行符")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ResponsiveStack(compactBreakpoint: 620, spacing: 10) {
                titleBlock
                kindPicker
                    .frame(width: 150)
            }

            HStack(spacing: 6) {
                Badge(text: report.sourceFormat.label, systemImage: nil, tint: .secondary)
                Badge(text: report.shape.label, systemImage: nil, tint: report.shape == .pivotWide ? AppTheme.info : AppTheme.accent)
                Badge(text: "置信度 \(Int(report.detectedConfidence * 100))%", systemImage: nil, tint: needsReview ? AppTheme.warning : AppTheme.success)
                if needsReview {
                    Badge(text: "需要确认", systemImage: "exclamationmark.triangle", tint: AppTheme.warning)
                }
            }

            Text("\(report.rowCount) 行 · 表头列 \(report.headers.count) 个 · 首列指标 \(report.firstColumnValues.count) 个 · 趋势点 \(report.trendSummary.metricTrends.count) 个 · \(report.sheetName.map { "Sheet \($0) · " } ?? "")编码 \(report.originalEncoding.isEmpty ? "未知" : report.originalEncoding) · 分隔符 \(report.delimiter) · \(DateFormatting.shortDateTime.string(from: report.importedAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !report.trendSummary.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("数据趋势")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("已识别 \(report.trendSummary.metricTrends.count) 个趋势点，展示前 \(min(report.trendSummary.trendBullets.count, 30)) 条。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(report.trendSummary.trendBullets.prefix(30), id: \.self) { trend in
                        Text("• \(trend)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(report.trendSummary.distributionBullets.prefix(5), id: \.self) { trend in
                        Text("• \(trend)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !report.parseWarnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(report.parseWarnings.prefix(4), id: \.self) { warning in
                        Text("• \(warning)")
                            .font(.caption)
                            .foregroundStyle(actionableWarnings.contains(warning) ? AppTheme.warning : AppTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(report.fileName)
                .fontWeight(.medium)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text("字段/指标预览：\(DataImportService.fieldDefinitionNames(for: report).prefix(10).joined(separator: "，"))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var kindPicker: some View {
        Picker("报表类型", selection: Binding(
            get: { report.kind },
            set: { store.updateImportedReportKind(reportID: report.id, kind: $0) }
        )) {
            ForEach(ImportedReportKind.allCases) { kind in
                Text(kind.label).tag(kind)
            }
        }
        .labelsHidden()
        .hoverControlShell(.pickerShell)
    }
}

private struct DataPackRow: View {
    var pack: DataPack
    var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "archivebox")
                .foregroundStyle(isSelected ? AppTheme.success : AppTheme.icon)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 5) {
                Text(pack.name)
                    .fontWeight(.medium)
                Text("\(pack.period) · \(pack.dateRangeText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(pack.reportSourceSummary)
                    .font(.caption)
                    .foregroundStyle(pack.tableauReportCount > 0 ? AppTheme.accent : AppTheme.mutedText)
                Text("更新 \(pack.productUpdates.count) · 指标 \(pack.metrics.count) · 事件 \(pack.events.count) · 反馈 \(pack.feedback.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Badge(text: pack.qualityReport.verdict.rawValue, systemImage: nil, tint: pack.qualityReport.verdict == .usable ? AppTheme.success : AppTheme.warning)
        }
        .padding(.vertical, 6)
    }
}

private struct ReportUnderstandingPanel: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    var pack: DataPack
    @Binding var selectedReportID: UUID?
    @Binding var descriptionDraft: String
    @Binding var answerText: String
    @Binding var qaQuestionText: String
    @State private var showAllReports = false

    private var pendingReports: [ImportedReport] {
        pack.importedReports.filter { $0.semanticStatus == .needsReview || $0.semanticStatus == .inProgress }
    }

    private var currentReport: ImportedReport? {
        if let selectedReportID,
           let report = pack.importedReports.first(where: { $0.id == selectedReportID }) {
            return report
        }
        return pendingReports.first ?? pack.importedReports.first
    }

    private var visibleReports: [ImportedReport] {
        guard !showAllReports, pack.importedReports.count > 60 else { return pack.importedReports }
        var visible = Array(pack.importedReports.prefix(60))
        if let selectedReportID,
           !visible.contains(where: { $0.id == selectedReportID }),
           let selected = pack.importedReports.first(where: { $0.id == selectedReportID }) {
            visible.append(selected)
        }
        return visible
    }

    var body: some View {
        SectionCard(title: "报表理解草稿", systemImage: "text.badge.checkmark") {
            if pack.importedReports.isEmpty {
                Text("当前数据包还没有需要确认的报表。")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 12) {
                            reportProgressText
                            Spacer()
                            reportProgressBar
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            reportProgressText
                            reportProgressBar
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(visibleReports) { report in
                            ReportUnderstandingQueueRow(
                                report: report,
                                isSelected: currentReport?.id == report.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedReportID = report.id
                                descriptionDraft = report.semanticProfile.summary
                                answerText = ""
                                qaQuestionText = ""
                            }
                        }
                        if visibleReports.count < pack.importedReports.count {
                            Button("显示全部 \(pack.importedReports.count) 张报表") {
                                showAllReports = true
                            }
                            .buttonStyle(AppHoverButtonStyle(variant: .link))
                            .font(.caption)
                        }
                    }

                    if let report = currentReport {
                        Divider()
                        ReportUnderstandingWorkspace(
                            report: report,
                            descriptionDraft: $descriptionDraft,
                            answerText: $answerText,
                            qaQuestionText: $qaQuestionText
                        )
                    }
                }
                .onAppear {
                    ensureSelection()
                }
                .onChange(of: pack.id) { _ in
                    selectedReportID = nil
                    descriptionDraft = ""
                    answerText = ""
                    qaQuestionText = ""
                    showAllReports = false
                    ensureSelection()
                }
                .onChange(of: selectedReportID) { _ in
                    descriptionDraft = currentReport?.semanticProfile.summary ?? ""
                    answerText = ""
                    qaQuestionText = ""
                }
            }
        }
    }

    private func ensureSelection() {
        guard selectedReportID == nil || !pack.importedReports.contains(where: { $0.id == selectedReportID }) else {
            descriptionDraft = currentReport?.semanticProfile.summary ?? descriptionDraft
            return
        }
        selectedReportID = pendingReports.first?.id ?? pack.importedReports.first?.id
        descriptionDraft = currentReport?.semanticProfile.summary ?? ""
    }

    private var reportProgressText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("待确认 \(pendingReports.count) / \(pack.importedReports.count) 张报表")
                .font(.headline)
            Text(pendingReports.isEmpty ? "报表已自动识别或人工确认，AI 分析和完整汇报会使用这些语义；你仍可手动校准。" : "只有识别弱或口径不明确的报表需要补充；其他报表会先按自动识别语义参与分析。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reportProgressBar: some View {
        ProgressView(value: Double(pack.importedReports.count - pendingReports.count), total: Double(max(pack.importedReports.count, 1)))
            .frame(maxWidth: 180)
    }
}

private struct ReportUnderstandingQueueRow: View {
    var report: ImportedReport
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "doc.text.magnifyingglass")
                .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.icon)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(report.fileName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Badge(text: report.semanticStatus.label, systemImage: nil, tint: statusColor)
                    Spacer()
                }
                Text("\(report.sourceFormat.label) · \(report.kind.label) · \(report.shape.label) · \(report.rowCount) 行 · 表头列 \(report.headers.count) 个 · 首列指标 \(report.firstColumnValues.count) 个 · 类型 \(Int(report.detectedConfidence * 100))% · 语义 \(Int(report.semanticConfidence * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch report.semanticStatus {
        case .needsReview: return AppTheme.warning
        case .inProgress: return AppTheme.accent
        case .autoInferred: return AppTheme.info
        case .confirmed: return AppTheme.success
        }
    }
}

private struct ReportUnderstandingWorkspace: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    var report: ImportedReport
    @Binding var descriptionDraft: String
    @Binding var answerText: String
    @Binding var qaQuestionText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    reportHeader
                    Spacer()
                    askQuestionButton
                }

                VStack(alignment: .leading, spacing: 8) {
                    reportHeader
                    askQuestionButton
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("你的报表描述")
                    .font(.headline)
                AdaptiveTextBox(text: $descriptionDraft, placeholder: "写清楚这张表是做什么的、统计周期、业务对象、适用场景和限制。", minHeight: 104, maxHeight: 320)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        descriptionHelpText
                        Spacer()
                        saveDescriptionButton
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        descriptionHelpText
                        saveDescriptionButton
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ReportSemanticProfilePreview(profile: report.semanticProfile)
                        .frame(minWidth: 280, maxWidth: .infinity, alignment: .topLeading)

                    ReportUnderstandingMessageList(messages: report.understandingMessages)
                        .frame(minWidth: 300, maxWidth: .infinity, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: 14) {
                    ReportSemanticProfilePreview(profile: report.semanticProfile)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ReportUnderstandingMessageList(messages: report.understandingMessages)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("回答 AI 的疑问")
                    .font(.headline)
                AdaptiveTextBox(text: $answerText, placeholder: "回答 AI 对这张表口径、时间范围或业务含义的疑问。", minHeight: 92, maxHeight: 280)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        answerHelpText
                        Spacer()
                        answerActions
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        answerHelpText
                        answerActions
                    }
                }
            }

            ReportQAWorkspace(report: report, questionText: $qaQuestionText)
        }
    }

    private var reportHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(report.fileName)
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text("先用自然语言写清楚这张表的业务含义，再让 AI 继续追问疑点。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var askQuestionButton: some View {
        Button {
            store.askReportUnderstandingQuestion(reportID: report.id)
        } label: {
            Label(store.isRunningReportUnderstandingAI ? "处理中" : "让 AI 继续追问", systemImage: "sparkles")
        }
        .disabled(store.isRunningReportUnderstandingAI)
    }

    private var descriptionHelpText: some View {
        Text("这段描述会进入报表语义草稿，确认后 AI 分析会优先使用。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var saveDescriptionButton: some View {
        Button {
            store.updateReportSemanticDescription(descriptionDraft, reportID: report.id)
        } label: {
            Label("保存描述", systemImage: "square.and.arrow.down")
        }
        .disabled(descriptionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var answerHelpText: some View {
        Text(report.semanticStatus == .confirmed ? "这张报表已确认；继续回答会把状态改为确认中。" : report.semanticStatus == .autoInferred ? "系统已自动识别报表含义；只在特殊口径、筛选条件或时间顺序不一致时校准。" : "可以反复回答和追问，最终由你手动确认。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var answerActions: some View {
        Button {
            let sent = answerText
            answerText = ""
            store.sendReportUnderstandingAnswer(sent, reportID: report.id)
        } label: {
            Label("发送回答", systemImage: "paperplane")
        }
        .disabled(store.isRunningReportUnderstandingAI || answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        Button {
            store.updateReportSemanticDescription(descriptionDraft, reportID: report.id)
            store.confirmReportUnderstanding(reportID: report.id)
        } label: {
            Label("确认报表说明", systemImage: "checkmark.seal")
        }
        .disabled(store.isRunningReportUnderstandingAI || report.semanticStatus == .confirmed)
    }
}

private struct ReportQAWorkspace: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    var report: ImportedReport
    @Binding var questionText: String

    private var latestAssistantMessage: ReportQAMessage? {
        report.qaMessages.reversed().first { $0.role == .assistant }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                Label("表格问答", systemImage: "bubble.left.and.text.bubble.right")
                    .font(.headline)
                Spacer()
                Text("回答可采纳为报表说明、同类规则、字段解释或知识库条目")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            AdaptiveTextBox(text: $questionText, placeholder: "输入你想问这张表的问题，例如趋势、异常、口径、未成熟周期或字段含义。", minHeight: 84, maxHeight: 260)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    askButton
                    Spacer()
                    qaAdoptionActions
                }
                VStack(alignment: .leading, spacing: 8) {
                    askButton
                    qaAdoptionActions
                }
            }

            if report.qaMessages.isEmpty {
                Text("可以直接问：最新周期是否完整、哪些指标不能直接比较、这张表适合分析什么、字段口径是否清楚。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ReportQAMessageList(messages: report.qaMessages)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var askButton: some View {
        Button {
            let question = questionText
            questionText = ""
            store.askReportQuestion(question, reportID: report.id)
        } label: {
            Label(store.isRunningReportQAI ? "回答中" : "提问这张表", systemImage: "sparkles")
        }
        .disabled(store.isRunningReportQAI || questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @ViewBuilder
    private var qaAdoptionActions: some View {
        Button {
            store.adoptReportQAAsProfile(reportID: report.id, messageID: latestAssistantMessage?.id)
        } label: {
            Label("采纳为本表说明", systemImage: "checkmark.seal")
        }
        .disabled(latestAssistantMessage == nil || store.isRunningReportQAI)

        Button {
            store.adoptReportQAAsMemory(reportID: report.id, messageID: latestAssistantMessage?.id)
        } label: {
            Label("采纳为同类规则", systemImage: "brain")
        }
        .disabled(latestAssistantMessage == nil || store.isRunningReportQAI)

        Button {
            store.applyReportQAFieldPatches(reportID: report.id, messageID: latestAssistantMessage?.id)
        } label: {
            Label("采纳字段解释", systemImage: "character.book.closed")
        }
        .disabled(latestAssistantMessage?.fieldPatches.isEmpty != false || store.isRunningReportQAI)

        Button {
            store.saveReportQAToKnowledge(reportID: report.id, messageID: latestAssistantMessage?.id)
        } label: {
            Label("沉淀进知识库", systemImage: "books.vertical")
        }
        .disabled(latestAssistantMessage == nil || store.isRunningReportQAI)
    }
}

private struct ReportQAMessageList: View {
    var messages: [ReportQAMessage]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(messages.suffix(16)) { message in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(message.role.label)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(DateFormatting.shortDateTime.string(from: message.createdAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(message.content)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !message.evidence.isEmpty {
                            Text("依据：\(message.evidence.prefix(4).joined(separator: "；"))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !message.uncertainties.isEmpty {
                            Text("待确认：\(message.uncertainties.prefix(4).joined(separator: "；"))")
                                .font(.caption)
                                .foregroundStyle(AppTheme.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !message.suggestedMemories.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("候选记忆")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                ForEach(message.suggestedMemories.prefix(4)) { memory in
                                    Text("• \(memory.title)：\(memory.content)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    Divider()
                }
            }
        }
        .frame(minHeight: 180, maxHeight: 360)
    }
}

private struct ReportSemanticProfilePreview: View {
    var profile: ReportSemanticProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("结构化草稿")
                .font(.headline)
            KeyValueRow(key: "摘要", value: profile.summary)
            KeyValueRow(key: "用途", value: profile.purpose)
            KeyValueRow(key: "业务对象", value: profile.businessObject)
            KeyValueRow(key: "粒度", value: profile.grain)
            KeyValueRow(key: "关键指标", value: profile.keyMetrics.joined(separator: "，"))
            KeyValueRow(key: "维度", value: profile.dimensions.joined(separator: "，"))
            KeyValueRow(key: "筛选条件", value: profile.filters)
            KeyValueRow(key: "适用场景", value: profile.useCases.joined(separator: "，"))
            KeyValueRow(key: "注意事项", value: profile.caveats.joined(separator: "，"))
            if !profile.openQuestions.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("待确认疑问")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(profile.openQuestions.prefix(6), id: \.self) { question in
                        Text("- \(question)")
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReportUnderstandingMessageList: View {
    var messages: [ReportUnderstandingMessage]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("确认对话")
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if messages.isEmpty {
                        Text("AI 会在这里追问报表用途、统计口径、关键指标和限制条件。")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                    } else {
                        ForEach(messages.suffix(14)) { message in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(message.role.label)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text(DateFormatting.shortDateTime.string(from: message.createdAt))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(message.content)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
            }
            .frame(minHeight: 180, maxHeight: 320)
        }
    }
}

private struct FieldDictionaryAssistantPanel: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    var pack: DataPack
    @Binding var selectedDefinitionID: UUID?
    @Binding var answerText: String

    private var confirmedCount: Int {
        pack.fieldDefinitions.filter(\.isConfirmed).count
    }

    private var currentDefinition: ReportFieldDefinition? {
        if let selectedDefinitionID,
           let definition = pack.fieldDefinitions.first(where: { $0.id == selectedDefinitionID }) {
            return definition
        }
        return nextUnconfirmedDefinition ?? pack.fieldDefinitions.first
    }

    private var nextUnconfirmedDefinition: ReportFieldDefinition? {
        pack.fieldDefinitions.first { !$0.isConfirmed }
    }

    private var fieldMenuDefinitions: [ReportFieldDefinition] {
        guard pack.fieldDefinitions.count > 120 else { return pack.fieldDefinitions }
        var result: [ReportFieldDefinition] = []
        var seen = Set<UUID>()
        func append(_ definition: ReportFieldDefinition?) {
            guard let definition, !seen.contains(definition.id) else { return }
            result.append(definition)
            seen.insert(definition.id)
        }
        append(currentDefinition)
        append(nextUnconfirmedDefinition)
        for definition in pack.fieldDefinitions where !definition.isConfirmed {
            append(definition)
            if result.count >= 80 { break }
        }
        for definition in pack.fieldDefinitions {
            append(definition)
            if result.count >= 120 { break }
        }
        return result
    }

    var body: some View {
        SectionCard(title: "AI 字段定义助手", systemImage: "bubble.left.and.text.bubble.right") {
            if pack.fieldDefinitions.isEmpty {
                Text("当前数据包还没有字段字典。导入报表后会从第一行和第一列提取字段标签。")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 12) {
                            fieldProgressText
                            Spacer()
                            fieldProgressBar
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            fieldProgressText
                            fieldProgressBar
                        }
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 10) {
                            fieldSelectionMenu
                            Spacer()
                            askFieldButton
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            fieldSelectionMenu
                            askFieldButton
                        }
                    }

                    if let definition = currentDefinition {
                        CurrentFieldDefinitionCard(definition: definition)
                    }

                    FieldDictionaryMessageList(messages: Array(pack.fieldDictionaryMessages.suffix(12)))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("回答当前字段")
                            .font(.headline)
                        AdaptiveTextBox(text: $answerText, placeholder: "填写当前字段的含义、业务口径、触发条件或统计注意事项。", minHeight: 92, maxHeight: 260)

                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                fieldAnswerHelpText
                                Spacer()
                                saveFieldAnswerButton
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                fieldAnswerHelpText
                                saveFieldAnswerButton
                            }
                        }
                    }
                }
                .onAppear {
                    ensureSelection()
                }
                .onChange(of: pack.id) { _ in
                    selectedDefinitionID = nil
                    answerText = ""
                    ensureSelection()
                }
            }
        }
    }

    private var currentDefinitionTitle: String {
        guard let currentDefinition else { return "选择字段" }
        return "\(currentDefinition.reportName) · \(currentDefinition.fieldName)"
    }

    private var fieldProgressText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("定义进度")
                .font(.headline)
            Text("已确认 \(confirmedCount) / \(pack.fieldDefinitions.count) 个字段")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("全局字段记忆 \(store.workspace.fieldDictionaryMemories.count) 条")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var fieldProgressBar: some View {
        ProgressView(value: Double(confirmedCount), total: Double(max(pack.fieldDefinitions.count, 1)))
            .frame(maxWidth: 180)
    }

    private var fieldSelectionMenu: some View {
        Menu(currentDefinitionTitle) {
            if let nextUnconfirmedDefinition {
                Button("选择下一个待确认字段") {
                    selectedDefinitionID = nextUnconfirmedDefinition.id
                }
                Divider()
            }
            ForEach(fieldMenuDefinitions) { definition in
                Button {
                    selectedDefinitionID = definition.id
                } label: {
                    Text("\(definition.isConfirmed ? "已确认" : "待确认") · \(definition.reportName) · \(definition.fieldName)")
                }
            }
            if fieldMenuDefinitions.count < pack.fieldDefinitions.count {
                Divider()
                Text("已显示 \(fieldMenuDefinitions.count)/\(pack.fieldDefinitions.count) 个字段；更多字段请在下方字段列表搜索。")
                    .foregroundStyle(.secondary)
            }
        }
        .hoverControlShell(.pickerShell)
    }

    private var askFieldButton: some View {
        Button {
            selectedDefinitionID = nextUnconfirmedDefinition?.id ?? currentDefinition?.id
            store.askFieldDictionaryQuestion(fieldID: selectedDefinitionID)
        } label: {
            Label(store.isRunningFieldDictionaryAI ? "处理中" : "让 AI 提问", systemImage: "sparkles")
        }
        .disabled(store.isRunningFieldDictionaryAI || currentDefinition == nil)
    }

    private var fieldAnswerHelpText: some View {
        Text("回答后系统会整理成字段含义、类型和备注，并自动进入下一个待确认字段。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var saveFieldAnswerButton: some View {
        Button {
            let sent = answerText
            answerText = ""
            store.saveFieldDictionaryAnswer(sent, fieldID: currentDefinition?.id)
        } label: {
            Label("保存回答", systemImage: "square.and.arrow.down")
        }
        .disabled(store.isRunningFieldDictionaryAI || answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func ensureSelection() {
        guard selectedDefinitionID == nil || !pack.fieldDefinitions.contains(where: { $0.id == selectedDefinitionID }) else {
            return
        }
        selectedDefinitionID = nextUnconfirmedDefinition?.id ?? pack.fieldDefinitions.first?.id
    }
}

private struct CurrentFieldDefinitionCard: View {
    var definition: ReportFieldDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Badge(text: definition.reportKind.label, systemImage: nil, tint: definition.reportKind == .eventTracking ? .secondary : AppTheme.accent)
                Badge(text: definition.isConfirmed ? "已确认" : "待确认", systemImage: nil, tint: definition.isConfirmed ? AppTheme.success : AppTheme.warning)
                Text(definition.fieldName)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(definition.dataType)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            KeyValueRow(key: "报表", value: definition.reportName)
            KeyValueRow(key: "样例", value: definition.exampleValue.isEmpty ? "无样例" : definition.exampleValue)
            KeyValueRow(key: "当前含义", value: definition.meaning.isEmpty ? "未填写" : definition.meaning)
            if !definition.notes.isEmpty {
                KeyValueRow(key: "备注", value: definition.notes)
            }
        }
        .padding(10)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }
}

private struct FieldDictionaryMessageList: View {
    var messages: [FieldDictionaryMessage]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if messages.isEmpty {
                    Text("点击“让 AI 提问”开始定义第一行和第一列里的字段标签。")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                } else {
                    ForEach(messages) { message in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(message.role.label)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                if !message.fieldName.isEmpty {
                                    Text("\(message.reportName) · \(message.fieldName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Text(DateFormatting.shortDateTime.string(from: message.createdAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Text(message.content)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }
                }
            }
        }
        .frame(minHeight: 120, maxHeight: 260)
    }
}

private struct FieldDefinitionDraft: Equatable {
    var meaning: String
    var dataType: String
    var notes: String

    init(_ definition: ReportFieldDefinition) {
        self.meaning = definition.meaning
        self.dataType = definition.dataType
        self.notes = definition.notes
    }
}

private struct FieldDefinitionRow: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    var definition: ReportFieldDefinition
    @State private var draft: FieldDefinitionDraft
    @State private var lastCommittedDraft: FieldDefinitionDraft
    @State private var commitTask: Task<Void, Never>?

    init(definition: ReportFieldDefinition) {
        self.definition = definition
        let initialDraft = FieldDefinitionDraft(definition)
        _draft = State(initialValue: initialDraft)
        _lastCommittedDraft = State(initialValue: initialDraft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    fieldBadges
                    Text(definition.reportName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(draft.dataType)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        fieldBadges
                    }
                    Text(definition.reportName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ResponsiveFormRow("字段", labelWidth: 56) {
                    Text(definition.fieldName)
                        .fontWeight(.medium)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ResponsiveFormRow("含义", labelWidth: 56) {
                    AdaptiveTextField(placeholder: "填写字段含义、业务口径、埋点触发时机", text: Binding(
                        get: { draft.meaning },
                        set: { updateDraft(\.meaning, value: $0) }
                    ), minLines: 1, maxLines: 4)
                }

                ResponsiveFormRow("类型", labelWidth: 56) {
                    AdaptiveTextField(placeholder: "string / number / date / enum", text: Binding(
                        get: { draft.dataType },
                        set: { updateDraft(\.dataType, value: $0) }
                    ), minLines: 1, maxLines: 2)
                }

                ResponsiveFormRow("示例", labelWidth: 56) {
                    Text(definition.exampleValue.isEmpty ? "无样例" : definition.exampleValue)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ResponsiveFormRow("备注", labelWidth: 56) {
                    AdaptiveTextField(placeholder: "补充统计口径、清洗规则或注意事项", text: Binding(
                        get: { draft.notes },
                        set: { updateDraft(\.notes, value: $0) }
                    ), minLines: 1, maxLines: 5)
                }
            }
        }
        .padding(.vertical, 8)
        .onChange(of: definition.id) { _ in
            resetDraftFromDefinition(force: true)
        }
        .onChange(of: definition.updatedAt) { _ in
            resetDraftFromDefinition(force: false)
        }
        .onDisappear {
            flushDraftToStore()
        }
    }

    @ViewBuilder
    private var fieldBadges: some View {
        Badge(text: definition.reportKind.label, systemImage: nil, tint: definition.reportKind == .eventTracking ? .secondary : AppTheme.accent)
        Badge(text: definition.isConfirmed ? "已确认" : "待确认", systemImage: nil, tint: definition.isConfirmed ? AppTheme.success : AppTheme.warning)
    }

    private func updateDraft(_ keyPath: WritableKeyPath<FieldDefinitionDraft, String>, value: String) {
        draft[keyPath: keyPath] = value
        scheduleDraftCommit(draft)
    }

    private func scheduleDraftCommit(_ pendingDraft: FieldDefinitionDraft) {
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, draft == pendingDraft else { return }
            commitDraftToStore(pendingDraft)
            commitTask = nil
        }
    }

    private func flushDraftToStore() {
        commitTask?.cancel()
        commitTask = nil
        commitDraftToStore(draft)
    }

    private func commitDraftToStore(_ draftToCommit: FieldDefinitionDraft) {
        guard draftToCommit != lastCommittedDraft else { return }
        store.updateFieldDefinition(
            definition,
            meaning: draftToCommit.meaning,
            dataType: draftToCommit.dataType,
            notes: draftToCommit.notes
        )
        lastCommittedDraft = draftToCommit
    }

    private func resetDraftFromDefinition(force: Bool) {
        let latestDraft = FieldDefinitionDraft(definition)
        guard force || draft == lastCommittedDraft else { return }
        commitTask?.cancel()
        commitTask = nil
        draft = latestDraft
        lastCommittedDraft = latestDraft
    }
}
