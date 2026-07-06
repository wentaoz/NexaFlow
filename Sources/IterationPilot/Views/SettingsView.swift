import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    @State private var notificationAuthorizationText = "系统通知权限尚未检查"
    @State private var aiSettingsDraft = AISettings.default
    @State private var lastCommittedAISettings = AISettings.default
    @State private var aiSettingsCommitTask: Task<Void, Never>?
    @State private var confluenceSettingsDraft = ConfluenceSettings.default
    @State private var lastCommittedConfluenceSettings = ConfluenceSettings.default
    @State private var confluenceSettingsCommitTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("AI 设置")
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                SectionCard(title: "OpenAI-compatible 接口", systemImage: "sparkles") {
                    Text("客户端会把本地分析结果整理成提示词，并发送到兼容 /chat/completions 的接口。可以填写完整 endpoint，也可以填写阿里云百炼这类 SDK base_url，客户端会自动补全 /chat/completions。")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        ResponsiveFormRow("Endpoint / Base URL", labelWidth: 136) {
                            AdaptiveTextField(placeholder: "https://dashscope.aliyuncs.com/compatible-mode/v1", text: Binding(
                                get: { aiSettingsDraft.endpoint },
                                set: { newValue in
                                    aiSettingsDraft.endpoint = newValue
                                    scheduleAISettingsCommit()
                                }
                            ), minLines: 1, maxLines: 3)
                        }

                        ResponsiveFormRow("Model", labelWidth: 136) {
                            AdaptiveTextField(placeholder: "qwen3.6-plus", text: Binding(
                                get: { aiSettingsDraft.model },
                                set: { newValue in
                                    aiSettingsDraft.model = newValue
                                    scheduleAISettingsCommit()
                                }
                            ), minLines: 1, maxLines: 2)
                        }

                        ResponsiveFormRow("API Key", labelWidth: 136) {
                            SecureField("sk-...", text: Binding(
                                get: { aiSettingsDraft.apiKey },
                                set: { newValue in
                                    aiSettingsDraft.apiKey = newValue
                                    scheduleAISettingsCommit()
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("System Prompt")
                            .foregroundStyle(.secondary)
                        AdaptiveTextBox(text: Binding(
                            get: { aiSettingsDraft.systemPrompt },
                            set: { newValue in
                                aiSettingsDraft.systemPrompt = newValue
                                scheduleAISettingsCommit()
                            }
                        ), minHeight: 120, maxHeight: 320)
                    }
                }

                notificationSettingsSection

                SectionCard(title: "Confluence 文档同步", systemImage: "network") {
                    Text("填写 Confluence 站点根地址、Root Page ID 和访问 Token 后即可同步页面树。同步范围先由 Root IDs 决定，标题关键字用于过滤最终导入和沉淀的页面。")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        ResponsiveFormRow("Base URL", labelWidth: 112) {
                            AdaptiveTextField(placeholder: "填写 Confluence Base URL", text: Binding(
                                get: { confluenceSettingsDraft.baseURL },
                                set: { newValue in
                                    confluenceSettingsDraft.baseURL = newValue
                                    scheduleConfluenceSettingsCommit()
                                }
                            ), minLines: 1, maxLines: 3)
                        }

                        ResponsiveFormRow("Root IDs", labelWidth: 112) {
                            AdaptiveTextField(placeholder: "填写 Root Page ID，多个用逗号分隔", text: Binding(
                                get: { confluenceSettingsDraft.rootPageIDs },
                                set: { newValue in
                                    confluenceSettingsDraft.rootPageIDs = newValue
                                    scheduleConfluenceSettingsCommit()
                                }
                            ), minLines: 1, maxLines: 3)
                        }

                        ResponsiveFormRow("标题关键字", labelWidth: 112) {
                            VStack(alignment: .leading, spacing: 5) {
                                AdaptiveTextField(placeholder: "留空表示不过滤；多个关键字用逗号或换行分隔", text: Binding(
                                    get: { confluenceSettingsDraft.titleKeywords },
                                    set: { newValue in
                                        confluenceSettingsDraft.titleKeywords = newValue
                                        scheduleConfluenceSettingsCommit()
                                    }
                                ), minLines: 1, maxLines: 5)

                                Text("示例：Sufinc信用卡, 授信, 还款, Dock, 风控。只匹配 Confluence 页面标题，不匹配正文。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        ResponsiveFormRow("Token", labelWidth: 112) {
                            SecureField("必填：Confluence Bearer Token", text: Binding(
                                get: { confluenceSettingsDraft.bearerToken },
                                set: { newValue in
                                    confluenceSettingsDraft.bearerToken = newValue
                                    scheduleConfluenceSettingsCommit()
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .help("直接填写 Confluence API Token。请求时会以 Authorization: Bearer <Token> 发送。")
                        }

                        ResponsiveFormRow("Max Pages", labelWidth: 112) {
                            Stepper(value: Binding(
                                get: { confluenceSettingsDraft.maxPages },
                                set: { newValue in
                                    confluenceSettingsDraft.maxPages = newValue
                                    flushConfluenceSettingsToStore()
                                }
                            ), in: 20...2000, step: 20) {
                                Text("\(confluenceSettingsDraft.maxPages)")
                            }
                        }
                    }

                    ResponsiveStack(compactBreakpoint: 520, spacing: 8) {
                        confluenceActionButtons
                    }
                }

                SectionCard(title: "当前数据路径", systemImage: "externaldrive") {
                    if let path = store.selectedPack?.sourcePath {
                        Text(path)
                            .font(.callout)
                            .textSelection(.enabled)
                    } else {
                        Text("示例数据或尚未导入外部数据包。")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(18)
        }
        .onAppear {
            resetSettingsDrafts()
            refreshNotificationAuthorization()
        }
        .onChange(of: store.workspace.aiSettings) { latest in
            guard aiSettingsCommitTask == nil, latest != aiSettingsDraft else { return }
            aiSettingsDraft = latest
            lastCommittedAISettings = latest
        }
        .onChange(of: store.workspace.confluenceSettings) { latest in
            guard confluenceSettingsCommitTask == nil, latest != confluenceSettingsDraft else { return }
            confluenceSettingsDraft = latest
            lastCommittedConfluenceSettings = latest
        }
        .onDisappear {
            flushSettingsDraftsToStore()
        }
    }

    private var notificationSettingsSection: some View {
        SectionCard(title: "通知设置", systemImage: "bell.badge") {
            Text("AI 回复完成后，可以发送 macOS 系统通知。默认只在 App 不在前台时提醒，避免你正在看页面时重复打扰。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                Toggle("AI 完成通知", isOn: Binding(
                    get: { store.workspace.notificationSettings.isEnabled },
                    set: { newValue in store.updateNotificationSettings { $0.isEnabled = newValue } }
                ))
                Toggle("AI 回复完成", isOn: Binding(
                    get: { store.workspace.notificationSettings.notifyAIReplyCompleted },
                    set: { newValue in store.updateNotificationSettings { $0.notifyAIReplyCompleted = newValue } }
                ))
                .disabled(!store.workspace.notificationSettings.isEnabled)
                Toggle("App 正在前台时也通知", isOn: Binding(
                    get: { store.workspace.notificationSettings.notifyWhenAppActive },
                    set: { newValue in store.updateNotificationSettings { $0.notifyWhenAppActive = newValue } }
                ))
                .disabled(!store.workspace.notificationSettings.isEnabled)
            }
            .toggleStyle(.checkbox)

            HStack(alignment: .top, spacing: 8) {
                SemanticIcon(
                    systemName: notificationAuthorizationText.contains("未开启") ? "bell.slash" : "bell.badge",
                    role: notificationAuthorizationText.contains("未开启") ? .risk : .opportunity,
                    size: 15,
                    frameWidth: 20
                )
                Text(notificationAuthorizationText)
                    .foregroundStyle(notificationAuthorizationText.contains("未开启") ? AppTheme.danger : .secondary)
                Spacer()
                Button("刷新权限状态") {
                    refreshNotificationAuthorization()
                }
                .buttonStyle(AppHoverButtonStyle(variant: .ghost))
            }
            .font(.caption)
            .padding(10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func refreshNotificationAuthorization() {
        AppNotificationService.shared.authorizationDescription { label in
            notificationAuthorizationText = label
        }
    }

    @ViewBuilder
    private var confluenceActionButtons: some View {
        Button {
            flushConfluenceSettingsToStore()
            store.testConfluenceConnection()
        } label: {
            SemanticLabel(title: store.isTestingConfluence ? "测试中" : "测试连接", systemImage: store.isTestingConfluence ? "hourglass" : "checkmark.seal", role: store.isTestingConfluence ? .external : .success)
        }
        .disabled(store.isTestingConfluence || store.isSyncingConfluence)

        Button {
            flushConfluenceSettingsToStore()
            store.syncConfluenceTree()
        } label: {
            SemanticLabel(title: store.isSyncingConfluence ? "同步中" : "同步页面树", systemImage: "arrow.triangle.2.circlepath", role: .external)
        }
        .disabled(store.isSyncingConfluence)

        Button {
            flushConfluenceSettingsToStore()
            store.importConfluencePagesFromJSON()
        } label: {
            SemanticLabel(title: "导入本地 pages.json", systemImage: "doc.badge.plus", role: .knowledge)
        }
        .disabled(store.isSyncingConfluence)
    }

    private func resetSettingsDrafts() {
        aiSettingsCommitTask?.cancel()
        aiSettingsCommitTask = nil
        confluenceSettingsCommitTask?.cancel()
        confluenceSettingsCommitTask = nil
        aiSettingsDraft = store.workspace.aiSettings
        lastCommittedAISettings = store.workspace.aiSettings
        confluenceSettingsDraft = store.workspace.confluenceSettings
        lastCommittedConfluenceSettings = store.workspace.confluenceSettings
    }

    private func scheduleAISettingsCommit() {
        let draft = aiSettingsDraft
        guard draft != lastCommittedAISettings else { return }
        aiSettingsCommitTask?.cancel()
        aiSettingsCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, aiSettingsDraft == draft else { return }
            commitAISettingsToStore(draft)
            aiSettingsCommitTask = nil
        }
    }

    private func scheduleConfluenceSettingsCommit() {
        let draft = confluenceSettingsDraft
        guard draft != lastCommittedConfluenceSettings else { return }
        confluenceSettingsCommitTask?.cancel()
        confluenceSettingsCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, confluenceSettingsDraft == draft else { return }
            commitConfluenceSettingsToStore(draft)
            confluenceSettingsCommitTask = nil
        }
    }

    private func flushSettingsDraftsToStore() {
        flushAISettingsToStore()
        flushConfluenceSettingsToStore()
    }

    private func flushAISettingsToStore() {
        aiSettingsCommitTask?.cancel()
        aiSettingsCommitTask = nil
        commitAISettingsToStore(aiSettingsDraft)
    }

    private func flushConfluenceSettingsToStore() {
        confluenceSettingsCommitTask?.cancel()
        confluenceSettingsCommitTask = nil
        commitConfluenceSettingsToStore(confluenceSettingsDraft)
    }

    private func commitAISettingsToStore(_ settings: AISettings) {
        guard settings != lastCommittedAISettings else { return }
        store.updateAISettings { $0 = settings }
        lastCommittedAISettings = settings
    }

    private func commitConfluenceSettingsToStore(_ settings: ConfluenceSettings) {
        guard settings != lastCommittedConfluenceSettings else { return }
        store.updateConfluenceSettings { $0 = settings }
        lastCommittedConfluenceSettings = settings
    }
}
