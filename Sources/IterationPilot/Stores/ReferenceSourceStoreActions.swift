import Foundation

@MainActor
extension ProductWorkflowStore {
    func normalizeExistingReferenceSourcesForTavilyCountry(silent: Bool = true) {
        var changed = false
        var fixedCount = 0
        workspace.referenceSources = workspace.referenceSources.map { source in
            let normalized = TavilyCountryResolver.normalizedSource(source)
            if normalized != source {
                changed = true
                fixedCount += 1
            }
            return normalized
        }
        guard changed else { return }
        save()
        if !silent {
            statusText = "已修复 \(fixedCount) 个历史数据源的 Tavily country/query 配置"
        }
    }

    func recommendReferenceSourcesForSelectedBusinessSpace() {
        guard let space = selectedBusinessSpace else {
            statusText = "请先选择业务空间"
            return
        }
        let candidates = BusinessSpaceAIService.localReferenceSourceCandidates(for: space)
        let result = mergeReferenceSources(candidates)
        if let index = workspace.businessSpaces.firstIndex(where: { $0.id == space.id }) {
            workspace.businessSpaces[index].recommendedSourceCategories = candidates.map(\.domain).map { domain in
                switch domain {
                case .competitor: return .marketing
                case .policy: return .policy
                case .market: return .market
                case .externalEvent: return .other
                case .manual: return .other
                }
            }.uniqued()
            workspace.businessSpaces[index].updatedAt = Date()
        }
        save()
        statusText = hasConfiguredAI
            ? "已先生成 \(result.added) 个 RivalRadar 风格基础候选源，正在让 AI 补充竞品、新闻、官方数据和社媒来源..."
            : "已生成 \(result.added) 个 RivalRadar 风格候选数据源，更新 \(result.updated) 个。候选源不会自动启用，请测试此源或手动启用"

        guard hasConfiguredAI else { return }
        enqueuePersistentAIJob(
            kind: .referenceSourceRecommendation,
            payload: PersistentAIJobPayload(
                prompt: BusinessSpaceAIService.referenceSourceRecommendationPrompt(space: space),
                businessSpaceID: space.id,
                targetName: space.name
            )
        )
        statusText = "已生成 \(result.added) 个基础候选源，AI 补充推荐已进入任务队列"
    }

    func enableReferenceSource(_ source: ExternalReferenceSource) {
        guard let index = workspace.referenceSources.firstIndex(where: { $0.id == source.id }) else { return }
        workspace.referenceSources[index].enabled = true
        workspace.referenceSources[index].lifecycleStatus = .enabled
        save()
        statusText = "已启用数据源：\(source.name)"
    }

    func ignoreReferenceSource(_ source: ExternalReferenceSource) {
        guard let index = workspace.referenceSources.firstIndex(where: { $0.id == source.id }) else { return }
        workspace.referenceSources[index].enabled = false
        workspace.referenceSources[index].lifecycleStatus = .ignored
        save()
        statusText = "已忽略候选数据源：\(source.name)"
    }

    func markReferenceSourceTested(_ source: ExternalReferenceSource) {
        guard let index = workspace.referenceSources.firstIndex(where: { $0.id == source.id }) else { return }
        workspace.referenceSources[index].lifecycleStatus = .tested
        save()
        statusText = "已完成测试：\(source.name)"
    }

    func sourceBelongsToCurrentBusinessSpace(_ source: ExternalReferenceSource) -> Bool {
        source.isBound(to: selectedBusinessSpace?.id)
    }

    func sourceIsExplicitGlobal(_ source: ExternalReferenceSource) -> Bool {
        source.isGlobal
    }

    func sourceIsUnbound(_ source: ExternalReferenceSource) -> Bool {
        source.isUnbound
    }

    func sourceIsVisibleInCurrentBusinessSpace(_ source: ExternalReferenceSource) -> Bool {
        source.isVisible(in: selectedBusinessSpace?.id)
    }

    func bindReferenceSourceToCurrentBusinessSpace(_ source: ExternalReferenceSource) {
        guard let spaceID = selectedBusinessSpace?.id,
              let index = workspace.referenceSources.firstIndex(where: { $0.id == source.id }) else { return }
        workspace.referenceSources[index].isGlobal = false
        if !workspace.referenceSources[index].businessSpaceIDs.contains(spaceID) {
            workspace.referenceSources[index].businessSpaceIDs.append(spaceID)
        }
        save()
        statusText = "已将数据源绑定到当前业务空间：\(source.name)"
    }

    func markReferenceSourceAsGlobal(_ source: ExternalReferenceSource) {
        guard let index = workspace.referenceSources.firstIndex(where: { $0.id == source.id }) else { return }
        workspace.referenceSources[index].isGlobal = true
        save()
        statusText = "已标记为全局数据源：\(source.name)"
    }

    func bindGlobalReferenceSourceToCurrentBusinessSpace(_ source: ExternalReferenceSource) {
        guard let spaceID = selectedBusinessSpace?.id,
              let index = workspace.referenceSources.firstIndex(where: { $0.id == source.id }) else { return }
        workspace.referenceSources[index].isGlobal = false
        workspace.referenceSources[index].businessSpaceIDs = [spaceID]
        save()
        statusText = "已取消全局，并绑定到当前业务空间：\(source.name)"
    }

