import SwiftUI

struct AnalysisView: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    @State private var cachedTrendOverview = ""
    @State private var cachedTrendBullets: [String] = []
    @State private var cachedTrendSignature = ""
    @State private var isPreparingTrend = false

    var body: some View {
        ScrollView {
            if let pack = store.selectedPack {
                let currentTrendSignature = trendComputationID(for: pack)
                LazyVStack(alignment: .leading, spacing: 16) {
                    let blocker = store.analysisBlockerText(for: pack)

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("分析证据")
                                .font(.largeTitle)
                                .fontWeight(.semibold)
                            if let task = store.currentAnalysisTask(in: pack) {
                                Text("当前任务：\(task.name)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if !pack.analysisTasks.isEmpty {
                            Picker("分析任务", selection: Binding(
                                get: { store.currentAnalysisTask(in: pack)?.id ?? pack.analysisTasks.first!.id },
                                set: { store.selectAnalysisTask(taskID: $0) }
                            )) {
                                ForEach(pack.analysisTasks) { task in
                                    Text(task.name).tag(task.id)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 220)
                            .hoverControlShell(.pickerShell)
                        }
                        Button {
                            store.recomputeSelectedPack()
                        } label: {
                            Label("刷新事实层", systemImage: "arrow.clockwise")
                        }
                        .disabled(blocker != nil || store.isRunningAI)
                    }

                    if let session = store.selectedAnalysisSession,
                       session.packID == pack.id,
                       let latest = session.messages.last(where: { $0.role == .assistant && $0.kind != .error }) {
                        SectionCard(title: "会话最新 AI 输出", systemImage: "bubble.left.and.text.bubble.right") {
                            let outputSource = latest.kind == .aiMemo ? "完整汇报" : (latest.kind == .simpleReport ? "简洁汇报" : "AI 对话分析")
                            HStack {
                                Badge(text: session.status.label, systemImage: nil, tint: session.status == .reportReady ? AppTheme.success : AppTheme.accent)
                                Badge(text: outputSource, systemImage: nil, tint: latest.kind == .aiMemo ? .secondary : (latest.kind == .simpleReport ? AppTheme.warning : AppTheme.accent))
                                Text(session.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("进入会话") {
                                    store.requestAnalysisSessionNavigation()
                                }
                            }
                            Label("来源：\(outputSource)。这是一段 AI 基于表格、知识库、Confluence、外部参照和会话上下文生成的分析文本，不是原始事实层证据。", systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(latest.content)
                                .lineLimit(18)
                                .textSelection(.enabled)
                        }
                    } else {
                        WorkflowActionBanner(
                            title: "请使用分析会话生成结论",
                            detail: store.hasConfiguredAI ? "本页只展示数据覆盖、趋势事实和证据视图。最终归因、追问和结论请进入分析会话完成。" : "请先到 AI 设置填写 API Key。未配置 AI 时不会生成本地伪分析。",
                            actionTitle: store.hasConfiguredAI ? "进入分析会话" : "去 AI 设置",
                            actionSystemImage: store.hasConfiguredAI ? "bubble.left.and.text.bubble.right" : "gearshape"
                        ) {
                            store.requestedSidebarSelection = store.hasConfiguredAI ? .sessions : .settings
                        }
                    }

                    if let task = store.currentAnalysisTask(in: pack), !task.businessLinkProfile.edges.isEmpty {
                        SectionCard(title: "业务链路影响图", systemImage: "point.3.connected.trianglepath.dotted") {
                            Text(task.businessLinkProfile.summary)
                                .foregroundStyle(.secondary)
                            ForEach(task.businessLinkProfile.edges.prefix(8)) { edge in
                                BusinessLinkEdgeRow(edge: edge, reports: store.reportsForCurrentTask(in: pack))
                                Divider()
                            }
                        }
                    }

                    if let task = store.currentAnalysisTask(in: pack), !task.businessLinkProfile.metricLinks.isEmpty {
                        SectionCard(title: "指标级多表联动", systemImage: "arrow.triangle.branch") {
                            Text("只展示当前分析任务内已识别的指标关系；页面埋点只能作为行为路径解释，不能单独证明业务结果原因。")
                                .foregroundStyle(.secondary)
                            ForEach(task.businessLinkProfile.metricLinks.filter { $0.confirmationStatus != .rejected }.prefix(12)) { link in
                                CrossTableMetricLinkRow(link: link, reports: store.reportsForCurrentTask(in: pack))
                                Divider()
                            }
                        }
                    }

                    SectionCard(title: "AI 数据覆盖与推理日志", systemImage: "eye") {
                        let reports = store.reportsForCurrentTask(in: pack)
                        if reports.isEmpty {
                            Text("当前任务还没有参与报表，暂无 AI 数据覆盖记录。")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(reports) { report in
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack {
                                        Text(report.displayName)
                                            .fontWeight(.medium)
                                            .lineLimit(1)
                                        Spacer()
                                        if let analysis = report.aiFirstAnalysis {
                                            Badge(text: analysis.readyForAnalysis ? "AI 已理解" : "AI 待补数据", systemImage: nil, tint: analysis.readyForAnalysis ? AppTheme.success : AppTheme.warning)
                                        } else {
                                            Badge(text: "待运行", systemImage: nil, tint: AppTheme.warning)
                                        }
                                    }
                                    if let coverage = report.tableContextCoverage {
                                        Text("\(coverage.summary)。\(coverage.omittedRowsDescription)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    if let analysis = report.aiFirstAnalysis {
                                        Text(analysis.dataAvailability.isEmpty ? analysis.summary : analysis.dataAvailability)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .textSelection(.enabled)
                                    }
                                    if !report.aiDataRequests.isEmpty {
                                        Text("数据追问：\(report.aiDataRequests.prefix(4).map { "\($0.kind.rawValue): \($0.target)" }.joined(separator: "；"))")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                Divider()
                            }
                            if !pack.aiJobRecords.isEmpty {
                                DisclosureGroup("AI 作业记录") {
                                    ForEach(pack.aiJobRecords.prefix(12)) { record in
                                        Text("\(record.jobType)：\(record.status.label)，尝试 \(record.attemptCount)/\(record.maxAttempts)\(record.lastError.isEmpty ? "" : "，\(record.lastError)")")
                                            .font(.caption)
                                            .foregroundStyle(record.status == .needsUserAction ? AppTheme.danger : .secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }

                    SectionCard(title: blocker == nil ? "表格数据趋势" : "导入表格趋势扫描", systemImage: "tablecells") {
                        if isPreparingTrend && cachedTrendSignature != currentTrendSignature {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在准备趋势证据...")
                                    .foregroundStyle(.secondary)
                            }
                        } else if cachedTrendBullets.isEmpty {
                            Text(cachedTrendOverview.isEmpty ? "暂无报表趋势摘要。" : cachedTrendOverview)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        } else {
                            Text(cachedTrendOverview)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            BulletList(items: Array(cachedTrendBullets.prefix(100)))
                        }
                    }

                    if let blocker {
                        WorkflowActionBanner(
                            title: "分析已暂停",
                            detail: blocker,
                            actionTitle: "去分析会话",
                            actionSystemImage: "bubble.left.and.text.bubble.right"
                        ) {
                            store.requestDataPackAuditNavigation()
                        }
                    } else {
                        if let warning = store.analysisWarningText(for: pack) {
                            WorkflowBlockedBanner(title: "分析置信度提醒", detail: warning)
                        }

                        let timelineSignals = pack.analysisReport.contextSignals.filter { $0.domain == .timeline }
                        SectionCard(title: "时间线匹配证据", systemImage: "calendar.badge.clock") {
                            if timelineSignals.isEmpty {
                                Text("暂无表格时间段与知识库/外部情报的结构化匹配。Confluence 只使用需求文档自身创建/修改时间，不使用知识库同步或创建时间。")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(timelineSignals.prefix(8)) { signal in
                                    ContextSignalRow(signal: signal)
                                    Divider()
                                }
                            }
                        }

                        let nonTimelineSignals = pack.analysisReport.contextSignals.filter { $0.domain != .timeline }
                        SectionCard(title: "综合上下文信号", systemImage: "sparkles") {
                            if nonTimelineSignals.isEmpty {
                                Text("暂无知识库、竞品舆情、政策/市场或纠偏信号。")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(nonTimelineSignals.prefix(16)) { signal in
                                    ContextSignalRow(signal: signal)
                                    Divider()
                                }
                            }
                        }

                        SectionCard(title: "显著指标波动", systemImage: "chart.line.uptrend.xyaxis") {
                            if pack.analysisReport.metricInsights.isEmpty {
                                Text("未检测到显著波动。")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(pack.analysisReport.metricInsights) { insight in
                                    MetricInsightRow(insight: insight)
                                    Divider()
                                }
                            }
                        }

                        SectionCard(title: "归因结论", systemImage: "point.3.connected.trianglepath.dotted") {
                            if pack.analysisReport.attributionFindings.isEmpty {
                                Text("暂无归因结论。")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(pack.analysisReport.attributionFindings) { finding in
                                    AttributionFindingView(finding: finding)
                                    Divider()
                                }
                            }
                        }

                        SectionCard(title: "最后结论", systemImage: "text.magnifyingglass") {
                            Text(pack.analysisReport.summary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(18)
                .task(id: currentTrendSignature) {
                    await refreshTrendEvidence(for: pack, signature: currentTrendSignature)
                }
            } else {
                EmptyStateView(title: "没有可展示的证据", detail: "请先在分析会话中导入表格、选择本次分析表、编写目标并发送给 AI。", systemImage: "chart.line.uptrend.xyaxis")
            }
        }
    }

    private func trendComputationID(for pack: DataPack) -> String {
        let task = store.currentAnalysisTask(in: pack)
        let activeIDs = (task?.activeReportIDs ?? []).map(\.uuidString).sorted().joined(separator: ",")
        let activeReports = store.reportsForCurrentTask(in: pack)
        let reportStamp = reportsSignature(activeReports.isEmpty ? pack.importedReports : activeReports)
        return [
            pack.id.uuidString,
            task?.id.uuidString ?? "no-task",
            activeIDs,
            reportStamp,
            String(pack.analysisReport.generatedAt.timeIntervalSince1970)
        ].joined(separator: "#")
    }

    private func reportsSignature(_ reports: [ImportedReport]) -> String {
        var hasher = Hasher()
        hasher.combine(reports.count)
        for report in reports {
            hasher.combine(report.id)
            hasher.combine(report.importedAt)
            hasher.combine(report.rowCount)
            hasher.combine(report.headers.count)
            hasher.combine(report.trendSummary.metricTrends.count)
            hasher.combine(report.trendSummary.warnings.count)
        }
        return "\(reports.count):\(hasher.finalize())"
    }

    @MainActor
    private func refreshTrendEvidence(for pack: DataPack, signature: String) async {
        if cachedTrendSignature != signature {
            isPreparingTrend = true
        }
        await Task.yield()
        let activeReports = store.reportsForCurrentTask(in: pack)
        let hasImportedReports = !pack.importedReports.isEmpty
        let fallbackOverview = pack.analysisReport.tableTrendOverview
        let fallbackBullets = pack.analysisReport.tableTrendBullets
        let result = await Task.detached(priority: .userInitiated) {
            if !activeReports.isEmpty {
                return (
                    ReportTrendAnalyzer.combinedTrendOverview(for: activeReports),
                    ReportTrendAnalyzer.combinedTrendBullets(for: activeReports)
                )
            }
            if hasImportedReports {
                return (
                    "当前分析任务还没有选择表。请在分析资料中加入本次要分析的表。",
                    []
                )
            }
            return (fallbackOverview, fallbackBullets)
        }.value
        guard !Task.isCancelled else { return }
        cachedTrendOverview = result.0
        cachedTrendBullets = result.1
        cachedTrendSignature = signature
        isPreparingTrend = false
    }
}

private struct ContextSignalRow: View {
    var signal: AnalysisContextSignal

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: signal.domain.systemImage)
                .foregroundStyle(tint)
                .frame(width: 22)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(signal.title)
                        .fontWeight(.medium)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if let observedAt = signal.observedAt {
                        Text(DateFormatting.shortDate.string(from: observedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Badge(text: signal.domain.label, systemImage: nil, tint: tint)
                        Badge(text: "强度 \(signal.strength)", systemImage: nil, tint: .secondary)
                        Badge(text: signal.isInferredRelation ? "推断关联" : "事实", systemImage: nil, tint: signal.isInferredRelation ? AppTheme.warning : AppTheme.success)
                    }
                    if !signal.relatedMetric.isEmpty {
                        Text("关联指标：\(signal.relatedMetric)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
                Text(signal.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if !signal.relationReason.isEmpty {
                    Text(signal.relationReason)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let rawURL = signal.sourceURL, let url = URL(string: rawURL) {
                    Link("打开来源", destination: url)
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var tint: Color {
        switch signal.domain {
        case .tableTrend: return AppTheme.info
        case .knowledge: return AppTheme.info
        case .competitor: return AppTheme.danger
        case .policy: return .secondary
        case .market: return AppTheme.success
        case .externalEvent: return .cyan
        case .correction: return AppTheme.warning
        case .manual: return AppTheme.accent
        case .sourceCoverage: return .secondary
        case .timeline: return .cyan
        }
    }
}

private struct BusinessLinkEdgeRow: View {
    var edge: BusinessLinkEdge
    var reports: [ImportedReport]

    private var sourceName: String {
        reports.first(where: { $0.id == edge.sourceReportID })?.displayName ?? "上游报表"
    }

    private var targetName: String {
        reports.first(where: { $0.id == edge.targetReportID })?.displayName ?? "下游报表"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("\(sourceName) → \(targetName)")
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Badge(text: edge.confirmationStatus.label, systemImage: nil, tint: edge.confirmationStatus == .confirmed ? AppTheme.success : AppTheme.warning)
                Badge(text: "置信度 \(Int(edge.confidence * 100))%", systemImage: nil, tint: edge.confidence >= 0.72 ? AppTheme.success : AppTheme.warning)
            }
            Text(edge.hypothesis)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !edge.evidence.isEmpty {
                Text("证据：\(edge.evidence.prefix(3).joined(separator: "；"))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct CrossTableMetricLinkRow: View {
    var link: CrossTableMetricLink
    var reports: [ImportedReport]

    private var sourceName: String {
        reports.first(where: { $0.id == link.sourceReportID })?.displayName ?? "上游表"
    }

    private var targetName: String {
        reports.first(where: { $0.id == link.targetReportID })?.displayName ?? "下游表"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(sourceName).\(link.sourceMetric) → \(targetName).\(link.targetMetric)")
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                EvidenceBadge(level: link.evidenceLevel)
                Badge(text: "\(Int(link.confidence * 100))%", systemImage: nil, tint: link.confidence >= 0.72 ? AppTheme.success : AppTheme.warning)
            }
            Text("\(link.relationType.label)：\(link.directionAlignment)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !link.evidence.isEmpty {
                Text("依据：\(link.evidence.prefix(3).joined(separator: "；"))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct MetricInsightRow: View {
    var insight: MetricInsight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.direction == .up ? "arrow.up.right" : "arrow.down.right")
                .foregroundStyle(insight.direction == .up ? AppTheme.success : AppTheme.danger)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(insight.metric)
                        .fontWeight(.medium)
                    Text(insight.scope)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Badge(text: insight.severity.rawValue, systemImage: nil, tint: insight.severity == .high ? AppTheme.danger : insight.severity == .medium ? AppTheme.warning : .secondary)
                    Text(insight.formattedChange)
                        .font(.headline)
                        .foregroundStyle(insight.direction == .up ? AppTheme.success : AppTheme.danger)
                }
                Text("最近窗口：\(insight.currentAverage.compactText)，对比窗口：\(insight.previousAverage.compactText)，观察至 \(DateFormatting.shortDate.string(from: insight.endDate))。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct AttributionFindingView: View {
    var finding: AttributionFinding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                EvidenceBadge(level: finding.evidenceLevel)
                Text(finding.title)
                    .fontWeight(.medium)
                Spacer()
                Text("置信度 \(finding.confidence)/10")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(finding.primaryCause)
            if !finding.supportingSignals.isEmpty {
                DisclosureGroup("支持信号") {
                    BulletList(items: finding.supportingSignals)
                }
            }
            if !finding.counterSignals.isEmpty {
                DisclosureGroup("反证与干扰") {
                    BulletList(items: finding.counterSignals)
                }
            }
            if !finding.recommendedNextData.isEmpty {
                DisclosureGroup("需要补充的数据") {
                    BulletList(items: finding.recommendedNextData)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct BulletList: View {
    var items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items, id: \.self) { item in
                Text("• \(item)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }
}
