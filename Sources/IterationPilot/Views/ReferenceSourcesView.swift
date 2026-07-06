import SwiftUI

private struct ReferenceSourcesSnapshot {
    var currentSources: [ExternalReferenceSource]
    var globalSources: [ExternalReferenceSource]
    var unboundSources: [ExternalReferenceSource]
    var collectionRuns: [ExternalReferenceCollectionRun]
    var visibleItems: [ExternalReferenceItem]
    var filteredItemCount: Int
    var relevantItemCount: Int
    var knowledgeItemCount: Int
    var highImportanceItemCount: Int

    static let empty = ReferenceSourcesSnapshot(
        currentSources: [],
        globalSources: [],
        unboundSources: [],
        collectionRuns: [],
        visibleItems: [],
        filteredItemCount: 0,
        relevantItemCount: 0,
        knowledgeItemCount: 0,
        highImportanceItemCount: 0
    )
}

private struct ReferenceSourcesRevision: Equatable {
    var businessSpaceID: UUID?
    var sourceCount: Int
    var sourceHash: Int
    var latestSourceFetchAt: Date?
    var itemCount: Int
    var latestItemCollectedAt: Date?
    var knowledgeLinkedItemCount: Int
    var runCount: Int
    var latestRunStartedAt: Date?
    var latestRunFingerprint: String
    var runningRunCount: Int
    var searchText: String
    var collectionRunIDFilter: UUID?
}

private struct TavilySearchSettingsDraft: Equatable {
    var endpoint: String
    var apiKey: String

    init(endpoint: String = SearchAPISettings.default.tavilyEndpoint, apiKey: String = "") {
        self.endpoint = endpoint
        self.apiKey = apiKey
    }

    init(_ settings: SearchAPISettings) {
        self.endpoint = settings.tavilyEndpoint
        self.apiKey = settings.tavilyAPIKey
    }
}

private final class TavilySearchSettingsFlushBridge {
    var flush: (() -> Void)?

    func flushNow() {
        flush?()
    }
}

