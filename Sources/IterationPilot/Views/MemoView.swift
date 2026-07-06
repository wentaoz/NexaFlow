import AppKit
import SwiftUI

struct MemoView: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    @State private var localMemoDraft = ""
    @State private var lastCommittedMemoDraft = ""
    @State private var memoDraftPackID: UUID?
    @State private var memoDraftTaskID: UUID?
    @State private var memoCommitTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            if let pack = store.selectedPack {
                MemoHeader()
                if let blocker = store.analysisBlockerText(for: pack) {
                    WorkflowActionBanner(
                        title: "Memo 已暂停",
                        detail: blocker,
                        actionTitle: "去分析会话",
                        actionSystemImage: "bubble.left.and.text.bubble.right"
                    ) {
                        store.requestDataPackAuditNavigation()
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
                    Spacer()
                } else if let warning = store.analysisWarningText(for: pack) {
                    WorkflowBlockedBanner(title: "Memo 置信度提醒", detail: warning)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)

                    memoBody(pack: pack)
                } else {
                    memoBody(pack: pack)
                }
            } else {
                EmptyStateView(title: "没有汇报草稿", detail: "请先在分析会话里向 AI 提需求，再生成完整汇报。", systemImage: "doc.text")
            }
        }
    }

    @ViewBuilder
    private func memoBody(pack: DataPack) -> some View {
        GeometryReader { proxy in
            if proxy.size.width < 920 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        MemoEditor(text: memoBinding(for: pack))
                            .frame(minHeight: 380)
                        SessionMemoSourcePanel(session: store.selectedAnalysisSession)
                            .frame(minHeight: 240)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                }
            } else {
                HSplitView {
                    MemoEditor(text: memoBinding(for: pack))
                        .padding(.leading, 18)
                        .padding(.bottom, 18)
                        .frame(minWidth: 420, idealWidth: max(480, proxy.size.width * 0.58))

                    SessionMemoSourcePanel(session: store.selectedAnalysisSession)
                        .padding(.trailing, 18)
                        .padding(.bottom, 18)
                        .frame(minWidth: 280, idealWidth: max(320, proxy.size.width * 0.34))
                }
            }
        }
        .onAppear {
            store.prepareDecisionMemoView()
            resetMemoDraft(for: pack)
        }
        .onChange(of: pack.id) { _ in
            flushMemoDraftToStore()
            store.prepareDecisionMemoView()
            resetMemoDraft(for: pack)
        }
        .onChange(of: pack.selectedAnalysisTaskID) { _ in
            flushMemoDraftToStore()
            store.prepareDecisionMemoView()
            resetMemoDraft(for: pack)
        }
        .onChange(of: pack.decisionMemo.generatedAt) { _ in
            flushMemoDraftToStore()
            resetMemoDraft(for: pack)
        }
        .onChange(of: store.selectedAnalysisSession?.lastReportGeneratedAt) { _ in
            flushMemoDraftToStore()
            store.prepareDecisionMemoView()
            resetMemoDraft(for: pack)
        }
        .onDisappear {
            flushMemoDraftToStore()
            store.commitMemoEdits()
        }
    }

    private func memoBinding(for pack: DataPack) -> Binding<String> {
        Binding(
            get: { localMemoDraft },
            set: { newValue in
                localMemoDraft = newValue
                scheduleMemoCommit(newValue, packID: pack.id, taskID: store.currentAnalysisTask(in: pack)?.id)
            }
        )
    }

    private func resetMemoDraft(for pack: DataPack) {
        memoCommitTask?.cancel()
        memoCommitTask = nil
        let markdown = store.memoMarkdownForCurrentContext()
        localMemoDraft = markdown
        lastCommittedMemoDraft = markdown
        memoDraftPackID = pack.id
        memoDraftTaskID = store.currentAnalysisTask(in: pack)?.id
    }

    private func scheduleMemoCommit(_ markdown: String, packID: UUID, taskID: UUID?) {
        memoDraftPackID = packID
        memoDraftTaskID = taskID
        memoCommitTask?.cancel()
        memoCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled,
                  localMemoDraft == markdown,
                  memoDraftPackID == packID,
                  memoDraftTaskID == taskID else {
                return
            }
            commitMemoDraftToStore(markdown, packID: packID, taskID: taskID)
            memoCommitTask = nil
        }
    }

    private func flushMemoDraftToStore() {
        memoCommitTask?.cancel()
        memoCommitTask = nil
        commitMemoDraftToStore(localMemoDraft, packID: memoDraftPackID, taskID: memoDraftTaskID)
    }

    private func commitMemoDraftToStore(_ markdown: String, packID: UUID?, taskID: UUID?) {
        guard markdown != lastCommittedMemoDraft else { return }
        store.updateMemo(markdown, packID: packID, taskID: taskID)
        lastCommittedMemoDraft = markdown
    }
}

