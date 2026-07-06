import AppKit
import SwiftUI

enum SemanticIconRole {
    case ai
    case data
    case knowledge
    case business
    case opportunity
    case risk
    case external
    case success
    case neutral

    var color: Color {
        switch self {
        case .ai: return AppTheme.text
        case .data, .knowledge, .business, .external, .neutral:
            return AppTheme.icon
        case .opportunity, .success:
            return AppTheme.success
        case .risk:
            return AppTheme.danger
        }
    }

    static func inferred(from systemName: String) -> SemanticIconRole {
        let key = systemName.lowercased()
        if key.contains("sparkles") || key.contains("wand") || key.contains("brain") || key.contains("function") || key.contains("hourglass") { return .ai }
        if key.contains("table") || key.contains("chart") || key.contains("tray") || key.contains("externaldrive") || key.contains("slider") || key.contains("eye") || key.contains("doc.badge") { return .data }
        if key.contains("book") || key.contains("doc") || key.contains("folder") || key.contains("character") || key.contains("tag") || key.contains("bubble.left") || key.contains("text.badge") || key.contains("list.bullet") { return .knowledge }
        if key.contains("globe") || key.contains("map") || key.contains("point.") || key.contains("link") || key.contains("target") { return .business }
        if key.contains("scope") || key.contains("star") || key.contains("flag") { return .opportunity }
        if key.contains("exclamation") || key.contains("xmark") || key.contains("trash") || key.contains("nosign") || key.contains("stop") { return .risk }
        if key.contains("network") || key.contains("antenna") || key.contains("cloud") || key.contains("newspaper") || key.contains("arrow.triangle") || key.contains("calendar") || key.contains("clock") { return .external }
        if key.contains("checkmark") { return .success }
        if key.contains("gear") { return .neutral }
        return .neutral
    }
}

struct SemanticIcon: View {
    var systemName: String
    var role: SemanticIconRole? = nil
    var color: Color? = nil
    var size: CGFloat? = nil
    var frameWidth: CGFloat? = nil

    var body: some View {
        Image(systemName: systemName)
            .font(size.map { .system(size: $0, weight: .semibold) } ?? AppFont.body(weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color ?? (role ?? .inferred(from: systemName)).color)
            .frame(width: frameWidth)
    }
}

struct SemanticLabel: View {
    var title: String
    var systemImage: String
    var role: SemanticIconRole? = nil
    var iconColor: Color? = nil
    var iconSize: CGFloat? = nil
    var spacing: CGFloat = 6

    var body: some View {
        HStack(spacing: spacing) {
            SemanticIcon(systemName: systemImage, role: role, color: iconColor, size: iconSize, frameWidth: iconSize.map { $0 + 4 })
            Text(title)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct SectionCard<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SemanticIcon(systemName: systemImage, size: 15, frameWidth: 20)
                Text(title)
                    .font(AppFont.headline())
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.border.opacity(0.72), lineWidth: 1)
        }
    }
}

struct LongTextPreview: View {
    var text: String
    var previewLimit: Int = 2_400
    var expandedHeight: CGFloat = 260
    var font: Font = .body
    var foregroundColor: Color = .primary

    @State private var isExpanded = false

