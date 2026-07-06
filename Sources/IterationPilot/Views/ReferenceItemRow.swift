import SwiftUI

struct ReferenceItemRow: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    var item: ExternalReferenceItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Badge(text: item.domain.label, systemImage: nil, tint: domainTint)
                Badge(text: item.intelligenceCategory.label, systemImage: nil, tint: AppTheme.info)
                Badge(text: "重要性 \(item.importance)/5", systemImage: nil, tint: item.importance >= 4 ? AppTheme.warning : .secondary)
                if item.knowledgeEntryID != nil {
                    Badge(text: "已沉淀", systemImage: "books.vertical", tint: AppTheme.success)
                }
                Text(item.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Text("\(DateFormatting.shortDate.string(from: item.displayDate)) · \(item.dateBasisLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text("采集：\(DateFormatting.shortDateTime.string(from: item.collectedAt))")
                if let publishedAt = item.publishedAt {
                    Text("发布：\(DateFormatting.shortDateTime.string(from: publishedAt))")
                }
                if let eventStartedAt = item.eventStartedAt {
                    Text("事件：\(DateFormatting.shortDateTime.string(from: eventStartedAt))")
                }
                Text("时间置信度 \(Int(item.resolvedDateConfidence * 100))%")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            Text(item.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            if !item.impact.isEmpty {
                Text("影响：\(item.impact)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack {
                Text(item.sourceName)
                if let collectionText {
                    Text("·")
                    Text(collectionText)
                        .lineLimit(1)
                }
                if !item.relevanceReason.isEmpty {
                    Text("·")
                    Text(item.relevanceReason)
                        .lineLimit(1)
                }
                if !item.url.isEmpty, let url = URL(string: item.url) {
                    Text("·")
                    Link("打开来源", destination: url)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private var domainTint: Color {
        switch item.domain {
        case .policy: return .secondary
        case .externalEvent: return .cyan
        case .market: return AppTheme.success
        case .manual: return .secondary
        case .competitor: return AppTheme.accent
        }
    }

    private var collectionText: String? {
        guard let runID = item.collectionRunID,
              let run = store.workspace.referenceCollectionRuns.first(where: { $0.id == runID }) else {
            return nil
        }
        return "来自采集任务：\(run.trigger.label) \(DateFormatting.shortDateTime.string(from: run.startedAt))"
    }
}
