import AppKit
import SwiftUI

@MainActor
public enum DebugSnapshotBootstrap {
    public static func scheduleIfRequested(store: ProductWorkflowStore, mainWindow: NSWindow?) {
        DebugSnapshotExporter.scheduleIfRequested(store: store, mainWindow: mainWindow)
    }
}

private enum DebugSnapshotScenario: String, CaseIterable, Codable {
    case current
    case analysisSessionNormal = "analysis-session-normal"
    case analysisSessionFirstQuestion = "analysis-session-first-question"
    case analysisSessionEmptyReports = "analysis-session-empty-reports"
    case analysisInfoSidebar = "analysis-info-sidebar"
    case analysisEvidenceSidebar = "analysis-evidence-sidebar"
    case analysisEvidenceTrace = "analysis-evidence-trace"
    case postImportConfirmation = "post-import-confirmation"
    case tableauError = "tableau-error"
    case sidebarMoreExpanded = "sidebar-more-expanded"

    var expectedText: [String] {
        switch self {
        case .current:
            return ["NexaFlow"]
        case .analysisSessionNormal:
            return ["分析会话", "导入数据", "确认分析表", "继续追问"]
        case .analysisSessionFirstQuestion:
            return ["首次全量分析", "首次提问会自动读取当前任务全部分析资料"]
        case .analysisSessionEmptyReports:
            return ["请先确认本次分析表", "确认选表"]
        case .analysisInfoSidebar:
            return ["分析资料", "资料", "本次分析表"]
        case .analysisEvidenceSidebar:
            return ["分析资料", "证据", "AI 读取范围"]
        case .analysisEvidenceTrace:
            return ["数字血缘定位", "原始表快照", "交易人数 2025 H2"]
        case .postImportConfirmation:
            return ["导入完成，确认本次分析表", "加入并开始分析"]
        case .tableauError:
            return ["Tableau 请求失败", "HTTP 502"]
        case .sidebarMoreExpanded:
            return ["更多", "业务空间", "分析证据", "记忆中心"]
        }
    }
}

private struct DebugSnapshotManifest: Codable {
    struct Entry: Codable {
        var scenario: String
        var path: String
        var width: Int
        var height: Int
        var byteCount: Int
        var source: String
        var expectedText: [String]
    }

    struct Failure: Codable {
        var scenario: String
        var error: String
    }

    var appName: String
    var runID: String
    var generatedAt: Date
    var entries: [Entry]
    var failures: [Failure]
}

@MainActor
enum DebugSnapshotExporter {
    private static let directoryKey = "NEXAFLOW_DEBUG_SNAPSHOT_DIR"
    private static let scenariosKey = "NEXAFLOW_DEBUG_SNAPSHOT_SCENARIOS"
    private static let runIDKey = "NEXAFLOW_DEBUG_SNAPSHOT_RUN_ID"
    private static let delayKey = "NEXAFLOW_DEBUG_SNAPSHOT_DELAY_SECONDS"
    private static let widthKey = "NEXAFLOW_DEBUG_SNAPSHOT_WIDTH"
    private static let heightKey = "NEXAFLOW_DEBUG_SNAPSHOT_HEIGHT"
    private static let terminateKey = "NEXAFLOW_DEBUG_SNAPSHOT_TERMINATE_AFTER_EXPORT"

    private static var didSchedule = false

