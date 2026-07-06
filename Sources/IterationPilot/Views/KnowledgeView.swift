import SwiftUI

private struct KnowledgeEntryPreview {
    var visibleEntries: [KnowledgeEntry]
    var totalCount: Int
    var confluenceCount: Int
    var reportCount: Int

    static let empty = KnowledgeEntryPreview(
        visibleEntries: [],
        totalCount: 0,
        confluenceCount: 0,
        reportCount: 0
    )
}

private struct ReportKnowledgeMemoryPreview {
    var visibleMemories: [ReportKnowledgeMemory]
    var totalCount: Int

    static let empty = ReportKnowledgeMemoryPreview(visibleMemories: [], totalCount: 0)
}

private struct ConfluencePagePreview {
    var visiblePages: [ConfluencePage]
    var totalCount: Int

    static let empty = ConfluencePagePreview(visiblePages: [], totalCount: 0)
}

private struct ConfluencePagePreviewRevision: Equatable {
    var searchText: String
    var visibleLimit: Int
    var confluencePageHash: Int
}

private struct KnowledgeViewSnapshot {
    var entryPreview: KnowledgeEntryPreview
    var reportKnowledgePreview: ReportKnowledgeMemoryPreview

    static let empty = KnowledgeViewSnapshot(
        entryPreview: .empty,
        reportKnowledgePreview: .empty
    )
}

private struct KnowledgeViewRevision: Equatable {
    var selectedBusinessSpaceID: UUID?
    var searchText: String
    var knowledgeFilter: KnowledgeFilter
    var knowledgeVisibleLimit: Int
    var reportKnowledgeVisibleLimit: Int
    var knowledgeEntryHash: Int
    var reportKnowledgeMemoryHash: Int
}