    var body: some View {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = normalized.previewSlice(limit: previewLimit)

        VStack(alignment: .leading, spacing: 8) {
            if isExpanded {
                PlainScrollableTextView(text: normalized)
                    .frame(height: expandedHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(preview.text)
                    .font(font)
                    .foregroundStyle(foregroundColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if preview.isTruncated {
                Button {
                    isExpanded.toggle()
                } label: {
                    SemanticLabel(
                        title: isExpanded ? "收起完整内容" : "展开完整内容",
                        systemImage: isExpanded ? "chevron.up" : "chevron.down",
                        role: .neutral
                    )
                }
                .buttonStyle(AppHoverButtonStyle(variant: .ghost))
            }
        }
    }
}

struct PlainScrollableTextView: NSViewRepresentable, Equatable {
    enum AutoScrollBehavior: Equatable {
        case preserveUserPosition
        case followStreamingBottom
    }

    var text: String
    var minHeight: CGFloat = 28
    var maxHeight: CGFloat = 260
    var autoScrollBehavior: AutoScrollBehavior = .preserveUserPosition

    static func == (lhs: PlainScrollableTextView, rhs: PlainScrollableTextView) -> Bool {
        lhs.text == rhs.text &&
            lhs.minHeight == rhs.minHeight &&
            lhs.maxHeight == rhs.maxHeight &&
            lhs.autoScrollBehavior == rhs.autoScrollBehavior
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = AdaptivePlainTextScrollView()
        scrollView.minimumContentHeight = minHeight
        scrollView.maximumContentHeight = maxHeight
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.font = NSFont(name: AppFont.textFamily, size: NSFont.smallSystemFontSize) ?? .systemFont(ofSize: NSFont.smallSystemFontSize)
        textView.textColor = NSColor.secondaryLabelColor
        textView.string = text

        scrollView.documentView = textView
        scrollView.textView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.isFollowingStreamingBottom = autoScrollBehavior == .followStreamingBottom
        scrollView.recalculateIntrinsicHeight()
        if autoScrollBehavior == .followStreamingBottom {
            context.coordinator.scheduleScrollToBottom(scrollView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        if let adaptive = scrollView as? AdaptivePlainTextScrollView {
            adaptive.minimumContentHeight = minHeight
            adaptive.maximumContentHeight = maxHeight
            adaptive.textView = textView
            context.coordinator.scrollView = adaptive
        }
        textView.font = NSFont(name: AppFont.textFamily, size: NSFont.smallSystemFontSize) ?? .systemFont(ofSize: NSFont.smallSystemFontSize)
        textView.textColor = NSColor.secondaryLabelColor
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: max(scrollView.contentSize.width, 1), height: .greatestFiniteMagnitude)
        textView.frame.size.width = max(scrollView.contentSize.width, 1)

        let wasNearBottom = context.coordinator.isNearBottom(in: scrollView)
        switch autoScrollBehavior {
        case .preserveUserPosition:
            break
        case .followStreamingBottom:
            context.coordinator.isFollowingStreamingBottom = true
        }

        defer {
            (scrollView as? AdaptivePlainTextScrollView)?.recalculateIntrinsicHeight()
        }
        guard textView.string != text else { return }
        let shouldScrollToBottom: Bool
        switch autoScrollBehavior {
        case .preserveUserPosition:
            shouldScrollToBottom = wasNearBottom
        case .followStreamingBottom:
            shouldScrollToBottom = true
        }
        textView.string = text
        (scrollView as? AdaptivePlainTextScrollView)?.recalculateIntrinsicHeight()
        if shouldScrollToBottom {
            context.coordinator.scheduleScrollToBottom(scrollView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var textView: NSTextView?
        weak var scrollView: AdaptivePlainTextScrollView?
        var isFollowingStreamingBottom = false

        func isNearBottom(in scrollView: NSScrollView) -> Bool {
            let visible = scrollView.contentView.bounds
            let documentHeight = scrollView.documentView?.bounds.height ?? 0
            return documentHeight <= visible.height + 2 || documentHeight - visible.maxY <= 24
        }

        func scheduleScrollToBottom(_ scrollView: NSScrollView) {
            DispatchQueue.main.async { [weak scrollView] in
                guard let scrollView else { return }
                (scrollView as? AdaptivePlainTextScrollView)?.recalculateIntrinsicHeight()
                self.scrollToBottom(scrollView)
            }
        }

        func scrollToBottom(_ scrollView: NSScrollView) {
            guard let documentView = scrollView.documentView else { return }
            let visibleHeight = scrollView.contentView.bounds.height
            let maxY = max(0, documentView.bounds.height - visibleHeight)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    final class AdaptivePlainTextScrollView: NSScrollView {
        weak var textView: NSTextView?
        var minimumContentHeight: CGFloat = 28
        var maximumContentHeight: CGFloat = 260
        private var cachedHeight: CGFloat = 28

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: cachedHeight)
        }

        override func layout() {
            super.layout()
            updateTextContainerWidth()
            recalculateIntrinsicHeight()
        }

        func recalculateIntrinsicHeight() {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                updateCachedHeight(minimumContentHeight)
                return
            }
            updateTextContainerWidth()
            layoutManager.ensureLayout(for: textContainer)
            let usedHeight = ceil(layoutManager.usedRect(for: textContainer).height)
            let lineHeight = ceil(textView.font?.boundingRectForFont.height ?? NSFont.smallSystemFontSize)
            let fullHeight = max(lineHeight, usedHeight) + textView.textContainerInset.height * 2 + 4
            let documentHeight = max(fullHeight, contentSize.height)
            if abs(textView.frame.size.height - documentHeight) > 1 {
                textView.frame.size.height = documentHeight
            }
            let cappedHeight = min(max(fullHeight, minimumContentHeight), maximumContentHeight)
            hasVerticalScroller = fullHeight > maximumContentHeight + 2
            updateCachedHeight(cappedHeight)
        }

        private func updateTextContainerWidth() {
            guard let textView else { return }
            let width = max(contentSize.width, 1)
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            textView.frame.size.width = width
        }

        private func updateCachedHeight(_ newHeight: CGFloat) {
            guard abs(cachedHeight - newHeight) > 1 else { return }
            cachedHeight = newHeight
            invalidateIntrinsicContentSize()
            superview?.invalidateIntrinsicContentSize()
        }
    }
}

struct MetricTile: View {
    var title: String
    var value: String
    var systemImage: String
    var helpText: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            SemanticIcon(systemName: systemImage, size: 20, frameWidth: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(AppFont.title(size: 20))
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                Text(title)
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 76, maxHeight: 76, alignment: .leading)
        .padding(12)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.border.opacity(0.55), lineWidth: 1)
        }
        .help(helpText ?? "\(title)：\(value)")
    }
}

enum AppHoverButtonVariant {
    case primary
    case secondary
    case ghost
    case danger
    case link
    case icon
    case navRow
    case pickerShell
    case segmentedShell
}

struct AppHoverButtonStyle: ButtonStyle {
    var variant: AppHoverButtonVariant = .secondary

    func makeBody(configuration: Configuration) -> some View {
        AppHoverButtonStyleBody(configuration: configuration, variant: variant)
    }

    private struct AppHoverButtonStyleBody: View {
        let configuration: ButtonStyle.Configuration
        let variant: AppHoverButtonVariant

        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(AppFont.callout(weight: fontWeight))
                .fontWeight(fontWeight)
                .foregroundStyle(foregroundStyle)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(strokeStyle, lineWidth: strokeWidth)
                }
                .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .textSelection(.disabled)
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
                .onHover { hovering in
                    guard isEnabled else { return }
                    isHovered = hovering
                }
        }

        private var fontWeight: Font.Weight {
            switch variant {
            case .primary, .danger:
                return .semibold
            case .secondary, .ghost, .link, .icon, .navRow, .pickerShell, .segmentedShell:
                return .medium
            }
        }

        private var horizontalPadding: CGFloat {
            switch variant {
            case .link:
                return 6
            case .icon:
                return 7
            case .ghost:
                return 8
            case .navRow:
                return 10
            case .pickerShell, .segmentedShell:
                return 0
            case .primary, .secondary, .danger:
                return 11
            }
        }

        private var verticalPadding: CGFloat {
            switch variant {
            case .link:
                return 3
            case .icon:
                return 6
            case .ghost:
                return 5
            case .navRow:
                return 8
            case .pickerShell, .segmentedShell:
                return 0
            case .primary, .secondary, .danger:
                return 7
            }
        }

        private var foregroundStyle: Color {
            switch variant {
            case .primary, .link:
                return AppTheme.accentStrong
            case .danger:
                return AppTheme.danger
            case .secondary, .ghost, .icon, .navRow, .pickerShell, .segmentedShell:
                return AppTheme.text
            }
        }

        private var backgroundStyle: Color {
            guard isEnabled else { return .clear }
            switch variant {
            case .primary:
                return AppTheme.accent.opacity(isHovered || configuration.isPressed ? 0.18 : 0.10)
            case .secondary:
                return AppTheme.panelStrong.opacity(isHovered || configuration.isPressed ? 0.82 : 0.58)
            case .ghost:
                return AppTheme.panelStrong.opacity(isHovered || configuration.isPressed ? 0.64 : 0.00)
            case .danger:
                return AppTheme.danger.opacity(isHovered || configuration.isPressed ? 0.14 : 0.07)
            case .link:
                return AppTheme.accent.opacity(isHovered || configuration.isPressed ? 0.09 : 0.00)
            case .icon:
                return AppTheme.panelStrong.opacity(isHovered || configuration.isPressed ? 0.78 : 0.46)
            case .navRow:
                return AppTheme.panelStrong.opacity(isHovered || configuration.isPressed ? 0.58 : 0.00)
            case .pickerShell, .segmentedShell:
                return AppTheme.panelStrong.opacity(isHovered || configuration.isPressed ? 0.58 : 0.24)
            }
        }

        private var strokeStyle: Color {
            guard isEnabled else { return .clear }
            switch variant {
            case .primary:
                return AppTheme.accent.opacity(isHovered ? 0.48 : 0.24)
            case .secondary:
                return AppTheme.border.opacity(isHovered ? 0.86 : 0.62)
            case .ghost, .link, .navRow:
                return AppTheme.border.opacity(isHovered ? 0.46 : 0.00)
            case .icon, .pickerShell, .segmentedShell:
                return AppTheme.border.opacity(isHovered ? 0.78 : 0.44)
            case .danger:
                return AppTheme.danger.opacity(isHovered ? 0.42 : 0.18)
            }
        }

        private var strokeWidth: CGFloat {
            isHovered || configuration.isPressed ? 1 : 0.8
        }
    }
}