    static func scheduleIfRequested(store: ProductWorkflowStore, mainWindow: NSWindow?) {
        guard !didSchedule else { return }
        guard let outputRoot = outputRootURL() else { return }
        didSchedule = true

        let environment = ProcessInfo.processInfo.environment
        let scenarios = requestedScenarios()
        let runID = environment[runIDKey].flatMap { $0.nilIfBlank } ?? Self.defaultRunID()
        let delaySeconds = environment[delayKey].flatMap(Double.init) ?? 1.0
        let shouldTerminate = environment[terminateKey] == "1"

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0.1, delaySeconds) * 1_000_000_000))
            do {
                let runDirectory = outputRoot.appendingPathComponent(runID, isDirectory: true)
                let manifest = await exportSnapshots(
                    scenarios: scenarios,
                    runID: runID,
                    runDirectory: runDirectory,
                    sourceStore: store,
                    mainWindow: mainWindow
                )
                try writeManifest(manifest, to: runDirectory)
                if shouldTerminate {
                    NSApplication.shared.terminate(nil)
                }
            } catch {
                let runDirectory = outputRoot.appendingPathComponent(runID, isDirectory: true)
                try? FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
                let manifest = DebugSnapshotManifest(
                    appName: "NexaFlow",
                    runID: runID,
                    generatedAt: Date(),
                    entries: [],
                    failures: [DebugSnapshotManifest.Failure(scenario: "export", error: String(describing: error))]
                )
                try? writeManifest(manifest, to: runDirectory)
            }
        }
    }

    private static func exportSnapshots(
        scenarios: [DebugSnapshotScenario],
        runID: String,
        runDirectory: URL,
        sourceStore: ProductWorkflowStore,
        mainWindow: NSWindow?
    ) async -> DebugSnapshotManifest {
        try? FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        var entries: [DebugSnapshotManifest.Entry] = []
        var failures: [DebugSnapshotManifest.Failure] = []

        for scenario in scenarios {
            do {
                let result: SnapshotResult
                if scenario == .current {
                    result = try await exportCurrentWindow(
                        scenario: scenario,
                        runDirectory: runDirectory,
                        mainWindow: mainWindow
                    )
                } else {
                    result = try await exportPresetScenario(
                        scenario: scenario,
                        runDirectory: runDirectory,
                        sourceStore: sourceStore
                    )
                }
                entries.append(DebugSnapshotManifest.Entry(
                    scenario: scenario.rawValue,
                    path: result.path.path,
                    width: result.width,
                    height: result.height,
                    byteCount: result.byteCount,
                    source: result.source,
                    expectedText: scenario.expectedText
                ))
            } catch {
                failures.append(DebugSnapshotManifest.Failure(
                    scenario: scenario.rawValue,
                    error: String(describing: error)
                ))
            }
        }

        return DebugSnapshotManifest(
            appName: "NexaFlow",
            runID: runID,
            generatedAt: Date(),
            entries: entries,
            failures: failures
        )
    }

    private static func exportCurrentWindow(
        scenario: DebugSnapshotScenario,
        runDirectory: URL,
        mainWindow: NSWindow?
    ) async throws -> SnapshotResult {
        guard let contentView = mainWindow?.contentView else {
            throw SnapshotError.missingMainWindow
        }
        mainWindow?.layoutIfNeeded()
        contentView.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 120_000_000)

        let fileURL = runDirectory.appendingPathComponent("\(scenario.rawValue).png")
        return try writePNG(of: contentView, to: fileURL, source: "current-window-view")
    }

    private static func exportPresetScenario(
        scenario: DebugSnapshotScenario,
        runDirectory: URL,
        sourceStore: ProductWorkflowStore
    ) async throws -> SnapshotResult {
        var workspace = makeSnapshotWorkspace(from: sourceStore.workspace, scenario: scenario)
        let scenarioStore = ProductWorkflowStore(debugSnapshotWorkspace: workspace)
        configure(store: scenarioStore, workspace: &workspace, scenario: scenario)

        let size = renderSize(for: scenario)
        let rootView: AnyView
        switch scenario {
        case .sidebarMoreExpanded:
            rootView = AnyView(
                SidebarView(selection: .constant(.sessions), initialMoreExpanded: true)
                    .environmentObject(scenarioStore)
                    .frame(width: size.width, height: size.height)
                    .background(.bar)
            )
        case .postImportConfirmation:
            guard let draft = scenarioStore.pendingPostImportConfirmation else {
                throw SnapshotError.missingPostImportDraft
            }
            rootView = AnyView(
                PostImportAnalysisConfirmationSheet(draft: draft)
                    .environmentObject(scenarioStore)
                    .frame(width: size.width, height: size.height)
                    .background(Color(nsColor: .windowBackgroundColor))
            )
        default:
            rootView = AnyView(
                ContentView()
                    .environmentObject(scenarioStore)
                    .frame(width: size.width, height: size.height)
            )
        }

        let fileURL = runDirectory.appendingPathComponent("\(scenario.rawValue).png")
        return try await render(rootView: rootView, size: size, to: fileURL, source: "offscreen-swiftui")
    }

    private static func render(rootView: AnyView, size: NSSize, to fileURL: URL, source: String) async throws -> SnapshotResult {
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.setFrameSize(size)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 350_000_000)
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        return try writePNG(of: hostingView, to: fileURL, source: source)
    }

    private static func writePNG(of view: NSView, to fileURL: URL, source: String) throws -> SnapshotResult {
        let bounds = view.bounds
        guard bounds.width > 10, bounds.height > 10 else {
            throw SnapshotError.invalidViewSize(bounds.size)
        }
        guard let representation = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw SnapshotError.bitmapCreationFailed
        }
        view.cacheDisplay(in: bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw SnapshotError.pngEncodingFailed
        }
        try data.write(to: fileURL, options: .atomic)
        return SnapshotResult(
            path: fileURL,
            width: representation.pixelsWide,
            height: representation.pixelsHigh,
            byteCount: data.count,
            source: source
        )
    }

    private static func makeSnapshotWorkspace(from source: ProductWorkspace, scenario: DebugSnapshotScenario) -> ProductWorkspace {
        var workspace = (source.dataPacks.isEmpty || scenario == .analysisEvidenceSidebar || scenario == .analysisEvidenceTrace)
            ? SampleDataFactory.makeWorkspace()
            : source
        ensureDebugReportsAndSession(in: &workspace, scenario: scenario)
        return workspace
    }

    private static func ensureDebugReportsAndSession(in workspace: inout ProductWorkspace, scenario: DebugSnapshotScenario) {
        if workspace.dataPacks.isEmpty {
            workspace = SampleDataFactory.makeWorkspace()
        }

        let selectedSpaceID = workspace.selectedBusinessSpaceID ?? workspace.businessSpaces.first?.id
        let packIndex = workspace.dataPacks.firstIndex { pack in
            guard let selectedSpaceID else { return true }
            return pack.businessSpaceID == selectedSpaceID || pack.businessSpaceID == nil
        } ?? workspace.dataPacks.indices.first
        guard let packIndex else { return }

        if workspace.dataPacks[packIndex].businessSpaceID == nil {
            workspace.dataPacks[packIndex].businessSpaceID = selectedSpaceID
        }
        if workspace.dataPacks[packIndex].name.contains("示例数据包") {
            workspace.dataPacks[packIndex].name = "6月8周会"
            workspace.dataPacks[packIndex].period = "2026 H1"
        }

        if workspace.dataPacks[packIndex].importedReports.count < 2 {
            workspace.dataPacks[packIndex].importedReports = makeDebugReports()
        }

        let reportIDs = workspace.dataPacks[packIndex].importedReports.map(\.id)
        let taskID = workspace.dataPacks[packIndex].selectedAnalysisTaskID ?? UUID()
        var roles: [UUID: AnalysisTaskReportRole] = [:]
        for (index, reportID) in reportIDs.enumerated() {
            roles[reportID] = index == 0 ? .primaryBusiness : .evidence
        }

        let selectedReportIDs = scenario == .analysisSessionEmptyReports ? [] : reportIDs
        var task = AnalysisTask(
            id: taskID,
            businessSpaceID: workspace.dataPacks[packIndex].businessSpaceID,
            businessSpaceSnapshot: workspace.businessSpaces.first { $0.id == workspace.dataPacks[packIndex].businessSpaceID }?.snapshot,
            name: "新分析任务",
            goal: "统计 H2 2025 与 H1 2026 的交易人数、交易金额、交易笔数、人均与笔均指标。",
            selectedReportIDs: selectedReportIDs,
            reportRoles: roles
        )
        if scenario == .analysisSessionEmptyReports {
            task.reportRoles = [:]
        }
        workspace.dataPacks[packIndex].analysisTasks = [task]
        workspace.dataPacks[packIndex].selectedAnalysisTaskID = task.id

        let session = makeDebugSession(
            pack: workspace.dataPacks[packIndex],
            task: task,
            scenario: scenario
        )
        workspace.analysisSessions.removeAll { $0.id == session.id || $0.packID == session.packID }
        workspace.analysisSessions.insert(session, at: 0)
        workspace.selectedAnalysisSessionID = session.id
    }

    private static func configure(store: ProductWorkflowStore, workspace: inout ProductWorkspace, scenario: DebugSnapshotScenario) {
        store.currentSidebarSelection = .sessions
        store.isMainSidebarVisible = true
        store.isAnalysisReadingMode = false
        store.isAnalysisInfoSidebarVisible = false
        store.analysisInfoSidebarPanelID = "资料"

        switch scenario {
        case .analysisInfoSidebar:
            store.isAnalysisInfoSidebarVisible = true
            store.analysisInfoSidebarPanelID = "资料"
        case .analysisEvidenceSidebar, .analysisEvidenceTrace:
            store.isAnalysisInfoSidebarVisible = true
            store.analysisInfoSidebarPanelID = "证据"
            if scenario == .analysisEvidenceTrace,
               let run = store.selectedAnalysisSession?.messages
                .flatMap(\.evidence)
                .compactMap(\.analysisHarnessRun)
                .first,
               let result = run.verifiedResults.first {
                store.selectedMetricResultID = result.id
                store.selectedSourceCellRefs = result.source.sourceCells ?? []
            }
        case .postImportConfirmation:
            if let pack = store.selectedPack {
                let reportIDs = pack.importedReports.map(\.id)
                let existingReportIDs = Array(reportIDs.prefix(1))
                let newReportIDs = Set(reportIDs.dropFirst())
                var roles: [UUID: AnalysisTaskReportRole] = [:]
                for (index, reportID) in reportIDs.enumerated() {
                    roles[reportID] = index == 0 ? .primaryBusiness : .evidence
                }
                store.pendingPostImportConfirmation = PostImportAnalysisConfirmation(
                    packID: pack.id,
                    title: "导入完成，确认本次分析表",
                    detail: "已将 \(reportIDs.count) 张报表导入「\(pack.name)」，请选择本轮要一起分析的表。",
                    reportIDs: reportIDs,
                    newReportIDs: newReportIDs,
                    currentTaskReportIDs: Set(existingReportIDs),
                    defaultSelectedReportIDs: Set(reportIDs),
                    defaultReportRoles: roles
                )
            }
        default:
            break
        }
    }

    private static func makeDebugReports() -> [ImportedReport] {
        [
            ImportedReport(
                id: UUID(),
                fileName: "Sufinc 周会产品运营 / 本地生活数据",
                kind: .coreMetrics,
                importedAt: Date(),
                sourceFileName: "Tableau Crosstab",
                sourceFingerprint: "debug-tableau-primary",
                rowCount: 6_552,
                headers: ["周期", "Measure Names", "Measure Values", "业务维度", "国家"],
                sampleRows: [
                    ["周期": "2025-07-13 ~ 2025-07-19", "Measure Names": "交易人数", "Measure Values": "19462", "业务维度": "本地生活", "国家": "墨西哥"],
                    ["周期": "2025-07-13 ~ 2025-07-19", "Measure Names": "交易金额", "Measure Values": "5047470", "业务维度": "本地生活", "国家": "墨西哥"],
                    ["周期": "2026-01-04 ~ 2026-01-10", "Measure Names": "交易人数", "Measure Values": "32569", "业务维度": "本地生活", "国家": "墨西哥"],
                    ["周期": "2026-01-04 ~ 2026-01-10", "Measure Names": "交易金额", "Measure Values": "6878234", "业务维度": "本地生活", "国家": "墨西哥"],
                    ["周期": "2025-07-13 ~ 2025-07-19", "Measure Names": "人均交易金额", "Measure Values": "259.35", "业务维度": "本地生活", "国家": "墨西哥"],
                    ["周期": "2026-01-04 ~ 2026-01-10", "Measure Names": "人均交易金额", "Measure Values": "211.19", "业务维度": "本地生活", "国家": "墨西哥"]
                ],
                shape: .pivotWide,
                sourceFormat: .tableau,
                semanticStatus: .confirmed,
                semanticConfidence: 0.92
            ),
            ImportedReport(
                id: UUID(),
                fileName: "支付通道与商户结算表",
                kind: .generic,
                importedAt: Date(),
                sourceFileName: "settlement.xlsx",
                sourceFingerprint: "debug-local-supporting",
                rowCount: 1_284,
                headers: ["日期", "通道", "成功率", "手续费率", "退款金额"],
                sampleRows: [
                    ["日期": "2026-01-07", "通道": "Card", "成功率": "0.91", "手续费率": "0.021", "退款金额": "1203"],
                    ["日期": "2026-01-14", "通道": "SPEI", "成功率": "0.94", "手续费率": "0.012", "退款金额": "804"]
                ],
                shape: .detail,
                sourceFormat: .xlsx,
                semanticStatus: .confirmed,
                semanticConfidence: 0.86
            )
        ]
    }

    private static func makeDebugSession(pack: DataPack, task: AnalysisTask, scenario: DebugSnapshotScenario) -> AnalysisSession {
        if scenario == .analysisSessionFirstQuestion {
            return AnalysisSession(
                packID: pack.id,
                taskID: task.id,
                businessSpaceID: pack.businessSpaceID,
                businessSpaceSnapshot: task.businessSpaceSnapshot,
                title: "新分析任务 · 2026-06-25",
                goal: task.goal,
                selectedReportIDs: task.activeReportIDs,
                status: .waitingForUser,
                messages: [],
                createdAt: Date(),
                updatedAt: Date()
            )
        }

        let userMessage = AnalysisSessionMessage(
            role: .user,
            kind: .userRequest,
            content: "帮我统计去年下半年和今年上半年的以下字段数据：交易人数、交易金额、交易笔数、人均交易金额、人均交易笔数、笔均交易金额。"
        )
        let assistantContent: String
        if scenario == .tableauError {
            assistantContent = """
            Tableau 请求失败：HTTP 502。Tableau Server 返回内部错误，通常是 Tableau 视图导出服务或反向代理临时失败，不是 NexaFlow 解析失败。

            请稍后重试，或在 Tableau 中确认该视图可以下载 Crosstab/CSV。
            """
        } else if scenario == .analysisSessionEmptyReports {
            assistantContent = "当前任务还没有选择表。请先在分析资料中加入至少 1 张表，再发送给 AI。"
        } else {
            assistantContent = """
            ## 直接回答你的问题
            基于本地已校验结果，2026 H1 相比 2025 H2 呈现“交易规模增长、单客贡献回落”的特征：交易人数从 19,462 人增至 32,569 人，增长 67.35%；交易金额从 5,047,470 MXN 增至 6,878,234 MXN，增长 36.27%；人均交易金额从 259.35 MXN/人降至 211.19 MXN/人。

            ## 本地已校验事实
            | 指标 | 2025 H2 | 2026 H1 | 变化 |
            |---|---:|---:|---:|
            | 交易人数 | 19,462 人 | 32,569 人 | +67.35% |
            | 交易金额 | 5,047,470 MXN | 6,878,234 MXN | +36.27% |
            | 人均交易金额 | 259.35 MXN/人 | 211.19 MXN/人 | -18.57% |

            ## 关键数据证据
            基础指标采用全周期 SUM；派生指标采用 SUM(分子) / SUM(分母) 重算，不直接平均周度人均值。

            ## AI 读取到的数据
            读取 2 张表、7,836 行、10 列，覆盖 H2 2025 与 H1 2026。

            ## 未覆盖/需补数据
            2026 H1 最新周可能未完整，应在正式复盘中标注周期截断风险。
            """
        }

        let harnessRun = (scenario == .tableauError || scenario == .analysisSessionEmptyReports)
            ? nil
            : debugHarnessRun(pack: pack)
        let assistantMessage = AnalysisSessionMessage(
            role: .assistant,
            kind: scenario == .tableauError ? .error : .aiAnalysis,
            content: assistantContent,
            evidence: [
                AnalysisSessionEvidence(
                    sourceType: "数据覆盖",
                    title: "读取范围",
                    detail: "读取 2 张表、7836 行、10 列，覆盖 H2 2025 与 H1 2026。"
                ),
                AnalysisSessionEvidence(
                    sourceType: "计算证据",
                    title: "聚合口径审计",
                    detail: "SUM 口径和派生指标重算均已生成。"
                ),
                AnalysisSessionEvidence(
                    sourceType: "Analysis Harness",
                    title: "本轮 Analysis Harness 审计",
                    detail: harnessRun?.evidenceMarkdown ?? debugHarnessEvidenceMarkdown(),
                    sourceID: harnessRun?.id.uuidString ?? "80DC2484",
                    analysisHarnessRun: harnessRun
                )
            ]
        )

        return AnalysisSession(
            packID: pack.id,
            taskID: task.id,
            businessSpaceID: pack.businessSpaceID,
            businessSpaceSnapshot: task.businessSpaceSnapshot,
            title: "新分析任务 · 2026-06-25",
            goal: task.goal,
            selectedReportIDs: task.activeReportIDs,
            status: .waitingForUser,
            messages: [userMessage, assistantMessage],
            finalReportMarkdown: scenario == .analysisSessionNormal ? "# 完整汇报\n\n本轮汇报已生成。" : "",
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private static func debugHarnessRun(pack: DataPack) -> AnalysisHarnessRun? {
        guard let report = pack.importedReports.first else { return nil }
        let tableID = report.id.uuidString
        let sheetName = report.sheetName ?? "Sheet 1"
        let h2PeopleID = UUID(uuidString: "7AAB3487-8B74-48B3-9B2C-B219560348E1") ?? UUID()
        let h1PeopleID = UUID(uuidString: "53F6B3B8-06A9-4728-A986-D7E2BA5218DE") ?? UUID()
        let growthID = UUID(uuidString: "8C8CB6E9-A012-4AF5-9029-C9E3B3F9C636") ?? UUID()
        let metricID = UUID(uuidString: "022EEC52-A9C2-4851-B317-F7E5B682D2B6") ?? UUID()

        let h2Cell = HarnessSourceCellRef(sheetName: sheetName, row: 2, column: 3, columnName: "Measure Values", value: "19462")
        let h1Cell = HarnessSourceCellRef(sheetName: sheetName, row: 4, column: 3, columnName: "Measure Values", value: "32569")
        let sourceBase = MetricResultSource(
            tableID: tableID,
            tableName: report.displayName,
            operation: .sum,
            field: "Measure Values",
            groupKey: "2025H2",
            rowCount: 1,
            filtersApplied: [HarnessFilterDefinition(field: "Measure Names", op: .equals, value: "交易人数")],
            methodology: "标准事实表按周期桶执行 SUM",
            factRowCount: 1,
            sourceRowRange: "R2",
            sourceColumnRange: "C",
            sourceCells: [h2Cell],
            coverageSummary: "2025 H2",
            lineageSummary: "\(sheetName)!C2"
        )
        let h2Result = MetricResult(
            id: h2PeopleID,
            metricID: metricID,
            label: "交易人数 2025 H2",
            rawValue: 19_462,
            unit: "人",
            format: .integer,
            source: sourceBase,
            confidence: 1
        )
        var h1Source = sourceBase
        h1Source.groupKey = "2026H1"
        h1Source.sourceRowRange = "R4"
        h1Source.sourceCells = [h1Cell]
        h1Source.coverageSummary = "2026 H1"
        h1Source.lineageSummary = "\(sheetName)!C4"
        let h1Result = MetricResult(
            id: h1PeopleID,
            metricID: metricID,
            label: "交易人数 2026 H1",
            rawValue: 32_569,
            unit: "人",
            format: .integer,
            source: h1Source,
            confidence: 1
        )
        var growthSource = sourceBase
        growthSource.operation = .calculateGrowthRate
        growthSource.groupKey = "2025H2 -> 2026H1"
        growthSource.methodology = "SUM(2026 H1) / SUM(2025 H2) - 1"
        growthSource.sourceRowRange = "R2,R4"
        growthSource.sourceCells = [h2Cell, h1Cell]
        growthSource.coverageSummary = "2025 H2 vs 2026 H1"
        growthSource.lineageSummary = "\(sheetName)!C2 + \(sheetName)!C4"
        let growthResult = MetricResult(
            id: growthID,
            metricID: metricID,
            label: "交易人数 增长率",
            rawValue: 67.35,
            unit: "",
            format: .percent,
            source: growthSource,
            confidence: 1
        )

        let factRows = [
            NormalizedFactRow(
                tableID: tableID,
                tableName: report.displayName,
                sourceSheet: sheetName,
                sourceRow: 2,
                sourceColumn: 3,
                periodRaw: "2025-07-13 ~ 2025-07-19",
                periodStart: "2025-07-13",
                periodEnd: "2025-07-19",
                periodBucket: "2025H2",
                metricName: "交易人数",
                metricValue: 19_462,
                rawValue: "19462",
                unit: "人",
                valueKind: .additive,
                dimensionName: "业务维度",
                dimensionValue: "本地生活"
            ),
            NormalizedFactRow(
                tableID: tableID,
                tableName: report.displayName,
                sourceSheet: sheetName,
                sourceRow: 4,
                sourceColumn: 3,
                periodRaw: "2026-01-04 ~ 2026-01-10",
                periodStart: "2026-01-04",
                periodEnd: "2026-01-10",
                periodBucket: "2026H1",
                metricName: "交易人数",
                metricValue: 32_569,
                rawValue: "32569",
                unit: "人",
                valueKind: .additive,
                dimensionName: "业务维度",
                dimensionValue: "本地生活"
            )
        ]
        let catalog = [
            HarnessMetricCatalogEntry(
                metricName: "交易人数",
                valueKind: .additive,
                observationCount: 2,
                firstPeriod: "2025-07-13",
                lastPeriod: "2026-01-10",
                sampleValues: ["19462", "32569"]
            )
        ]
        let understanding = HarnessTableUnderstandingSummary(
            shape: .tableauLong,
            confidence: 0.92,
            periodColumn: "周期",
            metricNameColumn: "Measure Names",
            metricValueColumn: "Measure Values",
            dimensionColumns: ["业务维度", "国家"],
            metricCatalog: catalog,
            warnings: []
        )
        let manifest = TableManifest(
            id: tableID,
            reportID: report.id,
            displayName: report.displayName,
            rowCount: report.rowCount,
            columnCount: report.headers.count,
            sourceFormat: report.sourceFormat.rawValue,
            sourceType: report.sourceFileName,
            shape: String(describing: report.shape),
            columns: [
                ColumnManifest(
                    name: "周期",
                    inferredType: .string,
                    semanticCandidates: [HarnessSemanticCandidate(role: .period, confidence: 0.92, reason: "周区间文本")],
                    aggregationRisk: .categoryLike,
                    nullCount: 0,
                    nonNullCount: 6,
                    uniqueCount: 2,
                    sampleValues: ["2025-07-13 ~ 2025-07-19", "2026-01-04 ~ 2026-01-10"],
                    numericMin: nil,
                    numericMax: nil,
                    dateMin: "2025-07-13",
                    dateMax: "2026-01-10"
                ),
                ColumnManifest(
                    name: "Measure Names",
                    inferredType: .string,
                    semanticCandidates: [HarnessSemanticCandidate(role: .metricName, confidence: 0.94, reason: "Tableau 指标列")],
                    aggregationRisk: .categoryLike,
                    nullCount: 0,
                    nonNullCount: 6,
                    uniqueCount: 3,
                    sampleValues: ["交易人数", "交易金额", "人均交易金额"],
                    numericMin: nil,
                    numericMax: nil,
                    dateMin: nil,
                    dateMax: nil
                ),
                ColumnManifest(
                    name: "Measure Values",
                    inferredType: .number,
                    semanticCandidates: [HarnessSemanticCandidate(role: .metricValue, confidence: 0.95, reason: "Tableau 数值列")],
                    aggregationRisk: .safeSum,
                    nullCount: 0,
                    nonNullCount: 6,
                    uniqueCount: 6,
                    sampleValues: ["19462", "32569", "5047470"],
                    numericMin: 211.19,
                    numericMax: 6_878_234,
                    dateMin: nil,
                    dateMax: nil
                )
            ],
            detectedGrain: HarnessDetectedGrain(
                kind: .oneRowPerMetricPeriod,
                confidence: 0.9,
                keyColumns: ["周期", "Measure Names"],
                description: "每行代表一个周期下的一个指标值。"
            ),
            dateRanges: [
                HarnessManifestDateRange(column: "周期", min: "2025-07-13", max: "2026-01-10", nonNullCount: 6)
            ],
            duplicateSummary: HarnessDuplicateSummary(
                exactDuplicateRowCount: 0,
                duplicateRatio: 0,
                candidateKeyColumns: ["周期", "Measure Names"]
            ),
            warnings: [],
            understanding: understanding
        )
        let factTable = NormalizedFactTable(
            tableID: tableID,
            tableName: report.displayName,
            shape: .tableauLong,
            confidence: 0.92,
            rows: factRows,
            metricCatalog: catalog,
            warnings: []
        )
        return AnalysisHarnessRun(
            id: UUID(uuidString: "80DC2484-1111-4222-8333-444444444444") ?? UUID(),
            createdAt: Date(),
            finishedAt: Date(),
            status: .success,
            userQuery: "统计 H2 2025 与 H1 2026 的交易人数。",
            tableManifest: [manifest],
            normalizedFactTables: [factTable],
            analysisPlan: nil,
            verifiedResults: [h2Result, h1Result, growthResult],
            validationIssues: [],
            auditLog: [
                AuditEvent(stage: .tableUnderstanding, status: .completed, summary: "识别 Tableau 长表结构。"),
                AuditEvent(stage: .metricExecution, status: .completed, summary: "执行本地 SUM 与增长率计算。"),
                AuditEvent(stage: .answerNumberTracing, status: .completed, summary: "回答数字已链接到 verified results。")
            ],
            reportMarkdown: """
            ## 直接回答你的问题
            交易人数从 19,462 人增至 32,569 人，增长 67.35%。
            """,
            repairAttemptsPlan: 0,
            repairAttemptsReport: 0,
            durationMilliseconds: 842,
            answerNumberTraces: [
                AnswerNumberTrace(
                    rawText: "19,462",
                    normalizedValue: 19_462,
                    unitHint: "人",
                    contextSnippet: "交易人数从 19,462 人增至 32,569 人",
                    status: .matched,
                    matchedResultID: h2PeopleID,
                    matchedResultLabel: "交易人数 2025 H2",
                    toleranceDescription: "整数精确匹配"
                ),
                AnswerNumberTrace(
                    rawText: "32,569",
                    normalizedValue: 32_569,
                    unitHint: "人",
                    contextSnippet: "交易人数从 19,462 人增至 32,569 人",
                    status: .matched,
                    matchedResultID: h1PeopleID,
                    matchedResultLabel: "交易人数 2026 H1",
                    toleranceDescription: "整数精确匹配"
                ),
                AnswerNumberTrace(
                    rawText: "67.35%",
                    normalizedValue: 67.35,
                    unitHint: "%",
                    contextSnippet: "增长 67.35%",
                    status: .matched,
                    matchedResultID: growthID,
                    matchedResultLabel: "交易人数 增长率",
                    toleranceDescription: "百分比容差匹配"
                )
            ]
        )
    }

    private static func debugHarnessEvidenceMarkdown() -> String {
        """
        # Analysis Harness 审计

        ## 运行状态
        - Run ID：80DC2484-DEBUG
        - 状态：已通过
        - 计划修复次数：0
        - 报告修复次数：0
        - 耗时：842 ms

        ## 表格理解
        - Sufinc 周会产品运营 / 本地生活数据：Tableau 长表，置信度 92%；周期列=周期；指标列=Measure Names；数值列=Measure Values；指标：交易人数(26)、交易金额(26)、交易笔数(26)

        ## Table Understanding / Normalized Facts
        - Sufinc 周会产品运营 / 本地生活数据：Tableau 长表，事实行 78，指标 交易人数、交易金额、交易笔数

        ## 标准事实表预览
        - Sufinc 周会产品运营 / 本地生活数据 R2C3：2025-07-13 ~ 2025-07-19；归属 2025H2；交易人数=19462
        - Sufinc 周会产品运营 / 本地生活数据 R3C3：2025-07-13 ~ 2025-07-19；归属 2025H2；交易金额=5047470
        - Sufinc 周会产品运营 / 本地生活数据 R4C3：2026-01-04 ~ 2026-01-10；归属 2026H1；交易人数=32569

        ## 关键指标结果
        - 交易人数 2025 H2：19,462 人；Sufinc 周会产品运营 / 本地生活数据!C2=19462
        - 交易人数 2026 H1：32,569 人；Sufinc 周会产品运营 / 本地生活数据!C4=32569
        - 交易人数 增长率：67.35%；SUM(2026 H1) / SUM(2025 H2) - 1

        ## Verified Results
        - 交易人数 2025 H2：19,462 人；标准事实表 SUM
        - 交易人数 2026 H1：32,569 人；标准事实表 SUM
        - 交易人数 增长率：67.35%；本地派生指标

        ## Validation Issues
        - 无阻断或警告。
        """
    }

    private static func requestedScenarios() -> [DebugSnapshotScenario] {
        let raw = ProcessInfo.processInfo.environment[scenariosKey] ?? "current"
        let parsed = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap(DebugSnapshotScenario.init(rawValue:))
        return parsed.isEmpty ? [.current] : parsed
    }

    private static func renderSize(for scenario: DebugSnapshotScenario) -> NSSize {
        if scenario == .sidebarMoreExpanded {
            return NSSize(width: 320, height: 760)
        }
        if scenario == .postImportConfirmation {
            return NSSize(width: 720, height: 680)
        }
        let environment = ProcessInfo.processInfo.environment
        let width = environment[widthKey].flatMap(Double.init) ?? 1_440
        let height = environment[heightKey].flatMap(Double.init) ?? 900
        return NSSize(width: max(900, width), height: max(700, height))
    }

    private static func outputRootURL() -> URL? {
        guard let rawPath = ProcessInfo.processInfo.environment[directoryKey]?.nilIfBlank else {
            return nil
        }
        return URL(fileURLWithPath: NSString(string: rawPath).expandingTildeInPath, isDirectory: true)
    }

    private static func defaultRunID() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "snapshot-\(formatter.string(from: Date()))"
    }

    private static func writeManifest(_ manifest: DebugSnapshotManifest, to runDirectory: URL) throws {
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: runDirectory.appendingPathComponent("manifest.json"), options: .atomic)
    }

    private struct SnapshotResult {
        var path: URL
        var width: Int
        var height: Int
        var byteCount: Int
        var source: String
    }

    private enum SnapshotError: Error, CustomStringConvertible {
        case missingMainWindow
        case missingPostImportDraft
        case invalidViewSize(NSSize)
        case bitmapCreationFailed
        case pngEncodingFailed

        var description: String {
            switch self {
            case .missingMainWindow:
                return "main window is not available"
            case .missingPostImportDraft:
                return "post-import confirmation draft is not available"
            case .invalidViewSize(let size):
                return "invalid view size \(Int(size.width))x\(Int(size.height))"
            case .bitmapCreationFailed:
                return "failed to create bitmap representation"
            case .pngEncodingFailed:
                return "failed to encode PNG"
            }
        }
    }
}
