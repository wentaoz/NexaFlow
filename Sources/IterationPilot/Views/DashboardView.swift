import SwiftUI

private struct DashboardRevision: Equatable {
    var selectedPackID: UUID?
    var selectedBusinessSpaceID: UUID?
    var selectedAnalysisSessionID: UUID?
    var selectedPackHash: Int
    var knowledgeEntryHash: Int
    var referenceSourceHash: Int
    var referenceItemHash: Int
    var selectedSessionMessageHash: Int
}

struct DashboardView: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    @State private var snapshot = DashboardSnapshot.empty
    @State private var snapshotRevision: DashboardRevision?
    @State private var snapshotRefreshTask: Task<Void, Never>?

    private func makeSnapshot(for pack: DataPack) -> DashboardSnapshot {
        let sourceByID = Dictionary(uniqueKeysWithValues: store.workspace.referenceSources.map { ($0.id, $0) })
        let businessSpaceID = store.selectedBusinessSpace?.id
        let externalReferenceCount = store.workspace.referenceItems.reduce(0) { count, item in
            item.isVisible(in: businessSpaceID, sourceByID: sourceByID) ? count + 1 : count
        }
        return DashboardSnapshot(
            knowledgeEventCount: KnowledgeEventAxis.productEventCount(from: store.workspace.knowledgeEntries),
            externalReferenceCount: externalReferenceCount,
            contextSignalCount: pack.analysisReport.contextSignals.count,
            hasSelectedTaskReports: !(store.currentAnalysisTask(in: pack)?.activeReportIDs.isEmpty ?? true),
            hasAIAnalysisMessage: store.selectedAnalysisSession?.messages.contains { $0.role == .assistant && $0.kind == .aiAnalysis } == true
        )
    }

    var body: some View {
        ScrollView {
            if let pack = store.selectedPack {
                LazyVStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("产品迭代 AI 工作流")
                                .font(.largeTitle)
                                .fontWeight(.semibold)
                            Text(pack.name)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Badge(text: pack.qualityReport.verdict.rawValue, systemImage: pack.qualityReport.verdict.systemImage, tint: pack.qualityReport.verdict == .blocked ? AppTheme.danger : pack.qualityReport.verdict == .caution ? AppTheme.warning : AppTheme.success)
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        MetricTile(title: "知识库事件", value: "\(snapshot.knowledgeEventCount)", systemImage: "books.vertical")
                        MetricTile(title: "报表", value: "\(pack.importedReports.count)", systemImage: "tablecells")
                        MetricTile(title: "外部参照", value: "\(snapshot.externalReferenceCount)", systemImage: "newspaper")
                        MetricTile(title: "上下文信号", value: "\(snapshot.contextSignalCount)", systemImage: "sparkles")
                        MetricTile(title: "指标记录", value: "\(pack.metrics.count)", systemImage: "chart.bar")
                        MetricTile(title: "反馈样本", value: "\(pack.feedback.count)", systemImage: "bubble.left.and.bubble.right")
                    }

                    SectionCard(title: "当前结论", systemImage: "sparkles") {
                        Text(pack.analysisReport.summary)
                            .font(.body)
                            .textSelection(.enabled)
                    }

                    SectionCard(title: "工作流状态", systemImage: "checklist") {
                        WorkflowStepRow(title: "1. 进入分析会话", detail: "主流程集中在分析会话：导入表格、选本次任务表、写目标并连续追问 AI。", isDone: true)
                        WorkflowStepRow(title: "2. 选择任务报表", detail: "AI 只分析当前任务选择的表，不会把同一数据包里的所有表强行联动。", isDone: snapshot.hasSelectedTaskReports)
                        WorkflowStepRow(title: "3. AI 对话分析", detail: "业务解释、归因、外部事件影响和结论由 AI 直接生成；本地只负责读数、事实打包和校验。", isDone: snapshot.hasAIAnalysisMessage)
                        WorkflowStepRow(title: "4. 二级质检与口径", detail: "数据质检、导入审核、字段字典和业务链路都放在分析会话右侧二级面板。", isDone: pack.qualityReport.verdict != .blocked)
                        WorkflowStepRow(title: "5. 机会评分", detail: "AI 分析成功后自动抽取结构化机会，并写回当前任务和机会评分页。", isDone: !pack.analysisReport.opportunities.isEmpty)
                        WorkflowStepRow(title: "6. 完整汇报", detail: "AI 根据当前会话、机会评分和结构化证据生成完整汇报并支持导出。", isDone: !pack.decisionMemo.markdown.isEmpty)
                    }
                }
                .padding(18)
            } else {
                EmptyStateView(title: "还没有数据包", detail: "导入指标/报表数据包，产品事件轴会直接参考知识库和 Confluence。", systemImage: "tray")
            }
        }
        .onAppear {
            refreshSnapshot(force: true)
        }
        .onReceive(store.$workspace) { _ in
            scheduleSnapshotRefresh()
        }
        .onChange(of: store.selectedPackID) { _ in
            refreshSnapshot(force: true)
        }
        .onDisappear {
            snapshotRefreshTask?.cancel()
            snapshotRefreshTask = nil
        }
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
        let revision = makeDashboardRevision()
        guard force || revision != snapshotRevision else { return }
        if let pack = store.selectedPack {
            snapshot = makeSnapshot(for: pack)
        } else {
            snapshot = .empty
        }
        snapshotRevision = revision
    }

    private func makeDashboardRevision() -> DashboardRevision {
        let selectedPack = store.selectedPack
        var selectedPackHasher = Hasher()
        if let selectedPack {
            selectedPackHasher.combine(selectedPack.id)
            selectedPackHasher.combine(selectedPack.qualityReport.verdict)
            selectedPackHasher.combine(selectedPack.importedReports.count)
            selectedPackHasher.combine(selectedPack.metrics.count)
            selectedPackHasher.combine(selectedPack.feedback.count)
            selectedPackHasher.combine(selectedPack.analysisReport.contextSignals.count)
            selectedPackHasher.combine(selectedPack.analysisReport.opportunities.count)
            selectedPackHasher.combine(selectedPack.decisionMemo.markdown.isEmpty)
            selectedPackHasher.combine(store.currentAnalysisTask(in: selectedPack)?.activeReportIDs)
        }

        var knowledgeHasher = Hasher()
        for entry in store.workspace.knowledgeEntries {
            knowledgeHasher.combine(entry.id)
            knowledgeHasher.combine(entry.businessSpaceID)
            knowledgeHasher.combine(entry.isGlobal)
            knowledgeHasher.combine(entry.scenario)
            knowledgeHasher.combine(entry.problem)
            knowledgeHasher.combine(entry.action)
            knowledgeHasher.combine(entry.result)
            knowledgeHasher.combine(entry.tags)
        }

        var referenceSourceHasher = Hasher()
        for source in store.workspace.referenceSources {
            referenceSourceHasher.combine(source.id)
            referenceSourceHasher.combine(source.isGlobal)
            referenceSourceHasher.combine(source.businessSpaceIDs)
        }

        var referenceItemHasher = Hasher()
        for item in store.workspace.referenceItems {
            referenceItemHasher.combine(item.id)
            referenceItemHasher.combine(item.sourceID)
            referenceItemHasher.combine(item.businessSpaceID)
        }

        var messageHasher = Hasher()
        if let session = store.selectedAnalysisSession {
            for message in session.messages {
                messageHasher.combine(message.id)
                messageHasher.combine(message.role)
                messageHasher.combine(message.kind)
            }
        }

        return DashboardRevision(
            selectedPackID: store.selectedPackID,
            selectedBusinessSpaceID: store.workspace.selectedBusinessSpaceID,
            selectedAnalysisSessionID: store.workspace.selectedAnalysisSessionID,
            selectedPackHash: selectedPackHasher.finalize(),
            knowledgeEntryHash: knowledgeHasher.finalize(),
            referenceSourceHash: referenceSourceHasher.finalize(),
            referenceItemHash: referenceItemHasher.finalize(),
            selectedSessionMessageHash: messageHasher.finalize()
        )
    }
}

private struct DashboardSnapshot {
    var knowledgeEventCount: Int
    var externalReferenceCount: Int
    var contextSignalCount: Int
    var hasSelectedTaskReports: Bool
    var hasAIAnalysisMessage: Bool

    static let empty = DashboardSnapshot(
        knowledgeEventCount: 0,
        externalReferenceCount: 0,
        contextSignalCount: 0,
        hasSelectedTaskReports: false,
        hasAIAnalysisMessage: false
    )
}

private struct WorkflowStepRow: View {
    var title: String
    var detail: String
    var isDone: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDone ? AppTheme.success : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
