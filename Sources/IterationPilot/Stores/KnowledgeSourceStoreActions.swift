import AppKit
import Foundation

extension ProductWorkflowStore {
    var localKnowledgeFolderSourcesForSelectedBusinessSpace: [LocalKnowledgeFolderSource] {
        guard let spaceID = selectedBusinessSpace?.id else { return [] }
        return workspace.localKnowledgeFolderSources
            .filter { $0.businessSpaceID == spaceID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var localKnowledgeFolderSyncRecordsForSelectedBusinessSpace: [LocalKnowledgeFolderSyncRecord] {
        guard let spaceID = selectedBusinessSpace?.id else { return [] }
        return workspace.localKnowledgeFolderSyncRecords
            .filter { $0.businessSpaceID == spaceID }
            .sorted { $0.finishedAt > $1.finishedAt }
    }

    var dingtalkDocumentSourcesForSelectedBusinessSpace: [DingTalkDocumentSource] {
        guard let spaceID = selectedBusinessSpace?.id else { return [] }
        return workspace.dingtalkDocumentSources
            .filter { $0.businessSpaceID == spaceID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var dingtalkDocumentItemsForSelectedBusinessSpace: [DingTalkDocumentItem] {
        guard let spaceID = selectedBusinessSpace?.id else { return [] }
        return workspace.dingtalkDocumentItems
            .filter { $0.businessSpaceID == spaceID }
            .sorted { ($0.updatedAt ?? $0.syncedAt) > ($1.updatedAt ?? $1.syncedAt) }
    }

    var dingtalkDocumentSyncRecordsForSelectedBusinessSpace: [DingTalkDocumentSyncRecord] {
        guard let spaceID = selectedBusinessSpace?.id else { return [] }
        return workspace.dingtalkDocumentSyncRecords
            .filter { $0.businessSpaceID == spaceID }
            .sorted { $0.finishedAt > $1.finishedAt }
    }

    var jiraProjectSourcesForSelectedBusinessSpace: [JiraProjectSource] {
        guard let spaceID = selectedBusinessSpace?.id else { return [] }
        return workspace.jiraProjectSources
            .filter { $0.businessSpaceID == spaceID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var jiraProjectSyncRecordsForSelectedBusinessSpace: [JiraProjectSyncRecord] {
        guard let spaceID = selectedBusinessSpace?.id else { return [] }
        return workspace.jiraProjectSyncRecords
            .filter { $0.businessSpaceID == spaceID }
            .sorted { $0.finishedAt > $1.finishedAt }
    }

    var jiraProjectEvidencesForSelectedBusinessSpace: [JiraProjectEvidence] {
        guard let spaceID = selectedBusinessSpace?.id else { return [] }
        return workspace.jiraProjectEvidences
            .filter { $0.businessSpaceID == spaceID }
            .sorted { ($0.updatedAt ?? $0.statusChangedAt ?? $0.syncedAt) > ($1.updatedAt ?? $1.statusChangedAt ?? $1.syncedAt) }
    }

    func addLocalKnowledgeFolderSource() {
        guard let space = selectedBusinessSpace else {
            statusText = "请先选择业务空间"
            return
        }
        let panel = NSOpenPanel()
        panel.title = "选择本地知识文件夹"
        panel.message = "选择后会绑定到当前业务空间「\(space.name)」。同步只读取文件，不会修改原文件。"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let normalizedPath = url.standardizedFileURL.path
        if let existing = workspace.localKnowledgeFolderSources.first(where: { $0.businessSpaceID == space.id && $0.folderPath == normalizedPath }) {
            statusText = "这个文件夹已绑定：\(existing.displayName)"
            return
        }

        let source = LocalKnowledgeFolderSource(
            businessSpaceID: space.id,
            displayName: url.lastPathComponent.nilIfBlank ?? "本地知识文件夹",
            folderPath: normalizedPath,
            folderBookmarkData: try? SecurityScopedResource.bookmarkData(for: url)
        )
        workspace.localKnowledgeFolderSources.insert(source, at: 0)
        save()
        statusText = "已添加本地知识文件夹：\(source.displayName)"
    }

    func updateLocalKnowledgeFolderSource(_ source: LocalKnowledgeFolderSource, _ transform: (inout LocalKnowledgeFolderSource) -> Void) {
        guard let index = workspace.localKnowledgeFolderSources.firstIndex(where: { $0.id == source.id }) else { return }
        transform(&workspace.localKnowledgeFolderSources[index])
        workspace.localKnowledgeFolderSources[index].updatedAt = Date()
        save(policy: .deferred)
    }

    func deleteLocalKnowledgeFolderSource(_ source: LocalKnowledgeFolderSource) {
        workspace.localKnowledgeFolderSources.removeAll { $0.id == source.id }
        save()
        statusText = "已删除本地文件夹绑定，已沉淀的知识条目会保留"
    }

    func createDingTalkDocumentSource(_ draft: DingTalkDocumentSourceDraft) {
        guard let space = selectedBusinessSpace else {
            statusText = "请先选择业务空间"
            return
        }
        let displayName = draft.displayName.nilIfBlank ?? "钉钉文档源"
        let source = DingTalkDocumentSource(
            businessSpaceID: space.id,
            displayName: displayName,
            clientID: draft.clientID.trimmingCharacters(in: .whitespacesAndNewlines),
            clientSecret: draft.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines),
            agentID: draft.agentID.trimmingCharacters(in: .whitespacesAndNewlines),
            operatorID: draft.operatorID.trimmingCharacters(in: .whitespacesAndNewlines),
            defaultSpaceID: draft.defaultSpaceID.trimmingCharacters(in: .whitespacesAndNewlines),
            folderInputs: draft.folderInputs.trimmingCharacters(in: .whitespacesAndNewlines),
            titleKeywords: draft.titleKeywords.trimmingCharacters(in: .whitespacesAndNewlines),
            excludedTitleKeywords: draft.excludedTitleKeywords.trimmingCharacters(in: .whitespacesAndNewlines),
            syncSchedule: draft.syncSchedule,
            maxDocuments: max(1, min(draft.maxDocuments, 500))
        )
        workspace.dingtalkDocumentSources.insert(source, at: 0)
        workspace.knowledgeSourceConnectors.insert(
            KnowledgeSourceConnector(
                connectorType: .dingtalk,
                businessSpaceID: space.id,
                displayName: source.displayName,
                status: .available,
                syncSchedule: source.syncSchedule
            ),
            at: 0
        )
        save()
        statusText = "已添加钉钉文档源：\(source.displayName)"
    }

    func updateDingTalkDocumentSource(_ source: DingTalkDocumentSource, _ transform: (inout DingTalkDocumentSource) -> Void) {
        guard let index = workspace.dingtalkDocumentSources.firstIndex(where: { $0.id == source.id }) else { return }
        transform(&workspace.dingtalkDocumentSources[index])
        workspace.dingtalkDocumentSources[index].updatedAt = Date()
        workspace.dingtalkDocumentSources[index].maxDocuments = max(1, min(workspace.dingtalkDocumentSources[index].maxDocuments, 500))
        save(policy: .deferred)
    }

    func deleteDingTalkDocumentSource(_ source: DingTalkDocumentSource) {
        workspace.dingtalkDocumentSources.removeAll { $0.id == source.id }
        save()
        statusText = "已删除钉钉文档源，已同步的知识条目会保留"
    }

    func testDingTalkDocumentSource(_ source: DingTalkDocumentSource) {
        guard !testingDingTalkDocumentSourceIDs.contains(source.id) else { return }
        guard let current = workspace.dingtalkDocumentSources.first(where: { $0.id == source.id }) else { return }
        testingDingTalkDocumentSourceIDs.insert(source.id)
        statusText = "正在测试钉钉连接：\(current.displayName)"

        Task { [weak self] in
            guard let self else { return }
            defer { self.testingDingTalkDocumentSourceIDs.remove(current.id) }
            do {
                self.statusText = try await DingTalkDocumentService().testConnection(source: current)
            } catch {
                self.statusText = "钉钉测试失败：\(error.localizedDescription)"
            }
        }
    }

    func syncDingTalkDocumentSource(_ source: DingTalkDocumentSource, automatic: Bool = false) {
        guard !syncingDingTalkDocumentSourceIDs.contains(source.id) else { return }
        guard let current = workspace.dingtalkDocumentSources.first(where: { $0.id == source.id }) else { return }
        syncingDingTalkDocumentSourceIDs.insert(source.id)
        statusText = automatic ? "正在自动同步钉钉文档：\(current.displayName)" : "正在同步钉钉文档：\(current.displayName)"
        let startedAt = Date()

        Task { [weak self] in
            guard let self else { return }
            defer { self.syncingDingTalkDocumentSourceIDs.remove(current.id) }
            do {
                let result = try await DingTalkDocumentService().fetchDocuments(source: current)
                self.mergeDingTalkDocumentSyncResult(
                    sourceID: current.id,
                    result: result,
                    startedAt: startedAt,
                    automatic: automatic,
                    failureMessage: nil
                )
            } catch {
                let result = DingTalkDocumentFetchResult(items: [], folderCount: current.parsedFolderInputs.count, skippedCount: 0, failures: [])
                self.mergeDingTalkDocumentSyncResult(
                    sourceID: current.id,
                    result: result,
                    startedAt: startedAt,
                    automatic: automatic,
                    failureMessage: error.localizedDescription
                )
            }
        }
    }

    func syncAllEnabledDingTalkDocumentSourcesForSelectedSpace() {
        let sources = dingtalkDocumentSourcesForSelectedBusinessSpace.filter(\.isEnabled)
        guard !sources.isEmpty else {
            statusText = "当前业务空间没有已启用的钉钉文档源"
            return
        }
        for source in sources {
            syncDingTalkDocumentSource(source)
        }
    }

    func createJiraProjectSource(_ draft: JiraProjectSourceDraft) {
        guard let space = selectedBusinessSpace else {
            statusText = "请先选择业务空间"
            return
        }
        let projectKey = draft.projectKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = draft.displayName.nilIfBlank ?? "\(projectKey.nilIfBlank ?? "Jira") 项目状态"
        let source = JiraProjectSource(
            businessSpaceID: space.id,
            displayName: displayName,
            baseURL: draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            authMode: draft.authMode,
            username: draft.username.trimmingCharacters(in: .whitespacesAndNewlines),
            token: draft.token.trimmingCharacters(in: .whitespacesAndNewlines),
            projectKey: projectKey,
            jql: draft.jql.trimmingCharacters(in: .whitespacesAndNewlines),
            syncSchedule: draft.syncSchedule,
            maxIssues: max(1, min(draft.maxIssues, 500))
        )
        workspace.jiraProjectSources.insert(source, at: 0)
        workspace.knowledgeSourceConnectors.insert(
            KnowledgeSourceConnector(
                connectorType: .jira,
                businessSpaceID: space.id,
                displayName: source.displayName,
                status: .available,
                syncSchedule: source.syncSchedule
            ),
            at: 0
        )
        save()
        statusText = "已添加 Jira 项目状态源：\(source.displayName)"
    }

    func updateJiraProjectSource(_ source: JiraProjectSource, _ transform: (inout JiraProjectSource) -> Void) {
        guard let index = workspace.jiraProjectSources.firstIndex(where: { $0.id == source.id }) else { return }
        transform(&workspace.jiraProjectSources[index])
        workspace.jiraProjectSources[index].updatedAt = Date()
        workspace.jiraProjectSources[index].maxIssues = max(1, min(workspace.jiraProjectSources[index].maxIssues, 500))
        save(policy: .deferred)
    }

    func deleteJiraProjectSource(_ source: JiraProjectSource) {
        workspace.jiraProjectSources.removeAll { $0.id == source.id }
        save()
        statusText = "已删除 Jira 连接，已同步的知识条目和项目证据会保留"
    }

    func testJiraProjectSource(_ source: JiraProjectSource) {
        guard !testingJiraProjectSourceIDs.contains(source.id) else { return }
        guard let current = workspace.jiraProjectSources.first(where: { $0.id == source.id }) else { return }
        testingJiraProjectSourceIDs.insert(source.id)
        statusText = "正在测试 Jira 连接：\(current.displayName)"

        Task { [weak self] in
            guard let self else { return }
            defer { self.testingJiraProjectSourceIDs.remove(current.id) }
            do {
                self.statusText = try await JiraService().testConnection(source: current)
            } catch {
                self.statusText = "Jira 测试失败：\(error.localizedDescription)"
            }
        }
    }

    func syncJiraProjectSource(_ source: JiraProjectSource, automatic: Bool = false) {
        guard !syncingJiraProjectSourceIDs.contains(source.id) else { return }
        guard let current = workspace.jiraProjectSources.first(where: { $0.id == source.id }) else { return }
        syncingJiraProjectSourceIDs.insert(source.id)
        statusText = automatic ? "正在自动同步 Jira：\(current.displayName)" : "正在同步 Jira：\(current.displayName)"
        let startedAt = Date()

        Task { [weak self] in
            guard let self else { return }
            defer { self.syncingJiraProjectSourceIDs.remove(current.id) }
            do {
                let evidences = try await JiraService().fetchProjectEvidence(source: current)
                self.mergeJiraProjectSyncResult(
                    sourceID: current.id,
                    evidences: evidences,
                    startedAt: startedAt,
                    automatic: automatic,
                    failureMessage: nil
                )
            } catch {
                self.mergeJiraProjectSyncResult(
                    sourceID: current.id,
                    evidences: [],
                    startedAt: startedAt,
                    automatic: automatic,
                    failureMessage: error.localizedDescription
                )
            }
        }
    }

    func syncAllEnabledJiraProjectSourcesForSelectedSpace() {
        let sources = jiraProjectSourcesForSelectedBusinessSpace.filter(\.isEnabled)
        guard !sources.isEmpty else {
            statusText = "当前业务空间没有已启用的 Jira 项目状态源"
            return
        }
        for source in sources {
            syncJiraProjectSource(source)
        }
    }

    func syncLocalKnowledgeFolderSource(_ source: LocalKnowledgeFolderSource, automatic: Bool = false) {
        guard !syncingLocalKnowledgeFolderSourceIDs.contains(source.id) else { return }
        guard let current = workspace.localKnowledgeFolderSources.first(where: { $0.id == source.id }) else { return }
        syncingLocalKnowledgeFolderSourceIDs.insert(source.id)
        statusText = automatic ? "正在自动同步本地知识：\(current.displayName)" : "正在同步本地知识：\(current.displayName)"
        let startedAt = Date()

        Task { [weak self] in
            guard let self else { return }
            defer { self.syncingLocalKnowledgeFolderSourceIDs.remove(current.id) }
            let fallbackURL = URL(fileURLWithPath: current.folderPath, isDirectory: true)
            let resolution = SecurityScopedResource.resolve(
                bookmarkData: current.folderBookmarkData,
                fallbackURL: fallbackURL
            )
            if let refreshedBookmarkData = resolution.refreshedBookmarkData,
               let sourceIndex = self.workspace.localKnowledgeFolderSources.firstIndex(where: { $0.id == current.id }) {
                self.workspace.localKnowledgeFolderSources[sourceIndex].folderBookmarkData = refreshedBookmarkData
                self.save(policy: .deferred)
            }
            let parsedResult = await Task.detached(priority: .userInitiated) {
                SecurityScopedResource.access(resolution.url) {
                    LocalKnowledgeFolderSyncService.parseSupportedFiles(in: resolution.url)
                }
            }.value

            self.mergeLocalKnowledgeFolderSyncResult(
                sourceID: current.id,
                parsedFiles: parsedResult.files,
                totalFiles: parsedResult.totalFiles,
                failures: parsedResult.failures,
                startedAt: startedAt,
                automatic: automatic
            )
        }
    }

    func syncAllEnabledLocalKnowledgeFoldersForSelectedSpace() {
        let sources = localKnowledgeFolderSourcesForSelectedBusinessSpace.filter(\.isEnabled)
        guard !sources.isEmpty else {
            statusText = "当前业务空间没有已启用的本地知识文件夹"
            return
        }
        for source in sources {
            syncLocalKnowledgeFolderSource(source)
        }
    }

    func scheduleLocalKnowledgeFolderSync() {
        localKnowledgeFolderSyncTask?.cancel()
        localKnowledgeFolderSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    self?.runDueLocalKnowledgeFolderSyncIfNeeded()
                }
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            }
        }
    }

    func runDueLocalKnowledgeFolderSyncIfNeeded() {
        let now = Date()
        let calendar = Calendar.current
        guard calendar.component(.hour, from: now) >= 18 else { return }
        let dueSources = workspace.localKnowledgeFolderSources.filter { source in
            guard source.isEnabled, source.syncSchedule == .daily1800 else { return false }
            guard !syncingLocalKnowledgeFolderSourceIDs.contains(source.id) else { return false }
            guard let lastSyncAt = source.lastSyncAt else { return true }
            return !calendar.isDate(lastSyncAt, inSameDayAs: now)
        }
        for source in dueSources {
            syncLocalKnowledgeFolderSource(source, automatic: true)
        }

        let dueDingTalkSources = workspace.dingtalkDocumentSources.filter { source in
            guard source.isEnabled, source.syncSchedule == .daily1800 else { return false }
            guard !syncingDingTalkDocumentSourceIDs.contains(source.id) else { return false }
            guard let lastSyncAt = source.lastSyncAt else { return true }
            return !calendar.isDate(lastSyncAt, inSameDayAs: now)
        }
        for source in dueDingTalkSources {
            syncDingTalkDocumentSource(source, automatic: true)
        }

        let dueJiraSources = workspace.jiraProjectSources.filter { source in
            guard source.isEnabled, source.syncSchedule == .daily1800 else { return false }
            guard !syncingJiraProjectSourceIDs.contains(source.id) else { return false }
            guard let lastSyncAt = source.lastSyncAt else { return true }
            return !calendar.isDate(lastSyncAt, inSameDayAs: now)
        }
        for source in dueJiraSources {
            syncJiraProjectSource(source, automatic: true)
        }
    }

    func showDingTalkConnectorPlaceholder() {
        statusText = "钉钉文档源已支持配置：请填写 Client ID、Client Secret、operatorId 和文件夹链接后测试连接。"
    }

    private func mergeDingTalkDocumentSyncResult(
        sourceID: UUID,
        result: DingTalkDocumentFetchResult,
        startedAt: Date,
        automatic: Bool,
        failureMessage: String?
    ) {
        guard let sourceIndex = workspace.dingtalkDocumentSources.firstIndex(where: { $0.id == sourceID }) else { return }
        let source = workspace.dingtalkDocumentSources[sourceIndex]
        let businessSpace = workspace.businessSpaces.first { $0.id == source.businessSpaceID }

        var added = 0
        var updated = 0

        if failureMessage == nil {
            for item in result.items {
                if let existingIndex = workspace.dingtalkDocumentItems.firstIndex(where: { $0.sourceID == item.sourceID && $0.itemID == item.itemID }) {
                    var replacement = item
                    replacement.id = workspace.dingtalkDocumentItems[existingIndex].id
                    workspace.dingtalkDocumentItems[existingIndex] = replacement
                } else {
                    workspace.dingtalkDocumentItems.insert(item, at: 0)
                }

                let entry = knowledgeEntry(from: item, source: source, businessSpace: businessSpace)
                if let existingEntryIndex = workspace.knowledgeEntries.firstIndex(where: { $0.sourceID == entry.sourceID }) {
                    var replacement = entry
                    replacement.id = workspace.knowledgeEntries[existingEntryIndex].id
                    replacement.createdAt = workspace.knowledgeEntries[existingEntryIndex].createdAt
                    workspace.knowledgeEntries[existingEntryIndex] = replacement
                    updated += 1
                } else {
                    workspace.knowledgeEntries.insert(entry, at: 0)
                    added += 1
                }
            }
        }

        let failed = failureMessage == nil ? result.failures.count : max(result.failures.count, 1)
        let status: ConfluenceSyncStatus = failureMessage == nil && failed == 0 ? .success : .failed
        let message: String
        if let failureMessage {
            message = "钉钉同步失败：\(failureMessage)"
        } else if result.items.isEmpty, failed > 0 {
            message = "钉钉同步失败：\(result.failures.prefix(3).joined(separator: "；"))"
        } else if result.items.isEmpty {
            message = "钉钉同步完成，但没有命中文档。请检查文件夹链接、Space ID、权限或标题过滤。"
        } else if failed > 0 {
            message = "钉钉同步部分完成：读取 \(result.items.count) 个文档，失败 \(failed)，知识库新增 \(added)，更新 \(updated)。\(result.failures.prefix(2).joined(separator: "；"))"
        } else {
            message = "钉钉同步完成：读取 \(result.items.count) 个文档，知识库新增 \(added)，更新 \(updated)"
        }

        workspace.dingtalkDocumentSources[sourceIndex].lastSyncAt = Date()
        workspace.dingtalkDocumentSources[sourceIndex].lastDocumentCount = result.items.count
        workspace.dingtalkDocumentSources[sourceIndex].lastAddedCount = added
        workspace.dingtalkDocumentSources[sourceIndex].lastUpdatedCount = updated
        workspace.dingtalkDocumentSources[sourceIndex].lastFailedCount = failed
        workspace.dingtalkDocumentSources[sourceIndex].lastSkippedCount = result.skippedCount
        workspace.dingtalkDocumentSources[sourceIndex].updatedAt = Date()

        let record = DingTalkDocumentSyncRecord(
            sourceID: source.id,
            businessSpaceID: source.businessSpaceID,
            startedAt: startedAt,
            status: status,
            folderCount: result.folderCount,
            totalDocuments: result.items.count,
            addedKnowledgeEntries: added,
            updatedKnowledgeEntries: updated,
            failedDocuments: failed,
            skippedDocuments: result.skippedCount,
            message: message
        )
        workspace.dingtalkDocumentSyncRecords.insert(record, at: 0)
        workspace.dingtalkDocumentSyncRecords = Array(workspace.dingtalkDocumentSyncRecords.sorted { $0.finishedAt > $1.finishedAt }.prefix(200))
        workspace.dingtalkDocumentItems = Array(workspace.dingtalkDocumentItems.sorted { ($0.updatedAt ?? $0.syncedAt) > ($1.updatedAt ?? $1.syncedAt) }.prefix(1_000))
        workspace.knowledgeEntries.sort {
            ($0.sourceUpdatedAt ?? $0.sourceCreatedAt ?? $0.createdAt) > ($1.sourceUpdatedAt ?? $1.sourceCreatedAt ?? $1.createdAt)
        }
        refreshSelectedPackAfterKnowledgeChange()
        save()
        statusText = automatic ? "18:00 钉钉自动同步完成：\(message)" : message
    }

    private func knowledgeEntry(
        from item: DingTalkDocumentItem,
        source: DingTalkDocumentSource,
        businessSpace: BusinessSpace?
    ) -> KnowledgeEntry {
        KnowledgeEntry(
            id: UUID(),
            createdAt: item.syncedAt,
            businessSpaceID: source.businessSpaceID,
            isGlobal: false,
            scenario: "钉钉文档证据 / \(source.displayName)",
            problem: "\(item.kind.label)：\(item.title)",
            action: "来源文件夹：\(item.folderInput)；内容状态：\(item.contentStatus)；URL：\(item.sourceURL.nilIfBlank ?? "未返回")",
            result: "\(item.summary)\n时间记录：\(item.timingSummary)。注意：钉钉文档创建/更新时间只代表文档记录，不等同真实上线、灰度或业务生效时间。",
            evidenceLevel: item.contentStatus.contains("仅同步元数据") ? .c : .b,
            relatedPackName: businessSpace.map { "\($0.name) · 钉钉文档" } ?? "钉钉文档",
            sourceID: "dingtalk-\(source.id.uuidString)-\(item.itemID)",
            sourceURL: item.sourceURL.nilIfBlank,
            sourceUpdatedAt: item.updatedAt,
            sourceCreatedAt: item.createdAt,
            tags: [
                "钉钉文档证据",
                item.kind.label,
                businessSpace?.name ?? "当前业务空间"
            ].filter { !$0.isEmpty }.uniqued()
        )
    }

    private func mergeLocalKnowledgeFolderSyncResult(
        sourceID: UUID,
        parsedFiles: [LocalKnowledgeParsedFile],
        totalFiles: Int,
        failures: [String],
        startedAt: Date,
        automatic: Bool
    ) {
        guard let sourceIndex = workspace.localKnowledgeFolderSources.firstIndex(where: { $0.id == sourceID }) else { return }
        let source = workspace.localKnowledgeFolderSources[sourceIndex]
        let businessSpace = workspace.businessSpaces.first { $0.id == source.businessSpaceID }
        var added = 0
        var updated = 0

        for parsed in parsedFiles {
            var entry = LocalKnowledgeFolderSyncService.knowledgeEntry(from: parsed, source: source, businessSpace: businessSpace)
            if let existingIndex = workspace.knowledgeEntries.firstIndex(where: { $0.sourceID == entry.sourceID }) {
                entry.id = workspace.knowledgeEntries[existingIndex].id
                entry.createdAt = workspace.knowledgeEntries[existingIndex].createdAt
                workspace.knowledgeEntries[existingIndex] = entry
                updated += 1
            } else {
                workspace.knowledgeEntries.insert(entry, at: 0)
                added += 1
            }
        }

        let failedCount = failures.count
        let supportedCount = parsedFiles.count + failedCount
        let status: ConfluenceSyncStatus = parsedFiles.isEmpty && failedCount > 0 ? .failed : .success
        let message: String
        if parsedFiles.isEmpty, failedCount == 0 {
            message = "未找到可同步文件。支持 csv/xlsx/xls/md/txt/json/pdf/docx。"
        } else if failedCount > 0 {
            message = "已同步 \(parsedFiles.count) 个文件，\(failedCount) 个文件失败。\(failures.prefix(3).joined(separator: "；"))"
        } else {
            message = "已同步 \(parsedFiles.count) 个文件，新增 \(added)，更新 \(updated)"
        }

        workspace.localKnowledgeFolderSources[sourceIndex].lastSyncAt = Date()
        workspace.localKnowledgeFolderSources[sourceIndex].lastFileCount = parsedFiles.count
        workspace.localKnowledgeFolderSources[sourceIndex].lastAddedCount = added
        workspace.localKnowledgeFolderSources[sourceIndex].lastUpdatedCount = updated
        workspace.localKnowledgeFolderSources[sourceIndex].lastFailedCount = failedCount
        workspace.localKnowledgeFolderSources[sourceIndex].updatedAt = Date()

        let record = LocalKnowledgeFolderSyncRecord(
            sourceID: source.id,
            businessSpaceID: source.businessSpaceID,
            startedAt: startedAt,
            status: status,
            totalFiles: totalFiles,
            supportedFiles: supportedCount,
            addedKnowledgeEntries: added,
            updatedKnowledgeEntries: updated,
            failedFiles: failedCount,
            message: message
        )
        workspace.localKnowledgeFolderSyncRecords.insert(record, at: 0)
        workspace.localKnowledgeFolderSyncRecords = Array(workspace.localKnowledgeFolderSyncRecords.sorted { $0.finishedAt > $1.finishedAt }.prefix(200))
        workspace.knowledgeEntries.sort {
            ($0.sourceUpdatedAt ?? $0.sourceCreatedAt ?? $0.createdAt) > ($1.sourceUpdatedAt ?? $1.sourceCreatedAt ?? $1.createdAt)
        }
        refreshSelectedPackAfterKnowledgeChange()
        save()
        statusText = automatic ? "18:00 自动同步完成：\(message)" : message
    }

    private func mergeJiraProjectSyncResult(
        sourceID: UUID,
        evidences: [JiraProjectEvidence],
        startedAt: Date,
        automatic: Bool,
        failureMessage: String?
    ) {
        guard let sourceIndex = workspace.jiraProjectSources.firstIndex(where: { $0.id == sourceID }) else { return }
        let source = workspace.jiraProjectSources[sourceIndex]
        let businessSpace = workspace.businessSpaces.first { $0.id == source.businessSpaceID }

        var added = 0
        var updated = 0

        if failureMessage == nil {
            for evidence in evidences {
                if let existingIndex = workspace.jiraProjectEvidences.firstIndex(where: { $0.sourceID == evidence.sourceID && $0.issueKey == evidence.issueKey }) {
                    var replacement = evidence
                    replacement.id = workspace.jiraProjectEvidences[existingIndex].id
                    workspace.jiraProjectEvidences[existingIndex] = replacement
                } else {
                    workspace.jiraProjectEvidences.insert(evidence, at: 0)
                }

                let entry = knowledgeEntry(from: evidence, source: source, businessSpace: businessSpace)
                if let existingEntryIndex = workspace.knowledgeEntries.firstIndex(where: { $0.sourceID == entry.sourceID }) {
                    var replacement = entry
                    replacement.id = workspace.knowledgeEntries[existingEntryIndex].id
                    replacement.createdAt = workspace.knowledgeEntries[existingEntryIndex].createdAt
                    workspace.knowledgeEntries[existingEntryIndex] = replacement
                    updated += 1
                } else {
                    workspace.knowledgeEntries.insert(entry, at: 0)
                    added += 1
                }
            }
        }

        let failed = failureMessage == nil ? 0 : 1
        let status: ConfluenceSyncStatus = failureMessage == nil ? .success : .failed
        let message: String
        if let failureMessage {
            message = "Jira 同步失败：\(failureMessage)"
        } else if evidences.isEmpty {
            message = "Jira 同步完成，但没有命中 Issue。请检查 Project Key 或 JQL。"
        } else {
            message = "Jira 同步完成：读取 \(evidences.count) 条 Issue，知识库新增 \(added)，更新 \(updated)"
        }

        workspace.jiraProjectSources[sourceIndex].lastSyncAt = Date()
        workspace.jiraProjectSources[sourceIndex].lastIssueCount = evidences.count
        workspace.jiraProjectSources[sourceIndex].lastAddedCount = added
        workspace.jiraProjectSources[sourceIndex].lastUpdatedCount = updated
        workspace.jiraProjectSources[sourceIndex].lastFailedCount = failed
        workspace.jiraProjectSources[sourceIndex].updatedAt = Date()

        let record = JiraProjectSyncRecord(
            sourceID: source.id,
            businessSpaceID: source.businessSpaceID,
            startedAt: startedAt,
            status: status,
            totalIssues: evidences.count,
            addedKnowledgeEntries: added,
            updatedKnowledgeEntries: updated,
            failedIssues: failed,
            message: message
        )
        workspace.jiraProjectSyncRecords.insert(record, at: 0)
        workspace.jiraProjectSyncRecords = Array(workspace.jiraProjectSyncRecords.sorted { $0.finishedAt > $1.finishedAt }.prefix(200))
        workspace.jiraProjectEvidences = Array(workspace.jiraProjectEvidences.sorted { ($0.updatedAt ?? $0.statusChangedAt ?? $0.syncedAt) > ($1.updatedAt ?? $1.statusChangedAt ?? $1.syncedAt) }.prefix(1_000))
        workspace.knowledgeEntries.sort {
            ($0.sourceUpdatedAt ?? $0.sourceCreatedAt ?? $0.createdAt) > ($1.sourceUpdatedAt ?? $1.sourceCreatedAt ?? $1.createdAt)
        }
        refreshSelectedPackAfterKnowledgeChange()
        save()
        statusText = automatic ? "18:00 Jira 自动同步完成：\(message)" : message
    }

    private func knowledgeEntry(
        from evidence: JiraProjectEvidence,
        source: JiraProjectSource,
        businessSpace: BusinessSpace?
    ) -> KnowledgeEntry {
        let timing = evidence.timingSummary
        let versions = evidence.fixVersions.isEmpty ? "未记录" : evidence.fixVersions.joined(separator: "、")
        let sprints = evidence.sprintNames.isEmpty ? "未记录" : evidence.sprintNames.joined(separator: "、")
        return KnowledgeEntry(
            id: UUID(),
            createdAt: evidence.syncedAt,
            businessSpaceID: source.businessSpaceID,
            isGlobal: false,
            scenario: "Jira 项目证据 / \(source.projectKey)",
            problem: "\(evidence.issueKey) \(evidence.issueType)：\(evidence.summary)",
            action: "状态：\(evidence.status)；负责人：\(evidence.assignee.nilIfBlank ?? "未分配")；优先级：\(evidence.priority.nilIfBlank ?? "未记录")；Fix Version：\(versions)；Sprint：\(sprints)",
            result: "时间记录：\(timing)。注意：Jira 创建/更新时间、状态流转和解决时间只代表项目管理记录，不等同真实上线或业务结果。\(evidence.changelogSummary.nilIfBlank.map { "状态流转：\($0)。" } ?? "")\(evidence.commentSummary.nilIfBlank.map { "评论摘要：\($0)" } ?? "")",
            evidenceLevel: .c,
            relatedPackName: businessSpace.map { "\($0.name) · Jira 项目状态" } ?? "Jira 项目状态",
            sourceID: "jira-\(source.id.uuidString)-\(evidence.issueKey)",
            sourceURL: evidence.issueURL,
            sourceUpdatedAt: evidence.updatedAt ?? evidence.statusChangedAt,
            sourceCreatedAt: evidence.createdAt,
            tags: ([
                "Jira 项目证据",
                source.projectKey,
                evidence.issueType,
                evidence.status
            ] + evidence.labels + evidence.components).filter { !$0.isEmpty }.uniqued()
        )
    }
}
