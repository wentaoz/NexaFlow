import Foundation

@MainActor
extension ProductWorkflowStore {
    var tableauSourcesForSelectedBusinessSpace: [TableauSource] {
        guard let spaceID = selectedBusinessSpace?.id else { return [] }
        return workspace.tableauSources
            .filter { $0.businessSpaceID == spaceID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var tableauSyncRecordsForSelectedBusinessSpace: [TableauSyncRecord] {
        guard let spaceID = selectedBusinessSpace?.id else { return [] }
        return workspace.tableauSyncRecords
            .filter { $0.businessSpaceID == spaceID }
            .sorted { $0.startedAt > $1.startedAt }
    }

    func createTableauSource(_ draft: TableauSourceDraft) {
        guard let spaceID = selectedBusinessSpace?.id else {
            statusText = "请先选择业务空间"
            return
        }
        let displayName = draft.displayName.nilIfBlank
            ?? draft.workbookFilter.nilIfBlank
            ?? "Tableau 数据源"
        let source = TableauSource(
            businessSpaceID: spaceID,
            displayName: displayName,
            baseURL: draft.baseURL,
            siteContentURL: draft.siteContentURL,
            patName: draft.patName,
            patToken: draft.patToken,
            projectFilter: draft.projectFilter,
            workbookFilter: draft.workbookFilter
        )
        workspace.tableauSources.insert(source, at: 0)
        save()
        statusText = "已添加 Tableau 连接：\(displayName)"
    }

    func updateTableauSource(_ source: TableauSource, _ transform: (inout TableauSource) -> Void) {
        guard let index = workspace.tableauSources.firstIndex(where: { $0.id == source.id }) else { return }
        var copy = workspace.tableauSources[index]
        transform(&copy)
        copy.updatedAt = Date()
        workspace.tableauSources[index] = copy
        save(policy: .deferred)
    }

    func deleteTableauSource(_ source: TableauSource) {
        workspace.tableauSources.removeAll { $0.id == source.id }
        save()
        statusText = "已删除 Tableau 连接：\(source.displayName)"
    }

    func testTableauSource(_ source: TableauSource) {
        testingTableauSourceIDs.insert(source.id)
        statusText = "正在测试 Tableau 连接..."
        Task { @MainActor in
            defer { testingTableauSourceIDs.remove(source.id) }
            do {
                let message = try await TableauService().testConnection(source: source)
                updateTableauSource(source) {
                    $0.lastTestedAt = Date()
                    $0.lastStatusMessage = message
                }
                statusText = message
            } catch {
                updateTableauSource(source) {
                    $0.lastTestedAt = Date()
                    $0.lastStatusMessage = error.localizedDescription
                }
                statusText = error.localizedDescription
            }
        }
    }

    func importTableauViewsIntoCurrentTask(source: TableauSource, views: [TableauView]) {
        guard !views.isEmpty else {
            statusText = "请选择至少一个 Tableau 视图"
            return
        }
        guard let spaceID = selectedBusinessSpace?.id else {
            statusText = "请先选择业务空间"
            return
        }

        let startedAt = Date()
        importingTableauSourceIDs.insert(source.id)
        statusText = "正在从 Tableau 导入 \(views.count) 个视图..."
        Task { @MainActor in
            defer { importingTableauSourceIDs.remove(source.id) }
            do {
                let result = try await TableauService().importViews(source: source, views: views)
                let importSummary = mergeTableauImportResult(result, source: source)
                let packID = importSummary.packID
                let targetSummary = packID.flatMap { id in
                    workspace.dataPacks.first(where: { $0.id == id })?.reportSourceSummary
                } ?? "当前分析资料"
                let successMessage = "已将 \(result.importedViewCount) 个 Tableau 视图导入当前分析资料（\(targetSummary)）"
                recordTableauSync(
                    sourceID: source.id,
                    businessSpaceID: spaceID,
                    dataPackID: packID,
                    startedAt: startedAt,
                    status: .success,
                    importedViewCount: result.importedViewCount,
                    message: successMessage
                )
                updateTableauSource(source) {
                    $0.lastImportAt = Date()
                    $0.lastStatusMessage = successMessage
                }
                requestedSidebarSelection = .sessions
                isAnalysisInfoSidebarVisible = false
                if let packID {
                    presentPostImportConfirmation(
                        packID: packID,
                        reportIDs: importSummary.reportIDs,
                        detail: "已导入 \(importSummary.reportIDs.count) 张 Tableau 报表，默认加入当前分析。"
                    )
                } else {
                    statusText = successMessage
                }
            } catch {
                recordTableauSync(
                    sourceID: source.id,
                    businessSpaceID: spaceID,
                    dataPackID: selectedPack?.id,
                    startedAt: startedAt,
                    status: .failed,
                    importedViewCount: 0,
                    message: error.localizedDescription
                )
                updateTableauSource(source) {
                    $0.lastStatusMessage = error.localizedDescription
                }
                statusText = error.localizedDescription
            }
        }
    }

    private func mergeTableauImportResult(_ result: TableauImportResult, source: TableauSource) -> (packID: UUID?, reportIDs: [UUID]) {
        let packID = ensureSelectedTableauDataPack()
        var importedIDs: [UUID] = []
        updateSelectedPack(saveImmediately: false) { pack in
            ensureAnalysisTaskExists(in: &pack)
            pack.businessSpaceID = pack.businessSpaceID ?? selectedBusinessSpace?.id
            pack.importedAt = Date()

            for report in result.reports {
                var updatedReport = report
                if let existingIndex = pack.importedReports.firstIndex(where: {
                    reportImportBaseKey(for: $0) == reportImportBaseKey(for: report)
                }) {
                    let existing = pack.importedReports[existingIndex]
                    updatedReport.id = existing.id
                    if updatedReport.userReportAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        updatedReport.userReportAlias = existing.userReportAlias
                    }
                    pack.importedReports[existingIndex] = updatedReport
                } else {
                    pack.importedReports.append(updatedReport)
                }
                importedIDs.append(updatedReport.id)
            }

            pack.importedReports = dedupedReports(pack.importedReports).sorted { $0.importedAt > $1.importedAt }
            pack.fieldDefinitions = DataImportService.rebuildFieldDefinitions(
                for: pack.importedReports,
                preserving: pack.fieldDefinitions + result.fieldDefinitions
            )

            markPackNeedsReview(&pack)
            refreshTaskRelationshipProfile(for: &pack, forceReview: true)
            refreshTaskBusinessLinks(for: &pack, forceReview: true)
            preparePackForImportReview(&pack)
        }
        save()
        return (packID, importedIDs)
    }

    private func ensureSelectedTableauDataPack() -> UUID? {
        if let selectedPack {
            return selectedPack.id
        }
        let dateText = DateFormatting.shortDate.string(from: Date())
        let pack = DataPack(
            id: UUID(),
            businessSpaceID: selectedBusinessSpace?.id,
            name: "Tableau 导入 · \(dateText)",
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

    private func recordTableauSync(
        sourceID: UUID,
        businessSpaceID: UUID,
        dataPackID: UUID?,
        startedAt: Date,
        status: TableauSyncRecord.Status,
        importedViewCount: Int,
        message: String
    ) {
        workspace.tableauSyncRecords.insert(
            TableauSyncRecord(
                sourceID: sourceID,
                businessSpaceID: businessSpaceID,
                dataPackID: dataPackID,
                startedAt: startedAt,
                finishedAt: Date(),
                status: status,
                importedViewCount: importedViewCount,
                message: message
            ),
            at: 0
        )
        workspace.tableauSyncRecords = Array(workspace.tableauSyncRecords.prefix(200))
        save()
    }
}
