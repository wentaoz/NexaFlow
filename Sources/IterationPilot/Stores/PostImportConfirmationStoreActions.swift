import Foundation

struct PostImportAnalysisConfirmation: Identifiable, Equatable {
    var id = UUID()
    var packID: UUID
    var title: String
    var detail: String
    var reportIDs: [UUID]
    var newReportIDs: Set<UUID> = []
    var currentTaskReportIDs: Set<UUID> = []
    var availableExtraReportIDs: [UUID] = []
    var defaultSelectedReportIDs: Set<UUID>
    var defaultReportRoles: [UUID: AnalysisTaskReportRole]
    var poolOnlyButtonTitle = "只导入，不加入"
    var poolOnlyStatusText = "已导入，可稍后在分析资料中加入本次分析。"
    var closeHelpText = "关闭。导入数据会保留，不会加入当前分析。"
    var emptyReportText = "本次导入的报表已经不存在。"
}

extension ProductWorkflowStore {
    func presentPostImportConfirmation(
        packID: UUID,
        reportIDs: [UUID],
        newReportIDs explicitNewReportIDs: Set<UUID>? = nil,
        defaultSelectedReportIDs explicitDefaultSelectedReportIDs: Set<UUID>? = nil,
        title: String = "导入完成，确认本次分析表",
        detail: String,
        poolOnlyButtonTitle: String = "只导入，不加入",
        poolOnlyStatusText: String = "已导入，可稍后在分析资料中加入本次分析。",
        closeHelpText: String = "关闭。导入数据会保留，不会加入当前分析。",
        emptyReportText: String = "本次导入的报表已经不存在。"
    ) {
        let requestedReportIDs = reportIDs.uniqued()
        guard !requestedReportIDs.isEmpty else { return }

        selectedPackID = packID
        ensureAnalysisSessionAfterReportImport()

        guard let pack = selectedPack else { return }
        let availableReportIDs = Set(pack.importedReports.map(\.id))
        let visibleReportIDs = requestedReportIDs.filter { availableReportIDs.contains($0) }
        guard !visibleReportIDs.isEmpty else { return }

        let task = currentAnalysisTask(in: pack)
        let existingRoles = task?.reportRoles ?? [:]
        let currentTaskReportIDs = task?.activeReportIDs.filter { availableReportIDs.contains($0) } ?? []
        let mainReportIDs = (currentTaskReportIDs + visibleReportIDs).uniqued()
        let selectableReportIDs = pack.importedReports
            .filter { !$0.isIgnoredFromAnalysis }
            .map(\.id)
        let availableExtraReportIDs = selectableReportIDs.filter { !mainReportIDs.contains($0) }
        let defaultSelectedIDs = explicitDefaultSelectedReportIDs ?? Set(mainReportIDs)
        let newReportIDs = explicitNewReportIDs ?? Set(visibleReportIDs)
        let hasPrimaryReport = defaultSelectedIDs.contains { reportID in
            if let role = existingRoles[reportID] {
                return role == .primaryBusiness
            }
            return task?.role(for: reportID) == .primaryBusiness
        }
        var defaultRoles: [UUID: AnalysisTaskReportRole] = [:]
        let roleCandidateIDs = (mainReportIDs + availableExtraReportIDs).uniqued()
        for (offset, reportID) in roleCandidateIDs.enumerated() {
            defaultRoles[reportID] = existingRoles[reportID] ?? (!hasPrimaryReport && defaultSelectedIDs.contains(reportID) && offset == 0 ? .primaryBusiness : .evidence)
        }

        pendingPostImportConfirmation = PostImportAnalysisConfirmation(
            packID: packID,
            title: title,
            detail: detail,
            reportIDs: mainReportIDs,
            newReportIDs: newReportIDs,
            currentTaskReportIDs: Set(currentTaskReportIDs),
            availableExtraReportIDs: availableExtraReportIDs,
            defaultSelectedReportIDs: defaultSelectedIDs,
            defaultReportRoles: defaultRoles,
            poolOnlyButtonTitle: poolOnlyButtonTitle,
            poolOnlyStatusText: poolOnlyStatusText,
            closeHelpText: closeHelpText,
            emptyReportText: emptyReportText
        )
        requestedSidebarSelection = .sessions
        isAnalysisInfoSidebarVisible = false
        statusText = detail
    }

