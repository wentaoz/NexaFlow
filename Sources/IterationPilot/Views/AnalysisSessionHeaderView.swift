import SwiftUI

struct LiveAIJobSnapshot: Identifiable, Equatable {
    var id: UUID
    var status: AIJobStatus
    var kind: PersistentAIJobKind
    var updatedAt: Date
    var attemptCount: Int
    var recordAttemptCount: Int
    var maxImmediateAttempts: Int
    var delayedRetryCount: Int
    var latestDetail: String

    init(job: PersistentAIJob) {
        id = job.id
        status = job.status
        kind = job.kind
        updatedAt = job.updatedAt
        attemptCount = job.attemptCount
        recordAttemptCount = job.record.attemptCount
        maxImmediateAttempts = job.maxImmediateAttempts
        delayedRetryCount = job.delayedRetryCount
        latestDetail = (job.logs.last?.detail.nilIfBlank ?? job.record.logs.last?.detail.nilIfBlank ?? "")
            .replacingOccurrences(of: "\n", with: " ")
    }

    var displayedAttemptCount: Int {
        max(attemptCount, recordAttemptCount)
    }
}

struct NextActionBanner: View {
    struct ActionState {
        var title: String
        var detail: String
        var systemImage: String
    }

    var action: ActionState

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SemanticIcon(systemName: action.systemImage, role: .ai, size: 16, frameWidth: 22)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(action.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(action.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct AnalysisFlowGuide: View {
    var hasImportedReports: Bool
    var selectedReportCount: Int
    var hasMessages: Bool
    var hasReport: Bool
    var isAnalysisRunning: Bool
    var isReportGenerating: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                step(title: "导入表格", value: hasImportedReports ? "已导入" : "先导入", isDone: hasImportedReports)
                step(title: "选择分析表", value: selectedReportCount > 0 ? "\(selectedReportCount) 张" : "未选", isDone: selectedReportCount > 0)
                step(title: "和 AI 对话分析", value: isAnalysisRunning ? "分析中" : (hasMessages ? "已开始" : "未开始"), isDone: hasMessages, isRunning: isAnalysisRunning)
                step(title: "报告", value: isReportGenerating ? "生成中" : (hasReport ? "已生成" : "待生成"), isDone: hasReport, isRunning: isReportGenerating)
            }
            VStack(alignment: .leading, spacing: 6) {
                step(title: "导入表格", value: hasImportedReports ? "已导入" : "先导入", isDone: hasImportedReports)
                step(title: "选择分析表", value: selectedReportCount > 0 ? "\(selectedReportCount) 张" : "未选", isDone: selectedReportCount > 0)
                step(title: "和 AI 对话分析", value: isAnalysisRunning ? "分析中" : (hasMessages ? "已开始" : "未开始"), isDone: hasMessages, isRunning: isAnalysisRunning)
                step(title: "报告", value: isReportGenerating ? "生成中" : (hasReport ? "已生成" : "待生成"), isDone: hasReport, isRunning: isReportGenerating)
            }
        }
    }

    private func step(title: String, value: String, isDone: Bool, isRunning: Bool = false) -> some View {
        HStack(spacing: 6) {
            if isRunning {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.55)
                    .frame(width: 12, height: 12)
            } else {
                SemanticIcon(systemName: isDone ? "checkmark.circle.fill" : "circle", role: isDone ? .success : .neutral, size: 12, frameWidth: 14)
            }
            Text(title)
                .fontWeight(.medium)
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct LiveJobBadge: View {
    var job: LiveAIJobSnapshot

    var body: some View {
        HStack(spacing: 5) {
            if job.status == .waiting && job.delayedRetryCount > 0 {
                SemanticIcon(systemName: "clock.arrow.circlepath", role: .external, size: 12, frameWidth: 14)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.55)
                    .frame(width: 12, height: 12)
            }
            Text(title)
                .lineLimit(1)
        }
        .font(.caption)
        .fontWeight(.semibold)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(AppTheme.accent)
        .background(AppTheme.accent.opacity(0.12), in: Capsule())
    }

    private var title: String {
        if job.status == .waiting && job.delayedRetryCount > 0 {
            return "自动重试中"
        }
        switch job.status {
        case .correcting:
            return "自动修正中"
        case .waiting:
            return "等待执行"
        case .requesting, .validating:
            if job.kind == .memo {
                return "完整汇报生成中"
            }
            if job.kind == .simpleReportGeneration {
                return "简洁汇报生成中"
            }
            return "正在分析"
        case .needsUserAction:
            return "需要处理"
        case .cancelled:
            return "已取消"
        case .failed:
            return "已失败"
        case .completed:
            return "已完成"
        }
    }
}

struct LiveAnalysisStatusBar: View {
    var job: LiveAIJobSnapshot
    var reportRequirementCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            LiveJobBadge(job: job)
            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var statusTitle: String {
        switch job.kind {
        case .simpleReportGeneration:
            return "正在生成简洁汇报"
        case .memo:
            return "正在生成完整汇报"
        case .analysisSession:
            return "正在分析当前会话"
        default:
            return job.kind.label
        }
    }

