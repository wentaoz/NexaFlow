import Foundation
@testable import IterationPilotCore

final class ProductExperienceTests: XCTestCase {
    func testDemoWorkspaceContainsSelectedAnalyzableReports() throws {
        let pack = SampleDataFactory.makeSamplePack()
        let task = try XCTUnwrap(pack.analysisTasks.first)

        XCTAssert(pack.importedReports.count == 2)
        XCTAssert(Set(task.activeReportIDs) == Set(pack.importedReports.map(\.id)))
        XCTAssert(pack.importedReports.allSatisfy { $0.semanticStatus == .confirmed })
        XCTAssert(pack.importedReports.allSatisfy { !$0.storedDataRows.isEmpty })
    }

    func testLegacyWorkspaceDefaultsExperienceFieldsWithoutShowingOnboarding() throws {
        setenv("NEXAFLOW_SECURE_STORAGE_NAMESPACE", "test-\(UUID().uuidString)", 1)
        defer { unsetenv("NEXAFLOW_SECURE_STORAGE_NAMESPACE") }
        let workspace = SampleDataFactory.makeWorkspace()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(workspace)
        let rawObject = try JSONSerialization.jsonObject(with: data)
        var object = try XCTUnwrap(rawObject as? [String: Any])
        object.removeValue(forKey: "onboardingState")
        object.removeValue(forKey: "aiConnectionHealth")
        object.removeValue(forKey: "reportTemplates")
        object.removeValue(forKey: "reportRevisions")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ProductWorkspace.self, from: legacyData)

