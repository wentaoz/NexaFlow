import SwiftUI

enum AnalysisWorkflowStep: Int, CaseIterable, Identifiable {
    case importData = 1
    case selectReports
    case askAI
    case reviewEvidence
    case generateReport

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .importData: return "导入数据"
        case .selectReports: return "确认分析表"
        case .askAI: return "提问分析"
        case .reviewEvidence: return "核对证据"
        case .generateReport: return "生成汇报"
        }
    }

    var systemImage: String {
        switch self {
        case .importData: return "tray.and.arrow.down"
        case .selectReports: return "tablecells"
        case .askAI: return "paperplane.fill"
        case .reviewEvidence: return "doc.text.magnifyingglass"
        case .generateReport: return "doc.richtext"
        }
    }
}

struct AnalysisWorkflowStepBar: View {
    var hasImportedReports: Bool
    var selectedReportCount: Int
    var hasAIReply: Bool
    var hasEvidence: Bool
    var hasReport: Bool
    var isAnalysisRunning: Bool
    var isReportGenerating: Bool
    var taskName: String
    var importAction: () -> Void
    var selectReportsAction: () -> Void
    var focusComposerAction: () -> Void
    var reviewEvidenceAction: () -> Void
    var generateReportAction: () -> Void

    private var activeStep: AnalysisWorkflowStep {
        if !hasImportedReports { return .importData }
        if selectedReportCount == 0 { return .selectReports }
        if !hasAIReply { return .askAI }
        return .reviewEvidence
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: activeStep.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(activeStepTint)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(activeStep.title)
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(AppTheme.text)
                    Text("\(taskName) · \(statusText)")
                        .font(AppFont.caption())
                        .foregroundStyle(AppTheme.mutedText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                primaryActionButton
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: activeStep.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(activeStepTint)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activeStep.title)
                            .font(AppFont.caption(weight: .semibold))
                        Text("\(taskName) · \(statusText)")
                            .font(AppFont.caption())
                            .foregroundStyle(AppTheme.mutedText)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                primaryActionButton
            }
        }
        .padding(10)
        .background(AppTheme.panel.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.border.opacity(0.50), lineWidth: 1)
        }
    }

    private var primaryActionButton: some View {
        Button {
            perform(activeStep)
        } label: {
            Label(primaryActionTitle, systemImage: primaryActionIcon)
                .font(AppFont.caption(weight: .semibold))
                .lineLimit(1)
        }
        .buttonStyle(AppHoverButtonStyle(variant: .secondary))
        .help(helpText(for: activeStep))
    }

    private var primaryActionTitle: String {
        switch activeStep {
        case .importData: return "选择数据来源"
        case .selectReports: return "确认分析表"
        case .askAI: return "开始提问"
        case .reviewEvidence: return "查看证据"
        case .generateReport: return hasReport ? "生成/更新汇报" : "生成汇报"
        }
    }

    private var primaryActionIcon: String {
        switch activeStep {
        case .importData: return "tray.and.arrow.down"
        case .selectReports: return "tablecells"
        case .askAI: return "paperplane.fill"
        case .reviewEvidence: return "doc.text.magnifyingglass"
        case .generateReport: return "doc.richtext"
        }
    }

    private var activeStepTint: Color {
        switch activeStep {
        case .importData, .selectReports, .askAI, .reviewEvidence:
            return AppTheme.icon
        case .generateReport:
            return AppTheme.accent
        }
    }

    private func stepButton(_ step: AnalysisWorkflowStep) -> some View {
        let isComplete = isStepComplete(step)
        let isActive = activeStep == step
        return Button {
            perform(step)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : step.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isActive ? AppTheme.accent : (isComplete ? AppTheme.success : AppTheme.icon))
                    .frame(width: 15)
                Text("\(step.rawValue) \(step.title)")
                    .font(AppFont.caption(weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? AppTheme.accentStrong : AppTheme.mutedText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                isActive ? AppTheme.accent.opacity(0.12) : AppTheme.panelStrong.opacity(isComplete ? 0.42 : 0.30),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(isActive ? AppTheme.accent.opacity(0.28) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(helpText(for: step))
    }

    private var statusText: String {
        if isAnalysisRunning { return "正在分析" }
        if hasEvidence { return "证据可核对" }
        if hasAIReply { return "对话已开始" }
        if selectedReportCount > 0 { return "\(selectedReportCount) 张表已选" }
        if hasImportedReports { return "等待确认分析表" }
        return "等待导入数据"
    }

    private func isStepComplete(_ step: AnalysisWorkflowStep) -> Bool {
        switch step {
        case .importData: return hasImportedReports
        case .selectReports: return selectedReportCount > 0
        case .askAI: return hasAIReply
        case .reviewEvidence: return hasEvidence
        case .generateReport: return hasReport
        }
    }

    private func perform(_ step: AnalysisWorkflowStep) {
        switch step {
        case .importData: importAction()
        case .selectReports: selectReportsAction()
        case .askAI: focusComposerAction()
        case .reviewEvidence: reviewEvidenceAction()
        case .generateReport: generateReportAction()
        }
    }

    private func helpText(for step: AnalysisWorkflowStep) -> String {
        switch step {
        case .importData: return "导入本地表或 Tableau 视图"
        case .selectReports: return "确认本轮要一起分析的表"
        case .askAI: return "回到底部输入框提问"
        case .reviewEvidence: return "打开分析资料里的证据页"
        case .generateReport: return "基于当前会话生成完整汇报"
        }
    }
}

struct ComposerModeChipLabel: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let isDisabled: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
            Text(title)
                .font(AppFont.callout(weight: .semibold))
                .fontWeight(.semibold)
                .foregroundStyle(textColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(backgroundColor, in: Capsule())
        .overlay {
            Capsule()
                .stroke(borderColor, lineWidth: isSelected || isHovered ? 1 : 0)
        }
        .opacity(isDisabled ? 0.48 : 1)
        .contentShape(Capsule())
        .textSelection(.disabled)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .onHover { hovering in
            guard !isDisabled else { return }
            isHovered = hovering
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return AppTheme.accent.opacity(isHovered ? 0.18 : 0.12)
        }
        return AppTheme.panelStrong.opacity(isHovered ? 0.62 : 0.32)
    }

    private var borderColor: Color {
        if isSelected {
            return AppTheme.accent.opacity(isHovered ? 0.46 : 0.32)
        }
        return AppTheme.border.opacity(isHovered ? 0.52 : 0)
    }

    private var iconColor: Color {
        isSelected ? AppTheme.text : AppTheme.icon
    }

    private var textColor: Color {
        isSelected ? AppTheme.accentStrong : AppTheme.mutedText
    }
}

struct ComposerToolbarIcon: View {
    var systemImage: String
    var tint: Color = .secondary

    @State private var isHovered = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(
                AppTheme.panelStrong.opacity(isHovered ? 0.55 : 0),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

struct NoAnalysisDataSourceStartPanel: View {
    var importAction: () -> Void
    var tableauAction: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 7) {
                Image(systemName: "tablecells")
                    .font(.system(size: 28, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                Text("先选择数据来源")
                    .font(.title3.weight(.semibold))
                Text("导入本地多张表格，或接入 Tableau。导入后会直接进入“确认本次分析表”。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 520)
            }

            HStack(spacing: 10) {
                Button {
                    importAction()
                } label: {
                    Label("导入本地表", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .primary))

                Button {
                    tableauAction()
                } label: {
                    Label("接入 Tableau", systemImage: "chart.bar.doc.horizontal")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .secondary))
            }
            .font(.callout.weight(.medium))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(24)
    }
}
