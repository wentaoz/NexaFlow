import AppKit
import SwiftUI

struct DetailView: View {
    var selection: SidebarSelection
    var leadingAccessory: AnyView? = nil

    var body: some View {
        VStack(spacing: 0) {
            PackTopBar(leadingAccessory: leadingAccessory)
            Divider()

            Group {
                switch selection {
                case .dashboard:
                    DeferredDetailPage(
                        title: "分析会话",
                        systemImage: SidebarSelection.sessions.systemImage,
                        detail: "正在准备会话与消息..."
                    ) {
                        AnalysisSessionsView()
                    }
                case .businessSpaces:
                    DeferredDetailPage(title: "业务空间", systemImage: SidebarSelection.businessSpaces.systemImage) {
                        BusinessSpacesView()
                    }
                case .dataPacks:
                    DeferredDetailPage(title: "数据包管理", systemImage: SidebarSelection.dataPacks.systemImage) {
                        DataPacksView()
                    }
                case .quality:
                    DeferredDetailPage(title: "质检详情", systemImage: SidebarSelection.quality.systemImage) {
                        QualityView()
                    }
                case .timeline:
                    DeferredDetailPage(title: "事件时间轴", systemImage: SidebarSelection.timeline.systemImage) {
                        TimelineView()
                    }
                case .sessions:
                    DeferredDetailPage(
                        title: "分析会话",
                        systemImage: SidebarSelection.sessions.systemImage,
                        detail: "正在准备会话与消息..."
                    ) {
                        AnalysisSessionsView()
                    }
                case .analysis:
                    DeferredDetailPage(title: "分析证据", systemImage: SidebarSelection.analysis.systemImage) {
                        AnalysisView()
                    }
                case .opportunities:
                    DeferredDetailPage(title: "机会评分", systemImage: SidebarSelection.opportunities.systemImage) {
                        OpportunitiesView()
                    }
                case .memo:
                    DeferredDetailPage(title: "报告草稿", systemImage: SidebarSelection.memo.systemImage) {
                        MemoView()
                    }
                case .references:
                    DeferredDetailPage(title: "参照数据源", systemImage: SidebarSelection.references.systemImage) {
                        ReferenceSourcesView()
                    }
                case .corrections:
                    DeferredDetailPage(title: "记忆中心", systemImage: SidebarSelection.corrections.systemImage) {
                        CorrectionMemoryView()
                    }
                case .knowledge:
                    DeferredDetailPage(title: "知识库", systemImage: SidebarSelection.knowledge.systemImage) {
                        KnowledgeView()
                    }
                case .settings:
                    DeferredDetailPage(title: "设置", systemImage: SidebarSelection.settings.systemImage) {
                        SettingsView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DeferredDetailPage<Content: View>: View {
    var title: String
    var systemImage: String
    var detail = "正在打开页面..."
    @ViewBuilder var content: () -> Content
    @State private var isReady = false

    var body: some View {
        Group {
            if isReady {
                content()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    SemanticLabel(title: title, systemImage: systemImage, iconSize: 20)
                        .font(.title2)
                        .fontWeight(.semibold)
                    ProgressView()
                        .controlSize(.small)
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .task {
            guard !isReady else { return }
            try? await Task.sleep(nanoseconds: 40_000_000)
            await MainActor.run {
                isReady = true
            }
        }
    }
}