struct ReferenceSourcesView: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    @State private var searchText = ""
    @State private var createDraft = ReferenceSourceDraft(domain: .competitor)
    @State private var isShowingCreateSheet = false
    @State private var expandedSourceGroups: Set<String> = []
    @State private var sourceIDToReveal: UUID?
    @State private var collectionRunIDToReveal: UUID?
    @State private var collectionRunIDFilter: UUID?
    @State private var snapshot = ReferenceSourcesSnapshot.empty
    @State private var snapshotRevision: ReferenceSourcesRevision?
    @State private var snapshotRefreshTask: Task<Void, Never>?
    @State private var tavilySettingsFlushBridge = TavilySearchSettingsFlushBridge()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 8) {
                            referenceTitle
                            Spacer()
                            referenceActions
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            referenceTitle
                            referenceActions
                        }
                    }

                    SectionCard(title: "配置说明", systemImage: "info.circle") {
                        Text("参照数据源用于 AI 分析时排除或解释指标波动。只有当前业务空间源和显式全局源会进入完整分析/报告；未绑定数据源不会参与分析，请先绑定到当前业务空间或标记为全局源。")
                            .foregroundStyle(.secondary)
                    }

                    TavilySearchSettingsSection(flushBridge: tavilySettingsFlushBridge)

                    SectionCard(title: "数据源", systemImage: "newspaper") {
                        if snapshot.currentSources.isEmpty && snapshot.globalSources.isEmpty && snapshot.unboundSources.isEmpty {
                            Text("暂无参照数据源。")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("数据源默认收起，展开分组后可测试、编辑或启用单个源。新增源或从日志定位时，会自动展开对应分组。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            LazyVStack(alignment: .leading, spacing: 14) {
                                sourceScopeSection(
                                    id: "scope-current",
                                    title: "当前业务空间数据源",
                                    subtitle: "只在当前业务空间展示、采集和进入 AI Prompt",
                                    sources: snapshot.currentSources
                                )
                                sourceScopeSection(
                                    id: "scope-global",
                                    title: "显式全局数据源",
                                    subtitle: "跨业务空间可用，报告和覆盖中会标为全局源",
                                    sources: snapshot.globalSources
                                )
                                sourceScopeSection(
                                    id: "scope-unbound",
                                    title: "未绑定数据源",
                                    subtitle: "不会参与默认分析；请绑定到当前空间或标记为全局源",
                                    sources: snapshot.unboundSources
                                )
                            }
                        }
                    }

                    SectionCard(title: "采集日志", systemImage: "clock.arrow.circlepath") {
                        let runs = snapshot.collectionRuns
                        if runs.isEmpty {
                            Text("暂无采集日志。手动采集、测试此源、完整分析或报告生成触发外部搜索后，会在这里记录每个数据源的 query、返回数量和错误原因。")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(runs.prefix(50)) { run in
                                    ReferenceCollectionRunRow(
                                        run: run,
                                        filterItemsAction: {
                                            collectionRunIDFilter = run.id
                                        },
	                                        editSourceAction: { sourceID in
	                                            revealSource(sourceID)
	                                        },
	                                        retrySourceAction: { sourceID in
	                                            flushTavilySettingsDraftToStore()
	                                            if let source = store.workspace.referenceSources.first(where: { $0.id == sourceID }) {
	                                                store.testCollectReferenceSource(source)
	                                            }
	                                        }
                                    )
                                    .id(run.id)
                                    Divider()
                                }
                            }
                        }
                    }

                    SectionCard(title: "情报沉淀结果", systemImage: "tray.full") {
                        if let collectionRunIDFilter,
                           let run = store.workspace.referenceCollectionRuns.first(where: { $0.id == collectionRunIDFilter }) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Badge(text: "正在筛选本次采集结果", systemImage: nil, tint: AppTheme.accent)
                                Text("\(run.trigger.label) · \(DateFormatting.shortDateTime.string(from: run.startedAt))。下方只显示这一次采集产生的情报，便于核对来源和内容。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                Button("清除过滤") {
                                    self.collectionRunIDFilter = nil
                                }
                                .buttonStyle(AppHoverButtonStyle(variant: .ghost))
                            }
                            .padding(8)
                            .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }

                        AdaptiveTextField(placeholder: "搜索标题、摘要、来源或关键词", text: $searchText, minLines: 1, maxLines: 2)

                        HStack(spacing: 10) {
                            MetricTile(title: "相关情报", value: "\(snapshot.relevantItemCount)", systemImage: "checkmark.seal")
                            MetricTile(title: "知识库沉淀", value: "\(snapshot.knowledgeItemCount)", systemImage: "books.vertical")
                            MetricTile(title: "高重要性", value: "\(snapshot.highImportanceItemCount)", systemImage: "exclamationmark.triangle")
                        }

                        let items = snapshot.visibleItems
                        if items.isEmpty {
                            Text("暂无情报结果。人工数据源需要填写备注后点击采集；网页/RSS/通用搜索需要填写 URL；Tavily 需要先填写全局搜索 API。")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("显示 \(items.count)/\(snapshot.filteredItemCount) 条匹配情报")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(items) { item in
                                    ReferenceItemRow(item: item)
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .padding(18)
            }
            .onChange(of: sourceIDToReveal) { newValue in
                guard let newValue else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
            .onChange(of: collectionRunIDToReveal) { newValue in
                guard let newValue else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
            .onDisappear {
                flushTavilySettingsDraftToStore()
                snapshotRefreshTask?.cancel()
                snapshotRefreshTask = nil
            }
        }
        .onAppear {
            refreshReferenceSnapshot(force: true)
        }
        .onReceive(store.$workspace) { _ in
            scheduleReferenceSnapshotRefresh()
        }
        .onChange(of: searchText) { _ in
            scheduleReferenceSnapshotRefresh(delayNanoseconds: 120_000_000)
        }
        .onChange(of: collectionRunIDFilter) { _ in
            refreshReferenceSnapshot(force: true)
        }
        .sheet(isPresented: $isShowingCreateSheet) {
            ReferenceSourceCreateSheet(draft: $createDraft) { finalDraft in
                let newID = store.createReferenceSource(finalDraft)
                expandedSourceGroups.insert("scope-current")
                expandedSourceGroups.insert("scope-current-\(preferredGroupID(for: finalDraft.domain))")
                sourceIDToReveal = newID
            }
        }
    }

    private var referenceTitle: some View {
        Text("参照数据源")
            .font(.largeTitle)
            .fontWeight(.semibold)
    }

    private func flushTavilySettingsDraftToStore() {
        tavilySettingsFlushBridge.flushNow()
    }

    @ViewBuilder
    private var referenceActions: some View {
        Button {
            openCreateSheet(domain: .competitor)
        } label: {
            Label("新增竞品源", systemImage: "plus")
        }
        .help("打开弹窗创建数据源，不会立即采集")
        .buttonStyle(AppHoverButtonStyle(variant: .secondary))
        Button {
            openCreateSheet(domain: .policy)
        } label: {
            Label("新增政策源", systemImage: "plus")
        }
        .help("打开弹窗创建数据源，不会立即采集")
        .buttonStyle(AppHoverButtonStyle(variant: .secondary))
        Button {
            openCreateSheet(domain: .externalEvent)
        } label: {
            Label("新增事件源", systemImage: "plus")
        }
        .help("打开弹窗创建数据源，不会立即采集")
        .buttonStyle(AppHoverButtonStyle(variant: .secondary))
        Menu {
            Button {
                store.recommendReferenceSourcesForSelectedBusinessSpace()
            } label: {
                Label("按业务空间推荐数据源", systemImage: "wand.and.stars")
            }
            Button {
                store.recommendReferenceSourcesForSelectedBusinessSpace()
            } label: {
                Label("生成竞品候选", systemImage: "person.2.badge.gearshape")
            }
            Button {
                store.recommendReferenceSourcesForSelectedBusinessSpace()
            } label: {
                Label("生成 RivalRadar 风格来源", systemImage: "scope")
            }
        } label: {
            Label("AI 推荐", systemImage: "wand.and.stars")
        }
        .buttonStyle(AppHoverButtonStyle(variant: .secondary))
        Button {
            store.importRivalRadarReferenceSources()
        } label: {
            Label("导入竞品雷达", systemImage: "tray.and.arrow.down")
        }
        .buttonStyle(AppHoverButtonStyle(variant: .secondary))
        if store.isCollectingReferences {
            Button(role: .destructive) {
                store.cancelReferenceCollection()
            } label: {
                Label("停止采集", systemImage: "stop.circle")
            }
            .help("停止当前外部采集任务；已完成情报会保留，未完成源会在日志中标记为已取消。")
            .buttonStyle(AppHoverButtonStyle(variant: .danger))
        } else {
            Button {
                flushTavilySettingsDraftToStore()
                store.collectReferenceSources()
            } label: {
                Label("采集已启用源", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("从所有已启用且配置可用的数据源获取外部证据，供完整分析和报告使用。")
            .buttonStyle(AppHoverButtonStyle(variant: .secondary))
        }
    }

    private func makeSnapshot() -> ReferenceSourcesSnapshot {
        let spaceID = store.selectedBusinessSpace?.id
        let sources = store.workspace.referenceSources
        var currentSources: [ExternalReferenceSource] = []
        var globalSources: [ExternalReferenceSource] = []
        var unboundSources: [ExternalReferenceSource] = []
        var sourceByID: [UUID: ExternalReferenceSource] = [:]
        sourceByID.reserveCapacity(sources.count)

        for source in sources {
            sourceByID[source.id] = source
            if source.isGlobal {
                globalSources.append(source)
            } else if source.isUnbound {
                unboundSources.append(source)
            } else if source.isBound(to: spaceID) {
                currentSources.append(source)
            }
        }

        let runs = recentCollectionRuns(for: spaceID, limit: 50)
        let itemStats = referenceItemStats(spaceID: spaceID, sourceByID: sourceByID, limit: 120)
        return ReferenceSourcesSnapshot(
            currentSources: currentSources,
            globalSources: globalSources,
            unboundSources: unboundSources,
            collectionRuns: runs,
            visibleItems: itemStats.visibleItems,
            filteredItemCount: itemStats.filteredItemCount,
            relevantItemCount: itemStats.relevantItemCount,
            knowledgeItemCount: itemStats.knowledgeItemCount,
            highImportanceItemCount: itemStats.highImportanceItemCount
        )
    }

    private func scheduleReferenceSnapshotRefresh(delayNanoseconds: UInt64 = 240_000_000) {
        snapshotRefreshTask?.cancel()
        snapshotRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            refreshReferenceSnapshot(force: false)
            snapshotRefreshTask = nil
        }
    }

    private func refreshReferenceSnapshot(force: Bool) {
        let revision = makeSnapshotRevision()
        guard force || revision != snapshotRevision else { return }
        snapshot = makeSnapshot()
        snapshotRevision = revision
    }

    private func makeSnapshotRevision() -> ReferenceSourcesRevision {
        let sources = store.workspace.referenceSources
        let items = store.workspace.referenceItems
        let runs = store.workspace.referenceCollectionRuns
        let latestSourceFetchAt = latestSourceFetchDate(from: sources)
        let itemSummary = referenceItemRevisionSummary(from: items)
        let runSummary = referenceRunRevisionSummary(from: runs)
        return ReferenceSourcesRevision(
            businessSpaceID: store.selectedBusinessSpace?.id,
            sourceCount: sources.count,
            sourceHash: sourceSignature(from: sources),
            latestSourceFetchAt: latestSourceFetchAt,
            itemCount: items.count,
            latestItemCollectedAt: itemSummary.latestCollectedAt,
            knowledgeLinkedItemCount: itemSummary.knowledgeLinkedCount,
            runCount: runs.count,
            latestRunStartedAt: runSummary.latestStartedAt,
            latestRunFingerprint: latestRunFingerprint(from: runs),
            runningRunCount: runSummary.runningCount,
            searchText: searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            collectionRunIDFilter: collectionRunIDFilter
        )
    }

    private func latestSourceFetchDate(from sources: [ExternalReferenceSource]) -> Date? {
        var latestFetchAt: Date?
        for source in sources {
            guard let lastFetchedAt = source.lastFetchedAt else { continue }
            if latestFetchAt == nil || lastFetchedAt > latestFetchAt! {
                latestFetchAt = lastFetchedAt
            }
        }
        return latestFetchAt
    }

    private func referenceItemRevisionSummary(from items: [ExternalReferenceItem]) -> (latestCollectedAt: Date?, knowledgeLinkedCount: Int) {
        var latestCollectedAt: Date?
        var knowledgeLinkedCount = 0
        for item in items {
            if latestCollectedAt == nil || item.collectedAt > latestCollectedAt! {
                latestCollectedAt = item.collectedAt
            }
            if item.knowledgeEntryID != nil {
                knowledgeLinkedCount += 1
            }
        }
        return (latestCollectedAt, knowledgeLinkedCount)
    }

    private func referenceRunRevisionSummary(from runs: [ExternalReferenceCollectionRun]) -> (latestStartedAt: Date?, runningCount: Int) {
        var latestStartedAt: Date?
        var runningCount = 0
        for run in runs {
            if latestStartedAt == nil || run.startedAt > latestStartedAt! {
                latestStartedAt = run.startedAt
            }
            if run.status == .running {
                runningCount += 1
            }
        }
        return (latestStartedAt, runningCount)
    }

    private func sourceSignature(from sources: [ExternalReferenceSource]) -> Int {
        var hasher = Hasher()
        hasher.combine(sources.count)
        for source in sources {
            hasher.combine(source.id)
            hasher.combine(source.isGlobal)
            hasher.combine(source.businessSpaceIDs)
            hasher.combine(source.businessDomainIDs.count)
            hasher.combine(source.lifecycleStatus)
            hasher.combine(source.createdByAI)
            hasher.combine(source.name)
            hasher.combine(source.domain)
            hasher.combine(source.collectorType)
            hasher.combine(source.enabled)
            hasher.combine(source.lastFetchedAt)
            hasher.combine(source.tavilyTopic)
            hasher.combine(source.tavilySearchDepth)
            hasher.combine(source.tavilyTimeRange)
            hasher.combine(source.tavilyMaxResults)
            hasher.combine(source.tavilyIncludeRawContent)
            hasher.combine(source.tavilyQueryGroup)
            hasher.combine(source.tavilySourceProfile)
            hasher.combine(source.url.count)
            hasher.combine(source.queryTemplate.count)
            hasher.combine(source.keywordsText.count)
            hasher.combine(source.manualNote.count)
        }
        return hasher.finalize()
    }

    private func latestRunFingerprint(from runs: [ExternalReferenceCollectionRun]) -> String {
        guard let run = runs.max(by: { $0.startedAt < $1.startedAt }) else { return "" }
        return [
            run.id.uuidString,
            "\(run.status)",
            run.phase ?? "",
            "\(run.completedSourceCount ?? -1)",
            "\(run.analyzedItemCount ?? -1)",
            "\(run.pendingItemCount ?? -1)",
            "\(run.successfulSourceCount)",
            "\(run.failedSourceCount)",
            "\(run.rawItemCount)",
            "\(run.insertedItemCount)",
            "\(run.duplicateItemCount)",
            "\(run.irrelevantItemCount)"
        ].joined(separator: "|")
    }

    private func referenceItemStats(
        spaceID: UUID?,
        sourceByID: [UUID: ExternalReferenceSource],
        limit: Int
    ) -> (visibleItems: [ExternalReferenceItem], filteredItemCount: Int, relevantItemCount: Int, knowledgeItemCount: Int, highImportanceItemCount: Int) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var visibleItems: [ExternalReferenceItem] = []
        visibleItems.reserveCapacity(limit)
        var filteredItemCount = 0
        var relevantItemCount = 0
        var knowledgeItemCount = 0
        var highImportanceItemCount = 0

        for item in store.workspace.referenceItems where item.isVisible(in: spaceID, sourceByID: sourceByID) {
            if item.isRelevant { relevantItemCount += 1 }
            if item.knowledgeEntryID != nil { knowledgeItemCount += 1 }
            if item.importance >= 4 { highImportanceItemCount += 1 }

            guard collectionRunIDFilter == nil || item.collectionRunID == collectionRunIDFilter else {
                continue
            }
            guard query.isEmpty || referenceItem(item, matches: query) else {
                continue
            }

            filteredItemCount += 1
            if visibleItems.count < limit {
                visibleItems.append(item)
            }
        }

        return (visibleItems, filteredItemCount, relevantItemCount, knowledgeItemCount, highImportanceItemCount)
    }

    private func referenceItem(_ item: ExternalReferenceItem, matches query: String) -> Bool {
        [
            item.title,
            item.summary,
            item.impact,
            item.relevanceReason,
            item.sourceName,
            item.intelligenceCategory.label,
            item.domain.label,
            item.keywords.joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()
        .contains(query)
    }

    private func recentCollectionRuns(for spaceID: UUID?, limit: Int) -> [ExternalReferenceCollectionRun] {
        guard let spaceID else { return [] }
        var runs: [ExternalReferenceCollectionRun] = []
        runs.reserveCapacity(limit)

        for run in store.workspace.referenceCollectionRuns where run.businessSpaceID == spaceID {
            insertCollectionRun(run, into: &runs, limit: limit)
        }
        return runs
    }

    private func insertCollectionRun(_ run: ExternalReferenceCollectionRun, into runs: inout [ExternalReferenceCollectionRun], limit: Int) {
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

    private func groupedSources(from sources: [ExternalReferenceSource]) -> [ReferenceSourceGroup] {
        let groups: [(String, String, (ExternalReferenceSource) -> Bool)] = [
            ("候选未启用", "AI 推荐后需测试此源或启用", { !$0.enabled && ($0.lifecycleStatus == .candidate || $0.lifecycleStatus == .needsConfirmation || $0.lifecycleStatus == .tested) }),
            ("竞品源", "竞品官网、价格、活动、评价和投诉", { $0.domain == .competitor && ($0.enabled || $0.lifecycleStatus == .enabled) }),
            ("外部事件源", "天气、灾害、能源、交通、治安等", { $0.domain == .externalEvent }),
            ("官方数据源", "监管、央行、统计和公共机构", { $0.domain == .policy || $0.tavilySourceProfile.contains("official") || !$0.officialDomainHint.isEmpty }),
            ("新闻/财经媒体", "财经、行业和本地新闻", { $0.tavilySourceProfile.contains("news") || $0.tavilySourceProfile.contains("finance") }),
            ("社媒/评价", "App Store、Google Play 和社区反馈", { $0.tavilySourceProfile.contains("social") || $0.tavilyQueryGroup.contains("app_reviews") }),
            ("其他来源", "手工、网页、RSS 或未分类来源", { _ in true })
        ]
        var used = Set<UUID>()
        return groups.compactMap { title, subtitle, predicate in
            let matched = sources.filter { source in
                guard !used.contains(source.id), predicate(source) else { return false }
                return true
            }
            matched.forEach { used.insert($0.id) }
            guard !matched.isEmpty else { return nil }
            return ReferenceSourceGroup(title: title, subtitle: subtitle, sources: matched)
        }
    }

    @ViewBuilder
    private func sourceScopeSection(
        id: String,
        title: String,
        subtitle: String,
        sources: [ExternalReferenceSource]
    ) -> some View {
        if !sources.isEmpty {
            LazyDisclosureGroup(isExpanded: sourceGroupExpansionBinding(id)) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groupedSources(from: sources)) { group in
                        LazyDisclosureGroup(isExpanded: sourceGroupExpansionBinding("\(id)-\(group.id)")) {
                            LazyVStack(alignment: .leading, spacing: 0) {
	                                ForEach(group.sources) { source in
	                                    ReferenceSourceEditor(source: source, beforeCollectAction: {
	                                        flushTavilySettingsDraftToStore()
	                                    }) { runID in
	                                        collectionRunIDToReveal = runID
	                                    }
                                    .id(source.id)
                                    Divider()
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            HStack {
                                Text(group.title)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Badge(text: "\(group.sources.count)", systemImage: nil, tint: .secondary)
                                Spacer()
                                Text(group.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack {
                    Text(title)
                        .font(.headline)
                    Badge(text: "\(sources.count)", systemImage: nil, tint: .secondary)
                    Spacer()
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func openCreateSheet(domain: ExternalReferenceDomain) {
        createDraft = ReferenceSourceDraft(domain: domain)
        isShowingCreateSheet = true
    }

    private func sourceGroupExpansionBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expandedSourceGroups.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedSourceGroups.insert(id)
                } else {
                    expandedSourceGroups.remove(id)
                }
            }
        )
    }

    private func preferredGroupID(for domain: ExternalReferenceDomain) -> String {
        switch domain {
        case .competitor: return "竞品源"
        case .policy: return "官方数据源"
        case .externalEvent: return "外部事件源"
        case .market: return "新闻/财经媒体"
        case .manual: return "其他来源"
        }
    }

    private func revealSource(_ sourceID: UUID) {
        guard let source = store.workspace.referenceSources.first(where: { $0.id == sourceID }) else { return }
        if source.isGlobal {
            expandedSourceGroups.insert("scope-global")
            expandedSourceGroups.insert("scope-global-\(preferredGroupID(for: source.domain))")
        } else if source.isUnbound {
            expandedSourceGroups.insert("scope-unbound")
            expandedSourceGroups.insert("scope-unbound-\(preferredGroupID(for: source.domain))")
        } else {
            expandedSourceGroups.insert("scope-current")
            expandedSourceGroups.insert("scope-current-\(preferredGroupID(for: source.domain))")
        }
        sourceIDToReveal = sourceID
    }
}

private struct TavilySearchSettingsSection: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    let flushBridge: TavilySearchSettingsFlushBridge
    @State private var draft = TavilySearchSettingsDraft()
    @State private var lastCommittedDraft = TavilySearchSettingsDraft()
    @State private var commitTask: Task<Void, Never>?

    var body: some View {
        SectionCard(title: "全局搜索 API", systemImage: "magnifyingglass") {
            VStack(alignment: .leading, spacing: 10) {
                ResponsiveFormRow("Tavily Endpoint", labelWidth: 120) {
                    AdaptiveTextField(
                        placeholder: "https://api.tavily.com/search",
                        text: Binding(
                            get: { draft.endpoint },
                            set: { value in updateDraft(\.endpoint, value: value) }
                        ),
                        minLines: 1,
                        maxLines: 3
                    )
                }

                ResponsiveFormRow("Tavily API Key", labelWidth: 120) {
                    SecureField(
                        "全局 Tavily API Key",
                        text: Binding(
                            get: { draft.apiKey },
                            set: { value in updateDraft(\.apiKey, value: value) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                }
            }

            Text("Tavily Key 现在只在这里填写一次。所有 Tavily 类型的数据源都会复用这个全局配置，单个数据源不再保存 API Key。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            resetDraft(force: true)
            flushBridge.flush = { flushDraftToStore() }
        }
        .onChange(of: store.workspace.searchSettings) { _ in
            resetDraft(force: false)
        }
        .onDisappear {
            flushDraftToStore()
            commitTask?.cancel()
            commitTask = nil
            flushBridge.flush = nil
        }
    }

    private func updateDraft(
        _ keyPath: WritableKeyPath<TavilySearchSettingsDraft, String>,
        value: String
    ) {
        draft[keyPath: keyPath] = value
        scheduleCommit(draft)
    }

    private func scheduleCommit(_ pendingDraft: TavilySearchSettingsDraft) {
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

    private func commitDraftToStore(_ pendingDraft: TavilySearchSettingsDraft) {
        guard pendingDraft != lastCommittedDraft else { return }
        store.updateSearchSettings { settings in
            settings.tavilyEndpoint = pendingDraft.endpoint
            settings.tavilyAPIKey = pendingDraft.apiKey
        }
        lastCommittedDraft = pendingDraft
    }

    private func resetDraft(force: Bool) {
        let latestDraft = TavilySearchSettingsDraft(store.workspace.searchSettings)
        guard force || draft == lastCommittedDraft else { return }
        commitTask?.cancel()
        commitTask = nil
        draft = latestDraft
        lastCommittedDraft = latestDraft
    }
}

private struct LazyDisclosureGroup<Content: View, LabelContent: View>: View {
    @Binding var isExpanded: Bool
    let content: () -> Content
    let label: () -> LabelContent

    init(
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder label: @escaping () -> LabelContent
    ) {
        _isExpanded = isExpanded
        self.content = content
        self.label = label
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if isExpanded {
                content()
            }
        } label: {
            label()
        }
    }
}

private struct ReferenceSourceGroup: Identifiable {
    var id: String { title }
    var title: String
    var subtitle: String
    var sources: [ExternalReferenceSource]
}
