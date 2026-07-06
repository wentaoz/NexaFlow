import SwiftUI

struct ReferenceCollectionRunRow: View {
    var run: ExternalReferenceCollectionRun
    var filterItemsAction: () -> Void
    var editSourceAction: (UUID) -> Void
    var retrySourceAction: (UUID) -> Void

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button("筛选本次采集结果") {
                        filterItemsAction()
                    }
                    .buttonStyle(AppHoverButtonStyle(variant: .secondary))
                    .help("只在下方“情报沉淀结果”里显示这一次采集任务产生的外部情报，方便回溯本次采集用到了哪些内容。")
                    Spacer()
                }
                if let window = run.evidenceWindow {
                    Text("分析周期：\(window.summary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let phase = run.phase?.nilIfBlank {
                    Text("当前阶段：\(phase)")
                        .font(.caption)
                        .foregroundStyle(run.status == .running ? AppTheme.accent : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("预算 \(run.timeBudgetSeconds ?? 0) 秒 · 完成源 \(run.completedSourceCount ?? run.sourceLogs.filter { $0.status != .running }.count)/\(run.enabledSourceCount) · AI 已分析 \(run.analyzedItemCount ?? 0) · 待复核 \(run.pendingItemCount ?? 0)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !run.errorMessage.isEmpty {
                    Text("错误：\(run.errorMessage)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if run.sourceLogs.isEmpty {
                    Text("暂无单源日志。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(run.sourceLogs) { log in
                            ReferenceSourceRunLogRow(
                                log: log,
                                editSourceAction: editSourceAction,
                                retrySourceAction: retrySourceAction
                            )
                            Divider()
                        }
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Badge(text: run.trigger.label, systemImage: nil, tint: AppTheme.accent)
                    Badge(text: run.status.label, systemImage: nil, tint: tint(for: run.status))
                    Text(DateFormatting.shortDateTime.string(from: run.startedAt))
                        .font(.headline)
                    Spacer()
                    Text("源 \(run.successfulSourceCount)/\(run.enabledSourceCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(run.phase ?? "采集任务") · 命中 \(run.rawItemCount) · 新增 \(run.insertedItemCount) · 去重 \(run.duplicateItemCount) · 过滤 \(run.irrelevantItemCount) · 沉淀 \(run.knowledgeEntryCount) · 待复核 \(run.pendingItemCount ?? 0)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tint(for status: ExternalReferenceCollectionStatus) -> Color {
        switch status {
        case .running: return AppTheme.accent
        case .succeeded: return AppTheme.success
        case .partialFailed: return AppTheme.warning
        case .failed: return AppTheme.danger
        case .cancelled: return .secondary
        }
    }
}

private struct ReferenceSourceRunLogRow: View {
    var log: ExternalReferenceSourceRunLog
    var editSourceAction: (UUID) -> Void
    var retrySourceAction: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Badge(text: log.status.label, systemImage: nil, tint: tint(for: log.status))
                Text(log.sourceName)
                    .fontWeight(.medium)
                Text(log.collectorType.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(log.durationMs) ms")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let sourceID = log.sourceID {
                HStack(spacing: 8) {
                    Button("编辑数据源") {
                        editSourceAction(sourceID)
                    }
                    Button("重试此源") {
                        retrySourceAction(sourceID)
                    }
                    .disabled(log.status == .running)
                    Spacer()
                }
                .font(.caption)
            }
            if !log.renderedQuery.isEmpty {
                KeyValueRow(key: "Query", value: log.renderedQuery)
            }
            if !log.endpoint.isEmpty {
                KeyValueRow(key: "Endpoint", value: log.endpoint)
            }
            if let countryDecision = log.tavilyCountryDecision?.nilIfBlank {
                let sent = log.tavilyCountrySent?.nilIfBlank ?? "未传"
                let input = log.tavilyCountryInput?.nilIfBlank ?? "未配置"
                KeyValueRow(key: "Country 参数", value: "原始 \(input) · 实传 \(sent) · \(countryDecision)")
            }
            Text("返回 \(log.rawItemCount) · 有效 \(log.validItemCount) · 写入 \(log.insertedItemCount) · 沉淀 \(log.knowledgeEntryCount)\(log.httpStatusCode.map { " · HTTP \($0)" } ?? "")")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !log.errorMessage.isEmpty {
                Text(log.errorMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reason = log.cancellationReason?.nilIfBlank {
                Text("取消原因：\(reason)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reason = log.timeoutReason?.nilIfBlank {
                Text("超时原因：\(reason)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private func tint(for status: ExternalReferenceCollectionStatus) -> Color {
        switch status {
        case .running: return AppTheme.accent
        case .succeeded: return AppTheme.success
        case .partialFailed: return AppTheme.warning
        case .failed: return AppTheme.danger
        case .cancelled: return .secondary
        }
    }
}