    private var detailText: String {
        let latestLog = job.latestDetail.nilIfBlank ?? job.status.label
        let requirementText = (job.kind == .memo || job.kind == .simpleReportGeneration) ? "；报告将覆盖 \(reportRequirementCount) 个会话问题" : ""
        return "\(job.status.label) · 第 \(job.displayedAttemptCount)/\(job.maxImmediateAttempts) 次\(requirementText)；\(latestLog)"
    }
}

struct ReportRequirementHint: View {
    var count: Int
    var generatedAt: Date?

    var body: some View {
        HStack(spacing: 8) {
            SemanticIcon(systemName: "checklist.checked", role: .success, size: 14, frameWidth: 18)
            Text("本报告已按 \(count) 个会话问题生成\(generatedAt.map { " · \(DateFormatting.shortDateTime.string(from: $0))" } ?? "")。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(AppTheme.success.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SessionStartPanel: View {
    var pack: DataPack
    var selectedReportCount: Int
    var createAction: () -> Void
    var chooseReportsAction: () -> Void
    var importAction: () -> Void

    private var importedReportCount: Int {
        pack.importedReports.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                AnalysisFlowGuide(
                    hasImportedReports: importedReportCount > 0,
                    selectedReportCount: selectedReportCount,
                    hasMessages: false,
                    hasReport: false,
                    isAnalysisRunning: false,
                    isReportGenerating: false
                )

                NextActionBanner(action: nextAction)

                if importedReportCount == 0 {
                    SectionCard(title: "先导入表格", systemImage: "tray.and.arrow.down") {
                        Text("当前分析资料还没有表。导入 CSV、TSV、XLSX 或 XLS 后，系统会先本地解析和质检，再让你确认本次分析表。")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            importAction()
                        } label: {
                            Label("导入表格", systemImage: "tray.and.arrow.down")
                        }
                        .buttonStyle(AppHoverButtonStyle(variant: .primary))
                    }
                } else {
                    importedReportsStartContent
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.window)
    }

    @ViewBuilder
    private var importedReportsStartContent: some View {
        SectionCard(title: "已导入，待选择本次分析表", systemImage: "tablecells") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    metric(title: "已导入报表", value: "\(importedReportCount) 张")
                    metric(title: "当前任务已选", value: "\(selectedReportCount) 张")
                    metric(title: "AI 自动分析", value: "未开始")
                }
                VStack(alignment: .leading, spacing: 8) {
                    metric(title: "已导入报表", value: "\(importedReportCount) 张")
                    metric(title: "当前任务已选", value: "\(selectedReportCount) 张")
                    metric(title: "AI 自动分析", value: "未开始")
                }
            }

            Text("导入后会先弹出确认页，勾选本次要一起分析的表；后续也可以在右侧“分析资料”里调整。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    createAction()
                } label: {
                    Label("创建分析会话", systemImage: "plus.bubble")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .primary))

                Button {
                    chooseReportsAction()
                } label: {
                    Label("选择本次分析表", systemImage: "sidebar.right")
                }

                Button {
                    importAction()
                } label: {
                    Label("导入更多表格", systemImage: "tray.and.arrow.down")
                }
            }
            .buttonStyle(AppHoverButtonStyle(variant: .secondary))
        }

        SectionCard(title: "最近导入的报表", systemImage: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(pack.importedReports.prefix(6)) { report in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "tablecells")
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(report.displayName)
                                .fontWeight(.medium)
                                .lineLimit(2)
                            Text("\(report.sourceFormat.label) · \(report.shape.label) · \(report.kind.label) · \(report.rowCount) 行 · 字段 \(report.headers.count) 个 · 首列指标 \(report.firstColumnValues.count) 个")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                titleBlock
                Spacer()
                quickActions
            }
            VStack(alignment: .leading, spacing: 10) {
                titleBlock
                quickActions
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("开始分析")
                .font(.title2)
                .fontWeight(.semibold)
            Text("\(pack.name) · \(importedReportCount > 0 ? "已导入 \(importedReportCount) 张报表" : "暂无报表")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            Button {
                createAction()
            } label: {
                Label("创建分析会话", systemImage: "plus.bubble")
            }
            .disabled(importedReportCount == 0)

            Button {
                importAction()
            } label: {
                Label(importedReportCount == 0 ? "导入表格" : "导入更多表格", systemImage: "tray.and.arrow.down")
            }
        }
    }

    private var nextAction: NextActionBanner.ActionState {
        if importedReportCount == 0 {
            return .init(
                title: "下一步：先导入表格",
                detail: "导入后页面会进入分析会话工作台，但不会自动调用 AI，也不会自动联动所有表。",
                systemImage: "tray.and.arrow.down"
            )
        }
        return .init(
            title: "下一步：确认本次分析表",
            detail: "导入后会弹出确认页，直接选择本次要分析的表和角色；也可以稍后在“分析资料”中调整。",
            systemImage: "tablecells"
        )
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(minWidth: 150, alignment: .leading)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}