    func removeReferenceSourceFromCurrentBusinessSpace(_ source: ExternalReferenceSource) {
        guard let spaceID = selectedBusinessSpace?.id,
              let index = workspace.referenceSources.firstIndex(where: { $0.id == source.id }) else { return }
        workspace.referenceSources[index].businessSpaceIDs.removeAll { $0 == spaceID }
        save()
        statusText = workspace.referenceSources[index].isUnbound
            ? "已从当前业务空间移除，数据源进入未绑定：\(source.name)"
            : "已从当前业务空间移除数据源：\(source.name)"
    }

    func testCollectReferenceSource(_ source: ExternalReferenceSource) {
        guard workspace.referenceSources.contains(where: { $0.id == source.id }) else { return }
        if let issue = ReferenceSourceHealthEvaluator.configurationIssue(for: source, searchSettings: workspace.searchSettings) {
            statusText = "无法测试此源：\(issue.detail)"
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let succeeded = await self.collectReferenceSources(
                sources: [source],
                autoRecompute: false,
                silent: false,
                evidenceWindow: nil,
                trigger: .singleSourceTest
            )
            if succeeded {
                self.markReferenceSourceTested(source)
            }
        }
    }

    func addReferenceSource(domain: ExternalReferenceDomain = .competitor) {
        _ = createReferenceSource(ReferenceSourceDraft(domain: domain))
    }

    @discardableResult
    func createReferenceSource(_ draft: ReferenceSourceDraft) -> UUID {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = ExternalReferenceSource(
            id: UUID(),
            businessSpaceIDs: selectedBusinessSpace.map { [$0.id] } ?? [],
            businessDomainIDs: selectedBusinessSpace?.domains.map(\.id) ?? [],
            lifecycleStatus: .enabled,
            name: trimmedName.isEmpty ? ReferenceSourceDraft.defaultName(for: draft.domain) : trimmedName,
            domain: draft.domain,
            collectorType: draft.collectorType,
            url: draft.url.trimmingCharacters(in: .whitespacesAndNewlines),
            keywordsText: draft.keywordsText.trimmingCharacters(in: .whitespacesAndNewlines),
            queryTemplate: draft.queryTemplate.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: "",
            competitorName: draft.domain == .competitor ? trimmedName : "",
            enabled: true,
            manualNote: draft.manualNote.trimmingCharacters(in: .whitespacesAndNewlines),
            lastFetchedAt: nil
        )
        workspace.referenceSources.insert(source, at: 0)
        statusText = "已新增并启用 \(source.name)，可点击测试此源或采集已启用源"
        save()
        return source.id
    }

    func deleteReferenceSource(_ source: ExternalReferenceSource) {
        workspace.referenceSources.removeAll { $0.id == source.id }
        workspace.referenceItems.removeAll { $0.sourceID == source.id }
        save()
    }

    func updateReferenceSource(_ source: ExternalReferenceSource) {
        guard let index = workspace.referenceSources.firstIndex(where: { $0.id == source.id }) else { return }
        workspace.referenceSources[index] = TavilyCountryResolver.normalizedSource(source)
        save(policy: .deferred)
    }

    func collectReferenceSources() {
        collectReferenceSources(autoRecompute: true, silent: false)
    }

    func collectReferenceSources(
        autoRecompute: Bool,
        silent: Bool,
        evidenceWindow: ExternalEvidenceWindow? = nil,
        trigger: ExternalReferenceCollectionTrigger? = nil
    ) {
        guard !isCollectingReferences else {
            if !silent {
                statusText = "参照数据正在采集中"
            }
            return
        }
        recoverInterruptedReferenceCollectionRuns()
        let sources = enabledReferenceSourcesForCurrentSpace()
        guard !sources.isEmpty else {
            if !silent {
                statusText = skippedEnabledReferenceSourceSummaryForCurrentSpace()
            }
            return
        }

        Task { [weak self] in
            guard let self else { return }
            await self.collectReferenceSources(
                sources: sources,
                autoRecompute: autoRecompute,
                silent: silent,
                evidenceWindow: evidenceWindow,
                trigger: trigger ?? (silent ? .backgroundRefresh : .manual)
            )
        }
    }

    func enabledReferenceSourcesForCurrentSpace() -> [ExternalReferenceSource] {
        return workspace.referenceSources.filter { source in
            source.enabled &&
                source.lifecycleStatus != .ignored &&
                sourceIsVisibleInCurrentBusinessSpace(source) &&
                ReferenceSourceHealthEvaluator.evaluate(
                    source: source,
                    searchSettings: workspace.searchSettings,
                    collectionRuns: workspace.referenceCollectionRuns
                ).isCollectable
        }
    }

    func collectableReferenceSourcesForCurrentSpace() -> [ExternalReferenceSource] {
        enabledReferenceSourcesForCurrentSpace()
    }

    func analysisBackgroundReferenceSources(
        from sources: [ExternalReferenceSource],
        limit: Int = 12
    ) -> [ExternalReferenceSource] {
        guard sources.count > limit else { return sources }
        let priorities: [(ExternalReferenceDomain, Int)] = [
            (.externalEvent, 4),
            (.competitor, 4),
            (.policy, 3),
            (.market, 2),
            (.manual, 2)
        ]
        var selected: [ExternalReferenceSource] = []
        var selectedIDs = Set<UUID>()

        func append(_ source: ExternalReferenceSource) {
            guard selected.count < limit, !selectedIDs.contains(source.id) else { return }
            selected.append(source)
            selectedIDs.insert(source.id)
        }

        for (domain, domainLimit) in priorities {
            for source in sources.filter({ $0.domain == domain }).prefix(domainLimit) {
                append(source)
            }
        }
        for source in sources {
            append(source)
        }
        return selected
    }

