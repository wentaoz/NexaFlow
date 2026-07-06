import AppKit
import SwiftUI

private struct MessageNeutralLabel: View {
    var title: String
    var systemImage: String
    var tint: Color = .secondary
    var iconSize: CGFloat = 13
    var spacing: CGFloat = 6

    var body: some View {
        HStack(spacing: spacing) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: iconSize + 5)
            Text(title)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct SessionListRowSnapshot: Identifiable, Equatable {
    var id: UUID
    var title: String
    var goal: String
    var status: AnalysisSessionStatus
    var updatedAt: Date
    var hasFinalReport: Bool

    init(session: AnalysisSession) {
        id = session.id
        title = session.title
        goal = session.goal
        status = session.status
        updatedAt = session.updatedAt
        hasFinalReport = !session.finalReportMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct SessionListActiveJobSnapshot: Equatable {
    var id: UUID
    var status: AIJobStatus
    var updatedAt: Date
    var delayedRetryCount: Int
    var kind: PersistentAIJobKind

    init(job: PersistentAIJob) {
        id = job.id
        status = job.status
        updatedAt = job.updatedAt
        delayedRetryCount = job.delayedRetryCount
        kind = job.kind
    }
}

struct SessionListRow: View, Equatable {
    var snapshot: SessionListRowSnapshot
    var isSelected: Bool
    var activeJob: SessionListActiveJobSnapshot?
    var sourcePackMissing: Bool
    var archiveAction: () -> Void
    var restoreAction: () -> Void
    var deleteAction: () -> Void

    @State private var isHovered = false

    static func == (lhs: SessionListRow, rhs: SessionListRow) -> Bool {
        lhs.snapshot == rhs.snapshot &&
            lhs.isSelected == rhs.isSelected &&
            lhs.sourcePackMissing == rhs.sourcePackMissing &&
            lhs.activeJob == rhs.activeJob
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 7, height: 7)
                .overlay {
                    if activeJob != nil {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.38)
                            .frame(width: 12, height: 12)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.title)
                    .font(AppFont.callout(weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(primaryTextColor)
                Text(metaText)
                    .font(AppFont.caption2())
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                if snapshot.status == .archived {
                    Button {
                        restoreAction()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 16)
                    }
                    .buttonStyle(SessionListActionButtonStyle(isSelected: isSelected))
                    .help("恢复会话")
                } else {
                    Button {
                        archiveAction()
                    } label: {
                        Image(systemName: "archivebox")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 16)
                    }
                    .buttonStyle(SessionListActionButtonStyle(isSelected: isSelected))
                    .help("归档会话")
                }
                Button(role: .destructive) {
                    deleteAction()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 16)
                }
                .buttonStyle(SessionListActionButtonStyle(isSelected: isSelected, isDestructive: true))
                .help("永久删除会话")
            }
            .controlSize(.small)
            .opacity(showsManagementActions ? 1 : 0)
            .allowsHitTesting(showsManagementActions)
            .animation(.easeOut(duration: 0.10), value: showsManagementActions)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(minHeight: 46)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .textSelection(.disabled)
        .help(snapshot.goal.nilIfBlank ?? snapshot.title)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .onHover { isHovered = $0 }
    }

    private var showsManagementActions: Bool {
        isHovered || isSelected
    }

    private var primaryTextColor: Color {
        AppTheme.text
    }

    private var secondaryTextColor: Color {
        AppTheme.mutedText
    }

    private var backgroundStyle: Color {
        if isSelected {
            return AppTheme.accent.opacity(isHovered ? 0.15 : 0.11)
        }
        return AppTheme.panelStrong.opacity(isHovered ? 0.48 : 0)
    }

    private var metaText: String {
        var parts: [String] = []
        if let activeJob {
            parts.append(jobLabel(activeJob))
        } else {
            parts.append(statusLabel)
        }
        if sourcePackMissing {
            parts.append("原始资料已删除")
        }
        parts.append(DateFormatting.shortDateTime.string(from: snapshot.updatedAt))
        return parts.joined(separator: " · ")
    }

    private var statusDotColor: Color {
        if activeJob != nil {
            return AppTheme.accent
        }
        if sourcePackMissing {
            return AppTheme.warning
        }
        switch snapshot.status {
        case .reportReady: return snapshot.hasFinalReport ? AppTheme.success : AppTheme.icon
        case .analyzing: return AppTheme.accent
        case .archived: return AppTheme.faintText
        default: return AppTheme.icon
        }
    }