struct KnowledgeView: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    @State private var searchText = ""
    @State private var knowledgeVisibleLimit = 80
    @State private var reportKnowledgeVisibleLimit = 80
    @State private var knowledgeFilter: KnowledgeFilter = .all
    @State private var isKnowledgePreviewReady = false
    @State private var knowledgeSnapshot = KnowledgeViewSnapshot.empty
    @State private var knowledgeSnapshotRevision: KnowledgeViewRevision?
    @State private var knowledgeSnapshotRefreshTask: Task<Void, Never>?
    @State private var knowledgeSnapshotWarmupTask: Task<Void, Never>?
    @State private var showingDingTalkCreateSheet = false
    @State private var showingJiraCreateSheet = false
    @State private var showingTableauCreateSheet = false

    var body: some View {
        ScrollView {
            let entryPreview = knowledgeSnapshot.entryPreview
            let reportKnowledgePreview = knowledgeSnapshot.reportKnowledgePreview
            VStack(alignment: .leading, spacing: 18) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        knowledgeTitle
                        Spacer()
                        addKnowledgeButton
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        knowledgeTitle
                        addKnowledgeButton
                    }
                }

                localKnowledgeSourcesSection

                tableauSourcesSection

                dingtalkDocumentSourcesSection

                jiraProjectSourcesSection

                ConfluenceLibrarySection(
                    confluenceKnowledgeCount: entryPreview.confluenceCount,
                    reportKnowledgeCount: entryPreview.reportCount
                )

                SectionCard(title: "复盘经验", systemImage: "books.vertical") {
                    Picker("知识类型", selection: $knowledgeFilter) {
                        ForEach(KnowledgeFilter.allCases) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .hoverControlShell(.segmentedShell)

                    AdaptiveTextField(placeholder: "搜索场景、标题、结果或来源", text: $searchText, minLines: 1, maxLines: 2)

                    let entries = entryPreview.visibleEntries
                    if !isKnowledgePreviewReady {
                        Text("正在加载知识条目...")
                            .foregroundStyle(.secondary)
                    } else if entryPreview.totalCount == 0 {
                        Text("暂无知识条目。每次上线复盘后，把动作、结果和适用条件沉淀到这里。")
                            .foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Text("显示 \(entries.count)/\(entryPreview.totalCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }

                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(entries) { entry in
                                KnowledgeEntryRow(entry: entry) {
                                    store.deleteKnowledgeEntry(entry)
                                }
                                Divider()
                            }
                        }

                        if entries.count < entryPreview.totalCount {
                            HStack {
                                Button {
                                    knowledgeVisibleLimit += 80
                                } label: {
                                    Label("显示更多", systemImage: "chevron.down")
                                }

                                Button {
                                    knowledgeVisibleLimit = entryPreview.totalCount
                                } label: {
                                    Label("显示全部", systemImage: "list.bullet")
                                }
                            }
                        }
                    }
                }

                SectionCard(title: "报表知识规则", systemImage: "tablecells.badge.ellipsis") {
                    if !isKnowledgePreviewReady {
                        Text("正在加载报表知识...")
                            .foregroundStyle(.secondary)
                    } else if reportKnowledgePreview.totalCount == 0 {
                        Text("暂无报表问答沉淀规则。")
                            .foregroundStyle(.secondary)
                    } else {
                        let visibleMemories = reportKnowledgePreview.visibleMemories
                        HStack {
                            Text("显示 \(visibleMemories.count)/\(reportKnowledgePreview.totalCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }

                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(visibleMemories) { memory in
                                ReportKnowledgeMemoryRow(memory: memory) {
                                    store.setReportKnowledgeMemoryArchived(memory, archived: !memory.isArchived)
                                }
                                Divider()
                            }
                        }

                        if visibleMemories.count < reportKnowledgePreview.totalCount {
                            HStack {
                                Button {
                                    reportKnowledgeVisibleLimit += 80
                                } label: {
                                    Label("显示更多", systemImage: "chevron.down")
                                }

                                Button {
                                    reportKnowledgeVisibleLimit = reportKnowledgePreview.totalCount
                                } label: {
                                    Label("显示全部", systemImage: "list.bullet")
                                }
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
        .sheet(isPresented: $showingDingTalkCreateSheet) {
            DingTalkDocumentSourceCreateSheet { draft in
                store.createDingTalkDocumentSource(draft)
            }
        }
        .sheet(isPresented: $showingJiraCreateSheet) {
            JiraProjectSourceCreateSheet { draft in
                store.createJiraProjectSource(draft)
            }
        }
        .sheet(isPresented: $showingTableauCreateSheet) {
            TableauSourceCreateSheet { draft in
                store.createTableauSource(draft)
            }
        }
        .onAppear {
            scheduleKnowledgeSnapshotWarmup()
        }
        .onReceive(store.$workspace) { _ in
            if isKnowledgePreviewReady {
                scheduleKnowledgeSnapshotRefresh()
            }
        }
        .onChange(of: searchText) { _ in
            isKnowledgePreviewReady = true
            scheduleKnowledgeSnapshotRefresh(delayNanoseconds: 120_000_000)
        }
        .onChange(of: knowledgeFilter) { _ in
            isKnowledgePreviewReady = true
            refreshKnowledgeSnapshot(force: true)
        }
        .onChange(of: knowledgeVisibleLimit) { _ in
            isKnowledgePreviewReady = true
            refreshKnowledgeSnapshot(force: true)
        }
        .onChange(of: reportKnowledgeVisibleLimit) { _ in
            isKnowledgePreviewReady = true
            refreshKnowledgeSnapshot(force: true)
        }
        .onDisappear {
            knowledgeSnapshotRefreshTask?.cancel()
            knowledgeSnapshotRefreshTask = nil
            knowledgeSnapshotWarmupTask?.cancel()
            knowledgeSnapshotWarmupTask = nil
            isKnowledgePreviewReady = false
        }
    }

    private var filteredEntries: [KnowledgeEntry] {
        filteredEntries(from: spaceScopedKnowledgeEntries)
    }

    private func filteredEntries(from entries: [KnowledgeEntry]) -> [KnowledgeEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = entries.filter { entry in
            switch knowledgeFilter {
            case .all: return true
            case .reportKnowledge: return isReportKnowledge(entry)
            case .reviewExperience: return !isReportKnowledge(entry)
            }
        }
        guard !query.isEmpty else { return base }
        return base.filter { entry in
            [
                entry.scenario,
                entry.problem,
                entry.action,
                entry.result,
                entry.relatedPackName,
                entry.tags.joined(separator: " ")
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    private var spaceScopedKnowledgeEntries: [KnowledgeEntry] {
        guard let spaceID = store.selectedBusinessSpace?.id else { return store.workspace.knowledgeEntries }
        return store.workspace.knowledgeEntries.filter { entry in
            entry.isGlobal || entry.businessSpaceID == spaceID
        }
    }

    private func makeKnowledgeSnapshot() -> KnowledgeViewSnapshot {
        let scopedKnowledgeEntries = spaceScopedKnowledgeEntries
        return KnowledgeViewSnapshot(
            entryPreview: knowledgeEntryPreview(from: scopedKnowledgeEntries, limit: knowledgeVisibleLimit),
            reportKnowledgePreview: reportKnowledgeMemoryPreview(limit: reportKnowledgeVisibleLimit)
        )
    }

    private func scheduleKnowledgeSnapshotRefresh(delayNanoseconds: UInt64 = 240_000_000) {
        knowledgeSnapshotRefreshTask?.cancel()
        knowledgeSnapshotRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            refreshKnowledgeSnapshot(force: false)
            knowledgeSnapshotRefreshTask = nil
        }
    }

    private func scheduleKnowledgeSnapshotWarmup(delayNanoseconds: UInt64 = 90_000_000) {
        knowledgeSnapshotWarmupTask?.cancel()
        isKnowledgePreviewReady = false
        knowledgeSnapshotWarmupTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            isKnowledgePreviewReady = true
            refreshKnowledgeSnapshot(force: true)
            knowledgeSnapshotWarmupTask = nil
        }
    }

    private func refreshKnowledgeSnapshot(force: Bool) {
        let revision = makeKnowledgeViewRevision()
        guard force || revision != knowledgeSnapshotRevision else { return }
        knowledgeSnapshot = makeKnowledgeSnapshot()
        knowledgeSnapshotRevision = revision
    }

    private func makeKnowledgeViewRevision() -> KnowledgeViewRevision {
        KnowledgeViewRevision(
            selectedBusinessSpaceID: store.workspace.selectedBusinessSpaceID,
            searchText: searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            knowledgeFilter: knowledgeFilter,
            knowledgeVisibleLimit: knowledgeVisibleLimit,
            reportKnowledgeVisibleLimit: reportKnowledgeVisibleLimit,
            knowledgeEntryHash: knowledgeEntrySignature(),
            reportKnowledgeMemoryHash: reportKnowledgeMemorySignature()
        )
    }

    private func knowledgeEntrySignature() -> Int {
        var hasher = Hasher()
        hasher.combine(store.workspace.knowledgeEntries.count)
        for entry in store.workspace.knowledgeEntries {
            hasher.combine(entry.id)
            hasher.combine(entry.createdAt)
            hasher.combine(entry.businessSpaceID)
            hasher.combine(entry.rootPageID)
            hasher.combine(entry.isGlobal)
            hasher.combine(entry.evidenceLevel)
            hasher.combine(entry.sourceID)
            hasher.combine(entry.sourceUpdatedAt)
            hasher.combine(entry.tags.count)
            hasher.combine(entry.scenario.count)
            hasher.combine(entry.problem.count)
            hasher.combine(entry.action.count)
            hasher.combine(entry.result.count)
        }
        return hasher.finalize()
    }

    private func reportKnowledgeMemorySignature() -> Int {
        var hasher = Hasher()
        hasher.combine(store.workspace.reportKnowledgeMemories.count)
        for memory in store.workspace.reportKnowledgeMemories {
            hasher.combine(memory.id)
            hasher.combine(memory.updatedAt)
            hasher.combine(memory.reportKind)
            hasher.combine(memory.reportShape)
            hasher.combine(memory.sourceFormat)
            hasher.combine(memory.fieldKeywords.count)
            hasher.combine(memory.knowledgeEntryID)
            hasher.combine(memory.hitCount)
            hasher.combine(memory.lastMatchedAt)
            hasher.combine(memory.isArchived)
        }
        return hasher.finalize()
    }

    private func isReportKnowledge(_ entry: KnowledgeEntry) -> Bool {
        entry.tags.contains { $0.normalizedKey.contains("报表知识".normalizedKey) || $0.normalizedKey.contains("ai问答沉淀".normalizedKey) }
    }

    private func knowledgeEntryPreview(from entries: [KnowledgeEntry], limit: Int) -> KnowledgeEntryPreview {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var visibleEntries: [KnowledgeEntry] = []
        visibleEntries.reserveCapacity(limit)
        var totalCount = 0
        var confluenceCount = 0
        var reportCount = 0

        for entry in entries {
            let isReportEntry = isReportKnowledge(entry)
            if isReportEntry {
                reportCount += 1
            } else if entry.sourceID != nil && entry.sourceID?.hasPrefix("report-memory-") != true {
                confluenceCount += 1
            }

            guard knowledgeEntry(entry, isReportEntry: isReportEntry, matchesFilter: knowledgeFilter) else {
                continue
            }
            guard query.isEmpty || knowledgeEntry(entry, matches: query) else {
                continue
            }

            totalCount += 1
            if visibleEntries.count < limit {
                visibleEntries.append(entry)
            }
        }

        return KnowledgeEntryPreview(
            visibleEntries: visibleEntries,
            totalCount: totalCount,
            confluenceCount: confluenceCount,
            reportCount: reportCount
        )
    }

    private func knowledgeEntry(_ entry: KnowledgeEntry, isReportEntry: Bool, matchesFilter filter: KnowledgeFilter) -> Bool {
        switch filter {
        case .all: return true
        case .reportKnowledge: return isReportEntry
        case .reviewExperience: return !isReportEntry
        }
    }

    private func knowledgeEntry(_ entry: KnowledgeEntry, matches query: String) -> Bool {
        [
            entry.scenario,
            entry.problem,
            entry.action,
            entry.result,
            entry.relatedPackName,
            entry.tags.joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()
        .contains(query)
    }

    private func reportKnowledgeMemoryPreview(limit: Int) -> ReportKnowledgeMemoryPreview {
        let memories = store.workspace.reportKnowledgeMemories
        if limit >= memories.count {
            return ReportKnowledgeMemoryPreview(
                visibleMemories: memories.sorted { $0.updatedAt > $1.updatedAt },
                totalCount: memories.count
            )
        }

        var visibleMemories: [ReportKnowledgeMemory] = []
        visibleMemories.reserveCapacity(limit)

        for memory in memories {
            insertReportKnowledgeMemory(memory, into: &visibleMemories, limit: limit)
        }

        return ReportKnowledgeMemoryPreview(
            visibleMemories: visibleMemories,
            totalCount: memories.count
        )
    }

    private func insertReportKnowledgeMemory(_ memory: ReportKnowledgeMemory, into memories: inout [ReportKnowledgeMemory], limit: Int) {
        guard limit > 0 else { return }
        if memories.count == limit,
           let last = memories.last,
           memory.updatedAt <= last.updatedAt {
            return
        }
        if let index = memories.firstIndex(where: { memory.updatedAt > $0.updatedAt }) {
            memories.insert(memory, at: index)
        } else {
            memories.append(memory)
        }
        if memories.count > limit {
            memories.removeLast()
        }
    }

    private var knowledgeTitle: some View {
        Text("产品知识库")
            .font(.largeTitle)
            .fontWeight(.semibold)
    }

    private var addKnowledgeButton: some View {
        Button {
            store.addKnowledgeFromSelectedPack()
        } label: {
            Label("从当前分析沉淀", systemImage: "plus")
        }
        .disabled(store.selectedPack == nil)
    }

    private var localKnowledgeSourcesSection: some View {
        SectionCard(title: "本地文件夹知识源", systemImage: "folder.badge.gearshape") {
            let sources = store.localKnowledgeFolderSourcesForSelectedBusinessSpace
            let syncRecords = store.localKnowledgeFolderSyncRecordsForSelectedBusinessSpace
            let enabledSources = sources.filter(\.isEnabled)

            LazyVGrid(columns: knowledgeSummaryColumns, spacing: 12) {
                KnowledgeSummaryTile(title: "已绑定文件夹", value: "\(sources.count)", systemImage: "folder")
                KnowledgeSummaryTile(title: "已启用", value: "\(enabledSources.count)", systemImage: "checkmark.circle")
                KnowledgeSummaryTile(title: "同步记录", value: "\(syncRecords.count)", systemImage: "clock.arrow.circlepath")
                KnowledgeSummaryTile(title: "自动同步", value: "每天 18:00", systemImage: "calendar.badge.clock", helpText: "App 运行时到 18:00 自动同步；错过后下次打开 App 会补同步一次。")
            }

            Text("本地文件夹知识只属于当前业务空间。支持 csv/xlsx/xls/md/txt/json/pdf/docx；同步只读取文件，不修改原文件。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ResponsiveStack(compactBreakpoint: 620, spacing: 8) {
                Button {
                    store.addLocalKnowledgeFolderSource()
                } label: {
                    Label("添加本地文件夹", systemImage: "folder.badge.plus")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .primary))

                Button {
                    store.syncAllEnabledLocalKnowledgeFoldersForSelectedSpace()
                } label: {
                    Label("同步已启用文件夹", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .secondary))
                .disabled(enabledSources.isEmpty)

            }

            if sources.isEmpty {
                Text("还没有绑定本地知识文件夹。添加后可以手动同步，也可以启用每天 18:00 自动同步。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sources) { source in
                        LocalKnowledgeFolderSourceRow(source: source)
                            .environmentObject(store)
                        Divider()
                    }
                }
            }

            LocalKnowledgeSyncHistory(records: Array(syncRecords.prefix(8)))
        }
    }

    private var dingtalkDocumentSourcesSection: some View {
        SectionCard(title: "钉钉文档源", systemImage: "doc.text.magnifyingglass") {
            let sources = store.dingtalkDocumentSourcesForSelectedBusinessSpace
            let items = store.dingtalkDocumentItemsForSelectedBusinessSpace
            let syncRecords = store.dingtalkDocumentSyncRecordsForSelectedBusinessSpace
            let enabledSources = sources.filter(\.isEnabled)

            LazyVGrid(columns: knowledgeSummaryColumns, spacing: 12) {
                KnowledgeSummaryTile(title: "已绑定源", value: "\(sources.count)", systemImage: "doc.text")
                KnowledgeSummaryTile(title: "已启用", value: "\(enabledSources.count)", systemImage: "checkmark.circle")
                KnowledgeSummaryTile(title: "文档证据", value: "\(items.count)", systemImage: "doc.on.doc")
                KnowledgeSummaryTile(title: "同步记录", value: "\(syncRecords.count)", systemImage: "clock.arrow.circlepath")
            }

            Text("钉钉文档源绑定到当前业务空间。同步在线文档和在线表格时，Client Secret 只保存在本地 workspace，不进入 AI Prompt、日志或导出文件；文档创建/更新时间不能自动等同真实上线时间。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ResponsiveStack(compactBreakpoint: 620, spacing: 8) {
                Button {
                    showingDingTalkCreateSheet = true
                } label: {
                    Label("添加钉钉文档源", systemImage: "plus")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .primary))

                Button {
                    store.syncAllEnabledDingTalkDocumentSourcesForSelectedSpace()
                } label: {
                    Label("同步已启用钉钉源", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .secondary))
                .disabled(enabledSources.isEmpty)
            }

            if sources.isEmpty {
                Text("还没有绑定钉钉文件夹。添加后可以测试连接、手动同步，也可以启用每天 18:00 自动同步。第一版以文件夹为入口，支持多个文件夹链接或 ID。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sources) { source in
                        DingTalkDocumentSourceRow(source: source)
                            .environmentObject(store)
                        Divider()
                    }
                }
            }

            DingTalkDocumentSyncHistory(records: Array(syncRecords.prefix(8)))

            let recentItems = Array(items.prefix(8))
            if !recentItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("最近钉钉文档证据")
                        .font(.headline)
                    ForEach(recentItems) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Badge(text: item.kind.label, systemImage: nil, tint: AppTheme.warning)
                                Text(item.title)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                Spacer()
                                if let url = URL(string: item.sourceURL), !item.sourceURL.isEmpty {
                                    Link("打开", destination: url)
                                        .font(.caption)
                                }
                            }
                            Text("\(item.timingSummary) · \(item.contentStatus)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
        }
    }

    private var tableauSourcesSection: some View {
        SectionCard(title: "Tableau 数据源", systemImage: "chart.bar.doc.horizontal") {
            let sources = store.tableauSourcesForSelectedBusinessSpace
            let syncRecords = store.tableauSyncRecordsForSelectedBusinessSpace
            let enabledSources = sources.filter(\.isEnabled)

            LazyVGrid(columns: knowledgeSummaryColumns, spacing: 12) {
                KnowledgeSummaryTile(title: "已绑定连接", value: "\(sources.count)", systemImage: "chart.bar.doc.horizontal")
                KnowledgeSummaryTile(title: "已启用", value: "\(enabledSources.count)", systemImage: "checkmark.circle")
                KnowledgeSummaryTile(title: "导入记录", value: "\(syncRecords.count)", systemImage: "clock.arrow.circlepath")
                KnowledgeSummaryTile(
                    title: "导入方式",
                    value: "View Export",
                    systemImage: "tablecells",
                    helpText: "第一版导入 Tableau View / Worksheet 导出的 Crosstab/CSV 数据，不等同底层完整数据源。"
                )
            }

            Text("Tableau 连接绑定到当前业务空间。PAT Token 只保存在本地 workspace，不进入 AI Prompt、日志或导出文件；导入表会进入当前分析资料，和本地表格一起分析。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ResponsiveStack(compactBreakpoint: 620, spacing: 8) {
                Button {
                    showingTableauCreateSheet = true
                } label: {
                    SemanticLabel(title: "添加 Tableau 连接", systemImage: "plus", role: .data)
                }
                .buttonStyle(AppHoverButtonStyle(variant: .primary))
            }

            if sources.isEmpty {
                Text("还没有绑定 Tableau 连接。添加后可在“分析资料”中选择 View 导入并直接进入分析会话。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sources) { source in
                        TableauSourceRow(source: source)
                            .environmentObject(store)
                        Divider()
                    }
                }
            }

            if !syncRecords.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("最近 Tableau 导入记录")
                        .font(.headline)
                    ForEach(Array(syncRecords.prefix(8))) { record in
                        HStack {
                            Badge(text: record.status.label, systemImage: nil, tint: record.status == .success ? AppTheme.success : AppTheme.danger)
                            Text(DateFormatting.shortDateTime.string(from: record.finishedAt))
                                .fontWeight(.medium)
                            Text("导入 \(record.importedViewCount) 个 View")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(record.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Divider()
                    }
                }
            }
        }
    }

    private var jiraProjectSourcesSection: some View {
        SectionCard(title: "Jira 项目状态源", systemImage: "checklist") {
            let sources = store.jiraProjectSourcesForSelectedBusinessSpace
            let evidences = store.jiraProjectEvidencesForSelectedBusinessSpace
            let syncRecords = store.jiraProjectSyncRecordsForSelectedBusinessSpace
            let enabledSources = sources.filter(\.isEnabled)

            LazyVGrid(columns: knowledgeSummaryColumns, spacing: 12) {
                KnowledgeSummaryTile(title: "已绑定项目", value: "\(sources.count)", systemImage: "checklist")
                KnowledgeSummaryTile(title: "已启用", value: "\(enabledSources.count)", systemImage: "checkmark.circle")
                KnowledgeSummaryTile(title: "项目证据", value: "\(evidences.count)", systemImage: "doc.text.magnifyingglass")
                KnowledgeSummaryTile(title: "同步记录", value: "\(syncRecords.count)", systemImage: "clock.arrow.circlepath")
            }

            Text("Jira 属于当前业务空间的内部项目证据，用于佐证需求、Bug、版本、Sprint 和状态流转；Jira 创建/更新时间不能自动等同真实上线时间。Token 只保存在本地 workspace，不会发送给 AI。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ResponsiveStack(compactBreakpoint: 620, spacing: 8) {
                Button {
                    showingJiraCreateSheet = true
                } label: {
                    Label("添加 Jira 连接", systemImage: "plus")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .primary))

                Button {
                    store.syncAllEnabledJiraProjectSourcesForSelectedSpace()
                } label: {
                    Label("同步已启用 Jira", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .secondary))
                .disabled(enabledSources.isEmpty)
            }

            if sources.isEmpty {
                Text("还没有绑定 Jira 项目。添加后可以测试连接、手动同步，也可以启用每天 18:00 自动同步。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sources) { source in
                        JiraProjectSourceRow(source: source)
                            .environmentObject(store)
                        Divider()
                    }
                }
            }

            JiraProjectSyncHistory(records: Array(syncRecords.prefix(8)))

            let recentEvidence = Array(evidences.prefix(8))
            if !recentEvidence.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("最近 Jira 项目证据")
                        .font(.headline)
                    ForEach(recentEvidence) { evidence in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Badge(text: evidence.status.nilIfBlank ?? "未知状态", systemImage: nil, tint: AppTheme.accent)
                                Text(evidence.compactSummary)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                Spacer()
                                if let url = URL(string: evidence.issueURL) {
                                    Link("Jira", destination: url)
                                        .font(.caption)
                                }
                            }
                            Text(evidence.timingSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
        }
    }

    private var knowledgeSummaryColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 190), spacing: 12)]
    }
}

