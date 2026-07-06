import SwiftUI

private struct TimelineRevision: Equatable {
    var selectedPackID: UUID?
    var selectedBusinessSpaceID: UUID?
    var selectedPackHash: Int
    var scopedKnowledgeHash: Int
}

struct TimelineView: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    @State private var cachedItems: [TimelineItem] = []
    @State private var cachedRevision: TimelineRevision?
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            let items = cachedItems
            if store.selectedPack != nil || !items.isEmpty {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text("事件时间轴")
                        .font(.largeTitle)
                        .fontWeight(.semibold)

                    SectionCard(title: "知识库产品文档/事件轴", systemImage: "books.vertical") {
                        Text("产品上下文直接参考知识库和 Confluence 文档；Confluence 只使用需求文档自身创建/修改时间，不使用知识库同步或创建时间，且不默认等同实际上线时间。")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        if items.isEmpty {
                            Text("知识库里还没有可展示的产品文档或事件。同步 Confluence 后会自动出现在这里。")
                                .foregroundStyle(.secondary)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(items) { item in
                                    TimelineRow(item: item)
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .padding(18)
            } else {
                EmptyStateView(title: "没有时间轴", detail: "同步 Confluence 或沉淀知识库后，会自动生成产品事件轴。", systemImage: "calendar")
            }
        }
        .onAppear {
            refreshCacheIfNeeded()
        }
        .onReceive(store.$workspace) { _ in
            scheduleRefresh()
        }
        .onChange(of: store.selectedPackID) { _ in
            refreshCacheIfNeeded(force: true)
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    private func scheduleRefresh(delayNanoseconds: UInt64 = 220_000_000) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            refreshCacheIfNeeded(force: false)
            refreshTask = nil
        }
    }

    private func refreshCacheIfNeeded(force: Bool = false) {
        let revision = makeTimelineRevision()
        guard force || revision != cachedRevision else { return }
        let scopedEntries = spaceScopedKnowledgeEntries
        cachedRevision = revision
        cachedItems = timelineItems(
            for: store.selectedPack,
            knowledgeEntries: scopedEntries
        )
    }

    private var spaceScopedKnowledgeEntries: [KnowledgeEntry] {
        guard let spaceID = store.selectedBusinessSpace?.id else { return store.workspace.knowledgeEntries }
        return store.workspace.knowledgeEntries.filter { entry in
            entry.isGlobal || entry.businessSpaceID == spaceID
        }
    }

    private func makeTimelineRevision() -> TimelineRevision {
        let pack = store.selectedPack
        var packHasher = Hasher()
        if let pack {
            packHasher.combine(pack.id)
            for update in pack.productUpdates {
                packHasher.combine(update.id)
                packHasher.combine(update.date)
                packHasher.combine(update.module)
                packHasher.combine(update.changeType)
                packHasher.combine(update.targetUser)
                packHasher.combine(update.expectedMetric)
                packHasher.combine(update.releaseNote)
            }
            for event in pack.events {
                packHasher.combine(event.id)
                packHasher.combine(event.date)
                packHasher.combine(event.eventType)
                packHasher.combine(event.title)
                packHasher.combine(event.scope)
                packHasher.combine(event.note)
            }
        }

        let spaceID = store.selectedBusinessSpace?.id
        var knowledgeHasher = Hasher()
        for entry in store.workspace.knowledgeEntries {
            guard entry.isGlobal || entry.businessSpaceID == spaceID else { continue }
            knowledgeHasher.combine(entry.id)
            knowledgeHasher.combine(entry.createdAt)
            knowledgeHasher.combine(entry.businessSpaceID)
            knowledgeHasher.combine(entry.isGlobal)
            knowledgeHasher.combine(entry.scenario)
            knowledgeHasher.combine(entry.problem)
            knowledgeHasher.combine(entry.action)
            knowledgeHasher.combine(entry.result)
            knowledgeHasher.combine(entry.sourceUpdatedAt)
            knowledgeHasher.combine(entry.sourceCreatedAt)
            knowledgeHasher.combine(entry.tags)
        }

        return TimelineRevision(
            selectedPackID: store.selectedPackID,
            selectedBusinessSpaceID: store.workspace.selectedBusinessSpaceID,
            selectedPackHash: packHasher.finalize(),
            scopedKnowledgeHash: knowledgeHasher.finalize()
        )
    }

    private func timelineItems(for pack: DataPack?, knowledgeEntries: [KnowledgeEntry]) -> [TimelineItem] {
        let knowledgeItems = KnowledgeEventAxis.productEvents(from: knowledgeEntries)
            .prefix(200)
            .map {
                let timing = KnowledgeEventAxis.eventTiming(for: $0)
                let detail = [
                    KnowledgeEventAxis.detail(for: $0).nilIfBlank,
                    timing.basis == .explicitLaunchDate ? nil : "时间说明：\(timing.basis.caveat)"
                ].compactMap { $0 }.joined(separator: "\n")
                return TimelineItem(
                    id: $0.id,
                    date: timing.date,
                    kind: timing.basis == .explicitLaunchDate ? "知识库事件" : "知识库文档",
                    title: KnowledgeEventAxis.title(for: $0),
                    subtitle: "\(KnowledgeEventAxis.subtitle(for: $0)) · \(timing.basis.label)",
                    detail: detail,
                    tint: AppTheme.info,
                    systemImage: "books.vertical"
                )
            }

        let updates = (pack?.productUpdates ?? []).map {
            TimelineItem(
                id: $0.id,
                date: $0.date,
                kind: "产品更新",
                title: $0.releaseNote,
                subtitle: "\($0.module) · \($0.changeType)",
                detail: "目标用户：\($0.targetUser)；预期指标：\($0.expectedMetric)",
                tint: AppTheme.accent,
                systemImage: "shippingbox"
            )
        }
        let events = (pack?.events ?? []).map {
            TimelineItem(
                id: $0.id,
                date: $0.date,
                kind: $0.eventType,
                title: $0.title,
                subtitle: $0.scope,
                detail: $0.note,
                tint: color(for: $0.eventType),
                systemImage: image(for: $0.eventType)
            )
        }
        return (knowledgeItems + updates + events).sorted { $0.date > $1.date }
    }

    private func color(for type: String) -> Color {
        if type.contains("技术") { return AppTheme.danger }
        if type.contains("运营") { return AppTheme.warning }
        if type.contains("竞品") { return .secondary }
        return .secondary
    }

    private func image(for type: String) -> String {
        if type.contains("技术") { return "exclamationmark.triangle" }
        if type.contains("运营") { return "megaphone" }
        if type.contains("竞品") { return "scope" }
        return "calendar"
    }
}

private struct TimelineItem: Identifiable {
    var id: UUID
    var date: Date
    var kind: String
    var title: String
    var subtitle: String
    var detail: String
    var tint: Color
    var systemImage: String
}

private struct TimelineRow: View {
    var item: TimelineItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Text(DateFormatting.shortDate.string(from: item.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: item.systemImage)
                    .foregroundStyle(item.tint)
                    .frame(width: 22)
            }
            .frame(width: 92, alignment: .top)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Badge(text: item.kind, systemImage: nil, tint: item.tint)
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Text(item.title)
                    .fontWeight(.medium)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