    @discardableResult
    func startBackgroundReferenceCollectionForAnalysis(
        sources: [ExternalReferenceSource],
        evidenceWindow: ExternalEvidenceWindow,
        trigger: ExternalReferenceCollectionTrigger,
        sessionID: UUID,
        packID: UUID,
        taskID: UUID?,
        contextMode: AnalysisContextMode,
        jobID: UUID
    ) -> (started: Bool, selectedCount: Int, skippedCount: Int) {
        guard !sources.isEmpty else { return (false, 0, 0) }
        guard !isCollectingReferences else {
            updatePersistentAIJob(jobID, saveImmediately: false) { job in
                job.logs.append(AIReasoningLogEntry(
                    step: "外部采集使用缓存",
                    status: .requesting,
                    detail: "已有外部采集任务正在运行，本轮 AI 先使用已有缓存和表格事实分析。"
                ))
            }
            return (false, 0, sources.count)
        }
        let selectedSources = analysisBackgroundReferenceSources(from: sources)
        let skippedCount = max(sources.count - selectedSources.count, 0)
        updatePersistentAIJob(jobID, saveImmediately: false) { job in
            job.logs.append(AIReasoningLogEntry(
                step: "外部采集转入后台",
                status: .requesting,
                detail: "本轮选择 \(selectedSources.count) 个高优先级外部源后台采集，跳过 \(skippedCount) 个低优先级源；AI 会先基于表格、知识库和已有缓存分析。分析周期：\(evidenceWindow.summary)"
            ))
        }
        Task { [weak self] in
            guard let self else { return }
            await self.collectReferenceSources(
                sources: selectedSources,
                autoRecompute: false,
                silent: true,
                evidenceWindow: evidenceWindow,
                trigger: trigger,
                sessionID: sessionID,
                packID: packID,
                taskID: taskID,
                contextMode: contextMode
            )
        }
        return (true, selectedSources.count, skippedCount)
    }

    func skippedEnabledReferenceSourceSummaryForCurrentSpace() -> String {
        let scopedEnabledSources = workspace.referenceSources.filter { source in
            source.enabled &&
                source.lifecycleStatus != .ignored &&
                sourceIsVisibleInCurrentBusinessSpace(source)
        }
        guard !scopedEnabledSources.isEmpty else {
            return "没有启用的参照数据源"
        }
        let reasons = scopedEnabledSources.compactMap { source -> String? in
            let health = ReferenceSourceHealthEvaluator.evaluate(
                source: source,
                searchSettings: workspace.searchSettings,
                collectionRuns: workspace.referenceCollectionRuns
            )
            guard !health.isCollectable else { return nil }
            return "\(source.name)：\(health.status.label)"
        }
        guard !reasons.isEmpty else {
            return "没有可采集的已启用参照数据源"
        }
        return "没有可采集的已启用参照数据源。\(reasons.prefix(5).joined(separator: "；"))"
    }

