import SwiftUI

struct ReferenceSourceEditor: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    @State var source: ExternalReferenceSource
    @State private var lastCommittedSource: ExternalReferenceSource?
    @State private var sourceCommitTask: Task<Void, Never>?
    var beforeCollectAction: () -> Void = {}
    var focusLatestLogAction: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResponsiveStack(compactBreakpoint: 760, spacing: 8) {
                Badge(text: source.lifecycleStatus.label, systemImage: nil, tint: lifecycleTint)
                Badge(text: health.status.label, systemImage: nil, tint: healthTint)
                Badge(text: scopeLabel, systemImage: nil, tint: scopeTint)
                if !source.tavilyQueryGroup.isEmpty {
                    Badge(text: source.tavilyQueryGroup, systemImage: nil, tint: AppTheme.accent)
                }
                if !source.tavilySourceProfile.isEmpty {
                    Badge(text: source.tavilySourceProfile, systemImage: nil, tint: AppTheme.info)
                }
                enabledToggle
                nameField
                domainPicker
                    .frame(width: 150)
                collectorPicker
                    .frame(width: 150)
                deleteButton
            }

            Text(health.detail)
                .font(.caption)
                .foregroundStyle(health.isCollectable ? Color.secondary : AppTheme.warning)
                .fixedSize(horizontal: false, vertical: true)

            if let latestLog = health.latestLog {
                Text("最近结果：\(latestLog.status.label)，返回 \(latestLog.rawItemCount) 条，有效 \(latestLog.validItemCount) 条，沉淀 \(latestLog.knowledgeEntryCount) 条。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                if !source.recommendationReason.isEmpty || source.createdByAI {
                    ResponsiveFormRow("推荐理由", labelWidth: 70) {
                        AdaptiveTextField(placeholder: "这个源为什么值得采集", text: $source.recommendationReason, minLines: 1, maxLines: 4)
                    }
                }
                if !source.possibleImpactedMetricsText.isEmpty || source.createdByAI {
                    ResponsiveFormRow("影响指标", labelWidth: 70) {
                        AdaptiveTextField(placeholder: "可能影响哪些业务指标", text: $source.possibleImpactedMetricsText, minLines: 1, maxLines: 4)
                    }
                }
                ResponsiveFormRow("URL", labelWidth: 70) {
                    AdaptiveTextField(
                        placeholder: source.collectorType == .tavilySearch ? "Tavily 数据源可留空，默认使用全局 Endpoint" : "https://...",
                        text: $source.url,
                        minLines: 1,
                        maxLines: 3
                    )
                }

                ResponsiveFormRow("关键词", labelWidth: 70) {
                    AdaptiveTextField(placeholder: "竞品名、政策关键词、市场关键词", text: $source.keywordsText, minLines: 1, maxLines: 4)
                }

                ResponsiveFormRow("查询", labelWidth: 70) {
                    AdaptiveTextField(
                        placeholder: "查询语句，可用 {competitor} {aliases} {keywords} {focus_market} {languages}",
                        text: $source.queryTemplate,
                        minLines: 1,
                        maxLines: 6
                    )
                        .disabled(!usesSearchQuery)
                }
            }

            if source.collectorType == .searchAPI {
                DisclosureGroup("通用搜索接口") {
                    VStack(alignment: .leading, spacing: 8) {
                        ResponsiveFormRow("API Key", labelWidth: 76) {
                            SecureField("可选：Bearer API Key", text: $source.apiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        ResponsiveFormRow("字段路径", labelWidth: 76) {
                            ResponsiveStack(compactBreakpoint: 520, spacing: 8) {
                                AdaptiveTextField(placeholder: "标题字段路径，例如 title", text: $source.searchTitlePath, minLines: 1, maxLines: 2)
                                AdaptiveTextField(placeholder: "URL 字段路径，例如 url", text: $source.searchURLPath, minLines: 1, maxLines: 2)
                            }
                        }
                        Text("接口可使用包含 {query} 的 URL 模板；否则会自动追加 q 参数。返回 JSON 会自动寻找 results/items/data 等列表。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if source.collectorType == .tavilySearch {
                DisclosureGroup("Tavily 参数") {
                    VStack(alignment: .leading, spacing: 8) {
                        ResponsiveFormRow("竞品", labelWidth: 76) {
                            AdaptiveTextField(placeholder: "竞品名称", text: $source.competitorName, minLines: 1, maxLines: 2)
                        }

                        ResponsiveFormRow("别名", labelWidth: 76) {
                            AdaptiveTextField(placeholder: "竞品别名，换行或逗号分隔", text: $source.competitorAliasesText, minLines: 2, maxLines: 6)
                        }

                        ResponsiveFormRow("主题/深度", labelWidth: 76) {
                            ResponsiveStack(compactBreakpoint: 520, spacing: 8) {
                                AdaptiveTextField(placeholder: "news/general/finance", text: $source.tavilyTopic, minLines: 1, maxLines: 2)
                                AdaptiveTextField(placeholder: "basic/advanced", text: $source.tavilySearchDepth, minLines: 1, maxLines: 2)
                            }
                        }

                        ResponsiveFormRow("时间/数量", labelWidth: 76) {
                            ResponsiveStack(compactBreakpoint: 520, spacing: 8) {
                                AdaptiveTextField(placeholder: "day/week/month/year/none", text: $source.tavilyTimeRange, minLines: 1, maxLines: 2)
                                Stepper("结果数 \(source.tavilyMaxResults)", value: $source.tavilyMaxResults, in: 1...20)
                            }
                        }

                        ResponsiveFormRow("市场/语言", labelWidth: 76) {
                            ResponsiveStack(compactBreakpoint: 520, spacing: 8) {
                                AdaptiveTextField(placeholder: "重点市场，例如 Mexico", text: $source.tavilyCountry, minLines: 1, maxLines: 2)
                                AdaptiveTextField(placeholder: "语言提示", text: $source.tavilyLanguageHintsText, minLines: 1, maxLines: 3)
                            }
                        }

                        ResponsiveFormRow("包含域名", labelWidth: 76) {
                            AdaptiveTextField(placeholder: "换行或逗号分隔", text: $source.tavilyIncludeDomainsText, minLines: 2, maxLines: 6)
                        }

                        ResponsiveFormRow("排除域名", labelWidth: 76) {
                            AdaptiveTextField(placeholder: "换行或逗号分隔", text: $source.tavilyExcludeDomainsText, minLines: 2, maxLines: 6)
                        }
                    }
                    Toggle("包含 raw_content", isOn: $source.tavilyIncludeRawContent)
                    if !source.tavilyQueryGroup.isEmpty || !source.tavilySourceProfile.isEmpty {
                        Text("来源分组：\(source.tavilyQueryGroup.isEmpty ? "未记录" : source.tavilyQueryGroup) / \(source.tavilySourceProfile.isEmpty ? "未记录" : source.tavilySourceProfile)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("人工备注")
                    .foregroundStyle(.secondary)
                AdaptiveTextBox(text: $source.manualNote, minHeight: 82, maxHeight: 260)
                    .disabled(source.collectorType != .manual)
            }

            HStack {
                Text("最近采集：\(source.lastFetchedAt.map { DateFormatting.shortDateTime.string(from: $0) } ?? "未采集")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("测试此源") {
                    beforeCollectAction()
                    flushReferenceSourceToStore()
                    store.testCollectReferenceSource(source)
                }
                .disabled(testConfigurationIssue != nil || store.isCollectingReferences)
                .help(testConfigurationIssue?.detail ?? "只验证该源配置和返回质量，不代表正式分析已经使用它。")
                .buttonStyle(AppHoverButtonStyle(variant: .secondary))
                if let latestRunID = health.latestRunID {
                    Button("查看最近日志") {
                        flushReferenceSourceToStore()
                        focusLatestLogAction(latestRunID)
                    }
                    .buttonStyle(AppHoverButtonStyle(variant: .ghost))
                }
                if source.lifecycleStatus != .enabled {
                    Button("启用此源") {
                        flushReferenceSourceToStore()
                        store.enableReferenceSource(source)
                    }
                    .help("启用后参与后续完整分析/报告采集，不会立即采集。配置不完整时会显示健康状态并在正式采集中跳过。")
                    .buttonStyle(AppHoverButtonStyle(variant: .primary))
                }
                if source.lifecycleStatus != .ignored {
                    Button("忽略") {
                        flushReferenceSourceToStore()
                        store.ignoreReferenceSource(source)
                    }
                    .buttonStyle(AppHoverButtonStyle(variant: .ghost))
                }
                scopeActions
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            lastCommittedSource = source
        }
        .onChange(of: source) { newValue in
            scheduleReferenceSourceCommit(newValue)
        }
        .onChange(of: store.workspace.referenceSources.first(where: { $0.id == source.id })) { latest in
            guard let latest, latest != source else { return }
            guard sourceCommitTask == nil else { return }
            source = latest
            lastCommittedSource = latest
        }
        .onDisappear {
            flushReferenceSourceToStore()
        }
    }

    private var enabledToggle: some View {
        Toggle("启用", isOn: $source.enabled)
            .help("启用后参与后续完整分析/报告采集，不会立即采集。配置不完整时会显示健康状态并在正式采集中跳过。")
    }

    private var nameField: some View {
        AdaptiveTextField(placeholder: "数据源名称", text: $source.name, minLines: 1, maxLines: 3)
            .frame(minWidth: 160)
    }

    private var domainPicker: some View {
        Picker("类型", selection: $source.domain) {
            ForEach(ExternalReferenceDomain.allCases) { domain in
                Text(domain.label).tag(domain)
            }
        }
        .hoverControlShell(.pickerShell)
    }

    private var collectorPicker: some View {
        Picker("采集方式", selection: $source.collectorType) {
            ForEach(ExternalReferenceCollectorType.allCases) { type in
                Text(type.label).tag(type)
            }
        }
        .hoverControlShell(.pickerShell)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            sourceCommitTask?.cancel()
            sourceCommitTask = nil
            store.deleteReferenceSource(source)
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(AppHoverButtonStyle(variant: .danger))
    }

    private var usesSearchQuery: Bool {
        source.collectorType == .tavilySearch || source.collectorType == .searchAPI
    }

    private var lifecycleTint: Color {
        switch source.lifecycleStatus {
        case .enabled: return AppTheme.success
        case .tested: return AppTheme.accent
        case .candidate, .needsConfirmation: return AppTheme.warning
        case .ignored: return .secondary
        }
    }

    private var health: ReferenceSourceHealth {
        ReferenceSourceHealthEvaluator.evaluate(
            source: source,
            searchSettings: store.workspace.searchSettings,
            collectionRuns: store.workspace.referenceCollectionRuns
        )
    }

    private var testConfigurationIssue: ReferenceSourceHealth? {
        ReferenceSourceHealthEvaluator.configurationIssue(for: source, searchSettings: store.workspace.searchSettings)
    }

    private var healthTint: Color {
        switch health.status {
        case .collectable, .lastCollectionSucceeded: return AppTheme.success
        case .lastTestFailed: return AppTheme.danger
        case .missingTavilyKey, .missingQuery, .missingURL, .emptyManualNote: return AppTheme.warning
        }
    }

    private var scopeLabel: String {
        if source.isGlobal { return "全局源" }
        if source.isUnbound { return "未绑定" }
        if store.sourceBelongsToCurrentBusinessSpace(source) { return "当前空间" }
        return "其他空间"
    }

    private var scopeTint: Color {
        if source.isGlobal { return .secondary }
        if source.isUnbound { return AppTheme.warning }
        if store.sourceBelongsToCurrentBusinessSpace(source) { return AppTheme.success }
        return .secondary
    }

    @ViewBuilder
    private var scopeActions: some View {
        if source.isUnbound {
            Button("绑定到当前空间") {
                flushReferenceSourceToStore()
                store.bindReferenceSourceToCurrentBusinessSpace(source)
            }
            .buttonStyle(AppHoverButtonStyle(variant: .secondary))
            Button("标记为全局源") {
                flushReferenceSourceToStore()
                store.markReferenceSourceAsGlobal(source)
            }
            .buttonStyle(AppHoverButtonStyle(variant: .secondary))
        } else if source.isGlobal {
            Button("取消全局并绑定到当前空间") {
                flushReferenceSourceToStore()
                store.bindGlobalReferenceSourceToCurrentBusinessSpace(source)
            }
            .buttonStyle(AppHoverButtonStyle(variant: .secondary))
        } else if store.sourceBelongsToCurrentBusinessSpace(source) {
            Button("设为全局源") {
                flushReferenceSourceToStore()
                store.markReferenceSourceAsGlobal(source)
            }
            .buttonStyle(AppHoverButtonStyle(variant: .secondary))
            Button("从当前空间移除") {
                flushReferenceSourceToStore()
                store.removeReferenceSourceFromCurrentBusinessSpace(source)
            }
            .buttonStyle(AppHoverButtonStyle(variant: .danger))
        }
    }

    private func scheduleReferenceSourceCommit(_ newValue: ExternalReferenceSource) {
        guard lastCommittedSource != newValue else { return }
        sourceCommitTask?.cancel()
        sourceCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled,
                  source == newValue else {
                return
            }
            commitReferenceSourceToStore(newValue)
            sourceCommitTask = nil
        }
    }

    private func flushReferenceSourceToStore() {
        sourceCommitTask?.cancel()
        sourceCommitTask = nil
        commitReferenceSourceToStore(source)
    }

    private func commitReferenceSourceToStore(_ value: ExternalReferenceSource) {
        guard lastCommittedSource != value else { return }
        store.updateReferenceSource(value)
        lastCommittedSource = value
    }
}
