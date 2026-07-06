import SwiftUI

private extension SidebarSelection {
    var sidebarDisplayTitle: String {
        switch self {
        case .dataPacks: return "数据资料"
        case .settings: return "设置"
        case .businessSpaces: return "业务空间"
        case .references: return "参照源"
        case .quality: return "质检"
        case .timeline: return "时间轴"
        case .analysis: return "分析证据"
        case .corrections: return "记忆中心"
        default: return title
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    @Binding var selection: SidebarSelection
    @State private var advancedToolsExpanded = false
    @State private var sessionListScope: SessionListScope = .currentPack
    @State private var showArchivedSessions = false
    @State private var showAllSessions = false
    @State private var isSessionSearchVisible = false
    @State private var sessionSearchText = ""
    @State private var pendingPermanentDeleteSession: SidebarSessionDeleteTarget?
    @State private var isSessionHistoryReady = false
    @State private var sessionHistorySnapshot = SidebarSessionHistorySnapshot.empty
    @State private var sessionHistoryRevision: SidebarSessionHistoryRevision?
    @State private var sessionHistoryRefreshTask: Task<Void, Never>?
    @State private var sessionHistoryWarmupTask: Task<Void, Never>?

    private let primaryItems: [SidebarSelection] = [.sessions, .opportunities, .knowledge, .settings]
    private let secondaryItems: [SidebarSelection] = [.businessSpaces, .references, .quality, .timeline, .analysis, .corrections]
    private let recentSessionLimit = 8
    private let topChromePadding: CGFloat = 32

    init(selection: Binding<SidebarSelection>, initialMoreExpanded: Bool = false) {
        _selection = selection
        _advancedToolsExpanded = State(initialValue: initialMoreExpanded)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sidebarHeader
                primaryNavigation
                if selection == .sessions {
                    sessionHistorySection
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .padding(.top, topChromePadding)
        }
        .background(AppTheme.surface)
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

    private var sidebarHeader: some View {
        HStack(spacing: 8) {
            Text("NexaFlow")
                .font(AppFont.brand(size: 17))
                .lineLimit(1)
                .foregroundStyle(AppTheme.text)
            Spacer(minLength: 0)
            let canCreateSession = store.hasSelectedPackForCurrentBusinessSpace
            Button {
                store.createAnalysisSessionFromCurrentTask()
                selection = .sessions
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(canCreateSession ? AppTheme.text : AppTheme.faintText)
                    .frame(width: 26, height: 26)
                    .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .disabled(!canCreateSession)
            .help("新建分析会话")
        }
        .padding(.horizontal, 6)
        .textSelection(.disabled)
    }

    private var primaryNavigation: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(primaryItems) { item in
                sidebarNavigationRow(item)
            }
            moreNavigationDisclosure
        }
    }

    private var moreNavigationDisclosure: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                withAnimation(.easeOut(duration: 0.14)) {
                    advancedToolsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppTheme.icon)
                        .frame(width: 20)
                    Text("更多")
                        .font(AppFont.callout())
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.faintText)
                        .rotationEffect(.degrees(advancedToolsExpanded ? 90 : 0))
                }
                .foregroundStyle(AppTheme.mutedText)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    advancedToolsExpanded ? AppTheme.panelStrong.opacity(0.55) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help(advancedToolsExpanded ? "收起低频配置和工具入口" : "展开低频配置和工具入口")