    @discardableResult
    func collectReferenceSources(
        sources: [ExternalReferenceSource],
        autoRecompute: Bool,
        silent: Bool,
        evidenceWindow: ExternalEvidenceWindow? = nil,
        trigger: ExternalReferenceCollectionTrigger = .manual,
        sessionID: UUID? = nil,
        packID: UUID? = nil,
        taskID: UUID? = nil,
        contextMode: AnalysisContextMode? = nil,
        timeBudget: TimeInterval = NetworkTimeouts.referenceCollectionRunBudget
    ) async -> Bool {
        guard !isCollectingReferences else {
            if !silent {
                statusText = "参照数据正在采集中"
            }
            return false
        }
        recoverInterruptedReferenceCollectionRuns()
        isCollectingReferences = true
        let runID = createReferenceCollectionRun(
            trigger: trigger,
            sources: sources,
            evidenceWindow: evidenceWindow,
            sessionID: sessionID,
            packID: packID,
            taskID: taskID,
            contextMode: contextMode,
            timeBudget: timeBudget
        )
        currentReferenceCollectionRunID = runID
        cancelledReferenceCollectionRunIDs.remove(runID)
        let deadline = Date().addingTimeInterval(timeBudget)
        let windowText = evidenceWindow.map { "（按分析周期：\($0.summary)）" } ?? ""
        statusText = silent ? "正在后台刷新竞品/舆情/政策/市场参照\(windowText)..." : "正在采集竞品/政策参照数据\(windowText)..."
        defer {
            if currentReferenceCollectionRunID == runID {
                currentReferenceCollectionRunID = nil
            }
            isCollectingReferences = false
        }

        do {
            updateReferenceCollectionRunPhase(runID, phase: "正在请求外部源 0/\(sources.count)", completedSourceCount: 0)
            let collectionResult = try await ExternalReferenceCollector().collectDetailed(
                sources: sources,
                searchSettings: workspace.searchSettings,
                evidenceWindow: evidenceWindow,
                collectionRunID: runID,
                deadline: deadline
            )
            guard !isReferenceCollectionCancelled(runID) else { return false }
            let rawItems = collectionResult.items
            updateReferenceCollectionRunPhase(
                runID,
                phase: "正在分析情报 0/\(min(rawItems.count, NetworkTimeouts.maxReferenceIntelligenceItemsPerRun))",
                completedSourceCount: collectionResult.sourceLogs.count
            )
            let pipelineResult = await processReferenceIntelligence(
                rawItems,
                sources: sources,
                deadline: deadline,
                maxAIItems: NetworkTimeouts.maxReferenceIntelligenceItemsPerRun,
                runID: runID
            )
            guard !isReferenceCollectionCancelled(runID) else { return false }
            updateReferenceCollectionRunPhase(
                runID,
                phase: "正在去重和沉淀",
                completedSourceCount: collectionResult.sourceLogs.count,
                analyzedItemCount: pipelineResult.analyzedItemCount,
                pendingItemCount: pipelineResult.pendingItemCount
            )
            let sedimentedItems = upsertReferenceKnowledgeEntries(for: pipelineResult.items)
            let successfulSourceIDs = Set(collectionResult.sourceLogs.compactMap { log -> UUID? in
                log.status == .succeeded ? log.sourceID : nil
            })
            let mergeResult = mergeReferenceItems(sedimentedItems, fetchedSourceIDs: successfulSourceIDs)
            let didTimeOut = Date() >= deadline || pipelineResult.timedOut
            finishReferenceCollectionRun(
                runID,
                sourceLogs: finalizedSourceLogs(collectionResult.sourceLogs, acceptedItems: pipelineResult.items, sedimentedItems: sedimentedItems),
                rawItemCount: rawItems.count,
                insertedItemCount: mergeResult.inserted,
                duplicateItemCount: pipelineResult.duplicateCount,
                irrelevantItemCount: pipelineResult.irrelevantCount,
                knowledgeEntryCount: sedimentedItems.filter { $0.knowledgeEntryID != nil }.count,
                errorMessage: didTimeOut ? "采集达到本轮时间预算，已使用已完成证据继续。" : "",
                timedOut: didTimeOut,
                analyzedItemCount: pipelineResult.analyzedItemCount,
                pendingItemCount: pipelineResult.pendingItemCount
            )
            if autoRecompute {
                if analysisBlockerText(for: selectedPack) == nil {
                    await runExternalEventImpactAnalysisForSelectedPack()
                    recomputeSelectedPackIgnoringSemanticGate(
                        status: "已采集 \(rawItems.count) 条，新增 \(sedimentedItems.count) 条情报，去重 \(pipelineResult.duplicateCount) 条，过滤无关 \(pipelineResult.irrelevantCount) 条，并重新生成多源分析"
                    )
                } else {
                    statusText = "已采集 \(rawItems.count) 条，新增 \(sedimentedItems.count) 条情报；当前分析资料仍需先完成导入审核"
                }
            } else {
                statusText = "已采集 \(rawItems.count) 条，新增 \(sedimentedItems.count) 条情报，去重 \(pipelineResult.duplicateCount) 条，过滤无关 \(pipelineResult.irrelevantCount) 条"
            }
            return true
        } catch {
            failReferenceCollectionRun(runID, error: error)
            statusText = silent ? "后台刷新参照数据失败：\(error.localizedDescription)" : error.localizedDescription
            return false
        }
    }

    func refreshReferenceSourcesForAnalysisIfPossible() {
        guard shouldAutoRefreshReferenceSources() else { return }
        collectReferenceSources(autoRecompute: true, silent: true)
    }

    func shouldAutoRefreshReferenceSources() -> Bool {
        guard !isCollectingReferences else { return false }
        let enabledSources = enabledReferenceSourcesForCurrentSpace()
        guard !enabledSources.isEmpty else { return false }
        if workspace.referenceItems.isEmpty { return true }
        let staleBoundary = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        return enabledSources.contains { source in
            guard let lastFetchedAt = source.lastFetchedAt else { return true }
            return lastFetchedAt < staleBoundary
        }
    }

    func importRivalRadarReferenceSources(silent: Bool = false) {
        do {
            let result = try RivalRadarImportService().load()
            let mergeResult = mergeReferenceSources(bindImportedReferenceSources(result.sources))
            if workspace.searchSettings.tavilyAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let tavilyAPIKey = result.tavilyAPIKey {
                workspace.searchSettings.tavilyAPIKey = tavilyAPIKey
            }
            workspace.searchSettings.didImportRivalRadarSources = true
            save()
            if !silent {
                statusText = "已从竞品雷达导入 \(mergeResult.added) 个新数据源，更新 \(mergeResult.updated) 个"
            }
        } catch {
            if !silent {
                statusText = error.localizedDescription
            }
        }
    }

    func importMexicoEventReferenceSourcesIfNeeded(silent: Bool = false) {
        guard !workspace.searchSettings.didImportMexicoEventSources else { return }
        let mergeResult = mergeReferenceSources(bindImportedReferenceSources(ExternalReferenceSource.mexicoEventDefaults))
        workspace.searchSettings.didImportMexicoEventSources = true
        save()
        if !silent {
            statusText = "已导入墨西哥事件源 \(mergeResult.added) 个，更新 \(mergeResult.updated) 个"
        }
    }

