import SwiftUI

struct TableStructureConfirmationSheet: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TableStructureConfirmationDraft

    init(draft: TableStructureConfirmationDraft) {
        _draft = State(initialValue: draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            VStack(alignment: .leading, spacing: 12) {
                selector("周期列", selection: $draft.selectedPeriodColumn, values: draft.periodColumnCandidates)
                selector("指标列", selection: $draft.selectedMetricNameColumn, values: draft.metricNameColumnCandidates)
                selector("数值列", selection: $draft.selectedMetricValueColumn, values: draft.metricValueColumnCandidates)
                Toggle("周期空白时向下填充", isOn: $draft.fillDownPeriod)
                    .font(AppFont.callout())
                Picker("半年度归属", selection: $draft.halfYearBucketRule) {
                    Text("按周期起始日").tag("period_start_date")
                    Text("按周期结束日").tag("period_end_date")
                }
                .pickerStyle(.segmented)
            }
            .padding(14)
            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 10))
            footer
        }
        .padding(22)
        .frame(width: 560)
        .background(AppTheme.surface)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("确认表格结构")
                .font(AppFont.title(size: 18, weight: .semibold))
            Text(draft.reportName)
                .font(AppFont.callout())
                .foregroundStyle(AppTheme.mutedText)
            Text("识别置信度 \(Int(draft.confidence * 100))% · \(draft.reason)")
                .font(AppFont.caption())
                .foregroundStyle(AppTheme.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func selector(_ title: String, selection: Binding<String?>, values: [String]) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(AppFont.callout(weight: .semibold))
                .frame(width: 72, alignment: .leading)
            Picker(title, selection: Binding(
                get: { selection.wrappedValue ?? values.first ?? "" },
                set: { selection.wrappedValue = $0.nilIfBlank }
            )) {
                ForEach(values.uniqued(), id: \.self) { value in
                    Text(value.nilIfBlank ?? "未指定").tag(value)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
    }

    private var footer: some View {
        HStack {
            Button("取消") {
                store.dismissHarnessConfirmation()
                dismiss()
            }
            .buttonStyle(AppHoverButtonStyle(variant: .secondary))
            Spacer()
            Button {
                store.confirmTableStructure(draft)
                dismiss()
            } label: {
                Label("确认并重新分析", systemImage: "checkmark.circle")
            }
            .buttonStyle(AppHoverButtonStyle(variant: .primary))
            .disabled(draft.selectedPeriodColumn == nil || draft.selectedMetricNameColumn == nil || draft.selectedMetricValueColumn == nil)
        }
    }
}

struct MetricMappingConfirmationSheet: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MetricMappingConfirmationDraft

    init(draft: MetricMappingConfirmationDraft) {
        _draft = State(initialValue: draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            VStack(alignment: .leading, spacing: 8) {
                ForEach(draft.candidates) { candidate in
                    Button {
                        draft.selectedActualMetric = candidate.actualMetric
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: draft.selectedActualMetric == candidate.actualMetric ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(draft.selectedActualMetric == candidate.actualMetric ? AppTheme.accent : AppTheme.icon)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(candidate.actualMetric)
                                    .font(AppFont.callout(weight: .semibold))
                                Text("相似度 \(Int(candidate.score * 100))%\(candidate.sampleValues.isEmpty ? "" : " · 示例 \(candidate.sampleValues.prefix(3).joined(separator: "、"))")")
                                    .font(AppFont.caption())
                                    .foregroundStyle(AppTheme.mutedText)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            Toggle("保存为后续表格模板", isOn: $draft.saveAsTemplate)
                .font(AppFont.callout())
            footer
        }
        .padding(22)
        .frame(width: 560)
        .background(AppTheme.surface)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("确认指标映射")
                .font(AppFont.title(size: 18, weight: .semibold))
            Text("用户问题中的「\(draft.requestedMetric)」没有直接命中，请确认它对应表内哪个指标。")
                .font(AppFont.callout())
                .foregroundStyle(AppTheme.mutedText)
            Text(draft.reportName)
                .font(AppFont.caption())
                .foregroundStyle(AppTheme.faintText)
        }
    }

    private var footer: some View {
        HStack {
            Button("取消") {
                store.dismissHarnessConfirmation()
                dismiss()
            }
            .buttonStyle(AppHoverButtonStyle(variant: .secondary))
            Spacer()
            Button {
                store.confirmMetricMapping(draft)
                dismiss()
            } label: {
                Label("确认并重新分析", systemImage: "checkmark.circle")
            }
            .buttonStyle(AppHoverButtonStyle(variant: .primary))
            .disabled(draft.selectedActualMetric == nil)
        }
    }
}