struct HoverableControlShell<Content: View>: View {
    var variant: AppHoverButtonVariant = .pickerShell
    var isSelected = false
    var cornerRadius: CGFloat = 8
    @ViewBuilder var content: Content

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(strokeStyle, lineWidth: strokeWidth)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .textSelection(.disabled)
            .shadow(color: shadowStyle, radius: shadowRadius, x: 0, y: 0)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { hovering in
                guard isEnabled else { return }
                isHovered = hovering
            }
    }

    private var horizontalPadding: CGFloat {
        switch variant {
        case .segmentedShell:
            return 0
        case .navRow:
            return 0
        default:
            return 0
        }
    }

    private var verticalPadding: CGFloat {
        switch variant {
        case .segmentedShell:
            return 0
        case .navRow:
            return 0
        default:
            return 0
        }
    }

    private var backgroundStyle: Color {
        guard isEnabled else { return .clear }
        if isSelected {
            return AppTheme.accent.opacity(isHovered ? 0.92 : 0.84)
        }
        switch variant {
        case .pickerShell, .segmentedShell:
            return .clear
        case .danger:
            return AppTheme.danger.opacity(isHovered ? 0.14 : 0.06)
        case .primary:
            return AppTheme.accent.opacity(isHovered ? 0.17 : 0.10)
        case .navRow:
            return AppTheme.panelStrong.opacity(isHovered ? 0.55 : 0.00)
        case .link:
            return AppTheme.accent.opacity(isHovered ? 0.09 : 0.00)
        case .icon, .secondary, .ghost:
            return AppTheme.panelStrong.opacity(isHovered ? 0.56 : 0.22)
        }
    }

    private var strokeStyle: Color {
        guard isEnabled else { return .clear }
        if isSelected {
            return AppTheme.accent.opacity(0.35)
        }
        switch variant {
        case .pickerShell, .segmentedShell:
            return .clear
        case .danger:
            return AppTheme.danger.opacity(isHovered ? 0.36 : 0.12)
        case .primary:
            return AppTheme.accent.opacity(isHovered ? 0.45 : 0.18)
        case .navRow:
            return .clear
        case .link:
            return AppTheme.accent.opacity(isHovered ? 0.22 : 0.00)
        default:
            return AppTheme.border.opacity(isHovered ? 0.72 : 0.44)
        }
    }

    private var strokeWidth: CGFloat {
        switch variant {
        case .pickerShell, .segmentedShell:
            return 0
        default:
            return isHovered || isSelected ? 1 : 0.8
        }
    }

    private var shadowStyle: Color {
        guard isEnabled else { return .clear }
        switch variant {
        case .pickerShell, .segmentedShell:
            return .clear
        default:
            return .clear
        }
    }

    private var shadowRadius: CGFloat {
        switch variant {
        case .pickerShell, .segmentedShell:
            return 0
        default:
            return 0
        }
    }
}

