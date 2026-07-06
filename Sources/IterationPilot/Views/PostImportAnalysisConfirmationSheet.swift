import SwiftUI

struct PostImportAnalysisConfirmationSheet: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    @Environment(\.dismiss) private var dismiss

    let draft: PostImportAnalysisConfirmation

    @State private var selectedReportIDs: Set<UUID>
    @State private var reportRoles: [UUID: AnalysisTaskReportRole]
    @State private var prompt: String
    @State private var isExtraReportsExpanded = false

    init(draft: PostImportAnalysisConfirmation) {
        self.draft = draft
        _selectedReportIDs = State(initialValue: draft.defaultSelectedReportIDs)
        _reportRoles = State(initialValue: draft.defaultReportRoles)
        _prompt = State(initialValue: "")
    }

    private var reportByID: [UUID: ImportedReport] {
        guard let pack = store.workspace.dataPacks.first(where: { $0.id == draft.packID }) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: pack.importedReports.map { ($0.id, $0) })
    }

    private var reports: [ImportedReport] {
        let lookup = reportByID
        return draft.reportIDs.compactMap { lookup[$0] }
    }

    private var extraReports: [ImportedReport] {
        let lookup = reportByID
        return draft.availableExtraReportIDs.compactMap { lookup[$0] }
    }

    private var visibleReportCount: Int {
        reports.count + extraReports.count
    }

    private var selectedCount: Int {
        (reports + extraReports).filter { selectedReportIDs.contains($0.id) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            reportList
            promptBox
            footer
        }
        .padding(22)
        .frame(width: 760)
        .frame(minHeight: 520)
        .background(AppTheme.surface)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(draft.title)
                    .font(AppFont.title())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(draft.closeHelpText)
            }

            Text(draft.detail)
                .font(AppFont.callout())
                .foregroundStyle(AppTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reportList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("本次分析表")
                    .font(AppFont.headline())
                Spacer()
                Text("\(selectedCount)/\(visibleReportCount) 张已选择")
                    .font(AppFont.caption())
                    .foregroundStyle(AppTheme.mutedText)
            }
            .padding(.bottom, 8)

            Divider()

            if reports.isEmpty {
                Text(draft.emptyReportText)
                    .foregroundStyle(AppTheme.mutedText)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(reports) { report in
                            reportRow(report)
                            Divider()
                        }

                        if !extraReports.isEmpty {
                            DisclosureGroup(isExpanded: $isExtraReportsExpanded) {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(extraReports) { report in
                                        reportRow(report, isExtra: true)
                                        Divider()
                                    }
                                }
                                .padding(.top, 4)
                            } label: {
                                HStack(spacing: 6) {
                                    Text("可加入的其他表")
                                        .font(AppFont.callout(weight: .semibold))
                                    Text("\(extraReports.count) 张")
                                        .font(AppFont.caption())
                                        .foregroundStyle(AppTheme.mutedText)
                                }
                                .padding(.vertical, 10)
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
    }

    private func reportRow(_ report: ImportedReport, isExtra: Bool = false) -> some View {
        let isSelected = selectedReportIDs.contains(report.id)
        return HStack(alignment: .center, spacing: 12) {
            Button {
                toggleReport(report.id)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.icon)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(isSelected ? "不加入本次分析" : "加入本次分析")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(report.displayName)
                        .font(AppFont.callout(weight: .semibold))
                        .lineLimit(2)
                    if draft.newReportIDs.contains(report.id) {
                        statusChip("新导入", tint: AppTheme.accent)
                    }
                    if draft.currentTaskReportIDs.contains(report.id) {
                        statusChip("已加入", tint: AppTheme.success)
                    } else if isExtra {
                        statusChip("可加入", tint: AppTheme.icon)
                    }
                }
                Text("\(report.sourceFormat.label) · \(report.rowCount) 行 · \(report.headers.count) 列 · \(report.shape.label)")
                    .font(AppFont.caption())
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(1)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Picker("角色", selection: roleBinding(for: report.id)) {
                Text("主表").tag(AnalysisTaskReportRole.primaryBusiness)
                Text("旁证").tag(AnalysisTaskReportRole.evidence)
                Text("辅助").tag(AnalysisTaskReportRole.impactSource)
            }
            .labelsHidden()
            .frame(width: 112)
            .disabled(!isSelected)
            .opacity(isSelected ? 1 : 0.45)
            .hoverControlShell(.pickerShell)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func statusChip(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(AppFont.caption(weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.10), in: Capsule())
    }

    private var promptBox: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("你想让 AI 分析什么？")
                .font(AppFont.headline())
            AdaptiveTextBox(
                text: $prompt,
                placeholder: "可选。填写后会直接开始深度分析；不填写则加入表后回到底部输入框。",
                minHeight: 72,
                maxHeight: 130
            )
        }
    }

    private var footer: some View {
        HStack {
            Button(draft.poolOnlyButtonTitle) {
                store.keepPostImportReportsInPool(draftID: draft.id)
                dismiss()
            }
            .buttonStyle(AppHoverButtonStyle(variant: .secondary))

            Spacer()

            Button("取消") {
                dismiss()
            }
            .buttonStyle(AppHoverButtonStyle(variant: .secondary))

            Button(primaryActionTitle) {
                store.confirmPostImportReportsForAnalysis(
                    draftID: draft.id,
                    selectedReportIDs: selectedReportIDs,
                    reportRoles: reportRoles,
                    prompt: prompt
                )
                dismiss()
            }
            .buttonStyle(AppHoverButtonStyle(variant: .primary))
        }
    }

    private var primaryActionTitle: String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedCount == 0 {
            return "确认清空"
        }
        return trimmedPrompt.isEmpty ? "确认本次分析表" : "加入并开始分析"
    }

    private func toggleReport(_ reportID: UUID) {
        if selectedReportIDs.contains(reportID) {
            selectedReportIDs.remove(reportID)
        } else {
            selectedReportIDs.insert(reportID)
            if reportRoles[reportID] == nil {
                reportRoles[reportID] = .evidence
            }
        }
    }

    private func roleBinding(for reportID: UUID) -> Binding<AnalysisTaskReportRole> {
        Binding(
            get: { reportRoles[reportID] ?? .evidence },
            set: { reportRoles[reportID] = $0 }
        )
    }
}
