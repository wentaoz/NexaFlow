import SwiftUI

struct ImportSourceChoiceSheet: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("选择导入来源")
                    .font(AppFont.title())
                Text("可以一次选择多张本地表格，也可以从 Tableau 视图或工作表导入数据。")
                    .font(AppFont.callout())
                    .foregroundStyle(AppTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 14) {
                importSourceCard(
                    title: "导入本地表",
                    subtitle: "支持一次多选 CSV / TSV / XLSX / XLS，导入后直接确认本次分析表。",
                    systemImage: "tray.and.arrow.down",
                    role: .data,
                    isDisabled: store.isImportingData
                ) {
                    dismiss()
                    DispatchQueue.main.async {
                        store.showImportPanel()
                    }
                }

                importSourceCard(
                    title: "从 Tableau 导入",
                    subtitle: "导入 View / Worksheet 的导出数据，导入后使用同一确认页加入本次分析。",
                    systemImage: "chart.bar.doc.horizontal",
                    role: .external,
                    isDisabled: store.isImportingData
                ) {
                    dismiss()
                    DispatchQueue.main.async {
                        store.showTableauImportSheet()
                    }
                }
            }

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(AppHoverButtonStyle(variant: .secondary))
            }
        }
        .padding(22)
        .frame(width: 620)
        .background(AppTheme.surface)
    }

    private func importSourceCard(
        title: String,
        subtitle: String,
        systemImage: String,
        role: SemanticIconRole,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                SemanticIcon(systemName: systemImage, role: role, size: 26, frameWidth: 32)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(AppFont.headline())
                    Text(subtitle)
                        .font(AppFont.caption())
                        .foregroundStyle(AppTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Text("选择")
                        .font(AppFont.caption(weight: .semibold))
                        .fontWeight(.semibold)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(AppTheme.mutedText)
            }
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
            .padding(16)
        }
        .buttonStyle(AppHoverButtonStyle(variant: .secondary))
        .disabled(isDisabled)
    }
}
