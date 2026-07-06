import CryptoKit
import Foundation

enum DataImportService {
    static func importDataPack(from folderURL: URL) throws -> DataPack {
        let manifest = try loadManifest(from: folderURL)
        let period = manifest.period.isEmpty ? folderURL.lastPathComponent : manifest.period

        let updates = try loadProductUpdates(from: folderURL)
        let metrics = try loadMetrics(from: folderURL)
        let events = try loadEvents(from: folderURL)
        let feedback = try loadFeedback(from: folderURL)
        let reports = try loadImportedReports(from: folderURL)
        let fieldDefinitions = buildFieldDefinitions(for: reports)

        guard !updates.isEmpty || !metrics.isEmpty || !events.isEmpty || !feedback.isEmpty || !reports.isEmpty else {
            throw ImportError.unsupportedFolder(folderURL.path)
        }

        var pack = DataPack(
            id: UUID(),
            name: folderURL.lastPathComponent,
            period: period,
            importedAt: Date(),
            sourcePath: folderURL.path,
            manifest: manifest,
            productUpdates: updates,
            metrics: metrics,
            events: events,
            feedback: feedback,
            importedReports: reports,
            fieldDefinitions: fieldDefinitions,
            qualityReport: QualityReport(
                generatedAt: Date(),
                verdict: .caution,
                issues: [],
                stats: QualityStats(updateCount: updates.count, metricCount: metrics.count, eventCount: events.count, feedbackCount: feedback.count, metricDateCount: Set(metrics.map(\.date)).count)
            ),
            analysisReport: AnalysisReport(generatedAt: Date(), summary: "", metricInsights: [], attributionFindings: [], opportunities: []),
            decisionMemo: DecisionMemo(generatedAt: Date(), markdown: "", aiSupplement: ""),
            analysisGateStatus: .needsImportReview
        )
        pack.qualityReport = AnalysisEngine.buildQualityReport(for: pack)
        return pack
    }

    static func importReports(from urls: [URL]) throws -> (reports: [ImportedReport], fieldDefinitions: [ReportFieldDefinition]) {
        var reports: [ImportedReport] = []
        for url in urls {
            let fingerprint = sourceFingerprint(for: url)
            switch url.pathExtension.lowercased() {
            case "csv", "tsv":
                reports.append(try importedReport(
                    fileName: url.lastPathComponent,
                    sourceFileName: url.lastPathComponent,
                    sourceFingerprint: fingerprint,
                    table: CSVParser.parse(fileURL: url)
                ))
            case "xlsx", "xls":
                let tables = try ExcelParser.parse(fileURL: url)
                for table in tables {
                    let name = [url.lastPathComponent, table.sheetName].compactMap { $0?.nilIfBlank }.joined(separator: " / ")
                    reports.append(try importedReport(
                        fileName: name,
                        sourceFileName: url.lastPathComponent,
                        sourceFingerprint: fingerprint,
                        table: table
                    ))
                }
            default:
                continue
            }
        }
        return (reports, buildFieldDefinitions(for: reports))
    }

    static func importCSVReports(from urls: [URL]) throws -> (reports: [ImportedReport], fieldDefinitions: [ReportFieldDefinition]) {
        try importReports(from: urls)
    }

    static func importTableauReport(
        fileName: String,
        sourceFileName: String,
        sourceFingerprint: String,
        table: CSVTable,
        metadata: ImportedReportSourceMetadata
    ) throws -> ImportedReport {
        var tableauTable = table
        tableauTable.sourceFormat = .tableau
        tableauTable.sheetName = tableauTable.sheetName ?? metadata.viewName.nilIfBlank
        tableauTable.parseWarnings.append("当前报表来自 Tableau 视图导出，可能受 Tableau 视图筛选、聚合、权限和 Crosstab 导出范围限制。")
        return try importedReport(
            fileName: fileName,
            sourceFileName: sourceFileName,
            sourceFingerprint: sourceFingerprint,
            table: tableauTable,
            sourceMetadata: metadata
        )
    }

