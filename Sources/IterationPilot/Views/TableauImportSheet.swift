import Foundation
import SwiftUI

struct TableauImportSheet: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSourceID: UUID?
    @State private var catalog: TableauCatalog?
    @State private var selectedViewIDs = Set<String>()
    @State private var searchText = ""
    @State private var isLoadingCatalog = false
    @State private var statusText = ""
    @State private var technicalStatusDetail = ""
    @State private var showingCreateSheet = false

    private var sources: [TableauSource] {
        store.tableauSourcesForSelectedBusinessSpace
    }

    private var selectedSource: TableauSource? {
        guard let selectedSourceID else { return sources.first }
        return sources.first { $0.id == selectedSourceID }
    }

    private var filteredViews: [TableauView] {
        let views = catalog?.views ?? []
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return views }
        return views.filter { view in
            [
                view.projectName,
                view.workbookName,
                view.name
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    private var selectedViews: [TableauView] {
        (catalog?.views ?? []).filter { selectedViewIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if sources.isEmpty {
                emptySourceState
            } else {
                sourceControls
                viewBrowser
            }

            if !statusText.isEmpty {
                tableauStatusMessage
            }

            footer
        }
        .padding(22)
        .frame(width: 840, height: 680)
        .background(AppTheme.surface)
        .onAppear {
            selectedSourceID = selectedSourceID ?? sources.first?.id
        }
        .sheet(isPresented: $showingCreateSheet) {
            TableauSourceCreateSheet { draft in
                store.createTableauSource(draft)
                selectedSourceID = store.tableauSourcesForSelectedBusinessSpace.first?.id
            }
        }
    }

    private var header: some View {
        HStack {
            SemanticLabel(title: "从 Tableau 导入视图", systemImage: "chart.bar.doc.horizontal", role: .data)
                .font(.title2.weight(.semibold))
            Spacer()
            Button("取消") { dismiss() }
                .buttonStyle(AppHoverButtonStyle(variant: .secondary))
        }
    }

    private var emptySourceState: some View {
        SectionCard(title: "还没有 Tableau 连接", systemImage: "chart.bar.doc.horizontal") {
            Text("先添加当前业务空间的 Tableau 连接。Token 只保存在本地 workspace，不会进入 AI Prompt、日志或导出文件。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showingCreateSheet = true
            } label: {
                SemanticLabel(title: "添加 Tableau 连接", systemImage: "plus", role: .data)
            }
            .buttonStyle(AppHoverButtonStyle(variant: .primary))
        }
    }

    private var sourceControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Tableau 连接", selection: Binding(
                    get: { selectedSourceID ?? sources.first?.id },
                    set: { value in
                        selectedSourceID = value
                        catalog = nil
                        selectedViewIDs = []
                    }
                )) {
                    ForEach(sources) { source in
                        Text(source.displayName).tag(source.id as UUID?)
                    }
                }
                .frame(maxWidth: 260)
                .hoverControlShell(.pickerShell)

                Button {
                    showingCreateSheet = true
                } label: {
                    SemanticLabel(title: "添加连接", systemImage: "plus", role: .data)
                }
                .buttonStyle(AppHoverButtonStyle(variant: .secondary))

                Button {
                    loadCatalog()
                } label: {
                    if isLoadingCatalog {
                        ProgressView()
                            .controlSize(.small)
                    }
                    SemanticLabel(title: "加载工作簿/视图", systemImage: "arrow.triangle.2.circlepath", role: .data)
                }
                .buttonStyle(AppHoverButtonStyle(variant: .primary))
                .disabled(selectedSource == nil || isLoadingCatalog)
            }

            Text("第一版导入 Tableau View / Worksheet 导出的数据，不读取 Hyper 或底层 Published Data Source。导入后会进入当前分析资料，并弹出确认页选择本次分析表。")
                .font(AppFont.caption())
                .foregroundStyle(AppTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SemanticIcon(systemName: "archivebox", role: .data, size: 13, frameWidth: 17)
                Text(targetPackText)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(AppTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(AppTheme.accent.opacity(0.16), lineWidth: 1)
            }
        }
    }

    private var viewBrowser: some View {
        SectionCard(title: "选择要导入的 View / Worksheet", systemImage: "tablecells") {
            AdaptiveTextField(placeholder: "搜索 Project、Workbook 或 View", text: $searchText, minLines: 1, maxLines: 1)

            if isLoadingCatalog {
                HStack {
                    ProgressView()
                    Text("正在读取 Tableau 目录...")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 24)
            } else if catalog == nil {
                Text("点击“加载工作簿/视图”后选择要导入的 Tableau 视图。")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
            } else if filteredViews.isEmpty {
                Text("没有匹配的 Tableau 视图。请检查 Project/Workbook 过滤条件或 View 下载权限。")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredViews) { view in
                            TableauViewSelectionRow(
                                view: view,
                                isSelected: selectedViewIDs.contains(view.id),
                                toggle: {
                                    if selectedViewIDs.contains(view.id) {
                                        selectedViewIDs.remove(view.id)
                                    } else {
                                        selectedViewIDs.insert(view.id)
                                    }
                                }
                            )
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("已选择 \(selectedViewIDs.count) 个视图")
                .font(AppFont.caption())
                .foregroundStyle(AppTheme.mutedText)
            Spacer()
            Button("导入并确认分析表") {
                guard let selectedSource else { return }
                store.importTableauViewsIntoCurrentTask(source: selectedSource, views: selectedViews)
                dismiss()
            }
            .buttonStyle(AppHoverButtonStyle(variant: .primary))
            .disabled(selectedSource == nil || selectedViews.isEmpty)
        }
    }

    private var tableauStatusMessage: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: technicalStatusDetail.isEmpty ? "info.circle" : "exclamationmark.triangle")
                    .foregroundStyle(technicalStatusDetail.isEmpty ? AppTheme.icon : AppTheme.warning)
                    .frame(width: 18)
                    .padding(.top, 1)
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !technicalStatusDetail.isEmpty {
                DisclosureGroup("技术详情") {
                    Text(technicalStatusDetail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .font(.caption)
                .padding(.leading, 26)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private var targetPackText: String {
        if let pack = store.selectedPack {
            return "将导入到当前分析资料：\(pack.reportSourceSummary)"
        }
        let dateText = DateFormatting.shortDate.string(from: Date())
        return "当前还没有分析资料，将创建 Tableau 导入资料：\(dateText)"
    }

    private func loadCatalog() {
        guard let source = selectedSource else { return }
        isLoadingCatalog = true
        statusText = "正在连接 Tableau..."
        technicalStatusDetail = ""
        selectedViewIDs = []
        Task { @MainActor in
            defer { isLoadingCatalog = false }
            do {
                let fetched = try await TableauService().fetchCatalog(source: source)
                catalog = fetched
                statusText = "已加载 \(fetched.workbooks.count) 个 Workbook、\(fetched.views.count) 个 View。"
                technicalStatusDetail = ""
            } catch {
                let display = productizedTableauError(error.localizedDescription)
                statusText = display.message
                technicalStatusDetail = display.technicalDetail
            }
        }
    }

    private func productizedTableauError(_ raw: String) -> (message: String, technicalDetail: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let containsHTML = trimmed.range(of: "<html", options: .caseInsensitive) != nil ||
            trimmed.range(of: "<iframe", options: .caseInsensitive) != nil ||
            trimmed.range(of: "<body", options: .caseInsensitive) != nil
        if trimmed.localizedCaseInsensitiveContains("HTTP 502") || containsHTML {
            let requestID = firstCapture(in: trimmed, pattern: #"requestId=([^"'&<>\s]+)"#)
            var message = "Tableau 服务暂时不可用。请稍后重试，或在 Tableau 中确认该视图可以下载 CSV/Crosstab。"
            if let requestID {
                message += " Request ID：\(requestID)。"
            }
            return (message, trimmed)
        }
        return (trimmed, "")
    }

    private func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }
}

struct TableauSourceCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = TableauSourceDraft()
    var onSave: (TableauSourceDraft) -> Void

    private var canSave: Bool {
        !draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.patName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.patToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SemanticLabel(title: "添加 Tableau 连接", systemImage: "chart.bar.doc.horizontal", role: .data)
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(AppHoverButtonStyle(variant: .secondary))
            }

            Form {
                TextField("显示名称，例如 墨西哥信用卡 Tableau", text: $draft.displayName)
                TextField("Tableau Base URL，例如 https://tableau.company.com", text: $draft.baseURL)
                TextField("Site Content URL，默认站点可留空", text: $draft.siteContentURL)
                TextField("PAT Name", text: $draft.patName)
                SecureField("PAT Token", text: $draft.patToken)
                TextField("默认 Project 过滤，可选", text: $draft.projectFilter)
                TextField("默认 Workbook 过滤，可选", text: $draft.workbookFilter)
            }

            Text("PAT Token 只保存在本地 workspace，不会发送给 AI。第一版只导入 View / Worksheet 导出数据；底层数据源与 Hyper Extract 后续再接。")
                .font(AppFont.callout())
                .foregroundStyle(AppTheme.mutedText)
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
        .frame(width: 680, height: 520)
        .background(AppTheme.surface)
    }
}

