import SwiftUI

struct ReferenceSourceCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var draft: ReferenceSourceDraft
    var onSave: (ReferenceSourceDraft) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.sheetTitle)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("先填写必要信息，保存后数据源会直接启用；后续高级参数可在列表里继续编辑。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Badge(text: draft.domain.label, systemImage: nil, tint: badgeTint)
            }

            VStack(alignment: .leading, spacing: 10) {
                ResponsiveFormRow("名称", labelWidth: 86) {
                    AdaptiveTextField(placeholder: ReferenceSourceDraft.defaultName(for: draft.domain), text: $draft.name, minLines: 1, maxLines: 2)
                }

                ResponsiveFormRow("采集方式", labelWidth: 86) {
                    Picker("采集方式", selection: $draft.collectorType) {
                        ForEach(ExternalReferenceCollectorType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .labelsHidden()
                    .hoverControlShell(.pickerShell)
                    Text(collectorDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if needsURLField {
                    ResponsiveFormRow(urlLabel, labelWidth: 86) {
                        AdaptiveTextField(placeholder: urlPlaceholder, text: $draft.url, minLines: 1, maxLines: 3)
                    }
                }

                if needsQueryField {
                    ResponsiveFormRow("查询", labelWidth: 86) {
                        AdaptiveTextField(placeholder: queryPlaceholder, text: $draft.queryTemplate, minLines: 2, maxLines: 6)
                    }
                }

                if draft.collectorType != .manual {
                    ResponsiveFormRow("关键词", labelWidth: 86) {
                        AdaptiveTextField(placeholder: "竞品名、政策关键词、市场关键词，可用逗号或换行分隔", text: $draft.keywordsText, minLines: 1, maxLines: 4)
                    }
                }

                if draft.collectorType == .manual {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("人工备注")
                            .foregroundStyle(.secondary)
                        AdaptiveTextBox(text: $draft.manualNote, minHeight: 110, maxHeight: 220)
                    }
                }
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("保存后会启用该源；如配置不完整，采集时会在采集日志里显示失败原因。弹窗不会立即采集，也不会消耗 Tavily 请求。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("取消", role: .cancel) {
                    dismiss()
                }
                Button {
                    onSave(draft)
                    dismiss()
                } label: {
                    Label("保存并启用", systemImage: "checkmark.circle")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .primary))
            }
        }
        .padding(22)
        .frame(width: 620)
    }

    private var validationMessage: String? {
        switch draft.collectorType {
        case .manual:
            return draft.manualNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "配置待补全：人工填写源备注为空，保存后会启用，但采集不会产生有效情报。" : nil
        case .webPage, .rss:
            return draft.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "配置待补全：网页或 RSS 数据源需要 URL，保存后会启用，但正式采集会跳过。" : nil
        case .searchAPI:
            if draft.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "配置待补全：通用搜索接口需要 Endpoint URL，保存后会启用，但正式采集会跳过。"
            }
            return hasQueryOrKeywords ? nil : "配置待补全：通用搜索接口需要查询语句或关键词，保存后会启用，但正式采集会跳过。"
        case .tavilySearch:
            return hasQueryOrKeywords ? nil : "可以不填 URL，走全局 Tavily Endpoint；但必须填 Query 或关键词，否则保存后即使是启用状态，正式采集也会跳过它。"
        }
    }

    private var hasQueryOrKeywords: Bool {
        !draft.queryTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !draft.keywordsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var needsURLField: Bool {
        draft.collectorType == .webPage ||
            draft.collectorType == .rss ||
            draft.collectorType == .searchAPI ||
            draft.collectorType == .tavilySearch
    }

    private var needsQueryField: Bool {
        draft.collectorType == .searchAPI || draft.collectorType == .tavilySearch
    }

    private var urlLabel: String {
        draft.collectorType == .tavilySearch ? "URL（可选）" : "URL"
    }

    private var urlPlaceholder: String {
        switch draft.collectorType {
        case .tavilySearch:
            return "可留空，默认使用全局 Tavily Endpoint"
        case .searchAPI:
            return "https://example.com/search?q={query}"
        case .rss:
            return "https://example.com/rss.xml"
        case .webPage:
            return "https://example.com/page"
        case .manual:
            return ""
        }
    }

    private var queryPlaceholder: String {
        switch draft.domain {
        case .competitor:
            return "例如：Mexico fintech credit card competitor promotion news"
        case .policy:
            return "例如：Mexico credit regulation central bank consumer protection"
        case .externalEvent:
            return "例如：Mexico weather outage traffic public safety events"
        case .market:
            return "例如：Mexico consumer credit market fintech trend"
        case .manual:
            return "输入搜索查询"
        }
    }

    private var collectorDescription: String {
        switch draft.collectorType {
        case .manual:
            return "不联网，只把你写的备注作为外部参照。"
        case .webPage:
            return "读取固定网页内容，适合官网公告、政策页面或帮助中心。"
        case .rss:
            return "读取 RSS 列表，适合新闻源或公告订阅。"
        case .searchAPI:
            return "调用通用搜索接口，需要配置 Endpoint。"
        case .tavilySearch:
            return "使用全局 Tavily API 搜索，适合竞品、新闻、政策和外部事件。"
        }
    }

    private var badgeTint: Color {
        switch draft.domain {
        case .competitor: return AppTheme.accent
        case .policy: return .secondary
        case .market: return AppTheme.success
        case .externalEvent: return .cyan
        case .manual: return .secondary
        }
    }
}
