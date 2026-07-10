import AppKit
import Foundation
import UniformTypeIdentifiers

enum WorkspaceSavePolicy {
    case immediate
    case deferred
    case none
}

enum WorkspaceLoadResult {
    case loaded(ProductWorkspace)
    case missing
    case unsupportedVersion(found: Int, supported: Int)
    case credentialUnavailable(String)
    case corrupt(errorDescription: String, backupURL: URL?)
}

private actor WorkspaceDiskWriter {
    private var latestCompletedGeneration = 0
    private var latestSuccessfulGeneration = 0
    private var pendingWorkspace: ProductWorkspace?
    private var pendingGeneration = 0
    private var pendingFailureHandler: (@Sendable (String) -> Void)?
    private var isDraining = false
    private var flushWaiters: [Int: [CheckedContinuation<Bool, Never>]] = [:]

    func save(
        _ workspace: ProductWorkspace,
        generation: Int,
        onFailure: (@Sendable (String) -> Void)? = nil
    ) {
        enqueue(workspace, generation: generation, onFailure: onFailure)
        startDrainingIfNeeded()
    }

    func flush(
        _ workspace: ProductWorkspace,
        generation: Int,
        onFailure: (@Sendable (String) -> Void)? = nil
    ) async -> Bool {
        if generation <= latestCompletedGeneration {
            return generation <= latestSuccessfulGeneration
        }

        return await withCheckedContinuation { continuation in
            flushWaiters[generation, default: []].append(continuation)
            enqueue(workspace, generation: generation, onFailure: onFailure)
            startDrainingIfNeeded()
        }
    }

    private func enqueue(
        _ workspace: ProductWorkspace,
        generation: Int,
        onFailure: (@Sendable (String) -> Void)?
    ) {
        guard generation > latestCompletedGeneration else { return }
        if pendingWorkspace != nil, generation < pendingGeneration {
            return
        }

        pendingWorkspace = workspace
        pendingGeneration = generation
        pendingFailureHandler = onFailure
    }

    private func startDrainingIfNeeded() {
        guard !isDraining else { return }
        isDraining = true
        Task {
            await drain()
        }
    }

    private func drain() async {
        while true {
            guard let workspace = pendingWorkspace else {
                isDraining = false
                return
            }
            let generation = pendingGeneration
            pendingWorkspace = nil
            pendingGeneration = 0
            let failureHandler = pendingFailureHandler
            pendingFailureHandler = nil

            guard generation > latestCompletedGeneration else {
                resolveFlushWaiters()
                continue
            }
            do {
                try await Task.detached(priority: .utility) {
                    try ProductWorkflowStore.saveWorkspace(workspace)
                }.value
                latestSuccessfulGeneration = max(latestSuccessfulGeneration, generation)
                latestCompletedGeneration = max(latestCompletedGeneration, generation)
                resolveFlushWaiters()
            } catch {
                latestCompletedGeneration = max(latestCompletedGeneration, generation)
                failureHandler?("workspace 保存失败：\(error.localizedDescription)")
                if pendingWorkspace == nil {
                    resolveFlushWaiters()
                }
            }
        }
    }

    private func resolveFlushWaiters() {
        let completedGenerations = flushWaiters.keys.filter { $0 <= latestCompletedGeneration }
        for generation in completedGenerations {
            let didSave = generation <= latestSuccessfulGeneration
            let waiters = flushWaiters.removeValue(forKey: generation) ?? []
            waiters.forEach { $0.resume(returning: didSave) }
        }
    }
}

@MainActor
public final class ProductWorkflowStore: ObservableObject {
    @Published var workspace: ProductWorkspace
    @Published var selectedPackID: UUID?
    @Published var statusText = "就绪"
    @Published var isRunningAI = false
    @Published var isRunningCorrection = false
    @Published var isRunningFieldDictionaryAI = false
    @Published var isRunningReportUnderstandingAI = false
    @Published var isRunningReportQAI = false
    @Published var isRunningAIFirstAnalysis = false
    @Published var isImportingData = false
    @Published var isExportingReport = false
    @Published var isSyncingConfluence = false
    @Published var isTestingConfluence = false
    @Published var isCollectingReferences = false
    @Published var syncingLocalKnowledgeFolderSourceIDs = Set<UUID>()
    @Published var testingDingTalkDocumentSourceIDs = Set<UUID>()
    @Published var syncingDingTalkDocumentSourceIDs = Set<UUID>()
    @Published var testingJiraProjectSourceIDs = Set<UUID>()
    @Published var syncingJiraProjectSourceIDs = Set<UUID>()
    @Published var testingTableauSourceIDs = Set<UUID>()
    @Published var importingTableauSourceIDs = Set<UUID>()
    @Published var importRequestToken = UUID()
    @Published var showingImportSourceChoice = false
    @Published var showingTableauImportSheet = false
    @Published var pendingPostImportConfirmation: PostImportAnalysisConfirmation?
    @Published var focusAnalysisComposerToken: UUID?
    @Published var requestedSidebarSelection: SidebarSelection?
    @Published var requestedAnalysisReportsPanelToken: UUID?
    @Published public var isAnalysisReadingMode = false
    @Published var currentSidebarSelection: SidebarSelection = .sessions
    @Published public var isMainSidebarVisible = true
    @Published var isAnalysisInfoSidebarVisible = false
    @Published var analysisInfoSidebarWidth: CGFloat = 460
    @Published var analysisInfoSidebarPanelID = "资料"
    @Published var selectedAnalysisEvidenceMessageID: UUID?
    @Published var selectedMetricResultID: UUID?
    @Published var selectedSourceCellRefs: [HarnessSourceCellRef] = []
    @Published var pendingTableStructureConfirmation: TableStructureConfirmationDraft?
    @Published var pendingMetricMappingConfirmation: MetricMappingConfirmationDraft?
    @Published var workspaceReadOnlySafeModeMessage: String?
    @Published var workspaceSaveFailureMessage: String?

    var hasPendingFieldDefinitionEdits = false
    var hasPendingMemoEdits = false
    var runningPersistentAIJobID: UUID?
    var persistentAIJobTasks: [UUID: Task<Void, Never>] = [:]
    var schedulerWakeTask: Task<Void, Never>?
    private var deferredWorkspaceSaveTask: Task<Void, Never>?
    private var deferredStartupMaintenanceTask: Task<Void, Never>?
    private var isBatchingWorkspaceSaves = false
    private var batchedWorkspaceSavePolicy: WorkspaceSavePolicy?
    private var workspaceSaveGeneration = 0
    var localKnowledgeFolderSyncTask: Task<Void, Never>?
    var currentReferenceCollectionRunID: UUID?
    var cancelledReferenceCollectionRunIDs = Set<UUID>()
    private let workspaceDiskWriter = WorkspaceDiskWriter()
    nonisolated private static let workspacePathEnvironmentKey = "NEXAFLOW_WORKSPACE_PATH"
    nonisolated private static let aiEndpointEnvironmentKey = "NEXAFLOW_AI_ENDPOINT"
    nonisolated private static let aiModelEnvironmentKey = "NEXAFLOW_AI_MODEL"
    private static let confluenceJSONImportDirectoryKey = "NEXAFLOW_LAST_CONFLUENCE_JSON_DIRECTORY"
    nonisolated private static let aiAPIKeyEnvironmentKey = "NEXAFLOW_AI_API_KEY"
    nonisolated private static let aiSystemPromptEnvironmentKey = "NEXAFLOW_AI_SYSTEM_PROMPT"

    var selectedPack: DataPack? {
        guard let selectedPackID,
              let pack = workspace.dataPacks.first(where: { $0.id == selectedPackID }) else {
            return nil
        }
        guard let spaceID = selectedBusinessSpace?.id else { return pack }
        return pack.businessSpaceID == spaceID ? pack : nil
    }

    var hasSelectedPackForCurrentBusinessSpace: Bool {
        guard let selectedPackID else { return false }
        let spaceID = selectedBusinessSpace?.id
        for index in workspace.dataPacks.indices where workspace.dataPacks[index].id == selectedPackID {
            guard let spaceID else { return true }
            return workspace.dataPacks[index].businessSpaceID == spaceID
        }
        return false
    }

    var selectedBusinessSpace: BusinessSpace? {
        if let id = workspace.selectedBusinessSpaceID,
           let space = workspace.businessSpaces.first(where: { $0.id == id && !$0.isArchived }) {
            return space
        }
        return workspace.businessSpaces.first { !$0.isArchived }
    }

    var activeBusinessSpaces: [BusinessSpace] {
        workspace.businessSpaces.filter { !$0.isArchived }
    }

    var packsForSelectedBusinessSpace: [DataPack] {
        guard let spaceID = selectedBusinessSpace?.id else { return [] }
        return workspace.dataPacks
            .filter { $0.businessSpaceID == spaceID }
            .sorted { $0.importedAt > $1.importedAt }
    }

    var unboundDataPacks: [DataPack] {
        workspace.dataPacks
            .filter { $0.businessSpaceID == nil }
            .sorted { $0.importedAt > $1.importedAt }
    }

    var selectedAnalysisTask: AnalysisTask? {
        guard let selectedPack else { return nil }
        return currentAnalysisTask(in: selectedPack)
    }

    var selectedAnalysisSession: AnalysisSession? {
        if let selectedID = workspace.selectedAnalysisSessionID,
           let session = workspace.analysisSessions.first(where: { $0.id == selectedID }),
           analysisSessionBelongsToSelectedBusinessSpace(session) {
            return session
        }
        if let selectedPackID {
            return workspace.analysisSessions.first {
                $0.packID == selectedPackID &&
                $0.status != .archived &&
                analysisSessionBelongsToSelectedBusinessSpace($0)
            }
        }
        return workspace.analysisSessions.first {
            $0.status != .archived && analysisSessionBelongsToSelectedBusinessSpace($0)
        }
    }

    var hasConfiguredAI: Bool {
        !workspace.aiSettings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var runningBlockingAIJobForSelectedAnalysisSession: PersistentAIJob? {
        guard let sessionID = selectedAnalysisSession?.id else { return nil }
        return blockingAIJob(for: sessionID)
    }

    func blockingAIJob(for sessionID: UUID) -> PersistentAIJob? {
        return workspace.persistentAIJobs
            .first { job in isBlockingAnalysisSessionJob(job, sessionID: sessionID) }
    }

    var runningAIJobForSelectedAnalysisSession: AIJobRecord? {
        runningBlockingAIJobForSelectedAnalysisSession?.record
    }

    public var canToggleMainSidebarFromTitlebar: Bool {
        true
    }

    var canToggleAnalysisInfoSidebarFromTitlebar: Bool {
        currentSidebarSelection == .sessions && selectedPack != nil && selectedAnalysisSession != nil
    }

    func syncCurrentSidebarSelection(_ selection: SidebarSelection) {
        currentSidebarSelection = selection
        if selection != .sessions {
            isAnalysisReadingMode = false
            isAnalysisInfoSidebarVisible = false
        }
    }

    public func toggleMainSidebarFromTitlebar() {
        guard canToggleMainSidebarFromTitlebar else { return }
        if isAnalysisReadingMode {
            isAnalysisReadingMode = false
            isMainSidebarVisible = true
            return
        }
        isMainSidebarVisible.toggle()
    }

    func toggleAnalysisInfoSidebarFromTitlebar() {
        guard canToggleAnalysisInfoSidebarFromTitlebar else { return }
        if isAnalysisReadingMode {
            isAnalysisReadingMode = false
        }
        isAnalysisInfoSidebarVisible.toggle()
    }

    var isReportGenerationRunningForSelectedAnalysisSession: Bool {
        let kind = runningBlockingAIJobForSelectedAnalysisSession?.kind
        return kind == .memo || kind == .simpleReportGeneration
    }

    var suggestedContextModeForSelectedAnalysisSession: AnalysisContextMode {
        guard let session = selectedAnalysisSession,
              let context = analysisSessionContext(for: session) else {
            return .fullReanalysis
        }
        let signature = analysisContextSignature(session: session, pack: context.pack, task: context.task, reports: context.reports)
        if session.contextCache?.signature == signature {
            return .cachedFollowUp
        }
        if session.messages.contains(where: { $0.role == .assistant && ($0.kind == .aiAnalysis || $0.kind == .aiMemo || $0.kind == .simpleReport) }) {
            return .quickFollowUp
        }
        return .fullReanalysis
    }

    var canAnalyzeSelectedPack: Bool {
        analysisBlockerText(for: selectedPack) == nil
    }

    public init() {
        var shouldStartRuntimeServices = true
        switch Self.loadWorkspaceResult() {
        case .loaded(let saved):
            var loaded = saved
            Self.migrateLegacyTavilyAPIKey(in: &loaded)
            Self.applyEnvironmentOverrides(to: &loaded)
            workspace = loaded
            performCriticalStartupRecovery()
        case .missing:
            var initialWorkspace = SampleDataFactory.makeWorkspace()
            Self.applyEnvironmentOverrides(to: &initialWorkspace)
            workspace = initialWorkspace
            performCriticalStartupRecovery()
        case .unsupportedVersion(let found, let supported):
            var safeWorkspace = SampleDataFactory.makeWorkspace()
            Self.applyEnvironmentOverrides(to: &safeWorkspace)
            workspace = safeWorkspace
            let message = "workspace 来自更高版本（版本 \(found)，当前支持到 \(supported)）。为避免覆盖数据，已进入只读安全模式。"
            workspaceReadOnlySafeModeMessage = message
            workspaceSaveFailureMessage = message
            statusText = message
            shouldStartRuntimeServices = false
        case .credentialUnavailable(let detail):
            var safeWorkspace = SampleDataFactory.makeWorkspace()
            Self.applyEnvironmentOverrides(to: &safeWorkspace)
            workspace = safeWorkspace
            let message = "钥匙串凭据暂时无法读取。为避免覆盖现有配置，已进入只读安全模式。原因：\(detail)"
            workspaceReadOnlySafeModeMessage = message
            workspaceSaveFailureMessage = message
            statusText = message
            shouldStartRuntimeServices = false
        case .corrupt(let errorDescription, let backupURL):
            var safeWorkspace = SampleDataFactory.makeWorkspace()
            Self.applyEnvironmentOverrides(to: &safeWorkspace)
            workspace = safeWorkspace
            let backupText = backupURL.map { "，备份：\($0.lastPathComponent)" } ?? ""
            let message = "workspace 读取失败，已保留损坏文件\(backupText)。原因：\(errorDescription)"
            workspaceReadOnlySafeModeMessage = message
            workspaceSaveFailureMessage = message
            statusText = message
            shouldStartRuntimeServices = false
        }
        selectedPackID = latestDataPackIDForSelectedBusinessSpace()
        rescopeAnalysisSessionSelectionToCurrentBusinessSpace()
        if shouldStartRuntimeServices {
            schedulePersistentAIJobs()
            scheduleLocalKnowledgeFolderSync()
            scheduleDeferredStartupMaintenance()
        }
    }

    init(debugSnapshotWorkspace workspace: ProductWorkspace) {
        self.workspace = workspace
        selectedPackID = latestDataPackIDForSelectedBusinessSpace()
        rescopeAnalysisSessionSelectionToCurrentBusinessSpace()
        currentSidebarSelection = .sessions
        isMainSidebarVisible = true
        isAnalysisInfoSidebarVisible = false
        isAnalysisReadingMode = false
    }

    private func performCriticalStartupRecovery() {
        batchWorkspaceSaves(flushPolicy: .deferred) {
            seedBuiltInBusinessSpacesIfNeeded()
            normalizeAnalysisTasksForAllPacks()
            normalizeBusinessSpaceTimeZones()
            recoverInterruptedReferenceCollectionRuns()
            recoverInterruptedPersistentAIJobs()
            normalizeStaleAnalysisSessionStatuses()
        }
    }

    private func scheduleDeferredStartupMaintenance() {
        deferredStartupMaintenanceTask?.cancel()
        deferredStartupMaintenanceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let self else { return }
            self.performDeferredStartupMaintenance()
            self.deferredStartupMaintenanceTask = nil
        }
    }

    private func performDeferredStartupMaintenance() {
        batchWorkspaceSaves(flushPolicy: .deferred) {
            if workspaceNeedsStorageCompaction() {
                workspace.confluencePages = workspace.confluencePages.map { $0.optimizedForStorage() }
                workspace.confluenceSyncRecords = Array(workspace.confluenceSyncRecords.sorted { $0.finishedAt > $1.finishedAt }.prefix(200))
            }
            let shouldNormalizeFields = workspaceNeedsFieldNormalization()
            if shouldNormalizeFields {
                normalizeFieldDefinitionsForCurrentReports()
                seedFieldDictionaryMemoriesFromExistingPacks()
                applyFieldDictionaryMemoriesToAllPacks()
            }
            if shouldNormalizeFields || workspaceNeedsAuditRefresh() {
                refreshAuditStateForAllPacks()
            }
            if !workspace.searchSettings.didImportRivalRadarSources {
                importRivalRadarReferenceSources(silent: true)
            }
            importMexicoEventReferenceSourcesIfNeeded(silent: true)
            importMexicoUtilityReferenceSourcesIfNeeded(silent: true)
            normalizeExistingReferenceSourcesForTavilyCountry()
            trimOperationalLogsForStorage()
        }
        selectedPackID = latestDataPackIDForSelectedBusinessSpace()
        rescopeAnalysisSessionSelectionToCurrentBusinessSpace()
    }