    private var statusLabel: String {
        if snapshot.status == .analyzing {
            return AnalysisSessionStatus.waitingForUser.label
        }
        if snapshot.status == .reportReady && !snapshot.hasFinalReport {
            return AnalysisSessionStatus.waitingForUser.label
        }
        return snapshot.status.label
    }

    private func jobLabel(_ job: SessionListActiveJobSnapshot) -> String {
        if job.status == .waiting && job.delayedRetryCount > 0 {
            return "自动重试中"
        }
        if job.kind == .simpleReportGeneration {
            return job.status == .waiting ? "简洁汇报排队中" : "简洁汇报生成中"
        }
        if job.kind == .memo {
            return job.status == .waiting ? "完整汇报排队中" : "完整汇报生成中"
        }
        return job.status == .waiting ? "分析排队中" : "AI 分析中"
    }
}

private struct SessionListBadge: View {
    var text: String
    var tint: Color
    var isSelected: Bool

    var body: some View {
        Text(text)
            .font(AppFont.caption2())
            .fontWeight(.medium)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundStyle, in: Capsule())
            .foregroundStyle(foregroundStyle)
    }

    private var foregroundStyle: Color {
        isSelected ? AppTheme.surface : tint
    }

    private var backgroundStyle: Color {
        isSelected ? AppTheme.surface.opacity(0.18) : tint.opacity(0.12)
    }
}

private struct SessionListActionButtonStyle: ButtonStyle {
    var isSelected: Bool
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        SessionListActionButtonStyleBody(
            configuration: configuration,
            isSelected: isSelected,
            isDestructive: isDestructive
        )
    }

    private struct SessionListActionButtonStyleBody: View {
        let configuration: ButtonStyle.Configuration
        let isSelected: Bool
        let isDestructive: Bool

        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .fontWeight(.medium)
                .foregroundStyle(foregroundStyle)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 6))
                .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .textSelection(.disabled)
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
                .onHover { hovering in
                    guard isEnabled else { return }
                    isHovered = hovering
                }
        }

        private var foregroundStyle: Color {
            if isDestructive && !isSelected {
                return AppTheme.danger
            }
            return AppTheme.icon
        }

        private var backgroundStyle: Color {
            guard isEnabled else { return .clear }
            if isDestructive {
                return AppTheme.danger.opacity(isHovered || configuration.isPressed ? (isSelected ? 0.20 : 0.12) : 0.00)
            }
            if isSelected {
                return AppTheme.surface.opacity(isHovered || configuration.isPressed ? 0.18 : 0.00)
            }
            return AppTheme.panelStrong.opacity(isHovered || configuration.isPressed ? 0.55 : 0.00)
        }
    }
}

struct LiveMiniJobIndicator: View {
    var job: SessionListActiveJobSnapshot
    var isSelected = false

    var body: some View {
        HStack(spacing: 4) {
            if job.status == .waiting && job.delayedRetryCount > 0 {
                Image(systemName: "clock.arrow.circlepath")
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(isSelected ? AppTheme.surface : AppTheme.accent)
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
            }
            Text(label)
        }
        .font(.caption2)
        .fontWeight(.semibold)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(isSelected ? AppTheme.surface : AppTheme.accentStrong)
        .background(isSelected ? AppTheme.surface.opacity(0.18) : AppTheme.accent.opacity(0.12), in: Capsule())
    }

    private var label: String {
        if job.status == .waiting && job.delayedRetryCount > 0 {
            return "自动重试中"
        }
        if job.kind == .simpleReportGeneration {
            return job.status == .waiting ? "简洁汇报排队中" : "简洁汇报生成中"
        }
        if job.kind == .memo {
            return job.status == .waiting ? "完整汇报排队中" : "完整汇报生成中"
        }
        return job.status == .waiting ? "分析排队中" : "AI 分析中"
    }
}

struct SessionMessageRenderSnapshot: Equatable {
    var id: UUID
    var createdAt: Date
    var role: AnalysisSessionMessageRole
    var kind: AnalysisSessionMessageKind
    var contentFingerprint: BoundedTextFingerprint
    var streamingStatus: StreamingStatusSnapshot?
    var evidence: EvidenceSnapshot
    var adoptedAs: [String]
    var replyToMessageID: UUID?
    var quotedMessageSummaryFingerprint: BoundedTextFingerprint?
    var correctionStatus: AnalysisMessageCorrectionStatus
    var supersededByMessageID: UUID?
    var savedCorrectionMemoryID: UUID?
    var reportInclusion: AnalysisMessageReportInclusion