private struct ConfluenceLibrarySection: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    var confluenceKnowledgeCount: Int
    var reportKnowledgeCount: Int
    @State private var searchText = ""
    @State private var visibleLimit = 80
    @State private var isPagePreviewReady = false
    @State private var pagePreview = ConfluencePagePreview.empty
    @State private var pagePreviewRevision: ConfluencePagePreviewRevision?
    @State private var pagePreviewRefreshTask: Task<Void, Never>?
    @State private var pagePreviewWarmupTask: Task<Void, Never>?

    var body: some View {
        SectionCard(title: "Confluence 文档库", systemImage: "doc.text.magnifyingglass") {
            LazyVGrid(columns: knowledgeSummaryColumns, spacing: 12) {
                KnowledgeSummaryTile(title: "已同步页面", value: "\(store.workspace.confluencePages.count)", systemImage: "doc.richtext")
                KnowledgeSummaryTile(title: "Confluence 条目", value: "\(confluenceKnowledgeCount)", systemImage: "books.vertical")
                KnowledgeSummaryTile(title: "报表知识", value: "\(reportKnowledgeCount)", systemImage: "tablecells.badge.ellipsis")
                KnowledgeSummaryTile(
                    title: "最后同步",
                    value: lastConfluenceSyncInfo.summary,
                    systemImage: "clock.arrow.circlepath",
                    helpText: lastConfluenceSyncInfo.detail
                )
                KnowledgeSummaryTile(
                    title: "根页面",
                    value: confluenceRootPageSummary,
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                    helpText: confluenceRootPageDetail
                )
            }

            if !store.workspace.confluenceSettings.parsedTitleKeywords.isEmpty {
                Text("当前标题过滤：\(store.workspace.confluenceSettings.parsedTitleKeywords.joined(separator: "、"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ResponsiveStack(compactBreakpoint: 520, spacing: 8) {
                confluenceButtons
            }

            ConfluenceSyncHistory(records: Array(store.workspace.confluenceSyncRecords.prefix(12)))

            if store.workspace.confluencePages.isEmpty,
               store.workspace.confluenceSyncRecords.isEmpty {
                Text("暂无同步记录。可以直接读取已有 `sufinc_credit_card_confluence/pages.json`，也可以在 AI 设置里填写 Confluence Token 后直接同步页面树。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if store.workspace.confluencePages.isEmpty {
                Text("当前没有已同步页面。历史同步结果会保留在上方记录里；如需恢复本地导出的页面，请点击“导入 pages.json”。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                AdaptiveTextField(placeholder: "搜索已同步页面标题、场景、空间或 URL", text: $searchText, minLines: 1, maxLines: 2)

                let visiblePages = pagePreview.visiblePages
                if !isPagePreviewReady {
                    Text("正在加载页面清单...")
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text("完整页面清单")
                            .font(.headline)
                        Spacer()
                        Text("显示 \(visiblePages.count)/\(pagePreview.totalCount)，总计 \(store.workspace.confluencePages.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visiblePages) { page in
                            ConfluencePageRow(page: page)
                            Divider()
                        }
                    }

                    if visiblePages.count < pagePreview.totalCount {
                        HStack {
                            Button {
                                visibleLimit += 80
                            } label: {
                                Label("显示更多", systemImage: "chevron.down")
                            }

                            Button {
                                visibleLimit = pagePreview.totalCount
                            } label: {
                                Label("显示全部", systemImage: "list.bullet")
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            schedulePagePreviewWarmup()
        }
        .onReceive(store.$workspace) { _ in
            if isPagePreviewReady {
                schedulePagePreviewRefresh()
            }
        }
        .onChange(of: searchText) { _ in
            isPagePreviewReady = true
            schedulePagePreviewRefresh(delayNanoseconds: 120_000_000)
        }
        .onChange(of: visibleLimit) { _ in
            isPagePreviewReady = true
            refreshPagePreview(force: true)
        }
        .onDisappear {
            pagePreviewRefreshTask?.cancel()
            pagePreviewRefreshTask = nil
            pagePreviewWarmupTask?.cancel()
            pagePreviewWarmupTask = nil
            isPagePreviewReady = false
        }
    }

    private var knowledgeSummaryColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 190), spacing: 12)]
    }

    private var confluenceButtons: some View {
        Group {
            Button {
                store.importConfluencePagesFromJSON()
            } label: {
                Label("导入 pages.json", systemImage: "doc.badge.plus")
            }
            .disabled(store.isSyncingConfluence)

            Button {
                store.syncConfluenceTree()
            } label: {
                Label(store.isSyncingConfluence ? "同步中" : "同步 Confluence", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(store.isSyncingConfluence)

            Button {
                store.mergeConfluenceKnowledgeEntries()
            } label: {
                Label("重新沉淀知识库", systemImage: "books.vertical")
            }
            .disabled(store.workspace.confluencePages.isEmpty)
        }
    }

    private func confluencePagePreview(limit: Int) -> ConfluencePagePreview {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pages = store.workspace.confluencePages
        if limit >= pages.count {
            let matched = query.isEmpty ? pages : pages.filter { confluencePage($0, matches: query) }
            return ConfluencePagePreview(
                visiblePages: matched.sorted(by: confluencePageSortsBefore),
                totalCount: matched.count
            )
        }

        var visiblePages: [ConfluencePage] = []
        visiblePages.reserveCapacity(limit)
        var totalCount = 0

        for page in pages {
            guard query.isEmpty || confluencePage(page, matches: query) else { continue }
            totalCount += 1
            insertConfluencePage(page, into: &visiblePages, limit: limit)
        }

        return ConfluencePagePreview(visiblePages: visiblePages, totalCount: totalCount)
    }

    private func schedulePagePreviewRefresh(delayNanoseconds: UInt64 = 240_000_000) {
        pagePreviewRefreshTask?.cancel()
        pagePreviewRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            refreshPagePreview(force: false)
            pagePreviewRefreshTask = nil
        }
    }

    private func schedulePagePreviewWarmup(delayNanoseconds: UInt64 = 90_000_000) {
        pagePreviewWarmupTask?.cancel()
        isPagePreviewReady = false
        pagePreviewWarmupTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            isPagePreviewReady = true
            refreshPagePreview(force: true)
            pagePreviewWarmupTask = nil
        }
    }

    private func refreshPagePreview(force: Bool) {
        let revision = makePagePreviewRevision()
        guard force || revision != pagePreviewRevision else { return }
        pagePreview = confluencePagePreview(limit: visibleLimit)
        pagePreviewRevision = revision
    }

    private func makePagePreviewRevision() -> ConfluencePagePreviewRevision {
        ConfluencePagePreviewRevision(
            searchText: searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            visibleLimit: visibleLimit,
            confluencePageHash: confluencePageSignature()
        )
    }

    private func confluencePageSignature() -> Int {
        var hasher = Hasher()
        hasher.combine(store.workspace.confluencePages.count)
        for page in store.workspace.confluencePages {
            hasher.combine(page.id)
            hasher.combine(page.title)
            hasher.combine(page.spaceKey)
            hasher.combine(page.lastUpdated)
            hasher.combine(page.syncedAt)
            hasher.combine(page.version)
            hasher.combine(page.labels.count)
            hasher.combine(page.charCount)
        }
        return hasher.finalize()
    }

    private func confluencePage(_ page: ConfluencePage, matches query: String) -> Bool {
        [
            page.title,
            page.spaceName,
            page.spaceKey,
            page.url,
            page.labels.joined(separator: " "),
            page.ancestors.joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()
        .contains(query)
    }

    private func insertConfluencePage(_ page: ConfluencePage, into pages: inout [ConfluencePage], limit: Int) {
        guard limit > 0 else { return }
        if pages.count == limit,
           let last = pages.last,
           !confluencePageSortsBefore(page, last) {
            return
        }
        if let index = pages.firstIndex(where: { confluencePageSortsBefore(page, $0) }) {
            pages.insert(page, at: index)
        } else {
            pages.append(page)
        }
        if pages.count > limit {
            pages.removeLast()
        }
    }

    private func confluencePageSortsBefore(_ lhs: ConfluencePage, _ rhs: ConfluencePage) -> Bool {
        let lhsSyncedAt = lhs.syncedAt ?? .distantPast
        let rhsSyncedAt = rhs.syncedAt ?? .distantPast
        if lhsSyncedAt != rhsSyncedAt {
            return lhsSyncedAt > rhsSyncedAt
        }
        return (lhs.lastUpdated ?? lhs.createdAt ?? .distantPast) > (rhs.lastUpdated ?? rhs.createdAt ?? .distantPast)
    }

    private var lastConfluenceSyncInfo: (summary: String, detail: String) {
        if let record = store.workspace.confluenceSyncRecords.first {
            let dateText = DateFormatting.shortDateTime.string(from: record.finishedAt)
            return (dateText, "最后同步：\(record.status.label) · \(dateText)")
        }

        var latestSyncedAt: Date?
        for page in store.workspace.confluencePages {
            guard let syncedAt = page.syncedAt else { continue }
            if latestSyncedAt == nil || syncedAt > latestSyncedAt! {
                latestSyncedAt = syncedAt
            }
        }

        guard let latestSyncedAt else {
            return ("未同步", "最后同步：未同步")
        }
        let dateText = DateFormatting.shortDateTime.string(from: latestSyncedAt)
        return (dateText, "页面最近同步时间：\(dateText)")
    }

    private var confluenceRootPageIDs: [String] {
        store.workspace.confluenceSettings.rootPageIDs
            .components(separatedBy: CharacterSet(charactersIn: ",，;；\n\t "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var confluenceRootPageSummary: String {
        let ids = confluenceRootPageIDs
        guard !ids.isEmpty else { return "未配置" }
        return ids.count == 1 ? ids[0] : "\(ids.count) 个"
    }

    private var confluenceRootPageDetail: String {
        let ids = confluenceRootPageIDs
        guard !ids.isEmpty else { return "未配置 Root Page ID，导入时会使用默认范围。" }
        return "Root Page ID：\(ids.joined(separator: "、"))"
    }
}

private enum KnowledgeFilter: String, CaseIterable, Identifiable {
    case all
    case reportKnowledge
    case reviewExperience

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "全部"
        case .reportKnowledge: return "报表知识"
        case .reviewExperience: return "复盘/文档"
        }
    }
}

private struct KnowledgeSummaryTile: View {
    var title: String
    var value: String
    var systemImage: String
    var helpText: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SemanticIcon(systemName: systemImage, size: 22, frameWidth: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .padding(12)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .help(helpText ?? "\(title)：\(value)")
    }
}

private struct ConfluenceSyncHistory: View {
    var records: [ConfluenceSyncRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("同步记录")
                    .font(.headline)
                Spacer()
                Text(records.isEmpty ? "暂无" : "最近 \(records.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if records.isEmpty {
                Text("同步或导入后会在这里保留来源、时间、命中页数和知识库沉淀结果。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(records) { record in
                        ConfluenceSyncRecordRow(record: record)
                        Divider()
                    }
                }
            }
        }
        .padding(10)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }
}

private struct LocalKnowledgeFolderSourceRow: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    var source: LocalKnowledgeFolderSource

    private var isSyncing: Bool {
        store.syncingLocalKnowledgeFolderSourceIDs.contains(source.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ResponsiveStack(compactBreakpoint: 720, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        SemanticIcon(systemName: "folder", role: .knowledge)
                        Text(source.displayName)
                            .font(.headline)
                        Badge(text: source.isEnabled ? "已启用" : "已停用", systemImage: nil, tint: source.isEnabled ? AppTheme.success : .gray)
                        Badge(text: source.syncSchedule.label, systemImage: nil, tint: AppTheme.accent)
                    }
                    Text(source.folderPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)

                Toggle("启用", isOn: Binding(
                    get: { source.isEnabled },
                    set: { enabled in
                        store.updateLocalKnowledgeFolderSource(source) { $0.isEnabled = enabled }
                    }
                ))
                .toggleStyle(.checkbox)

                Picker("同步方式", selection: Binding(
                    get: { source.syncSchedule },
                    set: { schedule in
                        store.updateLocalKnowledgeFolderSource(source) { $0.syncSchedule = schedule }
                    }
                )) {
                    ForEach(KnowledgeSyncSchedule.allCases, id: \.self) { schedule in
                        Text(schedule.label).tag(schedule)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
                .hoverControlShell(.pickerShell)

                Button {
                    store.syncLocalKnowledgeFolderSource(source)
                } label: {
                    Label(isSyncing ? "同步中" : "同步", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .secondary))
                .disabled(isSyncing)

                Button {
                    store.deleteLocalKnowledgeFolderSource(source)
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .danger))
            }

            HStack(spacing: 12) {
                Text("最近同步：\(source.lastSyncAt.map { DateFormatting.shortDateTime.string(from: $0) } ?? "未同步")")
                Text("文件 \(source.lastFileCount)")
                Text("新增 \(source.lastAddedCount)")
                Text("更新 \(source.lastUpdatedCount)")
                if source.lastFailedCount > 0 {
                    Text("失败 \(source.lastFailedCount)")
                        .foregroundStyle(AppTheme.danger)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }
}

private struct LocalKnowledgeSyncHistory: View {
    var records: [LocalKnowledgeFolderSyncRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("本地文件夹同步记录")
                    .font(.headline)
                Spacer()
                Text(records.isEmpty ? "暂无" : "最近 \(records.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if records.isEmpty {
                Text("手动同步或 18:00 自动同步后，会在这里记录文件数、知识库新增/更新数量和失败原因。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(records) { record in
                        HStack(alignment: .top, spacing: 10) {
                            SemanticIcon(systemName: record.status == .success ? "checkmark.circle" : "exclamationmark.triangle", role: record.status == .success ? .success : .risk)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Badge(text: record.status.label, systemImage: nil, tint: record.status == .success ? AppTheme.success : AppTheme.danger)
                                    Text(DateFormatting.shortDateTime.string(from: record.finishedAt))
                                        .fontWeight(.semibold)
                                }
                                Text("文件 \(record.totalFiles) · 支持 \(record.supportedFiles) · 新增 \(record.addedKnowledgeEntries) · 更新 \(record.updatedKnowledgeEntries) · 失败 \(record.failedFiles)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(record.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }
                }
            }
        }
    }
}

private struct DingTalkDocumentSourceCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = DingTalkDocumentSourceDraft()
    var onSave: (DingTalkDocumentSourceDraft) -> Void

    private var canSave: Bool {
        !draft.clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.operatorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.folderInputs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SemanticLabel(title: "添加钉钉文档源", systemImage: "doc.text.magnifyingglass", role: .knowledge)
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(AppHoverButtonStyle(variant: .secondary))
            }

            Form {
                TextField("显示名称，例如 墨西哥信用卡钉钉文档", text: $draft.displayName)
                TextField("Client ID", text: $draft.clientID)
                SecureField("Client Secret", text: $draft.clientSecret)
                TextField("AgentId（可选）", text: $draft.agentID)
                TextField("操作人 User ID（operatorId，必填）", text: $draft.operatorID)
                TextField("默认 Space ID（文件夹链接解析不到时使用，可选）", text: $draft.defaultSpaceID)
                TextEditor(text: $draft.folderInputs)
                    .frame(minHeight: 80)
                    .overlay(alignment: .topLeading) {
                        if draft.folderInputs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("每行一个钉钉文件夹链接或文件夹 ID")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
                TextField("标题关键词，可选，用逗号分隔", text: $draft.titleKeywords)
                TextField("标题排除词，可选，用逗号分隔", text: $draft.excludedTitleKeywords)
                Picker("同步方式", selection: $draft.syncSchedule) {
                    ForEach(KnowledgeSyncSchedule.allCases, id: \.self) { schedule in
                        Text(schedule.label).tag(schedule)
                    }
                }
                Stepper("单次最多 \(draft.maxDocuments) 个文档", value: $draft.maxDocuments, in: 1...500, step: 25)
            }

            Text("需要钉钉开放平台文档读取、在线表格读取、文件夹/目录读取权限。operatorId 是有文档访问权限的钉钉用户 UserID，不是 AgentId。Token 和 Client Secret 只保存在本地，不会进入 AI Prompt 或同步日志。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("保存连接") {
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(AppHoverButtonStyle(variant: .primary))
                .disabled(!canSave)
            }
        }
        .padding(22)
        .frame(width: 720, height: 660)
    }
}

private struct DingTalkDocumentSourceEditableDraft: Equatable {
    var isEnabled: Bool
    var displayName: String
    var clientID: String
    var clientSecret: String
    var agentID: String
    var operatorID: String
    var defaultSpaceID: String
    var folderInputs: String
    var titleKeywords: String
    var excludedTitleKeywords: String
    var syncSchedule: KnowledgeSyncSchedule
    var maxDocuments: Int

    init(_ source: DingTalkDocumentSource) {
        self.isEnabled = source.isEnabled
        self.displayName = source.displayName
        self.clientID = source.clientID
        self.clientSecret = source.clientSecret
        self.agentID = source.agentID
        self.operatorID = source.operatorID ?? ""
        self.defaultSpaceID = source.defaultSpaceID
        self.folderInputs = source.folderInputs
        self.titleKeywords = source.titleKeywords
        self.excludedTitleKeywords = source.excludedTitleKeywords
        self.syncSchedule = source.syncSchedule
        self.maxDocuments = source.maxDocuments
    }

    var normalizedOperatorID: String? {
        operatorID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }
}

private struct DingTalkDocumentSourceRow: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    var source: DingTalkDocumentSource
    @State private var draft: DingTalkDocumentSourceEditableDraft
    @State private var lastCommittedDraft: DingTalkDocumentSourceEditableDraft
    @State private var commitTask: Task<Void, Never>?

    init(source: DingTalkDocumentSource) {
        self.source = source
        let initialDraft = DingTalkDocumentSourceEditableDraft(source)
        _draft = State(initialValue: initialDraft)
        _lastCommittedDraft = State(initialValue: initialDraft)
    }

    private var isTesting: Bool {
        store.testingDingTalkDocumentSourceIDs.contains(source.id)
    }

    private var isSyncing: Bool {
        store.syncingDingTalkDocumentSourceIDs.contains(source.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SemanticIcon(systemName: "doc.text.magnifyingglass", role: .knowledge)
                Text(draft.displayName.nilIfBlank ?? "钉钉文档源")
                    .font(.headline)
                Badge(text: draft.isEnabled ? "已启用" : "已停用", systemImage: nil, tint: draft.isEnabled ? AppTheme.success : .gray)
                Badge(text: draft.syncSchedule.label, systemImage: nil, tint: AppTheme.accent)
                Spacer()
                Toggle("启用", isOn: Binding(
                    get: { draft.isEnabled },
                    set: { updateDraft(\.isEnabled, value: $0) }
                ))
                .toggleStyle(.checkbox)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], spacing: 10) {
                TextField("显示名称", text: Binding(
                    get: { draft.displayName },
                    set: { updateDraft(\.displayName, value: $0) }
                ))
                TextField("Client ID", text: Binding(
                    get: { draft.clientID },
                    set: { updateDraft(\.clientID, value: $0) }
                ))
                SecureField("Client Secret", text: Binding(
                    get: { draft.clientSecret },
                    set: { updateDraft(\.clientSecret, value: $0) }
                ))
                TextField("AgentId（可选）", text: Binding(
                    get: { draft.agentID },
                    set: { updateDraft(\.agentID, value: $0) }
                ))
                TextField("操作人 User ID（operatorId，必填）", text: Binding(
                    get: { draft.operatorID },
                    set: { updateDraft(\.operatorID, value: $0) }
                ))
                TextField("默认 Space ID（可选）", text: Binding(
                    get: { draft.defaultSpaceID },
                    set: { updateDraft(\.defaultSpaceID, value: $0) }
                ))
            }

            if draft.normalizedOperatorID == nil {
                Text("请填写 operatorId：这是拥有该钉钉文件夹访问权限的用户 UserID。缺少它时，钉钉会返回 operatorId is mandatory。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("同步文件夹")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: Binding(
                    get: { draft.folderInputs },
                    set: { updateDraft(\.folderInputs, value: $0) }
                ))
                .frame(minHeight: 70)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], spacing: 10) {
                TextField("标题关键词，可选", text: Binding(
                    get: { draft.titleKeywords },
                    set: { updateDraft(\.titleKeywords, value: $0) }
                ))
                TextField("标题排除词，可选", text: Binding(
                    get: { draft.excludedTitleKeywords },
                    set: { updateDraft(\.excludedTitleKeywords, value: $0) }
                ))
            }

            ResponsiveStack(compactBreakpoint: 720, spacing: 8) {
                Picker("同步方式", selection: Binding(
                    get: { draft.syncSchedule },
                    set: { updateDraft(\.syncSchedule, value: $0) }
                )) {
                    ForEach(KnowledgeSyncSchedule.allCases, id: \.self) { schedule in
                        Text(schedule.label).tag(schedule)
                    }
                }
                .frame(width: 140)
                .hoverControlShell(.pickerShell)

                Stepper("最多 \(draft.maxDocuments) 个", value: Binding(
                    get: { draft.maxDocuments },
                    set: { updateDraft(\.maxDocuments, value: $0) }
                ), in: 1...500, step: 25)

                Button {
                    flushDraftToStore()
                    store.testDingTalkDocumentSource(sourceWithDraftValues())
                } label: {
                    Label(isTesting ? "测试中" : "测试连接", systemImage: "network")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .secondary))
                .disabled(isTesting || isSyncing)

                Button {
                    flushDraftToStore()
                    store.syncDingTalkDocumentSource(sourceWithDraftValues())
                } label: {
                    Label(isSyncing ? "同步中" : "手动同步", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .secondary))
                .disabled(isTesting || isSyncing || !draft.isEnabled)

                Button {
                    store.deleteDingTalkDocumentSource(source)
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .danger))
            }

            HStack(spacing: 12) {
                Text("最近同步：\(source.lastSyncAt.map { DateFormatting.shortDateTime.string(from: $0) } ?? "未同步")")
                Text("文档 \(source.lastDocumentCount)")
                Text("新增 \(source.lastAddedCount)")
                Text("更新 \(source.lastUpdatedCount)")
                Text("跳过 \(source.lastSkippedCount)")
                if source.lastFailedCount > 0 {
                    Text("失败 \(source.lastFailedCount)")
                        .foregroundStyle(AppTheme.danger)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("钉钉文档时间只代表文档记录：创建/更新时间不能自动等同真实上线、灰度或业务生效时间。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .onChange(of: source) { _ in
            resetDraftFromSource(force: false)
        }
        .onDisappear {
            flushDraftToStore()
        }
    }

    private func updateDraft<Value: Equatable>(_ keyPath: WritableKeyPath<DingTalkDocumentSourceEditableDraft, Value>, value: Value) {
        draft[keyPath: keyPath] = value
        scheduleDraftCommit(draft)
    }

    private func scheduleDraftCommit(_ pendingDraft: DingTalkDocumentSourceEditableDraft) {
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

    private func commitDraftToStore(_ draftToCommit: DingTalkDocumentSourceEditableDraft) {
        guard draftToCommit != lastCommittedDraft else { return }
        store.updateDingTalkDocumentSource(source) { source in
            source.isEnabled = draftToCommit.isEnabled
            source.displayName = draftToCommit.displayName
            source.clientID = draftToCommit.clientID
            source.clientSecret = draftToCommit.clientSecret
            source.agentID = draftToCommit.agentID
            source.operatorID = draftToCommit.operatorID.nilIfBlank
            source.defaultSpaceID = draftToCommit.defaultSpaceID
            source.folderInputs = draftToCommit.folderInputs
            source.titleKeywords = draftToCommit.titleKeywords
            source.excludedTitleKeywords = draftToCommit.excludedTitleKeywords
            source.syncSchedule = draftToCommit.syncSchedule
            source.maxDocuments = draftToCommit.maxDocuments
        }
        lastCommittedDraft = draftToCommit
    }

    private func resetDraftFromSource(force: Bool) {
        let latestDraft = DingTalkDocumentSourceEditableDraft(source)
        guard force || draft == lastCommittedDraft else { return }
        commitTask?.cancel()
        commitTask = nil
        draft = latestDraft
        lastCommittedDraft = latestDraft
    }

    private func sourceWithDraftValues() -> DingTalkDocumentSource {
        var copy = source
        copy.isEnabled = draft.isEnabled
        copy.displayName = draft.displayName
        copy.clientID = draft.clientID
        copy.clientSecret = draft.clientSecret
        copy.agentID = draft.agentID
        copy.operatorID = draft.operatorID.nilIfBlank
        copy.defaultSpaceID = draft.defaultSpaceID
        copy.folderInputs = draft.folderInputs
        copy.titleKeywords = draft.titleKeywords
        copy.excludedTitleKeywords = draft.excludedTitleKeywords
        copy.syncSchedule = draft.syncSchedule
        copy.maxDocuments = max(1, min(draft.maxDocuments, 500))
        return copy
    }
}

private struct DingTalkDocumentSyncHistory: View {
    var records: [DingTalkDocumentSyncRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("钉钉同步记录")
                    .font(.headline)
                Spacer()
                Text(records.isEmpty ? "暂无" : "最近 \(records.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if records.isEmpty {
                Text("测试或同步后会在这里记录文件夹数、文档数、知识库新增/更新数量和失败原因。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(records) { record in
                        HStack(alignment: .top, spacing: 10) {
                            SemanticIcon(systemName: record.status == .success ? "checkmark.circle" : "exclamationmark.triangle", role: record.status == .success ? .success : .risk)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Badge(text: record.status.label, systemImage: nil, tint: record.status == .success ? AppTheme.success : AppTheme.danger)
                                    Text(DateFormatting.shortDateTime.string(from: record.finishedAt))
                                        .fontWeight(.semibold)
                                }
                                Text("文件夹 \(record.folderCount) · 文档 \(record.totalDocuments) · 新增 \(record.addedKnowledgeEntries) · 更新 \(record.updatedKnowledgeEntries) · 跳过 \(record.skippedDocuments) · 失败 \(record.failedDocuments)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(record.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }
                }
            }
        }
    }
}

private struct JiraProjectSourceCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = JiraProjectSourceDraft()
    var onSave: (JiraProjectSourceDraft) -> Void

    private var canSave: Bool {
        !draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.projectKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (draft.authMode == .dataCenterBearer || !draft.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SemanticLabel(title: "添加 Jira 项目状态源", systemImage: "checklist", role: .knowledge)
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(AppHoverButtonStyle(variant: .secondary))
            }

            Form {
                TextField("显示名称，例如 ABC 项目状态", text: $draft.displayName)
                TextField("Jira Base URL，例如 https://your-domain.atlassian.net", text: $draft.baseURL)
                Picker("认证方式", selection: $draft.authMode) {
                    ForEach(JiraAuthMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if draft.authMode == .cloudAPIToken {
                    TextField("用户名或邮箱", text: $draft.username)
                }
                SecureField("Token", text: $draft.token)
                TextField("Project Key，例如 ABC", text: $draft.projectKey)
                TextField("可选 JQL，留空默认拉取最近 90 天", text: $draft.jql)
                Picker("同步方式", selection: $draft.syncSchedule) {
                    ForEach(KnowledgeSyncSchedule.allCases, id: \.self) { schedule in
                        Text(schedule.label).tag(schedule)
                    }
                }
                Stepper("单次最多 \(draft.maxIssues) 条 Issue", value: $draft.maxIssues, in: 1...500, step: 25)
            }

            Text("Token 只保存在本地 workspace，不会发送给 AI。AI 只会读取 Issue 摘要、状态和时间证据，并会标注 Jira 时间不等于真实上线时间。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("保存连接") {
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(AppHoverButtonStyle(variant: .primary))
                .disabled(!canSave)
            }
        }
        .padding(22)
        .frame(width: 680, height: 560)
    }
}

private struct JiraProjectSourceEditableDraft: Equatable {
    var isEnabled: Bool
    var displayName: String
    var baseURL: String
    var authMode: JiraAuthMode
    var username: String
    var token: String
    var projectKey: String
    var jql: String
    var syncSchedule: KnowledgeSyncSchedule
    var maxIssues: Int

    init(_ source: JiraProjectSource) {
        self.isEnabled = source.isEnabled
        self.displayName = source.displayName
        self.baseURL = source.baseURL
        self.authMode = source.authMode
        self.username = source.username
        self.token = source.token
        self.projectKey = source.projectKey
        self.jql = source.jql
        self.syncSchedule = source.syncSchedule
        self.maxIssues = source.maxIssues
    }
}

private struct JiraProjectSourceRow: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    var source: JiraProjectSource
    @State private var draft: JiraProjectSourceEditableDraft
    @State private var lastCommittedDraft: JiraProjectSourceEditableDraft
    @State private var commitTask: Task<Void, Never>?

    init(source: JiraProjectSource) {
        self.source = source
        let initialDraft = JiraProjectSourceEditableDraft(source)
        _draft = State(initialValue: initialDraft)
        _lastCommittedDraft = State(initialValue: initialDraft)
    }

    private var isTesting: Bool {
        store.testingJiraProjectSourceIDs.contains(source.id)
    }

    private var isSyncing: Bool {
        store.syncingJiraProjectSourceIDs.contains(source.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SemanticIcon(systemName: "checklist", role: .knowledge)
                Text(draft.displayName.nilIfBlank ?? "Jira 项目状态源")
                    .font(.headline)
                Badge(text: draft.isEnabled ? "已启用" : "已停用", systemImage: nil, tint: draft.isEnabled ? AppTheme.success : .gray)
                Badge(text: draft.authMode.label, systemImage: nil, tint: AppTheme.accent)
                Spacer()
                Toggle("启用", isOn: Binding(
                    get: { draft.isEnabled },
                    set: { updateDraft(\.isEnabled, value: $0) }
                ))
                .toggleStyle(.checkbox)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], spacing: 10) {
                TextField("显示名称", text: Binding(
                    get: { draft.displayName },
                    set: { updateDraft(\.displayName, value: $0) }
                ))
                TextField("Base URL", text: Binding(
                    get: { draft.baseURL },
                    set: { updateDraft(\.baseURL, value: $0) }
                ))
                Picker("认证方式", selection: Binding(
                    get: { draft.authMode },
                    set: { updateDraft(\.authMode, value: $0) }
                )) {
                    ForEach(JiraAuthMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .hoverControlShell(.pickerShell)
                TextField("Project Key", text: Binding(
                    get: { draft.projectKey },
                    set: { updateDraft(\.projectKey, value: $0) }
                ))
                if draft.authMode == .cloudAPIToken {
                    TextField("用户名或邮箱", text: Binding(
                        get: { draft.username },
                        set: { updateDraft(\.username, value: $0) }
                    ))
                }
                SecureField("Token", text: Binding(
                    get: { draft.token },
                    set: { updateDraft(\.token, value: $0) }
                ))
            }

            TextField("JQL，留空默认：project = \(draft.projectKey.nilIfBlank ?? "PROJECT") AND updated >= -90d", text: Binding(
                get: { draft.jql },
                set: { updateDraft(\.jql, value: $0) }
            ))

            ResponsiveStack(compactBreakpoint: 720, spacing: 8) {
                Picker("同步方式", selection: Binding(
                    get: { draft.syncSchedule },
                    set: { updateDraft(\.syncSchedule, value: $0) }
                )) {
                    ForEach(KnowledgeSyncSchedule.allCases, id: \.self) { schedule in
                        Text(schedule.label).tag(schedule)
                    }
                }
                .frame(width: 140)
                .hoverControlShell(.pickerShell)

                Stepper("最多 \(draft.maxIssues) 条", value: Binding(
                    get: { draft.maxIssues },
                    set: { updateDraft(\.maxIssues, value: $0) }
                ), in: 1...500, step: 25)

                Button {
                    flushDraftToStore()
                    store.testJiraProjectSource(sourceWithDraftValues())
                } label: {
                    Label(isTesting ? "测试中" : "测试连接", systemImage: "network")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .secondary))
                .disabled(isTesting || isSyncing)

                Button {
                    flushDraftToStore()
                    store.syncJiraProjectSource(sourceWithDraftValues())
                } label: {
                    Label(isSyncing ? "同步中" : "手动同步", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .secondary))
                .disabled(isTesting || isSyncing || !draft.isEnabled)

                Button {
                    store.deleteJiraProjectSource(source)
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .danger))
            }

            HStack(spacing: 12) {
                Text("最近同步：\(source.lastSyncAt.map { DateFormatting.shortDateTime.string(from: $0) } ?? "未同步")")
                Text("Issue \(source.lastIssueCount)")
                Text("新增 \(source.lastAddedCount)")
                Text("更新 \(source.lastUpdatedCount)")
                if source.lastFailedCount > 0 {
                    Text("失败 \(source.lastFailedCount)")
                        .foregroundStyle(AppTheme.danger)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("Jira 时间只代表项目管理记录：创建、更新、状态变更、解决或版本字段不自动等同真实上线。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .onChange(of: source) { _ in
            resetDraftFromSource(force: false)
        }
        .onDisappear {
            flushDraftToStore()
        }
    }

    private func updateDraft<Value: Equatable>(_ keyPath: WritableKeyPath<JiraProjectSourceEditableDraft, Value>, value: Value) {
        draft[keyPath: keyPath] = value
        scheduleDraftCommit(draft)
    }

    private func scheduleDraftCommit(_ pendingDraft: JiraProjectSourceEditableDraft) {
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

    private func commitDraftToStore(_ draftToCommit: JiraProjectSourceEditableDraft) {
        guard draftToCommit != lastCommittedDraft else { return }
        store.updateJiraProjectSource(source) { source in
            source.isEnabled = draftToCommit.isEnabled
            source.displayName = draftToCommit.displayName
            source.baseURL = draftToCommit.baseURL
            source.authMode = draftToCommit.authMode
            source.username = draftToCommit.username
            source.token = draftToCommit.token
            source.projectKey = draftToCommit.projectKey
            source.jql = draftToCommit.jql
            source.syncSchedule = draftToCommit.syncSchedule
            source.maxIssues = draftToCommit.maxIssues
        }
        lastCommittedDraft = draftToCommit
    }

    private func resetDraftFromSource(force: Bool) {
        let latestDraft = JiraProjectSourceEditableDraft(source)
        guard force || draft == lastCommittedDraft else { return }
        commitTask?.cancel()
        commitTask = nil
        draft = latestDraft
        lastCommittedDraft = latestDraft
    }

    private func sourceWithDraftValues() -> JiraProjectSource {
        var copy = source
        copy.isEnabled = draft.isEnabled
        copy.displayName = draft.displayName
        copy.baseURL = draft.baseURL
        copy.authMode = draft.authMode
        copy.username = draft.username
        copy.token = draft.token
        copy.projectKey = draft.projectKey
        copy.jql = draft.jql
        copy.syncSchedule = draft.syncSchedule
        copy.maxIssues = max(1, min(draft.maxIssues, 500))
        return copy
    }
}

private struct JiraProjectSyncHistory: View {
    var records: [JiraProjectSyncRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Jira 同步记录")
                    .font(.headline)
                Spacer()
                Text(records.isEmpty ? "暂无" : "最近 \(records.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if records.isEmpty {
                Text("测试或同步后会在这里记录读取 Issue 数、知识库新增/更新数量和失败原因。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(records) { record in
                        HStack(alignment: .top, spacing: 10) {
                            SemanticIcon(systemName: record.status == .success ? "checkmark.circle" : "exclamationmark.triangle", role: record.status == .success ? .success : .risk)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Badge(text: record.status.label, systemImage: nil, tint: record.status == .success ? AppTheme.success : AppTheme.danger)
                                    Text(DateFormatting.shortDateTime.string(from: record.finishedAt))
                                        .fontWeight(.semibold)
                                }
                                Text("Issue \(record.totalIssues) · 新增 \(record.addedKnowledgeEntries) · 更新 \(record.updatedKnowledgeEntries) · 失败 \(record.failedIssues)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(record.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }
                }
            }
        }
    }
}

private struct DingTalkKnowledgeConnectorInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("钉钉在线文档（待授权）", systemImage: "lock.doc")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(AppHoverButtonStyle(variant: .secondary))
            }

            Text("当前只是预留入口，不会发起网络请求，也不会同步任何钉钉内容。")
                .font(.headline)
                .foregroundStyle(AppTheme.warning)

            VStack(alignment: .leading, spacing: 8) {
                Text("后续接入需要：")
                    .font(.headline)
                Text("1. 钉钉企业内部应用。")
                Text("2. AppKey / AppSecret。")
                Text("3. 文档或钉盘读取权限。")
                Text("4. 需要同步的空间、文件夹或文档范围。")
            }

            Text("未来支持范围：在线文档、在线表格和普通附件；同步后仍会按业务空间隔离，不会混入其他业务空间。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(22)
        .frame(width: 560, height: 360)
    }
}