    func importMexicoUtilityReferenceSourcesIfNeeded(silent: Bool = false) {
        guard !workspace.searchSettings.didImportMexicoUtilitySources else { return }
        let mergeResult = mergeReferenceSources(bindImportedReferenceSources(ExternalReferenceSource.mexicoUtilityTavilyDefaults))
        workspace.searchSettings.didImportMexicoUtilitySources = true
        save()
        if !silent {
            statusText = "已导入墨西哥 CFE/天气/用电候选源 \(mergeResult.added) 个，更新 \(mergeResult.updated) 个"
        }
    }

    func bindImportedReferenceSources(_ sources: [ExternalReferenceSource]) -> [ExternalReferenceSource] {
        guard let space = selectedBusinessSpace else { return sources }
        return sources.map { source in
            guard !source.isGlobal, source.businessSpaceIDs.isEmpty else { return source }
            var copy = source
            copy.businessSpaceIDs = [space.id]
            copy.businessDomainIDs = space.domains.map(\.id)
            return copy
        }
    }

    @discardableResult
    func mergeReferenceItems(_ items: [ExternalReferenceItem], fetchedSourceIDs: Set<UUID> = []) -> (inserted: Int, updated: Int) {
        var existing = workspace.referenceItems
        let sourceByID = Dictionary(uniqueKeysWithValues: workspace.referenceSources.map { ($0.id, $0) })
        var inserted = 0
        var updated = 0
        for item in items {
            if let index = existing.firstIndex(where: {
                referenceItemsShareScope($0, item, sourceByID: sourceByID) &&
                    ((!item.urlHash.isEmpty && $0.urlHash == item.urlHash) ||
                    (!item.normalizedURL.isEmpty && $0.normalizedURL == item.normalizedURL) ||
                    (!$0.url.isEmpty && $0.url == item.url))
            }) {
                existing[index] = item
                updated += 1
            } else {
                existing.append(item)
                inserted += 1
            }
        }
        workspace.referenceItems = existing.sorted { $0.displayDate > $1.displayDate }
        let now = Date()
        for sourceID in fetchedSourceIDs {
            if let index = workspace.referenceSources.firstIndex(where: { $0.id == sourceID }) {
                workspace.referenceSources[index].lastFetchedAt = now
            }
        }
        save()
        return (inserted, updated)
    }

    func createReferenceCollectionRun(
        trigger: ExternalReferenceCollectionTrigger,
        sources: [ExternalReferenceSource],
        evidenceWindow: ExternalEvidenceWindow?,
        sessionID: UUID?,
        packID: UUID?,
        taskID: UUID?,
        contextMode: AnalysisContextMode?,
        timeBudget: TimeInterval = NetworkTimeouts.referenceCollectionRunBudget
    ) -> UUID {
        let resolvedPackID = packID ?? selectedPack?.id
        let resolvedTaskID = taskID ?? selectedPack.flatMap { currentAnalysisTask(in: $0)?.id }
        let run = ExternalReferenceCollectionRun(
            trigger: trigger,
            businessSpaceID: selectedBusinessSpace?.id ?? workspace.selectedBusinessSpaceID,
            packID: resolvedPackID,
            taskID: resolvedTaskID,
            sessionID: sessionID,
            contextMode: contextMode,
            evidenceWindow: evidenceWindow,
            sourceLogs: sources.map { source in
                ExternalReferenceSourceRunLog(
                    sourceID: source.id,
                    sourceName: source.name,
                    collectorType: source.collectorType,
                    domain: source.domain,
                    sourceProfile: source.tavilySourceProfile,
                    queryGroup: source.tavilyQueryGroup,
                    renderedQuery: source.queryTemplate.nilIfBlank ?? source.keywordsText,
                    endpoint: source.url.nilIfBlank ?? workspace.searchSettings.tavilyEndpoint,
                    tavilyTopic: source.tavilyTopic,
                    tavilySearchDepth: source.tavilySearchDepth,
                    tavilyTimeRange: source.tavilyTimeRange,
                    tavilyMaxResults: source.tavilyMaxResults,
                    startedAt: Date(),
                    status: .running
                )
            },
            enabledSourceCount: sources.count,
            timeBudgetSeconds: Int(timeBudget),
            timedOut: false,
            cancelledByUser: false,
            phase: "准备数据源",
            completedSourceCount: 0,
            analyzedItemCount: 0,
            pendingItemCount: 0
        )
        workspace.referenceCollectionRuns.insert(run, at: 0)
        trimReferenceCollectionRuns()
        save()
        return run.id
    }

    func recoverInterruptedReferenceCollectionRuns() {
        var changed = false
        let now = Date()
        for index in workspace.referenceCollectionRuns.indices where workspace.referenceCollectionRuns[index].status == .running {
            workspace.referenceCollectionRuns[index].status = .cancelled
            workspace.referenceCollectionRuns[index].endedAt = now
            workspace.referenceCollectionRuns[index].errorMessage = "App 上次退出、重启或采集任务中断，已停止旧采集状态。"
            changed = true
        }
        if changed {
            trimReferenceCollectionRuns()
            save()
        }
    }