        XCTAssert(decoded.onboardingState.stage == .completed)
        XCTAssert(decoded.aiConnectionHealth.status == .notTested)
        XCTAssert(decoded.reportTemplates.count == 3)
        XCTAssert(decoded.reportRevisions.isEmpty)
    }

    func testOpportunityLegacyDecodeInfersWorkflowStatus() throws {
        let opportunity = ProductOpportunity(
            title: "Improve activation",
            problem: "Conversion dropped",
            affectedUsers: "New users",
            expectedImpact: 8,
            confidence: 7,
            urgency: 6,
            effort: 4,
            risk: 3,
            strategicFit: 8,
            isUserConfirmed: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(opportunity)
        let rawObject = try JSONSerialization.jsonObject(with: data)
        var object = try XCTUnwrap(rawObject as? [String: Any])
        object.removeValue(forKey: "workflowStatus")
        object.removeValue(forKey: "owner")
        object.removeValue(forKey: "dueDate")
        object.removeValue(forKey: "nextAction")
        object.removeValue(forKey: "notes")
        object.removeValue(forKey: "sourceMessageIDs")
        object.removeValue(forKey: "updatedAt")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ProductOpportunity.self, from: legacyData)

        XCTAssert(decoded.workflowStatus == .confirmed)
        XCTAssert(decoded.owner.isEmpty)
        XCTAssert(decoded.updatedAt == decoded.generatedAt)
    }

    func testOpportunityActionFieldsRoundTrip() throws {
        let dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        let opportunity = ProductOpportunity(
            title: "Fix funnel",
            problem: "Drop-off",
            affectedUsers: "Applicants",
            expectedImpact: 9,
            confidence: 8,
            urgency: 7,
            effort: 5,
            risk: 4,
            strategicFit: 9,
            workflowStatus: .inProgress,
            owner: "Product Ops",
            dueDate: dueDate,
            nextAction: "Run cohort analysis",
            notes: "Weekly review"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(opportunity)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ProductOpportunity.self, from: data)

        XCTAssert(decoded.workflowStatus == .inProgress)
        XCTAssert(decoded.isUserConfirmed)
        XCTAssert(decoded.owner == "Product Ops")
        XCTAssert(decoded.dueDate == dueDate)
        XCTAssert(decoded.nextAction == "Run cohort analysis")
    }

    func testReportPreflightBlocksEmptyAndPlaceholderContent() {
        let emptyIssues = ReportPreflightService.evaluate(markdown: "", generatedAt: nil)
        XCTAssert(emptyIssues.contains { $0.severity == .blocker && $0.id == "empty" })

        let placeholder = """
        # Weekly Report

        ## 核心结论

        交易人数为 [H2_SUM]，证据来自当前数据范围。
        """
        let issues = ReportPreflightService.evaluate(markdown: placeholder, generatedAt: Date())
        XCTAssert(issues.contains { $0.severity == .blocker && $0.id == "placeholder" })
    }

    func testReportPreflightAcceptsStructuredEvidenceReport() {
        let paragraph = String(repeating: "本周期关键指标已经完成本地计算，并与上一周期进行一致口径比较。", count: 12)
        let report = """
        # 周报

        ## 核心结论

        \(paragraph)

        ## 数据范围与证据

        依据当前任务三张报表和 Notebook 计算结果，所有数字均可回溯。

        ## 风险与下一步

        建议补充分渠道数据后再验证候选原因。
        """
        let issues = ReportPreflightService.evaluate(markdown: report, generatedAt: Date())
        XCTAssert(!issues.contains { $0.severity == .blocker })
        XCTAssert(!issues.contains { $0.id == "structure" })
        XCTAssert(!issues.contains { $0.id == "evidence" })
    }

    func testReportTemplateRendererAddsTitleAndOrganization() {
        var template = ReportTemplate.builtIns[1]
        template.organizationName = "NexaFlow Product Ops"
        let rendered = ReportTemplateRenderer.render(
            markdown: "## 核心结论\n\n内容",
            title: "经营复盘",
            template: template
        )
        XCTAssert(rendered.hasPrefix("# 经营复盘"))
        XCTAssert(rendered.contains("**NexaFlow Product Ops**"))
        XCTAssert(rendered.contains("## 核心结论"))
    }

    func testReportTemplateRendererKeepsOrganizationBelowExistingTitle() {
        var template = ReportTemplate.builtIns[0]
        template.organizationName = "NexaFlow Product Ops"
        let rendered = ReportTemplateRenderer.render(
            markdown: "# 已有标题\n\n## 核心结论\n\n内容",
            title: "备用标题",
            template: template
        )

        XCTAssert(rendered.hasPrefix("# 已有标题\n\n**NexaFlow Product Ops**"))
    }

    func testReportTemplateRendererAppliesSectionOrderAndVisibility() throws {
        var template = ReportTemplate.builtIns[1]
        template.sectionOrder = ["关键发现", "执行摘要", "数据范围"]
        template.enabledSections = ["关键发现", "执行摘要"]
        let rendered = ReportTemplateRenderer.render(
            markdown: """
            ## 执行摘要

            摘要内容

            ## 数据范围与证据

            范围内容

            ## 关键发现

            发现内容

            ## 附录

            附录内容
            """,
            title: "经营复盘",
            template: template
        )

        let findingRange = try XCTUnwrap(rendered.range(of: "## 关键发现"))
        let summaryRange = try XCTUnwrap(rendered.range(of: "## 执行摘要"))
        XCTAssert(findingRange.lowerBound < summaryRange.lowerBound)
        XCTAssert(!rendered.contains("## 数据范围与证据"))
        XCTAssert(rendered.contains("## 附录"))
    }

    func testVersionComparisonHandlesReleaseSuffixes() {
        XCTAssert(AppUpdateService.isVersion("v1.2.0", newerThan: "1.1.9"))
        XCTAssert(AppUpdateService.isVersion("v1.0.3-20260707", newerThan: "1.0.2"))
        XCTAssert(!AppUpdateService.isVersion("v1.0.3-20260707", newerThan: "1.0.3"))
        XCTAssert(!AppUpdateService.isVersion("v1.0.2", newerThan: "1.0.3"))
    }

    func testWorkspaceTransferRoundTripPreservesExperienceData() throws {
        setenv("NEXAFLOW_SECURE_STORAGE_NAMESPACE", "test-\(UUID().uuidString)", 1)
        defer { unsetenv("NEXAFLOW_SECURE_STORAGE_NAMESPACE") }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexaflow-workspace-transfer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var workspace = SampleDataFactory.makeWorkspace()
        workspace.onboardingState = .firstLaunchDemo
        workspace.aiConnectionHealth = AIConnectionHealth(
            status: .available,
            testedAt: Date(timeIntervalSince1970: 1_800_000_000),
            latencyMilliseconds: 320,
            endpointHost: "example.com",
            model: "test-model",
            supportsChatCompletions: true,
            message: "ok"
        )
        workspace.reportRevisions = [ReportRevision(
            sessionID: UUID(uuidString: "EC0ACB35-7736-4A8B-AE7B-C55707CA0001") ?? UUID(),
            templateID: ReportTemplate.builtIns[1].id,
            title: "经营复盘",
            markdown: "## 核心结论\n\n测试内容",
            source: .manualEdit
        )]
        let url = directory.appendingPathComponent("workspace.json")
        try WorkspaceTransferService.export(workspace: workspace, to: url)
        let loaded = try WorkspaceTransferService.load(from: url)

        XCTAssert(loaded.onboardingState.stage == .welcome)
        XCTAssert(loaded.aiConnectionHealth.status == .available)
        XCTAssert(loaded.reportTemplates.count == 3)
        XCTAssert(loaded.reportRevisions.first?.title == "经营复盘")
        XCTAssert(loaded.schemaVersion == ProductWorkspace.currentSchemaVersion)
    }

    func testReportPDFExporterCreatesReadablePDF() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexaflow-report-pdf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("report.pdf")
        try ReportPDFExporter.export(
            title: "经营复盘",
            markdown: "## 核心结论\n\n交易人数同比增长 12.5%。\n\n## 数据范围与证据\n\n依据当前数据包计算。",
            to: url
        )

        let data = try Data(contentsOf: url)
        XCTAssert(data.count > 1_000)
        XCTAssert(String(data: data.prefix(4), encoding: .ascii) == "%PDF")
    }

    func testDiagnosticBundleExporterCreatesZIP() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexaflow-diagnostics-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("diagnostics.zip")
        try DiagnosticBundleExporter.export(
            payload: DiagnosticBundlePayload(
                generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                appVersion: "1.2.3",
                operatingSystem: "macOS",
                workspaceSchemaVersion: ProductWorkspace.currentSchemaVersion,
                workspaceByteCount: 42,
                selectedBusinessSpace: "测试空间",
                counts: ["dataPacks": 2],
                aiConnectionStatus: "连接正常",
                recentJobs: [],
                currentStatusText: "就绪"
            ),
            to: url
        )

        let data = try Data(contentsOf: url)
        XCTAssert(data.count > 100)
        XCTAssert(String(data: data.prefix(2), encoding: .ascii) == "PK")
    }
}
