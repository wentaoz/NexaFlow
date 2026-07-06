import AppKit
import SwiftUI

struct ChatScrollPositionObserver: NSViewRepresentable {
    @Binding var isAtBottom: Bool
    var onScrollAwayFromBottom: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.onScrollAwayFromBottom = onScrollAwayFromBottom
        context.coordinator.scheduleAttach(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let bottomBinding = $isAtBottom
        context.coordinator.onChange = { isAtBottom in
            if bottomBinding.wrappedValue != isAtBottom {
                bottomBinding.wrappedValue = isAtBottom
            }
        }
        context.coordinator.onScrollAwayFromBottom = onScrollAwayFromBottom
        if nsView.enclosingScrollView == nil {
            context.coordinator.scheduleAttach(from: nsView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var onChange: ((Bool) -> Void)?
        var onScrollAwayFromBottom: (() -> Void)?
        private weak var scrollView: NSScrollView?
        private var observer: NSObjectProtocol?
        private var hasPendingAttach = false
        private var lastVisibleOriginY: CGFloat?

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func attach(from view: NSView) {
            hasPendingAttach = false
            guard let scrollView = nearestScrollView(from: view) else { return }
            guard self.scrollView !== scrollView else {
                update()
                return
            }
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            self.scrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.update()
            }
            update()
        }

        private func update() {
            guard let scrollView else { return }
            let visible = scrollView.contentView.bounds
            let documentHeight = scrollView.documentView?.bounds.height ?? 0
            let threshold: CGFloat = 96
            let atBottom = documentHeight <= visible.height + 2 || documentHeight - visible.maxY <= threshold
            if let lastVisibleOriginY,
               abs(lastVisibleOriginY - visible.origin.y) > 1,
               !atBottom {
                onScrollAwayFromBottom?()
            }
            lastVisibleOriginY = visible.origin.y
            onChange?(atBottom)
        }

        private func nearestScrollView(from view: NSView) -> NSScrollView? {
            if let scrollView = view.enclosingScrollView {
                return scrollView
            }

            var current: NSView? = view
            while let superview = current?.superview {
                if let scrollView = superview as? NSScrollView {
                    return scrollView
                }
                current = superview
            }
            return nil
        }

        func scheduleAttach(from view: NSView) {
            guard !hasPendingAttach else { return }
            hasPendingAttach = true
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                self.attach(from: view)
            }
        }
    }
}

struct SessionChatScrollContainer: View {
    var session: AnalysisSession
    var latestAssistantID: UUID?
    var streamingAssistantMessageID: UUID?
    var expandedMessageIDs: Set<UUID>
    var followUpAction: (AnalysisSessionMessage) -> Void
    var explainEvidenceAction: (AnalysisSessionMessage) -> Void
    var challengeAction: (AnalysisSessionMessage) -> Void
    var correctionAction: (AnalysisSessionMessage) -> Void
    var adoptAction: (AnalysisSessionMessage) -> Void
    var importSupplementDataAction: (AnalysisSessionMessage) -> Void
    var markExistingDataAction: (AnalysisSessionMessage) -> Void
    var setReportInclusionAction: (AnalysisSessionMessage, AnalysisMessageReportInclusion) -> Void
    var viewEvidenceAction: (AnalysisSessionMessage) -> Void
    var focusMetricEvidenceAction: (AnalysisSessionMessage, UUID?, [HarnessSourceCellRef]) -> Void
    var generateFullReportAction: (AnalysisSessionMessage) -> Void
    var generateFullReportForQuestionAction: (AnalysisSessionMessage) -> Void
    var generateSimpleReportForQuestionAction: (AnalysisSessionMessage) -> Void
    var toggleExpandedAction: (UUID) -> Void

