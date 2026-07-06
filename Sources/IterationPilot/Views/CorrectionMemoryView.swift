import SwiftUI

private struct CorrectionMemorySnapshot {
    var currentBusinessSpace: BusinessSpace?
    var correctionMemories: [AnalysisCorrectionMemory]
    var pendingCandidates: [SmartMemoryCandidate]
    var knowledgeEntryCount: Int
    var templateCount: Int
    var sessionHistoryCount: Int

    static let empty = CorrectionMemorySnapshot(
        currentBusinessSpace: nil,
        correctionMemories: [],
        pendingCandidates: [],
        knowledgeEntryCount: 0,
        templateCount: 0,
        sessionHistoryCount: 0
    )
}

private struct CorrectionMemoryRevision: Equatable {
    var selectedBusinessSpaceID: UUID?
    var selectedPackID: UUID?
    var correctionMemoryHash: Int
    var smartCandidateHash: Int
    var knowledgeEntryCount: Int
    var templateMemoryHash: Int
    var sessionCount: Int
    var searchText: String
}

struct CorrectionMemoryView: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    @State private var userCorrection = ""
    @State private var revisedConclusion = ""
    @State private var reusableRule = ""
    @State private var tagsText = ""
    @State private var appliesToFuture = true
    @State private var memorySearchText = ""
    @State private var selectedMemoryID: UUID?
    @State private var showAllMemories = false
    @State private var showAllCandidates = false
    @State private var snapshot = CorrectionMemorySnapshot.empty
    @State private var snapshotRevision: CorrectionMemoryRevision?
    @State private var snapshotRefreshTask: Task<Void, Never>?

    private let editorAnchorID = "correction-memory-editor-anchor"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("记忆中心")
                        .font(.largeTitle)
                        .fontWeight(.semibold)

                    memoryOverview(snapshot)
                    candidateMemorySection(snapshot)
                    memoryList(snapshot, scrollProxy: proxy)
                    editorSection
                }
                .padding(18)
            }
        }
        .onAppear {
            refreshSnapshot(force: true)
        }
        .onReceive(store.$workspace) { _ in
            scheduleSnapshotRefresh()
        }
        .onChange(of: memorySearchText) { _ in
            scheduleSnapshotRefresh(delayNanoseconds: 120_000_000)
        }
        .onDisappear {
            snapshotRefreshTask?.cancel()
            snapshotRefreshTask = nil
        }
    }

    private func memoryOverview(_ snapshot: CorrectionMemorySnapshot) -> some View {
        SectionCard(title: "记忆总览", systemImage: "list.bullet.rectangle") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                MetricTile(title: "纠偏规则", value: "\(snapshot.correctionMemories.count)", systemImage: "exclamationmark.bubble")
                MetricTile(title: "待确认候选", value: "\(snapshot.pendingCandidates.count)", systemImage: "sparkles")
                MetricTile(title: "分析会话历史", value: "\(snapshot.sessionHistoryCount)", systemImage: "bubble.left.and.bubble.right")
                MetricTile(title: "知识库条目", value: "\(snapshot.knowledgeEntryCount)", systemImage: "books.vertical")
                MetricTile(title: "分析模板记忆", value: "\(snapshot.templateCount)", systemImage: "doc.text.magnifyingglass")
                MetricTile(title: "指标语义", value: "\(snapshot.currentBusinessSpace?.metricSemanticLibrary.count ?? 0)", systemImage: "tag")
            }

            HStack(alignment: .top, spacing: 8) {
                SemanticIcon(systemName: "info.circle", role: .data, size: 15, frameWidth: 20)
                Text("这里统一管理 AI 后续会参考的长期记忆：纠偏规则、指标口径、分析/报告偏好、业务链路和待确认候选。普通聊天不会自动变成长期记忆，必须采纳后才会影响后续分析。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func candidateMemorySection(_ snapshot: CorrectionMemorySnapshot) -> some View {
        SectionCard(title: "待确认记忆候选", systemImage: "sparkles") {
            let candidates = snapshot.pendingCandidates
            let visibleCandidates = Array(candidates.prefix(showAllCandidates ? candidates.count : 50))
            if candidates.isEmpty {
                Text("暂无待确认候选。你在分析会话里说“以后按这个口径”“记住这个规则”“不要再这样判断”时，系统会在这里生成候选，采纳后才进入长期记忆。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(visibleCandidates) { candidate in
                    SmartMemoryCandidateRow(candidate: candidate) {
                        store.adoptSmartMemoryCandidate(candidate)
                    } onIgnore: {
                        store.ignoreSmartMemoryCandidate(candidate)
                    } onDelete: {
                        store.deleteSmartMemoryCandidate(candidate)
                    }
                    Divider()
                }
                if visibleCandidates.count < candidates.count {
                    Button("显示全部 \(candidates.count) 条候选") {
                        showAllCandidates = true
                    }
                    .buttonStyle(AppHoverButtonStyle(variant: .link))
                    .font(.caption)
                }
            }
        }
    }

    private func memoryList(_ snapshot: CorrectionMemorySnapshot, scrollProxy: ScrollViewProxy) -> some View {
        SectionCard(title: "已有纠偏记忆", systemImage: "clock.arrow.circlepath") {
            AdaptiveTextField(placeholder: "搜索指标、场景、规则或标签", text: $memorySearchText, minLines: 1, maxLines: 2)

            let memories = snapshot.correctionMemories
            let visibleMemories = Array(memories.prefix(showAllMemories ? memories.count : 120))
            if memories.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SemanticLabel(title: "还没有长期纠偏记忆", systemImage: "tray", role: .data, iconSize: 17)
                        .font(.headline)
                Text("请回到“分析会话”，针对某条 AI 回复点击“质疑结论”，或直接说明“以后按这个口径”。AI 会生成候选，你采纳后才会进入长期记忆。")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("这里不再提供空白手写新增入口，避免脱离具体 AI 回复时难以描述清楚。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
            } else {
                ForEach(visibleMemories) { memory in
                    CorrectionMemoryRow(memory: memory) {
                        loadMemory(memory)
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                scrollProxy.scrollTo(editorAnchorID, anchor: .top)
                            }
                        }
                    } onDelete: {
                        if selectedMemoryID == memory.id {
                            clearMemoryDraft()
                        }
                        store.deleteCorrectionMemory(memory)
                    }
                    Divider()
                }
                if visibleMemories.count < memories.count {
                    Button("显示全部 \(memories.count) 条纠偏记忆") {
                        showAllMemories = true
                    }
                    .buttonStyle(AppHoverButtonStyle(variant: .link))
                    .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private var editorSection: some View {
        if selectedMemoryID != nil {
            SectionCard(title: "编辑纠偏记忆", systemImage: "brain.head.profile") {
                if let selectedMemoryID,
                   let memory = store.workspace.correctionMemories.first(where: { $0.id == selectedMemoryID }) {
                    HStack(alignment: .top, spacing: 8) {
                        Badge(text: "正在编辑", systemImage: nil, tint: AppTheme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(memory.metric.isEmpty ? memory.findingTitle : memory.metric)
                                .fontWeight(.medium)
                            Text(memory.reusableRule.nilIfBlank ?? memory.revisedConclusion.nilIfBlank ?? memory.userCorrection)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button("取消编辑") {
                            clearMemoryDraft()
                        }
                        .buttonStyle(AppHoverButtonStyle(variant: .ghost))
                    }
                    Divider()
                }

                CorrectionMemoryEditor(
                    userCorrection: $userCorrection,
                    revisedConclusion: $revisedConclusion,
                    reusableRule: $reusableRule,
                    tagsText: $tagsText,
                    appliesToFuture: $appliesToFuture
                )

                HStack {
                    Spacer()
                    Button {
                        if let selectedMemoryID {
                            store.updateCorrectionMemory(
                                memoryID: selectedMemoryID,
                                userCorrection: userCorrection,
                                revisedConclusion: revisedConclusion,
                                reusableRule: reusableRule,
                                tagsText: tagsText,
                                appliesToFuture: appliesToFuture
                            )
                        }
                        clearMemoryDraft()
                    } label: {
                        SemanticLabel(title: "更新纠偏记忆", systemImage: "square.and.arrow.down", role: .knowledge)
                    }
                    .disabled(memoryDraftIsEmpty)
                }
            }
            .id(editorAnchorID)
        }
    }

    private var memoryDraftIsEmpty: Bool {
        userCorrection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && revisedConclusion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && reusableRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func makeSnapshot() -> CorrectionMemorySnapshot {
        let currentSpace = currentBusinessSpace
        let spaceID = currentSpace?.id
        let correctionMemories = filteredMemories(from: scopedCorrectionMemories(spaceID: spaceID))
        let candidates = filteredCandidates(from: scopedSmartMemoryCandidates(spaceID: spaceID))
        let knowledgeEntries: [KnowledgeEntry]
        if let spaceID {
            knowledgeEntries = store.workspace.knowledgeEntries.filter { $0.isGlobal || $0.businessSpaceID == spaceID }
        } else {
            knowledgeEntries = store.workspace.knowledgeEntries
        }
        let templates: [AnalysisTemplateMemory]
        if let spaceID {
            templates = store.workspace.analysisTemplateMemories.filter { !$0.isArchived && $0.businessSpaceID == spaceID }
        } else {
            templates = store.workspace.analysisTemplateMemories.filter { !$0.isArchived }
        }
        return CorrectionMemorySnapshot(
            currentBusinessSpace: currentSpace,
            correctionMemories: correctionMemories,
            pendingCandidates: candidates,
            knowledgeEntryCount: knowledgeEntries.count,
            templateCount: templates.count,
            sessionHistoryCount: store.sessionsForCurrentPack(includeArchived: false, includeAllHistory: true).count
        )
    }

    private func scheduleSnapshotRefresh(delayNanoseconds: UInt64 = 240_000_000) {
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

    private func makeSnapshotRevision() -> CorrectionMemoryRevision {
        CorrectionMemoryRevision(
            selectedBusinessSpaceID: store.workspace.selectedBusinessSpaceID,
            selectedPackID: store.selectedPackID,
            correctionMemoryHash: correctionMemorySignature(),
            smartCandidateHash: smartMemoryCandidateSignature(),
            knowledgeEntryCount: store.workspace.knowledgeEntries.count,
            templateMemoryHash: analysisTemplateMemorySignature(),
            sessionCount: store.workspace.analysisSessions.count,
            searchText: memorySearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
    }

    private func correctionMemorySignature() -> Int {
        var hasher = Hasher()
        hasher.combine(store.workspace.correctionMemories.count)
        for memory in store.workspace.correctionMemories {
            hasher.combine(memory.id)
            hasher.combine(memory.updatedAt)
            hasher.combine(memory.packID)
            hasher.combine(memory.businessSpaceID)
            hasher.combine(memory.findingID)
            hasher.combine(memory.metric)
            hasher.combine(memory.tags.count)
            hasher.combine(memory.appliesToFuture)
            hasher.combine(memory.reusableRule.count)
            hasher.combine(memory.revisedConclusion.count)
            hasher.combine(memory.userCorrection.count)
        }
        return hasher.finalize()
    }

    private func smartMemoryCandidateSignature() -> Int {
        var hasher = Hasher()
        hasher.combine(store.workspace.smartMemoryCandidates.count)
        for candidate in store.workspace.smartMemoryCandidates {
            hasher.combine(candidate.id)
            hasher.combine(candidate.updatedAt)
            hasher.combine(candidate.kind)
            hasher.combine(candidate.status)
            hasher.combine(candidate.businessSpaceID)
            hasher.combine(candidate.adoptedMemoryID)
            hasher.combine(candidate.hitCount)
            hasher.combine(candidate.tags.count)
        }
        return hasher.finalize()
    }

    private func analysisTemplateMemorySignature() -> Int {
        var hasher = Hasher()
        hasher.combine(store.workspace.analysisTemplateMemories.count)
        for template in store.workspace.analysisTemplateMemories {
            hasher.combine(template.id)
            hasher.combine(template.businessSpaceID)
            hasher.combine(template.updatedAt)
            hasher.combine(template.useCount)
            hasher.combine(template.lastUsedAt)
            hasher.combine(template.isArchived)
        }
        return hasher.finalize()
    }

    private func filteredMemories(from scopedMemories: [AnalysisCorrectionMemory]) -> [AnalysisCorrectionMemory] {
        let query = memorySearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let memories = scopedMemories.sorted { $0.updatedAt > $1.updatedAt }
        guard !query.isEmpty else { return memories }
        return memories.filter { memory in
            [
                memory.packName,
                memory.findingTitle,
                memory.metric,
                memory.scope,
                memory.originalConclusion,
                memory.userCorrection,
                memory.revisedConclusion,
                memory.reusableRule,
                memory.tags.joined(separator: " ")
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    private func filteredCandidates(from scopedCandidates: [SmartMemoryCandidate]) -> [SmartMemoryCandidate] {
        let query = memorySearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let candidates = scopedCandidates
            .filter { $0.status == .pending }
            .sorted { $0.updatedAt > $1.updatedAt }
        guard !query.isEmpty else { return candidates }
        return candidates.filter { candidate in
            [
                candidate.kind.label,
                candidate.title,
                candidate.content,
                candidate.scope,
                candidate.rationale,
                candidate.tags.joined(separator: " ")
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    private var currentBusinessSpace: BusinessSpace? {
        guard let id = store.workspace.selectedBusinessSpaceID else { return nil }
        return store.workspace.businessSpaces.first { $0.id == id }
    }

    private func scopedCorrectionMemories(spaceID: UUID?) -> [AnalysisCorrectionMemory] {
        guard let spaceID else { return store.workspace.correctionMemories }
        return store.workspace.correctionMemories.filter { $0.businessSpaceID == spaceID }
    }

    private func scopedSmartMemoryCandidates(spaceID: UUID?) -> [SmartMemoryCandidate] {
        guard let spaceID else { return store.workspace.smartMemoryCandidates }
        return store.workspace.smartMemoryCandidates.filter { $0.businessSpaceID == spaceID }
    }

    private func loadMemory(_ memory: AnalysisCorrectionMemory) {
        selectedMemoryID = memory.id
        userCorrection = memory.userCorrection
        revisedConclusion = memory.revisedConclusion
        reusableRule = memory.reusableRule
        tagsText = memory.tags.joined(separator: ", ")
        appliesToFuture = memory.appliesToFuture
    }

    private func clearMemoryDraft() {
        selectedMemoryID = nil
        userCorrection = ""
        revisedConclusion = ""
        reusableRule = ""
        tagsText = ""
        appliesToFuture = true
    }
}

private struct CorrectionMemoryEditor: View {
    @Binding var userCorrection: String
    @Binding var revisedConclusion: String
    @Binding var reusableRule: String
    @Binding var tagsText: String
    @Binding var appliesToFuture: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledTextEditor(title: "纠偏内容", placeholder: "原分析哪里不对，遗漏了什么事实或误判了什么因果", text: $userCorrection)
            LabeledTextEditor(title: "修正后结论", placeholder: "这次分析应该改成什么结论", text: $revisedConclusion)
            LabeledTextEditor(title: "复用规则", placeholder: "以后遇到类似场景，应该优先检查什么、避免什么误判", text: $reusableRule)

            AdaptiveTextField(placeholder: "标签，用逗号分隔", text: $tagsText, minLines: 1, maxLines: 3)

            Toggle("用于后续分析", isOn: $appliesToFuture)
        }
    }
}

private struct LabeledTextEditor: View {
    var title: String
    var placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            AdaptiveTextBox(text: $text, placeholder: placeholder, minHeight: 76, maxHeight: 240)
        }
    }
}

private struct CorrectionMemoryRow: View {
    var memory: AnalysisCorrectionMemory
    var onRefine: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Badge(text: memory.appliesToFuture ? "后续生效" : "仅本次", systemImage: nil, tint: memory.appliesToFuture ? AppTheme.success : .secondary)
                Text(memory.metric.isEmpty ? "整体分析" : memory.metric)
                    .fontWeight(.medium)
                Text(memory.scope)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(DateFormatting.shortDateTime.string(from: memory.updatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    onRefine()
                } label: {
                    SemanticLabel(title: "编辑", systemImage: "pencil", role: .knowledge)
                }
                .buttonStyle(AppHoverButtonStyle(variant: .ghost))
                .help("基于这条记忆继续纠偏或更新规则")
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    SemanticIcon(systemName: "trash", role: .risk, frameWidth: 18)
                }
                .buttonStyle(AppHoverButtonStyle(variant: .danger))
                .help("删除纠偏记忆")
            }

            Text(memory.findingTitle)
                .font(.callout)
                .foregroundStyle(.secondary)
            if !memory.revisedConclusion.isEmpty {
                KeyValueRow(key: "修正结论", value: memory.revisedConclusion)
            }
            if !memory.reusableRule.isEmpty {
                KeyValueRow(key: "复用规则", value: memory.reusableRule)
            }
            if !memory.tags.isEmpty {
                Text(memory.tags.map { "#\($0)" }.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct SmartMemoryCandidateRow: View {
    var candidate: SmartMemoryCandidate
    var onAdopt: () -> Void
    var onIgnore: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Badge(text: candidate.kind.label, systemImage: nil, tint: tint(for: candidate.kind))
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.title)
                        .fontWeight(.medium)
                    Text(candidate.content)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("范围：\(candidate.scope) · 置信度 \(Int(candidate.confidence * 100))% · \(candidate.rationale)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 8) {
                    Text(DateFormatting.shortDateTime.string(from: candidate.updatedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button {
                            onAdopt()
                        } label: {
                            SemanticLabel(title: "采纳", systemImage: "checkmark.circle", role: .success)
                        }
                        .buttonStyle(AppHoverButtonStyle(variant: .primary))
                        .help("采纳后才进入长期记忆，并影响后续 AI 分析")

                        Button {
                            onIgnore()
                        } label: {
                            SemanticLabel(title: "忽略", systemImage: "minus.circle", role: .neutral)
                        }
                        .buttonStyle(AppHoverButtonStyle(variant: .ghost))
                        .help("忽略后不会用于长期记忆")

                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            SemanticIcon(systemName: "trash", role: .risk, frameWidth: 18)
                        }
                        .buttonStyle(AppHoverButtonStyle(variant: .danger))
                        .help("删除这条候选")
                    }
                }
            }
            if !candidate.tags.isEmpty {
                Text(candidate.tags.map { "#\($0)" }.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private func tint(for kind: SmartMemoryKind) -> Color {
        switch kind {
        case .correctionRule: return AppTheme.danger
        case .metricDefinition: return AppTheme.accent
        case .analysisPreference: return .secondary
        case .reportPreference: return AppTheme.success
        case .businessLinkRule: return AppTheme.warning
        case .externalEventRule: return AppTheme.info
        case .dataSourceRule: return AppTheme.info
        case .analysisTemplate: return .yellow
        case .reportKnowledge: return .cyan
        case .knowledgeFact: return .secondary
        }
    }
}