private struct ConfluenceSyncRecordRow: View {
    var record: ConfluenceSyncRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Badge(text: record.status.label, systemImage: record.status == .success ? "checkmark" : "exclamationmark.triangle", tint: record.status == .success ? AppTheme.success : AppTheme.warning)
                Text(DateFormatting.shortDateTime.string(from: record.finishedAt))
                    .fontWeight(.medium)
                Spacer()
                Text(record.sourceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text("读取 \(record.totalPages) 页，命中 \(record.matchedPages) 页，当前保留 \(record.pageCountAfterSync) 页；知识库新增 \(record.addedKnowledgeEntries)，更新 \(record.updatedKnowledgeEntries)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !record.message.isEmpty {
                Text(record.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct KnowledgeEntryRow: View {
    var entry: KnowledgeEntry
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                EvidenceBadge(level: entry.evidenceLevel)
                Text(entry.scenario)
                    .font(.headline)
                Spacer()
                Text(DateFormatting.shortDate.string(from: entry.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .danger))
            }
            KeyValueRow(key: "问题", value: entry.problem)
            KeyValueRow(key: "动作", value: entry.action)
            KeyValueRow(key: "结果", value: entry.result)
            KeyValueRow(key: "来源", value: entry.relatedPackName)
            if let sourceURL = entry.sourceURL, !sourceURL.isEmpty {
                Link("打开来源页面", destination: URL(string: sourceURL) ?? URL(fileURLWithPath: "/"))
                    .font(.caption)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct ReportKnowledgeMemoryRow: View {
    var memory: ReportKnowledgeMemory
    var onToggleArchive: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Badge(text: memory.isArchived ? "已归档" : "生效中", systemImage: nil, tint: memory.isArchived ? .secondary : AppTheme.success)
                Badge(text: memory.reportKind.label, systemImage: nil, tint: AppTheme.accent)
                Badge(text: memory.reportShape.label, systemImage: nil, tint: AppTheme.info)
                Text(memory.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button(action: onToggleArchive) {
                    Label(memory.isArchived ? "恢复" : "归档", systemImage: memory.isArchived ? "arrow.uturn.backward" : "archivebox")
                }
            }
            Text(memory.content)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text("来源：\(memory.sourcePackName) / \(memory.sourceReportName)")
                Text("命中 \(memory.hitCount) 次")
                Text("最近命中：\(memory.lastMatchedAt.map { DateFormatting.shortDateTime.string(from: $0) } ?? "无")")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 6)
    }
}

private struct ConfluencePageRow: View {
    var page: ConfluencePage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(page.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Badge(text: page.scenario, systemImage: nil, tint: AppTheme.accent)
            }
            Text(page.compactSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text("同步：\(page.syncedAt.map { DateFormatting.shortDateTime.string(from: $0) } ?? "未记录")")
                Text("·")
                Text("Confluence 创建：\(page.createdAt.map { DateFormatting.shortDateTime.string(from: $0) } ?? "无记录")")
                Text("·")
                Text("Confluence 更新：\(page.lastUpdated.map { DateFormatting.shortDateTime.string(from: $0) } ?? "无记录")")
                Text("·")
                Text("ID \(page.id)")
                Text("· \(page.charCount) 字")
                if !page.url.isEmpty, let url = URL(string: page.url) {
                    Text("·")
                    Link("Confluence", destination: url)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 6)
    }
}