    init(message: AnalysisSessionMessage) {
        id = message.id
        createdAt = message.createdAt
        role = message.role
        kind = message.kind
        contentFingerprint = BoundedTextFingerprint(message.content)
        streamingStatus = message.streamingStatus.map(StreamingStatusSnapshot.init(status:))
        evidence = EvidenceSnapshot(evidence: message.evidence)
        adoptedAs = message.adoptedAs
        replyToMessageID = message.replyToMessageID
        quotedMessageSummaryFingerprint = message.quotedMessageSummary.map(BoundedTextFingerprint.init(_:))
        correctionStatus = message.correctionStatus
        supersededByMessageID = message.supersededByMessageID
        savedCorrectionMemoryID = message.savedCorrectionMemoryID
        reportInclusion = message.reportInclusion
    }

    struct BoundedTextFingerprint: Equatable {
        var utf8Count: Int
        var prefix: String
        var suffix: String

        init(_ text: String) {
            utf8Count = text.utf8.count
            prefix = String(text.prefix(96))
            suffix = String(text.suffix(96))
        }
    }

    struct StreamingStatusSnapshot: Equatable {
        var state: AnalysisMessageStreamingStatusState
        var title: String
        var detailFingerprint: BoundedTextFingerprint
        var updatedAt: Date

        init(status: AnalysisMessageStreamingStatus) {
            state = status.state
            title = status.title
            detailFingerprint = BoundedTextFingerprint(status.detail)
            updatedAt = status.updatedAt
        }
    }

    struct EvidenceSnapshot: Equatable {
        var count: Int
        var items: [EvidenceItemSnapshot]
        var harnesses: [HarnessSnapshot]

        init(evidence: [AnalysisSessionEvidence]) {
            count = evidence.count
            items = evidence
                .prefix(20)
                .map(EvidenceItemSnapshot.init(evidence:))
            harnesses = evidence.compactMap(\.analysisHarnessRun).map(HarnessSnapshot.init(run:))
        }

        struct EvidenceItemSnapshot: Equatable {
            var id: UUID
            var sourceType: String
            var title: BoundedTextFingerprint
            var detail: BoundedTextFingerprint
            var sourceID: String?
            var sourceURL: String?

            init(evidence: AnalysisSessionEvidence) {
                id = evidence.id
                sourceType = evidence.sourceType
                title = BoundedTextFingerprint(evidence.title)
                detail = BoundedTextFingerprint(evidence.detail)
                sourceID = evidence.sourceID
                sourceURL = evidence.sourceURL
            }
        }

        struct HarnessSnapshot: Equatable {
            var id: UUID
            var status: AnalysisHarnessStatus
            var verifiedResultCount: Int
            var validationIssueCount: Int
            var answerNumberTraceCount: Int
            var reportMarkdown: BoundedTextFingerprint

            init(run: AnalysisHarnessRun) {
                id = run.id
                status = run.status
                verifiedResultCount = run.verifiedResults.count
                validationIssueCount = run.validationIssues.count
                answerNumberTraceCount = run.answerNumberTraces?.count ?? 0
                reportMarkdown = BoundedTextFingerprint(run.reportMarkdown)
            }
        }
    }
}

private final class EvidenceLinkedContentCache {
    private final class Box {
        let value: String

        init(_ value: String) {
            self.value = value
        }
    }

    private let cache = NSCache<NSString, Box>()

    init() {
        cache.countLimit = 80
        cache.totalCostLimit = 1_200_000
    }

    func value(
        messageID: UUID,
        displayedContent: String,
        run: AnalysisHarnessRun,
        traces: [AnswerNumberTrace],
        compute: () -> String
    ) -> String {
        let key = cacheKey(
            messageID: messageID,
            displayedContent: displayedContent,
            run: run,
            traces: traces
        )
        if let cached = cache.object(forKey: key) {
            return cached.value
        }
        let linked = PerformanceTrace.measure(
            "message.linkedEvidenceContent",
            metadata: "chars=\(displayedContent.utf8.count) traces=\(traces.count)"
        ) {
            compute()
        }
        cache.setObject(Box(linked), forKey: key, cost: linked.utf8.count)
        return linked
    }

    private func cacheKey(
        messageID: UUID,
        displayedContent: String,
        run: AnalysisHarnessRun,
        traces: [AnswerNumberTrace]
    ) -> NSString {
        let contentFingerprint = SessionMessageRenderSnapshot.BoundedTextFingerprint(displayedContent)
        let traceFingerprint = traces.prefix(80).map { trace in
            let rawFingerprint = SessionMessageRenderSnapshot.BoundedTextFingerprint(trace.rawText)
            return [
                trace.status.rawValue,
                trace.matchedResultID?.uuidString ?? "",
                "\(rawFingerprint.utf8Count)",
                rawFingerprint.prefix,
                rawFingerprint.suffix
            ].joined(separator: ":")
        }
        .joined(separator: "|")
        return [
            messageID.uuidString,
            run.id.uuidString,
            "\(run.status.rawValue)",
            "\(contentFingerprint.utf8Count)",
            contentFingerprint.prefix,
            contentFingerprint.suffix,
            "\(traces.count)",
            traceFingerprint
        ].joined(separator: "||") as NSString
    }
}