private struct MemoHeader: View {
    @EnvironmentObject private var store: ProductWorkflowStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    title
                    Spacer(minLength: 12)
                    MemoToolbar()
                }

                VStack(alignment: .leading, spacing: 10) {
                    title
                    MemoToolbar()
                }
            }

            Text("完整汇报由 AI 分析会话生成；本地只负责保存草稿和导出完整汇报，不再生成本地伪分析。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let pack = store.selectedPack, !pack.analysisTasks.isEmpty {
                Picker("分析任务", selection: Binding(
                    get: { store.currentAnalysisTask(in: pack)?.id ?? pack.analysisTasks.first!.id },
                    set: { store.selectAnalysisTask(taskID: $0) }
                )) {
                    ForEach(pack.analysisTasks) { task in
                        Text(task.name).tag(task.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260, alignment: .leading)
                .hoverControlShell(.pickerShell)
            }
        }
        .padding([.horizontal, .top], 18)
        .padding(.bottom, 10)
    }

    private var title: some View {
        Text("完整汇报草稿")
            .font(.largeTitle)
            .fontWeight(.semibold)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

private struct MemoToolbar: View {
    @EnvironmentObject private var store: ProductWorkflowStore

    private var isBlocked: Bool {
        store.analysisBlockerText(for: store.selectedPack) != nil
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                toolbarButtons(iconOnly: false)
            }

            HStack(spacing: 6) {
                toolbarButtons(iconOnly: true)
            }
        }
    }

    @ViewBuilder
    private func toolbarButtons(iconOnly: Bool) -> some View {
        Button {
            store.regenerateMemoForSelectedPack()
        } label: {
            if iconOnly {
                Image(systemName: "wand.and.stars")
            } else {
                Label(store.isRunningAI ? "生成中" : "AI 生成汇报", systemImage: "wand.and.stars")
            }
        }
        .disabled(isBlocked || store.isRunningAI || !store.hasConfiguredAI)
        .help(store.hasConfiguredAI ? "由 AI 分析会话直接生成完整汇报" : "请先配置 AI API Key")

        Button {
            store.copyAIPromptForSelectedPack()
        } label: {
            if iconOnly {
                Image(systemName: "doc.on.doc")
            } else {
                Label("复制 AI 提示词", systemImage: "doc.on.doc")
            }
        }
        .disabled(isBlocked)
        .help("复制 AI 分析提示词")

        Button {
            if store.selectedAnalysisSession == nil {
                store.createAnalysisSessionFromCurrentTask()
            }
            store.requestAnalysisSessionNavigation()
        } label: {
            if iconOnly {
                Image(systemName: "bubble.left.and.text.bubble.right")
            } else {
                Label("进入会话", systemImage: "bubble.left.and.text.bubble.right")
            }
        }
        .disabled(isBlocked)
        .help("进入 ChatGPT 式分析会话，继续追问或修正口径")

        Button {
            store.exportSelectedMemo()
        } label: {
            if iconOnly {
                Image(systemName: "doc.richtext")
            } else {
                Label("导出完整汇报", systemImage: "doc.richtext")
            }
        }
        .disabled((store.selectedAnalysisSession?.finalReportMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) || store.runningBlockingAIJobForSelectedAnalysisSession != nil || store.isExportingReport)
        .help(store.runningBlockingAIJobForSelectedAnalysisSession == nil ? "请先在分析会话生成完整汇报，导出后会自动定位文件" : "AI 任务完成后可导出最新完整汇报")
    }
}

private struct MemoEditor: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("报告草稿")
                .font(.headline)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 360, maxHeight: .infinity)
                    .textSelection(.enabled)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("AI 生成的完整汇报会出现在这里，也可以继续人工编辑。")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 360, maxHeight: .infinity)
            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SessionMemoSourcePanel: View {
    var session: AnalysisSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AI 会话来源")
                    .font(.headline)
                Spacer()
                Text(session?.status.label ?? "未创建")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                if let session {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(session.title)
                            .fontWeight(.medium)
                        Text(session.goal.nilIfBlank ?? "未填写分析目标")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Divider()
                        ForEach(session.messages.suffix(6)) { message in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(message.role.label)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text(message.content)
                                    .font(.caption)
                                    .lineLimit(10)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(12)
                } else {
                    Text("还没有分析会话。请先在“分析会话”里选择任务报表并向 AI 提需求，再生成完整汇报。")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
            }
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
    }
}