extension View {
    func hoverControlShell(
        _ variant: AppHoverButtonVariant = .pickerShell,
        isSelected: Bool = false,
        cornerRadius: CGFloat = 8
    ) -> some View {
        HoverableControlShell(variant: variant, isSelected: isSelected, cornerRadius: cornerRadius) {
            self
        }
    }
}

struct EmptyStateView: View {
    var title: String
    var detail: String
    var systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(AppTheme.icon)
            Text(title)
                .font(AppFont.headline())
            Text(detail)
                .font(AppFont.callout())
                .foregroundStyle(AppTheme.mutedText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct WorkflowBlockedBanner: View {
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(AppTheme.warning)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(AppFont.headline())
                Text(detail)
                    .font(AppFont.callout())
                    .foregroundStyle(AppTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.warning.opacity(0.11), in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.warning.opacity(0.18), lineWidth: 1)
        }
    }
}

struct WorkflowActionBanner: View {
    var title: String
    var detail: String
    var actionTitle: String
    var actionSystemImage: String
    var action: () -> Void

    var body: some View {
        ResponsiveStack(compactBreakpoint: 620, spacing: 10, horizontalAlignment: .top) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(AppTheme.warning)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(AppFont.headline())
                    Text(detail)
                        .font(AppFont.callout())
                        .foregroundStyle(AppTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            Button(action: action) {
                Label(actionTitle, systemImage: actionSystemImage)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.warning.opacity(0.11), in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.warning.opacity(0.18), lineWidth: 1)
        }
    }
}

struct WrappingTextEditor: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Binding var text: String
    var font: NSFont = NSFont(name: AppFont.textFamily, size: NSFont.systemFontSize) ?? .systemFont(ofSize: NSFont.systemFontSize)
    var minHeight: CGFloat = 72
    var maxHeight: CGFloat = 260
    var focusToken: UUID?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = AdaptiveTextScrollView()
        scrollView.minimumContentHeight = minHeight
        scrollView.maximumContentHeight = maxHeight
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        let textView = ShortcutFriendlyTextView()
        textView.string = text
        textView.font = font
        textView.isRichText = false
        textView.isEditable = isEnabled
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.delegate = context.coordinator
        scrollView.documentView = textView
        scrollView.textView = textView
        context.coordinator.scrollView = scrollView
        scrollView.recalculateIntrinsicHeight()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if let adaptive = scrollView as? AdaptiveTextScrollView {
            adaptive.minimumContentHeight = minHeight
            adaptive.maximumContentHeight = maxHeight
            adaptive.textView = textView
            context.coordinator.scrollView = adaptive
        }
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEnabled
        textView.textColor = isEnabled ? .labelColor : .secondaryLabelColor
        textView.font = font
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: max(scrollView.contentSize.width, 1),
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.frame.size.width = max(scrollView.contentSize.width, 1)
        (scrollView as? AdaptiveTextScrollView)?.recalculateIntrinsicHeight()

        if let focusToken, context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var scrollView: AdaptiveTextScrollView?
        var lastFocusToken: UUID?

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            scrollView?.recalculateIntrinsicHeight()
        }
    }

    final class ShortcutFriendlyTextView: NSTextView {
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command),
                  !flags.contains(.control),
                  !flags.contains(.option),
                  let key = event.charactersIgnoringModifiers?.lowercased() else {
                return super.performKeyEquivalent(with: event)
            }

            switch key {
            case "c":
                copy(nil)
                return true
            case "v":
                guard isEditable else { return super.performKeyEquivalent(with: event) }
                paste(nil)
                return true
            case "x":
                guard isEditable else { return super.performKeyEquivalent(with: event) }
                cut(nil)
                return true
            case "a":
                selectAll(nil)
                return true
            case "z":
                if flags.contains(.shift) {
                    undoManager?.redo()
                } else {
                    undoManager?.undo()
                }
                return true
            default:
                return super.performKeyEquivalent(with: event)
            }
        }
    }

    final class AdaptiveTextScrollView: NSScrollView {
        weak var textView: NSTextView?
        var minimumContentHeight: CGFloat = 72
        var maximumContentHeight: CGFloat = 260
        private var cachedHeight: CGFloat = 72

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: cachedHeight)
        }

        override func layout() {
            super.layout()
            updateTextContainerWidth()
            recalculateIntrinsicHeight()
        }

        func recalculateIntrinsicHeight() {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                updateCachedHeight(minimumContentHeight)
                return
            }
            updateTextContainerWidth()
            layoutManager.ensureLayout(for: textContainer)
            let usedHeight = ceil(layoutManager.usedRect(for: textContainer).height)
            let lineHeight = ceil(textView.font?.boundingRectForFont.height ?? NSFont.systemFontSize)
            let fullHeight = max(lineHeight, usedHeight) + textView.textContainerInset.height * 2 + 8
            let cappedHeight = min(max(fullHeight, minimumContentHeight), maximumContentHeight)
            hasVerticalScroller = fullHeight > maximumContentHeight + 2
            updateCachedHeight(cappedHeight)
        }

        private func updateTextContainerWidth() {
            guard let textView else { return }
            let width = max(contentSize.width, 1)
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            textView.frame.size.width = width
        }

        private func updateCachedHeight(_ newHeight: CGFloat) {
            guard abs(cachedHeight - newHeight) > 1 else { return }
            cachedHeight = newHeight
            invalidateIntrinsicContentSize()
            superview?.invalidateIntrinsicContentSize()
        }
    }
}