    func cancelReferenceCollection() {
        guard let runID = currentReferenceCollectionRunID,
              let index = workspace.referenceCollectionRuns.firstIndex(where: { $0.id == runID }) else {
            statusText = "当前没有正在运行的采集任务"
            return
        }
        cancelledReferenceCollectionRunIDs.insert(runID)
        workspace.referenceCollectionRuns[index].status = .cancelled
        workspace.referenceCollectionRuns[index].endedAt = Date()
        workspace.referenceCollectionRuns[index].cancelledByUser = true
        workspace.referenceCollectionRuns[index].phase = "用户已停止采集"
        workspace.referenceCollectionRuns[index].errorMessage = "用户手动停止采集；已完成的情报会保留，未完成源不会继续进入本轮分析。"
        workspace.referenceCollectionRuns[index].sourceLogs = workspace.referenceCollectionRuns[index].sourceLogs.map { log in
            guard log.status == .running else { return log }
            var copy = log
            copy.status = .cancelled
            copy.endedAt = Date()
            copy.cancellationReason = "用户手动停止采集"
            copy.errorMessage = "用户手动停止采集"
            return copy
        }
        isCollectingReferences = false
        currentReferenceCollectionRunID = nil
        save()
        statusText = "已停止外部采集；已完成情报仍会保留"
    }

    func isReferenceCollectionCancelled(_ runID: UUID) -> Bool {
        cancelledReferenceCollectionRunIDs.contains(runID) ||
            workspace.referenceCollectionRuns.first(where: { $0.id == runID })?.status == .cancelled
    }

    func updateReferenceCollectionRunPhase(
        _ runID: UUID,
        phase: String,
        completedSourceCount: Int? = nil,
        analyzedItemCount: Int? = nil,
        pendingItemCount: Int? = nil
    ) {
        guard let index = workspace.referenceCollectionRuns.firstIndex(where: { $0.id == runID }) else { return }
        workspace.referenceCollectionRuns[index].phase = phase
        if let completedSourceCount {
            workspace.referenceCollectionRuns[index].completedSourceCount = completedSourceCount
        }
        if let analyzedItemCount {
            workspace.referenceCollectionRuns[index].analyzedItemCount = analyzedItemCount
        }
        if let pendingItemCount {
            workspace.referenceCollectionRuns[index].pendingItemCount = pendingItemCount
        }
        save(policy: .deferred)
    }

    func finalizedSourceLogs(
        _ logs: [ExternalReferenceSourceRunLog],
        acceptedItems: [ExternalReferenceItem],
        sedimentedItems: [ExternalReferenceItem]
    ) -> [ExternalReferenceSourceRunLog] {
        let acceptedByLog = Dictionary(grouping: acceptedItems, by: \.sourceRunLogID)
        let sedimentedByLog = Dictionary(grouping: sedimentedItems, by: \.sourceRunLogID)
        return logs.map { log in
            var copy = log
            let accepted = acceptedByLog[Optional(log.id)] ?? []
            let sedimented = sedimentedByLog[Optional(log.id)] ?? []
            copy.validItemCount = accepted.count
            copy.insertedItemCount = sedimented.count
            copy.knowledgeEntryCount = sedimented.filter { $0.knowledgeEntryID != nil }.count
            return copy
        }
    }

    func finishReferenceCollectionRun(
        _ runID: UUID,
        sourceLogs: [ExternalReferenceSourceRunLog],
        rawItemCount: Int,
        insertedItemCount: Int,
        duplicateItemCount: Int,
        irrelevantItemCount: Int,
        knowledgeEntryCount: Int,
        errorMessage: String,
        timedOut: Bool = false,
        analyzedItemCount: Int? = nil,
        pendingItemCount: Int? = nil
    ) {
        guard let index = workspace.referenceCollectionRuns.firstIndex(where: { $0.id == runID }) else { return }
        let successful = sourceLogs.filter { $0.status == .succeeded }.count
        let failed = sourceLogs.filter { $0.status == .failed }.count
        workspace.referenceCollectionRuns[index].status = timedOut ? .partialFailed : (failed == 0 ? .succeeded : (successful > 0 ? .partialFailed : .failed))
        workspace.referenceCollectionRuns[index].endedAt = Date()
        workspace.referenceCollectionRuns[index].sourceLogs = sourceLogs
        workspace.referenceCollectionRuns[index].successfulSourceCount = successful
        workspace.referenceCollectionRuns[index].failedSourceCount = failed
        workspace.referenceCollectionRuns[index].completedSourceCount = sourceLogs.count
        workspace.referenceCollectionRuns[index].rawItemCount = rawItemCount
        workspace.referenceCollectionRuns[index].insertedItemCount = insertedItemCount
        workspace.referenceCollectionRuns[index].duplicateItemCount = duplicateItemCount
        workspace.referenceCollectionRuns[index].irrelevantItemCount = irrelevantItemCount
        workspace.referenceCollectionRuns[index].knowledgeEntryCount = knowledgeEntryCount
        workspace.referenceCollectionRuns[index].errorMessage = errorMessage
        workspace.referenceCollectionRuns[index].timedOut = timedOut
        workspace.referenceCollectionRuns[index].phase = timedOut ? "已超时，使用已完成证据继续分析" : "采集完成"
        workspace.referenceCollectionRuns[index].analyzedItemCount = analyzedItemCount
        workspace.referenceCollectionRuns[index].pendingItemCount = pendingItemCount
        trimReferenceCollectionRuns()
        save()
    }

    func failReferenceCollectionRun(_ runID: UUID, error: Error) {
        guard let index = workspace.referenceCollectionRuns.firstIndex(where: { $0.id == runID }) else { return }
        workspace.referenceCollectionRuns[index].status = .failed
        workspace.referenceCollectionRuns[index].endedAt = Date()
        workspace.referenceCollectionRuns[index].errorMessage = error.localizedDescription
        trimReferenceCollectionRuns()
        save()
    }