    @discardableResult
    func presentCurrentPackReportSelectionConfirmation(force: Bool = true) -> Bool {
        guard let pack = selectedPack else {
            statusText = "请先导入本地表或接入 Tableau"
            return false
        }
        let selectableReports = pack.importedReports.filter { !$0.isIgnoredFromAnalysis }
        guard !selectableReports.isEmpty else {
            statusText = "当前没有可加入本次分析的表。请先导入本地表或 Tableau。"
            return false
        }
        if !force, !reportsForCurrentTask(in: pack).isEmpty {
            return false
        }

        let currentReportIDs = reportsForCurrentTask(in: pack).map(\.id)
        let reportIDs = currentReportIDs.isEmpty ? selectableReports.map(\.id) : currentReportIDs
        let defaultSelectedReportIDs = currentReportIDs.isEmpty ? Set(reportIDs) : Set(currentReportIDs)
        presentPostImportConfirmation(
            packID: pack.id,
            reportIDs: reportIDs,
            newReportIDs: [],
            defaultSelectedReportIDs: defaultSelectedReportIDs,
            title: "确认「\(pack.name)」的本次分析表",
            detail: "当前任务还没有选择报表。请选择本轮要一起分析的表，确认后即可直接提问。",
            poolOnlyButtonTitle: "暂不加入",
            poolOnlyStatusText: "暂未加入表。可以稍后在分析资料中选择本次分析表。",
            closeHelpText: "关闭。不会修改当前任务选表。",
            emptyReportText: "这些报表已经不存在。"
        )
        return true
    }

    func keepPostImportReportsInPool(draftID: UUID) {
        guard pendingPostImportConfirmation?.id == draftID else { return }
        let status = pendingPostImportConfirmation?.poolOnlyStatusText
        pendingPostImportConfirmation = nil
        requestedSidebarSelection = .sessions
        isAnalysisInfoSidebarVisible = false
        statusText = status ?? "已导入，可稍后在分析资料中加入本次分析。"
    }

    func confirmPostImportReportsForAnalysis(
        draftID: UUID,
        selectedReportIDs: Set<UUID>,
        reportRoles: [UUID: AnalysisTaskReportRole],
        prompt: String
    ) {
        guard let draft = pendingPostImportConfirmation, draft.id == draftID else { return }
        pendingPostImportConfirmation = nil
        selectedPackID = draft.packID

        var selectedIDs: [UUID] = []
        updateSelectedPack(saveImmediately: false) { pack in
            ensureAnalysisTaskExists(in: &pack)
            guard let taskIndex = currentAnalysisTaskIndex(in: pack) else { return }

            let availableReportIDs = Set(pack.importedReports.map(\.id))
            let manageableReportIDs = (draft.reportIDs + draft.availableExtraReportIDs).uniqued().filter { availableReportIDs.contains($0) }
            selectedIDs = manageableReportIDs.filter { selectedReportIDs.contains($0) }
            let selectedSet = Set(selectedIDs)

            for reportID in manageableReportIDs where !selectedSet.contains(reportID) {
                pack.analysisTasks[taskIndex].selectedReportIDs.removeAll { $0 == reportID }
                pack.analysisTasks[taskIndex].reportRoles.removeValue(forKey: reportID)
                if pack.analysisTasks[taskIndex].relationshipProfile.primaryReportID == reportID {
                    pack.analysisTasks[taskIndex].relationshipProfile.primaryReportID = nil
                }
                pack.analysisTasks[taskIndex].relationshipProfile.supportingReportIDs.removeAll { $0 == reportID }
                pack.analysisTasks[taskIndex].relationshipProfile.incompatibleReportIDs.removeAll { $0 == reportID }
            }

            let hasPrimaryReport = pack.analysisTasks[taskIndex].activeReportIDs.contains {
                pack.analysisTasks[taskIndex].role(for: $0) == .primaryBusiness
            }
            for (offset, reportID) in selectedIDs.enumerated() {
                if !pack.analysisTasks[taskIndex].selectedReportIDs.contains(reportID) {
                    pack.analysisTasks[taskIndex].selectedReportIDs.append(reportID)
                }
                let role = reportRoles[reportID] ?? (!hasPrimaryReport && offset == 0 ? .primaryBusiness : .evidence)
                pack.analysisTasks[taskIndex].reportRoles[reportID] = role
                if role == .primaryBusiness {
                    pack.analysisTasks[taskIndex].relationshipProfile.primaryReportID = reportID
                }
            }

            pack.analysisTasks[taskIndex].updatedAt = Date()
            markPackNeedsReview(&pack)
            refreshTaskRelationshipProfile(for: &pack, forceReview: true)
            refreshTaskBusinessLinks(for: &pack, forceReview: true)
            refreshAuditState(for: &pack)
        }
        save()
        selectOrCreateAnalysisSessionForCurrentTask()
        if let selectedPack {
            syncSelectedAnalysisSessionWithCurrentTask(pack: selectedPack)
        }

        requestedSidebarSelection = .sessions
        isAnalysisInfoSidebarVisible = false

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedIDs.isEmpty {
            focusAnalysisComposerToken = UUID()
            statusText = "当前分析任务没有选择表。请先加入至少 1 张表，再发送给 AI。"
        } else if trimmedPrompt.isEmpty {
            focusAnalysisComposerToken = UUID()
            statusText = "已将 \(selectedIDs.count) 张报表加入当前分析。可以直接在底部输入问题。"
        } else {
            sendAnalysisSessionMessage(trimmedPrompt, mode: .fullReanalysis)
        }
    }
}