struct AdaptiveTextBox: View {
    @Binding var text: String
    var placeholder: String = ""
    var minHeight: CGFloat = 72
    var maxHeight: CGFloat = 260
    var font: NSFont = NSFont(name: AppFont.textFamily, size: NSFont.systemFontSize) ?? .systemFont(ofSize: NSFont.systemFontSize)

    var body: some View {
        ZStack(alignment: .topLeading) {
            WrappingTextEditor(text: $text, font: font, minHeight: minHeight, maxHeight: maxHeight)
                .frame(minHeight: minHeight, maxHeight: maxHeight)
            if text.isEmpty, !placeholder.isEmpty {
                Text(placeholder)
                    .font(AppFont.callout())
                    .foregroundStyle(AppTheme.faintText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .allowsHitTesting(false)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.border.opacity(0.72), lineWidth: 1)
        )
    }
}

struct AdaptiveTextField: View {
    var placeholder: String
    @Binding var text: String
    var minLines: Int = 1
    var maxLines: Int = 4

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .font(AppFont.callout())
            .lineLimit(minLines...max(maxLines, minLines))
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(AppTheme.border.opacity(0.72), lineWidth: 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ResponsiveFormRow<Content: View>: View {
    var label: String
    var labelWidth: CGFloat
    var spacing: CGFloat
    var compactBreakpoint: CGFloat
    @ViewBuilder var content: () -> Content
    @State private var availableWidth: CGFloat = 0

    init(
        _ label: String,
        labelWidth: CGFloat = 112,
        spacing: CGFloat = 12,
        compactBreakpoint: CGFloat = 460,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.label = label
        self.labelWidth = labelWidth
        self.spacing = spacing
        self.compactBreakpoint = compactBreakpoint
        self.content = content
    }

    var body: some View {
        Group {
            if shouldStack {
                VStack(alignment: .leading, spacing: 6) {
                    labelView
                    content()
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: spacing) {
                    labelView
                        .frame(width: labelWidth, alignment: .leading)
                    content()
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .readAvailableWidth($availableWidth)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shouldStack: Bool {
        availableWidth > 0 && availableWidth < compactBreakpoint
    }

    private var labelView: some View {
        Text(label)
            .font(AppFont.callout())
            .foregroundStyle(AppTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ResponsiveStack<Content: View>: View {
    var compactBreakpoint: CGFloat
    var spacing: CGFloat
    var horizontalAlignment: VerticalAlignment
    var verticalAlignment: HorizontalAlignment
    @ViewBuilder var content: () -> Content
    @State private var availableWidth: CGFloat = 0

    init(
        compactBreakpoint: CGFloat = 560,
        spacing: CGFloat = 8,
        horizontalAlignment: VerticalAlignment = .center,
        verticalAlignment: HorizontalAlignment = .leading,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.compactBreakpoint = compactBreakpoint
        self.spacing = spacing
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.content = content
    }

    var body: some View {
        Group {
            if shouldStack {
                VStack(alignment: verticalAlignment, spacing: spacing) {
                    content()
                }
            } else {
                HStack(alignment: horizontalAlignment, spacing: spacing) {
                    content()
                }
            }
        }
        .readAvailableWidth($availableWidth)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shouldStack: Bool {
        availableWidth > 0 && availableWidth < compactBreakpoint
    }
}

private struct AvailableWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

extension View {
    func readAvailableWidth(_ width: Binding<CGFloat>) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: AvailableWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(AvailableWidthPreferenceKey.self) { newValue in
            guard abs(width.wrappedValue - newValue) > 1 else { return }
            width.wrappedValue = newValue
        }
    }
}

struct Badge: View {
    var text: String
    var systemImage: String?
    var tint: Color

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(AppFont.caption(weight: .medium))
        .fontWeight(.medium)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.11), in: Capsule())
        .foregroundStyle(tint)
        .overlay {
            Capsule()
                .stroke(tint.opacity(0.16), lineWidth: 1)
        }
    }
}

struct EvidenceBadge: View {
    var level: EvidenceLevel

    var body: some View {
        let color: Color = switch level {
        case .a: AppTheme.success
        case .b: AppTheme.info
        case .c: AppTheme.warning
        case .d: AppTheme.danger
        case .e: .secondary
        }
        Badge(text: level.rawValue, systemImage: nil, tint: color)
            .help(level.label)
    }
}

struct SeverityBadge: View {
    var severity: IssueSeverity

    var body: some View {
        let color: Color = switch severity {
        case .info: .secondary
        case .warning: AppTheme.warning
        case .critical: AppTheme.danger
        }
        Badge(text: severity.rawValue, systemImage: severity.systemImage, tint: color)
    }
}

struct PackTopBar: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    @State private var isStatusExpanded = false
    @State private var pickerSnapshot = PackTopBarPickerSnapshot.empty
    @State private var pickerSnapshotRevision: PackTopBarPickerRevision?
    @State private var pickerSnapshotRefreshTask: Task<Void, Never>?
    var leadingAccessory: AnyView? = nil
    var trailingReservedWidth: CGFloat = 0
    private let topChromePadding: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    leadingAccessory
                    contextPickerGroup
                    analysisMaterialSummaryText
                    Spacer(minLength: 8)
                    if shouldShowStatusSummary {
                        statusSummary
                    }
                    importButtons
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        leadingAccessory
                        contextPickerGroup
                        Spacer(minLength: 8)
                        importButtons
                    }
                    HStack(spacing: 8) {
                        analysisMaterialSummaryText
                        Spacer(minLength: 8)
                        if shouldShowStatusSummary {
                            statusSummary
                        }
                    }
                }
            }

            if shouldShowExpandedStatus {
                StatusDetailBanner(
                    text: store.statusText,
                    isExpanded: $isStatusExpanded
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .padding(.top, topChromePadding)
        .padding(.trailing, trailingReservedWidth)
        .background(AppTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.divider)
                .frame(height: 1)
        }
        .animation(.easeInOut(duration: 0.22), value: trailingReservedWidth)
        .onAppear {
            refreshPickerSnapshot(force: true)
        }
        .onChange(of: store.selectedPackID) { _ in
            refreshPickerSnapshot(force: true)
        }
        .onChange(of: store.workspace.selectedBusinessSpaceID) { _ in
            refreshPickerSnapshot(force: true)
        }
        .onChange(of: store.workspace.dataPacks.count) { _ in
            schedulePickerSnapshotRefresh()
        }
        .onChange(of: store.workspace.businessSpaces.count) { _ in
            schedulePickerSnapshotRefresh()
        }
        .onChange(of: store.statusText) { newValue in
            if newValue == "就绪" || newValue.count <= 40 {
                isStatusExpanded = false
            }
        }
        .onDisappear {
            pickerSnapshotRefreshTask?.cancel()
            pickerSnapshotRefreshTask = nil
        }
    }

    private var contextPickerGroup: some View {
        HStack(spacing: 10) {
            topBarPickerBlock(title: "业务空间") {
                businessSpacePicker
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(3)
    }

    private func topBarPickerBlock<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 7) {
            Text(title)
                .font(AppFont.caption(weight: .semibold))
                .foregroundStyle(AppTheme.mutedText)
                .lineLimit(1)
            content()
        }
    }

    private var packPicker: some View {
        Picker("数据包", selection: Binding(
            get: { store.selectedPackID },
            set: { packID in
                guard let packID else {
                    store.selectedPackID = nil
                    return
                }
                guard let pack = store.workspace.dataPacks.first(where: { $0.id == packID }) else {
                    store.selectedPackID = nil
                    return
                }
                store.select(pack: pack)
            }
        )) {
            ForEach(pickerSnapshot.packOptions) { pack in
                Text(pack.name).tag(Optional(pack.id))
            }
        }
        .frame(minWidth: 128, idealWidth: 200, maxWidth: 240)
        .font(AppFont.callout(weight: .semibold))
        .labelsHidden()
        .hoverControlShell(.pickerShell)
    }

    private var businessSpacePicker: some View {
        Picker("业务空间", selection: Binding(
            get: { store.selectedBusinessSpace?.id },
            set: { store.selectBusinessSpace($0) }
        )) {
            ForEach(pickerSnapshot.businessSpaceOptions) { space in
                Text(space.name).tag(Optional(space.id))
            }
        }
        .frame(minWidth: 128, idealWidth: 190, maxWidth: 230)
        .font(AppFont.callout(weight: .semibold))
        .labelsHidden()
        .hoverControlShell(.pickerShell)
        .help("切换业务空间会影响 AI 分析范围、知识库、Confluence Root Page 和参照数据源")
    }

    private func makePickerSnapshot() -> PackTopBarPickerSnapshot {
        let businessSpaceOptions = store.workspace.businessSpaces
            .filter { !$0.isArchived }
            .map { BusinessSpacePickerOption(id: $0.id, name: $0.name) }
        guard let spaceID = store.selectedBusinessSpace?.id else {
            return PackTopBarPickerSnapshot(
                packOptions: [],
                businessSpaceOptions: businessSpaceOptions,
                selectedPackDateText: nil,
                selectedPackSourceText: nil
            )
        }
        let packOptions: [PackPickerOption] = store.workspace.dataPacks
            .compactMap { (pack: DataPack) -> PackPickerOption? in
                guard pack.businessSpaceID == spaceID else { return nil }
                return PackPickerOption(id: pack.id, name: pack.name, importedAt: pack.importedAt)
            }
            .sorted { $0.importedAt > $1.importedAt }
        return PackTopBarPickerSnapshot(
            packOptions: packOptions,
            businessSpaceOptions: businessSpaceOptions,
            selectedPackDateText: store.selectedPack?.dateRangeText,
            selectedPackSourceText: store.selectedPack?.reportSourceSummary
        )
    }

    private func schedulePickerSnapshotRefresh(delayNanoseconds: UInt64 = 220_000_000) {
        pickerSnapshotRefreshTask?.cancel()
        pickerSnapshotRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            refreshPickerSnapshot(force: false)
            pickerSnapshotRefreshTask = nil
        }
    }

    private func refreshPickerSnapshot(force: Bool) {
        let revision = makePickerRevision()
        guard force || revision != pickerSnapshotRevision else { return }
        pickerSnapshot = makePickerSnapshot()
        pickerSnapshotRevision = revision
    }

    private func makePickerRevision() -> PackTopBarPickerRevision {
        var dataPackHasher = Hasher()
        for pack in store.workspace.dataPacks {
            dataPackHasher.combine(pack.id)
            dataPackHasher.combine(pack.name)
            dataPackHasher.combine(pack.importedAt)
            dataPackHasher.combine(pack.businessSpaceID)
            if pack.id == store.selectedPackID {
                dataPackHasher.combine(pack.dateRangeText)
                dataPackHasher.combine(pack.importedReports.count)
                dataPackHasher.combine(pack.tableauReportCount)
            }
        }

        var businessSpaceHasher = Hasher()
        for space in store.workspace.businessSpaces {
            businessSpaceHasher.combine(space.id)
            businessSpaceHasher.combine(space.name)
            businessSpaceHasher.combine(space.isArchived)
        }

        return PackTopBarPickerRevision(
            selectedBusinessSpaceID: store.workspace.selectedBusinessSpaceID,
            selectedPackID: store.selectedPackID,
            dataPackHash: dataPackHasher.finalize(),
            businessSpaceHash: businessSpaceHasher.finalize()
        )
    }

    @ViewBuilder
    private var analysisMaterialSummaryText: some View {
        if let text = currentAnalysisMaterialSummary.nilIfBlank {
            Text(text)
                .font(AppFont.caption())
                .foregroundStyle(AppTheme.mutedText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 0, idealWidth: 280, maxWidth: 360, alignment: .leading)
                .clipped()
                .layoutPriority(0)
        }
    }

    private var currentAnalysisMaterialSummary: String {
        guard let pack = store.selectedPack else {
            return "尚未导入分析表"
        }
        let selectedCount = store.reportsForCurrentTask(in: pack).count
        let localCount = pack.localReportCount
        let tableauCount = pack.tableauReportCount
        return "本次分析表 \(selectedCount) 张 · 已导入本地表 \(localCount) 张 · 已导入 Tableau \(tableauCount) 张"
    }

    private var statusSummary: some View {
        StatusSummaryView(
            text: store.statusText,
            isExpanded: $isStatusExpanded
        )
        .layoutPriority(1)
    }

    private var importButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                evidenceTopBarButton(title: "查看证据")
                tableauTopBarButton(title: "接入 Tableau")
            }
            HStack(spacing: 8) {
                evidenceTopBarButton(title: "查看证据")
                tableauTopBarButton(title: "Tableau")
            }
            topBarActionsMenu
        }
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(4)
    }

    @ViewBuilder
    private func evidenceTopBarButton(title: String) -> some View {
        if store.canToggleAnalysisInfoSidebarFromTitlebar {
            Button {
                toggleEvidenceSidebar()
            } label: {
                topBarActionLabel(title, systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(AppHoverButtonStyle(variant: store.isAnalysisInfoSidebarVisible && store.analysisInfoSidebarPanelID == "证据" ? .primary : .secondary))
            .help(store.isAnalysisInfoSidebarVisible && store.analysisInfoSidebarPanelID == "证据" ? "收起证据侧栏" : "打开本轮分析证据、读取范围和本地校验结果")
        }
    }

    private func tableauTopBarButton(title: String) -> some View {
        Button {
            store.showTableauImportSheet()
        } label: {
            topBarActionLabel(title, systemImage: "chart.bar.doc.horizontal")
        }
        .buttonStyle(AppHoverButtonStyle(variant: .secondary))
        .disabled(store.isImportingData)
        .help("从 Tableau 视图或工作表导入数据")
    }

    private func topBarActionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var topBarActionsMenu: some View {
        Menu {
            if store.canToggleAnalysisInfoSidebarFromTitlebar {
                Button {
                    toggleEvidenceSidebar()
                } label: {
                    Label("查看证据", systemImage: "doc.text.magnifyingglass")
                }
            }
            Button {
                store.showTableauImportSheet()
            } label: {
                Label("接入 Tableau", systemImage: "chart.bar.doc.horizontal")
            }
            .disabled(store.isImportingData)
        } label: {
            topBarActionLabel("更多", systemImage: "ellipsis.circle")
        }
        .hoverControlShell(.pickerShell)
        .help("查看证据、导入本地表或接入 Tableau")
    }

    private func toggleEvidenceSidebar() {
        if store.isAnalysisInfoSidebarVisible && store.analysisInfoSidebarPanelID == "证据" {
            store.isAnalysisInfoSidebarVisible = false
        } else {
            store.analysisInfoSidebarPanelID = "证据"
            store.isAnalysisInfoSidebarVisible = true
        }
    }

    private var shouldShowExpandedStatus: Bool {
        isStatusExpanded && store.statusText != "就绪" && store.statusText.count > 40
    }

    private var shouldShowStatusSummary: Bool {
        let trimmed = store.statusText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "就绪"
    }
}

private struct PackTopBarPickerSnapshot: Equatable {
    var packOptions: [PackPickerOption]
    var businessSpaceOptions: [BusinessSpacePickerOption]
    var selectedPackDateText: String?
    var selectedPackSourceText: String?

    static let empty = PackTopBarPickerSnapshot(
        packOptions: [],
        businessSpaceOptions: [],
        selectedPackDateText: nil,
        selectedPackSourceText: nil
    )
}

private struct PackTopBarPickerRevision: Equatable {
    var selectedBusinessSpaceID: UUID?
    var selectedPackID: UUID?
    var dataPackHash: Int
    var businessSpaceHash: Int
}

private struct PackPickerOption: Identifiable, Hashable {
    var id: UUID
    var name: String
    var importedAt: Date
}

private struct BusinessSpacePickerOption: Identifiable, Hashable {
    var id: UUID
    var name: String
}

private struct StatusDisplayText {
    var raw: String
    var message: String
    var technicalDetail: String?

    init(_ raw: String) {
        self.raw = raw
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let containsHTML = trimmed.range(of: "<html", options: .caseInsensitive) != nil ||
            trimmed.range(of: "<iframe", options: .caseInsensitive) != nil ||
            trimmed.range(of: "<body", options: .caseInsensitive) != nil
        let isTableauError = trimmed.localizedCaseInsensitiveContains("Tableau") &&
            (trimmed.localizedCaseInsensitiveContains("HTTP 502") || containsHTML)

        if isTableauError {
            let requestID = StatusDisplayText.firstCapture(in: trimmed, pattern: #"requestId=([^"'&<>\s]+)"#)
            var message = "Tableau 服务暂时不可用。请稍后重试，或在 Tableau 中确认该视图可以下载 CSV/Crosstab。"
            if let requestID {
                message += " Request ID：\(requestID)。"
            }
            self.message = message
            self.technicalDetail = trimmed
        } else if containsHTML {
            self.message = "服务返回了无法直接展示的错误页面。请展开技术详情或稍后重试。"
            self.technicalDetail = trimmed
        } else {
            self.message = trimmed
            self.technicalDetail = nil
        }
    }

    var isError: Bool {
        raw.contains("失败") || raw.contains("错误") || raw.contains("HTTP") || technicalDetail != nil
    }

    var summary: String {
        guard message.count > 42 else { return message }
        return String(message.prefix(42)) + "…"
    }

    var shouldOfferExpansion: Bool {
        message.count > 40 || technicalDetail != nil
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
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

private struct StatusSummaryView: View {
    var text: String
    @Binding var isExpanded: Bool

    var body: some View {
        let display = StatusDisplayText(text)
        HStack(spacing: 6) {
            Image(systemName: display.isError ? "exclamationmark.triangle" : "info.circle")
                .foregroundStyle(display.isError ? AppTheme.warning : AppTheme.icon)

            Text(display.summary)
                .font(AppFont.caption())
                .foregroundStyle(AppTheme.mutedText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 0, maxWidth: 320, alignment: .trailing)
                .clipped()

            if display.shouldOfferExpansion {
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.up.circle" : "chevron.down.circle")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .ghost))
                .help(isExpanded ? "收起完整提示" : "展开完整提示")
            }
        }
        .frame(minWidth: 0, maxWidth: 380, alignment: .trailing)
        .clipped()
    }
}

private struct StatusDetailBanner: View {
    var text: String
    @Binding var isExpanded: Bool

    var body: some View {
        let display = StatusDisplayText(text)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: display.isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(display.isError ? AppTheme.warning : AppTheme.info)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(display.message)
                    .font(AppFont.caption())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let technicalDetail = display.technicalDetail {
                    DisclosureGroup("技术详情") {
                        Text(technicalDetail)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppTheme.mutedText)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(AppHoverButtonStyle(variant: .ghost))
            .help("复制完整提示")

            Button {
                isExpanded = false
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(AppHoverButtonStyle(variant: .ghost))
            .help("关闭提示")
        }
        .padding(10)
        .background((display.isError ? AppTheme.warning : AppTheme.info).opacity(0.11), in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke((display.isError ? AppTheme.warning : AppTheme.info).opacity(0.18), lineWidth: 1)
        }
    }
}

struct KeyValueRow: View {
    var key: String
    var value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(key)
                .foregroundStyle(AppTheme.mutedText)
                .frame(width: 90, alignment: .leading)
            Text(value.isEmpty ? "未记录" : value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(AppFont.callout())
    }
}

private extension String {
    func previewSlice(limit: Int) -> (text: String, isTruncated: Bool) {
        guard limit > 0 else { return ("…", true) }
        guard let boundary = index(startIndex, offsetBy: limit, limitedBy: endIndex) else {
            return (self, false)
        }
        guard boundary < endIndex else { return (self, false) }
        return (String(self[..<boundary]) + "\n\n…内容较长，展开后可查看完整文本。", true)
    }
}