            if advancedToolsExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(secondaryItems) { item in
                        moreNavigationChildRow(item)
                    }
                }
                .padding(.vertical, 5)
                .padding(.leading, 10)
                .padding(.trailing, 4)
                .background(AppTheme.panel.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppTheme.border.opacity(0.50), lineWidth: 1)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.14), value: advancedToolsExpanded)
    }

    private func sidebarNavigationRow(_ item: SidebarSelection) -> some View {
        Button {
            selection = item
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selection == item ? AppTheme.accentStrong : AppTheme.icon)
                    .frame(width: 20)
                Text(item.sidebarDisplayTitle)
                    .font(AppFont.callout(weight: selection == item ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selection == item ? AppTheme.text : AppTheme.mutedText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selection == item ? AppTheme.accent.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(item.title)
    }

    private func moreNavigationChildRow(_ item: SidebarSelection) -> some View {
        Button {
            selection = item
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selection == item ? AppTheme.accentStrong : AppTheme.icon)
                    .frame(width: 18)
                Text(item.sidebarDisplayTitle)
                    .font(AppFont.caption(weight: selection == item ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selection == item ? AppTheme.text : AppTheme.mutedText)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selection == item ? AppTheme.accent.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(item.title)
    }

    private var sessionHistorySection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("最近会话")
                    .font(AppFont.caption(weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
                Spacer(minLength: 0)
                sessionHistorySearchButton
                sessionHistoryOptionsMenu
            }
            .padding(.horizontal, 6)

            if isSessionSearchVisible {
                sessionHistorySearchField
            }

            if !isSessionHistoryReady {
                Text("正在加载历史会话...")
                    .font(AppFont.caption())
                    .foregroundStyle(AppTheme.mutedText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            } else if sessionHistorySnapshot.totalCount == 0 {
                Text(sessionSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "还没有会话，导入表格后开始分析" : "没有匹配会话")
                    .font(AppFont.caption())
                    .foregroundStyle(AppTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            } else {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(sessionHistorySnapshot.visibleRows) { row in
                        SessionListRow(
                            snapshot: row.session,
                            isSelected: row.isSelected,
                            activeJob: row.activeJob,
                            sourcePackMissing: row.sourcePackMissing,
                            archiveAction: {
                                store.archiveAnalysisSession(sessionID: row.id)
                            },
                            restoreAction: {
                                store.restoreAnalysisSession(sessionID: row.id)
                            },
                            deleteAction: {
                                pendingPermanentDeleteSession = SidebarSessionDeleteTarget(id: row.id, title: row.session.title)
                            }
                        )
                        .equatable()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.selectAnalysisSession(sessionID: row.id)
                            selection = .sessions
                        }
                    }
                    if sessionHistorySnapshot.visibleRows.count < sessionHistorySnapshot.totalCount {
                        Button {
                            showAllSessions = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("查看全部 \(sessionHistorySnapshot.totalCount) 个")
                            }
                        }
                        .buttonStyle(.plain)
                        .font(AppFont.caption())
                        .foregroundStyle(AppTheme.mutedText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .onChange(of: sessionListScope) { _ in
            showAllSessions = false
            isSessionHistoryReady = true
            refreshSessionHistorySnapshot(force: true)
        }
        .onChange(of: showArchivedSessions) { _ in
            showAllSessions = false
            isSessionHistoryReady = true
            refreshSessionHistorySnapshot(force: true)
        }
        .onChange(of: showAllSessions) { _ in
            isSessionHistoryReady = true
            refreshSessionHistorySnapshot(force: true)
        }
        .onChange(of: sessionSearchText) { _ in
            isSessionHistoryReady = true
            refreshSessionHistorySnapshot(force: true)
        }
        .onChange(of: selection) { _ in
            scheduleSessionHistoryWarmup()
        }
        .onReceive(store.$workspace) { _ in
            if isSessionHistoryReady {
                scheduleSessionHistoryRefresh()
            }
        }
        .onAppear {
            scheduleSessionHistoryWarmup()
        }
        .onDisappear {
            sessionHistoryRefreshTask?.cancel()
            sessionHistoryRefreshTask = nil
            sessionHistoryWarmupTask?.cancel()
            sessionHistoryWarmupTask = nil
            isSessionHistoryReady = false
        }
    }

    private var sessionHistorySearchButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.14)) {
                if isSessionSearchVisible {
                    sessionSearchText = ""
                    isSessionSearchVisible = false
                } else {
                    isSessionSearchVisible = true
                }
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSessionSearchVisible ? AppTheme.accentStrong : AppTheme.icon)
                .frame(width: 24, height: 22)
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(isSessionSearchVisible ? "关闭会话搜索" : "搜索最近会话")
    }

    private var sessionHistorySearchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.icon)
            TextField("搜索会话", text: $sessionSearchText)
                .textFieldStyle(.plain)
                .font(AppFont.caption())
                .onExitCommand {
                    sessionSearchText = ""
                    isSessionSearchVisible = false
                }
            if !sessionSearchText.isEmpty {
                Button {
                    sessionSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.faintText)
                }
                .buttonStyle(.plain)
                .help("清空搜索")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(AppTheme.panelStrong.opacity(0.46), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border.opacity(0.42), lineWidth: 1)
        }
        .padding(.horizontal, 6)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var sessionHistoryOptionsMenu: some View {
        Menu {
            Picker("范围", selection: $sessionListScope) {
                ForEach(SessionListScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            Toggle("显示已归档", isOn: $showArchivedSessions)
            if showAllSessions {
                Button("只显示最近会话") {
                    showAllSessions = false
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.icon)
                .frame(width: 24, height: 22)
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .help("筛选历史会话")
    }

    private func makeSessionHistorySnapshot() -> SidebarSessionHistorySnapshot {
        let selectedSessionID = store.workspace.selectedAnalysisSessionID
        let selectedPackID = store.selectedPackID
        let selectedSpaceID = store.selectedBusinessSpace?.id
        let packSpaceByID = Dictionary(uniqueKeysWithValues: store.workspace.dataPacks.map { ($0.id, $0.businessSpaceID) })
        let dataPackIDs = Set(store.workspace.dataPacks.map(\.id))
        let activeJobsBySessionID = blockingJobSnapshotsBySessionID()
        let includeAllHistory = sessionListScope == .allHistory
        let normalizedSearchText = sessionSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isSearching = !normalizedSearchText.isEmpty
        let visibleLimit = isSearching || showAllSessions ? Int.max : recentSessionLimit
        var visibleRows: [SidebarSessionRowSnapshot] = []
        var selectedRow: SidebarSessionRowSnapshot?
        var totalCount = 0

        for session in store.workspace.analysisSessions {
            guard showArchivedSessions || session.status != .archived else { continue }
            if !includeAllHistory, let selectedPackID, session.packID != selectedPackID {
                continue
            }
            guard sessionBelongsToSelectedSpace(session, selectedSpaceID: selectedSpaceID, packSpaceByID: packSpaceByID) else {
                continue
            }
            guard !isSearching || sessionMatchesSearch(session, query: normalizedSearchText) else {
                continue
            }

            totalCount += 1
            let row = SidebarSessionRowSnapshot(
                session: SessionListRowSnapshot(session: session),
                isSelected: selectedSessionID == session.id,
                activeJob: activeJobsBySessionID[session.id],
                sourcePackMissing: isSessionSourceMissing(session, dataPackIDs: dataPackIDs)
            )
            if row.isSelected {
                selectedRow = row
            }
            if isSearching || showAllSessions {
                visibleRows.append(row)
            } else {
                insertVisibleSessionRow(row, into: &visibleRows, limit: visibleLimit)
            }
        }

        if isSearching || showAllSessions {
            visibleRows.sort { $0.session.updatedAt > $1.session.updatedAt }
        } else if let selectedRow, !visibleRows.contains(where: { $0.id == selectedRow.id }) {
            visibleRows.append(selectedRow)
        }

        return SidebarSessionHistorySnapshot(visibleRows: visibleRows, totalCount: totalCount)
    }

    private func scheduleSessionHistoryRefresh(delayNanoseconds: UInt64 = 220_000_000) {
        sessionHistoryRefreshTask?.cancel()
        sessionHistoryRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            refreshSessionHistorySnapshot(force: false)
            sessionHistoryRefreshTask = nil
        }
    }

    private func scheduleSessionHistoryWarmup(delayNanoseconds: UInt64 = 90_000_000) {
        sessionHistoryWarmupTask?.cancel()
        isSessionHistoryReady = false
        sessionHistoryWarmupTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            isSessionHistoryReady = true
            refreshSessionHistorySnapshot(force: true)
            sessionHistoryWarmupTask = nil
        }
    }

    private func refreshSessionHistorySnapshot(force: Bool) {
        let revision = makeSessionHistoryRevision()
        guard force || revision != sessionHistoryRevision else { return }
        sessionHistorySnapshot = makeSessionHistorySnapshot()
        sessionHistoryRevision = revision
    }

    private func makeSessionHistoryRevision() -> SidebarSessionHistoryRevision {
        SidebarSessionHistoryRevision(
            selectedPackID: store.selectedPackID,
            selectedBusinessSpaceID: store.workspace.selectedBusinessSpaceID,
            selectedAnalysisSessionID: store.workspace.selectedAnalysisSessionID,
            scope: sessionListScope,
            showArchivedSessions: showArchivedSessions,
            showAllSessions: showAllSessions,
            searchText: sessionSearchText.trimmingCharacters(in: .whitespacesAndNewlines),
            dataPackSignature: dataPackSignature(),
            sessionSignature: analysisSessionListSignature(),
            activeJobSignature: activeJobListSignature()
        )
    }

    private func dataPackSignature() -> Int {
        var hasher = Hasher()
        for pack in store.workspace.dataPacks {
            hasher.combine(pack.id)
            hasher.combine(pack.businessSpaceID)
        }
        return hasher.finalize()
    }

    private func analysisSessionListSignature() -> Int {
        var hasher = Hasher()
        for session in store.workspace.analysisSessions {
            hasher.combine(session.id)
            hasher.combine(session.packID)
            hasher.combine(session.businessSpaceID)
            hasher.combine(session.status)
            hasher.combine(session.updatedAt)
            hasher.combine(session.title)
            hasher.combine(session.goal)
            hasher.combine(session.sourcePackDeleted == true)
        }
        return hasher.finalize()
    }

    private func activeJobListSignature() -> Int {
        let sessionIDs = Set(store.workspace.analysisSessions.map(\.id))
        var hasher = Hasher()
        for job in store.workspace.persistentAIJobs {
            guard let sessionID = job.payload.sessionID,
                  job.status == .waiting || job.status.isActive,
                  job.kind == .analysisSession || job.kind == .memo || job.kind == .simpleReportGeneration,
                  sessionIDs.contains(sessionID) else {
                continue
            }
            hasher.combine(job.id)
            hasher.combine(sessionID)
            hasher.combine(job.status)
            hasher.combine(job.updatedAt)
            hasher.combine(job.delayedRetryCount)
            hasher.combine(job.kind)
        }
        return hasher.finalize()
    }

    private func insertVisibleSessionRow(
        _ row: SidebarSessionRowSnapshot,
        into rows: inout [SidebarSessionRowSnapshot],
        limit: Int
    ) {
        guard limit > 0 else { return }
        if rows.count == limit,
           let last = rows.last,
           row.session.updatedAt <= last.session.updatedAt {
            return
        }

        if let index = rows.firstIndex(where: { row.session.updatedAt > $0.session.updatedAt }) {
            rows.insert(row, at: index)
        } else {
            rows.append(row)
        }
        if rows.count > limit {
            rows.removeLast()
        }
    }

    private func blockingJobSnapshotsBySessionID() -> [UUID: SessionListActiveJobSnapshot] {
        var result: [UUID: SessionListActiveJobSnapshot] = [:]
        for job in store.workspace.persistentAIJobs {
            guard let sessionID = job.payload.sessionID,
                  result[sessionID] == nil,
                  job.status == .waiting || job.status.isActive,
                  job.kind == .analysisSession || job.kind == .memo || job.kind == .simpleReportGeneration else {
                continue
            }
            result[sessionID] = SessionListActiveJobSnapshot(job: job)
        }
        return result
    }

    private func sessionBelongsToSelectedSpace(
        _ session: AnalysisSession,
        selectedSpaceID: UUID?,
        packSpaceByID: [UUID: UUID?]
    ) -> Bool {
        guard let selectedSpaceID else { return true }
        if let packSpaceID = packSpaceByID[session.packID] {
            return packSpaceID == selectedSpaceID
        }
        return session.businessSpaceID == selectedSpaceID
    }

    private func isSessionSourceMissing(_ session: AnalysisSession, dataPackIDs: Set<UUID>) -> Bool {
        session.sourcePackDeleted == true ||
            !dataPackIDs.contains(session.packID)
    }

    private func sessionMatchesSearch(_ session: AnalysisSession, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let dateText = DateFormatting.shortDateTime.string(from: session.updatedAt)
        return [
            session.title,
            session.goal,
            session.status.label,
            dateText
        ].contains { value in
            value.lowercased().contains(query)
        }
    }
}

private struct SidebarSessionDeleteTarget: Identifiable {
    var id: UUID
    var title: String
}

private struct SidebarSessionHistorySnapshot: Equatable {
    var visibleRows: [SidebarSessionRowSnapshot]
    var totalCount: Int

    static let empty = SidebarSessionHistorySnapshot(visibleRows: [], totalCount: 0)
}

private struct SidebarSessionHistoryRevision: Equatable {
    var selectedPackID: UUID?
    var selectedBusinessSpaceID: UUID?
    var selectedAnalysisSessionID: UUID?
    var scope: SessionListScope
    var showArchivedSessions: Bool
    var showAllSessions: Bool
    var searchText: String
    var dataPackSignature: Int
    var sessionSignature: Int
    var activeJobSignature: Int
}

private struct SidebarSessionRowSnapshot: Identifiable, Equatable {
    var session: SessionListRowSnapshot
    var isSelected: Bool
    var activeJob: SessionListActiveJobSnapshot?
    var sourcePackMissing: Bool

    var id: UUID { session.id }
}

private enum SessionListScope: String, CaseIterable, Identifiable {
    case currentPack = "当前资料"
    case allHistory = "当前空间历史"

    var id: String { rawValue }
}