struct SessionMessageCard: View, Equatable {
    private enum CopyFeedbackState {
        case copied
        case failed

        var title: String {
            switch self {
            case .copied: return "已复制"
            case .failed: return "复制失败"
            }
        }

        var systemImage: String {
            switch self {
            case .copied: return "checkmark"
            case .failed: return "exclamationmark.triangle"
            }
        }
    }

    var message: AnalysisSessionMessage
    var renderSnapshot: SessionMessageRenderSnapshot
    var isLatestAssistant: Bool
    var isStreamingAssistant: Bool = false
    var latestExpansionOverride: Bool?
    var isExpanded: Bool
    var followUpAction: () -> Void
    var viewEvidenceAction: () -> Void
    var focusMetricEvidenceAction: (UUID?, [HarnessSourceCellRef]) -> Void = { _, _ in }
    var explainEvidenceAction: () -> Void
    var challengeAction: () -> Void
    var correctionAction: () -> Void
    var adoptAction: () -> Void
    var importSupplementDataAction: () -> Void
    var markExistingDataAction: () -> Void
    var setReportInclusionAction: (AnalysisMessageReportInclusion) -> Void
    var generateFullReportAction: () -> Void
    var generateFullReportForQuestionAction: () -> Void
    var generateSimpleReportForQuestionAction: () -> Void
    var toggleExpandedAction: () -> Void
    @State private var copyFeedbackState: CopyFeedbackState?
    private static let linkedContentCache = EvidenceLinkedContentCache()

    private var answerPresentation: AnalysisAnswerPresentation? {
        guard message.role == .assistant,
              message.kind == .aiAnalysis || message.kind == .aiMemo || message.kind == .simpleReport else {
            return nil
        }
        return AnalysisAnswerPresentation.parse(message.content)
    }

    static func == (lhs: SessionMessageCard, rhs: SessionMessageCard) -> Bool {
        lhs.renderSnapshot == rhs.renderSnapshot &&
            lhs.isLatestAssistant == rhs.isLatestAssistant &&
            lhs.isStreamingAssistant == rhs.isStreamingAssistant &&
            lhs.latestExpansionOverride == rhs.latestExpansionOverride &&
            lhs.isExpanded == rhs.isExpanded
    }

    var body: some View {
        if isCompactCoverageMessage {
            compactCoverageBody
        } else {
            regularBody
        }
    }