    func trimReferenceCollectionRuns() {
        let sourceLogLimitPerRun = 60
        let textLimit = 1_200
        workspace.referenceCollectionRuns = Array(workspace.referenceCollectionRuns.sorted { $0.startedAt > $1.startedAt }.prefix(120))
        for runIndex in workspace.referenceCollectionRuns.indices {
            if workspace.referenceCollectionRuns[runIndex].sourceLogs.count > sourceLogLimitPerRun {
                workspace.referenceCollectionRuns[runIndex].sourceLogs = Array(workspace.referenceCollectionRuns[runIndex].sourceLogs.prefix(sourceLogLimitPerRun))
            }
            for logIndex in workspace.referenceCollectionRuns[runIndex].sourceLogs.indices {
                if workspace.referenceCollectionRuns[runIndex].sourceLogs[logIndex].errorMessage.count > textLimit {
                    workspace.referenceCollectionRuns[runIndex].sourceLogs[logIndex].errorMessage = String(workspace.referenceCollectionRuns[runIndex].sourceLogs[logIndex].errorMessage.prefix(textLimit))
                }
                if workspace.referenceCollectionRuns[runIndex].sourceLogs[logIndex].renderedQuery.count > textLimit {
                    workspace.referenceCollectionRuns[runIndex].sourceLogs[logIndex].renderedQuery = String(workspace.referenceCollectionRuns[runIndex].sourceLogs[logIndex].renderedQuery.prefix(textLimit))
                }
            }
        }
    }

    func processReferenceIntelligence(
        _ rawItems: [ExternalReferenceItem],
        sources: [ExternalReferenceSource],
        deadline: Date? = nil,
        maxAIItems: Int = NetworkTimeouts.maxReferenceIntelligenceItemsPerRun,
        runID: UUID? = nil
    ) async -> (items: [ExternalReferenceItem], duplicateCount: Int, irrelevantCount: Int, analyzedItemCount: Int, pendingItemCount: Int, timedOut: Bool) {
        let sourceByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        let analyzer = ReferenceIntelligenceAnalyzer()
        var knownItems = workspace.referenceItems
        var accepted: [ExternalReferenceItem] = []
        var duplicateCount = 0
        var irrelevantCount = 0
        var analyzedItemCount = 0
        var pendingItemCount = 0
        var timedOut = false

        for rawItem in rawItems {
            if let runID, isReferenceCollectionCancelled(runID) {
                break
            }
            let source = sourceByID[rawItem.sourceID]
            var item = ReferenceDedupeService.enriched(rawItem, source: source)
            item.businessSpaceID = collectedReferenceBusinessSpaceID(for: source)
            item.businessDomainIDs = source?.businessDomainIDs ?? []
            let comparableItems = (knownItems + accepted).filter {
                referenceItemsShareScope($0, item, sourceByID: sourceByID)
            }
            if ReferenceDedupeService.isDuplicate(item, against: comparableItems) {
                duplicateCount += 1
                continue
            }

            let enoughTimeForAI = deadline.map { Date().addingTimeInterval(NetworkTimeouts.referenceIntelligenceRequest) < $0 } ?? true
            if analyzedItemCount < maxAIItems, enoughTimeForAI {
                let analysis = await analyzer.analyze(
                    item: item,
                    source: source,
                    settings: workspace.aiSettings
                )
                analyzedItemCount += 1
                item.intelligenceCategory = analysis.category
                item.summary = analysis.summary
                item.impact = analysis.impact
                item.importance = analysis.importance
                item.isRelevant = analysis.isRelevant
                item.relevanceReason = analysis.relevanceReason
                if let eventStartedAt = analysis.eventStartedAt {
                    item.eventStartedAt = eventStartedAt
                }
                if let eventEndedAt = analysis.eventEndedAt {
                    item.eventEndedAt = eventEndedAt
                }
                if let dateBasis = analysis.dateBasis {
                    item.dateBasis = dateBasis
                }
                if let dateConfidence = analysis.dateConfidence {
                    item.dateConfidence = min(max(dateConfidence, 0), 1)
                }
                item.analyzedAt = Date()
                item.analysisWarning = analysis.warning
            } else {
                pendingItemCount += 1
                timedOut = timedOut || !enoughTimeForAI
                item.isRelevant = true
                item.importance = min(max(item.importance, 1), 3)
                item.relevanceReason = "超出本轮采集 AI 分析预算，已保留为待复核弱线索"
                item.analysisWarning = "本条情报未做 AI 相关性分析；报告中只能作为弱线索或缓存资料。"
            }

            if item.isRelevant {
                accepted.append(item)
                knownItems.append(item)
            } else {
                irrelevantCount += 1
            }
            if let runID {
                updateReferenceCollectionRunPhase(
                    runID,
                    phase: "正在分析情报 \(analyzedItemCount)/\(min(rawItems.count, maxAIItems))",
                    analyzedItemCount: analyzedItemCount,
                    pendingItemCount: pendingItemCount
                )
            }
        }

        return (accepted, duplicateCount, irrelevantCount, analyzedItemCount, pendingItemCount, timedOut)
    }