    @discardableResult
    private func trimOperationalLogsForStorage() -> Bool {
        var didChange = false
        let aiLogLimit = 160
        let aiRecordLimit = 100
        let sourceLogLimitPerRun = 60
        let textLimit = 1_200
        let referenceItemLimit = 2_000
        let dingtalkDocumentItemLimit = 2_000
        let jiraEvidenceLimit = 3_000
        let knowledgeEntryLimit = 10_000
        let correctionMessageLimitPerPack = 1_000
        let correctionMemoryLimit = 5_000
        let fieldDictionaryMemoryLimit = 20_000
        let reportKnowledgeMemoryLimit = 5_000
        let analysisTemplateMemoryLimit = 1_000

        for index in workspace.persistentAIJobs.indices {
            if workspace.persistentAIJobs[index].logs.count > aiLogLimit {
                workspace.persistentAIJobs[index].logs = Array(workspace.persistentAIJobs[index].logs.suffix(aiLogLimit))
                didChange = true
            }
            if workspace.persistentAIJobs[index].record.logs.count > aiLogLimit {
                workspace.persistentAIJobs[index].record.logs = Array(workspace.persistentAIJobs[index].record.logs.suffix(aiLogLimit))
                didChange = true
            }
        }

        if workspace.aiJobRecords.count > aiRecordLimit {
            workspace.aiJobRecords = Array(workspace.aiJobRecords.sorted { $0.updatedAt > $1.updatedAt }.prefix(aiRecordLimit))
            didChange = true
        }
        for index in workspace.aiJobRecords.indices where workspace.aiJobRecords[index].logs.count > aiLogLimit {
            workspace.aiJobRecords[index].logs = Array(workspace.aiJobRecords[index].logs.suffix(aiLogLimit))
            didChange = true
        }

        for packIndex in workspace.dataPacks.indices {
            if workspace.dataPacks[packIndex].correctionMessages.count > correctionMessageLimitPerPack {
                workspace.dataPacks[packIndex].correctionMessages = Array(
                    workspace.dataPacks[packIndex].correctionMessages
                        .sorted { $0.createdAt < $1.createdAt }
                        .suffix(correctionMessageLimitPerPack)
                )
                didChange = true
            }
            if workspace.dataPacks[packIndex].aiJobRecords.count > aiRecordLimit {
                workspace.dataPacks[packIndex].aiJobRecords = Array(workspace.dataPacks[packIndex].aiJobRecords.sorted { $0.updatedAt > $1.updatedAt }.prefix(aiRecordLimit))
                didChange = true
            }
            for recordIndex in workspace.dataPacks[packIndex].aiJobRecords.indices
                where workspace.dataPacks[packIndex].aiJobRecords[recordIndex].logs.count > aiLogLimit {
                workspace.dataPacks[packIndex].aiJobRecords[recordIndex].logs = Array(workspace.dataPacks[packIndex].aiJobRecords[recordIndex].logs.suffix(aiLogLimit))
                didChange = true
            }
        }

        if workspace.referenceCollectionRuns.count > 120 {
            workspace.referenceCollectionRuns = Array(workspace.referenceCollectionRuns.sorted { $0.startedAt > $1.startedAt }.prefix(120))
            didChange = true
        }
        for runIndex in workspace.referenceCollectionRuns.indices {
            if workspace.referenceCollectionRuns[runIndex].sourceLogs.count > sourceLogLimitPerRun {
                workspace.referenceCollectionRuns[runIndex].sourceLogs = Array(workspace.referenceCollectionRuns[runIndex].sourceLogs.prefix(sourceLogLimitPerRun))
                didChange = true
            }
            for logIndex in workspace.referenceCollectionRuns[runIndex].sourceLogs.indices {
                if workspace.referenceCollectionRuns[runIndex].sourceLogs[logIndex].errorMessage.count > textLimit {
                    workspace.referenceCollectionRuns[runIndex].sourceLogs[logIndex].errorMessage = String(workspace.referenceCollectionRuns[runIndex].sourceLogs[logIndex].errorMessage.prefix(textLimit))
                    didChange = true
                }
                if workspace.referenceCollectionRuns[runIndex].sourceLogs[logIndex].renderedQuery.count > textLimit {
                    workspace.referenceCollectionRuns[runIndex].sourceLogs[logIndex].renderedQuery = String(workspace.referenceCollectionRuns[runIndex].sourceLogs[logIndex].renderedQuery.prefix(textLimit))
                    didChange = true
                }
            }
        }

        if workspace.referenceItems.count > referenceItemLimit {
            workspace.referenceItems = Array(workspace.referenceItems.sorted { $0.collectedAt > $1.collectedAt }.prefix(referenceItemLimit))
            didChange = true
        }
        if workspace.knowledgeEntries.count > knowledgeEntryLimit {
            workspace.knowledgeEntries = Array(
                workspace.knowledgeEntries
                    .sorted { ($0.sourceUpdatedAt ?? $0.createdAt) > ($1.sourceUpdatedAt ?? $1.createdAt) }
                    .prefix(knowledgeEntryLimit)
            )
            didChange = true
        }
        if workspace.correctionMemories.count > correctionMemoryLimit {
            workspace.correctionMemories = Array(
                workspace.correctionMemories.sorted { $0.updatedAt > $1.updatedAt }.prefix(correctionMemoryLimit)
            )
            didChange = true
        }
        if workspace.fieldDictionaryMemories.count > fieldDictionaryMemoryLimit {
            workspace.fieldDictionaryMemories = Array(
                workspace.fieldDictionaryMemories.sorted { $0.updatedAt > $1.updatedAt }.prefix(fieldDictionaryMemoryLimit)
            )
            didChange = true
        }
        if workspace.reportKnowledgeMemories.count > reportKnowledgeMemoryLimit {
            workspace.reportKnowledgeMemories = Array(
                workspace.reportKnowledgeMemories.sorted { $0.updatedAt > $1.updatedAt }.prefix(reportKnowledgeMemoryLimit)
            )
            didChange = true
        }
        if workspace.analysisTemplateMemories.count > analysisTemplateMemoryLimit {
            workspace.analysisTemplateMemories = Array(
                workspace.analysisTemplateMemories.sorted { $0.updatedAt > $1.updatedAt }.prefix(analysisTemplateMemoryLimit)
            )
            didChange = true
        }
        if workspace.dingtalkDocumentItems.count > dingtalkDocumentItemLimit {
            workspace.dingtalkDocumentItems = Array(workspace.dingtalkDocumentItems.sorted { $0.syncedAt > $1.syncedAt }.prefix(dingtalkDocumentItemLimit))
            didChange = true
        }
        if workspace.jiraProjectEvidences.count > jiraEvidenceLimit {
            workspace.jiraProjectEvidences = Array(workspace.jiraProjectEvidences.sorted {
                ($0.updatedAt ?? $0.createdAt ?? .distantPast) > ($1.updatedAt ?? $1.createdAt ?? .distantPast)
            }.prefix(jiraEvidenceLimit))
            didChange = true
        }

        return didChange
    }

    private func workspaceNeedsStorageCompaction() -> Bool {
        workspace.confluenceSyncRecords.count > 200 ||
            workspace.confluencePages.contains { $0.text.count > ConfluencePage.storedTextLimit }
    }

    private func workspaceNeedsFieldNormalization() -> Bool {
        for pack in workspace.dataPacks where !pack.importedReports.isEmpty {
            let reportIDs = Set(pack.importedReports.map(\.id))
            let fieldReportIDs = Set(pack.fieldDefinitions.map(\.reportID))
            if !reportIDs.isSubset(of: fieldReportIDs) {
                return true
            }
            if pack.importedReports.contains(where: {
                $0.kind == .generic ||
                    $0.detectedConfidence <= 0.5 ||
                    $0.semanticProfile.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    $0.semanticConfidence <= 0
            }) {
                return true
            }
        }
        return false
    }

    private func workspaceNeedsAuditRefresh() -> Bool {
        workspace.dataPacks.contains { pack in
            pack.importedReports.contains { report in
                report.auditSteps.isEmpty ||
                    !report.auditSteps.contains { $0.kind == .analysisAdmission }
            }
        }
    }

    private func batchWorkspaceSaves(flushPolicy: WorkspaceSavePolicy, _ body: () -> Void) {
        let wasBatching = isBatchingWorkspaceSaves
        if !wasBatching {
            isBatchingWorkspaceSaves = true
            batchedWorkspaceSavePolicy = nil
        }

        body()

        guard !wasBatching else { return }
        batchedWorkspaceSavePolicy = nil
        isBatchingWorkspaceSaves = false

        save(policy: flushPolicy)
    }

    func latestDataPackIDForSelectedBusinessSpace() -> UUID? {
        guard let spaceID = selectedBusinessSpace?.id else { return nil }
        var latestPack: DataPack?
        for pack in workspace.dataPacks where pack.businessSpaceID == spaceID {
            guard let current = latestPack else {
                latestPack = pack
                continue
            }
            if pack.importedAt > current.importedAt {
                latestPack = pack
            }
        }
        return latestPack?.id
    }

    func analysisSessionBelongsToSelectedBusinessSpace(_ session: AnalysisSession) -> Bool {
        guard let spaceID = selectedBusinessSpace?.id else { return true }
        if let pack = workspace.dataPacks.first(where: { $0.id == session.packID }) {
            return pack.businessSpaceID == spaceID
        }
        return session.businessSpaceID == spaceID
    }

    func rescopeAnalysisSessionSelectionToCurrentBusinessSpace() {
        let selectedSpaceID = selectedBusinessSpace?.id
        let packSpaceByID = Dictionary(uniqueKeysWithValues: workspace.dataPacks.map { ($0.id, $0.businessSpaceID) })

        func belongsToSelectedSpace(_ session: AnalysisSession) -> Bool {
            guard let selectedSpaceID else { return true }
            if let packSpaceID = packSpaceByID[session.packID] {
                return packSpaceID == selectedSpaceID
            }
            return session.businessSpaceID == selectedSpaceID
        }

        if let selectedID = workspace.selectedAnalysisSessionID,
           let selected = workspace.analysisSessions.first(where: { $0.id == selectedID }),
           selected.status != .archived,
           belongsToSelectedSpace(selected),
           selected.packID == selectedPackID {
            return
        }

        var latestForSelectedPack: AnalysisSession?
        var latestInSelectedSpace: AnalysisSession?
        for session in workspace.analysisSessions where session.status != .archived && belongsToSelectedSpace(session) {
            if latestInSelectedSpace == nil || session.updatedAt > latestInSelectedSpace!.updatedAt {
                latestInSelectedSpace = session
            }
            if let selectedPackID,
               session.packID == selectedPackID,
               (latestForSelectedPack == nil || session.updatedAt > latestForSelectedPack!.updatedAt) {
                latestForSelectedPack = session
            }
        }

        workspace.selectedAnalysisSessionID = latestForSelectedPack?.id ?? latestInSelectedSpace?.id
    }

    func normalizeBusinessSpaceTimeZones() {
        for index in workspace.businessSpaces.indices {
            let normalized = BusinessTimeZoneResolver.normalized(
                workspace.businessSpaces[index].timeZoneIdentifier,
                for: workspace.businessSpaces[index]
            )
            if workspace.businessSpaces[index].timeZoneIdentifier != normalized {
                workspace.businessSpaces[index].timeZoneIdentifier = normalized
                workspace.businessSpaces[index].updatedAt = Date()
            }
        }
    }

    func seedBuiltInBusinessSpacesIfNeeded() {
        let existingKeys = Set(workspace.businessSpaces.compactMap(\.builtInKey))
        let existingNames = Set(workspace.businessSpaces.map { $0.name.normalizedKey })
        let missingSpaces = BuiltInBusinessSpaceCatalog.spaces.filter { builtIn in
            guard let key = builtIn.builtInKey else { return false }
            if existingKeys.contains(key) { return false }
            if existingNames.contains(builtIn.name.normalizedKey) { return false }
            return true
        }
        guard !missingSpaces.isEmpty else { return }
        workspace.businessSpaces.append(contentsOf: missingSpaces)
        if workspace.selectedBusinessSpaceID == nil {
            workspace.selectedBusinessSpaceID = workspace.businessSpaces.first?.id
        }
    }

    func restoreBuiltInBusinessSpaces() {
        let before = workspace.businessSpaces.count
        let updated = syncExistingBuiltInBusinessSpaces()
        seedBuiltInBusinessSpacesIfNeeded()
        let added = workspace.businessSpaces.count - before
        normalizeBusinessSpaceTimeZones()
        save()
        if added > 0 || updated > 0 {
            statusText = "已恢复 \(added) 个、更新 \(updated) 个内置海外金融业务空间"
        } else {
            statusText = "内置业务空间已完整，无需重复恢复"
        }
    }

    @discardableResult
    func syncExistingBuiltInBusinessSpaces() -> Int {
        var updated = 0
        for index in workspace.businessSpaces.indices {
            guard let key = workspace.businessSpaces[index].builtInKey,
                  let template = BuiltInBusinessSpaceCatalog.space(for: key) else {
                continue
            }
            let currentID = workspace.businessSpaces[index].id
            let currentCreatedAt = workspace.businessSpaces[index].createdAt
            let currentConfluenceRoots = workspace.businessSpaces[index].confluenceRoots
            let currentMetricSemantics = workspace.businessSpaces[index].metricSemanticLibrary
            let wasArchived = workspace.businessSpaces[index].isArchived
            workspace.businessSpaces[index] = template
            workspace.businessSpaces[index].id = currentID
            workspace.businessSpaces[index].createdAt = currentCreatedAt
            workspace.businessSpaces[index].updatedAt = Date()
            workspace.businessSpaces[index].confluenceRoots = currentConfluenceRoots
            workspace.businessSpaces[index].metricSemanticLibrary = currentMetricSemantics
            workspace.businessSpaces[index].isArchived = wasArchived
            updated += 1
        }
        return updated
    }

    func createBusinessSpaceFromBuiltIn(_ template: BusinessSpace) {
        var copy = template
        copy.id = UUID()
        copy.builtInKey = nil
        copy.name = "\(template.name) 副本"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        workspace.businessSpaces.insert(copy, at: 0)
        workspace.selectedBusinessSpaceID = copy.id
        selectedPackID = nil
        workspace.selectedAnalysisSessionID = nil
        save()
        requestedSidebarSelection = .businessSpaces
        statusText = "已从内置模板新建业务空间：\(copy.name)"
    }

    func resetBusinessSpaceToBuiltIn(_ template: BusinessSpace, targetID: UUID) {
        guard let index = workspace.businessSpaces.firstIndex(where: { $0.id == targetID }) else { return }
        let currentID = workspace.businessSpaces[index].id
        let currentCreatedAt = workspace.businessSpaces[index].createdAt
        workspace.businessSpaces[index].builtInKey = template.builtInKey
        workspace.businessSpaces[index].name = template.name
        workspace.businessSpaces[index].countryRegion = template.countryRegion
        workspace.businessSpaces[index].timeZoneIdentifier = template.timeZoneIdentifier
        workspace.businessSpaces[index].currencyCode = template.currencyCode
        workspace.businessSpaces[index].primaryLanguagesText = template.primaryLanguagesText
        workspace.businessSpaces[index].businessBackground = template.businessBackground
        workspace.businessSpaces[index].domains = template.domains
        workspace.businessSpaces[index].domainLinks = template.domainLinks
        workspace.businessSpaces[index].metricClassificationRulesText = template.metricClassificationRulesText
        workspace.businessSpaces[index].anomalyRulesText = template.anomalyRulesText
        workspace.businessSpaces[index].analysisGuardrailsText = template.analysisGuardrailsText
        workspace.businessSpaces[index].recommendedSourceCategories = template.recommendedSourceCategories
        workspace.businessSpaces[index].generatedSummary = template.generatedSummary
        workspace.businessSpaces[index].id = currentID
        workspace.businessSpaces[index].createdAt = currentCreatedAt
        workspace.businessSpaces[index].updatedAt = Date()
        save()
        requestedSidebarSelection = .businessSpaces
        statusText = "已用「\(template.name)」模板覆盖当前空间配置，分析资料、会话和知识已保留"
    }

    public func requestImport() {
        showImportPanel()
    }

    func showImportSourceChoice() {
        showImportPanel()
    }

    func showTableauImportSheet() {
        showingTableauImportSheet = true
    }

    func requestDataPackAuditNavigation() {
        requestedSidebarSelection = .sessions
    }

    func requestAnalysisSessionNavigation() {
        requestedSidebarSelection = .sessions
    }

    func requestAnalysisReportsPanel() {
        requestedSidebarSelection = .sessions
        requestedAnalysisReportsPanelToken = UUID()
    }

    func showImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "选择本次要分析的表格"
        panel.message = "可一次选择多张 CSV、XLSX 或 XLS 表格。导入后会直接确认本次分析表。"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        let xlsxType = UTType(filenameExtension: "xlsx") ?? .data
        let xlsType = UTType(filenameExtension: "xls") ?? .data
        let tsvType = UTType(filenameExtension: "tsv") ?? .data
        panel.allowedContentTypes = [.commaSeparatedText, .plainText, xlsxType, xlsType, tsvType]

