import AppKit
import SwiftUI

public struct ContentView: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    @State private var selectedSidebarID = SidebarSelection.sessions.id
    @State private var sidebarWasVisibleBeforeCompact = true
    @State private var mainSidebarWidth: CGFloat = 300
    @State private var analysisInfoSidebarWidth: CGFloat = 460
    private let compactWidthThreshold: CGFloat = 1280

    public init() {}

    private var selection: Binding<SidebarSelection> {
        Binding(
            get: { SidebarSelection.from(id: selectedSidebarID) },
            set: { selectedSidebarID = $0.id }
        )
    }

    public var body: some View {
        GeometryReader { proxy in
            let currentSelection = selection.wrappedValue
            let isCompactWidth = proxy.size.width < compactWidthThreshold
            let readingModeHidesSidebar = store.isAnalysisReadingMode && currentSelection == .sessions
            let shouldShowInlineSidebar = !readingModeHidesSidebar && !isCompactWidth && store.isMainSidebarVisible
            let shouldShowCompactSidebar = !readingModeHidesSidebar && isCompactWidth && store.isMainSidebarVisible
            let canShowAnalysisInfoSidebar = currentSelection == .sessions &&
                !store.isAnalysisReadingMode &&
                store.selectedPackID != nil &&
                store.workspace.selectedAnalysisSessionID != nil
            let shouldShowInlineAnalysisInfoSidebar = canShowAnalysisInfoSidebar &&
                !isCompactWidth &&
                store.isAnalysisInfoSidebarVisible
            let shouldShowCompactAnalysisInfoSidebar = canShowAnalysisInfoSidebar &&
                isCompactWidth &&
                store.isAnalysisInfoSidebarVisible

            ZStack {
                HStack(spacing: 0) {
                    AnimatedMainSidebarContainer(
                        isVisible: shouldShowInlineSidebar,
                        width: $mainSidebarWidth
                    ) {
                        SidebarView(selection: selection)
                    }

                    DetailView(
                        selection: currentSelection,
                        leadingAccessory: nil
                    )
                    .frame(
                        minWidth: isCompactWidth ? 0 : (shouldShowInlineAnalysisInfoSidebar ? 640 : 760),
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                    .background(AppTheme.window)

                    AnimatedAnalysisInfoRootSidebarContainer(
                        isVisible: shouldShowInlineAnalysisInfoSidebar,
                        width: $analysisInfoSidebarWidth,
                        commitWidth: { width in
                            store.analysisInfoSidebarWidth = width
                        }
                    ) {
                        AnalysisInfoSidebarRootView()
                    }
                }

                if shouldShowCompactSidebar {
                    HStack(spacing: 0) {
                        SidebarView(selection: selection)
                            .frame(width: 300)
                            .frame(maxHeight: .infinity)
                            .background(AppTheme.surface)
                            .shadow(color: AppTheme.shadow, radius: 18, x: 6, y: 0)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        Spacer(minLength: 0)
                    }
                    .background(
                        AppTheme.text.opacity(0.08)
                            .ignoresSafeArea()
                            .onTapGesture {
                                store.isMainSidebarVisible = false
                            }
                    )
                    .transition(.opacity)
                }

                if shouldShowCompactAnalysisInfoSidebar {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        DeferredRootAnalysisInfoSidebarContent(isVisible: shouldShowCompactAnalysisInfoSidebar) {
                            AnalysisInfoSidebarRootView()
                        }
                            .frame(width: min(max(analysisInfoSidebarWidth, 360), min(500, max(320, proxy.size.width - 32))))
                            .frame(maxHeight: .infinity)
                            .background(AppTheme.surface)
                            .shadow(color: AppTheme.shadow, radius: 18, x: -6, y: 0)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    .background(
                        AppTheme.text.opacity(0.07)
                            .ignoresSafeArea()
                            .onTapGesture {
                                store.isAnalysisInfoSidebarVisible = false
                            }
                    )
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.window)
            .buttonStyle(AppHoverButtonStyle(variant: .secondary))
            .appThemeRoot()
            .animation(.easeInOut(duration: 0.22), value: store.isMainSidebarVisible)
            .animation(.easeInOut(duration: 0.22), value: store.isAnalysisInfoSidebarVisible)
            .animation(.easeInOut(duration: 0.22), value: isCompactWidth)
            .onAppear {
                if isCompactWidth {
                    sidebarWasVisibleBeforeCompact = store.isMainSidebarVisible
                    store.isMainSidebarVisible = false
                }
            }
            .onChange(of: isCompactWidth) { compact in
                if compact {
                    sidebarWasVisibleBeforeCompact = store.isMainSidebarVisible
                    store.isMainSidebarVisible = false
                } else {
                    store.isMainSidebarVisible = sidebarWasVisibleBeforeCompact
                }
            }
        }
        .sheet(isPresented: $store.showingImportSourceChoice) {
            ImportSourceChoiceSheet()
                .environmentObject(store)
                .appThemeRoot()
        }
        .sheet(isPresented: $store.showingTableauImportSheet) {
            TableauImportSheet()
                .environmentObject(store)
                .appThemeRoot()
        }
        .sheet(item: $store.pendingPostImportConfirmation) { draft in
            PostImportAnalysisConfirmationSheet(draft: draft)
                .environmentObject(store)
                .appThemeRoot()
        }
        .sheet(item: $store.pendingTableStructureConfirmation) { draft in
            TableStructureConfirmationSheet(draft: draft)
                .environmentObject(store)
                .appThemeRoot()
        }
        .sheet(item: $store.pendingMetricMappingConfirmation) { draft in
            MetricMappingConfirmationSheet(draft: draft)
                .environmentObject(store)
                .appThemeRoot()
        }
        .onChange(of: store.importRequestToken) { _ in
            store.showImportSourceChoice()
        }
        .onAppear {
            analysisInfoSidebarWidth = store.analysisInfoSidebarWidth
            store.syncCurrentSidebarSelection(selection.wrappedValue)
        }
        .onChange(of: selectedSidebarID) { newValue in
            store.syncCurrentSidebarSelection(SidebarSelection.from(id: newValue))
        }
        .onChange(of: store.selectedPackID) { _ in
            store.isAnalysisReadingMode = false
        }
        .onChange(of: store.workspace.selectedBusinessSpaceID) { _ in
            store.isAnalysisReadingMode = false
        }
        .onChange(of: store.requestedSidebarSelection) { target in
            guard let target else { return }
            store.isAnalysisReadingMode = false
            selectedSidebarID = (target == .dashboard || target == .memo ? SidebarSelection.sessions : target).id
            store.syncCurrentSidebarSelection(SidebarSelection.from(id: selectedSidebarID))
            store.requestedSidebarSelection = nil
        }
    }

}

private struct AnimatedMainSidebarContainer<Content: View>: View {
    var isVisible: Bool
    @Binding var width: CGFloat
    @ViewBuilder var content: () -> Content

    @State private var isResizing = false
    private let minWidth: CGFloat = 230
    private let maxWidth: CGFloat = 320

    var body: some View {
        ZStack(alignment: .trailing) {
            content()
                .frame(width: clampedWidth)
                .background(AppTheme.surface)
                .allowsHitTesting(isVisible)
                .opacity(isVisible ? 1 : 0)
                .clipped()

            if isVisible {
                SidebarResizeHandle(
                    isActive: isResizing,
                    dragChanged: { delta in
                        width = min(max(width + delta, minWidth), maxWidth)
                    },
                    dragEnded: { isResizing = false },
                    dragStarted: { isResizing = true }
                )
            }
        }
        .frame(width: isVisible ? clampedWidth : 0, alignment: .leading)
        .frame(maxHeight: .infinity)
        .clipped()
    }

    private var clampedWidth: CGFloat {
        min(max(width, minWidth), maxWidth)
    }
}

private struct AnimatedAnalysisInfoRootSidebarContainer<Content: View>: View {
    var isVisible: Bool
    @Binding var width: CGFloat
    var commitWidth: (CGFloat) -> Void
    @ViewBuilder var content: () -> Content

    @State private var isResizing = false
    private let minWidth: CGFloat = 360
    private let maxWidth: CGFloat = 500

    var body: some View {
        ZStack(alignment: .leading) {
            DeferredRootAnalysisInfoSidebarContent(isVisible: isVisible) {
                content()
            }
                .frame(width: clampedWidth)
                .background(AppTheme.surface)
                .allowsHitTesting(isVisible)
                .opacity(isVisible ? 1 : 0)
                .clipped()

            if isVisible {
                SidebarResizeHandle(
                    isActive: isResizing,
                    dragChanged: { delta in
                        width = min(max(width - delta, minWidth), maxWidth)
                    },
                    dragEnded: {
                        isResizing = false
                        commitWidth(clampedWidth)
                    },
                    dragStarted: { isResizing = true }
                )
            }
        }
        .frame(width: isVisible ? clampedWidth : 0, alignment: .trailing)
        .frame(maxHeight: .infinity)
        .clipped()
    }

    private var clampedWidth: CGFloat {
        min(max(width, minWidth), maxWidth)
    }
}

private struct DeferredRootAnalysisInfoSidebarContent<Content: View>: View {
    var isVisible: Bool
    @ViewBuilder var content: () -> Content

    @State private var isMounted = false
    @State private var isReady = false
    @State private var renderGeneration = 0

    private let openDelayNanos: UInt64 = 120_000_000
    private let closeDelayNanos: UInt64 = 220_000_000

    var body: some View {
        Group {
            if isMounted {
                if isReady {
                    content()
                } else {
                    RootAnalysisInfoOpeningPlaceholder()
                }
            } else {
                RootAnalysisInfoOpeningPlaceholder()
            }
        }
        .onAppear {
            updateVisibility(isVisible, deferOpen: isVisible)
        }
        .onChange(of: isVisible) { visible in
            updateVisibility(visible, deferOpen: true)
        }
    }

    private func updateVisibility(_ visible: Bool, deferOpen: Bool) {
        renderGeneration += 1
        let generation = renderGeneration

        if visible {
            isMounted = true
            isReady = false
            Task { @MainActor in
                if deferOpen {
                    try? await Task.sleep(nanoseconds: openDelayNanos)
                }
                guard generation == renderGeneration else { return }
                isReady = true
            }
        } else {
            isReady = false
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: closeDelayNanos)
                guard generation == renderGeneration else { return }
                isMounted = false
            }
        }
    }
}

private struct RootAnalysisInfoOpeningPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在打开数据资料...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 26)
        .background(AppTheme.window)
    }
}

private struct SidebarResizeHandle: View {
    var isActive: Bool
    var dragChanged: (CGFloat) -> Void
    var dragEnded: () -> Void
    var dragStarted: () -> Void

    @State private var lastTranslation: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(isActive ? AppTheme.accent.opacity(0.32) : AppTheme.text.opacity(0.08))
            .frame(width: isActive ? 3 : 1)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle().inset(by: -4))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if lastTranslation == 0 {
                            dragStarted()
                        }
                        let delta = value.translation.width - lastTranslation
                        lastTranslation = value.translation.width
                        dragChanged(delta)
                    }
                    .onEnded { _ in
                        lastTranslation = 0
                        dragEnded()
                    }
            )
    }
}