    private static func importedReport(
        fileName: String,
        sourceFileName: String,
        sourceFingerprint: String,
        table: CSVTable,
        sourceMetadata: ImportedReportSourceMetadata? = nil
    ) throws -> ImportedReport {
        let detection = reportKind(for: fileName, table: table)
        let timeAxisProfile = ReportTimeAxisDetector.detect(table: table)
        let trendSummary = ReportTrendAnalyzer.analyze(fileName: fileName, kind: detection.kind, table: table, timeAxisProfile: timeAxisProfile)
        let semanticInference = ReportSemanticInferencer.infer(
            fileName: fileName,
            kind: detection.kind,
            table: table,
            detectedConfidence: detection.confidence,
            trendSummary: trendSummary
        )
        var report = ImportedReport(
            id: UUID(),
            fileName: fileName,
            kind: detection.kind,
            importedAt: Date(),
            sourceFileName: sourceFileName,
            sourceFingerprint: sourceFingerprint,
            rowCount: table.rows.count,
            headers: table.headers,
            firstColumnValues: table.firstColumnValues,
            fieldExamples: table.fieldExamples,
            sampleRows: storedRows(for: table),
            storedDataRows: TableContextPackageBuilder.storedRows(for: table),
            rawRows: table.rawRows,
            shape: table.shape,
            sourceFormat: table.sourceFormat,
            sheetName: table.sheetName,
            sheetIndex: table.sheetIndex,
            sourceMetadata: sourceMetadata,
            parseWarnings: table.parseWarnings,
            cellTypeHints: table.cellTypeHints,
            detectedConfidence: detection.confidence,
            originalEncoding: table.originalEncoding,
            delimiter: table.delimiter,
            semanticStatus: semanticInference.status,
            semanticConfidence: semanticInference.confidence,
            semanticProfile: semanticInference.profile,
            understandingMessages: semanticInference.message.map { [$0] } ?? [],
            trendSummary: trendSummary,
            timeAxisProfile: timeAxisProfile
        )
        let context = TableContextPackageBuilder.build(for: report)
        report.tableContextCoverage = context.coverage
        report.metricSemanticProfiles = AITableFirstAnalysisService.initialMetricProfiles(for: report)
        report.auditSteps = auditSteps(for: report, matchedMemoryCount: 0)
        return report
    }

    static func auditSteps(for report: ImportedReport, matchedMemoryCount: Int = 0) -> [ImportAuditStep] {
        var steps: [ImportAuditStep] = []
        let hasReadableRows = report.rowCount > 0 && !report.headers.isEmpty
        let parseBlockingWarnings = actionableWarnings(report.parseWarnings).filter {
            $0.contains("为空") || $0.contains("未解析到有效数据行")
        }
        steps.append(ImportAuditStep(
            kind: .parsing,
            status: hasReadableRows && parseBlockingWarnings.isEmpty ? .completed : .blocked,
            confidence: hasReadableRows ? 0.95 : 0.1,
            details: hasReadableRows
                ? "已读取 \(report.sourceFormat.label) 数据，得到 \(report.rowCount) 行、\(report.headers.count) 列。"
                : "没有读取到可用于分析的数据行或表头。",
            warnings: parseBlockingWarnings
        ))

        steps.append(ImportAuditStep(
            kind: .sheetSplit,
            status: .completed,
            confidence: 1,
            details: report.sourceFormat == .csv
                ? "CSV 单文件生成 1 张报表。"
                : "Workbook 中的可见非空 Sheet「\(report.sheetName ?? "Sheet")」已生成 1 张报表。",
            warnings: actionableWarnings(report.parseWarnings).filter { $0.contains("隐藏") || $0.contains("合并单元格") }
        ))

        let structureNeedsConfirmation = report.shape == .unknown || report.headers.count > 200
        steps.append(ImportAuditStep(
            kind: .structureDetection,
            status: structureNeedsConfirmation ? .needsConfirmation : .completed,
            confidence: report.shape == .unknown ? 0.35 : report.headers.count > 200 ? 0.68 : 0.9,
            details: "识别为\(report.shape.label)，表头字段 \(report.headers.count) 个，首列指标 \(report.firstColumnValues.count) 个。",
            warnings: structureNeedsConfirmation ? ["结构识别置信度低"] : []
        ))

        let typeNeedsConfirmation = report.kind == .generic || report.detectedConfidence < 0.65
        steps.append(ImportAuditStep(
            kind: .typeDetection,
            status: typeNeedsConfirmation ? .needsConfirmation : .completed,
            confidence: report.detectedConfidence,
            details: "识别为\(report.kind.label)，置信度 \(Int(report.detectedConfidence * 100))%。",
            warnings: typeNeedsConfirmation ? ["类型置信度低"] : []
        ))

        let timeAxisWarnings = report.trendSummary.warnings.filter {
            $0.contains("时间轴") || $0.contains("时间字段")
        } + report.timeAxisProfile.warnings
        let timeAxisRiskWarnings = (report.timeAxisProfile.orientation == .unknown ||
            report.timeAxisProfile.candidateDateColumns.count > 1)
            ? ["时间口径未完全确认；这只是本地风险提示，不阻塞 AI 分析。"]
            : []
        steps.append(ImportAuditStep(
            kind: .timeAxisDetection,
            status: .completed,
            confidence: max(0.35, report.timeAxisProfile.confidence),
            details: "时间口径：\(report.timeAxisProfile.summary)。本地识别只作为候选，不会阻塞 AI 分析。",
            warnings: (timeAxisWarnings + timeAxisRiskWarnings).uniqued()
        ))

        let partialWarnings = latestPeriodWarnings(for: report)
        steps.append(ImportAuditStep(
            kind: .latestPeriodCompleteness,
            status: partialWarnings.isEmpty ? .completed : .needsConfirmation,
            confidence: partialWarnings.isEmpty ? 0.9 : 0.7,
            details: partialWarnings.isEmpty
                ? "未发现明显候选成熟口径风险。"
                : "发现部分指标可能存在滞后或成熟口径；本地只做风险提示，不预先排除周期。",
            warnings: partialWarnings
        ))

        let fieldCount = fieldDefinitionNames(for: report).count
        steps.append(ImportAuditStep(
            kind: .fieldDictionary,
            status: fieldCount > 0 ? .completed : .needsConfirmation,
            confidence: fieldCount > 0 ? 0.85 : 0.45,
            details: fieldCount > 0
                ? "已从第一行/表头和第一列指标提取 \(fieldCount) 个字段标签。"
                : "没有提取到可解释的字段标签。",
            warnings: fieldCount > 0 ? [] : ["字段字典为空"]
        ))

        let semanticNeedsConfirmation = semanticNeedsConfirmation(report)
        steps.append(ImportAuditStep(
            kind: .reportSemantic,
            status: semanticNeedsConfirmation ? .needsConfirmation : .completed,
            confidence: report.semanticConfidence,
            details: report.semanticProfile.summary.nilIfBlank ?? "尚未形成报表含义摘要。",
            warnings: semanticNeedsConfirmation ? ["表格含义未确认"] : []
        ))

        let coverage = report.tableContextCoverage ?? TableContextPackageBuilder.build(for: report).coverage
        let coverageWarnings = coverage.limitations.filter {
            $0.contains("未发送") || $0.contains("未保存") || $0.contains("未成熟")
        }
        steps.append(ImportAuditStep(
            kind: .aiCoverageValidation,
            status: coverageWarnings.isEmpty ? .completed : .acceptedRisk,
            confidence: coverage.sentRows == coverage.totalRows && coverage.sentMetrics == coverage.totalMetrics ? 0.95 : 0.72,
            details: "AI 上下文覆盖：\(coverage.summary)。\(coverage.omittedRowsDescription)",
            warnings: coverageWarnings,
            usedAI: false
        ))

        if let ai = report.aiFirstAnalysis {
            steps.append(ImportAuditStep(
                kind: .aiTableUnderstanding,
                status: ai.readyForAnalysis ? .completed : .needsConfirmation,
                confidence: ai.validationWarnings.isEmpty ? 0.86 : 0.64,
                details: ai.summary.nilIfBlank ?? "AI 已完成表格理解，但没有返回摘要。",
                warnings: ai.validationWarnings,
                usedAI: true
            ))
        } else {
            steps.append(ImportAuditStep(
                kind: .aiTableUnderstanding,
                status: .acceptedRisk,
                confidence: 0.5,
                details: "尚未运行 AI 预读；这是可选步骤，选定当前分析任务报表后也可以直接在分析会话中发送给 AI。",
                warnings: ["AI 表格理解待运行"],
                usedAI: false
            ))
        }

        steps.append(ImportAuditStep(
            kind: .memoryMatch,
            status: .completed,
            confidence: matchedMemoryCount > 0 ? 0.8 : 0.5,
            details: matchedMemoryCount > 0
                ? "命中 \(matchedMemoryCount) 条同类报表规则或知识库记忆。"
                : "未命中同类报表记忆，本次使用自动识别草稿。",
            warnings: []
        ))

        let preAdmissionIssues = steps.filter { $0.status == .needsConfirmation || $0.status == .blocked }
        steps.append(ImportAuditStep(
            kind: .analysisAdmission,
            status: preAdmissionIssues.isEmpty ? .completed : (preAdmissionIssues.contains { $0.status == .blocked } ? .blocked : .needsConfirmation),
            confidence: preAdmissionIssues.isEmpty ? 0.9 : 0.5,
            details: preAdmissionIssues.isEmpty
                ? "该报表可以进入分析上下文。"
                : "该报表还有 \(preAdmissionIssues.count) 个问题需要处理或接受风险。",
            warnings: preAdmissionIssues.flatMap(\.warnings).uniqued()
        ))
        return steps
    }