        guard panel.runModal() == .OK else { return }
        importReportsIntoSelectedPack(from: panel.urls)
    }

    func importDataPack(from url: URL) {
        guard !isImportingData else {
            statusText = "正在导入数据，请等待当前导入完成"
            return
        }
        if let blocker = localImportBlocker(for: [url]) {
            statusText = blocker
            return
        }
        let businessSpaceID = selectedBusinessSpace?.id
        isImportingData = true
        statusText = "正在后台导入 \(url.lastPathComponent)..."
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                try DataImportService.importDataPack(from: url)
            }.result
            guard let self else { return }
            self.isImportingData = false
            switch result {
            case .success(var pack):
                pack.businessSpaceID = businessSpaceID
                let importedReportIDs = pack.importedReports.map(\.id)
                let appliedCount = self.applyFieldDictionaryMemories(to: &pack)
                self.preparePackForImportReview(&pack)
                self.workspace.dataPacks.insert(pack, at: 0)
                self.selectedPackID = pack.id
                self.save()
                let successMessage = appliedCount > 0
                    ? "已导入 \(pack.name)，自动确认 \(appliedCount) 个字段。下一步：进入分析会话，先选择分析表，再直接提问"
                    : "已导入 \(pack.name)。下一步：进入分析会话，先选择分析表，再直接提问"
                self.statusText = successMessage
                self.presentPostImportConfirmation(
                    packID: pack.id,
                    reportIDs: importedReportIDs,
                    detail: "已导入 \(importedReportIDs.count) 张报表，默认加入当前分析。"
                )
            case .failure(let error):
                self.statusText = error.localizedDescription
            }
        }
    }

    func importReportsIntoSelectedPack() {
        let panel = NSOpenPanel()
        panel.title = "选择本次要分析的表格"
        panel.message = "可以一次选择多张 CSV、TSV、XLSX 或 XLS 表格。导入后会直接确认本次分析表。"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        let xlsxType = UTType(filenameExtension: "xlsx") ?? .data
        let xlsType = UTType(filenameExtension: "xls") ?? .data
        let tsvType = UTType(filenameExtension: "tsv") ?? .data
        panel.allowedContentTypes = [.commaSeparatedText, .plainText, xlsxType, xlsType, tsvType]

        guard panel.runModal() == .OK else { return }
        importReportsIntoSelectedPack(from: panel.urls)
    }

    func importReportsIntoSelectedPack(from urls: [URL]) {
        let cleanedURLs = urls.filter { ["csv", "tsv", "xlsx", "xls"].contains($0.pathExtension.lowercased()) }
        guard !cleanedURLs.isEmpty else {
            statusText = "请选择 CSV、TSV、XLSX 或 XLS 表格文件"
            return
        }
        if let blocker = localImportBlocker(for: cleanedURLs) {
            statusText = blocker
            return
        }
        let targetPackID = ensureSelectedLocalAnalysisPack()
        guard !isImportingData else {
            statusText = "正在导入数据，请等待当前导入完成"
            return
        }
        let businessSpaceID = selectedBusinessSpace?.id
        isImportingData = true
        statusText = "正在后台导入 \(cleanedURLs.count) 个表格文件..."
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                try DataImportService.importReports(from: cleanedURLs)
            }.result
            guard let self else { return }
            self.isImportingData = false
            switch result {
            case .success(let result):
                self.applyImportedReports(result, toPackID: targetPackID, businessSpaceID: businessSpaceID)
            case .failure(let error):
                self.statusText = error.localizedDescription
            }
        }
    }

    private func ensureSelectedLocalAnalysisPack() -> UUID {
        if let selectedPackID,
           workspace.dataPacks.contains(where: { $0.id == selectedPackID }) {
            return selectedPackID
        }
        let dateText = DateFormatting.shortDate.string(from: Date())
        let pack = DataPack(
            id: UUID(),
            businessSpaceID: selectedBusinessSpace?.id,
            name: "本次分析资料 · \(dateText)",
            period: dateText,
            importedAt: Date(),
            sourcePath: nil,
            manifest: .fallback(period: dateText, sourcePath: nil),
            productUpdates: [],
            metrics: [],
            events: [],
            feedback: [],
            importedReports: [],
            fieldDefinitions: [],
            qualityReport: QualityReport(
                generatedAt: Date(),
                verdict: .caution,
                issues: [],
                stats: QualityStats(updateCount: 0, metricCount: 0, eventCount: 0, feedbackCount: 0, metricDateCount: 0)
            ),
            analysisReport: AnalysisReport(generatedAt: Date(), summary: "", metricInsights: [], attributionFindings: [], opportunities: []),
            decisionMemo: DecisionMemo(generatedAt: Date(), markdown: "", aiSupplement: ""),
            analysisGateStatus: .needsImportReview
        )
        workspace.dataPacks.insert(pack, at: 0)
        selectedPackID = pack.id
        return pack.id
    }

    private func applyImportedReports(
        _ result: (reports: [ImportedReport], fieldDefinitions: [ReportFieldDefinition]),
        toPackID targetPackID: UUID,
        businessSpaceID: UUID?
    ) {
        var appliedCount = 0
        var importedReportIDs: [UUID] = []
        guard let packIndex = workspace.dataPacks.firstIndex(where: { $0.id == targetPackID }) else {
            statusText = "目标分析资料已不存在，表格导入结果未写入"
            return
        }
        var packs = workspace.dataPacks
        for report in result.reports {
            var updatedReport = report
            if let existingIndex = packs[packIndex].importedReports.firstIndex(where: {
                reportImportBaseKey(for: $0) == reportImportBaseKey(for: report)
            }) {
                let existing = packs[packIndex].importedReports[existingIndex]
                updatedReport.id = existing.id
                if updatedReport.userReportAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    updatedReport.userReportAlias = existing.userReportAlias
                }
                packs[packIndex].importedReports[existingIndex] = updatedReport
            } else if let existingIndex = packs[packIndex].importedReports.firstIndex(where: {
                reportImportKey(for: $0) == reportImportKey(for: report)
            }) {
                let existing = packs[packIndex].importedReports[existingIndex]
                updatedReport.id = existing.id
                if updatedReport.userReportAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    updatedReport.userReportAlias = existing.userReportAlias
                }
                packs[packIndex].importedReports[existingIndex] = updatedReport
            } else {
                packs[packIndex].importedReports.append(updatedReport)
            }
            importedReportIDs.append(updatedReport.id)
        }
        packs[packIndex].businessSpaceID = packs[packIndex].businessSpaceID ?? businessSpaceID
        packs[packIndex].importedReports = dedupedReports(packs[packIndex].importedReports).sorted { $0.importedAt > $1.importedAt }
        packs[packIndex].fieldDefinitions = DataImportService.rebuildFieldDefinitions(
            for: packs[packIndex].importedReports,
            preserving: packs[packIndex].fieldDefinitions + result.fieldDefinitions
        )
        appliedCount = applyFieldDictionaryMemories(to: &packs[packIndex])
        preparePackForImportReview(&packs[packIndex])
        workspace.dataPacks = packs
        save()
        statusText = appliedCount > 0
            ? "已导入 \(result.reports.count) 张表，自动确认 \(appliedCount) 个字段。请确认本次分析表。"
            : "已导入 \(result.reports.count) 张表。请确认本次分析表。"
        if selectedPackID == targetPackID {
            presentPostImportConfirmation(
                packID: targetPackID,
                reportIDs: importedReportIDs,
                detail: "已导入 \(importedReportIDs.count) 张表，默认加入当前分析。"
            )
        }
    }

    func importCSVReportsIntoSelectedPack() {
        importReportsIntoSelectedPack()
    }

    private func localImportBlocker(for urls: [URL]) -> String? {
        let maxFileCount = 40
        guard urls.count <= maxFileCount else {
            return "本次选择了 \(urls.count) 个文件，超过一次导入上限 \(maxFileCount) 个。请分批导入。"
        }

        var totalBytes: Int64 = 0
        for url in urls {
            let extensionName = url.pathExtension.lowercased()
            guard ["csv", "tsv", "xlsx", "xls"].contains(extensionName) else {
                return "不支持的文件类型：\(url.lastPathComponent)。请选择 CSV、TSV、XLSX 或 XLS。"
            }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == false {
                return "只能导入表格文件，不能导入文件夹：\(url.lastPathComponent)。"
            }
            let fileSize = ImportFileSizePolicy.fileSize(url) ?? 0
            if fileSize > ImportFileSizePolicy.maxSingleFileBytes {
                return "\(url.lastPathComponent) 大小超过 80 MB。请先拆分、抽样或导出更小的表格后再导入。"
            }
            totalBytes += fileSize
        }
        if totalBytes > ImportFileSizePolicy.maxTotalBytes {
            return "本次导入总大小超过 250 MB。请分批导入，避免 App 解析时内存过高。"
        }
        return nil
    }

    func updateFieldDefinition(_ definition: ReportFieldDefinition, meaning: String? = nil, dataType: String? = nil, notes: String? = nil) {
        var didChange = false
        updateSelectedPack(saveImmediately: false) { pack in
            guard let index = pack.fieldDefinitions.firstIndex(where: { $0.id == definition.id }) else { return }
            if let meaning, pack.fieldDefinitions[index].meaning != meaning {
                pack.fieldDefinitions[index].meaning = meaning
                didChange = true
            }
            if let dataType, pack.fieldDefinitions[index].dataType != dataType {
                pack.fieldDefinitions[index].dataType = dataType
                didChange = true
            }
            if let notes, pack.fieldDefinitions[index].notes != notes {
                pack.fieldDefinitions[index].notes = notes
                didChange = true
            }
            if didChange {
                pack.fieldDefinitions[index].isConfirmed = true
                pack.fieldDefinitions[index].updatedAt = Date()
            }
        }
        if didChange {
            hasPendingFieldDefinitionEdits = true
        }
    }

    func commitFieldDefinitionEdits() {
        guard hasPendingFieldDefinitionEdits else { return }
        if let selectedPack {
            syncFieldDictionaryMemories(from: selectedPack)
        }
        updateSelectedPack(saveImmediately: false) { pack in
            markPackNeedsReview(&pack)
            refreshAuditState(for: &pack)
        }
        save()
        hasPendingFieldDefinitionEdits = false
        statusText = "字段字典已保存"
    }

    func updateImportedReportKind(reportID: UUID, kind: ImportedReportKind) {
        updateSelectedPack { pack in
            guard let index = pack.importedReports.firstIndex(where: { $0.id == reportID }) else { return }
            pack.importedReports[index].kind = kind
            pack.importedReports[index].detectedConfidence = max(pack.importedReports[index].detectedConfidence, 0.95)
            pack.importedReports[index].parseWarnings.removeAll { $0.contains("低置信") }
            pack.fieldDefinitions = DataImportService.rebuildFieldDefinitions(
                for: pack.importedReports,
                preserving: pack.fieldDefinitions
            )
            markPackNeedsReview(&pack)
            refreshAuditState(for: &pack)
        }
        statusText = "已修正报表类型"
    }

    func updateReportAlias(reportID: UUID, alias: String) {
        var didChange = false
        updateSelectedPack(saveImmediately: false) { pack in
            guard let index = pack.importedReports.firstIndex(where: { $0.id == reportID }) else { return }
            let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard pack.importedReports[index].userReportAlias != trimmedAlias else { return }
            pack.importedReports[index].userReportAlias = trimmedAlias
            didChange = true
        }
        if didChange {
            save(policy: .deferred)
        }
    }

    func acceptAuditRisk(reportID: UUID, stepID: UUID) {
        updateSelectedPack { pack in
            guard let reportIndex = pack.importedReports.firstIndex(where: { $0.id == reportID }),
                  let stepIndex = pack.importedReports[reportIndex].auditSteps.firstIndex(where: { $0.id == stepID }) else {
                return
            }
            guard pack.importedReports[reportIndex].auditSteps[stepIndex].status == .needsConfirmation else {
                return
            }
            pack.importedReports[reportIndex].auditSteps[stepIndex].status = .acceptedRisk
            pack.importedReports[reportIndex].auditSteps[stepIndex].details += " 已由用户接受风险。"
            markPackNeedsReview(&pack)
            refreshAnalysisAdmission(for: &pack.importedReports[reportIndex])
        }
        statusText = "已接受该项风险"
    }

    func acceptAllImportReviewRisks() {
        var acceptedCount = 0
        updateSelectedPack { pack in
            for reportIndex in pack.importedReports.indices {
                guard !pack.importedReports[reportIndex].isIgnoredFromAnalysis else { continue }
                for stepIndex in pack.importedReports[reportIndex].auditSteps.indices
                where pack.importedReports[reportIndex].auditSteps[stepIndex].status == .needsConfirmation {
                    pack.importedReports[reportIndex].auditSteps[stepIndex].status = .acceptedRisk
                    pack.importedReports[reportIndex].auditSteps[stepIndex].details += " 已由用户接受风险。"
                    acceptedCount += 1
                }
                refreshAnalysisAdmission(for: &pack.importedReports[reportIndex])
            }
            if acceptedCount > 0 {
                markPackNeedsReview(&pack)
            }
        }
        statusText = acceptedCount > 0 ? "已接受 \(acceptedCount) 个低风险问题" : "没有可接受的低风险问题"
    }

    func ignoreReportFromAnalysis(reportID: UUID, ignored: Bool = true) {
        updateSelectedPack { pack in
            guard let index = pack.importedReports.firstIndex(where: { $0.id == reportID }) else { return }
            pack.importedReports[index].isIgnoredFromAnalysis = ignored
            markPackNeedsReview(&pack)
            refreshTaskRelationshipProfile(for: &pack, forceReview: false)
            refreshTaskBusinessLinks(for: &pack, forceReview: false)
            refreshAuditState(for: &pack)
        }
        statusText = ignored ? "已忽略该表，后续分析不会引用" : "已恢复该表参与分析"
    }

    func askFieldDictionaryQuestion(fieldID: UUID?) {
        guard let selectedPack,
              let definition = fieldDictionaryDefinition(fieldID: fieldID, in: selectedPack) else {
            statusText = "当前分析资料没有可定义的字段"
            return
        }

        let settings = workspace.aiSettings
        isRunningFieldDictionaryAI = true
        statusText = "正在生成字段定义问题..."
        Task { [weak self] in
            guard let self else { return }
            let question = await self.generateFieldDictionaryQuestion(for: definition, settings: settings)
            self.appendFieldDictionaryMessage(FieldDictionaryMessage(
                id: UUID(),
                createdAt: Date(),
                role: .assistant,
                fieldDefinitionID: definition.id,
                reportName: definition.reportName,
                fieldName: definition.fieldName,
                content: question
            ))
            self.statusText = "字段助手已提问"
            self.isRunningFieldDictionaryAI = false
        }
    }

    func saveFieldDictionaryAnswer(_ answer: String, fieldID: UUID?) {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let selectedPack,
              let definition = fieldDictionaryDefinition(fieldID: fieldID, in: selectedPack) else {
            statusText = "请先选择字段并填写回答"
            return
        }

        appendFieldDictionaryMessage(FieldDictionaryMessage(
            id: UUID(),
            createdAt: Date(),
            role: .user,
            fieldDefinitionID: definition.id,
            reportName: definition.reportName,
            fieldName: definition.fieldName,
            content: trimmed
        ))

        let settings = workspace.aiSettings
        isRunningFieldDictionaryAI = true
        statusText = "正在整理字段含义..."
        Task { [weak self] in
            guard let self else { return }
            let fallback = FieldDictionaryAIService.fallbackInterpretation(for: definition, userAnswer: trimmed)
            let interpretation: FieldDictionaryInterpretation
            if settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                interpretation = fallback
            } else {
                do {
                    let output = try await AIAnalysisService().runAnalysis(
                        prompt: FieldDictionaryAIService.interpretationPrompt(for: definition, userAnswer: trimmed),
                        settings: settings
                    )
                    interpretation = FieldDictionaryAIService.parseInterpretation(output, fallback: fallback)
                } catch {
                    var copy = fallback
                    copy.assistantReply = "AI 整理失败，已按你的原始回答保存字段含义。错误：\(error.localizedDescription)"
                    interpretation = copy
                }
            }

            self.applyFieldDictionaryInterpretation(interpretation, fieldID: definition.id)
            self.appendFieldDictionaryMessage(FieldDictionaryMessage(
                id: UUID(),
                createdAt: Date(),
                role: .assistant,
                fieldDefinitionID: definition.id,
                reportName: definition.reportName,
                fieldName: definition.fieldName,
                content: interpretation.assistantReply
            ))

            if let nextPack = self.selectedPack,
               let nextDefinition = self.nextUnconfirmedFieldDefinition(in: nextPack) {
                let question = await self.generateFieldDictionaryQuestion(for: nextDefinition, settings: settings)
                self.appendFieldDictionaryMessage(FieldDictionaryMessage(
                    id: UUID(),
                    createdAt: Date(),
                    role: .assistant,
                    fieldDefinitionID: nextDefinition.id,
                    reportName: nextDefinition.reportName,
                    fieldName: nextDefinition.fieldName,
                    content: question
                ))
            } else {
                self.appendFieldDictionaryMessage(FieldDictionaryMessage(
                    id: UUID(),
                    createdAt: Date(),
                    role: .system,
                    fieldDefinitionID: nil,
                    reportName: "",
                    fieldName: "",
                    content: "当前分析资料的字段字典都已确认。你仍可以在下方列表里继续手动编辑。"
                ))
            }

            self.statusText = "字段含义已保存"
            self.isRunningFieldDictionaryAI = false
        }
    }

    func updateReportSemanticDescription(_ description: String, reportID: UUID?) {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let reportID else {
            statusText = "请先选择要说明的报表"
            return
        }
        updateImportedReport(reportID: reportID) { report in
            report.semanticProfile.summary = trimmed
            if report.semanticProfile.purpose.isEmpty {
                report.semanticProfile.purpose = trimmed
            }
            report.semanticProfile.updatedAt = Date()
            if report.semanticStatus == .needsReview {
                report.semanticStatus = .inProgress
            }
        }
        updateSelectedPack { pack in
            markPackNeedsReview(&pack)
            refreshAuditState(for: &pack)
        }
        statusText = "报表描述已保存"
    }

    func askReportUnderstandingQuestion(reportID: UUID?) {
        guard let report = reportUnderstandingTarget(reportID: reportID) else {
            statusText = "当前分析资料没有待确认的表"
            return
        }
        runReportUnderstanding(for: report, userInput: nil)
    }

    func sendReportUnderstandingAnswer(_ answer: String, reportID: UUID?) {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusText = "请先填写报表说明或回答"
            return
        }
        guard let report = reportUnderstandingTarget(reportID: reportID) else {
            statusText = "当前分析资料没有待确认的表"
            return
        }

        appendReportUnderstandingMessage(
            ReportUnderstandingMessage(role: .user, content: trimmed),
            reportID: report.id
        )
        var updatedReport = report
        updatedReport.understandingMessages.append(ReportUnderstandingMessage(role: .user, content: trimmed))
        updatedReport.semanticProfile.summary = trimmed
        if updatedReport.semanticProfile.purpose.isEmpty {
            updatedReport.semanticProfile.purpose = trimmed
        }
        runReportUnderstanding(for: updatedReport, userInput: trimmed)
    }

    func confirmReportUnderstanding(reportID: UUID?) {
        guard let report = reportUnderstandingTarget(reportID: reportID) else {
            statusText = "当前分析资料没有可确认的表"
            return
        }
        let profile = report.semanticProfile
        guard !(profile.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                profile.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else {
            statusText = "请先填写或通过对话生成报表说明"
            return
        }

        updateImportedReport(reportID: report.id) { report in
            report.semanticStatus = .confirmed
            report.semanticProfile.updatedAt = Date()
            report.understandingMessages.append(ReportUnderstandingMessage(
                role: .system,
                    content: "已确认报表说明，后续 AI 分析会优先参考这份语义说明。"
            ))
            if report.understandingMessages.count > 120 {
                report.understandingMessages = Array(report.understandingMessages.suffix(120))
            }
        }

        updateSelectedPack { pack in
            markPackNeedsReview(&pack)
            refreshAuditState(for: &pack)
        }

        if let pack = selectedPack, let next = firstPendingReport(in: pack) {
            statusText = "已确认 \(report.fileName)，继续确认 \(next.fileName)"
        } else {
            statusText = "报表说明已确认。请回到分析会话按当前目标发送给 AI"
        }
    }

    func askReportQuestion(_ question: String, reportID: UUID?) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusText = "请先输入要问这张表的问题"
            return
        }
        guard let report = reportUnderstandingTarget(reportID: reportID),
              let pack = selectedPack else {
            statusText = "请先选择要提问的报表"
            return
        }

        appendReportQAMessage(ReportQAMessage(role: .user, content: trimmed), reportID: report.id)
        let settings = workspace.aiSettings
        let fieldDefinitions = pack.fieldDefinitions
        let reportMemories = matchingReportKnowledgeMemories(for: report)
        recordReportKnowledgeMemoryHits(reportMemories)
        let knowledgeEntries = workspace.knowledgeEntries
        let sourceByID = Dictionary(uniqueKeysWithValues: workspace.referenceSources.map { ($0.id, $0) })
        let referenceItems = workspace.referenceItems.filter { item in
            item.isVisible(in: pack.businessSpaceID ?? selectedBusinessSpace?.id, sourceByID: sourceByID)
        }
        isRunningReportQAI = true
        statusText = "正在回答表格问题..."

        Task {
            let fallback = ReportQAService.fallbackAnswer(
                question: trimmed,
                report: report,
                fieldDefinitions: fieldDefinitions,
                reportMemories: reportMemories,
                knowledgeEntries: knowledgeEntries
            )
            let output: ReportQAOutput
            if settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                output = fallback
            } else {
                do {
                    let raw = try await AIAnalysisService().runAnalysis(
                        prompt: ReportQAService.prompt(
                            question: trimmed,
                            report: report,
                            fieldDefinitions: fieldDefinitions,
                            reportMemories: reportMemories,
                            knowledgeEntries: knowledgeEntries,
                            referenceItems: referenceItems
                        ),
                        settings: settings
                    )
                    output = ReportQAService.parse(raw, fallback: fallback)
                } catch {
                    var copy = fallback
                    copy.answer = "表格问答请求失败，已使用本地解析结果回答：\(error.localizedDescription)\n\n\(fallback.answer)"
                    output = copy
                }
            }

            appendReportQAMessage(
                ReportQAMessage(
                    role: .assistant,
                    content: output.answer,
                    evidence: output.evidence,
                    uncertainties: output.uncertainties,
                    suggestedMemories: output.suggestedMemories,
                    profilePatch: output.profilePatch,
                    fieldPatches: output.fieldPatches
                ),
                reportID: report.id
            )
            isRunningReportQAI = false
            statusText = output.suggestedMemories.isEmpty ? "表格问题已回答" : "表格问题已回答，可选择沉淀为记忆或知识库"
        }
    }

    func adoptReportQAAsProfile(reportID: UUID?, messageID: UUID?) {
        guard let report = reportUnderstandingTarget(reportID: reportID),
              let message = reportQAMessage(messageID: messageID, in: report) else {
            statusText = "没有可采纳的表格问答"
            return
        }
        updateImportedReport(reportID: report.id) { report in
            if let patch = message.profilePatch {
                report.semanticProfile = mergeSemanticProfile(existing: report.semanticProfile, patch: patch)
            } else {
                report.semanticProfile.summary = message.content
                if report.semanticProfile.purpose.isEmpty {
                    report.semanticProfile.purpose = message.content
                }
            }
            report.semanticProfile.updatedAt = Date()
            report.semanticStatus = .confirmed
            report.understandingMessages.append(ReportUnderstandingMessage(
                role: .system,
                content: "已从表格问答采纳报表说明。"
            ))
        }
        updateSelectedPack { pack in
            markPackNeedsReview(&pack)
            refreshAuditState(for: &pack)
        }
        statusText = "已更新表格含义。请回到分析会话按当前目标发送给 AI"
    }

    func adoptReportQAAsMemory(reportID: UUID?, messageID: UUID?, candidateID: UUID? = nil, alsoSaveKnowledge: Bool = true) {
        guard let report = reportUnderstandingTarget(reportID: reportID),
              let message = reportQAMessage(messageID: messageID, in: report) else {
            statusText = "没有可沉淀的表格问答"
            return
        }
        let candidate = candidateID.flatMap { id in message.suggestedMemories.first { $0.id == id } }
            ?? message.suggestedMemories.first
            ?? ReportQAMemoryCandidate(title: "表格问答沉淀", content: message.content, scope: "similarReports")
        let now = Date()
        let sourceQuestion = report.qaMessages.reversed().first { $0.role == .user }?.content ?? ""
        let fieldKeywords = (report.semanticProfile.keyMetrics + report.firstColumnValues.prefix(12) + report.headers.prefix(12))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
        var memory = ReportKnowledgeMemory(
            id: UUID(),
            createdAt: now,
            updatedAt: now,
            reportNamePattern: report.fileName,
            reportKind: report.kind,
            reportShape: report.shape,
            sourceFormat: report.sourceFormat,
            fieldKeywords: fieldKeywords,
            title: candidate.title,
            content: candidate.content,
            sourceQuestion: sourceQuestion,
            sourceAnswer: message.content,
            sourcePackName: selectedPack?.name ?? "",
            sourceReportName: report.fileName,
            knowledgeEntryID: nil
        )
        if alsoSaveKnowledge {
            let knowledgeEntry = knowledgeEntry(for: memory, report: report)
            memory.knowledgeEntryID = knowledgeEntry.id
            upsertKnowledgeEntry(knowledgeEntry)
        }
        upsertReportKnowledgeMemory(memory)
        refreshSelectedPackAfterKnowledgeChange()
        save()
        statusText = alsoSaveKnowledge ? "已沉淀为同类报表规则，并写入知识库" : "已沉淀为同类报表规则"
    }

    func saveReportQAToKnowledge(reportID: UUID?, messageID: UUID?) {
        adoptReportQAAsMemory(reportID: reportID, messageID: messageID, alsoSaveKnowledge: true)
    }

    func setReportKnowledgeMemoryArchived(_ memory: ReportKnowledgeMemory, archived: Bool) {
        guard let index = workspace.reportKnowledgeMemories.firstIndex(where: { $0.id == memory.id }) else { return }
        workspace.reportKnowledgeMemories[index].isArchived = archived
        workspace.reportKnowledgeMemories[index].updatedAt = Date()
        if let knowledgeEntryID = workspace.reportKnowledgeMemories[index].knowledgeEntryID,
           let entryIndex = workspace.knowledgeEntries.firstIndex(where: { $0.id == knowledgeEntryID }) {
            if archived {
                workspace.knowledgeEntries[entryIndex].tags = (workspace.knowledgeEntries[entryIndex].tags + ["已归档"]).uniqued()
            } else {
                workspace.knowledgeEntries[entryIndex].tags.removeAll { $0.normalizedKey == "已归档".normalizedKey }
            }
        }
        save()
        statusText = archived ? "已归档报表知识规则" : "已恢复报表知识规则"
    }

    func applyReportQAFieldPatches(reportID: UUID?, messageID: UUID?) {
        guard let report = reportUnderstandingTarget(reportID: reportID),
              let message = reportQAMessage(messageID: messageID, in: report),
              !message.fieldPatches.isEmpty else {
            statusText = "这条回答没有可采纳的字段解释"
            return
        }
        updateSelectedPack { pack in
            for patch in message.fieldPatches {
                guard let index = pack.fieldDefinitions.firstIndex(where: {
                    $0.reportID == report.id && $0.fieldName.normalizedKey == patch.fieldName.normalizedKey
                }) else { continue }
                pack.fieldDefinitions[index].meaning = patch.meaning
                if !patch.notes.isEmpty {
                    pack.fieldDefinitions[index].notes = patch.notes
                }
                pack.fieldDefinitions[index].isConfirmed = true
                pack.fieldDefinitions[index].updatedAt = Date()
            }
            markPackNeedsReview(&pack)
            refreshAuditState(for: &pack)
        }
        if let pack = selectedPack {
            syncFieldDictionaryMemories(from: pack)
        }
        save()
        statusText = "已采纳字段解释并同步字段记忆"
    }

    func select(pack: DataPack, presentSelectionIfEmpty: Bool = true) {
        if let spaceID = selectedBusinessSpace?.id, pack.businessSpaceID != spaceID {
            statusText = "该分析资料不属于当前业务空间，已阻止跨空间切换"
            return
        }
        selectedPackID = pack.id

        updateSelectedPack(saveImmediately: false) { pack in
            ensureAnalysisTaskExists(in: &pack)
            refreshTaskBusinessLinks(for: &pack, forceReview: false)
        }

        selectOrCreateAnalysisSessionForCurrentTask()
        if let selectedPack {
            syncSelectedAnalysisSessionWithCurrentTask(pack: selectedPack)
        }

        save()

        guard presentSelectionIfEmpty, let selectedPack else {
            statusText = "已切换分析资料：\(pack.name)"
            return
        }

        let selectedReports = reportsForCurrentTask(in: selectedPack)
        guard selectedReports.isEmpty else {
            statusText = "已切换分析资料：\(selectedPack.name)。当前任务已选择 \(selectedReports.count) 张表。"
            return
        }

        let selectableReportCount = selectedPack.importedReports.filter { !$0.isIgnoredFromAnalysis }.count
        guard selectableReportCount > 0 else {
            statusText = "已切换分析资料：\(selectedPack.name)。当前没有可分析表，请先导入本地表或 Tableau。"
            return
        }

        _ = presentCurrentPackReportSelectionConfirmation(force: false)
    }

    func bindDataPackToCurrentBusinessSpace(_ pack: DataPack) {
        guard let space = selectedBusinessSpace,
              let index = workspace.dataPacks.firstIndex(where: { $0.id == pack.id }) else {
            return
        }
        workspace.dataPacks[index].businessSpaceID = space.id
        for taskIndex in workspace.dataPacks[index].analysisTasks.indices {
            workspace.dataPacks[index].analysisTasks[taskIndex].businessSpaceID = space.id
            workspace.dataPacks[index].analysisTasks[taskIndex].businessSpaceSnapshot = space.snapshot
            workspace.dataPacks[index].analysisTasks[taskIndex].updatedAt = Date()
        }
        for sessionIndex in workspace.analysisSessions.indices where workspace.analysisSessions[sessionIndex].packID == pack.id {
            workspace.analysisSessions[sessionIndex].businessSpaceID = space.id
            workspace.analysisSessions[sessionIndex].businessSpaceSnapshot = space.snapshot
            workspace.analysisSessions[sessionIndex].updatedAt = Date()
        }
        selectedPackID = pack.id
        rescopeAnalysisSessionSelectionToCurrentBusinessSpace()
        save()
        statusText = "已将分析资料「\(pack.name)」绑定到业务空间「\(space.name)」"
    }

    func deleteSelectedPack() {
        guard let selectedPack else { return }
        let deletedPackID = selectedPack.id
        for index in workspace.analysisSessions.indices where workspace.analysisSessions[index].packID == deletedPackID {
            workspace.analysisSessions[index].sourcePackDeleted = true
            workspace.analysisSessions[index].sourcePackName = selectedPack.name
            workspace.analysisSessions[index].updatedAt = Date()
            workspace.analysisSessions[index].messages.append(AnalysisSessionMessage(
                role: .system,
                kind: .systemCoverage,
                content: "原始资料“\(selectedPack.name)”已删除。此会话作为历史工作记忆保留，可查看历史对话和报告，但不能继续基于原始表格重算。"
            ))
        }
        workspace.dataPacks.removeAll { $0.id == selectedPack.id }
        selectedPackID = latestDataPackIDForSelectedBusinessSpace()
        rescopeAnalysisSessionSelectionToCurrentBusinessSpace()
        save()
        statusText = "已删除 \(selectedPack.name)，关联分析会话已保留为历史记忆"
    }

    func resetToSampleData() {
        workspace = SampleDataFactory.makeWorkspace()
        selectedPackID = latestDataPackIDForSelectedBusinessSpace()
        rescopeAnalysisSessionSelectionToCurrentBusinessSpace()
        save()
        statusText = "已恢复示例数据"
    }

    func selectBusinessSpace(_ id: UUID?) {
        guard let id, workspace.businessSpaces.contains(where: { $0.id == id && !$0.isArchived }) else { return }
        isAnalysisReadingMode = false
        workspace.selectedBusinessSpaceID = id
        selectedPackID = latestDataPackIDForSelectedBusinessSpace()
        rescopeAnalysisSessionSelectionToCurrentBusinessSpace()
        requestedSidebarSelection = .businessSpaces
        save()
        statusText = "已切换业务空间：\(selectedBusinessSpace?.name ?? "未命名")"
    }

    func createBusinessSpace() {
        createBusinessSpace(
            name: "新业务空间",
            businessBackground: BusinessSpace.backgroundPromptTemplate
        )
    }

    func createBusinessSpace(name: String, businessBackground: String) {
        let draft = BusinessSpaceAIService.localProfileDraft(
            name: name,
            businessBackground: businessBackground
        )
        let map = draft.mapDraft
        let normalizedTimeZone = BusinessTimeZoneResolver.resolve(
            timeZoneIdentifier: draft.timeZoneIdentifier,
            countryRegion: draft.countryRegion,
            businessBackground: draft.businessBackground,
            businessSpaceName: draft.name
        )
        let space = BusinessSpace(
            name: draft.name,
            countryRegion: draft.countryRegion,
            timeZoneIdentifier: normalizedTimeZone,
            currencyCode: draft.currencyCode,
            primaryLanguagesText: draft.primaryLanguagesText,
            businessBackground: draft.businessBackground,
            domains: map.domains,
            domainLinks: map.links,
            metricClassificationRulesText: map.metricRules,
            anomalyRulesText: map.anomalyRules,
            analysisGuardrailsText: map.guardrails,
            recommendedSourceCategories: map.sourceCategories,
            generatedSummary: hasConfiguredAI ? "已创建本地草稿，AI 正在识别基础配置和业务地图。" : "未配置 AI，已使用本地规则生成基础配置草稿，请检查国家、时区、币种和语言。"
        )
        workspace.businessSpaces.insert(space, at: 0)
        workspace.selectedBusinessSpaceID = space.id
        selectedPackID = nil
        workspace.selectedAnalysisSessionID = nil
        save()
        requestedSidebarSelection = .businessSpaces
        if hasConfiguredAI {
            enqueuePersistentAIJob(
                kind: .businessSpaceProfile,
                payload: PersistentAIJobPayload(
                    prompt: BusinessSpaceAIService.profilePrompt(space: space),
                    businessSpaceID: space.id,
                    targetName: space.name
                )
            )
            statusText = "已创建业务空间，本地草稿可用；AI 基础配置识别已进入任务队列"
        } else {
            statusText = "已创建业务空间；未配置 AI，基础配置需要后续手动检查"
        }
    }

    func updateBusinessSpace(_ space: BusinessSpace) {
        guard let index = workspace.businessSpaces.firstIndex(where: { $0.id == space.id }) else { return }
        var copy = space
        copy.timeZoneIdentifier = BusinessTimeZoneResolver.normalized(copy.timeZoneIdentifier, for: copy)
        copy.updatedAt = Date()
        workspace.businessSpaces[index] = copy
        save(policy: .deferred)
    }

    func archiveBusinessSpace(_ space: BusinessSpace) {
        guard workspace.businessSpaces.filter({ !$0.isArchived }).count > 1,
              let index = workspace.businessSpaces.firstIndex(where: { $0.id == space.id }) else {
            statusText = "至少需要保留一个业务空间"
            return
        }
        workspace.businessSpaces[index].isArchived = true
        if workspace.selectedBusinessSpaceID == space.id {
            workspace.selectedBusinessSpaceID = workspace.businessSpaces.first { !$0.isArchived }?.id
            selectedPackID = latestDataPackIDForSelectedBusinessSpace()
            rescopeAnalysisSessionSelectionToCurrentBusinessSpace()
            requestedSidebarSelection = .businessSpaces
        }
        save()
        statusText = "已归档业务空间"
    }

    func insertBusinessSpaceExample(_ kind: BusinessSpaceExampleKind, into spaceID: UUID) {
        guard let index = workspace.businessSpaces.firstIndex(where: { $0.id == spaceID }) else { return }
        workspace.businessSpaces[index].businessBackground = kind.background
        if workspace.businessSpaces[index].name == "新业务空间" || workspace.businessSpaces[index].name == "默认业务空间" {
            workspace.businessSpaces[index].name = kind.defaultName
        }
        workspace.businessSpaces[index].countryRegion = kind.countryRegion
        workspace.businessSpaces[index].timeZoneIdentifier = BusinessTimeZoneResolver.resolve(
            timeZoneIdentifier: nil,
            countryRegion: kind.countryRegion,
            businessBackground: kind.background,
            businessSpaceName: workspace.businessSpaces[index].name
        )
        workspace.businessSpaces[index].currencyCode = kind.currencyCode
        workspace.businessSpaces[index].primaryLanguagesText = kind.languages
        workspace.businessSpaces[index].updatedAt = Date()
        save()
        statusText = "已插入示例背景，可继续修改后生成业务地图"
    }

    func generateBusinessMapForSelectedSpace() {
        guard let space = selectedBusinessSpace,
              let index = workspace.businessSpaces.firstIndex(where: { $0.id == space.id }) else {
            statusText = "请先选择业务空间"
            return
        }
        statusText = hasConfiguredAI ? "正在让 AI 生成业务地图..." : "未配置 AI，已使用本地规则生成可编辑业务地图草稿"
        let draft = BusinessSpaceAIService.localBusinessMapDraft(for: space)
        workspace.businessSpaces[index].domains = draft.domains
        workspace.businessSpaces[index].domainLinks = draft.links
        workspace.businessSpaces[index].metricClassificationRulesText = draft.metricRules
        workspace.businessSpaces[index].anomalyRulesText = draft.anomalyRules
        workspace.businessSpaces[index].analysisGuardrailsText = draft.guardrails
        workspace.businessSpaces[index].recommendedSourceCategories = draft.sourceCategories
        workspace.businessSpaces[index].generatedSummary = draft.summary
        workspace.businessSpaces[index].updatedAt = Date()
        save()

        guard hasConfiguredAI else { return }
        let prompt = BusinessSpaceAIService.businessMapPrompt(space: workspace.businessSpaces[index])
        enqueuePersistentAIJob(
            kind: .businessMap,
            payload: PersistentAIJobPayload(
                prompt: prompt,
                businessSpaceID: space.id,
                targetName: space.name
            )
        )
        statusText = "已保留本地业务地图草稿，AI 业务地图生成已进入任务队列"
    }

    public func recomputeSelectedPack() {
        confirmSelectedPackForAnalysis(skipAIObservationWarning: true)
    }

    func confirmSelectedPackForAnalysis(skipAIObservationWarning: Bool = true) {
        guard let selectedPack else { return }
        if let blocker = importReviewBlockerText(for: selectedPack) {
            statusText = blocker
            return
        }
        if !skipAIObservationWarning, let warning = aiObservationWarningText(for: selectedPack) {
            statusText = warning
            return
        }
        guard hasConfiguredAI else {
            statusText = "请先在 AI 设置中填写 API Key。现在不会再生成本地伪分析。"
            requestedSidebarSelection = .settings
            return
        }
        guard !isRunningAI, !isRunningAIFirstAnalysis else {
            statusText = "AI 正在执行，请等待本轮完成"
            return
        }

        updateSelectedPack { pack in
            ensureAnalysisTaskExists(in: &pack)
            refreshTaskRelationshipProfile(for: &pack, forceReview: false)
            refreshTaskBusinessLinks(for: &pack, forceReview: false)
            pack.analysisGateStatus = .readyForAnalysis
        }

        let refreshedPack = self.selectedPack ?? selectedPack
        let task = currentAnalysisTask(in: refreshedPack)
        if selectedAnalysisSession?.packID != refreshedPack.id || selectedAnalysisSession?.taskID != task?.id {
            createAnalysisSessionFromCurrentTask(initialGoal: task?.goal)
        }
        requestedSidebarSelection = .sessions

        let goal = task?.goal.nilIfBlank ?? selectedAnalysisSession?.goal.nilIfBlank ?? "请基于当前任务报表、知识库、Confluence、竞品舆情、政策和社会/自然事件，直接生成完整分析。"
        let observationNote = skipAIObservationWarning
            ? "本轮可不使用 AI 预读，请直接基于表格事实包和外部证据分析；如缺少预读信息，请写入限制说明。"
            : "如已有 AI 预读，请把它作为事实参考；如没有，请直接基于表格事实包和外部证据分析。"
        sendAnalysisSessionMessage(
            """
            请按当前任务和本次分析目标直接生成完整分析。

            本次分析目标：
            \(goal)

            \(observationNote)

            输出时先回答我的目标，再补充你额外发现的趋势、指标级多表联动、外部事件影响、不确定性和需补数据。
            """
            ,
            mode: .fullReanalysis
        )
    }

    func generateAIObservationForSelectedTask() {
        guard let selectedPack else { return }
        guard reportsForCurrentTask(in: selectedPack).isEmpty == false else {
            statusText = "当前分析任务还没有选择报表。请先加入至少 1 张表。"
            return
        }
        guard hasConfiguredAI else {
            statusText = "请先在 AI 设置中填写 API Key。AI 预读不会使用本地兜底分析。"
            requestedSidebarSelection = .settings
            return
        }
        guard !isRunningAIFirstAnalysis else {
            statusText = "AI 预读或分析正在执行，请等待完成"
            return
        }
        guard let task = currentAnalysisTask(in: selectedPack) else {
            statusText = "当前还没有分析任务"
            return
        }
        for report in reportsForCurrentTask(in: selectedPack) {
            enqueuePersistentAIJob(
                kind: .tableFirstAnalysis,
                payload: PersistentAIJobPayload(
                    packID: selectedPack.id,
                    taskID: task.id,
                    reportID: report.id,
                    targetName: report.displayName
                )
            )
        }
        statusText = "AI 预读已按报表进入任务队列，可在“分析资料 > AI 任务”查看进度"
    }

    func saveSelectedPackWithoutAnalysis() {
        updateSelectedPack { pack in
            markPackNeedsReview(&pack)
        }
        statusText = "已保存导入结果，暂不进入分析"
    }

    func recomputeSelectedPackIgnoringSemanticGate(status: String) {
        updateSelectedPack { pack in
            recomputeReports(for: &pack)
        }
        statusText = status
    }

    func runAIFirstAnalysisForSelectedTask() async -> Bool {
        guard let packID = selectedPack?.id,
              let packSnapshot = workspace.dataPacks.first(where: { $0.id == packID }) else {
            return false
        }
        let reports = reportsForCurrentTask(in: packSnapshot)
        guard !reports.isEmpty else { return true }

        let settings = workspace.aiSettings
        var allReady = true
        for report in reports {
            statusText = "AI-first 表格理解：\(report.displayName)"
            let result = await AITableFirstAnalysisService.analyze(report: report, settings: settings)
            updateSelectedPack { pack in
                guard let reportIndex = pack.importedReports.firstIndex(where: { $0.id == report.id }) else { return }
                pack.importedReports[reportIndex] = result.report
                if let jobRecord = result.jobRecord {
                    pack.aiJobRecords.insert(jobRecord, at: 0)
                    pack.aiJobRecords = Array(pack.aiJobRecords.prefix(120))
                    if jobRecord.status == .needsUserAction {
                        allReady = false
                    }
                }
                refreshAuditState(for: &pack)
            }
            if !allReady {
                statusText = "AI-first 表格理解暂停：请检查 AI 设置或模型错误后重试"
                return false
            }
        }
        statusText = "AI-first 表格理解已完成"
        return true
    }

    func runExternalEventImpactAnalysisForSelectedPack() async {
        guard let packID = selectedPack?.id,
              let pack = workspace.dataPacks.first(where: { $0.id == packID }) else { return }
        let sourceByID = Dictionary(uniqueKeysWithValues: workspace.referenceSources.map { ($0.id, $0) })
        let eventItems = workspace.referenceItems.filter { item in
            item.isVisible(in: pack.businessSpaceID ?? selectedBusinessSpace?.id, sourceByID: sourceByID) &&
                (item.domain == .externalEvent ||
                [.weather, .disaster, .energy, .holiday, .traffic, .publicSafety, .localEconomy].contains(item.intelligenceCategory)
                )
        }
        guard !eventItems.isEmpty else { return }
        enqueuePersistentAIJob(
            kind: .externalEventImpact,
            payload: PersistentAIJobPayload(
                packID: packID,
                targetName: pack.name
            )
        )
        statusText = "社会/自然事件影响分析已进入 AI 任务队列"
    }

    public func regenerateMemoForSelectedPack() {
        guard let selectedPack else { return }
        guard ensureSelectedPackCanAnalyze(actionName: "生成完整汇报") else { return }
        if selectedAnalysisSession == nil || selectedAnalysisSession?.packID != selectedPack.id {
            createAnalysisSessionFromCurrentTask(initialGoal: currentAnalysisTask(in: selectedPack)?.goal)
        }
        generateMemoFromSelectedAnalysisSession()
    }

    func updateMemo(_ markdown: String, packID: UUID? = nil, taskID: UUID? = nil) {
        var didChange = false
        if let packID {
            guard let packIndex = workspace.dataPacks.firstIndex(where: { $0.id == packID }) else { return }
            var pack = workspace.dataPacks[packIndex]
            if pack.decisionMemo.markdown != markdown {
                pack.decisionMemo.markdown = markdown
                didChange = true
            }
            let taskIndex = taskID.flatMap { id in
                pack.analysisTasks.firstIndex(where: { $0.id == id })
            } ?? currentAnalysisTaskIndex(in: pack)
            if let taskIndex {
                if pack.analysisTasks[taskIndex].decisionMemo.markdown != markdown {
                    pack.analysisTasks[taskIndex].decisionMemo.markdown = markdown
                    didChange = true
                }
            }
            if didChange {
                workspace.dataPacks[packIndex] = pack
            }
        } else {
            updateSelectedPack(saveImmediately: false) { pack in
                if pack.decisionMemo.markdown != markdown {
                    pack.decisionMemo.markdown = markdown
                    didChange = true
                }
                if let index = currentAnalysisTaskIndex(in: pack) {
                    if pack.analysisTasks[index].decisionMemo.markdown != markdown {
                        pack.analysisTasks[index].decisionMemo.markdown = markdown
                        didChange = true
                    }
                }
            }
        }
        if didChange {
            hasPendingMemoEdits = true
        }
    }

    func commitMemoEdits() {
        guard hasPendingMemoEdits else { return }
        save()
        hasPendingMemoEdits = false
        statusText = "报告草稿已保存"
    }

    func copyAIPromptForSelectedPack() {
        guard let selectedPack else { return }
        guard ensureSelectedPackCanAnalyze(actionName: "复制 AI 分析提示词") else { return }
        let task = currentAnalysisTask(in: selectedPack)
        let reports = task.map { taskReports(in: selectedPack, task: $0) } ?? reportsForCurrentTask(in: selectedPack)
        let session = selectedAnalysisSession ?? AnalysisSession(
            packID: selectedPack.id,
            taskID: task?.id,
            title: task?.name ?? "\(selectedPack.name) 分析会话",
            goal: task?.goal ?? "",
            selectedReportIDs: reports.map(\.id)
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            AnalysisSessionAIService.buildChatPrompt(
                userMessage: task?.goal.nilIfBlank ?? "请基于当前任务直接分析。",
                session: session,
                pack: selectedPack,
                task: task,
                reports: reports,
                workspace: workspace,
                contextMode: .fullReanalysis
            ),
            forType: .string
        )
        statusText = "AI 会话提示词已复制"
    }

    func runAIForSelectedPack() {
        guard let selectedPack else { return }
        guard ensureSelectedPackCanAnalyze(actionName: "运行 AI 分析") else { return }
        guard hasConfiguredAI else {
            statusText = "请先在 AI 设置中填写 API Key。现在不会再生成本地伪分析。"
            requestedSidebarSelection = .settings
            return
        }
        if selectedAnalysisSession == nil || selectedAnalysisSession?.packID != selectedPack.id {
            createAnalysisSessionFromCurrentTask(initialGoal: currentAnalysisTask(in: selectedPack)?.goal)
        }
        requestedSidebarSelection = .sessions
        let goal = selectedAnalysisSession?.goal.nilIfBlank ?? currentAnalysisTask(in: selectedPack)?.goal.nilIfBlank ?? "请基于当前任务报表和所有可用数据源直接生成分析。"
        sendAnalysisSessionMessage(goal, mode: .fullReanalysis)
    }

    func sendCorrectionMessage(_ content: String, findingID: UUID?) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let selectedPack else { return }

        let finding = selectedPack.analysisReport.attributionFindings.first { $0.id == findingID }
        let findingTitle = finding?.title ?? "整体分析"
        let userMessage = CorrectionMessage(
            id: UUID(),
            createdAt: Date(),
            role: .user,
            findingID: finding?.id,
            findingTitle: findingTitle,
            content: trimmed
        )
        appendCorrectionMessage(userMessage)

        let recentDialogue = selectedPack.correctionMessages
            .suffix(8)
            .map { "\($0.role.label)：\($0.content)" }
            .joined(separator: "\n")
        let dialogueInput = recentDialogue.isEmpty
            ? trimmed
            : "\(recentDialogue)\n你：\(trimmed)"

        guard !workspace.aiSettings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appendCorrectionMessage(CorrectionMessage(
                id: UUID(),
                createdAt: Date(),
                role: .assistant,
                findingID: finding?.id,
                findingTitle: findingTitle,
                content: "已记录你的纠偏。当前未配置 AI API Key，不能自动重写结论；请在分析会话里针对具体 AI 回复继续补充，配置 AI 后再生成可保存的纠偏规则。"
            ))
            statusText = "已记录纠偏输入"
            return
        }

        let prompt = AnalysisEngine.buildCorrectionPrompt(
            for: selectedPack,
            finding: finding,
            userMessage: dialogueInput,
            correctionMemories: workspace.correctionMemories
        )
        let settings = workspace.aiSettings
        isRunningCorrection = true
        statusText = "正在根据纠偏输入修正分析..."

        Task {
            do {
                let output = try await AIAnalysisService().runAnalysis(prompt: prompt, settings: settings)
                appendCorrectionMessage(CorrectionMessage(
                    id: UUID(),
                    createdAt: Date(),
                    role: .assistant,
                    findingID: finding?.id,
                    findingTitle: findingTitle,
                    content: output
                ))
                statusText = "纠偏回复已生成"
            } catch {
                appendCorrectionMessage(CorrectionMessage(
                    id: UUID(),
                    createdAt: Date(),
                    role: .assistant,
                    findingID: finding?.id,
                    findingTitle: findingTitle,
                    content: "纠偏请求失败：\(error.localizedDescription)"
                ))
                statusText = error.localizedDescription
            }
            isRunningCorrection = false
        }
    }

    func saveCorrectionMemory(
        findingID: UUID?,
        userCorrection: String,
        revisedConclusion: String,
        reusableRule: String,
        tagsText: String,
        appliesToFuture: Bool
    ) {
        guard let selectedPack else { return }
        let correction = userCorrection.trimmingCharacters(in: .whitespacesAndNewlines)
        let revised = revisedConclusion.trimmingCharacters(in: .whitespacesAndNewlines)
        let rule = reusableRule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !correction.isEmpty || !revised.isEmpty || !rule.isEmpty else {
            statusText = "请先填写纠偏内容、修正结论或复用规则"
            return
        }

        let finding = selectedPack.analysisReport.attributionFindings.first { $0.id == findingID }
        let tags = parseTags(tagsText)
        let memory = AnalysisCorrectionMemory(
            id: UUID(),
            createdAt: Date(),
            updatedAt: Date(),
            packID: selectedPack.id,
            packName: selectedPack.name,
            findingID: finding?.id,
            findingTitle: finding?.title ?? "整体分析",
            metric: finding?.relatedMetric ?? "",
            scope: finding?.relatedScope ?? "",
            originalConclusion: finding?.primaryCause ?? selectedPack.analysisReport.summary,
            userCorrection: correction,
            revisedConclusion: revised,
            reusableRule: rule,
            tags: tags,
            appliesToFuture: appliesToFuture
        )

        workspace.correctionMemories.insert(memory, at: 0)
        workspace.correctionMemories.sort { $0.updatedAt > $1.updatedAt }
        workspace.knowledgeEntries.insert(KnowledgeEntry(
            id: UUID(),
            createdAt: Date(),
            scenario: memory.scope.isEmpty ? "分析纠偏" : memory.scope,
            problem: memory.findingTitle,
            action: correction.isEmpty ? "人工修正归因结论" : correction,
            result: [
                revised.isEmpty ? nil : "修正后结论：\(revised)",
                rule.isEmpty ? nil : "复用规则：\(rule)"
            ]
            .compactMap { $0 }
            .joined(separator: "\n"),
            evidenceLevel: .b,
            relatedPackName: selectedPack.name,
            sourceID: "correction-\(memory.id.uuidString)",
            sourceURL: nil,
            sourceUpdatedAt: memory.updatedAt,
            tags: (["人工纠偏", "归因修正", memory.metric, memory.scope] + tags).filter { !$0.isEmpty }.uniqued()
        ), at: 0)

        updateSelectedPack { pack in
            if let findingID, let index = pack.analysisReport.attributionFindings.firstIndex(where: { $0.id == findingID }) {
                if !revised.isEmpty {
                    pack.analysisReport.attributionFindings[index].primaryCause = revised
                }
                if !correction.isEmpty {
                    pack.analysisReport.attributionFindings[index].counterSignals.append("人工纠偏：\(correction)")
                }
                if !rule.isEmpty {
                    pack.analysisReport.attributionFindings[index].supportingSignals.append("纠偏记忆规则：\(rule)")
                    pack.analysisReport.attributionFindings[index].recommendedNextData.append("按纠偏记忆复核：\(rule)")
                }
                pack.analysisReport.attributionFindings[index].supportingSignals = pack.analysisReport.attributionFindings[index].supportingSignals.uniqued()
                pack.analysisReport.attributionFindings[index].counterSignals = pack.analysisReport.attributionFindings[index].counterSignals.uniqued()
                pack.analysisReport.attributionFindings[index].recommendedNextData = pack.analysisReport.attributionFindings[index].recommendedNextData.uniqued()
            }
        }
        statusText = appliesToFuture ? "已保存纠偏记忆，并会用于后续分析" : "已保存本次纠偏记忆"
    }

    func deleteCorrectionMemory(_ memory: AnalysisCorrectionMemory) {
        workspace.correctionMemories.removeAll { $0.id == memory.id }
        workspace.knowledgeEntries.removeAll { $0.sourceID == "correction-\(memory.id.uuidString)" }
        save()
        statusText = "已删除纠偏记忆"
    }

    func updateCorrectionMemory(
        memoryID: UUID,
        userCorrection: String,
        revisedConclusion: String,
        reusableRule: String,
        tagsText: String,
        appliesToFuture: Bool
    ) {
        guard let index = workspace.correctionMemories.firstIndex(where: { $0.id == memoryID }) else {
            statusText = "未找到要更新的纠偏记忆"
            return
        }
        let correction = userCorrection.trimmingCharacters(in: .whitespacesAndNewlines)
        let revised = revisedConclusion.trimmingCharacters(in: .whitespacesAndNewlines)
        let rule = reusableRule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !correction.isEmpty || !revised.isEmpty || !rule.isEmpty else {
            statusText = "请先填写纠偏内容、修正结论或复用规则"
            return
        }

        workspace.correctionMemories[index].userCorrection = correction
        workspace.correctionMemories[index].revisedConclusion = revised
        workspace.correctionMemories[index].reusableRule = rule
        workspace.correctionMemories[index].tags = parseTags(tagsText)
        workspace.correctionMemories[index].appliesToFuture = appliesToFuture
        workspace.correctionMemories[index].updatedAt = Date()
        let memory = workspace.correctionMemories[index]
        upsertKnowledgeEntry(KnowledgeEntry(
            id: UUID(),
            createdAt: memory.updatedAt,
            scenario: memory.scope.isEmpty ? "分析纠偏" : memory.scope,
            problem: memory.findingTitle,
            action: correction.isEmpty ? "人工修正归因结论" : correction,
            result: [
                revised.isEmpty ? nil : "修正后结论：\(revised)",
                rule.isEmpty ? nil : "复用规则：\(rule)"
            ]
            .compactMap { $0 }
            .joined(separator: "\n"),
            evidenceLevel: .b,
            relatedPackName: memory.packName,
            sourceID: "correction-\(memory.id.uuidString)",
            sourceUpdatedAt: memory.updatedAt,
            tags: (["人工纠偏", "归因修正", memory.metric, memory.scope] + memory.tags).filter { !$0.isEmpty }.uniqued()
        ))
        workspace.correctionMemories.sort { $0.updatedAt > $1.updatedAt }
        save()
        statusText = appliesToFuture ? "已更新纠偏记忆，并会用于后续分析" : "已更新本次纠偏记忆"
    }

    func exportSelectedMemo() {
        guard !isExportingReport else {
            statusText = "正在导出汇报，请等待当前导出完成"
            return
        }
        guard runningBlockingAIJobForSelectedAnalysisSession == nil else {
            statusText = "当前会话正在执行 AI 任务，完成后可导出最新完整汇报"
            return
        }
        guard let session = selectedAnalysisSession else {
            statusText = "请先进入分析会话"
            return
        }
        guard let sessionReport = session.finalReportMarkdown.nilIfBlank else {
            statusText = "请先生成完整汇报"
            return
        }
        guard let selectedPack = workspace.dataPacks.first(where: { $0.id == session.packID }) else {
            statusText = "当前完整汇报缺少对应数据包，无法导出"
            return
        }
        let task = session.taskID.flatMap { taskID in
            selectedPack.analysisTasks.first(where: { $0.id == taskID })
        } ?? currentAnalysisTask(in: selectedPack)
        let reportName = [selectedPack.name, task?.name].compactMap { $0?.nilIfBlank }.joined(separator: "-")
        let generatedAt = session.lastReportGeneratedAt ?? Date()
        let generatedSuffix = wordExportTimestamp.string(from: generatedAt)
        let panel = NSSavePanel()
        panel.title = "导出完整汇报"
        panel.nameFieldStringValue = "NexaFlow_完整汇报_\(safeFileName(reportName.isEmpty ? selectedPack.name : reportName))_\(generatedSuffix).docx"
        panel.allowedContentTypes = [UTType(filenameExtension: "docx") ?? .data]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportWordReport(
            packName: reportName.isEmpty ? selectedPack.name : reportName,
            markdown: sessionReport,
            aiSupplement: "",
            to: url,
            kindName: "完整汇报"
        )
    }

    func exportSelectedSimpleReport() {
        guard !isExportingReport else {
            statusText = "正在导出汇报，请等待当前导出完成"
            return
        }
        guard runningBlockingAIJobForSelectedAnalysisSession == nil else {
            statusText = "当前会话正在执行 AI 任务，完成后可导出最新简洁汇报"
            return
        }
        guard let session = selectedAnalysisSession else {
            statusText = "请先进入分析会话"
            return
        }
        guard let simpleReport = session.simpleReportMarkdown.nilIfBlank else {
            statusText = "请先生成简洁汇报"
            return
        }
        guard let selectedPack = workspace.dataPacks.first(where: { $0.id == session.packID }) else {
            statusText = "当前简洁汇报缺少对应数据包，无法导出"
            return
        }
        let task = session.taskID.flatMap { taskID in
            selectedPack.analysisTasks.first(where: { $0.id == taskID })
        } ?? currentAnalysisTask(in: selectedPack)
        let reportName = [selectedPack.name, task?.name].compactMap { $0?.nilIfBlank }.joined(separator: "-")
        let generatedAt = session.lastSimpleReportGeneratedAt ?? Date()
        let generatedSuffix = wordExportTimestamp.string(from: generatedAt)
        let panel = NSSavePanel()
        panel.title = "导出简洁汇报"
        panel.nameFieldStringValue = "NexaFlow_简洁汇报_\(safeFileName(reportName.isEmpty ? selectedPack.name : reportName))_\(generatedSuffix).docx"
        panel.allowedContentTypes = [UTType(filenameExtension: "docx") ?? .data]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportWordReport(
            packName: reportName.isEmpty ? selectedPack.name : reportName,
            markdown: simpleReport,
            aiSupplement: "",
            to: url,
            kindName: "简洁汇报"
        )
    }

    private func exportWordReport(
        packName: String,
        markdown: String,
        aiSupplement: String,
        to url: URL,
        kindName: String
    ) {
        isExportingReport = true
        statusText = "正在后台导出\(kindName)..."
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                try WordDocumentExporter.exportMemo(
                    packName: packName,
                    markdown: markdown,
                    aiSupplement: aiSupplement,
                    to: url
                )
            }.result
            guard let self else { return }
            self.isExportingReport = false
            switch result {
            case .success:
                NSWorkspace.shared.activateFileViewerSelecting([url])
                self.statusText = "\(kindName)已导出，并已在 Finder 中定位：\(url.lastPathComponent)"
            case .failure(let error):
                self.statusText = error.localizedDescription
            }
        }
    }

    func addKnowledgeFromSelectedPack() {
        guard let selectedPack else { return }
        let bestOpportunity = selectedPack.analysisReport.opportunities.first
        let bestFinding = selectedPack.analysisReport.attributionFindings.first
        let entry = KnowledgeEntry(
            id: UUID(),
            createdAt: Date(),
            scenario: bestOpportunity?.affectedUsers ?? "未归类场景",
            problem: bestOpportunity?.problem ?? selectedPack.analysisReport.summary,
            action: bestOpportunity?.title ?? "待确认动作",
            result: "上线后待复盘；请在完成验证后更新结果。",
            evidenceLevel: bestFinding?.evidenceLevel ?? .d,
            relatedPackName: selectedPack.name
        )
        workspace.knowledgeEntries.insert(entry, at: 0)
        refreshSelectedPackAfterKnowledgeChange()
        save()
        statusText = "已写入知识库草稿"
    }

    func importConfluencePagesFromJSON() {
        guard !isSyncingConfluence else {
            statusText = "正在同步 Confluence，请等待当前任务完成"
            return
        }
        let panel = NSOpenPanel()
        panel.title = "选择 Confluence pages.json"
        panel.message = "选择从 Confluence 导出的 pages.json，客户端会导入页面并生成知识库条目。"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]

        if let lastDirectoryPath = UserDefaults.standard.string(forKey: Self.confluenceJSONImportDirectoryKey),
           !lastDirectoryPath.isEmpty {
            let lastDirectoryURL = URL(fileURLWithPath: lastDirectoryPath, isDirectory: true)
            if FileManager.default.fileExists(atPath: lastDirectoryURL.path) {
                panel.directoryURL = lastDirectoryURL
            }
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.deletingLastPathComponent().path, forKey: Self.confluenceJSONImportDirectoryKey)
        let startedAt = Date()
        let sourceName = url.lastPathComponent
        isSyncingConfluence = true
        statusText = "正在后台导入 \(sourceName)..."

        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                try ConfluenceService().importPagesJSON(from: url)
            }.result
            guard let self else { return }
            switch result {
            case .success(let pages):
                self.mergeConfluencePages(pages, sourceName: sourceName, startedAt: startedAt)
            case .failure(let error):
                self.appendConfluenceSyncRecord(
                    startedAt: startedAt,
                    sourceName: sourceName,
                    status: .failed,
                    totalPages: 0,
                    matchedPages: 0,
                    addedKnowledgeEntries: 0,
                    updatedKnowledgeEntries: 0,
                    message: error.localizedDescription
                )
                self.statusText = error.localizedDescription
            }
            self.isSyncingConfluence = false
        }
    }

    func syncConfluenceTree() {
        guard !isSyncingConfluence else { return }
        let settings = confluenceSettingsForSelectedBusinessSpace()
        let startedAt = Date()
        isSyncingConfluence = true
        statusText = "正在同步 Confluence 页面..."

        Task {
            do {
                let pages = try await ConfluenceService().fetchTree(settings: settings)
                mergeConfluencePages(pages, sourceName: settings.baseURL, startedAt: startedAt)
            } catch {
                appendConfluenceSyncRecord(
                    startedAt: startedAt,
                    sourceName: settings.baseURL,
                    status: .failed,
                    totalPages: 0,
                    matchedPages: 0,
                    addedKnowledgeEntries: 0,
                    updatedKnowledgeEntries: 0,
                    message: error.localizedDescription
                )
                statusText = error.localizedDescription
            }
            isSyncingConfluence = false
        }
    }

    func testConfluenceConnection() {
        guard !isTestingConfluence else { return }
        let settings = confluenceSettingsForSelectedBusinessSpace()
        isTestingConfluence = true
        statusText = "正在测试 Confluence 连接..."

        Task {
            defer { isTestingConfluence = false }
            do {
                statusText = try await ConfluenceService().testConnection(settings: settings)
            } catch {
                statusText = error.localizedDescription
            }
        }
    }

    func mergeConfluenceKnowledgeEntries() {
        let result = mergeKnowledgeEntries(from: workspace.confluencePages)
        refreshSelectedPackAfterKnowledgeChange()
        save()
        statusText = "Confluence 知识库已更新：新增 \(result.added)，更新 \(result.updated)"
    }

    func deleteKnowledgeEntry(_ entry: KnowledgeEntry) {
        workspace.knowledgeEntries.removeAll { $0.id == entry.id }
        refreshSelectedPackAfterKnowledgeChange()
        save()
    }

    func updateAISettings(_ transform: (inout AISettings) -> Void) {
        transform(&workspace.aiSettings)
        save(policy: .deferred)
    }

    func updateNotificationSettings(_ transform: (inout AppNotificationSettings) -> Void) {
        transform(&workspace.notificationSettings)
        save(policy: .deferred)
    }

    func updateSearchSettings(_ transform: (inout SearchAPISettings) -> Void) {
        transform(&workspace.searchSettings)
        save(policy: .deferred)
    }

    func updateConfluenceSettings(_ transform: (inout ConfluenceSettings) -> Void) {
        transform(&workspace.confluenceSettings)
        save(policy: .deferred)
    }

    func deleteConfluencePage(_ page: ConfluencePage) {
        workspace.confluencePages.removeAll { $0.id == page.id }
        save()
    }

    func mergeConfluencePages(_ pages: [ConfluencePage], sourceName: String, startedAt: Date = Date()) {
        let settings = confluenceSettingsForSelectedBusinessSpace()
        let mergedAt = Date()
        let filteredPages = pages
            .filter { settings.matchesTitle($0.title) }
            .map { page -> ConfluencePage in
                var copy = page
                copy.syncedAt = copy.syncedAt ?? mergedAt
                return copy.optimizedForStorage()
            }
        var byID = Dictionary(uniqueKeysWithValues: workspace.confluencePages.map { ($0.id, $0) })
        for page in filteredPages {
            byID[page.id] = page
        }
        workspace.confluencePages = byID.values.sorted {
            ($0.syncedAt ?? .distantPast) == ($1.syncedAt ?? .distantPast)
                ? ($0.lastUpdated ?? $0.createdAt ?? .distantPast) > ($1.lastUpdated ?? $1.createdAt ?? .distantPast)
                : ($0.syncedAt ?? .distantPast) > ($1.syncedAt ?? .distantPast)
        }

        let result = mergeKnowledgeEntries(from: filteredPages)
        let message: String
        if settings.parsedTitleKeywords.isEmpty {
            message = "已导入 \(filteredPages.count) 个 Confluence 页面（\(sourceName)），知识库新增 \(result.added)，更新 \(result.updated)"
        } else {
            message = "已读取 \(pages.count) 页，标题关键字命中 \(filteredPages.count) 页，保留历史页面 \(workspace.confluencePages.count) 页，知识库新增 \(result.added)，更新 \(result.updated)"
        }
        appendConfluenceSyncRecord(
            startedAt: startedAt,
            sourceName: sourceName,
            status: .success,
            totalPages: pages.count,
            matchedPages: filteredPages.count,
            addedKnowledgeEntries: result.added,
            updatedKnowledgeEntries: result.updated,
            message: message
        )
        refreshSelectedPackAfterKnowledgeChange()
        save()
        statusText = message
    }

    func appendConfluenceSyncRecord(
        startedAt: Date,
        sourceName: String,
        status: ConfluenceSyncStatus,
        totalPages: Int,
        matchedPages: Int,
        addedKnowledgeEntries: Int,
        updatedKnowledgeEntries: Int,
        message: String
    ) {
        let record = ConfluenceSyncRecord(
            startedAt: startedAt,
            finishedAt: Date(),
            sourceName: sourceName,
            status: status,
            totalPages: totalPages,
            matchedPages: matchedPages,
            pageCountAfterSync: workspace.confluencePages.count,
            addedKnowledgeEntries: addedKnowledgeEntries,
            updatedKnowledgeEntries: updatedKnowledgeEntries,
            message: message
        )
        workspace.confluenceSyncRecords.insert(record, at: 0)
        workspace.confluenceSyncRecords = Array(workspace.confluenceSyncRecords.sorted { $0.finishedAt > $1.finishedAt }.prefix(200))
        save()
    }

    @discardableResult
    func mergeKnowledgeEntries(from pages: [ConfluencePage]) -> (added: Int, updated: Int) {
        var entries = workspace.knowledgeEntries
        var added = 0
        var updated = 0

        for page in pages {
            let root = matchingConfluenceRoot(for: page, in: selectedBusinessSpace)
            let entry = KnowledgeEntry(
                id: entries.first(where: { $0.sourceID == page.id })?.id ?? UUID(),
                createdAt: entries.first(where: { $0.sourceID == page.id })?.createdAt ?? Date(),
                businessSpaceID: root == nil ? nil : selectedBusinessSpace?.id,
                businessDomainIDs: root?.businessDomainIDs ?? [],
                rootPageID: root?.rootPageID,
                isGlobal: root == nil,
                scenario: page.scenario,
                problem: page.title,
                action: page.url.isEmpty ? "查看 Confluence 页面" : "查看 Confluence 页面：\(page.url)",
                result: page.compactSummary,
                evidenceLevel: .b,
                relatedPackName: "Confluence 产品文档",
                sourceID: page.id,
                sourceURL: page.url,
                sourceUpdatedAt: page.lastUpdated,
                sourceCreatedAt: page.createdAt,
                tags: (page.labels + [page.scenario]).uniqued()
            )

            if let index = entries.firstIndex(where: { $0.sourceID == page.id }) {
                entries[index] = entry
                updated += 1
            } else {
                entries.append(entry)
                added += 1
            }
        }

        workspace.knowledgeEntries = entries.sorted {
            ($0.sourceUpdatedAt ?? $0.sourceCreatedAt ?? $0.createdAt) > ($1.sourceUpdatedAt ?? $1.sourceCreatedAt ?? $1.createdAt)
        }
        return (added, updated)
    }

    func updateSelectedPack(saveImmediately: Bool = true, _ transform: (inout DataPack) -> Void) {
        guard let current = selectedPack, let index = workspace.dataPacks.firstIndex(where: { $0.id == current.id }) else { return }
        var packs = workspace.dataPacks
        transform(&packs[index])
        workspace.dataPacks = packs
        if saveImmediately { save() }
    }

    func businessSpace(for pack: DataPack, task: AnalysisTask? = nil) -> BusinessSpace? {
        let id = task?.businessSpaceID ?? pack.businessSpaceID ?? workspace.selectedBusinessSpaceID
        if let id, let space = workspace.businessSpaces.first(where: { $0.id == id && !$0.isArchived }) {
            return space
        }
        return selectedBusinessSpace
    }

    func matchingConfluenceRoot(for page: ConfluencePage, in space: BusinessSpace?) -> BusinessSpaceConfluenceRoot? {
        guard let space else { return nil }
        return space.confluenceRoots.first { root in
            let rootID = root.rootPageID.trimmingCharacters(in: .whitespacesAndNewlines)
            let rootMatches = rootID.isEmpty || page.id == rootID || page.ancestors.contains(rootID)
            guard rootMatches else { return false }
            let titleKey = page.title.normalizedKey
            let includeMatches = root.titleKeywords.isEmpty || root.titleKeywords.contains { titleKey.contains($0.normalizedKey) }
            let excluded = root.exclusionKeywords.contains { titleKey.contains($0.normalizedKey) }
            return includeMatches && !excluded
        }
    }

    func confluenceSettingsForSelectedBusinessSpace() -> ConfluenceSettings {
        var settings = workspace.confluenceSettings
        guard let space = selectedBusinessSpace, !space.confluenceRoots.isEmpty else {
            return settings
        }
        let rootIDs = space.confluenceRoots.map(\.rootPageID)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !rootIDs.isEmpty {
            settings.rootPageIDs = rootIDs.joined(separator: ",")
        }
        let keywords = space.confluenceRoots.flatMap(\.titleKeywords).uniqued()
        if !keywords.isEmpty {
            settings.titleKeywords = keywords.joined(separator: ",")
        }
        return settings
    }

    func updateImportedReport(
        reportID: UUID,
        saveImmediately: Bool = true,
        _ transform: (inout ImportedReport) -> Void
    ) {
        updateSelectedPack(saveImmediately: saveImmediately) { pack in
            guard let index = pack.importedReports.firstIndex(where: { $0.id == reportID }) else { return }
            transform(&pack.importedReports[index])
        }
    }

    func smartMemoryEvidence(
        pack: DataPack,
        task: AnalysisTask?,
        session: AnalysisSession,
        reports: [ImportedReport],
        userText: String
    ) -> [AnalysisSessionEvidence] {
        let result = SmartMemoryRetriever.retrieve(
            workspace: workspace,
            pack: pack,
            task: task,
            session: session,
            reports: reports,
            userText: userText,
            limit: 8
        )
        return result.used.prefix(8).map { memory in
            AnalysisSessionEvidence(
                sourceType: "智能记忆",
                title: "\(memory.kind.label) · \(memory.title)",
                detail: "\(memory.content)；范围：\(memory.scope)；置信度 \(Int(memory.confidence * 100))%；来源：\(memory.sourceType)。",
                sourceID: memory.sourceID
            )
        }
    }

    func analysisBlockerText(for pack: DataPack?) -> String? {
        guard let pack else { return nil }
        switch pack.analysisGateStatus {
        case .needsImportReview:
            return importReviewBlockerText(for: pack) ??
                "当前分析资料已导入但尚未按当前目标确认。请在分析会话右侧“校准”处理表格问题，或仅保存不分析。"
        case .readyForAnalysis, .analyzed:
            return importReviewBlockerText(for: pack)
        }
    }

    func analysisWarningText(for pack: DataPack?) -> String? {
        guard let pack else { return nil }
        guard pack.analysisGateStatus != .needsImportReview else { return nil }
        let reports = reportsForCurrentTask(in: pack)
        var parts: [String] = []
        let acceptedRiskCount = reports.reduce(0) { $0 + $1.acceptedRiskAuditSteps.count }
        if acceptedRiskCount > 0 {
            parts.append("\(acceptedRiskCount) 个导入识别风险已被接受")
        }
        let warningCount = reports.reduce(0) { $0 + actionableParseWarnings($1.parseWarnings).count }
        if warningCount > 0 {
            parts.append("\(warningCount) 条报表解析/识别提醒")
        }
        let lowConfidenceCount = reports.filter { $0.detectedConfidence < 0.65 }.count
        if lowConfidenceCount > 0 {
            parts.append("\(lowConfidenceCount) 张报表类型识别置信度较低")
        }
        if let task = currentAnalysisTask(in: pack), task.businessLinkProfile.confirmationStatus == .confirmed, task.businessLinkProfile.edges.contains(where: { $0.confidence < 0.72 }) {
            parts.append("当前任务含低置信业务影响边")
        }
        guard !parts.isEmpty else { return nil }
        return "\(parts.joined(separator: "，"))。这些内容会作为低置信上下文进入分析。"
    }

    func ensureSelectedPackCanAnalyze(actionName: String) -> Bool {
        if let blocker = analysisBlockerText(for: selectedPack) {
            statusText = "\(actionName)已暂停：\(blocker)"
            return false
        }
        if let warning = analysisWarningText(for: selectedPack) {
            statusText = "\(actionName)继续执行：\(warning)"
        }
        return true
    }

    func actionableParseWarnings(_ warnings: [String]) -> [String] {
        warnings.filter { warning in
            !warning.contains("识别为透视宽表") &&
                !warning.contains("已标准化 CSV 换行符")
        }
    }

    func recomputeReports(for pack: inout DataPack) {
        ensureAnalysisTaskExists(in: &pack)
        refreshTaskRelationshipProfile(for: &pack, forceReview: false)
        refreshTaskBusinessLinks(for: &pack, forceReview: false)
        var analysisPack = pack
        guard let taskIndex = currentAnalysisTaskIndex(in: pack) else { return }
        let task = pack.analysisTasks[taskIndex]
        analysisPack.importedReports = taskReports(in: pack, task: task)
        analysisPack.reportRelationshipProfile = task.relationshipProfile
        analysisPack.analysisTasks = [task]
        analysisPack.selectedAnalysisTaskID = task.id
        pack.qualityReport = AnalysisEngine.buildQualityReport(
            for: analysisPack,
            knowledgeEntries: workspace.knowledgeEntries
        )
        pack.analysisReport = factOnlyAnalysisReport(for: analysisPack)
        analysisPack.analysisReport = pack.analysisReport
        analysisPack.qualityReport = pack.qualityReport
        pack.analysisTasks[taskIndex].relationshipProfile = analysisPack.reportRelationshipProfile
        pack.analysisTasks[taskIndex].businessLinkProfile = task.businessLinkProfile
        pack.analysisTasks[taskIndex].analysisReport = pack.analysisReport
        pack.analysisTasks[taskIndex].lastAnalyzedAt = pack.analysisReport.generatedAt
        pack.analysisTasks[taskIndex].updatedAt = Date()
        pack.reportRelationshipProfile = analysisPack.reportRelationshipProfile
    }

    func factOnlyAnalysisReport(for pack: DataPack) -> AnalysisReport {
        let reports = pack.importedReports.filter { !$0.isIgnoredFromAnalysis }
        let overview = reports.isEmpty
            ? "当前任务还没有选择报表。"
            : ReportTrendAnalyzer.combinedTrendOverview(for: reports)
        let bullets = reports.flatMap { report in
            report.trendSummary.trendBullets.map { "\(report.displayName)：\($0)" }
        }
        return AnalysisReport(
            generatedAt: Date(),
            summary: "等待 AI 分析会话生成结论。本地只保留数据覆盖、确定性计算和趋势事实，不再输出业务归因或 Memo。",
            tableTrendOverview: overview,
            tableTrendBullets: Array(bullets.prefix(200)),
            contextSignals: [],
            metricInsights: [],
            attributionFindings: [],
            opportunities: []
        )
    }

    func refreshSelectedPackAfterKnowledgeChange() {
        updateSelectedPack(saveImmediately: false) { pack in
            refreshAuditState(for: &pack)
            if pack.analysisGateStatus != .needsImportReview {
                recomputeReports(for: &pack)
                pack.analysisGateStatus = .analyzed
            }
        }
    }

    func recomputeAllPacks() {
        var packs = workspace.dataPacks
        for index in packs.indices {
            if packs[index].analysisGateStatus != .needsImportReview {
                recomputeReports(for: &packs[index])
                if !packs[index].analysisReport.summary.isEmpty || !packs[index].decisionMemo.markdown.isEmpty {
                    packs[index].analysisGateStatus = .analyzed
                }
            }
        }
        workspace.dataPacks = packs
    }

    func reportUnderstandingTarget(reportID: UUID?) -> ImportedReport? {
        guard let pack = selectedPack else { return nil }
        if let reportID, let report = pack.importedReports.first(where: { $0.id == reportID }) {
            return report
        }
        return firstPendingReport(in: pack) ?? pack.importedReports.first
    }

    func firstPendingReport(in pack: DataPack) -> ImportedReport? {
        pack.importedReports
            .sorted { $0.importedAt > $1.importedAt }
            .first { semanticNeedsHumanReview($0) }
    }

    func semanticNeedsHumanReview(_ report: ImportedReport) -> Bool {
        report.semanticStatus == .needsReview || report.semanticStatus == .inProgress
    }

    func startFirstPendingReportUnderstandingIfNeeded(packID: UUID) {
        guard let pack = workspace.dataPacks.first(where: { $0.id == packID }),
              let report = firstPendingReport(in: pack),
              report.understandingMessages.isEmpty else {
            return
        }
        selectedPackID = packID
        askReportUnderstandingQuestion(reportID: report.id)
    }

    func runReportUnderstanding(for report: ImportedReport, userInput: String?) {
        let settings = workspace.aiSettings
        isRunningReportUnderstandingAI = true
        statusText = "正在确认报表含义..."
        updateImportedReport(reportID: report.id) { report in
            if report.semanticStatus != .inProgress {
                report.semanticStatus = .inProgress
            }
        }

        Task {
            let fallback: ReportUnderstandingOutput
            if let userInput {
                fallback = ReportUnderstandingAIService.fallbackOutput(for: report, userInput: userInput)
            } else {
                fallback = ReportUnderstandingAIService.fallbackInitialOutput(for: report)
            }

            let output: ReportUnderstandingOutput
            if settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                output = fallback
            } else {
                do {
                    let raw = try await AIAnalysisService().runAnalysis(
                        prompt: ReportUnderstandingAIService.prompt(for: report, userInput: userInput),
                        settings: settings
                    )
                    output = ReportUnderstandingAIService.parse(raw, fallback: fallback)
                } catch {
                    var copy = fallback
                    copy.assistantReply = "报表理解请求失败，已使用本地问题继续：\(error.localizedDescription)"
                    output = copy
                }
            }

            applyReportUnderstandingOutput(output, reportID: report.id)
            statusText = output.readyForConfirmation ? "报表说明草稿已整理，可继续追问或手动确认" : "报表助手已更新疑问点"
            isRunningReportUnderstandingAI = false
        }
    }

    func applyReportUnderstandingOutput(_ output: ReportUnderstandingOutput, reportID: UUID) {
        let reply = [output.assistantReply, output.nextQuestion]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
            .joined(separator: "\n\n")
        updateImportedReport(reportID: reportID) { report in
            report.semanticProfile = output.profileDraft
            if report.semanticStatus != .inProgress {
                report.semanticStatus = .inProgress
            }
            if !reply.isEmpty {
                report.understandingMessages.append(ReportUnderstandingMessage(role: .assistant, content: reply))
            }
            if report.understandingMessages.count > 120 {
                report.understandingMessages = Array(report.understandingMessages.suffix(120))
            }
        }
        updateSelectedPack { pack in
            markPackNeedsReview(&pack)
            refreshAuditState(for: &pack)
        }
    }

    func appendReportUnderstandingMessage(_ message: ReportUnderstandingMessage, reportID: UUID) {
        updateImportedReport(reportID: reportID) { report in
            report.understandingMessages.append(message)
            report.understandingMessages.sort { $0.createdAt < $1.createdAt }
            if report.understandingMessages.count > 120 {
                report.understandingMessages = Array(report.understandingMessages.suffix(120))
            }
            if report.semanticStatus != .inProgress {
                report.semanticStatus = .inProgress
            }
        }
    }

    func appendReportQAMessage(_ message: ReportQAMessage, reportID: UUID) {
        updateImportedReport(reportID: reportID) { report in
            report.qaMessages.append(message)
            report.qaMessages.sort { $0.createdAt < $1.createdAt }
            if report.qaMessages.count > 160 {
                report.qaMessages = Array(report.qaMessages.suffix(160))
            }
        }
    }

    func reportQAMessage(messageID: UUID?, in report: ImportedReport) -> ReportQAMessage? {
        if let messageID, let message = report.qaMessages.first(where: { $0.id == messageID }) {
            return message
        }
        return report.qaMessages.reversed().first { $0.role == .assistant }
    }

    func matchingReportKnowledgeMemories(for report: ImportedReport) -> [ReportKnowledgeMemory] {
        workspace.reportKnowledgeMemories
            .map { (memory: $0, score: $0.matchScore(for: report)) }
            .filter { $0.score >= 5 }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.memory.updatedAt > $1.memory.updatedAt
            }
            .prefix(20)
            .map(\.memory)
    }

    func mergeSemanticProfile(existing: ReportSemanticProfile, patch: ReportSemanticProfile) -> ReportSemanticProfile {
        ReportSemanticProfile(
            summary: patch.summary.nilIfBlank ?? existing.summary,
            purpose: patch.purpose.nilIfBlank ?? existing.purpose,
            businessObject: patch.businessObject.nilIfBlank ?? existing.businessObject,
            grain: patch.grain.nilIfBlank ?? existing.grain,
            keyMetrics: patch.keyMetrics.isEmpty ? existing.keyMetrics : patch.keyMetrics,
            dimensions: patch.dimensions.isEmpty ? existing.dimensions : patch.dimensions,
            filters: patch.filters.nilIfBlank ?? existing.filters,
            useCases: patch.useCases.isEmpty ? existing.useCases : patch.useCases,
            caveats: patch.caveats.isEmpty ? existing.caveats : patch.caveats,
            openQuestions: patch.openQuestions.isEmpty ? existing.openQuestions : patch.openQuestions,
            updatedAt: Date()
        )
    }

    func upsertReportKnowledgeMemory(_ memory: ReportKnowledgeMemory) {
        if let index = workspace.reportKnowledgeMemories.firstIndex(where: { $0.matchKey == memory.matchKey }) {
            var updated = memory
            updated.id = workspace.reportKnowledgeMemories[index].id
            updated.createdAt = workspace.reportKnowledgeMemories[index].createdAt
            updated.knowledgeEntryID = memory.knowledgeEntryID ?? workspace.reportKnowledgeMemories[index].knowledgeEntryID
            updated.hitCount = workspace.reportKnowledgeMemories[index].hitCount
            updated.lastMatchedAt = workspace.reportKnowledgeMemories[index].lastMatchedAt
            updated.isArchived = false
            workspace.reportKnowledgeMemories[index] = updated
        } else {
            workspace.reportKnowledgeMemories.insert(memory, at: 0)
        }
        workspace.reportKnowledgeMemories.sort { $0.updatedAt > $1.updatedAt }
    }

    func recordReportKnowledgeMemoryHits(_ memories: [ReportKnowledgeMemory]) {
        guard !memories.isEmpty else { return }
        let ids = Set(memories.map(\.id))
        let now = Date()
        for index in workspace.reportKnowledgeMemories.indices where ids.contains(workspace.reportKnowledgeMemories[index].id) {
            workspace.reportKnowledgeMemories[index].hitCount += 1
            workspace.reportKnowledgeMemories[index].lastMatchedAt = now
        }
        save()
    }

    func knowledgeEntry(for memory: ReportKnowledgeMemory, report: ImportedReport) -> KnowledgeEntry {
        KnowledgeEntry(
            id: memory.knowledgeEntryID ?? UUID(),
            createdAt: memory.createdAt,
            scenario: "报表知识",
            problem: memory.title,
            action: memory.sourceQuestion.isEmpty ? "从表格 AI 问答沉淀" : "问题：\(memory.sourceQuestion)",
            result: [
                memory.content,
                memory.sourceAnswer.isEmpty ? nil : "来源回答：\(memory.sourceAnswer)"
            ]
            .compactMap { $0 }
            .joined(separator: "\n"),
            evidenceLevel: .b,
            relatedPackName: memory.sourcePackName,
            sourceID: "report-memory-\(memory.id.uuidString)",
            sourceURL: nil,
            sourceUpdatedAt: memory.updatedAt,
            tags: ([
                "报表知识",
                "AI问答沉淀",
                report.sourceFormat.label,
                report.kind.label,
                report.shape.label
            ] + memory.fieldKeywords.prefix(8)).uniqued()
        )
    }

    func preparePackForImportReview(_ pack: inout DataPack) {
        ensureAnalysisTaskExists(in: &pack)
        markPackNeedsReview(&pack)
        refreshTaskRelationshipProfile(for: &pack, forceReview: true)
        refreshTaskBusinessLinks(for: &pack, forceReview: true)
        refreshAuditState(for: &pack)
        var qualityPack = pack
        qualityPack.importedReports = reportsForCurrentTask(in: pack)
        pack.qualityReport = AnalysisEngine.buildQualityReport(
            for: qualityPack,
            knowledgeEntries: workspace.knowledgeEntries
        )
    }

    func markPackNeedsReview(_ pack: inout DataPack) {
        pack.analysisGateStatus = .needsImportReview
    }

    func refreshAuditStateForAllPacks() {
        var packs = workspace.dataPacks
        for index in packs.indices {
            ensureAnalysisTaskExists(in: &packs[index])
            refreshAuditState(for: &packs[index])
        }
        workspace.dataPacks = packs
    }

    func refreshAuditState(for pack: inout DataPack) {
        for index in pack.importedReports.indices {
            let report = pack.importedReports[index]
            let matchedCount = workspace.reportKnowledgeMemories
                .map { $0.matchScore(for: report) }
                .filter { $0 >= 5 }
                .count
            let generated = DataImportService.auditSteps(for: report, matchedMemoryCount: matchedCount)
            pack.importedReports[index].auditSteps = mergeAuditSteps(
                existing: report.auditSteps,
                generated: generated,
                fieldDefinitions: pack.fieldDefinitions.filter { $0.reportID == report.id }
            )
            refreshAnalysisAdmission(for: &pack.importedReports[index])
        }
        refreshTaskRelationshipProfile(for: &pack, forceReview: false)
        refreshTaskBusinessLinks(for: &pack, forceReview: false)
    }

    func mergeAuditSteps(
        existing: [ImportAuditStep],
        generated: [ImportAuditStep],
        fieldDefinitions: [ReportFieldDefinition]
    ) -> [ImportAuditStep] {
        let existingByKind = existing.reduce(into: [ImportAuditStepKind: ImportAuditStep]()) { result, step in
            result[step.kind] = step
        }
        return generated.map { step in
            var copy = step
            if let existing = existingByKind[step.kind] {
                copy.id = existing.id
                copy.createdAt = existing.createdAt
                if existing.status == .acceptedRisk && step.status == .needsConfirmation {
                    copy.status = .acceptedRisk
                    copy.details = step.details + " 已由用户接受风险。"
                }
            }
            if step.kind == .fieldDictionary {
                let unconfirmed = fieldDefinitions.filter { !$0.isConfirmed }
                if fieldDefinitions.isEmpty {
                    copy.status = .needsConfirmation
                    copy.details = "没有提取到可解释的字段标签。"
                    copy.warnings = ["字段字典为空"]
                    copy.confidence = 0.45
                } else {
                    copy.status = .completed
                    copy.details = "已提取 \(fieldDefinitions.count) 个字段标签，其中 \(fieldDefinitions.count - unconfirmed.count) 个已确认。"
                    copy.warnings = unconfirmed.isEmpty ? [] : ["\(unconfirmed.count) 个字段含义仍可继续补充，不阻塞分析"]
                    copy.confidence = unconfirmed.isEmpty ? 0.9 : 0.76
                }
            }
            return copy
        }
    }

    func refreshAnalysisAdmission(for report: inout ImportedReport) {
        let existingAdmission = report.auditSteps.first { $0.kind == .analysisAdmission }
        report.auditSteps.removeAll { $0.kind == .analysisAdmission }
        let admission: ImportAuditStep
        if report.isIgnoredFromAnalysis {
            admission = ImportAuditStep(
                id: existingAdmission?.id ?? UUID(),
                kind: .analysisAdmission,
                status: .acceptedRisk,
                confidence: 1,
                details: "该报表已被忽略，不进入分析上下文。",
                warnings: [],
                usedAI: false,
                createdAt: existingAdmission?.createdAt ?? Date()
            )
        } else {
            let unresolved = report.auditSteps.filter { $0.status == .needsConfirmation || $0.status == .blocked }
            let status: ImportAuditStepStatus
            if unresolved.contains(where: { $0.status == .blocked }) {
                status = .blocked
            } else if unresolved.isEmpty {
                status = .completed
            } else {
                status = .needsConfirmation
            }
            admission = ImportAuditStep(
                id: existingAdmission?.id ?? UUID(),
                kind: .analysisAdmission,
                status: status,
                confidence: unresolved.isEmpty ? 0.9 : 0.5,
                details: unresolved.isEmpty
                    ? "该报表可以进入分析上下文。"
                    : "该报表还有 \(unresolved.count) 个问题需要处理或接受风险。",
                warnings: unresolved.flatMap(\.warnings).uniqued(),
                usedAI: false,
                createdAt: existingAdmission?.createdAt ?? Date()
            )
        }
        report.auditSteps.append(admission)
    }

    func currentAnalysisTask(in pack: DataPack) -> AnalysisTask? {
        if let selectedID = pack.selectedAnalysisTaskID,
           let task = pack.analysisTasks.first(where: { $0.id == selectedID }) {
            return task
        }
        return pack.analysisTasks.first
    }

    func reportsForCurrentTask(in pack: DataPack) -> [ImportedReport] {
        guard let task = currentAnalysisTask(in: pack) else { return [] }
        return taskReports(in: pack, task: task)
    }

    func normalizeAnalysisTasksForAllPacks() {
        var packs = workspace.dataPacks
        for index in packs.indices {
            ensureAnalysisTaskExists(in: &packs[index])
        }
        workspace.dataPacks = packs
    }

    func ensureAnalysisTaskExists(in pack: inout DataPack) {
        if pack.businessSpaceID == nil {
            pack.businessSpaceID = workspace.selectedBusinessSpaceID ?? workspace.businessSpaces.first?.id
        }
        let reportIDs = Set(pack.importedReports.map(\.id))
        pack.analysisTasks = pack.analysisTasks.map { task in
            var copy = task
            if copy.businessSpaceID == nil {
                copy.businessSpaceID = pack.businessSpaceID
                copy.businessSpaceSnapshot = businessSpace(for: pack, task: copy)?.snapshot
            }
            copy.selectedReportIDs = copy.selectedReportIDs.filter { reportIDs.contains($0) }.uniqued()
            copy.reportRoles = copy.reportRoles.filter { reportIDs.contains($0.key) }
            copy.relationshipProfile.primaryReportID = copy.relationshipProfile.primaryReportID.flatMap { reportIDs.contains($0) ? $0 : nil }
            copy.relationshipProfile.supportingReportIDs = copy.relationshipProfile.supportingReportIDs.filter { reportIDs.contains($0) }.uniqued()
            copy.relationshipProfile.incompatibleReportIDs = copy.relationshipProfile.incompatibleReportIDs.filter { reportIDs.contains($0) }.uniqued()
            return copy
        }
        if pack.analysisTasks.isEmpty {
            let space = businessSpace(for: pack)
            pack.analysisTasks = [AnalysisTask.emptyDefault(
                name: "新分析任务",
                businessSpaceID: space?.id,
                businessSpaceSnapshot: space?.snapshot
            )]
        }
        if pack.selectedAnalysisTaskID == nil || !pack.analysisTasks.contains(where: { $0.id == pack.selectedAnalysisTaskID }) {
            pack.selectedAnalysisTaskID = pack.analysisTasks.first?.id
        }
    }

    func currentAnalysisTaskIndex(in pack: DataPack) -> Int? {
        if let selectedID = pack.selectedAnalysisTaskID,
           let index = pack.analysisTasks.firstIndex(where: { $0.id == selectedID }) {
            return index
        }
        return pack.analysisTasks.indices.first
    }

    func taskReports(in pack: DataPack, task: AnalysisTask) -> [ImportedReport] {
        let activeIDs = Set(task.activeReportIDs)
        return pack.importedReports.filter { report in
            activeIDs.contains(report.id) && !report.isIgnoredFromAnalysis
        }
    }

    func aiObservationSignature(for task: AnalysisTask, reports: [ImportedReport]) -> String {
        let goalPart = task.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let reportPart = reports
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { report in
                let role = task.role(for: report.id).rawValue
                let importedAt = String(format: "%.3f", report.importedAt.timeIntervalSince1970)
                return "\(report.id.uuidString):\(role):\(importedAt)"
            }
            .joined(separator: "|")
        return "goal=\(goalPart)|reports=\(reportPart)"
    }

    func goalRequestsAnalysisTemplate(_ goal: String) -> Bool {
        let text = goal.normalizedKey
        return [
            "按上次",
            "上次一样",
            "和上次一样",
            "沿用上次",
            "套用模板",
            "一样的指标",
            "同样指标",
            "same_as_last"
        ].contains { text.contains($0.normalizedKey) }
    }

    func analysisTemplateReportRule(for report: ImportedReport, role: AnalysisTaskReportRole) -> AnalysisTemplateReportRule {
        let semantic = report.semanticProfile
        return AnalysisTemplateReportRule(
            role: role,
            reportNameKeywords: templateKeywords(from: [
                report.displayName,
                report.fileName,
                report.sourceFileName,
                report.sheetName ?? ""
            ], maxCount: 10),
            kind: report.kind,
            shape: report.shape,
            sourceFormat: report.sourceFormat,
            businessObjectKeywords: templateKeywords(from: [
                semantic.businessObject,
                semantic.purpose,
                semantic.summary
            ], maxCount: 12),
            fieldKeywords: templateKeywords(from: report.headers + semantic.dimensions, maxCount: 24),
            metricKeywords: templateKeywords(
                from: report.firstColumnValues + report.trendSummary.metricTrends.map(\.metricName) + semantic.keyMetrics,
                maxCount: 36
            ),
            notes: semantic.summary
        )
    }

    func matchAnalysisTemplate(
        _ template: AnalysisTemplateMemory,
        reports: [ImportedReport]
    ) -> [(rule: AnalysisTemplateReportRule, report: ImportedReport, role: AnalysisTaskReportRole, score: Double)] {
        var usedReportIDs = Set<UUID>()
        var matches: [(rule: AnalysisTemplateReportRule, report: ImportedReport, role: AnalysisTaskReportRole, score: Double)] = []
        let candidates = reports.filter { !$0.isIgnoredFromAnalysis }
        for rule in template.reportRules {
            let best = candidates
                .filter { !usedReportIDs.contains($0.id) }
                .map { report in
                    (report, analysisTemplateRuleMatchScore(rule, report: report))
                }
                .sorted { lhs, rhs in lhs.1 > rhs.1 }
                .first
            guard let best, best.1 >= 3 else { continue }
            usedReportIDs.insert(best.0.id)
            matches.append((rule, best.0, rule.role, best.1))
        }
        return matches
    }

    func analysisTemplateMatchScore(_ template: AnalysisTemplateMemory, reports: [ImportedReport]) -> Double {
        let matches = matchAnalysisTemplate(template, reports: reports)
        guard !template.reportRules.isEmpty else { return 0 }
        let coverage = Double(matches.count) / Double(template.reportRules.count)
        let confidence = matches.reduce(0) { $0 + min(12, $1.score) } / Double(max(1, template.reportRules.count))
        return coverage * 10 + confidence
    }

    func analysisTemplateRuleMatchScore(_ rule: AnalysisTemplateReportRule, report: ImportedReport) -> Double {
        let reportText = [
            report.displayName,
            report.fileName,
            report.sourceFileName,
            report.sheetName ?? "",
            report.kind.label,
            report.shape.label,
            report.headers.joined(separator: " "),
            report.firstColumnValues.joined(separator: " "),
            report.semanticProfile.summary,
            report.semanticProfile.purpose,
            report.semanticProfile.businessObject,
            report.semanticProfile.keyMetrics.joined(separator: " "),
            report.semanticProfile.dimensions.joined(separator: " ")
        ].joined(separator: " ").normalizedKey

        var score = 0.0
        if rule.kind == report.kind { score += 3 }
        if rule.shape == report.shape { score += 2 }
        if rule.sourceFormat == report.sourceFormat { score += 0.5 }
        score += Double(keywordHitCount(rule.reportNameKeywords, in: reportText)) * 2.2
        score += Double(keywordHitCount(rule.businessObjectKeywords, in: reportText)) * 1.4
        score += Double(keywordHitCount(rule.metricKeywords, in: reportText)) * 1.1
        score += Double(keywordHitCount(rule.fieldKeywords, in: reportText)) * 0.8
        return score
    }

    func keywordHitCount(_ keywords: [String], in normalizedText: String) -> Int {
        keywords
            .map(\.normalizedKey)
            .filter { $0.count >= 2 && normalizedText.contains($0) }
            .uniqued()
            .count
    }

    func templateKeywords(from values: [String], maxCount: Int) -> [String] {
        let separators = CharacterSet(charactersIn: " \t\r\n/_-·.()（）[]【】,，:：;；|")
        var result: [String] = []
        for raw in values {
            guard let value = raw.nilIfBlank else { continue }
            result.append(value)
            result.append(contentsOf: value.components(separatedBy: separators))
        }
        return result
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
            .uniqued()
            .prefix(maxCount)
            .map { $0 }
    }

    func currentTaskAnalysisPack(from pack: DataPack) -> DataPack {
        guard let task = currentAnalysisTask(in: pack) else { return pack }
        var analysisPack = pack
        analysisPack.importedReports = taskReports(in: pack, task: task)
        analysisPack.reportRelationshipProfile = task.relationshipProfile
        analysisPack.analysisTasks = [task]
        analysisPack.selectedAnalysisTaskID = task.id
        analysisPack.analysisReport = task.analysisReport.summary.isEmpty ? pack.analysisReport : task.analysisReport
        analysisPack.decisionMemo = task.decisionMemo.markdown.isEmpty ? pack.decisionMemo : task.decisionMemo
        return analysisPack
    }

    func refreshTaskRelationshipProfile(for pack: inout DataPack, forceReview: Bool) {
        ensureAnalysisTaskExists(in: &pack)
        guard let taskIndex = currentAnalysisTaskIndex(in: pack) else { return }
        let task = pack.analysisTasks[taskIndex]
        let activeReports = taskReports(in: pack, task: task)
        guard !activeReports.isEmpty else {
            pack.analysisTasks[taskIndex].relationshipProfile = .empty
            pack.reportRelationshipProfile = .empty
            return
        }

        let activeIDs = Set(activeReports.map(\.id))
        let currentPrimary = task.relationshipProfile.primaryReportID.flatMap { id in
            activeIDs.contains(id) ? id : nil
        }
        let rolePrimary = task.reportRoles.first { $0.value == .primaryBusiness && activeIDs.contains($0.key) }?.key
        let recommendedPrimary = activeReports
            .sorted { lhs, rhs in
                let lhsScore = reportPrimaryScore(lhs)
                let rhsScore = reportPrimaryScore(rhs)
                return lhsScore == rhsScore ? lhs.importedAt > rhs.importedAt : lhsScore > rhsScore
            }
            .first?.id
        let primaryID = currentPrimary ?? rolePrimary ?? recommendedPrimary
        let incompatible = task.selectedReportIDs.filter {
            task.reportRoles[$0] == .excluded && activeIDs.contains($0)
        } + task.relationshipProfile.incompatibleReportIDs.filter { activeIDs.contains($0) }
        let supporting = activeReports
            .map(\.id)
            .filter { $0 != primaryID && !incompatible.contains($0) }

        let shouldReview = activeReports.count > 1 && (forceReview || task.relationshipProfile.confirmationStatus != .confirmed)
        let profile = ReportRelationshipProfile(
            primaryReportID: primaryID,
            supportingReportIDs: supporting,
            incompatibleReportIDs: incompatible.uniqued(),
            periodConsistency: periodConsistencyText(for: activeReports),
            audienceConsistency: dimensionConsistencyText(for: activeReports, keywords: ["segment", "user", "用户", "人群", "客群"], label: "人群"),
            channelConsistency: dimensionConsistencyText(for: activeReports, keywords: ["channel", "渠道", "source", "来源"], label: "渠道"),
            versionConsistency: dimensionConsistencyText(for: activeReports, keywords: ["version", "版本", "app_version"], label: "版本"),
            experimentConsistency: dimensionConsistencyText(for: activeReports, keywords: ["experiment", "ab", "实验", "分桶"], label: "实验组"),
            confirmationStatus: activeReports.count <= 1 ? .confirmed : (shouldReview ? .needsReview : task.relationshipProfile.confirmationStatus),
            updatedAt: task.relationshipProfile.updatedAt
        )
        pack.analysisTasks[taskIndex].relationshipProfile = profile
        pack.reportRelationshipProfile = profile
    }

    func refreshTaskBusinessLinks(for pack: inout DataPack, forceReview: Bool) {
        ensureAnalysisTaskExists(in: &pack)
        guard let taskIndex = currentAnalysisTaskIndex(in: pack) else { return }
        let task = pack.analysisTasks[taskIndex]
        let existing = forceReview ? nil : task.businessLinkProfile
        if !forceReview,
           let existing,
           canReuseBusinessLinkProfile(existing, task: task, reports: pack.importedReports) {
            return
        }
        var profile = BusinessLinkAnalyzer.buildProfile(
            for: task,
            reports: pack.importedReports,
            preserving: existing
        )
        if forceReview, taskReports(in: pack, task: task).count > 1 {
            profile.confirmationStatus = .needsReview
        }
        pack.analysisTasks[taskIndex].businessLinkProfile = profile
    }

    private func canReuseBusinessLinkProfile(
        _ profile: BusinessLinkProfile,
        task: AnalysisTask,
        reports: [ImportedReport]
    ) -> Bool {
        guard profile.updatedAt != nil else { return false }
        let activeIDs = Set(task.activeReportIDs)
        let profileReportIDs = Set(profile.nodes.map(\.reportID))
        guard profileReportIDs == activeIDs else { return false }

        for node in profile.nodes where node.metricRole != task.role(for: node.reportID).label {
            return false
        }

        let reportByID = Dictionary(uniqueKeysWithValues: reports.map { ($0.id, $0) })
        for reportID in activeIDs {
            guard let report = reportByID[reportID],
                  !report.isIgnoredFromAnalysis,
                  (report.trendSummary.analysisVersion ?? 0) >= ReportTrendAnalyzer.currentAnalysisVersion else {
                return false
            }
        }
        return true
    }

    func reportPrimaryScore(_ report: ImportedReport) -> Int {
        var score = report.trendSummary.metricTrends.count
        if report.kind == .coreMetrics { score += 8 }
        if report.kind == .funnelMetrics { score += 7 }
        if report.shape == .pivotWide { score += 3 }
        if report.semanticStatus == .confirmed || report.semanticStatus == .autoInferred { score += 2 }
        return score
    }

    func periodConsistencyText(for reports: [ImportedReport]) -> String {
        guard reports.count > 1 else { return "单表，无需合并周期" }
        let signatures = reports.map { report -> String in
            let temporalHeaders = report.headers.filter { header in
                DateParsing.parse(header) != nil ||
                    header.normalizedKey.contains("week") ||
                    header.normalizedKey.contains("month") ||
                    header.normalizedKey.contains("date") ||
                    header.contains("周") ||
                    header.contains("月") ||
                    header.contains("日期")
            }
            if !temporalHeaders.isEmpty {
                return temporalHeaders.prefix(6).map(\.normalizedKey).joined(separator: "|")
            }
            return report.semanticProfile.grain.normalizedKey
        }
        let unique = Set(signatures.filter { !$0.isEmpty })
        if unique.count <= 1 {
            return "周期看起来一致"
        }
        return "多表周期可能不一致，需要确认主辅关系"
    }

    func dimensionConsistencyText(for reports: [ImportedReport], keywords: [String], label: String) -> String {
        guard reports.count > 1 else { return "单表，无需确认\(label)" }
        let matchedReports = reports.filter { report in
            let text = (report.headers + report.firstColumnValues + report.semanticProfile.dimensions).joined(separator: " ").normalizedKey
            return keywords.contains { text.contains($0.normalizedKey) }
        }
        if matchedReports.isEmpty {
            return "未发现明确\(label)字段"
        }
        if matchedReports.count == reports.count {
            return "所有参与表都包含\(label)相关字段，需确认口径是否一致"
        }
        return "部分表包含\(label)字段，需确认是否可合并"
    }

    func importReviewBlockerText(for pack: DataPack) -> String? {
        guard let task = currentAnalysisTask(in: pack) else {
            return "当前还没有分析任务，请先创建或选择一个分析任务。"
        }
        let activeReports = taskReports(in: pack, task: task)
        if activeReports.isEmpty && !pack.importedReports.isEmpty {
            return "当前分析任务还没有选择表。请在分析会话右侧“分析资料”加入本次要联动分析的表。"
        }
        let blockedSteps = activeReports.flatMap(\.blockingAuditSteps)
        if !blockedSteps.isEmpty {
            let reasons = blockedSteps.flatMap(\.warnings).prefix(3).joined(separator: "；")
            return "\(blockedSteps.count) 个问题无法进入分析\(reasons.isEmpty ? "" : "：\(reasons)")。请修正或忽略对应报表。"
        }
        let unresolvedSteps = activeReports.flatMap(\.unresolvedAuditSteps)
        if !unresolvedSteps.isEmpty {
            let reasons = unresolvedSteps.flatMap(\.warnings).prefix(3).joined(separator: "；")
            return "\(unresolvedSteps.count) 个问题需要确认\(reasons.isEmpty ? "" : "：\(reasons)")。可以修正类型、确认口径、提问 AI 或接受低风险。"
        }
        if activeReports.count > 1 && task.businessLinkProfile.confirmationStatus != .confirmed {
            return "当前任务的业务链路尚未确认。请确认主业务、影响来源、结果指标和上下游关系后再进入分析。"
        }
        return nil
    }

    func upsertKnowledgeEntry(_ entry: KnowledgeEntry) {
        if let sourceID = entry.sourceID,
           let index = workspace.knowledgeEntries.firstIndex(where: { $0.sourceID == sourceID }) {
            workspace.knowledgeEntries[index] = entry
        } else if let index = workspace.knowledgeEntries.firstIndex(where: { $0.id == entry.id }) {
            workspace.knowledgeEntries[index] = entry
        } else {
            workspace.knowledgeEntries.insert(entry, at: 0)
        }
        workspace.knowledgeEntries.sort { ($0.sourceUpdatedAt ?? $0.sourceCreatedAt ?? $0.createdAt) > ($1.sourceUpdatedAt ?? $1.sourceCreatedAt ?? $1.createdAt) }
    }

    func normalizeFieldDefinitionsForCurrentReports(allowDiskRecovery: Bool = false) {
        var packs = workspace.dataPacks
        for index in packs.indices where !packs[index].importedReports.isEmpty {
            let packSnapshot = packs[index]
            packs[index].importedReports = packSnapshot.importedReports.map { report in
                let recovered = allowDiskRecovery
                    ? recoverFullReportRowsIfPossible(report, pack: packSnapshot)
                    : report
                var normalized = DataImportService.reportWithFieldMetadata(recovered)
                let detection = DataImportService.recognizedKind(for: normalized)
                if normalized.kind == .generic || normalized.detectedConfidence <= 0.5 {
                    normalized.kind = detection.kind
                    normalized.detectedConfidence = detection.confidence
                }
                if normalized.rowCount == 0, normalized.headers.count > 200,
                   !normalized.parseWarnings.contains(where: { $0.contains("可能是旧版解析") }) {
                    normalized.parseWarnings.append("可能是旧版解析结果：行数为 0 但字段数异常偏高，建议重新导入该 CSV。")
                }
                let inference = ReportSemanticInferencer.infer(report: normalized)
                let profileWasEmpty = normalized.semanticProfile.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let confidenceWasMissing = normalized.semanticConfidence <= 0
                let hasUserSemanticMessage = normalized.understandingMessages.contains { $0.role == .user }
                let canRefreshAutoProfile = !hasUserSemanticMessage && normalized.semanticStatus != .confirmed
                if profileWasEmpty || canRefreshAutoProfile {
                    normalized.semanticProfile = inference.profile
                }
                if confidenceWasMissing {
                    normalized.semanticConfidence = inference.confidence
                }
                if profileWasEmpty || confidenceWasMissing {
                    if normalized.understandingMessages.isEmpty, let message = inference.message {
                        normalized.understandingMessages.append(message)
                    }
                }
                if normalized.semanticStatus == .needsReview && normalized.semanticConfidence >= 0.66 {
                    normalized.semanticStatus = .autoInferred
                } else if normalized.semanticStatus == .inProgress && normalized.semanticConfidence >= 0.82 && !hasUserSemanticMessage {
                    normalized.semanticStatus = .autoInferred
                }
                return normalized
            }
            packs[index].fieldDefinitions = DataImportService.rebuildFieldDefinitions(
                for: packs[index].importedReports,
                preserving: packs[index].fieldDefinitions
            )
        }
        workspace.dataPacks = packs
    }

    func recoverFullReportRowsIfPossible(_ report: ImportedReport, pack: DataPack) -> ImportedReport {
        let rowDataLooksTruncated = report.rowCount > report.sampleRows.count
        let trendLooksTruncated = report.shape == .pivotWide && report.firstColumnValues.count > report.trendSummary.metricTrends.count
        guard rowDataLooksTruncated || trendLooksTruncated else { return report }

        var sourceAccessURL: URL?
        if let sourcePath = pack.sourcePath?.nilIfBlank {
            let fallbackURL = URL(fileURLWithPath: sourcePath)
            let resolution = SecurityScopedResource.resolve(
                bookmarkData: pack.sourceBookmarkData,
                fallbackURL: fallbackURL
            )
            sourceAccessURL = resolution.url
            if let refreshedBookmarkData = resolution.refreshedBookmarkData,
               let packIndex = workspace.dataPacks.firstIndex(where: { $0.id == pack.id }) {
                workspace.dataPacks[packIndex].sourceBookmarkData = refreshedBookmarkData
                save(policy: .deferred)
            }
        }

        let urls = candidateCSVURLs(fileName: report.fileName, pack: pack, resolvedSourceURL: sourceAccessURL)
        let recover: () -> ImportedReport? = {
            for url in urls {
                guard FileManager.default.fileExists(atPath: url.path),
                      let table = try? CSVParser.parse(fileURL: url),
                      table.headers.first?.normalizedKey == report.headers.first?.normalizedKey else {
                    continue
                }

                var recovered = report
                recovered.rowCount = table.rows.count
                recovered.headers = table.headers
                recovered.firstColumnValues = table.firstColumnValues
                recovered.fieldExamples = table.fieldExamples
                recovered.sampleRows = DataImportService.storedRows(for: table)
                recovered.storedDataRows = TableContextPackageBuilder.storedRows(for: table)
                recovered.rawRows = table.rawRows
                recovered.shape = table.shape
                recovered.parseWarnings = table.parseWarnings
                recovered.cellTypeHints = table.cellTypeHints
                recovered.originalEncoding = table.originalEncoding
                recovered.delimiter = table.delimiter
                let detection = DataImportService.recognizedKind(for: recovered)
                if recovered.kind == .generic || recovered.detectedConfidence <= detection.confidence {
                    recovered.kind = detection.kind
                    recovered.detectedConfidence = detection.confidence
                }
                recovered.timeAxisProfile = ReportTimeAxisDetector.detect(table: table)
                recovered.trendSummary = ReportTrendAnalyzer.analyze(
                    fileName: recovered.fileName,
                    kind: recovered.kind,
                    table: table,
                    timeAxisProfile: recovered.timeAxisProfile
                )
                recovered.tableContextCoverage = TableContextPackageBuilder.build(for: recovered).coverage
                return recovered
            }
            return nil
        }

        if let sourceAccessURL,
           let recovered = SecurityScopedResource.access(sourceAccessURL, recover) {
            return recovered
        }
        if sourceAccessURL == nil, let recovered = recover() {
            return recovered
        }
        return report
    }

    func candidateCSVURLs(fileName: String, pack: DataPack, resolvedSourceURL: URL? = nil) -> [URL] {
        var urls: [URL] = []
        if let sourcePath = pack.sourcePath?.nilIfBlank {
            let sourceURL = resolvedSourceURL ?? URL(fileURLWithPath: sourcePath)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                urls.append(sourceURL.appendingPathComponent(fileName))
            } else {
                urls.append(sourceURL.deletingLastPathComponent().appendingPathComponent(fileName))
            }
        }
        urls.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(fileName))
        urls.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Playground").appendingPathComponent(fileName))
        urls.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").appendingPathComponent(fileName))

        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    func reportImportKey(for report: ImportedReport) -> String {
        if let key = report.sourceMetadata?.stableImportKey {
            return key
        }
        return [
            report.sourceFormat.rawValue,
            (report.sourceFileName.nilIfBlank ?? report.fileName).normalizedKey,
            report.sheetName?.normalizedKey ?? "",
            report.userReportAlias.normalizedKey
        ].joined(separator: "|")
    }

    func reportImportBaseKey(for report: ImportedReport) -> String {
        if let key = report.sourceMetadata?.stableImportKey {
            return key
        }
        return [
            report.sourceFormat.rawValue,
            (report.sourceFileName.nilIfBlank ?? report.fileName).normalizedKey,
            report.sheetName?.normalizedKey ?? ""
        ].joined(separator: "|")
    }

    func dedupedReports(_ reports: [ImportedReport]) -> [ImportedReport] {
        var result: [ImportedReport] = []
        for report in reports.sorted(by: { $0.importedAt > $1.importedAt }) {
            let key = reportImportBaseKey(for: report)
            if let existingIndex = result.firstIndex(where: { reportImportBaseKey(for: $0) == key }) {
                var kept = result[existingIndex]
                if kept.userReportAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    kept.userReportAlias = report.userReportAlias
                }
                result[existingIndex] = kept
            } else {
                result.append(report)
            }
        }
        return result
    }

    func seedFieldDictionaryMemoriesFromExistingPacks() {
        for pack in workspace.dataPacks {
            syncFieldDictionaryMemories(from: pack)
        }
    }

    func applyFieldDictionaryMemoriesToAllPacks() {
        var packs = workspace.dataPacks
        for index in packs.indices {
            _ = applyFieldDictionaryMemories(to: &packs[index])
        }
        workspace.dataPacks = packs
    }

    @discardableResult
    func applyFieldDictionaryMemories(to pack: inout DataPack) -> Int {
        var appliedCount = 0
        for index in pack.fieldDefinitions.indices where !pack.fieldDefinitions[index].isConfirmed {
            appliedCount += applyFieldDictionaryMemory(to: &pack.fieldDefinitions[index])
        }
        return appliedCount
    }

    @discardableResult
    func applyFieldDictionaryMemory(to definition: inout ReportFieldDefinition) -> Int {
        guard let memory = matchingFieldDictionaryMemory(for: definition) else {
            return 0
        }

        definition.meaning = memory.meaning
        definition.dataType = memory.dataType
        definition.notes = memory.notes
        definition.isConfirmed = true
        definition.updatedAt = memory.updatedAt
        return 1
    }

    func matchingFieldDictionaryMemory(for definition: ReportFieldDefinition) -> FieldDictionaryMemory? {
        let exactKey = FieldDictionaryMemory.matchKey(
            reportName: definition.reportName,
            reportKind: definition.reportKind,
            fieldName: definition.fieldName
        )
        if let exact = workspace.fieldDictionaryMemories
            .filter({ $0.matchKey == exactKey })
            .sorted(by: { $0.updatedAt > $1.updatedAt })
            .first {
            return exact
        }

        let candidates = workspace.fieldDictionaryMemories
            .filter {
                $0.reportKind == definition.reportKind &&
                $0.fieldName.normalizedKey == definition.fieldName.normalizedKey
            }
            .sorted { $0.updatedAt > $1.updatedAt }
        guard let latest = candidates.first else { return nil }

        let distinctDefinitions = Set(candidates.map {
            "\($0.meaning.trimmingCharacters(in: .whitespacesAndNewlines))|\($0.dataType.normalizedKey)|\($0.notes.trimmingCharacters(in: .whitespacesAndNewlines))"
        })
        return distinctDefinitions.count == 1 ? latest : nil
    }

    func syncFieldDictionaryMemories(from pack: DataPack) {
        for definition in pack.fieldDefinitions where definition.isConfirmed && !definition.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            upsertFieldDictionaryMemory(from: definition, packName: pack.name)
        }
        workspace.fieldDictionaryMemories.sort { $0.updatedAt > $1.updatedAt }
    }

    func upsertFieldDictionaryMemory(from definition: ReportFieldDefinition, packName: String) {
        let key = FieldDictionaryMemory.matchKey(
            reportName: definition.reportName,
            reportKind: definition.reportKind,
            fieldName: definition.fieldName
        )
        let now = Date()
        if let index = workspace.fieldDictionaryMemories.firstIndex(where: { $0.matchKey == key }) {
            workspace.fieldDictionaryMemories[index].updatedAt = now
            workspace.fieldDictionaryMemories[index].meaning = definition.meaning
            workspace.fieldDictionaryMemories[index].dataType = definition.dataType
            workspace.fieldDictionaryMemories[index].notes = definition.notes
            workspace.fieldDictionaryMemories[index].exampleValue = definition.exampleValue
            workspace.fieldDictionaryMemories[index].sourcePackName = packName
        } else {
            workspace.fieldDictionaryMemories.append(FieldDictionaryMemory(
                id: UUID(),
                createdAt: now,
                updatedAt: now,
                reportName: definition.reportName,
                reportKind: definition.reportKind,
                fieldName: definition.fieldName,
                meaning: definition.meaning,
                dataType: definition.dataType,
                notes: definition.notes,
                exampleValue: definition.exampleValue,
                sourcePackName: packName
            ))
        }
    }

    func fieldDictionaryDefinition(fieldID: UUID?, in pack: DataPack) -> ReportFieldDefinition? {
        if let fieldID, let definition = pack.fieldDefinitions.first(where: { $0.id == fieldID }) {
            return definition
        }
        return nextUnconfirmedFieldDefinition(in: pack) ?? pack.fieldDefinitions.first
    }

    func nextUnconfirmedFieldDefinition(in pack: DataPack) -> ReportFieldDefinition? {
        pack.fieldDefinitions.first { !$0.isConfirmed }
    }

    func generateFieldDictionaryQuestion(for definition: ReportFieldDefinition, settings: AISettings) async -> String {
        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return FieldDictionaryAIService.fallbackQuestion(for: definition)
        }

        do {
            let output = try await AIAnalysisService().runAnalysis(
                prompt: FieldDictionaryAIService.questionPrompt(for: definition),
                settings: settings
            )
            return output.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                ?? FieldDictionaryAIService.fallbackQuestion(for: definition)
        } catch {
            return "\(FieldDictionaryAIService.fallbackQuestion(for: definition))\n\nAI 提问生成失败，先使用本地问题继续：\(error.localizedDescription)"
        }
    }

    func applyFieldDictionaryInterpretation(_ interpretation: FieldDictionaryInterpretation, fieldID: UUID) {
        var updatedDefinition: ReportFieldDefinition?
        let packName = selectedPack?.name ?? ""
        updateSelectedPack { pack in
            guard let index = pack.fieldDefinitions.firstIndex(where: { $0.id == fieldID }) else { return }
            pack.fieldDefinitions[index].meaning = interpretation.meaning
            pack.fieldDefinitions[index].dataType = interpretation.dataType
            pack.fieldDefinitions[index].notes = interpretation.notes
            pack.fieldDefinitions[index].isConfirmed = true
            pack.fieldDefinitions[index].updatedAt = Date()
            updatedDefinition = pack.fieldDefinitions[index]
        }
        if let updatedDefinition {
            upsertFieldDictionaryMemory(from: updatedDefinition, packName: packName)
            save()
        }
    }

    func appendFieldDictionaryMessage(_ message: FieldDictionaryMessage) {
        updateSelectedPack { pack in
            pack.fieldDictionaryMessages.append(message)
            pack.fieldDictionaryMessages.sort { $0.createdAt < $1.createdAt }
            if pack.fieldDictionaryMessages.count > 300 {
                pack.fieldDictionaryMessages = Array(pack.fieldDictionaryMessages.suffix(300))
            }
        }
    }

    func appendCorrectionMessage(_ message: CorrectionMessage) {
        updateSelectedPack { pack in
            pack.correctionMessages.append(message)
            pack.correctionMessages.sort { $0.createdAt < $1.createdAt }
        }
    }

    func parseTags(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: ",，;；\n\t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
    }

    func safeFileName(_ text: String) -> String {
        let illegalCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = text
            .components(separatedBy: illegalCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "decision-report" : cleaned
    }

    private var wordExportTimestamp: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter
    }

    func save(policy: WorkspaceSavePolicy = .immediate) {
        if let workspaceReadOnlySafeModeMessage {
            workspaceSaveFailureMessage = workspaceReadOnlySafeModeMessage
            statusText = workspaceReadOnlySafeModeMessage
            return
        }
        if isBatchingWorkspaceSaves {
            switch policy {
            case .immediate:
                batchedWorkspaceSavePolicy = .immediate
            case .deferred:
                if batchedWorkspaceSavePolicy == nil {
                    batchedWorkspaceSavePolicy = .deferred
                }
            case .none:
                break
            }
            return
        }

        switch policy {
        case .immediate:
            workspaceSaveGeneration += 1
            let generation = workspaceSaveGeneration
            let snapshot = workspace
            deferredWorkspaceSaveTask?.cancel()
            deferredWorkspaceSaveTask = nil
            let failureHandler = workspaceSaveFailureHandler()
            let diskWriter = workspaceDiskWriter
            Task.detached(priority: .userInitiated) {
                await diskWriter.save(snapshot, generation: generation, onFailure: failureHandler)
            }
        case .deferred:
            scheduleDeferredWorkspaceSave()
        case .none:
            return
        }
    }

    @discardableResult
    public func flushWorkspaceToDisk() async -> Bool {
        if workspaceReadOnlySafeModeMessage != nil {
            return true
        }
        deferredWorkspaceSaveTask?.cancel()
        deferredWorkspaceSaveTask = nil
        workspaceSaveGeneration += 1
        let generation = workspaceSaveGeneration
        let snapshot = workspace
        let failureHandler = workspaceSaveFailureHandler()
        return await workspaceDiskWriter.flush(snapshot, generation: generation, onFailure: failureHandler)
    }

    private func scheduleDeferredWorkspaceSave() {
        if let workspaceReadOnlySafeModeMessage {
            workspaceSaveFailureMessage = workspaceReadOnlySafeModeMessage
            statusText = workspaceReadOnlySafeModeMessage
            return
        }
        workspaceSaveGeneration += 1
        let generation = workspaceSaveGeneration
        deferredWorkspaceSaveTask?.cancel()
        let failureHandler = workspaceSaveFailureHandler()
        deferredWorkspaceSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard self.workspaceSaveGeneration == generation else { return }
            self.deferredWorkspaceSaveTask = nil
            let snapshot = self.workspace
            let diskWriter = self.workspaceDiskWriter
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) {
                await diskWriter.save(snapshot, generation: generation, onFailure: failureHandler)
            }.value
        }
    }

    private func workspaceSaveFailureHandler() -> @Sendable (String) -> Void {
        { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.workspaceSaveFailureMessage = message
                self.statusText = message
            }
        }
    }

    nonisolated static var workspaceURL: URL {
        if let overridePath = ProcessInfo.processInfo.environment[workspacePathEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !overridePath.isEmpty {
            return URL(fileURLWithPath: (overridePath as NSString).expandingTildeInPath)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("IterationPilot", isDirectory: true).appendingPathComponent("workspace.json")
    }

    nonisolated static func applyEnvironmentOverrides(to workspace: inout ProductWorkspace) {
        let environment = ProcessInfo.processInfo.environment
        if let endpoint = environment[aiEndpointEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !endpoint.isEmpty {
            workspace.aiSettings.endpoint = endpoint
        }
        if let model = environment[aiModelEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !model.isEmpty {
            workspace.aiSettings.model = model
        }
        if let apiKey = environment[aiAPIKeyEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !apiKey.isEmpty {
            workspace.aiSettings.apiKey = apiKey
        }
        if let systemPrompt = environment[aiSystemPromptEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !systemPrompt.isEmpty {
            workspace.aiSettings.systemPrompt = systemPrompt
        }
    }

    nonisolated static func loadWorkspace() -> ProductWorkspace? {
        if case .loaded(let workspace) = loadWorkspaceResult() {
            return workspace
        }
        return nil
    }

    nonisolated static func loadWorkspaceResult() -> WorkspaceLoadResult {
        let url = workspaceURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }

        do {
            let data = try Data(contentsOf: url)
            if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let schemaVersion = object["schemaVersion"] as? Int,
               schemaVersion > ProductWorkspace.currentSchemaVersion {
                return .unsupportedVersion(found: schemaVersion, supported: ProductWorkspace.currentSchemaVersion)
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var workspace = try decoder.decode(ProductWorkspace.self, from: data)
            try migrateWorkspaceToCurrentSchema(&workspace)
            return .loaded(workspace)
        } catch let error as AppSecureStorage.PersistenceError {
            return .credentialUnavailable(error.localizedDescription)
        } catch {
            let backupURL = backupCorruptWorkspace(at: url)
            return .corrupt(errorDescription: error.localizedDescription, backupURL: backupURL)
        }
    }

    nonisolated static func migrateWorkspaceToCurrentSchema(_ workspace: inout ProductWorkspace) throws {
        guard workspace.schemaVersion <= ProductWorkspace.currentSchemaVersion else {
            throw CocoaError(.coderReadCorrupt)
        }
        while workspace.schemaVersion < ProductWorkspace.currentSchemaVersion {
            switch workspace.schemaVersion {
            case 1:
                workspace.schemaVersion = 2
            default:
                throw CocoaError(.coderReadCorrupt)
            }
        }
    }

    nonisolated static func backupCorruptWorkspace(at url: URL) -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let backupURL = url
            .deletingLastPathComponent()
            .appendingPathComponent("workspace.corrupt-\(timestamp).json")
        do {
            try FileManager.default.copyItem(at: url, to: backupURL)
            return backupURL
        } catch {
            let fallbackURL = url
                .deletingLastPathComponent()
                .appendingPathComponent("workspace.corrupt-\(timestamp)-\(UUID().uuidString).json")
            do {
                try FileManager.default.copyItem(at: url, to: fallbackURL)
                return fallbackURL
            } catch {
                return nil
            }
        }
    }

    nonisolated static func saveWorkspace(_ workspace: ProductWorkspace) throws {
        let url = workspaceURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(workspace)
        try data.write(to: url, options: [.atomic])
    }

    static func migrateLegacyTavilyAPIKey(in workspace: inout ProductWorkspace) {
        guard workspace.searchSettings.tavilyAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        guard let legacyKey = workspace.referenceSources
            .first(where: { $0.collectorType == .tavilySearch && !$0.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .apiKey
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !legacyKey.isEmpty else {
            return
        }
        workspace.searchSettings.tavilyAPIKey = legacyKey
        workspace.referenceSources = workspace.referenceSources.map { source in
            var copy = source
            copy.apiKey = ""
            return copy
        }
    }
}
