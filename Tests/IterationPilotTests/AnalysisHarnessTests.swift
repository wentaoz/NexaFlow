import Foundation
@testable import IterationPilotCore

final class AnalysisHarnessTests: XCTestCase {
    func testTableManifestBuilderDetectsMetricAndRateColumns() throws {
        let report = makeReport(
            headers: ["周期", "Measure Names", "Measure Values", "本地生活覆盖用户占比"],
            rows: [
                ["周期": "2025-01-05", "Measure Names": "交易人数", "Measure Values": "19462", "本地生活覆盖用户占比": "12.5%"],
                ["周期": "2026-01-04", "Measure Names": "交易人数", "Measure Values": "32569", "本地生活覆盖用户占比": "18.2%"]
            ]
        )

        let manifest = try XCTUnwrap(TableManifestBuilder.build(reports: [report]).first)

        XCTAssert(manifest.metricNameColumn?.name == "Measure Names")
        XCTAssert(manifest.metricValueColumn?.name == "Measure Values")
        XCTAssert(manifest.periodColumn?.name == "周期")
        let rateColumn = try XCTUnwrap(manifest.columns.first { $0.name == "本地生活覆盖用户占比" })
        XCTAssert(rateColumn.aggregationRisk == .rateLike)
    }
    func testPlanValidatorBlocksMissingFieldAndRateSum() throws {
        let report = makeReport(
            headers: ["日期", "交易金额", "转化率"],
            rows: [
                ["日期": "2026-01-01", "交易金额": "100", "转化率": "10%"],
                ["日期": "2026-01-02", "交易金额": "150", "转化率": "20%"]
            ]
        )
        let manifest = try XCTUnwrap(TableManifestBuilder.build(reports: [report]).first)
        let plan = AnalysisPlan(
            userQuestion: "统计交易金额和转化率",
            tablesUsed: [manifest.id],
            metrics: [
                MetricDefinition(label: "错误转化率求和", operation: .sum, tableID: manifest.id, field: "转化率"),
                MetricDefinition(label: "缺失字段", operation: .sum, tableID: manifest.id, field: "不存在字段")
            ]
        )

        let issues = PlanValidator.validate(plan: plan, manifests: [manifest])

        XCTAssert(issues.contains { $0.code == .rateAggregationError && $0.severity == .fatal })
        XCTAssert(issues.contains { $0.code == .missingField && $0.severity == .fatal })
    }
    func testMetricExecutorComputesSumAndGroupedLongTable() throws {
        let report = makeReport(
            headers: ["周期", "Measure Names", "Measure Values"],
            rows: [
                ["周期": "2025-H2", "Measure Names": "交易人数", "Measure Values": "19462"],
                ["周期": "2026-H1", "Measure Names": "交易人数", "Measure Values": "32569"],
                ["周期": "2025-H2", "Measure Names": "交易金额", "Measure Values": "5047470"],
                ["周期": "2026-H1", "Measure Names": "交易金额", "Measure Values": "6878234"]
            ]
        )
        let manifest = try XCTUnwrap(TableManifestBuilder.build(reports: [report]).first)
        let plan = AnalysisPlan(
            userQuestion: "统计交易人数",
            tablesUsed: [manifest.id],
            metrics: [
                MetricDefinition(
                    label: "交易人数",
                    operation: .sum,
                    tableID: manifest.id,
                    field: "Measure Values",
                    groupBy: ["周期"],
                    filters: [HarnessFilterDefinition(field: "Measure Names", op: .equals, value: "交易人数")]
                )
            ]
        )

        let results = MetricExecutor.execute(plan: plan, reports: [report], manifests: [manifest])

        XCTAssert(results.count == 2)
        XCTAssert(results.contains { $0.label.contains("2025-H2") && $0.rawValue == 19462 })
        XCTAssert(results.contains { $0.label.contains("2026-H1") && $0.rawValue == 32569 })
    }
    func testMetricExecutorDoesNotCrashWhenDerivedMetricReferencesGroupedResults() throws {
        let report = makeReport(
            headers: ["周期", "Measure Names", "Measure Values"],
            rows: [
                ["周期": "2025-H2", "Measure Names": "交易人数", "Measure Values": "19462"],
                ["周期": "2026-H1", "Measure Names": "交易人数", "Measure Values": "32569"],
                ["周期": "2025-H2", "Measure Names": "交易笔数", "Measure Values": "19462"],
                ["周期": "2026-H1", "Measure Names": "交易笔数", "Measure Values": "32569"]
            ]
        )
        let manifest = try XCTUnwrap(TableManifestBuilder.build(reports: [report]).first)
        let groupedPeople = MetricDefinition(
            label: "交易人数",
            operation: .sum,
            tableID: manifest.id,
            field: "Measure Values",
            groupBy: ["周期"],
            filters: [HarnessFilterDefinition(field: "Measure Names", op: .equals, value: "交易人数")]
        )
        let groupedOrders = MetricDefinition(
            label: "交易笔数",
            operation: .sum,
            tableID: manifest.id,
            field: "Measure Values",
            groupBy: ["周期"],
            filters: [HarnessFilterDefinition(field: "Measure Names", op: .equals, value: "交易笔数")]
        )
        let ratio = MetricDefinition(
            label: "人均交易笔数",
            operation: .calculateRatio,
            tableID: manifest.id,
            numeratorMetricID: groupedOrders.id,
            denominatorMetricID: groupedPeople.id,
            unit: "笔/人"
        )
        let plan = AnalysisPlan(
            userQuestion: "计算人均交易笔数",
            tablesUsed: [manifest.id],
            metrics: [groupedPeople, groupedOrders, ratio]
        )

        let results = MetricExecutor.execute(plan: plan, reports: [report], manifests: [manifest])
        let derived = try XCTUnwrap(results.first { $0.metricID == ratio.id })

        XCTAssert(derived.rawValue == nil)
        XCTAssert(derived.warnings.contains { $0.contains("分组结果") || $0.contains("明确分组口径") })
    }
    func testNormalizedFactTableHandlesSemiPivotMetricPeriodValueSheets() throws {
        let report = makeSemiPivotTradeReport()
        let manifest = try XCTUnwrap(TableManifestBuilder.build(reports: [report]).first)

        XCTAssert(manifest.understanding?.shape == .semiPivot)
        XCTAssert(manifest.understanding?.metricNameColumn == "指标")
        XCTAssert(manifest.understanding?.metricValueColumn == "值")
        XCTAssert(manifest.understanding?.periodColumn == "周期")
        XCTAssert(manifest.understanding?.metricCatalog.contains { $0.metricName == "交易人数" } == true)
        XCTAssert(manifest.understanding?.metricCatalog.contains { $0.metricName == "交易金额" } == true)
        XCTAssert(manifest.understanding?.metricCatalog.contains { $0.metricName == "交易笔数" } == true)

        let factTable = try XCTUnwrap(NormalizedFactTableBuilder.build(reports: [report], manifests: [manifest]).first)

        XCTAssert(factTable.shape == .semiPivot)
        XCTAssert(factTable.rows.contains { $0.metricName == "交易人数" && $0.periodBucket == "2025H2" && $0.metricValue == 19_462 })
        XCTAssert(factTable.rows.contains { $0.metricName == "交易人数" && $0.periodBucket == "2026H1" && $0.metricValue == 32_136 })
    }
    func testNormalizedFactAnalyzerComputesH1H2BaseDerivedAndGrowth() throws {
        let report = makeSemiPivotTradeReport()
        let manifest = try XCTUnwrap(TableManifestBuilder.build(reports: [report]).first)
        let factTable = try XCTUnwrap(NormalizedFactTableBuilder.build(reports: [report], manifests: [manifest]).first)
        let intent = makeAIIntent(
            requestedMetrics: ["交易人数", "交易金额", "交易笔数", "人均交易金额", "人均交易笔数", "笔均交易金额"],
            wantsGrowthRate: true
        )
        let output = try XCTUnwrap(NormalizedFactMetricAnalyzer.analyze(
            userQuery: "帮我统计去年下半年和今年上半年的以下字段数据：交易人数、交易金额、交易笔数、人均交易金额、人均交易笔数、笔均交易金额。",
            factTables: [factTable],
            intent: intent
        ))

        XCTAssert(output.plan.createdBy == "normalized_fact_table")
        XCTAssert(output.results.contains { $0.label == "交易人数 2025 H2" && $0.rawValue == 19_462 })
        XCTAssert(output.results.contains { $0.label == "交易人数 2026 H1" && $0.rawValue == 32_136 })
        XCTAssert(output.results.contains { $0.label == "交易金额 2025 H2" && $0.rawValue == 5_047_470 })
        XCTAssert(output.results.contains { $0.label == "交易笔数 2026 H1" && $0.rawValue == 55_022 })

        let h2AvgAmount = try XCTUnwrap(output.results.first { $0.label == "人均交易金额 2025 H2" }?.rawValue)
        XCTAssert(abs(h2AvgAmount - 259.3500154146542) < 0.0001)
        let h1PerUserTxn = try XCTUnwrap(output.results.first { $0.label == "人均交易笔数 2026 H1" }?.rawValue)
        XCTAssert(abs(h1PerUserTxn - 1.7121608165297486) < 0.0001)
        let growth = try XCTUnwrap(output.results.first { $0.label.contains("交易人数 增长率") }?.rawValue)
        XCTAssert(abs(growth - 65.1217757681636) < 0.0001)
    }
    func testDerivedOnlyQuestionKeepsSupportingMetricsOutOfMainAnswer() throws {
        let report = makeSemiPivotTradeReport()
        let manifest = try XCTUnwrap(TableManifestBuilder.build(reports: [report]).first)
        let factTable = try XCTUnwrap(NormalizedFactTableBuilder.build(reports: [report], manifests: [manifest]).first)
        let question = "算下人均交易笔数和笔均交易金额 人均交易笔数是每周交易笔数相加除以每周交易人数相加 笔均交易金额是每周交易金额相加除以每周交易笔数相加"
        let intent = makeAIIntent(
            requestedMetrics: ["人均交易笔数", "笔均交易金额"],
            supportingMetrics: ["交易人数", "交易金额", "交易笔数"],
            derivedFormulas: [
                .init(metric: "人均交易笔数", numeratorMetric: "交易笔数", denominatorMetric: "交易人数", formulaText: "每周交易笔数相加除以每周交易人数相加"),
                .init(metric: "笔均交易金额", numeratorMetric: "交易金额", denominatorMetric: "交易笔数", formulaText: "每周交易金额相加除以每周交易笔数相加")
            ]
        )

        XCTAssert(intent.requestedMetrics == ["人均交易笔数", "笔均交易金额"], "requested=\(intent.requestedMetrics)")
        XCTAssert(intent.supportingMetrics.contains("交易人数"))
        XCTAssert(intent.supportingMetrics.contains("交易金额"))
        XCTAssert(intent.supportingMetrics.contains("交易笔数"))
        XCTAssert(intent.derivedFormulas.contains { $0.metric == "人均交易笔数" && $0.numeratorMetric == "交易笔数" && $0.denominatorMetric == "交易人数" })
        XCTAssert(intent.derivedFormulas.contains { $0.metric == "笔均交易金额" && $0.numeratorMetric == "交易金额" && $0.denominatorMetric == "交易笔数" })

        let output = try XCTUnwrap(NormalizedFactMetricAnalyzer.analyze(
            userQuery: question,
            factTables: [factTable],
            intent: intent
        ))

        let h2PerUserTxn = try XCTUnwrap(output.results.first { $0.label == "人均交易笔数 2025 H2" })
        XCTAssert(h2PerUserTxn.presentationRole == MetricResultPresentationRole.derivedRequested)
        XCTAssert(abs((h2PerUserTxn.rawValue ?? 0) - 1.6712568081389374) < 0.0001)
        let h2PerTxnAmount = try XCTUnwrap(output.results.first { $0.label == "笔均交易金额 2025 H2" })
        XCTAssert(h2PerTxnAmount.presentationRole == MetricResultPresentationRole.derivedRequested)
        XCTAssert(abs((h2PerTxnAmount.rawValue ?? 0) - 155.18262313226342) < 0.0001)

        XCTAssert(output.results.filter { $0.label.hasPrefix("交易人数 ") && !$0.label.contains("增长率") }.allSatisfy { $0.presentationRole == .supporting })
        XCTAssert(output.results.filter { $0.label.hasPrefix("交易金额 ") && !$0.label.contains("增长率") }.allSatisfy { $0.presentationRole == .supporting })
        XCTAssert(output.results.filter { $0.label.hasPrefix("交易笔数 ") && !$0.label.contains("增长率") }.allSatisfy { $0.presentationRole == .supporting })
        XCTAssert(output.results.filter { $0.label.contains("增长率") }.allSatisfy { $0.presentationRole == .diagnostic })

        let rendered = HarnessReportGenerator.deterministicReport(
            userQuery: question,
            sourcePolicy: .tableOnly,
            plan: output.plan,
            manifests: [manifest],
            contextEvidence: nil,
            results: output.results,
            issues: output.issues
        )
        let directAnswer = rendered.components(separatedBy: "## 本地已校验事实").first ?? rendered
        XCTAssert(directAnswer.contains("人均交易笔数 2025 H2"))
        XCTAssert(directAnswer.contains("笔均交易金额 2025 H2"))
        XCTAssert(!directAnswer.contains("交易人数 2025 H2：19,462"))
        XCTAssert(!directAnswer.contains("交易金额 2025 H2：5,047,470"))
        XCTAssert(!directAnswer.contains("交易笔数 2025 H2：32,526"))
        XCTAssert(!directAnswer.contains("增长率"))
        XCTAssert(rendered.contains("## 计算依赖"))
        XCTAssert(rendered.contains("交易人数 2025 H2"))
    }
    func testAIIntentForPeopleAndCountQuestionComputesBothMetricsWithoutLocalCauseGuess() throws {
        let report = makeSamePeopleAndCountReport()
        let manifest = try XCTUnwrap(TableManifestBuilder.build(reports: [report]).first)
        let factTable = try XCTUnwrap(NormalizedFactTableBuilder.build(reports: [report], manifests: [manifest]).first)
        let question = "目前人数和笔数相同 可能是统计上的什么原因"
        let intent = makeAIIntent(requestedMetrics: ["交易人数", "交易笔数"])

        XCTAssert(intent.requestedMetrics.contains("交易人数"), "requested=\(intent.requestedMetrics)")
        XCTAssert(intent.requestedMetrics.contains("交易笔数"), "requested=\(intent.requestedMetrics)")

        let output = try XCTUnwrap(NormalizedFactMetricAnalyzer.analyze(
            userQuery: question,
            factTables: [factTable],
            intent: intent
        ))
        XCTAssert(output.results.contains { $0.label.hasPrefix("交易人数 ") && $0.presentationRole == .requested })
        XCTAssert(output.results.contains { $0.label.hasPrefix("交易笔数 ") && $0.presentationRole == .requested })

        let rendered = HarnessReportGenerator.deterministicReport(
            userQuery: question,
            sourcePolicy: .tableOnly,
            plan: output.plan,
            manifests: [manifest],
            contextEvidence: nil,
            results: output.results,
            issues: output.issues
        )
        let directAnswer = rendered.components(separatedBy: "## 本地已校验事实").first ?? rendered

        XCTAssert(directAnswer.contains("交易人数"))
        XCTAssert(directAnswer.contains("交易笔数"))
        XCTAssert(!directAnswer.contains("订单/流水 ID"))
        XCTAssert(!directAnswer.contains("用户 ID"))
    }
    func testOrchestratorBlocksIntentParsingWithoutAISettings() async throws {
        let run = try await AnalysisHarnessOrchestrator().run(
            userQuery: "算下人均交易笔数和笔均交易金额 人均交易笔数是每周交易笔数相加除以每周交易人数相加 笔均交易金额是每周交易金额相加除以每周交易笔数相加",
            reports: [makeSemiPivotTradeReport()],
            sourcePolicy: .tableOnly,
            settings: .default
        )

        XCTAssert(run.status == .blocked)
        XCTAssert(run.validationIssues.contains { $0.code == .aiIntentParsingFailed && $0.stage == .intentParsing })
        XCTAssert(run.auditLog.contains { $0.stage == .intentParsing && $0.status == .failed })
        XCTAssert(run.reportMarkdown.contains("本轮需要 AI 先解析分析目标"))
    }
    func testAnalysisIntentParserRequiresAPIKeyBeforeLocalCalculation() async throws {
        let report = makeSemiPivotTradeReport()
        let manifest = try XCTUnwrap(TableManifestBuilder.build(reports: [report]).first)
        let factTable = try XCTUnwrap(NormalizedFactTableBuilder.build(reports: [report], manifests: [manifest]).first)
        let parser = NormalizedFactMetricAnalyzer.AnalysisIntentParser { _, _, _ in
            self.makeAIIntent(requestedMetrics: ["交易人数"])
        }

        do {
            _ = try await parser.parse(userQuery: "统计交易人数", factTables: [factTable], settings: .default)
            XCTAssert(false, "Parser should block without API key.")
        } catch let error as NormalizedFactMetricAnalyzer.AnalysisIntentParsingError {
            XCTAssert(error.localizedDescription.contains("API Key"))
        }
    }
    func testAnalysisIntentParserBlocksUnmappedAIMetrics() async throws {
        let report = makeSemiPivotTradeReport()
        let manifest = try XCTUnwrap(TableManifestBuilder.build(reports: [report]).first)
        let factTable = try XCTUnwrap(NormalizedFactTableBuilder.build(reports: [report], manifests: [manifest]).first)
        let parser = NormalizedFactMetricAnalyzer.AnalysisIntentParser { _, _, _ in
            self.makeAIIntent(requestedMetrics: ["不存在的业务指标"])
        }
        let settings = AISettings(endpoint: "https://example.com/v1/chat/completions", model: "test", apiKey: "test-key", systemPrompt: "")

        do {
            _ = try await parser.parse(userQuery: "统计不存在的业务指标", factTables: [factTable], settings: settings)
            XCTAssert(false, "Parser should block unmapped AI metric names.")
        } catch let error as NormalizedFactMetricAnalyzer.AnalysisIntentParsingError {
            XCTAssert(error.localizedDescription.contains("无法映射"))
        }
    }
    func testNormalizedFactAnalyzerDoesNotMergeOtherPeopleMetricsIntoTradePeople() throws {
        let report = makeRealLocalLifeMetricCollisionReport()
        let manifest = try XCTUnwrap(TableManifestBuilder.build(reports: [report]).first)
        let factTable = try XCTUnwrap(NormalizedFactTableBuilder.build(reports: [report], manifests: [manifest]).first)
        let intent = makeAIIntent(
            requestedMetrics: ["交易人数", "交易金额", "交易笔数", "人均交易金额", "人均交易笔数", "笔均交易金额"]
        )
        let output = try XCTUnwrap(NormalizedFactMetricAnalyzer.analyze(
            userQuery: "帮我统计去年下半年和今年上半年的以下字段数据：交易人数、交易金额、交易笔数、人均交易金额、人均交易笔数、笔均交易金额。",
            factTables: [factTable],
            intent: intent
        ))

        XCTAssert(output.results.contains { $0.label == "交易人数 2025 H2" && $0.rawValue == 19_462 })
        XCTAssert(output.results.contains { $0.label == "交易人数 2026 H1" && $0.rawValue == 32_136 })
        XCTAssert(!output.results.contains { $0.label == "交易人数 2025 H2" && $0.rawValue == 153_935 })
        XCTAssert(!output.results.contains { $0.label == "交易人数 2026 H1" && $0.rawValue == 232_552 })

        let h2AvgAmount = try XCTUnwrap(output.results.first { $0.label == "人均交易金额 2025 H2" }?.rawValue)
        let h1AvgAmount = try XCTUnwrap(output.results.first { $0.label == "人均交易金额 2026 H1" }?.rawValue)
        XCTAssert(abs(h2AvgAmount - 259.3500154146542) < 0.0001)
        XCTAssert(abs(h1AvgAmount - 211.9911003236246) < 0.0001)
    }
    func testNormalizedFactAnalyzerUsesMetricIdentitySystemAcrossBusinessDomains() throws {
        let report = makeGenericBusinessMetricCollisionReport()
        let manifest = try XCTUnwrap(TableManifestBuilder.build(reports: [report]).first)
        let factTable = try XCTUnwrap(NormalizedFactTableBuilder.build(reports: [report], manifests: [manifest]).first)

        let applicationOutput = try XCTUnwrap(NormalizedFactMetricAnalyzer.analyze(
            userQuery: "统计去年下半年和今年上半年的申请人数、申请金额、申请笔数",
            factTables: [factTable],
            intent: makeAIIntent(requestedMetrics: ["申请用户数", "申请金额", "申请笔数"])
        ))
        XCTAssert(applicationOutput.results.contains { $0.label == "申请用户数 2025 H2" && $0.rawValue == 1_000 })
        XCTAssert(applicationOutput.results.contains { $0.label == "申请用户数 2026 H1" && $0.rawValue == 1_300 })
        XCTAssert(applicationOutput.results.contains { $0.label == "申请金额 2026 H1" && $0.rawValue == 260_000 })
        XCTAssert(!applicationOutput.results.contains { $0.label.contains("新增申请人数") })
        XCTAssert(!applicationOutput.results.contains { $0.rawValue == 99_999 })

        let creditOutput = try XCTUnwrap(NormalizedFactMetricAnalyzer.analyze(
            userQuery: "统计去年下半年和今年上半年的授信人数、授信金额、授信笔数",
            factTables: [factTable],
            intent: makeAIIntent(requestedMetrics: ["授信人数", "授信金额", "授信笔数"])
        ))
        XCTAssert(creditOutput.results.contains { $0.label == "授信人数 2025 H2" && $0.rawValue == 700 })
        XCTAssert(creditOutput.results.contains { $0.label == "授信金额 2026 H1" && $0.rawValue == 180_000 })
        XCTAssert(!creditOutput.results.contains { $0.label.contains("申请") })
    }
    func testNormalizedFactAnalyzerRequiresAIIntentInsteadOfLocalGenericGuess() throws {
        let report = makeGenericBusinessMetricCollisionReport()
        let manifest = try XCTUnwrap(TableManifestBuilder.build(reports: [report]).first)
        let factTable = try XCTUnwrap(NormalizedFactTableBuilder.build(reports: [report], manifests: [manifest]).first)

        XCTAssert(NormalizedFactMetricAnalyzer.analyze(
            userQuery: "统计去年下半年和今年上半年的金额和人数",
            factTables: [factTable]
        ) == nil)
    }
    func testNormalizedFactTableForwardFillsBlankPeriodsFromRealLocalLifeShape() throws {
        let report = makeBlankPeriodLocalLifeReport()
        let manifest = try XCTUnwrap(TableManifestBuilder.build(reports: [report]).first)
        let factTable = try XCTUnwrap(NormalizedFactTableBuilder.build(reports: [report], manifests: [manifest]).first)

        XCTAssert(factTable.metricCatalog.contains { $0.metricName == "交易人数" })
        XCTAssert(factTable.metricCatalog.contains { $0.metricName == "交易金额" })
        XCTAssert(factTable.metricCatalog.contains { $0.metricName == "交易笔数" })
        XCTAssert(factTable.rows.contains { $0.metricName == "交易笔数" && $0.periodBucket == "2026H1" && $0.metricValue == 2_698 })
        XCTAssert(factTable.rows.contains { $0.metricName == "交易金额" && $0.periodBucket == "2026H1" && $0.metricValue == 352_851 })
    }
    func testNormalizedFactAnalyzerChoosesTableWithRequestedTradeMetrics() throws {
        let ratioOnlyReport = makeReport(
            headers: ["周期", "指标", "值"],
            rows: (0..<20).map { index in
                ["周期": "2026-01-\(String(format: "%02d", min(index + 1, 28)))", "指标": "%押金卡占比", "值": "0.\(index + 10)"]
            }
        )
        let tradeReport = makeBlankPeriodLocalLifeReport()
        let manifests = TableManifestBuilder.build(reports: [ratioOnlyReport, tradeReport])
        let facts = NormalizedFactTableBuilder.build(reports: [ratioOnlyReport, tradeReport], manifests: manifests)
        let output = try XCTUnwrap(NormalizedFactMetricAnalyzer.analyze(
            userQuery: "帮我统计去年下半年和今年上半年的交易人数、交易金额、交易笔数。",
            factTables: facts,
            intent: makeAIIntent(requestedMetrics: ["交易人数", "交易金额", "交易笔数"])
        ))

        XCTAssert(output.results.contains { $0.label == "交易人数 2025 H2" && $0.rawValue == 19_462 })
        XCTAssert(output.results.contains { $0.label == "交易金额 2026 H1" && $0.rawValue == 352_851 })
        XCTAssert(!output.issues.contains { $0.code == .missingField && $0.message.contains("交易人数") })
    }
    func testBlockedOutputHidesRawValidationCodesFromPrimaryAnswer() {
        let markdown = BlockedAnalysisOutput(
            title: "需要重新读取表格结构",
            reason: "当前表格没有生成可用于回答问题的已校验指标。",
            issues: [
                ValidationIssue(severity: .fatal, code: .missingField, stage: .tableUnderstanding, message: "未识别到交易人数。"),
                ValidationIssue(severity: .fatal, code: .emptyResult, stage: .resultValidation, message: "没有生成指标结果。")
            ],
            nextSteps: ["确认周期列、指标列和值列。"]
        ).markdown

        XCTAssert(!markdown.contains("[MISSING_FIELD]"))
        XCTAssert(!markdown.contains("[EMPTY_RESULT]"))
        XCTAssert(markdown.contains("需要处理的问题"))
    }
    func testOrchestratorBlocksIntentParsingWithoutLocalTradeMetricFallback() async throws {
        let run = try await AnalysisHarnessOrchestrator().run(
            userQuery: "帮我统计去年下半年和今年上半年的以下字段数据：交易人数、交易金额、交易笔数、人均交易金额、人均交易笔数、笔均交易金额。",
            reports: [makeSemiPivotTradeReport()],
            sourcePolicy: .tableOnly,
            settings: .default
        )

        XCTAssert(run.status == .blocked)
        XCTAssert(run.normalizedFactTables.first?.rows.isEmpty == false)
        XCTAssert(run.verifiedResults.isEmpty)
        XCTAssert(run.validationIssues.contains { $0.code == .aiIntentParsingFailed && $0.stage == .intentParsing })
        XCTAssert(!run.reportMarkdown.contains("未包含上述交易核心指标"))
        XCTAssert(!run.reportMarkdown.contains("完全未包含"))
    }
    func testOrchestratorBlocksAmbiguousMetricPeriodTablesInsteadOfGuessing() async throws {
        let report = makeReport(
            headers: ["周期", "指标", "备注"],
            rows: [
                ["周期": "2025-07-13 ~ 2025-07-19", "指标": "交易人数", "备注": "需要人工确认数值列"],
                ["周期": "2026-01-04 ~ 2026-01-10", "指标": "交易金额", "备注": "没有数值"]
            ]
        )
        let run = try await AnalysisHarnessOrchestrator().run(
            userQuery: "帮我统计去年下半年和今年上半年的交易人数和交易金额。",
            reports: [report],
            sourcePolicy: .tableOnly,
            settings: .default
        )

        XCTAssert(run.status == AnalysisHarnessStatus.blocked)
        XCTAssert(run.validationIssues.contains { $0.code == AnalysisHarnessValidationCode.ambiguousFieldMapping })
        XCTAssert(run.reportMarkdown.contains("未确认周期列、指标列、数值列"))
    }
    @MainActor
    func testHarnessConfirmationDoesNotTreatAIIntentTimeoutAsTableStructureIssue() {
        let store = ProductWorkflowStore(debugSnapshotWorkspace: ProductWorkspace(
            dataPacks: [],
            knowledgeEntries: [],
            aiSettings: .default
        ))
        let report = makeReport(
            headers: ["周期", "指标", "值"],
            rows: [["周期": "2026-H1", "指标": "交易人数", "值": "100"]]
        )
        let issue = ValidationIssue(
            severity: .fatal,
            code: .aiIntentParsingFailed,
            stage: .intentParsing,
            message: "AI 意图解析请求失败：The request timed out."
        )
        let run = AnalysisHarnessRun(
            status: .blocked,
            userQuery: "分析交易人数",
            tableManifest: [],
            analysisPlan: nil,
            verifiedResults: [],
            validationIssues: [issue],
            auditLog: [],
            reportMarkdown: "",
            repairAttemptsPlan: 0,
            repairAttemptsReport: 0,
            durationMilliseconds: 0
        )

        store.presentHarnessConfirmationIfNeeded(run: run, sessionID: nil, reports: [report])

        XCTAssert(store.pendingTableStructureConfirmation == nil)
        XCTAssert(store.pendingMetricMappingConfirmation == nil)
    }
    @MainActor
    func testHarnessConfirmationStillPresentsForTableUnderstandingIssue() {
        let store = ProductWorkflowStore(debugSnapshotWorkspace: ProductWorkspace(
            dataPacks: [],
            knowledgeEntries: [],
            aiSettings: .default
        ))
        var report = makeReport(
            headers: ["周期", "指标", "值"],
            rows: [["周期": "2026-H1", "指标": "交易人数", "值": "100"]]
        )
        report.semanticConfidence = 0.52
        let issue = ValidationIssue(
            severity: .fatal,
            code: .ambiguousFieldMapping,
            stage: .tableUnderstanding,
            message: "表结构需要确认周期列、指标列和值列。"
        )
        let run = AnalysisHarnessRun(
            status: .blocked,
            userQuery: "分析交易人数",
            tableManifest: [],
            analysisPlan: nil,
            verifiedResults: [],
            validationIssues: [issue],
            auditLog: [],
            reportMarkdown: "",
            repairAttemptsPlan: 0,
            repairAttemptsReport: 0,
            durationMilliseconds: 0
        )

        store.presentHarnessConfirmationIfNeeded(run: run, sessionID: nil, reports: [report])

        XCTAssert(store.pendingTableStructureConfirmation?.reason == issue.message)
        XCTAssert(store.pendingMetricMappingConfirmation == nil)
    }
    func testReportValidatorBlocksPlaceholderOutput() {
        let source = MetricResultSource(
            tableID: "table",
            tableName: "表",
            operation: .sum,
            field: "交易人数",
            groupKey: "",
            rowCount: 10,
            filtersApplied: [],
            methodology: "SUM(交易人数)"
        )
        let result = MetricResult(metricID: UUID(), label: "交易人数", rawValue: 19_462, unit: "人", format: .integer, source: source)
        let report = """
        ## 直接回答你的问题
        交易人数是 `[H2_SUM]` 人，增长率 `[Growth]%`。

        ## AI 读取到的数据
        表。
        """

        let issues = ReportValidator.validate(report: report, verifiedResults: [result], contextEvidence: nil, issues: [])

        XCTAssert(issues.contains { $0.code == AnalysisHarnessValidationCode.placeholderOutput && $0.severity == AnalysisHarnessValidationSeverity.fatal })
    }
    func testReportValidatorRequiresCitationForContextEvidenceClaims() {
        let evidence = ContextEvidenceManifest(
            sourcePolicy: .tableAndKnowledge,
            items: [
                ContextEvidenceItem(
                    sourceType: .knowledgeBase,
                    sourceID: "kb-1",
                    title: "活动口径",
                    summary: "知识库记录了活动对交易指标的解释边界。",
                    citationLabel: "K1"
                )
            ]
        )
        let report = """
        ## 直接回答你的问题
        知识库指出活动可能影响交易走势，但这里没有引用标签。

        ## AI 读取到的数据
        表。
        """

        let issues = ReportValidator.validate(report: report, verifiedResults: [], contextEvidence: evidence, issues: [])

        XCTAssert(issues.contains { $0.code == .missingCitation && $0.severity == .fatal })
    }
    func testValidationDecisionKeepsRepairableReportIssuesOutOfFatalBlock() {
        let issues = [
            ValidationIssue(severity: .fatal, code: .missingCitation, stage: .reportValidation, message: "缺引用"),
            ValidationIssue(severity: .fatal, code: .causalBoundaryRisk, stage: .reportValidation, message: "强因果"),
            ValidationIssue(severity: .fatal, code: .unverifiedNumber, stage: .reportValidation, message: "未验证数字")
        ]

        let decision = ValidationDecisionEngine.decision(for: issues)

        XCTAssert(decision.autoRepairableIssues.map(\.code).contains(.missingCitation))
        XCTAssert(decision.autoRepairableIssues.map(\.code).contains(.causalBoundaryRisk))
        XCTAssert(decision.fatalIssues.map(\.code).contains(.unverifiedNumber))
        XCTAssert(decision.blocksFinalOutput)
    }
    func testValidationDisplaySummaryKeepsAuditOnlyWarningsOffMainStatus() {
        let issues = [
            ValidationIssue(severity: .warning, code: .missingMethodology, stage: .reportValidation, message: "缺读取范围"),
            ValidationIssue(severity: .warning, code: .evidenceBoundaryMissing, stage: .reportValidation, message: "缺资料边界"),
            ValidationIssue(severity: .warning, code: .externalNumberMixedWithLocalMetric, stage: .reportValidation, message: "外部数字风险"),
            ValidationIssue(severity: .error, code: .ambiguousFieldMapping, stage: .tableUnderstanding, message: "需要确认表结构")
        ]

        let summary = ValidationDecisionEngine.displaySummary(for: issues)

        XCTAssert(summary.auditOnlyIssues.map(\.code).contains(.missingMethodology))
        XCTAssert(summary.auditOnlyIssues.map(\.code).contains(.evidenceBoundaryMissing))
        XCTAssert(summary.answerRiskIssues.map(\.code).contains(.externalNumberMixedWithLocalMetric))
        XCTAssert(summary.actionRequiredIssues.map(\.code).contains(.ambiguousFieldMapping))
        XCTAssert(summary.summaryText == "需确认 1；影响结论 1；审计提示 2")
    }
    func testAnalysisOutputRepairerNormalizesHeadingAddsCitationAndDowngradesCausalClaim() {
        let evidence = ContextEvidenceManifest(
            sourcePolicy: .tableAndKnowledge,
            items: [
                ContextEvidenceItem(
                    sourceType: .knowledgeBase,
                    sourceID: "kb-1",
                    title: "活动口径",
                    summary: "知识库记录了活动对交易指标的解释边界。",
                    citationLabel: "K1"
                )
            ]
        )
        let report = """
        ## 直接结论
        知识库指出交易变化主因是活动上线。

        ## AI 读取到的数据
        表。
        """
        let issues = [
            ValidationIssue(severity: .fatal, code: .missingMethodology, stage: .reportValidation, message: "标题不标准"),
            ValidationIssue(severity: .fatal, code: .missingCitation, stage: .reportValidation, message: "缺引用"),
            ValidationIssue(severity: .fatal, code: .causalBoundaryRisk, stage: .reportValidation, message: "强因果")
        ]

        let repaired = AnalysisOutputRepairer.repair(report, contextEvidence: evidence, issues: issues)
        let validationIssues = ReportValidator.validate(report: repaired, verifiedResults: [], contextEvidence: evidence, issues: [])

        XCTAssert(repaired.hasPrefix("## 直接回答你的问题"), repaired)
        XCTAssert(repaired.contains("[K1]"), repaired)
        XCTAssert(repaired.contains("可能贡献因素"), repaired)
        XCTAssert(!validationIssues.contains { $0.severity.blocksOutput }, validationIssues.map(\.message).joined(separator: " | "))
    }
    func testReportValidatorIgnoresPlaceholderInsideUserQuestionSection() {
        let report = """
        ## 直接回答你的问题
        已完成本地核对，本轮没有可量化结论。

        ## 用户问题
        为什么字段值还是 TBD？

        ## AI 读取到的数据
        字段里出现 TBD 字样。
        """

        let issues = ReportValidator.validate(report: report, verifiedResults: [], contextEvidence: nil, issues: [])

        XCTAssert(!issues.contains { $0.code == .placeholderOutput }, issues.map(\.message).joined(separator: " | "))
    }
    func testDeterministicReportIncludesContextEvidenceCitations() {
        let evidence = ContextEvidenceManifest(
            sourcePolicy: .tableAndKnowledge,
            items: [
                ContextEvidenceItem(
                    sourceType: .knowledgeBase,
                    sourceID: "kb-1",
                    title: "业务规则",
                    summary: "内部规则说明人均指标需要分子分母重算。",
                    citationLabel: "K1"
                )
            ]
        )
        let report = HarnessReportGenerator.deterministicReport(
            userQuery: "解释人均指标",
            sourcePolicy: .tableAndKnowledge,
            plan: AnalysisPlan(userQuestion: "解释人均指标", tablesUsed: [], metrics: []),
            manifests: [],
            contextEvidence: evidence,
            results: [],
            issues: []
        )

        XCTAssert(report.contains("## 资料证据"))
        XCTAssert(report.contains("[K1]"))
    }
    func testOrchestratorBlocksWithoutTables() async throws {
        let run = try await AnalysisHarnessOrchestrator().run(
            userQuery: "统计交易人数",
            reports: [],
            sourcePolicy: .tableOnly,
            settings: .default
        )

        XCTAssert(run.status == .blocked)
        XCTAssert(run.reportMarkdown.contains("当前任务没有可分析表"))
    }
    func testRouterDetectsQuickComputationButNotPureExplanation() {
        XCTAssert(AnalysisHarnessRouter.userMessageLooksLikeTableComputation("帮我统计今年上半年交易金额和人数增长率"))
        XCTAssert(AnalysisHarnessRouter.userMessageLooksLikeTableComputation("top 5 渠道按交易金额排名"))
        XCTAssert(!AnalysisHarnessRouter.userMessageLooksLikeTableComputation("这个结论是什么意思，帮我解释一下"))
    }
    func testRouterDetectsContextEvidenceQuestions() {
        XCTAssert(AnalysisHarnessRouter.userMessageLooksLikeContextEvidenceQuestion("结合知识库和外部资料解释为什么交易金额变化"))
        XCTAssert(AnalysisHarnessRouter.userMessageLooksLikeContextEvidenceQuestion("参考 Confluence 和 Jira 看看上线影响"))
        XCTAssert(!AnalysisHarnessRouter.userMessageLooksLikeContextEvidenceQuestion("把这句话翻译一下"))
        XCTAssert(!AnalysisHarnessRouter.userMessageLooksLikeContextEvidenceQuestion("这个结论是什么意思，帮我解释一下"))
    }
    func testSQLLikePatternEscapesWildcardsAndStringLiterals() {
        XCTAssert(AnalysisSQLRuntime.sqlLikePattern(#"a%b_c\d'e"#) == #"a\%b\_c\\d''e"#)
    }
    func testReadOnlySQLValidatorBlocksDuckDBFileReaders() {
        XCTAssert(AnalysisSQLRuntime.validateReadOnlySQL("SELECT metric, value FROM report_1_raw") == nil)
        XCTAssert(AnalysisSQLRuntime.validateReadOnlySQL("SELECT * FROM read_csv_auto('/etc/passwd')") != nil)
        XCTAssert(AnalysisSQLRuntime.validateReadOnlySQL("SELECT * FROM read_parquet('/tmp/data.parquet')") != nil)
        XCTAssert(AnalysisSQLRuntime.validateReadOnlySQL("WITH x AS (SELECT * FROM parquet_scan('/tmp/a.parquet')) SELECT * FROM x") != nil)
    }
    func testNotebookRequestedMetricSQLUsesLikeEscapeAndRuns() throws {
        let report = makeReport(
            headers: ["指标", "2025-07", "2026-01"],
            rows: [
                ["指标": "交易人数", "2025-07": "10", "2026-01": "20"]
            ]
        )
        var pack = SampleDataFactory.makeSamplePack()
        pack.importedReports = [report]
        let workspace = ProductWorkspace(dataPacks: [pack], knowledgeEntries: [], aiSettings: .default)

        let run = AnalysisSQLRuntime.buildNotebookRun(
            userRequest: "对比 2025 下半年和 2026 上半年交易人数",
            reports: [report],
            workspace: workspace,
            pack: pack,
            task: nil,
            sessionID: nil,
            messageID: nil,
            trigger: "regression-test",
            contextMode: .fullReanalysis
        )

        let cell = try XCTUnwrap(run.cells.first { $0.title == "关键指标计算结果" })
        XCTAssert(cell.sql.contains(#"ESCAPE '\'"#), cell.sql)
        XCTAssert(cell.status == .success, cell.errorMessage ?? "Expected key metric SQL to run")
        XCTAssert(cell.rows.contains { row in row.contains("交易人数") }, "Expected calculated rows to include the requested metric")
    }
    func testRouterDowngradesSimpleTasksButKeepsComputationsVerified() {
        XCTAssert(AnalysisHarnessRouter.userMessageLooksLikeLightweightTask("把上面这段话翻译成英文"))
        XCTAssert(AnalysisHarnessRouter.userMessageLooksLikeLightweightTask("这个结论是什么意思，帮我解释一下"))
        XCTAssert(!AnalysisHarnessRouter.userMessageLooksLikeLightweightTask("帮我统计今年上半年交易金额"))
        XCTAssert(!AnalysisHarnessRouter.userMessageLooksLikeLightweightTask("解释为什么交易金额变化"))
        XCTAssert(AnalysisHarnessRouter.userMessageLooksLikeMetricRelationshipExplanation("目前人数和笔数相同，可能是统计上的什么原因"))
        XCTAssert(!AnalysisHarnessRouter.userMessageNeedsVerifiedAnalysis("目前人数和笔数相同，可能是统计上的什么原因", sourcePolicy: .tableOnly))
        XCTAssert(AnalysisHarnessRouter.userMessageLooksLikeMetricRelationshipExplanation("交易人数和订单笔数一样，是不是统计口径导致的"))
        XCTAssert(!AnalysisHarnessRouter.userMessageNeedsVerifiedAnalysis("交易人数和订单笔数一样，是不是统计口径导致的", sourcePolicy: .fullContext))
        XCTAssert(!AnalysisHarnessRouter.userMessageNeedsVerifiedAnalysis("解释一下人数和笔数相等可能有哪些业务口径原因", sourcePolicy: .tableOnly))
        XCTAssert(!AnalysisHarnessRouter.userMessageNeedsVerifiedAnalysis("""
        请重新完整分析当前任务。

        本次分析目标：
        目前人数和笔数相同 可能是统计上的什么原因
        """, sourcePolicy: .tableOnly))

        XCTAssert(
            AnalysisHarnessRouter.effectiveContextMode(
                requestedMode: .fullReanalysis,
                userMessage: "把上面这段话翻译成英文",
                hasPreviousAI: false,
                cacheMatches: false
            ) == .quickFollowUp
        )
        XCTAssert(
            AnalysisHarnessRouter.effectiveContextMode(
                requestedMode: .fullReanalysis,
                userMessage: "重新分析今年上半年交易金额",
                hasPreviousAI: true,
                cacheMatches: true
            ) == .fullReanalysis
        )
        XCTAssert(AnalysisHarnessRouter.userMessageNeedsVerifiedAnalysis("帮我统计今年上半年交易金额", sourcePolicy: .tableOnly))
        XCTAssert(!AnalysisHarnessRouter.userMessageNeedsVerifiedAnalysis("把上面这段话翻译成英文", sourcePolicy: .fullContext))
    }
    func testPeriodIntentUsesLatestPeriodRequestBeforeStaleTaskGoal() {
        var report = makeReport(
            headers: ["周期", "交易人数"],
            rows: [
                ["周期": "2025 H2", "交易人数": "100"],
                ["周期": "2026 H1", "交易人数": "120"],
                ["周期": "2026 H2", "交易人数": "150"]
            ]
        )
        report.trendSummary = ReportTrendSummary(
            analysisVersion: 1,
            generatedAt: Date(),
            overview: "",
            trendBullets: [],
            distributionBullets: [],
            warnings: [],
            metricTrends: [
                ReportMetricTrend(
                    metricName: "交易人数",
                    firstValue: 100,
                    lastValue: 150,
                    delta: 50,
                    percentChange: 0.5,
                    direction: .up,
                    pointCount: 3,
                    trendStartLabel: "2025 H2",
                    trendEndLabel: "2026 H2",
                    primaryComparison: PrimaryMetricComparison(
                        previousLabel: "2026 H1",
                        currentLabel: "2026 H2",
                        previousValue: 120,
                        currentValue: 150,
                        delta: 30,
                        percentChange: 0.25,
                        direction: .up,
                        isComparable: true,
                        incomparabilityReason: "",
                        confidence: 0.8,
                        evidenceLevel: .b
                    )
                )
            ]
        )

        let intent = MetricLinkageAnomalyScanner.extractPeriodIntent(
            userRequest: "帮我分析最新周期的交易人数变化",
            taskGoal: "继续分析 2025 H2 和 2026 H1 的交易人数",
            reports: [report]
        )

        XCTAssert(intent.source == .userMessage)
        XCTAssert(intent.requestedPeriods == ["2026 H2", "2026 H1"])
        XCTAssert(intent.summary.contains("表内最新周期"))
    }

    func testPeriodIntentLatestRequestDoesNotFallbackToStaleTaskGoalWhenPeriodIsUnresolved() {
        let report = makeReport(
            headers: ["指标", "值"],
            rows: [
                ["指标": "交易人数", "值": "100"]
            ]
        )

        let intent = MetricLinkageAnomalyScanner.extractPeriodIntent(
            userRequest: "帮我分析最新周期",
            taskGoal: "继续分析 2025/07/01-2025/12/31 和 2026/01/01-2026/06/30",
            reports: [report]
        )

        XCTAssert(intent.source == .userMessage)
        XCTAssert(intent.requestedPeriods.isEmpty)
        XCTAssert(intent.summary.contains("不能沿用任务目标里的旧周期"))
    }

    func testMessageRenderSnapshotTracksVisibleMessageChanges() {
        var message = AnalysisSessionMessage(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            role: .assistant,
            kind: .aiAnalysis,
            content: "第一版回答",
            streamingStatus: AnalysisMessageStreamingStatus(
                state: .reasoning,
                title: "正在思考",
                detail: "第一段思考"
            ),
            evidence: [
                AnalysisSessionEvidence(
                    sourceType: "数据覆盖",
                    title: "读取范围",
                    detail: "已读取 1 张表"
                )
            ]
        )

        let baseline = SessionMessageRenderSnapshot(message: message)
        message.content = "第二版回答"
        XCTAssert(SessionMessageRenderSnapshot(message: message) != baseline)

        message.content = "第一版回答"
        message.streamingStatus = AnalysisMessageStreamingStatus(
            state: .completed,
            title: "已完成",
            detail: "第一段思考"
        )
        XCTAssert(SessionMessageRenderSnapshot(message: message) != baseline)

        message.streamingStatus = baseline.streamingStatus.map { snapshot in
            AnalysisMessageStreamingStatus(
                state: snapshot.state,
                title: snapshot.title,
                detail: "第一段思考"
            )
        }
        message.evidence.append(AnalysisSessionEvidence(
            sourceType: "Analysis Harness",
            title: "审计",
            detail: "新增审计证据"
        ))
        XCTAssert(SessionMessageRenderSnapshot(message: message) != baseline)

        var sameLengthEvidenceChange = message
        sameLengthEvidenceChange.evidence = [
            AnalysisSessionEvidence(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                sourceType: "数据覆盖",
                title: "读取范围",
                detail: "甲乙丙丁"
            )
        ]
        let sameLengthBaseline = SessionMessageRenderSnapshot(message: sameLengthEvidenceChange)
        sameLengthEvidenceChange.evidence[0].detail = "戊己庚辛"
        XCTAssert(SessionMessageRenderSnapshot(message: sameLengthEvidenceChange) != sameLengthBaseline)
    }
    func testMessageCollapseThresholdsAvoidFullLengthCounting() {
        let shortMessage = AnalysisSessionMessage(
            role: .assistant,
            kind: .aiAnalysis,
            content: String(repeating: "a", count: 4_000)
        )
        XCTAssert(!shortMessage.shouldDefaultCollapseAsLatestAssistantReply)

        let longMessage = AnalysisSessionMessage(
            role: .assistant,
            kind: .aiAnalysis,
            content: String(repeating: "a", count: 4_001)
        )
        XCTAssert(longMessage.shouldDefaultCollapseAsLatestAssistantReply)

        let tableMessage = AnalysisSessionMessage(
            role: .assistant,
            kind: .aiAnalysis,
            content: "AI 读取到的数据\n" + String(repeating: "b", count: 1_601)
        )
        XCTAssert(tableMessage.shouldDefaultCollapseAsLatestAssistantReply)
    }
    @MainActor
    func testShouldUseAnalysisHarnessSkipsSimpleFullReanalysisTasks() {
        let store = ProductWorkflowStore(debugSnapshotWorkspace: ProductWorkspace(
            dataPacks: [],
            knowledgeEntries: [],
            aiSettings: .default
        ))

        XCTAssert(!store.shouldUseAnalysisHarness(
            contextMode: .fullReanalysis,
            sourcePolicy: .tableOnly,
            userMessage: "这个结论是什么意思，帮我解释一下",
            referencedMessage: nil,
            selectedReportCount: 1
        ))
        XCTAssert(store.shouldUseAnalysisHarness(
            contextMode: .fullReanalysis,
            sourcePolicy: .tableOnly,
            userMessage: "帮我统计今年上半年交易金额",
            referencedMessage: nil,
            selectedReportCount: 1
        ))
    }
    func testAnswerNumberTracerMatchesChineseCompactApproximateAndPercentNumbers() throws {
        let amount = makeMetricResult(label: "交易金额 2026 H1", rawValue: 370_000, unit: "MXN", format: .currency)
        let growth = makeMetricResult(label: "交易金额 增长率（2025 H2 -> 2026 H1）", rawValue: 12.34, unit: "%", format: .percent)
        let report = """
        ## 直接回答你的问题
        交易金额 2026 H1 约37万 MXN，交易金额增长 12.34%。
        """

        let traceReport = AnswerNumberTracer.trace(report: report, verifiedResults: [amount, growth])

        let traceDebug = traceReport.traces.map { "\($0.rawText):\($0.status.rawValue):\($0.reason)" }.joined(separator: " | ")
        XCTAssert(traceReport.traces.contains { $0.rawText.contains("37万") && $0.status == .approximateMatched }, traceDebug)
        XCTAssert(traceReport.traces.contains { $0.rawText.contains("12.34%") && $0.status == .matched }, traceDebug)
        XCTAssert(!traceReport.hasBlockingTrace)
    }
    func testAnswerNumberTracerMatchesRoundedDerivedValuesAndNormalizedUnits() throws {
        let perUserTxn = makeMetricResult(
            label: "人均交易笔数 2025 H2",
            rawValue: 1.6712568081389374,
            unit: "笔/人",
            format: .decimal,
            presentationRole: .derivedRequested
        )
        let perTxnAmount = makeMetricResult(
            label: "笔均交易金额 2025 H2",
            rawValue: 155.18262313226342,
            unit: "MXN/笔",
            format: .decimal,
            presentationRole: .derivedRequested
        )
        let report = """
        ## 直接回答你的问题
        人均交易笔数：2025 H2 为 1.67 笔/人。笔均交易金额：2025 H2 为 155.18 比索/订单。
        """

        let traceReport = AnswerNumberTracer.trace(report: report, verifiedResults: [perUserTxn, perTxnAmount])
        let traceDebug = traceReport.traces.map { "\($0.rawText):\($0.status.rawValue):\($0.matchedResultLabel ?? "-"):\($0.reason)" }.joined(separator: " | ")

        XCTAssert(traceReport.traces.contains { $0.rawText.contains("1.67") && $0.status == .matched && $0.matchedResultLabel == "人均交易笔数 2025 H2" }, traceDebug)
        XCTAssert(traceReport.traces.contains { $0.rawText.contains("155.18") && $0.status == .matched && $0.matchedResultLabel == "笔均交易金额 2025 H2" }, traceDebug)
        XCTAssert(!traceReport.hasBlockingTrace, traceDebug)
    }
    func testAnswerNumberTracerIgnoresClearlyCitedEvidenceNumbers() throws {
        let people = makeMetricResult(label: "交易人数 2025 H2", rawValue: 19_462, unit: "人", format: .integer)
        let report = """
        ## 直接回答你的问题
        外部资料 [E1] 提到监管罚款 20,000 MXN。
        交易人数 2025 H2 为 19,462 人。
        """

        let traceReport = AnswerNumberTracer.trace(report: report, verifiedResults: [people])
        let traceDebug = traceReport.traces.map { "\($0.rawText):\($0.status.rawValue):\($0.reason)" }.joined(separator: " | ")

        XCTAssert(!traceReport.traces.contains { $0.rawText.contains("20,000") }, traceDebug)
        XCTAssert(traceReport.traces.contains { $0.rawText.contains("19,462") && $0.status == .matched }, traceDebug)
        XCTAssert(!traceReport.hasBlockingTrace, traceDebug)
    }
    func testAnswerNumberTracerDoesNotLinkUnitConflictingAmountToPerTransactionValue() throws {
        let amount = makeMetricResult(label: "交易金额 2025 H2", rawValue: 155.18, unit: "MXN", format: .currency)
        let perTxnAmount = makeMetricResult(
            label: "笔均交易金额 2025 H2",
            rawValue: 155.18262313226342,
            unit: "MXN/笔",
            format: .decimal,
            presentationRole: .derivedRequested
        )
        let report = """
        ## 直接回答你的问题
        笔均交易金额：2025 H2 为 155.18 MXN/笔。
        """

        let traceReport = AnswerNumberTracer.trace(report: report, verifiedResults: [amount, perTxnAmount])
        let traceDebug = traceReport.traces.map { "\($0.rawText):\($0.status.rawValue):\($0.matchedResultLabel ?? "-"):\($0.candidateLabels.joined(separator: ","))" }.joined(separator: " | ")

        XCTAssert(traceReport.traces.contains { $0.rawText.contains("155.18") && $0.status == .matched && $0.matchedResultLabel == "笔均交易金额 2025 H2" }, traceDebug)
        XCTAssert(!traceReport.traces.contains { $0.matchedResultLabel == "交易金额 2025 H2" }, traceDebug)
    }
    func testAnswerNumberTracerMarksCloseMultipleCandidatesAsAmbiguous() throws {
        let first = makeMetricResult(label: "交易人数 2026 H1", rawValue: 100_000, unit: "人", format: .integer)
        let second = makeMetricResult(label: "交易笔数 2026 H1", rawValue: 100_000, unit: "笔", format: .integer)
        let report = """
        ## 直接回答你的问题
        当前数值为 100,000。
        """

        let traceReport = AnswerNumberTracer.trace(report: report, verifiedResults: [first, second])

        XCTAssert(traceReport.traces.contains { $0.status == .ambiguous })
        XCTAssert(traceReport.hasBlockingTrace)
    }
    func testReportValidatorBlocksUnmatchedMainAnswerNumbers() {
        let result = makeMetricResult(label: "交易人数 2025 H2", rawValue: 19_462, unit: "人", format: .integer)
        let report = """
        ## 直接回答你的问题
        交易人数 2025 H2 为 20,000 人。

        ## AI 读取到的数据
        表。
        """

        let issues = ReportValidator.validate(report: report, verifiedResults: [result], contextEvidence: nil, issues: [])

        XCTAssert(issues.contains { $0.code == .unverifiedNumber && $0.severity == .fatal })
    }
    func testReportRepairRewritesFromVerifiedResultsAndRevalidates() {
        let result = makeMetricResult(label: "交易人数 2025 H2", rawValue: 19_462, unit: "人", format: .integer)
        let plan = AnalysisPlan(userQuestion: "统计交易人数", tablesUsed: ["table"], metrics: [])

        let repaired = ReportValidator.repair(
            userQuery: "统计交易人数",
            sourcePolicy: .tableOnly,
            plan: plan,
            manifests: [],
            contextEvidence: nil,
            results: [result],
            issues: []
        )
        let issues = ReportValidator.validate(report: repaired, verifiedResults: [result], contextEvidence: nil, issues: [])

        XCTAssert(repaired.contains("19,462"), repaired)
        XCTAssert(!issues.contains { $0.severity.blocksOutput })
    }
    func testDataContractValidatorWarnsButDoesNotBlockNormalWideTableWithoutDates() throws {
        let report = makeReport(
            headers: ["交易人数", "交易金额"],
            rows: [
                ["交易人数": "100", "交易金额": "200"]
            ]
        )
        let manifest = try XCTUnwrap(TableManifestBuilder.build(reports: [report]).first)

        let output = DataContractValidator.validate(manifests: [manifest])

        XCTAssert(output.summary.status == .warning)
        XCTAssert(!output.issues.contains { $0.severity.blocksOutput })
    }
    func testRootCauseInvestigatorDoesNotEmitCausalConclusionWithoutDimensions() throws {
        let report = makeSemiPivotTradeReport()
        let manifest = try XCTUnwrap(TableManifestBuilder.build(reports: [report]).first)
        let factTable = try XCTUnwrap(NormalizedFactTableBuilder.build(reports: [report], manifests: [manifest]).first)
        let output = try XCTUnwrap(NormalizedFactMetricAnalyzer.analyze(
            userQuery: "为什么交易金额变化",
            factTables: [factTable],
            intent: makeAIIntent(requestedMetrics: ["交易金额"], wantsGrowthRate: true)
        ))

        let investigation = try XCTUnwrap(RootCauseInvestigator.investigate(
            userQuery: "为什么交易金额变化",
            results: output.results,
            factTables: [factTable]
        ))

        XCTAssert(investigation.findings.contains { $0.kind == .cannotAttribute })
        XCTAssert(!investigation.summary.contains("导致"))
        XCTAssert(!investigation.summary.contains("根因"))
    }
    func testConfirmedTableUnderstandingTemplateBuildsFactsForUnusualHeaders() throws {
        let report = makeReport(
            headers: ["周度", "项目", "数值"],
            rows: [
                ["周度": "2025-07-01 ~ 2025-12-31", "项目": "交易人数", "数值": "19462"],
                ["周度": "2026-01-01 ~ 2026-06-30", "项目": "交易人数", "数值": "32136"]
            ]
        )
        let manifest = try XCTUnwrap(TableManifestBuilder.build(reports: [report]).first)
        let template = AnalysisTableUnderstandingTemplate(
            name: "测试模板",
            sourceFingerprintHint: report.sourceFingerprint,
            headerSignature: report.headers,
            shape: "半透视表",
            periodColumn: "周度",
            metricNameColumn: "项目",
            metricValueColumn: "数值",
            fillDownPeriod: true
        )

        let factTable = try XCTUnwrap(NormalizedFactTableBuilder.build(
            reports: [report],
            manifests: [manifest],
            templates: [template]
        ).first)

        XCTAssert(factTable.rows.contains { $0.metricName == "交易人数" && $0.metricValue == 19_462 })
        XCTAssert(factTable.confidence >= 0.92)
    }
    func testMetricAliasTemplateLetsRequestedMetricUseActualMetricName() throws {
        let report = makeReport(
            headers: ["周期", "指标", "值"],
            rows: [
                ["周期": "2025-07-01 ~ 2025-12-31", "指标": "订单用户", "值": "100"],
                ["周期": "2026-01-01 ~ 2026-06-30", "指标": "订单用户", "值": "150"]
            ]
        )
        let manifest = try XCTUnwrap(TableManifestBuilder.build(reports: [report]).first)
        let template = AnalysisTableUnderstandingTemplate(
            name: "指标别名模板",
            sourceFingerprintHint: report.sourceFingerprint,
            headerSignature: report.headers,
            shape: "指标-周期-值长表",
            periodColumn: "周期",
            metricNameColumn: "指标",
            metricValueColumn: "值",
            fillDownPeriod: true,
            metricAliases: ["交易人数": "订单用户"]
        )
        let factTable = try XCTUnwrap(NormalizedFactTableBuilder.build(
            reports: [report],
            manifests: [manifest],
            templates: [template]
        ).first)
        let output = try XCTUnwrap(NormalizedFactMetricAnalyzer.analyze(
            userQuery: "对比去年下半年和今年上半年的交易人数",
            factTables: [factTable],
            intent: makeAIIntent(requestedMetrics: ["交易人数"], wantsGrowthRate: true)
        ))

        XCTAssert(output.results.contains { $0.label == "交易人数 2025 H2" && $0.rawValue == 100 })
        XCTAssert(output.results.contains { $0.label == "交易人数 2026 H1" && $0.rawValue == 150 })
    }
    func testRootCauseInvestigatorRecordsMultiStepContributionAudit() throws {
        let report = makeReport(
            headers: ["周期", "指标", "值", "渠道"],
            rows: [
                ["周期": "2025-07-01 ~ 2025-12-31", "指标": "交易金额", "值": "100", "渠道": "A"],
                ["周期": "2026-01-01 ~ 2026-06-30", "指标": "交易金额", "值": "180", "渠道": "A"],
                ["周期": "2025-07-01 ~ 2025-12-31", "指标": "交易金额", "值": "30", "渠道": "B"],
                ["周期": "2026-01-01 ~ 2026-06-30", "指标": "交易金额", "值": "35", "渠道": "B"]
            ]
        )
        let manifest = try XCTUnwrap(TableManifestBuilder.build(reports: [report]).first)
        let factTable = try XCTUnwrap(NormalizedFactTableBuilder.build(reports: [report], manifests: [manifest]).first)
        let investigation = try XCTUnwrap(RootCauseInvestigator.investigate(
            userQuery: "为什么交易金额变化",
            results: [],
            factTables: [factTable]
        ))

        XCTAssert(investigation.steps.count >= 5)
        XCTAssert(investigation.findings.contains { $0.kind == .contributionBreakdown })
        XCTAssert(investigation.missingCounterEvidence.contains { $0.contains("反证") || $0.contains("日志") })
        XCTAssert(!investigation.summary.contains("导致"))
    }

    func testRealLocalLifeXLSXImportAndLocalHarnessAlgorithms() throws {
        guard let path = ProcessInfo.processInfo.environment["NEXAFLOW_REAL_XLSX_SMOKE_PATH"]?.nilIfBlank else {
            print("SKIP real XLSX smoke: missing NEXAFLOW_REAL_XLSX_SMOKE_PATH")
            return
        }
        guard FileManager.default.fileExists(atPath: path) else {
            print("SKIP real XLSX smoke: file not found \(path)")
            return
        }

        let imported = try DataImportService.importReports(from: [URL(fileURLWithPath: path)])
        let reports = imported.reports.filter { !$0.headers.isEmpty && $0.rowCount > 0 }
        let manifests = TableManifestBuilder.build(reports: reports)
        let factTables = NormalizedFactTableBuilder.build(reports: reports, manifests: manifests)
        let metricCatalog = factTables.flatMap(\.metricCatalog).map(\.metricName)

        XCTAssert(!reports.isEmpty, "No reports imported from \(path)")
        XCTAssert(!manifests.isEmpty, "No manifests built from \(path)")
        XCTAssert(!factTables.isEmpty, "No normalized fact tables built from \(path). manifests=\(manifests.map(\.displayName).joined(separator: ","))")
        XCTAssert(metricCatalog.contains("交易人数"), "metrics=\(metricCatalog.prefix(80).joined(separator: ","))")
        XCTAssert(metricCatalog.contains("交易金额"), "metrics=\(metricCatalog.prefix(80).joined(separator: ","))")
        XCTAssert(metricCatalog.contains("交易笔数"), "metrics=\(metricCatalog.prefix(80).joined(separator: ","))")

        let output = try XCTUnwrap(NormalizedFactMetricAnalyzer.analyze(
            userQuery: "帮我统计去年下半年和今年上半年的交易人数、交易金额、交易笔数。",
            factTables: factTables,
            intent: makeAIIntent(requestedMetrics: ["交易人数", "交易金额", "交易笔数"], wantsGrowthRate: true)
        ))
        let resultDebug = output.results.map { "\($0.label)=\($0.displayValue)" }.joined(separator: " | ")

        XCTAssert(output.results.contains { $0.label == "交易人数 2025 H2" && $0.rawValue != nil }, resultDebug)
        XCTAssert(output.results.contains { $0.label == "交易人数 2026 H1" && $0.rawValue != nil }, resultDebug)
        XCTAssert(output.results.contains { $0.label == "交易金额 2025 H2" && $0.rawValue != nil }, resultDebug)
        XCTAssert(output.results.contains { $0.label == "交易金额 2026 H1" && $0.rawValue != nil }, resultDebug)
        XCTAssert(output.results.contains { $0.label == "交易笔数 2025 H2" && $0.rawValue != nil }, resultDebug)
        XCTAssert(output.results.contains { $0.label == "交易笔数 2026 H1" && $0.rawValue != nil }, resultDebug)
        XCTAssert(!output.issues.contains { $0.severity.blocksOutput }, output.issues.map(\.message).joined(separator: " | "))
        print("REAL_XLSX_SMOKE_OK reports=\(reports.count) factTables=\(factTables.count) metrics=\(metricCatalog.count) results=\(output.results.count)")
    }

    func testLiveAIStreamingServiceSmoke() async throws {
        let workspace = try XCTUnwrap(ProductWorkflowStore.loadWorkspace(), "未找到本机 workspace，无法读取 AI 设置。")
        let settings = workspace.aiSettings
        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RegressionTestFailure(message: "Live AI smoke requested but AI API key is missing.", file: #filePath, line: #line)
        }

        let result = try await AIStreamingService().runStreamingAnalysis(
            prompt: "请只输出一句中文：NexaFlow live smoke ok。",
            settings: settings,
            timeout: 60,
            onProgress: { _ in },
            onDelta: { _ in }
        )

        XCTAssert(!result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "AI streaming returned empty output")
        print("LIVE_AI_STREAMING_OK chars=\(result.output.count) streamed=\(result.didReceiveStreamDeltas)")
    }

    func testLiveHarnessAnalysisSmoke() async throws {
        let workspace = try XCTUnwrap(ProductWorkflowStore.loadWorkspace(), "未找到本机 workspace，无法读取 AI 设置。")
        let settings = workspace.aiSettings
        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RegressionTestFailure(message: "Live harness smoke requested but AI API key is missing.", file: #filePath, line: #line)
        }

        let run = try await AnalysisHarnessOrchestrator().run(
            userQuery: "帮我统计去年下半年和今年上半年的交易人数、交易金额、交易笔数。",
            reports: [makeSemiPivotTradeReport()],
            sourcePolicy: .tableOnly,
            settings: settings
        )

        XCTAssert(run.verifiedResults.contains { $0.label == "交易人数 2025 H2" && $0.rawValue == 19_462 })
        XCTAssert(!run.reportMarkdown.contains("未包含上述交易核心指标"))
        XCTAssert(!run.reportMarkdown.contains("[MISSING_FIELD]"))
        XCTAssert(!run.reportMarkdown.contains("[EMPTY_RESULT]"))
        XCTAssert(run.status == .success || run.status == .successWithWarnings, "status=\(run.status.rawValue), report=\(run.reportMarkdown)")
        print("LIVE_HARNESS_OK status=\(run.status.rawValue) results=\(run.verifiedResults.count) reportChars=\(run.reportMarkdown.count)")
    }

    private func makeAIIntent(
        requestedMetrics: [String],
        supportingMetrics: [String] = [],
        derivedFormulas: [NormalizedFactMetricAnalyzer.AnalysisIntent.DerivedFormula] = [],
        wantsGrowthRate: Bool = false,
        aggregationMode: String = "unknown",
        notes: [String] = []
    ) -> NormalizedFactMetricAnalyzer.AnalysisIntent {
        NormalizedFactMetricAnalyzer.AnalysisIntent(
            requestedMetrics: requestedMetrics,
            supportingMetrics: supportingMetrics,
            derivedFormulas: derivedFormulas,
            wantsGrowthRate: wantsGrowthRate,
            aggregationMode: aggregationMode,
            confidence: 0.96,
            source: .ai,
            notes: notes
        )
    }

    private func makeReport(headers: [String], rows: [[String: String]]) -> ImportedReport {
        ImportedReport(
            id: UUID(),
            fileName: "测试表.xlsx",
            kind: .generic,
            importedAt: Date(),
            rowCount: rows.count,
            headers: headers,
            sampleRows: rows,
            storedDataRows: rows,
            sourceFormat: .xlsx
        )
    }

    private func makeMetricResult(
        label: String,
        rawValue: Double,
        unit: String,
        format: MetricResultFormat,
        presentationRole: MetricResultPresentationRole = .requested
    ) -> MetricResult {
        MetricResult(
            metricID: UUID(),
            label: label,
            rawValue: rawValue,
            unit: unit,
            format: format,
            source: MetricResultSource(
                tableID: "table",
                tableName: "测试表",
                operation: .sum,
                field: label,
                groupKey: "",
                rowCount: 1,
                filtersApplied: [],
                methodology: "本地测试结果"
            ),
            presentationRole: presentationRole
        )
    }

    private func makeSemiPivotTradeReport() -> ImportedReport {
        let headers = ["周期", "指标", "值", "%环比", "生活缴费", "%生活缴费占比"]
        let rows: [[String: String]] = [
            ["周期": "2025-07-13 ~ 2025-07-19", "指标": "交易人数", "值": "19462", "%环比": "0.01", "生活缴费": "100", "%生活缴费占比": "0.10"],
            ["周期": "2025-07-13 ~ 2025-07-19", "指标": "交易金额", "值": "5047470", "%环比": "0.02", "生活缴费": "200", "%生活缴费占比": "0.20"],
            ["周期": "2025-07-13 ~ 2025-07-19", "指标": "交易笔数", "值": "32526", "%环比": "0.03", "生活缴费": "300", "%生活缴费占比": "0.30"],
            ["周期": "2026-01-04 ~ 2026-01-10", "指标": "交易人数", "值": "32136", "%环比": "0.04", "生活缴费": "400", "%生活缴费占比": "0.40"],
            ["周期": "2026-01-04 ~ 2026-01-10", "指标": "交易金额", "值": "6812546", "%环比": "0.05", "生活缴费": "500", "%生活缴费占比": "0.50"],
            ["周期": "2026-01-04 ~ 2026-01-10", "指标": "交易笔数", "值": "55022", "%环比": "0.06", "生活缴费": "600", "%生活缴费占比": "0.60"]
        ]
        return makeReport(headers: headers, rows: rows)
    }

    private func makeSamePeopleAndCountReport() -> ImportedReport {
        let headers = ["周期", "指标", "值"]
        let rows: [[String: String]] = [
            ["周期": "2025-07-13 ~ 2025-07-19", "指标": "交易人数", "值": "821"],
            ["周期": "", "指标": "交易笔数", "值": "821"],
            ["周期": "2025-07-20 ~ 2025-07-26", "指标": "交易人数", "值": "765"],
            ["周期": "", "指标": "交易笔数", "值": "765"],
            ["周期": "2026-01-04 ~ 2026-01-10", "指标": "交易人数", "值": "912"],
            ["周期": "", "指标": "交易笔数", "值": "912"],
            ["周期": "2026-01-11 ~ 2026-01-17", "指标": "交易人数", "值": "875"],
            ["周期": "", "指标": "交易笔数", "值": "875"]
        ]
        return makeReport(headers: headers, rows: rows)
    }

    private func makeBlankPeriodLocalLifeReport() -> ImportedReport {
        let headers = ["周期", "指标", "值", "%环比", "%押金卡占比", "%普通卡占比", "%新用户占比", "%老用户占比"]
        let rows: [[String: String]] = [
            ["周期": "2025-07-13 ~ 2025-07-19", "指标": "交易人数", "值": "19462", "%环比": "0.01", "%押金卡占比": "0.35", "%普通卡占比": "0.65", "%新用户占比": "0.05", "%老用户占比": "0.95"],
            ["周期": "", "指标": "交易笔数", "值": "32526", "%环比": "0.03", "%押金卡占比": "0.36", "%普通卡占比": "0.64", "%新用户占比": "0.05", "%老用户占比": "0.95"],
            ["周期": "", "指标": "交易金额", "值": "5047470", "%环比": "0.02", "%押金卡占比": "0.20", "%普通卡占比": "0.80", "%新用户占比": "0.03", "%老用户占比": "0.97"],
            ["周期": "", "指标": "本地生活覆盖用户占比", "值": "64.71%", "%环比": "", "%押金卡占比": "", "%普通卡占比": "", "%新用户占比": "", "%老用户占比": ""],
            ["周期": "2026-06-14 ~ 2026-06-20", "指标": "交易人数", "值": "1567", "%环比": "0.06", "%押金卡占比": "0.35", "%普通卡占比": "0.65", "%新用户占比": "0.05", "%老用户占比": "0.95"],
            ["周期": "", "指标": "交易笔数", "值": "2698", "%环比": "0.08", "%押金卡占比": "0.39", "%普通卡占比": "0.61", "%新用户占比": "0.04", "%老用户占比": "0.96"],
            ["周期": "", "指标": "交易金额", "值": "352851", "%环比": "0.30", "%押金卡占比": "0.20", "%普通卡占比": "0.80", "%新用户占比": "0.03", "%老用户占比": "0.97"]
        ]
        return makeReport(headers: headers, rows: rows)
    }

    private func makeRealLocalLifeMetricCollisionReport() -> ImportedReport {
        let headers = ["周期", "指标", "值", "%环比", "%押金卡占比", "%普通卡占比", "%新用户占比", "%老用户占比"]
        let rows: [[String: String]] = [
            ["周期": "2025-07-13 ~ 2025-12-31", "指标": "交易人数", "值": "19462", "%环比": "", "%押金卡占比": "", "%普通卡占比": "", "%新用户占比": "", "%老用户占比": ""],
            ["周期": "", "指标": "交易笔数", "值": "32526", "%环比": "", "%押金卡占比": "", "%普通卡占比": "", "%新用户占比": "", "%老用户占比": ""],
            ["周期": "", "指标": "本周初次交易人数", "值": "2992", "%环比": "", "%押金卡占比": "", "%普通卡占比": "", "%新用户占比": "", "%老用户占比": ""],
            ["周期": "", "指标": "交易金额", "值": "5047470", "%环比": "", "%押金卡占比": "", "%普通卡占比": "", "%新用户占比": "", "%老用户占比": ""],
            ["周期": "", "指标": "本地生活累计覆盖用户数", "值": "131481", "%环比": "", "%押金卡占比": "", "%普通卡占比": "", "%新用户占比": "", "%老用户占比": ""],
            ["周期": "", "指标": "本地生活覆盖用户占比", "值": "66.17", "%环比": "", "%押金卡占比": "", "%普通卡占比": "", "%新用户占比": "", "%老用户占比": ""],
            ["周期": "2026-01-04 ~ 2026-06-20", "指标": "交易人数", "值": "32136", "%环比": "", "%押金卡占比": "", "%普通卡占比": "", "%新用户占比": "", "%老用户占比": ""],
            ["周期": "", "指标": "交易笔数", "值": "55022", "%环比": "", "%押金卡占比": "", "%普通卡占比": "", "%新用户占比": "", "%老用户占比": ""],
            ["周期": "", "指标": "本周初次交易人数", "值": "7814", "%环比": "", "%押金卡占比": "", "%普通卡占比": "", "%新用户占比": "", "%老用户占比": ""],
            ["周期": "", "指标": "交易金额", "值": "6812546", "%环比": "", "%押金卡占比": "", "%普通卡占比": "", "%新用户占比": "", "%老用户占比": ""],
            ["周期": "", "指标": "本地生活累计覆盖用户数", "值": "192602", "%环比": "", "%押金卡占比": "", "%普通卡占比": "", "%新用户占比": "", "%老用户占比": ""],
            ["周期": "", "指标": "本地生活覆盖用户占比", "值": "64.71", "%环比": "", "%押金卡占比": "", "%普通卡占比": "", "%新用户占比": "", "%老用户占比": ""]
        ]
        return makeReport(headers: headers, rows: rows)
    }

    private func makeGenericBusinessMetricCollisionReport() -> ImportedReport {
        let headers = ["周期", "指标", "值"]
        let rows: [[String: String]] = [
            ["周期": "2025-07-01 ~ 2025-12-31", "指标": "申请用户数", "值": "1000"],
            ["周期": "", "指标": "新增申请人数", "值": "99999"],
            ["周期": "", "指标": "申请金额", "值": "200000"],
            ["周期": "", "指标": "申请笔数", "值": "1200"],
            ["周期": "", "指标": "授信人数", "值": "700"],
            ["周期": "", "指标": "授信金额", "值": "150000"],
            ["周期": "", "指标": "授信笔数", "值": "800"],
            ["周期": "", "指标": "累计覆盖用户数", "值": "500000"],
            ["周期": "", "指标": "覆盖用户占比", "值": "65.1"],
            ["周期": "2026-01-01 ~ 2026-06-30", "指标": "申请用户数", "值": "1300"],
            ["周期": "", "指标": "新增申请人数", "值": "88888"],
            ["周期": "", "指标": "申请金额", "值": "260000"],
            ["周期": "", "指标": "申请笔数", "值": "1500"],
            ["周期": "", "指标": "授信人数", "值": "900"],
            ["周期": "", "指标": "授信金额", "值": "180000"],
            ["周期": "", "指标": "授信笔数", "值": "1000"],
            ["周期": "", "指标": "累计覆盖用户数", "值": "620000"],
            ["周期": "", "指标": "覆盖用户占比", "值": "68.3"]
        ]
        return makeReport(headers: headers, rows: rows)
    }
}