    func collectedReferenceBusinessSpaceID(for source: ExternalReferenceSource?) -> UUID? {
        guard let source, !source.isGlobal, !source.isUnbound else { return nil }
        if let selectedID = selectedBusinessSpace?.id, source.businessSpaceIDs.contains(selectedID) {
            return selectedID
        }
        return source.businessSpaceIDs.first
    }

    func referenceItemsShareScope(
        _ lhs: ExternalReferenceItem,
        _ rhs: ExternalReferenceItem,
        sourceByID: [UUID: ExternalReferenceSource]
    ) -> Bool {
        if lhs.sourceID == rhs.sourceID {
            return true
        }
        if let lhsSpace = lhs.businessSpaceID, let rhsSpace = rhs.businessSpaceID {
            return lhsSpace == rhsSpace
        }
        guard lhs.businessSpaceID == nil, rhs.businessSpaceID == nil else {
            return false
        }
        return sourceByID[lhs.sourceID]?.isGlobal == true && sourceByID[rhs.sourceID]?.isGlobal == true
    }

    func upsertReferenceKnowledgeEntries(for items: [ExternalReferenceItem]) -> [ExternalReferenceItem] {
        var updatedItems = items
        let sourceByID = Dictionary(uniqueKeysWithValues: workspace.referenceSources.map { ($0.id, $0) })
        for index in updatedItems.indices where updatedItems[index].isRelevant {
            let item = updatedItems[index]
            let isGlobalReference = sourceByID[item.sourceID]?.isGlobal == true
            let sourceID = referenceKnowledgeSourceID(for: item)
            let existingIndex = workspace.knowledgeEntries.firstIndex { $0.sourceID == sourceID }
            let entryID = existingIndex.map { workspace.knowledgeEntries[$0].id } ?? UUID()
            let entry = KnowledgeEntry(
                id: entryID,
                createdAt: existingIndex.map { workspace.knowledgeEntries[$0].createdAt } ?? Date(),
                businessSpaceID: item.businessSpaceID,
                businessDomainIDs: item.businessDomainIDs,
                isGlobal: isGlobalReference,
                scenario: "\(item.domain.label) · \(item.intelligenceCategory.label)",
                problem: item.title,
                action: item.summary,
                result: item.impact.nilIfBlank ?? "建议作为 AI 分析外部参照，并人工复核影响。",
                evidenceLevel: item.importance >= 4 ? .b : .c,
                relatedPackName: selectedPack?.name ?? "",
                sourceID: sourceID,
                sourceURL: item.url.nilIfBlank,
                sourceUpdatedAt: item.displayDate,
                sourceCreatedAt: item.publishedAt,
                tags: [
                    "情报沉淀",
                    "竞品雷达链路",
                    item.dateBasisLabel,
                    item.domain.label,
                    item.intelligenceCategory.label,
                    item.sourceName
                ] + item.keywords
            )
            if let existingIndex {
                workspace.knowledgeEntries[existingIndex] = entry
            } else {
                workspace.knowledgeEntries.insert(entry, at: 0)
            }
            updatedItems[index].knowledgeEntryID = entry.id
        }
        return updatedItems
    }

    func referenceKnowledgeSourceID(for item: ExternalReferenceItem) -> String {
        let stableKey = item.urlHash.nilIfBlank ?? item.titleHash.nilIfBlank ?? item.id.uuidString
        return "reference-intelligence-\(stableKey)"
    }

    @discardableResult
    func mergeReferenceSources(_ sources: [ExternalReferenceSource]) -> (added: Int, updated: Int) {
        var current = workspace.referenceSources
        var added = 0
        var updated = 0
        for rawSource in sources {
            let source = TavilyCountryResolver.normalizedSource(rawSource)
            let incomingKey = referenceSourceMergeKey(source)
            if let index = current.firstIndex(where: { referenceSourceMergeKey($0) == incomingKey || $0.name.caseInsensitiveCompare(source.name) == .orderedSame }) {
                var copy = source
                copy.id = current[index].id
                copy.lastFetchedAt = current[index].lastFetchedAt
                copy.isGlobal = current[index].isGlobal || source.isGlobal
                copy.businessSpaceIDs = (current[index].businessSpaceIDs + source.businessSpaceIDs).uniqued()
                copy.businessDomainIDs = (current[index].businessDomainIDs + source.businessDomainIDs).uniqued()
                if current[index].enabled || current[index].lifecycleStatus == .enabled {
                    copy.enabled = true
                    copy.lifecycleStatus = .enabled
                } else if current[index].lifecycleStatus == .ignored {
                    copy.enabled = false
                    copy.lifecycleStatus = .ignored
                } else if current[index].lifecycleStatus == .tested {
                    copy.enabled = false
                    copy.lifecycleStatus = .tested
                }
                current[index] = copy
                updated += 1
            } else {
                current.append(source)
                added += 1
            }
        }
        workspace.referenceSources = current.sorted {
            if $0.domain == $1.domain {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.domain.label < $1.domain.label
        }
        return (added, updated)
    }

    func referenceSourceMergeKey(_ source: ExternalReferenceSource) -> String {
        [
            source.name,
            source.domain.rawValue,
            source.tavilyQueryGroup,
            source.tavilySourceProfile,
            source.competitorName,
            source.tavilyIncludeDomainsText,
            source.queryTemplate
        ]
            .joined(separator: "|")
            .normalizedKey
    }
}