    private var regularBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                MessageNeutralLabel(title: message.role.label, systemImage: iconName, iconSize: 14)
                    .font(AppFont.caption())
                    .fontWeight(.semibold)
                Badge(text: kindLabel, systemImage: nil, tint: tint)
                if canCollapse {
                    collapseToggleButton
                }
                if message.correctionStatus != .none {
                    Badge(
                        text: message.correctionStatus.excludesFromFinalConclusion ? "已纠偏，不进报告" : message.correctionStatus.label,
                        systemImage: nil,
                        tint: message.correctionStatus.excludesFromFinalConclusion ? AppTheme.danger : AppTheme.warning
                    )
                    .help(message.correctionStatus.excludesFromFinalConclusion ? "这条旧 AI 结论已被后续纠偏覆盖，生成汇报时只作为反例，不作为最终结论。" : "这条回复处于纠偏流程中。")
                }
                Spacer()
                Text(DateFormatting.shortDateTime.string(from: message.createdAt))
                    .font(AppFont.caption2())
                    .foregroundStyle(AppTheme.mutedText)
            }
            VStack(alignment: .leading, spacing: 6) {
                if let streamingStatus = message.streamingStatus {
                    AnalysisMessageStreamingStatusView(status: streamingStatus)
                }
                if showsAnalysisEvidenceBar {
                    analysisEvidenceBar
                }
                if let displayedContent = displayedContent.nilIfBlank {
                    if isCollapsed {
                        Text(displayedContent)
                            .lineLimit(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .transaction { transaction in
                                transaction.animation = nil
                            }
                    } else if isStreamingAssistant {
                        Text(displayedContent)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .transaction { transaction in
                                transaction.animation = nil
                            }
                    } else {
                        MarkdownMessageRenderer(linkedDisplayedContent)
                            .environment(\.openURL, OpenURLAction { url in
                                handleEvidenceLink(url)
                            })
                            .textSelection(.enabled)
                            .transaction { transaction in
                                transaction.animation = nil
                            }
                    }
                }
                if canCollapse {
                    collapseToggleButton
                }
            }
            if let quoted = message.quotedMessageSummary, !quoted.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.icon)
                        .frame(width: 17)
                    Text("引用回复：\(quoted)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(7)
                .background(AppTheme.panel.opacity(0.58), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AppTheme.border.opacity(0.48), lineWidth: 1)
                }
            }
            if !isCollapsed {
                if answerPresentation?.hasSupportingSections == true {
                    separatedEvidenceHint
                } else if let coverage = dataCoverageEvidence {
                    DisclosureGroup("本轮 AI 读取范围") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(coverage.detail)
                                .font(AppFont.caption())
                                .foregroundStyle(AppTheme.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 4)
                    }
                }
                if showsSupplementDataActions {
                    HStack(spacing: 8) {
                        Button {
                            importSupplementDataAction()
                        } label: {
                            MessageNeutralLabel(title: "导入补充数据", systemImage: "tray.and.arrow.down")
                        }
                        .help("导入 AI 在补数清单里提到的业务表或明细表")
                        Button {
                            markExistingDataAction()
                        } label: {
                            MessageNeutralLabel(title: "我已有这些数据", systemImage: "checkmark.circle")
                        }
                        .help("让 AI 回到当前任务表里重新核对补数清单是否已经被覆盖")
                        Spacer()
                    }
                    .buttonStyle(AppHoverButtonStyle(variant: .ghost))
                    .controlSize(.small)
                    .font(AppFont.caption())
                }
                if answerPresentation?.hasSupportingSections != true, !nonCoverageEvidence.isEmpty {
                    DisclosureGroup("引用证据 \(nonCoverageEvidence.count) 条") {
                        ForEach(nonCoverageEvidence.prefix(12)) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(item.sourceType)：\(item.title)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.mutedText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                if message.role == .assistant && message.kind != .error {
                    assistantPrimaryActions
                }
                if message.role == .user {
                    userPrimaryActions
                }
            }
        }
        .padding(12)
        .background(background, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.border.opacity(message.role == .user ? 0.38 : 0.48), lineWidth: 1)
        }
    }

    private var assistantPrimaryActions: some View {
        HStack(spacing: 8) {
            Button {
                followUpAction()
            } label: {
                MessageNeutralLabel(title: "追问", systemImage: "arrowshape.turn.up.left")
            }
            .help("围绕这条回复继续追问。")

            Button {
                viewEvidenceAction()
            } label: {
                MessageNeutralLabel(title: "查看证据", systemImage: "doc.text.magnifyingglass")
            }
            .help("打开分析资料里的证据页，核对读取范围、SQL/Notebook 和外部证据。")

            Button {
                copyMessageContent()
            } label: {
                copyActionLabel
            }
            .help(answerPresentation == nil ? "复制这条 AI 回复。" : "复制这条 AI 回复的直接回答。")

            copyInlineFeedback

            Menu {
                if answerPresentation != nil {
                    Button {
                        copyMessageContent(includeFullSource: true)
                    } label: {
                        MessageNeutralLabel(title: "复制完整原文", systemImage: "doc.on.doc.fill")
                    }
                    Divider()
                }
                Button {
                    explainEvidenceAction()
                } label: {
                    MessageNeutralLabel(title: "解释证据", systemImage: "doc.text.magnifyingglass")
                }
                Button {
                    challengeAction()
                } label: {
                    MessageNeutralLabel(title: "质疑结论", systemImage: "exclamationmark.bubble")
                }
                Button {
                    correctionAction()
                } label: {
                    MessageNeutralLabel(title: message.adoptedAs.contains("纠偏记忆") ? "已保存纠偏规则" : "保存为纠偏规则", systemImage: "checkmark.seal")
                }
                .disabled(message.adoptedAs.contains("纠偏记忆"))
                Button {
                    adoptAction()
                } label: {
                    MessageNeutralLabel(title: message.adoptedAs.contains("知识库") ? "已沉淀到知识库" : "沉淀进知识库", systemImage: "books.vertical")
                }
                .disabled(message.adoptedAs.contains("知识库"))
            } label: {
                MessageNeutralLabel(title: "更多", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("更多操作")

            Spacer()
        }
        .buttonStyle(AppHoverButtonStyle(variant: .ghost))
        .controlSize(.small)
        .font(AppFont.caption())
    }

    private var userPrimaryActions: some View {
        HStack(spacing: 8) {
            Button {
                copyMessageContent()
            } label: {
                copyActionLabel
            }
            .help("复制这条问题。")
            copyInlineFeedback
            Spacer()
        }
        .buttonStyle(AppHoverButtonStyle(variant: .ghost))
        .controlSize(.small)
        .font(AppFont.caption())
    }

    private var dataCoverageEvidence: AnalysisSessionEvidence? {
        message.evidence.first { $0.sourceType == "数据覆盖" }
    }

    private var analysisHarnessRun: AnalysisHarnessRun? {
        message.evidence.first { $0.analysisHarnessRun != nil }?.analysisHarnessRun
    }

    private var nonCoverageEvidence: [AnalysisSessionEvidence] {
        message.evidence.filter { $0.sourceType != "数据覆盖" }
    }

    private var showsSupplementDataActions: Bool {
        message.role == .assistant &&
            answerPresentation?.hasSupportingSections != true &&
            (message.content.contains("建议补充的数据") ||
                message.content.contains("建议补充数据") ||
                message.content.contains("需补数据"))
    }

    private var compactCoverageBody: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.icon)
                .frame(width: 17)
            Text(compactSystemEventText)
                .font(.caption)
                .foregroundStyle(AppTheme.mutedText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(DateFormatting.shortDateTime.string(from: message.createdAt))
                .font(.caption2)
                .foregroundStyle(AppTheme.faintText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AppTheme.panel.opacity(0.48), in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    private var isCompactCoverageMessage: Bool {
        message.kind == .systemCoverage
    }

    private var compactSystemEventText: String {
        message.content
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showsAnalysisEvidenceBar: Bool {
        message.role == .assistant &&
            (message.kind == .aiAnalysis || message.kind == .aiMemo || message.kind == .simpleReport)
    }

    private var hasComputationEvidence: Bool {
        message.evidence.contains { $0.sourceType == "计算证据" }
    }

    private var analysisEvidenceBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                MessageNeutralLabel(title: analysisEvidenceSummaryText, systemImage: "doc.text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedText)
                Spacer(minLength: 0)
                Button {
                    viewEvidenceAction()
                } label: {
                    MessageNeutralLabel(title: "查看证据", systemImage: "sidebar.right")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .ghost))
                .controlSize(.small)
                .help("打开分析资料里的证据页")
            }
            VStack(alignment: .leading, spacing: 6) {
                MessageNeutralLabel(title: analysisEvidenceSummaryText, systemImage: "doc.text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedText)
                Button {
                    viewEvidenceAction()
                } label: {
                    MessageNeutralLabel(title: "查看证据", systemImage: "sidebar.right")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .ghost))
                .controlSize(.small)
                .help("打开分析资料里的证据页")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AppTheme.panel.opacity(0.58), in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.border.opacity(0.42), lineWidth: 1)
        }
    }

    private var analysisEvidenceSummaryText: String {
        if let answerPresentation, answerPresentation.hasSupportingSections {
            return answerPresentation.supportSummaryText
        }
        let scopeText = (message.content.contains("分析口径") || message.content.contains("本轮周期")) ? "口径已声明" : "口径待核对"
        let coverageText = dataCoverageEvidence == nil ? "读取范围待核对" : "读取范围已生成"
        let sqlText = hasComputationEvidence ? "SQL/Notebook 已生成" : "SQL/Notebook 待生成"
        let externalCount = nonCoverageEvidence.filter { evidence in
            evidence.sourceType.contains("外部") ||
                evidence.sourceType.contains("参照") ||
                evidence.sourceType.contains("引用")
        }.count
        return "\(scopeText) · \(coverageText) · \(sqlText) · 外部证据 \(externalCount) 条"
    }

    private var canCollapse: Bool {
        if answerPresentation?.hasSupportingSections == true {
            return false
        }
        switch message.role {
        case .assistant:
            return message.content.isLongerThan(1_400) ||
                (isStreamingAssistant && message.content.isLongerThan(900)) ||
                (message.content.contains("\n|") && message.content.isLongerThan(900))
        case .system:
            return message.content.isLongerThan(1_800)
        case .user:
            return false
        }
    }

    private var displayedContent: String {
        let primaryContent = answerPresentation?.answerMarkdown ?? message.content
        guard isCollapsed else { return primaryContent }
        return primaryContent.collapsedMessagePreview(limit: 2_400)
    }

    private var linkedDisplayedContent: String {
        guard !isStreamingAssistant,
              !isCollapsed,
              let run = analysisHarnessRun,
              let traces = run.answerNumberTraces,
              !traces.isEmpty else {
            return displayedContent
        }
        return Self.linkedContentCache.value(
            messageID: message.id,
            displayedContent: displayedContent,
            run: run,
            traces: traces
        ) {
            linkedDisplayedContentUncached(displayedContent: displayedContent, traces: traces)
        }
    }

    private func linkedDisplayedContentUncached(displayedContent: String, traces: [AnswerNumberTrace]) -> String {
        let linkedTraces = traces
            .filter { trace in
                guard trace.status == .matched || trace.status == .approximateMatched,
                      trace.matchedResultID != nil,
                      !trace.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return false
                }
                return displayedContent.contains(trace.rawText)
            }
            .sorted { $0.rawText.count > $1.rawText.count }
        var working = displayedContent
        var replacements: [(token: String, replacement: String)] = []
        var seenRawTexts = Set<String>()
        for trace in linkedTraces where !seenRawTexts.contains(trace.rawText) {
            guard let resultID = trace.matchedResultID else { continue }
            seenRawTexts.insert(trace.rawText)
            let token = "%%NEXAFLOW_TRACE_\(replacements.count)%%"
            working = working.replacingOccurrences(of: trace.rawText, with: token)
            replacements.append((token, "[\(trace.rawText)](nexaflow-evidence://\(resultID.uuidString))"))
        }
        for replacement in replacements {
            working = working.replacingOccurrences(of: replacement.token, with: replacement.replacement)
        }
        return working
    }

    private var collapseToggleButton: some View {
        Button {
            toggleExpandedAction()
        } label: {
            Label(isCollapsed ? "展开全文" : "收起", systemImage: isCollapsed ? "chevron.down" : "chevron.up")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(MessageCollapseToggleStyle())
        .help(isCollapsed ? "展开完整回复内容" : "收起为摘要，减少滚动长度")
    }

    private var isCollapsed: Bool {
        if isStreamingAssistant && canCollapse {
            return true
        }
        if isLatestAssistant {
            let isExpanded = latestExpansionOverride ?? !message.shouldDefaultCollapseAsLatestAssistantReply
            return canCollapse && !isExpanded
        }
        return canCollapse && !isExpanded
    }

    private var iconName: String {
        switch message.role {
        case .user: return "person"
        case .assistant: return "sparkles"
        case .system: return "gearshape"
        }
    }

    private var messageIconRole: SemanticIconRole {
        switch message.role {
        case .user: return .business
        case .assistant: return .ai
        case .system: return .neutral
        }
    }

    private var kindLabel: String {
        switch message.kind {
        case .userRequest: return "需求"
        case .aiAnalysis: return "AI 分析"
        case .aiMemo: return "完整汇报"
        case .simpleReport: return "简洁汇报"
        case .systemCoverage: return "系统"
        case .adoption: return "采纳"
        case .error: return "错误"
        }
    }

    private var tint: Color {
        switch message.kind {
        case .error: return AppTheme.danger
        case .aiAnalysis, .aiMemo, .simpleReport: return .secondary
        case .adoption: return AppTheme.success
        default: return .secondary
        }
    }

    private var background: Color {
        switch message.role {
        case .user: return AppTheme.accent.opacity(0.10)
        case .assistant: return AppTheme.card
        case .system: return AppTheme.panel.opacity(0.55)
        }
    }

    private var separatedEvidenceHint: some View {
        Button {
            viewEvidenceAction()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.icon)
                    .frame(width: 16)
                Text("口径、证据、读取范围和限制已收进分析资料。")
                    .font(AppFont.caption())
                    .foregroundStyle(AppTheme.mutedText)
                Spacer(minLength: 0)
                Text("查看依据")
                    .font(AppFont.caption(weight: .semibold))
                    .foregroundStyle(AppTheme.accentStrong)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AppTheme.panel.opacity(0.50), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("打开右侧分析资料，查看这条回答的完整依据。")
    }

    private func copyMessageContent(includeFullSource: Bool = false) {
        NSPasteboard.general.clearContents()
        let content = includeFullSource ? message.content : (answerPresentation?.answerMarkdown ?? message.content)
        let didCopy = NSPasteboard.general.setString(content, forType: .string)
        copyFeedbackState = didCopy ? .copied : .failed
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            copyFeedbackState = nil
        }
    }

    private func handleEvidenceLink(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == "nexaflow-evidence",
              let host = url.host(),
              let resultID = UUID(uuidString: host) else {
            return .systemAction
        }
        let result = analysisHarnessRun?.verifiedResults.first { $0.id == resultID }
        focusMetricEvidenceAction(resultID, result?.source.sourceCells ?? [])
        return .handled
    }

    private var copyActionLabel: some View {
        let feedback = copyFeedbackState
        return MessageNeutralLabel(
            title: feedback?.title ?? (answerPresentation == nil ? "复制" : "复制回答"),
            systemImage: feedback?.systemImage ?? "doc.on.doc"
        )
        .foregroundStyle(feedback == .failed ? AppTheme.danger : (feedback == .copied ? AppTheme.success : AppTheme.text))
    }

    @ViewBuilder
    private var copyInlineFeedback: some View {
        if let feedback = copyFeedbackState {
            Label(
                feedback == .copied ? "已复制到剪贴板" : "复制失败",
                systemImage: feedback.systemImage
            )
            .labelStyle(.titleAndIcon)
            .font(AppFont.caption2())
            .foregroundStyle(feedback == .copied ? AppTheme.success : AppTheme.danger)
            .transition(.opacity)
        }
    }
}