    @State private var isAtBottom = true
    @State private var latestMessageExpansionOverrides: [UUID: Bool] = [:]
    @State private var visibleMessageLimit = 18
    @State private var lastContentAutoScrollAt = Date.distantPast
    @State private var autoScrollSuspendedUntil = Date.distantPast
    @State private var bottomPinUntil = Date.distantPast

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { _ in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if session.messages.count > visibleMessageLimit {
                                Button {
                                    visibleMessageLimit += 24
                                } label: {
                                    SemanticLabel(title: "加载更早消息", systemImage: "arrow.up.circle", role: .data)
                                }
                                .buttonStyle(AppHoverButtonStyle(variant: .secondary))
                                .frame(maxWidth: .infinity, alignment: .center)
                            }

                            ForEach(Array(session.messages.suffix(visibleMessageLimit))) { message in
                                SessionMessageCard(
                                    message: message,
                                    renderSnapshot: SessionMessageRenderSnapshot(message: message),
                                    isLatestAssistant: message.id == latestAssistantID,
                                    isStreamingAssistant: message.id == streamingAssistantMessageID,
                                    latestExpansionOverride: latestMessageExpansionOverrides[message.id],
                                    isExpanded: expandedMessageIDs.contains(message.id),
                                    followUpAction: { followUpAction(message) },
                                    viewEvidenceAction: { viewEvidenceAction(message) },
                                    focusMetricEvidenceAction: { resultID, sourceCells in
                                        focusMetricEvidenceAction(message, resultID, sourceCells)
                                    },
                                    explainEvidenceAction: { explainEvidenceAction(message) },
                                    challengeAction: { challengeAction(message) },
                                    correctionAction: { correctionAction(message) },
                                    adoptAction: { adoptAction(message) },
                                    importSupplementDataAction: { importSupplementDataAction(message) },
                                    markExistingDataAction: { markExistingDataAction(message) },
                                    setReportInclusionAction: { inclusion in setReportInclusionAction(message, inclusion) },
                                    generateFullReportAction: { generateFullReportAction(message) },
                                    generateFullReportForQuestionAction: { generateFullReportForQuestionAction(message) },
                                    generateSimpleReportForQuestionAction: { generateSimpleReportForQuestionAction(message) },
                                    toggleExpandedAction: {
                                        toggleMessageBody(message, proxy: proxy)
                                    }
                                )
                                .equatable()
                                .id(message.id)
                                .transaction { transaction in
                                    transaction.animation = nil
                                }
                            }
                            Color.clear
                                .frame(height: 1)
                                .id("session-chat-bottom")
                        }
                        .padding(14)
                    }
                    .background(ChatScrollPositionObserver(
                        isAtBottom: $isAtBottom,
                        onScrollAwayFromBottom: suspendAutoScrollAfterManualScroll
                    ))

                    if !session.messages.isEmpty && !isAtBottom {
                        Button {
                            autoScrollSuspendedUntil = .distantPast
                            var transaction = Transaction()
                            transaction.animation = .easeInOut(duration: 0.18)
                            withTransaction(transaction) {
                                proxy.scrollTo("session-chat-bottom", anchor: .bottom)
                                isAtBottom = true
                            }
                        } label: {
                            SemanticLabel(title: "回到底部", systemImage: "arrow.down.to.line", role: .data)
                                .font(.callout.weight(.medium))
                        }
                        .buttonStyle(AppHoverButtonStyle(variant: .secondary))
                        .padding(12)
                    }
                }
            }
            .onChange(of: session.messages.count) { _ in
                extendBottomPinIfAllowed()
                scheduleAutoScrollToBottomIfAllowed(proxy: proxy, animated: true)
            }
            .onChange(of: latestMessageContentRevision) { _ in
                guard canAutoScrollToBottom else { return }
                let now = Date()
                guard now.timeIntervalSince(lastContentAutoScrollAt) >= 0.45 else { return }
                lastContentAutoScrollAt = now
                extendBottomPinIfAllowed(now: now)
                scheduleAutoScrollToBottomIfAllowed(proxy: proxy, animated: false)
            }
            .onChange(of: latestMessageRenderRevision) { _ in
                extendBottomPinIfAllowed()
                scheduleAutoScrollToBottomIfAllowed(proxy: proxy, animated: false)
            }
            .onChange(of: isAtBottom) { atBottom in
                if atBottom {
                    autoScrollSuspendedUntil = .distantPast
                    extendBottomPinIfAllowed()
                }
            }
            .onChange(of: session.id) { _ in
                isAtBottom = true
                visibleMessageLimit = 18
                lastContentAutoScrollAt = .distantPast
                autoScrollSuspendedUntil = .distantPast
                bottomPinUntil = .distantPast
                latestMessageExpansionOverrides.removeAll()
            }
        }
    }

    private var canAutoScrollToBottom: Bool {
        let now = Date()
        return (isAtBottom || now < bottomPinUntil) && now >= autoScrollSuspendedUntil
    }

    private var latestMessageRenderRevision: String {
        guard let message = session.messages.last else { return "empty" }
        let status = message.streamingStatus
        return [
            message.id.uuidString,
            message.kind.rawValue,
            "\(message.content.utf8.count)",
            status?.state.rawValue ?? "none",
            status?.title ?? "",
            "\(status?.detail.utf8.count ?? 0)",
            "\(status?.updatedAt.timeIntervalSinceReferenceDate ?? 0)",
            "\(message.evidence.count)",
            "\(message.reportInclusion.rawValue)"
        ].joined(separator: "|")
    }

    private var latestMessageContentRevision: String {
        guard let message = session.messages.last else { return "empty" }
        return [
            message.id.uuidString,
            "\(message.content.utf8.count)",
            message.streamingStatus?.state.rawValue ?? "none",
            "\(message.streamingStatus?.updatedAt.timeIntervalSinceReferenceDate ?? 0)"
        ].joined(separator: "|")
    }

    private func suspendAutoScrollAfterManualScroll() {
        isAtBottom = false
        autoScrollSuspendedUntil = Date().addingTimeInterval(1.2)
        bottomPinUntil = .distantPast
    }

    private func autoScrollToBottomIfAllowed(proxy: ScrollViewProxy, animated: Bool) {
        guard canAutoScrollToBottom else { return }
        bottomPinUntil = Date().addingTimeInterval(1.0)
        var transaction = Transaction()
        transaction.animation = animated ? .easeInOut(duration: 0.18) : nil
        withTransaction(transaction) {
            proxy.scrollTo("session-chat-bottom", anchor: .bottom)
            isAtBottom = true
        }
    }

    private func scheduleAutoScrollToBottomIfAllowed(proxy: ScrollViewProxy, animated: Bool) {
        guard canAutoScrollToBottom else { return }
        DispatchQueue.main.async {
            autoScrollToBottomIfAllowed(proxy: proxy, animated: animated)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                autoScrollToBottomIfAllowed(proxy: proxy, animated: false)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                autoScrollToBottomIfAllowed(proxy: proxy, animated: false)
            }
        }
    }

    private func extendBottomPinIfAllowed(now: Date = Date()) {
        guard now >= autoScrollSuspendedUntil else { return }
        guard isAtBottom || now < bottomPinUntil else { return }
        bottomPinUntil = now.addingTimeInterval(1.6)
    }

    private func toggleMessageBody(_ message: AnalysisSessionMessage, proxy: ScrollViewProxy) {
        let isLatest = message.id == latestAssistantID
        let isCurrentlyCollapsed = isLatest
            ? !(latestMessageExpansionOverrides[message.id] ?? !message.shouldDefaultCollapseAsLatestAssistantReply)
            : !expandedMessageIDs.contains(message.id)
        let willCollapse = !isCurrentlyCollapsed

        if willCollapse {
            var scrollTransaction = Transaction()
            scrollTransaction.animation = nil
            withTransaction(scrollTransaction) {
                proxy.scrollTo(message.id, anchor: .top)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + (willCollapse ? 0.04 : 0)) {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                if isLatest {
                    latestMessageExpansionOverrides[message.id] = isCurrentlyCollapsed
                } else {
                    toggleExpandedAction(message.id)
                }
            }
        }
    }
}