private struct TableauViewSelectionRow: View {
    var view: TableauView
    var isSelected: Bool
    var toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.icon)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(view.name)
                        .font(AppFont.headline())
                    Text([view.projectName.nilIfBlank, view.workbookName.nilIfBlank].compactMap { $0 }.joined(separator: " / "))
                        .font(AppFont.caption())
                        .foregroundStyle(AppTheme.mutedText)
                }
                Spacer()
                Badge(text: "View Export", systemImage: nil, tint: AppTheme.accent)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 10)
        }
        .buttonStyle(AppHoverButtonStyle(variant: .ghost))
    }
}

private struct TableauSourceEditableDraft: Equatable {
    var isEnabled: Bool
    var displayName: String
    var baseURL: String
    var siteContentURL: String
    var patName: String
    var patToken: String
    var projectFilter: String
    var workbookFilter: String

    init(_ source: TableauSource) {
        self.isEnabled = source.isEnabled
        self.displayName = source.displayName
        self.baseURL = source.baseURL
        self.siteContentURL = source.siteContentURL
        self.patName = source.patName
        self.patToken = source.patToken
        self.projectFilter = source.projectFilter
        self.workbookFilter = source.workbookFilter
    }
}

struct TableauSourceRow: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    var source: TableauSource
    @State private var draft: TableauSourceEditableDraft
    @State private var lastCommittedDraft: TableauSourceEditableDraft
    @State private var commitTask: Task<Void, Never>?

    init(source: TableauSource) {
        self.source = source
        let initialDraft = TableauSourceEditableDraft(source)
        _draft = State(initialValue: initialDraft)
        _lastCommittedDraft = State(initialValue: initialDraft)
    }

    private var isTesting: Bool {
        store.testingTableauSourceIDs.contains(source.id)
    }

    private var isImporting: Bool {
        store.importingTableauSourceIDs.contains(source.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SemanticIcon(systemName: "chart.bar.doc.horizontal", role: .data)
                Text(draft.displayName.nilIfBlank ?? "Tableau 数据源")
                    .font(.headline)
                Badge(text: draft.isEnabled ? "已启用" : "已停用", systemImage: nil, tint: draft.isEnabled ? AppTheme.success : .gray)
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
                TextField("Site Content URL", text: Binding(
                    get: { draft.siteContentURL },
                    set: { updateDraft(\.siteContentURL, value: $0) }
                ))
                TextField("PAT Name", text: Binding(
                    get: { draft.patName },
                    set: { updateDraft(\.patName, value: $0) }
                ))
                SecureField("PAT Token", text: Binding(
                    get: { draft.patToken },
                    set: { updateDraft(\.patToken, value: $0) }
                ))
                TextField("Project 过滤", text: Binding(
                    get: { draft.projectFilter },
                    set: { updateDraft(\.projectFilter, value: $0) }
                ))
                TextField("Workbook 过滤", text: Binding(
                    get: { draft.workbookFilter },
                    set: { updateDraft(\.workbookFilter, value: $0) }
                ))
            }

            if !source.lastStatusMessage.isEmpty {
                Text(source.lastStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button {
                    flushDraftToStore()
                    store.testTableauSource(sourceWithDraftValues())
                } label: {
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    SemanticLabel(title: "测试连接", systemImage: "checkmark.circle", role: .data)
                }
                .buttonStyle(AppHoverButtonStyle(variant: .secondary))
                .disabled(isTesting || isImporting)

                Button {
                    store.deleteTableauSource(source)
                } label: {
                    SemanticLabel(title: "删除", systemImage: "trash", role: .risk)
                }
                .buttonStyle(AppHoverButtonStyle(variant: .danger))
            }
        }
        .padding(.vertical, 12)
        .onChange(of: source) { _ in
            resetDraftFromSource(force: false)
        }
        .onDisappear {
            flushDraftToStore()
        }
    }

    private func updateDraft<Value: Equatable>(_ keyPath: WritableKeyPath<TableauSourceEditableDraft, Value>, value: Value) {
        draft[keyPath: keyPath] = value
        scheduleDraftCommit(draft)
    }

    private func scheduleDraftCommit(_ pendingDraft: TableauSourceEditableDraft) {
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

    private func commitDraftToStore(_ draftToCommit: TableauSourceEditableDraft) {
        guard draftToCommit != lastCommittedDraft else { return }
        store.updateTableauSource(source) { source in
            source.isEnabled = draftToCommit.isEnabled
            source.displayName = draftToCommit.displayName
            source.baseURL = draftToCommit.baseURL
            source.siteContentURL = draftToCommit.siteContentURL
            source.patName = draftToCommit.patName
            source.patToken = draftToCommit.patToken
            source.projectFilter = draftToCommit.projectFilter
            source.workbookFilter = draftToCommit.workbookFilter
        }
        lastCommittedDraft = draftToCommit
    }

    private func resetDraftFromSource(force: Bool) {
        let latestDraft = TableauSourceEditableDraft(source)
        guard force || draft == lastCommittedDraft else { return }
        commitTask?.cancel()
        commitTask = nil
        draft = latestDraft
        lastCommittedDraft = latestDraft
    }

    private func sourceWithDraftValues() -> TableauSource {
        var copy = source
        copy.isEnabled = draft.isEnabled
        copy.displayName = draft.displayName
        copy.baseURL = draft.baseURL
        copy.siteContentURL = draft.siteContentURL
        copy.patName = draft.patName
        copy.patToken = draft.patToken
        copy.projectFilter = draft.projectFilter
        copy.workbookFilter = draft.workbookFilter
        return copy
    }
}