    static func storedRows(for table: CSVTable) -> [[String: String]] {
        let limit = table.shape == .pivotWide ? 1_000 : 300
        return Array(table.rows.prefix(limit))
    }

    private static func sourceFingerprint(for url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else {
            let attributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
            let size = attributes[.size] as? NSNumber
            let modified = attributes[.modificationDate] as? Date
            return [url.lastPathComponent, size?.stringValue, modified.map { DateFormatting.shortDateTime.string(from: $0) }]
                .compactMap { $0 }
                .joined(separator: "|")
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func actionableWarnings(_ warnings: [String]) -> [String] {
        warnings.filter {
            !$0.contains("识别为透视宽表") &&
                !$0.contains("已标准化 CSV 换行符")
        }
    }

    private static func latestPeriodWarnings(for report: ImportedReport) -> [String] {
        var warnings = report.trendSummary.warnings.filter {
            $0.contains("最新") || $0.contains("未完整") || $0.contains("成熟")
        }
        warnings.append(contentsOf: report.trendSummary.metricTrends.compactMap { trend in
            guard trend.latestPointIsPartial == true else { return nil }
            let label = trend.partialLatestLabel ?? "最新周期"
            let reason = trend.partialLatestPointReason ?? "未完整"
            return "\(trend.metricName)：\(label) \(reason)"
        })
        return warnings.uniqued()
    }

    private static func semanticNeedsConfirmation(_ report: ImportedReport) -> Bool {
        if report.semanticStatus == .confirmed || report.semanticStatus == .autoInferred {
            return false
        }
        return report.semanticProfile.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            report.semanticConfidence < 0.66
    }

    private static func loadManifest(from folderURL: URL) throws -> DataManifest {
        let manifestURL = folderURL.appendingPathComponent("data_manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return DataManifest.fallback(period: folderURL.lastPathComponent, sourcePath: folderURL.path)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = DateParsing.parse(raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date \(raw)")
        }

        let data = try Data(contentsOf: manifestURL)
        return try decoder.decode(DataManifest.self, from: data)
    }

    private static func loadProductUpdates(from folderURL: URL) throws -> [ProductUpdate] {
        guard let url = firstExistingFile(in: folderURL, names: ["product_updates.csv", "updates.csv", "产品更新记录.csv"]) else {
            return []
        }

        let table = try CSVParser.parse(fileURL: url)
        return table.rows.compactMap { row in
            guard let date = DateParsing.parse(value(in: row, aliases: ["update_date", "date", "日期", "上线时间"])) else {
                return nil
            }

            return ProductUpdate(
                id: UUID(),
                date: date,
                module: value(in: row, aliases: ["feature/module", "module", "feature", "功能模块", "模块"], fallback: "未归类模块"),
                changeType: value(in: row, aliases: ["change_type", "type", "更新类型", "类型"], fallback: "产品更新"),
                targetUser: value(in: row, aliases: ["target_user", "users", "目标用户", "影响用户"], fallback: "全量"),
                expectedMetric: value(in: row, aliases: ["expected_metric", "metric", "预期指标", "影响指标"], fallback: "未声明"),
                owner: value(in: row, aliases: ["owner", "负责人"], fallback: "未记录"),
                releaseNote: value(in: row, aliases: ["release_note", "note", "title", "更新说明", "说明"], fallback: "未填写更新说明"),
                riskNote: value(in: row, aliases: ["risk_note", "risk", "风险说明"], fallback: "")
            )
        }
    }

    private static func loadMetrics(from folderURL: URL) throws -> [MetricPoint] {
        let metricFiles = [
            "core_metrics_daily.csv",
            "funnel_metrics.csv",
            "metrics.csv",
            "核心指标.csv",
            "漏斗指标.csv"
        ]

        var points: [MetricPoint] = []
        for name in metricFiles {
            let url = folderURL.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let table = try CSVParser.parse(fileURL: url)
            points.append(contentsOf: parseMetricTable(table))
        }
        return points
    }

    private static func parseMetricTable(_ table: CSVTable) -> [MetricPoint] {
        var result: [MetricPoint] = []
        let normalizedHeaders = Set(table.headers.map(\.normalizedKey))
        let hasLongFormat = normalizedHeaders.contains("metric") || normalizedHeaders.contains("指标")

        for row in table.rows {
            guard let date = DateParsing.parse(value(in: row, aliases: ["date", "日期"])) else { continue }

            let segment = value(in: row, aliases: ["segment", "user_segment", "用户群体", "分群"], fallback: "全量")
            let platform = value(in: row, aliases: ["platform", "平台"], fallback: "全平台")
            let channel = value(in: row, aliases: ["channel", "渠道"], fallback: "全渠道")

            if hasLongFormat {
                let metricName = value(in: row, aliases: ["metric", "name", "指标", "指标名"], fallback: "")
                let rawValue = value(in: row, aliases: ["value", "数值", "metric_value"], fallback: "")
                if !metricName.isEmpty, let number = parseNumber(rawValue) {
                    result.append(MetricPoint(id: UUID(), date: date, metric: metricName, value: number, segment: segment, platform: platform, channel: channel))
                }
            } else {
                let dimensionKeys = Set(["date", "日期", "segment", "user_segment", "用户群体", "分群", "platform", "平台", "channel", "渠道"])
                for (header, rawValue) in row where !dimensionKeys.contains(header.normalizedKey) {
                    guard let number = parseNumber(rawValue) else { continue }
                    result.append(MetricPoint(id: UUID(), date: date, metric: header, value: number, segment: segment, platform: platform, channel: channel))
                }
            }
        }

        return result
    }

    private static func loadEvents(from folderURL: URL) throws -> [ProductEvent] {
        let files = [
            ("marketing_events.csv", "运营活动"),
            ("system_incidents.csv", "技术异常"),
            ("events.csv", "上下文事件"),
            ("运营活动.csv", "运营活动"),
            ("系统事故.csv", "技术异常")
        ]

        var events: [ProductEvent] = []
        for (name, defaultType) in files {
            let url = folderURL.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let table = try CSVParser.parse(fileURL: url)
            events.append(contentsOf: table.rows.compactMap { row in
                guard let date = DateParsing.parse(value(in: row, aliases: ["date", "日期", "start_date"])) else { return nil }
                return ProductEvent(
                    id: UUID(),
                    date: date,
                    eventType: value(in: row, aliases: ["event_type", "type", "事件类型", "类型"], fallback: defaultType),
                    title: value(in: row, aliases: ["title", "name", "event", "事件", "名称"], fallback: defaultType),
                    scope: value(in: row, aliases: ["scope", "影响范围", "范围"], fallback: "全量"),
                    note: value(in: row, aliases: ["note", "description", "说明", "备注"], fallback: "")
                )
            })
        }

        let competitorURL = folderURL.appendingPathComponent("competitor_notes.md")
        if FileManager.default.fileExists(atPath: competitorURL.path),
           let content = try? String(contentsOf: competitorURL, encoding: .utf8) {
            events.append(contentsOf: parseCompetitorNotes(content))
        }

        return events.sorted { $0.date < $1.date }
    }

    private static func parseCompetitorNotes(_ content: String) -> [ProductEvent] {
        content
            .split(separator: "\n")
            .compactMap { line -> ProductEvent? in
                let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                let prefix = String(text.prefix(10))
                guard let date = DateParsing.parse(prefix) else { return nil }
                let title = text.dropFirst(min(10, text.count)).trimmingCharacters(in: CharacterSet(charactersIn: " -:"))
                return ProductEvent(id: UUID(), date: date, eventType: "竞品动态", title: title.isEmpty ? "竞品动态" : title, scope: "市场", note: text)
            }
    }

    private static func loadFeedback(from folderURL: URL) throws -> [FeedbackItem] {
        guard let url = firstExistingFile(in: folderURL, names: ["user_feedback.csv", "support_tickets.csv", "feedback.csv", "用户反馈.csv", "客服工单.csv"]) else {
            return []
        }

        let table = try CSVParser.parse(fileURL: url)
        return table.rows.compactMap { row in
            guard let date = DateParsing.parse(value(in: row, aliases: ["date", "日期", "created_at"])) else { return nil }
            return FeedbackItem(
                id: UUID(),
                date: date,
                source: value(in: row, aliases: ["source", "来源"], fallback: "反馈"),
                module: value(in: row, aliases: ["module", "feature", "模块", "功能"], fallback: "未归类"),
                segment: value(in: row, aliases: ["segment", "user_segment", "用户群体"], fallback: "未标注"),
                sentiment: value(in: row, aliases: ["sentiment", "情绪"], fallback: "中性"),
                text: value(in: row, aliases: ["text", "content", "description", "反馈内容", "内容"], fallback: "")
            )
        }
    }

    private static func loadImportedReports(from folderURL: URL) throws -> [ImportedReport] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { supportedReportExtension($0.pathExtension) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try importReports(from: urls).reports
    }

    static func rebuildFieldDefinitions(
        for reports: [ImportedReport],
        preserving existingDefinitions: [ReportFieldDefinition]
    ) -> [ReportFieldDefinition] {
        let normalizedReports = reports.map(reportWithFieldMetadata)
        let existingByIDAndField = bestDefinitionsByKey(
            existingDefinitions,
            key: { fieldMatchKey(reportID: $0.reportID, fieldName: $0.fieldName) }
        )
        let existingByReportAndField = bestDefinitionsByKey(
            existingDefinitions,
            key: { fieldMatchKey(reportName: $0.reportName, reportKind: $0.reportKind, fieldName: $0.fieldName) }
        )

        var rebuilt: [ReportFieldDefinition] = []
        for report in normalizedReports {
            for fieldName in fieldDefinitionNames(for: report) {
                let existing = existingByIDAndField[fieldMatchKey(reportID: report.id, fieldName: fieldName)]
                    ?? existingByReportAndField[fieldMatchKey(reportName: report.fileName, reportKind: report.kind, fieldName: fieldName)]

                let example = fieldExample(for: fieldName, report: report)
                rebuilt.append(ReportFieldDefinition(
                    id: existing?.id ?? UUID(),
                    reportID: report.id,
                    reportName: report.fileName,
                    reportKind: report.kind,
                    reportShape: report.shape,
                    fieldName: fieldName,
                    meaning: existing?.meaning ?? defaultMeaning(for: fieldName, reportKind: report.kind),
                    dataType: existing?.dataType ?? inferredType(for: fieldName, report: report),
                    exampleValue: existing?.exampleValue.isEmpty == false ? existing?.exampleValue ?? example : example,
                    notes: existing?.notes ?? "",
                    isConfirmed: existing?.isConfirmed ?? false,
                    updatedAt: existing?.updatedAt
                ))
            }
        }

        let rebuiltKeys = Set(rebuilt.map { fieldMatchKey(reportID: $0.reportID, fieldName: $0.fieldName) })
        let preservedConfirmedDefinitions = existingDefinitions.filter {
            $0.isConfirmed && !rebuiltKeys.contains(fieldMatchKey(reportID: $0.reportID, fieldName: $0.fieldName))
        }

        return sortFieldDefinitions(rebuilt + preservedConfirmedDefinitions)
    }

    static func reportWithFieldMetadata(_ report: ImportedReport) -> ImportedReport {
        var copy = report
        if copy.shape == .unknown {
            copy.shape = inferredShape(for: copy)
        }
        if copy.firstColumnValues.isEmpty {
            copy.firstColumnValues = firstColumnValues(for: copy)
        }
        copy.fieldExamples = fieldExamples(for: copy)
        if copy.timeAxisProfile.updatedAt == nil || copy.timeAxisProfile.orientation == .unknown {
            copy.timeAxisProfile = ReportTimeAxisDetector.detect(report: copy)
        }
        if copy.trendSummary.isEmpty ||
            copy.trendSummary.analysisVersion ?? 0 < ReportTrendAnalyzer.currentAnalysisVersion ||
            copy.sampleRows.count >= copy.rowCount ||
            copy.rowCount <= 0 {
            copy.trendSummary = ReportTrendAnalyzer.analyze(report: copy)
        }
        if copy.tableContextCoverage == nil {
            copy.tableContextCoverage = TableContextPackageBuilder.build(for: copy).coverage
        }
        return copy
    }

    static func fieldDefinitionNames(for report: ImportedReport) -> [String] {
        let report = reportWithFieldMetadata(report)
        var names: [String] = []
        var seen = Set<String>()
        let firstColumnMetricNames = report.shape == .pivotWide ? firstColumnValues(for: report) : []
        for rawName in headerFieldNames(for: report) + firstColumnMetricNames {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isFieldNameCandidate(name) else { continue }
            guard seen.insert(name.normalizedKey).inserted else { continue }
            names.append(name)
        }
        return names
    }

    static func recognizedKind(for report: ImportedReport) -> (kind: ImportedReportKind, confidence: Double) {
        let table = CSVTable(
            headers: report.headers,
            rows: report.storedDataRows.isEmpty ? report.sampleRows : report.storedDataRows,
            firstColumnValues: report.firstColumnValues,
            fieldExamples: report.fieldExamples,
            shape: report.shape,
            sourceFormat: report.sourceFormat,
            sheetName: report.sheetName,
            sheetIndex: report.sheetIndex,
            parseWarnings: report.parseWarnings,
            originalEncoding: report.originalEncoding,
            delimiter: report.delimiter,
            workbookWarnings: [],
            cellTypeHints: report.cellTypeHints,
            rawRows: report.rawRows
        )
        return reportKind(for: report.fileName, table: table)
    }

    static func isFieldNameCandidate(_ rawValue: String) -> Bool {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 120 else { return false }
        if value.range(of: #"https?://"#, options: .regularExpression) != nil { return false }
        if parseNumber(value) != nil { return false }
        if DateParsing.parse(value) != nil { return false }
        if value.range(of: #"^\d{4}[-/.年]\d{1,2}([-/月.]\d{1,2})?日?$"#, options: .regularExpression) != nil {
            return false
        }
        return value.contains { $0.isLetter }
    }

    private static func buildFieldDefinitions(for reports: [ImportedReport]) -> [ReportFieldDefinition] {
        rebuildFieldDefinitions(for: reports, preserving: [])
    }

    private static func bestDefinitionsByKey(
        _ definitions: [ReportFieldDefinition],
        key: (ReportFieldDefinition) -> String
    ) -> [String: ReportFieldDefinition] {
        definitions.reduce(into: [:]) { result, definition in
            let key = key(definition)
            guard let existing = result[key] else {
                result[key] = definition
                return
            }
            let existingDate = existing.updatedAt ?? .distantPast
            let definitionDate = definition.updatedAt ?? .distantPast
            if definition.isConfirmed && !existing.isConfirmed {
                result[key] = definition
            } else if definition.isConfirmed == existing.isConfirmed && definitionDate > existingDate {
                result[key] = definition
            }
        }
    }

    private static func firstColumnValues(for report: ImportedReport) -> [String] {
        guard report.shape == .pivotWide else { return [] }
        if !report.firstColumnValues.isEmpty {
            return report.firstColumnValues
        }
        guard let firstHeader = report.headers.first else { return [] }
        let rows = report.storedDataRows.isEmpty ? report.sampleRows : report.storedDataRows
        return rows.compactMap { row in
            row[firstHeader]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }
    }

    private static func fieldExamples(for report: ImportedReport) -> [String: String] {
        var examples = report.fieldExamples
        for header in report.headers where examples[header]?.isEmpty != false {
            let value = sampleExampleValue(for: header, report: report)
            if !value.isEmpty {
                examples[header] = value
            }
        }
        guard let firstHeader = report.headers.first else { return examples }
        let rows = report.storedDataRows.isEmpty ? report.sampleRows : report.storedDataRows
        for label in firstColumnValues(for: report) where examples[label]?.isEmpty != false {
            guard let row = rows.first(where: { $0[firstHeader]?.normalizedKey == label.normalizedKey }),
                  let value = report.headers.dropFirst().compactMap({ row[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank }).first else {
                continue
            }
            examples[label] = value
        }
        return examples
    }

    private static func fieldExample(for fieldName: String, report: ImportedReport) -> String {
        if let exact = report.fieldExamples[fieldName], !exact.isEmpty {
            return exact
        }
        if let normalizedMatch = report.fieldExamples.first(where: { $0.key.normalizedKey == fieldName.normalizedKey })?.value,
           !normalizedMatch.isEmpty {
            return normalizedMatch
        }
        if let firstHeader = report.headers.first,
           firstColumnValues(for: report).contains(where: { $0.normalizedKey == fieldName.normalizedKey }),
           let row = (report.storedDataRows.isEmpty ? report.sampleRows : report.storedDataRows).first(where: { $0[firstHeader]?.normalizedKey == fieldName.normalizedKey }),
           let value = report.headers.dropFirst().compactMap({ row[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank }).first {
            return value
        }
        return sampleExampleValue(for: fieldName, report: report)
    }

    private static func fieldMatchKey(reportID: UUID, fieldName: String) -> String {
        "\(reportID.uuidString)|\(fieldName.normalizedKey)"
    }

    private static func fieldMatchKey(reportName: String, reportKind: ImportedReportKind, fieldName: String) -> String {
        "\(reportName.normalizedKey)|\(reportKind.rawValue)|\(fieldName.normalizedKey)"
    }

    private static func sortFieldDefinitions(_ definitions: [ReportFieldDefinition]) -> [ReportFieldDefinition] {
        definitions.sorted {
            if $0.reportName != $1.reportName { return $0.reportName < $1.reportName }
            if $0.isConfirmed != $1.isConfirmed { return !$0.isConfirmed && $1.isConfirmed }
            return $0.fieldName < $1.fieldName
        }
    }

    private static func sampleExampleValue(for fieldName: String, report: ImportedReport) -> String {
        let rows = report.storedDataRows.isEmpty ? report.sampleRows : report.storedDataRows
        return rows.compactMap { $0[fieldName]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank }.first ?? ""
    }

    private static func headerFieldNames(for report: ImportedReport) -> [String] {
        guard report.shape == .pivotWide else { return report.headers }
        var names: [String] = []
        var seen = Set<String>()
        for header in report.headers.prefix(120) {
            let parts = header
                .components(separatedBy: " / ")
                .map { $0.replacingOccurrences(of: #" #\d+$"#, with: "", options: .regularExpression) }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !isHorizontalValue($0) }
            for part in parts where seen.insert(part.normalizedKey).inserted {
                names.append(part)
            }
        }
        if names.isEmpty {
            names.append("指标")
        }
        return names
    }

    private static func inferredShape(for report: ImportedReport) -> CSVTableShape {
        let horizontalLikeHeaders = report.headers.filter(isHorizontalValue).count
        let firstHeader = report.headers.first?.normalizedKey ?? ""
        let firstHeaderLooksLikeMetric = firstHeader == "metric" ||
            firstHeader == "指标" ||
            firstHeader.contains("metric") ||
            firstHeader.contains("指标")
        if horizontalLikeHeaders >= 3 && (report.headers.count >= 4 || firstHeaderLooksLikeMetric) {
            return .pivotWide
        }
        return report.headers.isEmpty ? .unknown : .detail
    }

    private static func reportKind(for fileName: String, table: CSVTable) -> (kind: ImportedReportKind, confidence: Double) {
        let fileContext = fileName.lowercased()
        let headerContext = table.headers.prefix(80).joined(separator: " ").lowercased()
        let firstColumnContext = table.firstColumnValues.prefix(160).joined(separator: " ").lowercased()
        let exampleContext = table.fieldExamples.prefix(40).map { "\($0.key) \($0.value)" }.joined(separator: " ").lowercased()
        let context = [fileContext, headerContext, firstColumnContext, exampleContext].joined(separator: " ")

        let eventScore = matchCount(
            in: context,
            keywords: ["event_tracking", "event_log", "track", "tracking", "event name", "page", "screen", "button", "click", "view", "viewed", "tap", "submit", "error", "埋点", "打点", "曝光", "点击", "触发", "事件名", "页面", "按钮", "提交", "报错", "停留"]
        )
        let funnelScore = matchCount(
            in: context,
            keywords: ["funnel", "conversion", "register", "signup", "activation", "注册", "转化", "漏斗", "申请", "开户", "激活", "授信", "进件"]
        )
        let explicitEventStructureScore = matchCount(
            in: [fileContext, headerContext].joined(separator: " "),
            keywords: ["event_tracking", "event_log", "event_name", "event name", "event_type", "event type", "track", "tracking", "page", "screen", "button", "事件名", "事件类型", "埋点", "打点"]
        )
        let funnelStageScore = matchCount(
            in: [fileContext, firstColumnContext].joined(separator: " "),
            keywords: ["漏斗", "转化", "注册", "申请", "提审核", "审核", "通过", "开户", "激活", "授信", "发卡", "消费", "注册数/安装数", "提审核单/注册", "授信完成/注册"]
        )

        if containsAny(context, ["product_update", "release_note", "产品更新", "上线", "迭代", "需求"]) {
            return (.productUpdates, 0.86)
        }
        if table.shape == .detail && explicitEventStructureScore >= 2 && funnelStageScore < 3 {
            return (.eventTracking, min(0.92, 0.74 + Double(explicitEventStructureScore) * 0.04))
        }
        if funnelScore >= 2 && (table.shape == .pivotWide || funnelStageScore >= 2 || containsAny(fileContext, ["funnel", "conversion", "register", "signup", "注册", "转化", "漏斗"])) {
            return (.funnelMetrics, min(0.94, 0.78 + Double(max(funnelScore, funnelStageScore)) * 0.025))
        }
        if eventScore >= 2 && eventScore >= funnelScore + 2 {
            return (.eventTracking, min(0.92, 0.72 + Double(eventScore) * 0.04))
        }
        if funnelScore > 0 {
            return (.funnelMetrics, min(0.9, 0.74 + Double(funnelScore) * 0.03))
        }
        if eventScore > 0 {
            return (.eventTracking, 0.78)
        }
        if containsAny(context, ["feedback", "support", "ticket", "complaint", "反馈", "工单", "投诉", "客服"]) {
            return (.userFeedback, 0.84)
        }
        if containsAny(context, ["incident", "campaign", "marketing", "活动", "事故", "异常", "运营"]) {
            return (.contextEvents, 0.76)
        }
        if containsAny(context, ["metric", "指标", "value", "数值", "count", "次数", "rate", "率"]) ||
            table.shape == .pivotWide && table.headers.filter(isHorizontalValue).count >= 3 {
            return (.coreMetrics, table.shape == .pivotWide ? 0.72 : 0.68)
        }
        return (.generic, 0.35)
    }

    private static func defaultMeaning(for fieldName: String, reportKind: ImportedReportKind) -> String {
        let normalized = fieldName.normalizedKey
        if normalized == "date" || fieldName == "日期" { return "记录日期或事件发生日期" }
        if normalized.contains("user") || fieldName.contains("用户") { return "用户标识或用户分群字段" }
        if normalized.contains("event") || fieldName.contains("事件") || fieldName.contains("埋点") { return "埋点事件名称或事件属性" }
        if normalized.contains("value") || normalized.contains("count") || fieldName.contains("数值") || fieldName.contains("次数") { return "指标数值或事件计数" }
        if normalized.contains("channel") || fieldName.contains("渠道") { return "流量、投放或来源渠道" }
        if normalized.contains("platform") || fieldName.contains("平台") { return "客户端或平台维度" }
        if reportKind == .eventTracking { return "埋点报表字段，请补充事件口径、触发时机和统计方式" }
        return ""
    }

    private static func inferredType(for fieldName: String, report: ImportedReport) -> String {
        let value = fieldExample(for: fieldName, report: report)
        if DateParsing.parse(value) != nil { return "date" }
        if Double(value.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "%", with: "")) != nil { return "number" }
        return "string"
    }

    private static func containsAny(_ context: String, _ keywords: [String]) -> Bool {
        keywords.contains { context.contains($0.lowercased()) }
    }

    private static func matchCount(in context: String, keywords: [String]) -> Int {
        keywords.reduce(0) { count, keyword in
            context.contains(keyword.lowercased()) ? count + 1 : count
        }
    }

    private static func supportedReportExtension(_ pathExtension: String) -> Bool {
        ["csv", "tsv", "xlsx", "xls"].contains(pathExtension.lowercased())
    }

    private static func isHorizontalValue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let normalized = trimmed.normalizedKey
        if DateParsing.parse(trimmed) != nil { return true }
        if trimmed.range(of: #"\d{4}[-/.年]\d{1,2}[-/.月]\d{1,2}"#, options: .regularExpression) != nil { return true }
        if trimmed.range(of: #"\d{4}[-/.年]\d{1,2}\s*[-至~—]\s*\d{1,2}"#, options: .regularExpression) != nil { return true }
        if trimmed.range(of: #"\d{1,2}[-/.月]\d{1,2}\s*[-至~—]\s*\d{1,2}[-/.月]\d{1,2}"#, options: .regularExpression) != nil { return true }
        if parseNumber(trimmed) != nil { return true }
        if normalized.range(of: #"^week\s*\d+$"#, options: .regularExpression) != nil { return true }
        return normalized.contains("week of date") ||
            normalized.contains("month of date") ||
            normalized.contains("day of date") ||
            normalized.contains("current") ||
            normalized.contains("last") ||
            trimmed.contains("周") && trimmed.count <= 12 ||
            trimmed.contains("月") && trimmed.count <= 12 ||
            trimmed.contains("本期") ||
            trimmed.contains("上期") ||
            trimmed.contains("最近")
    }

    private static func firstExistingFile(in folderURL: URL, names: [String]) -> URL? {
        names
            .map { folderURL.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func value(in row: [String: String], aliases: [String], fallback: String = "") -> String {
        for alias in aliases {
            if let exact = row[alias], !exact.isEmpty { return exact }
            if let match = row.first(where: { $0.key.normalizedKey == alias.normalizedKey })?.value, !match.isEmpty {
                return match
            }
        }
        return fallback
    }

    private static func parseNumber(_ rawValue: String) -> Double? {
        let cleaned = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard let number = Double(cleaned) else { return nil }
        return rawValue.contains("%") ? number / 100 : number
    }
}