private struct AnalysisMessageStreamingStatusView: View {
    var status: AnalysisMessageStreamingStatus
    @State private var isExpanded = false

    var body: some View {
        Group {
            if status.state == .reasoning || status.state == .correcting {
                activeReasoningBody
            } else {
                DisclosureGroup(isExpanded: $isExpanded) {
                    Text(status.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                } label: {
                    statusLabel
                }
                .disclosureGroupStyle(.automatic)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var activeReasoningBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.72)
                    .frame(width: 18, height: 18)
                Text(status.title)
                    .font(AppFont.caption(weight: .semibold))
                    .foregroundStyle(AppTheme.text)
                Text(status.state == .correcting ? "自动修正" : "思考过程")
                    .font(AppFont.caption2(weight: .medium))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.12), in: Capsule())
            }
            PlainScrollableTextView(
                text: status.detail.nilIfBlank ?? "正在等待模型返回思考过程...",
                minHeight: 28,
                maxHeight: 180,
                autoScrollBehavior: .followStreamingBottom
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusLabel: some View {
        HStack(spacing: 7) {
            SemanticIcon(systemName: iconName, color: tint, size: 13, frameWidth: 17)
            Text(status.title)
                .font(AppFont.caption(weight: .semibold))
                .foregroundStyle(AppTheme.text)
            Text("思考过程")
                .font(AppFont.caption2(weight: .medium))
                .foregroundStyle(tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(tint.opacity(0.12), in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tint: Color {
        switch status.state {
        case .reasoning: return AppTheme.accent
        case .correcting: return AppTheme.warning
        case .completed: return AppTheme.success
        case .fallback: return AppTheme.warning
        }
    }

    private var iconName: String {
        switch status.state {
        case .reasoning: return "sparkles"
        case .correcting: return "wrench.and.screwdriver"
        case .completed: return "checkmark.circle"
        case .fallback: return "arrow.triangle.2.circlepath"
        }
    }
}

extension AnalysisSessionMessage {
    var shouldDefaultCollapseAsLatestAssistantReply: Bool {
        guard role == .assistant else { return false }
        if content.isLongerThan(4_000) {
            return true
        }
        if content.contains("AI 读取到的数据") && content.isLongerThan(1_600) {
            return true
        }
        return content.isLongerThan(2_400) && content.contains("\n|")
    }
}

private extension String {
    func isLongerThan(_ limit: Int) -> Bool {
        guard let boundary = index(startIndex, offsetBy: limit, limitedBy: endIndex) else {
            return false
        }
        return boundary < endIndex
    }

    func collapsedMessagePreview(limit: Int) -> String {
        let normalized = trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isLongerThan(limit) else { return normalized }
        let prefixText = normalized.prefix(limit)
        guard let lastBreak = prefixText.lastIndex(where: { $0.isNewline }) else {
            return String(prefixText).trimmingCharacters(in: .whitespacesAndNewlines) + "\n..."
        }
        let preview = prefixText[..<lastBreak]
        return preview.trimmingCharacters(in: .whitespacesAndNewlines) + "\n..."
    }
}

private struct MessageCollapseToggleStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.caption(weight: .semibold))
            .foregroundStyle(isEnabled ? AppTheme.accentStrong : AppTheme.mutedText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(background(configuration: configuration), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(AppTheme.accent.opacity(isHovered ? 0.42 : 0.22), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
            .textSelection(.disabled)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onHover { hovering in
                guard isEnabled else { return }
                isHovered = hovering
            }
    }

    private func background(configuration: Configuration) -> Color {
        guard isEnabled else { return .clear }
        if configuration.isPressed {
            return AppTheme.accent.opacity(0.18)
        }
        return AppTheme.accent.opacity(isHovered ? 0.14 : 0.08)
    }
}
