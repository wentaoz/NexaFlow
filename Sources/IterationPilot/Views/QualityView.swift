import SwiftUI

struct QualityView: View {
    @EnvironmentObject private var store: ProductWorkflowStore

    var body: some View {
        ScrollView {
            if let pack = store.selectedPack {
                DataQualityPanel(pack: pack, showTitle: true)
                .padding(18)
            } else {
                EmptyStateView(title: "没有可质检的数据", detail: "请先导入 Data Pack。", systemImage: "checkmark.seal")
            }
        }
    }
}

struct DataQualityPanel: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    var pack: DataPack
    var showTitle: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            qualityHeader

            LazyVGrid(columns: [GridItem(.adaptive(minimum: showTitle ? 154 : 118), spacing: 12)], spacing: 12) {
                QualityMetricTile(title: "结论", value: pack.qualityReport.verdict.rawValue, systemImage: pack.qualityReport.verdict.systemImage)
                QualityMetricTile(title: "指标日期", value: "\(pack.qualityReport.stats.metricDateCount)", systemImage: "calendar")
                QualityMetricTile(title: "指标记录", value: "\(pack.qualityReport.stats.metricCount)", systemImage: "chart.bar")
                QualityMetricTile(title: "问题数量", value: "\(pack.qualityReport.issues.count)", systemImage: "exclamationmark.triangle")
                QualityMetricTile(title: "更新时间", value: DateFormatting.shortDateTime.string(from: pack.qualityReport.generatedAt), systemImage: "clock")
            }

            SectionCard(title: "质检问题", systemImage: "list.bullet.rectangle") {
                if pack.qualityReport.issues.isEmpty {
                    Text("没有发现阻塞性质量问题。")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(pack.qualityReport.issues) { issue in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                SeverityBadge(severity: issue.severity)
                                Text(issue.title)
                                    .fontWeight(.medium)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                            }
                            Text(issue.detail)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("建议：\(issue.recommendedAction)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 6)
                        Divider()
                    }
                }
            }

            SectionCard(title: "Manifest", systemImage: "doc.badge.gearshape") {
                KeyValueRow(key: "周期", value: pack.manifest.period)
                KeyValueRow(key: "导出人", value: pack.manifest.exportedBy)
                KeyValueRow(key: "导出时间", value: pack.manifest.exportedAt.map { DateFormatting.shortDate.string(from: $0) } ?? "未记录")
                if !pack.manifest.sources.isEmpty {
                    Divider()
                    ForEach(pack.manifest.sources) { source in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.name)
                                .fontWeight(.medium)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(source.platform) · \(source.dateRange) · \(source.exportMethod)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var qualityHeader: some View {
        let title = Text(showTitle ? "质检详情" : "当前任务的数据质检结果")
            .font(showTitle ? .largeTitle : .headline)
            .fontWeight(showTitle ? .semibold : .bold)
            .fixedSize(horizontal: false, vertical: true)

        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                title
                Spacer()
                refreshButton
            }
            VStack(alignment: .leading, spacing: 10) {
                title
                refreshButton
            }
        }
    }

    private var refreshButton: some View {
        Button {
            store.recomputeSelectedPack()
        } label: {
            Label("重新质检", systemImage: "arrow.clockwise")
        }
    }
}

private struct QualityMetricTile: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                icon
                textBlock
            }
            VStack(alignment: .leading, spacing: 8) {
                icon
                textBlock
            }
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .padding(12)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(.title3)
            .frame(width: 24, alignment: .leading)
            .foregroundStyle(.secondary)
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(3)
                .minimumScaleFactor(0.68)
                .fixedSize(horizontal: false, vertical: true)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
}
