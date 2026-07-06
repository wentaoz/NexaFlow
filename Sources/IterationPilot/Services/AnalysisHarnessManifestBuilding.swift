import Foundation

struct TableManifestBuilder {
    static func build(reports: [ImportedReport]) -> [TableManifest] {
        reports
            .filter { !$0.isIgnoredFromAnalysis }
            .map { report in
                let rows = report.harnessRows
                let columns = report.headers.map { header in
                    buildColumnManifest(header: header, rows: rows)
                }
                let dateRanges = columns.compactMap { column -> HarnessManifestDateRange? in
                    guard let dateMin = column.dateMin, let dateMax = column.dateMax else { return nil }
                    return HarnessManifestDateRange(
                        column: column.name,
                        min: dateMin,
                        max: dateMax,
                        nonNullCount: column.nonNullCount
                    )
                }
                let duplicateSummary = duplicateSummary(for: rows, headers: report.headers)
                let grain = detectedGrain(
                    report: report,
                    rows: rows,
                    columns: columns,
                    duplicateSummary: duplicateSummary
                )
                let warnings = manifestWarnings(
                    rows: rows,
                    columns: columns,
                    duplicateSummary: duplicateSummary
                )
                let understanding = understandingSummary(
                    report: report,
                    rows: rows,
                    columns: columns,
                    warnings: warnings
                )
                return TableManifest(
                    id: report.id.uuidString,
                    reportID: report.id,
                    displayName: report.displayName,
                    rowCount: max(report.rowCount, rows.count),
                    columnCount: report.headers.count,
                    sourceFormat: report.sourceFormat.rawValue,
                    sourceType: report.sourceMetadata?.sourceType.label ?? (report.sourceFormat == .tableau ? "Tableau" : "本地文件"),
                    shape: report.shape.rawValue,
                    columns: columns,
                    detectedGrain: grain,
                    dateRanges: dateRanges,
                    duplicateSummary: duplicateSummary,
                    warnings: warnings,
                    understanding: understanding
                )
            }
    }

    private static func buildColumnManifest(header: String, rows: [[String: String]]) -> ColumnManifest {
        let rawValues = rows.map { $0[header]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        let nonEmptyValues = rawValues.filter { !$0.isEmpty }
        let numericValues = nonEmptyValues.compactMap { HarnessValueParser.number(from: $0) }
        let dateValues = nonEmptyValues.compactMap { HarnessValueParser.date(from: $0) }
        let uniqueValues = Set(nonEmptyValues.map(\.normalizedKey))
        let inferredType = inferType(
            header: header,
            nonEmptyCount: nonEmptyValues.count,
            numericCount: numericValues.count,
            dateCount: dateValues.count,
            uniqueCount: uniqueValues.count
        )
        let candidates = semanticCandidates(header: header, inferredType: inferredType, values: nonEmptyValues)
        let aggregationRisk = aggregationRisk(header: header, inferredType: inferredType, candidates: candidates)
        return ColumnManifest(
            name: header,
            inferredType: inferredType,
            semanticCandidates: candidates,
            aggregationRisk: aggregationRisk,
            nullCount: rawValues.count - nonEmptyValues.count,
            nonNullCount: nonEmptyValues.count,
            uniqueCount: uniqueValues.count,
            sampleValues: Array(nonEmptyValues.prefix(6)),
            numericMin: numericValues.min(),
            numericMax: numericValues.max(),
            dateMin: dateValues.min().map { HarnessValueParser.isoDateFormatter.string(from: $0) },
            dateMax: dateValues.max().map { HarnessValueParser.isoDateFormatter.string(from: $0) }
        )
    }

    private static func inferType(
        header: String,
        nonEmptyCount: Int,
        numericCount: Int,
        dateCount: Int,
        uniqueCount: Int
    ) -> HarnessColumnInferredType {
        guard nonEmptyCount > 0 else { return .unknown }
        let normalizedHeader = header.normalizedKey
        if dateCount >= max(1, Int(Double(nonEmptyCount) * 0.65)) ||
            normalizedHeader.contains("date") ||
            normalizedHeader.contains("日期") ||
            normalizedHeader.contains("period") ||
            normalizedHeader.contains("周期") {
            return .date
        }
        if numericCount >= max(1, Int(Double(nonEmptyCount) * 0.7)) {
            return .number
        }
        if uniqueCount <= max(12, Int(Double(nonEmptyCount) * 0.25)) {
            return .category
        }
        return .string
    }

    private static func semanticCandidates(
        header: String,
        inferredType: HarnessColumnInferredType,
        values: [String]
    ) -> [HarnessSemanticCandidate] {
        let key = header.normalizedKey
        var candidates: [HarnessSemanticCandidate] = []
        func add(_ role: HarnessColumnSemanticRole, _ confidence: Double, _ reason: String) {
            candidates.append(HarnessSemanticCandidate(role: role, confidence: confidence, reason: reason))
        }

        if key.contains("measure_names") || key.contains("measure names") || key.contains("metric_name") || key.contains("指标名称") || key == "指标" {
            add(.metricName, 0.95, "字段名显示为 Tableau/长表指标名称。")
        }
        if key.contains("measure_values") || key.contains("measure values") || key.contains("metric_value") || key.contains("value") || key == "值" {
            add(.metricValue, inferredType == .number ? 0.95 : 0.65, "字段名显示为指标值。")
        }
        if key.contains("date") || key.contains("日期") {
            add(.date, 0.9, "字段名显示为日期。")
        }
        if key.contains("period") || key.contains("week") || key.contains("month") || key.contains("周期") || key.contains("月份") || key.contains("周") {
            add(.period, 0.9, "字段名显示为周期。")
        }
        if key.contains("transaction_id") || key.contains("order_id") || key.contains("record_id") || key.contains("流水") {
            add(.recordID, 0.9, "字段名显示为记录主键。")
        } else if key == "id" || key.hasSuffix("_id") || key.contains("user_id") || key.contains("客户id") || key.contains("用户id") {
            add(.objectID, 0.82, "字段名显示为对象 ID。")
        }
        if key.contains("amount") || key.contains("gmv") || key.contains("revenue") || key.contains("金额") || key.contains("mxn") {
            add(.amount, 0.9, "字段名显示为金额。")
        }
        if key.contains("count") || key.contains("qty") || key.contains("数量") || key.contains("人数") || key.contains("笔数") {
            add(.quantity, 0.86, "字段名显示为数量。")
        }
        if key.contains("rate") || key.contains("ratio") || key.contains("percent") || key.contains("占比") || key.contains("率") || values.contains(where: { $0.contains("%") }) {
            add(.rate, 0.9, "字段名或样例值显示为比例。")
        }
        if key.contains("status") || key.contains("状态") {
            add(.status, 0.82, "字段名显示为状态。")
        }
        if key.contains("channel") || key.contains("source") || key.contains("渠道") || key.contains("来源") {
            add(.source, 0.82, "字段名显示为来源/渠道。")
        }
        if candidates.isEmpty, inferredType == .category {
            add(.category, 0.55, "低基数文本字段，可作为分组维度。")
        }
        if candidates.isEmpty {
            add(.unknown, 0.2, "未识别明确语义。")
        }
        return candidates.sorted { $0.confidence > $1.confidence }
    }

    private static func aggregationRisk(
        header: String,
        inferredType: HarnessColumnInferredType,
        candidates: [HarnessSemanticCandidate]
    ) -> HarnessAggregationRisk {
        if candidates.contains(where: { $0.role == .rate && $0.confidence > 0.5 }) { return .rateLike }
        if candidates.contains(where: { ($0.role == .objectID || $0.role == .recordID) && $0.confidence > 0.5 }) { return .idLike }
        if candidates.contains(where: { ($0.role == .amount || $0.role == .quantity || $0.role == .metricValue) && $0.confidence > 0.5 }) { return .safeSum }
        if inferredType == .number {
            let key = header.normalizedKey
            if key.contains("avg") || key.contains("平均") || key.contains("人均") || key.contains("笔均") {
                return .safeAverage
            }
            return .safeSum
        }
        if inferredType == .category { return .categoryLike }
        return .unknown
    }

    private static func duplicateSummary(for rows: [[String: String]], headers: [String]) -> HarnessDuplicateSummary {
        guard !rows.isEmpty else {
            return HarnessDuplicateSummary(exactDuplicateRowCount: 0, duplicateRatio: 0, candidateKeyColumns: [])
        }
        var seen: Set<String> = []
        var duplicates = 0
        for row in rows {
            let key = headers.map { row[$0]?.normalizedKey ?? "" }.joined(separator: "\u{1f}")
            if seen.contains(key) {
                duplicates += 1
            } else {
                seen.insert(key)
            }
        }
        let candidateKeys = headers.filter { header in
            let values = rows.map { $0[header]?.normalizedKey ?? "" }.filter { !$0.isEmpty }
            return !values.isEmpty && Set(values).count == values.count
        }
        return HarnessDuplicateSummary(
            exactDuplicateRowCount: duplicates,
            duplicateRatio: rows.isEmpty ? 0 : Double(duplicates) / Double(rows.count),
            candidateKeyColumns: Array(candidateKeys.prefix(5))
        )
    }

    private static func detectedGrain(
        report: ImportedReport,
        rows: [[String: String]],
        columns: [ColumnManifest],
        duplicateSummary: HarnessDuplicateSummary
    ) -> HarnessDetectedGrain {
        if report.shape == .pivotWide {
            return HarnessDetectedGrain(kind: .pivotSummary, confidence: 0.85, keyColumns: [], description: "导入器识别为透视宽表。")
        }
        if let metricName = columns.first(where: { $0.confidence(for: .metricName) > 0.45 }),
           let period = columns.first(where: { max($0.confidence(for: .period), $0.confidence(for: .date)) > 0.45 }) {
            return HarnessDetectedGrain(
                kind: .oneRowPerMetricPeriod,
                confidence: 0.82,
                keyColumns: [metricName.name, period.name],
                description: "同时存在指标名和周期字段，按指标-周期长表处理。"
            )
        }
        if let key = duplicateSummary.candidateKeyColumns.first {
            return HarnessDetectedGrain(kind: .oneRowPerRecord, confidence: 0.78, keyColumns: [key], description: "存在唯一键字段。")
        }
        if let period = columns.first(where: { max($0.confidence(for: .period), $0.confidence(for: .date)) > 0.45 }) {
            return HarnessDetectedGrain(kind: .oneRowPerPeriod, confidence: 0.62, keyColumns: [period.name], description: "存在周期字段但没有唯一记录 ID。")
        }
        if rows.count < 100 {
            return HarnessDetectedGrain(kind: .aggregatedSummary, confidence: 0.5, keyColumns: [], description: "行数较少且没有唯一键，可能为汇总表。")
        }
        return HarnessDetectedGrain(kind: .unknown, confidence: 0.3, keyColumns: [], description: "未能确认表粒度。")
    }

    private static func manifestWarnings(
        rows: [[String: String]],
        columns: [ColumnManifest],
        duplicateSummary: HarnessDuplicateSummary
    ) -> [String] {
        var warnings: [String] = []
        if rows.isEmpty { warnings.append("表格没有可执行计算的行数据。") }
        if duplicateSummary.exactDuplicateRowCount > 0 {
            warnings.append("检测到 \(duplicateSummary.exactDuplicateRowCount) 行完全重复记录，去重口径需谨慎。")
        }
        if !columns.contains(where: { $0.inferredType == .number }) {
            warnings.append("未识别到数值字段，无法执行 SUM/AVG 等指标计算。")
        }
        return warnings
    }

    private static func understandingSummary(
        report: ImportedReport,
        rows: [[String: String]],
        columns: [ColumnManifest],
        warnings: [String]
    ) -> HarnessTableUnderstandingSummary {
        let metricNameColumn = columns.first { $0.confidence(for: .metricName) > 0.45 }
        let metricValueColumn = columns.first { $0.confidence(for: .metricValue) > 0.45 }
        let periodColumn = columns.first { max($0.confidence(for: .period), $0.confidence(for: .date)) > 0.45 }
        let shape: HarnessTableUnderstandingShape
        let confidence: Double
        if metricNameColumn != nil, metricValueColumn != nil, periodColumn != nil {
            let sourceLooksTableau = report.sourceFormat == .tableau ||
                metricNameColumn?.name.localizedCaseInsensitiveContains("Measure Names") == true ||
                metricValueColumn?.name.localizedCaseInsensitiveContains("Measure Values") == true
            let extraNumericColumns = columns.filter { column in
                column.name != metricNameColumn?.name &&
                    column.name != metricValueColumn?.name &&
                    column.name != periodColumn?.name &&
                    (column.inferredType == .number || column.inferredType == .integer)
            }
            shape = sourceLooksTableau ? .tableauLong : (extraNumericColumns.isEmpty ? .metricPeriodValue : .semiPivot)
            confidence = sourceLooksTableau ? 0.92 : 0.88
        } else if report.shape == .pivotWide {
            shape = .horizontalPivot
            confidence = 0.72
        } else {
            shape = .standardWide
            confidence = 0.62
        }
        let catalog = metricCatalog(
            rows: rows,
            metricNameColumn: metricNameColumn?.name,
            metricValueColumn: metricValueColumn?.name,
            periodColumn: periodColumn?.name
        )
        let dimensionColumns = columns
            .filter { column in
                column.name != metricNameColumn?.name &&
                    column.name != metricValueColumn?.name &&
                    column.name != periodColumn?.name &&
                    column.confidence(for: .metricName) < 0.45 &&
                    column.confidence(for: .metricValue) < 0.45
            }
            .map(\.name)
        var summaryWarnings = warnings
        if metricNameColumn != nil, metricValueColumn != nil, catalog.isEmpty {
            summaryWarnings.append("识别到指标列和值列，但未能生成指标目录。")
        }
        return HarnessTableUnderstandingSummary(
            shape: shape,
            confidence: confidence,
            periodColumn: periodColumn?.name,
            metricNameColumn: metricNameColumn?.name,
            metricValueColumn: metricValueColumn?.name,
            dimensionColumns: dimensionColumns,
            metricCatalog: catalog,
            warnings: summaryWarnings.uniqued()
        )
    }

    private static func metricCatalog(
        rows: [[String: String]],
        metricNameColumn: String?,
        metricValueColumn: String?,
        periodColumn: String?
    ) -> [HarnessMetricCatalogEntry] {
        guard let metricNameColumn else { return [] }
        let grouped = Dictionary(grouping: rows) { row in
            (row[metricNameColumn] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return grouped.compactMap { metricName, rows -> HarnessMetricCatalogEntry? in
            guard !metricName.isEmpty else { return nil }
            let values = metricValueColumn.map { column in
                rows.compactMap { ($0[column] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank }
            } ?? []
            let periods = periodColumn.map { column in
                rows.compactMap { ($0[column] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank }
            } ?? []
            return HarnessMetricCatalogEntry(
                metricName: metricName,
                valueKind: valueKind(for: metricName),
                observationCount: rows.count,
                firstPeriod: periods.first,
                lastPeriod: periods.last,
                sampleValues: Array(values.prefix(4))
            )
        }
        .sorted {
            if $0.observationCount != $1.observationCount {
                return $0.observationCount > $1.observationCount
            }
            return $0.metricName.localizedStandardCompare($1.metricName) == .orderedAscending
        }
    }

    static func valueKind(for metricName: String) -> HarnessMetricValueKind {
        let key = metricName.normalizedKey
        if key.contains("占比") || key.contains("率") || key.contains("ratio") || key.contains("rate") || metricName.contains("%") {
            return .ratio
        }
        if key.contains("人均") || key.contains("笔均") || key.contains("客单价") || key.contains("avg") {
            return .derived
        }
        if key.contains("金额") || key.contains("人数") || key.contains("笔数") || key.contains("数量") || key.contains("次数") || key.contains("用户数") {
            return .additive
        }
        return .unknown
    }
}

struct NormalizedFactTableBuilder {
    static func build(
        reports: [ImportedReport],
        manifests: [TableManifest],
        templates: [AnalysisTableUnderstandingTemplate] = []
    ) -> [NormalizedFactTable] {
        let reportsByID = Dictionary(grouping: reports, by: { $0.id.uuidString })
            .compactMapValues(\.first)
        return manifests.compactMap { manifest in
            guard let report = reportsByID[manifest.id],
                  let resolved = resolvedUnderstanding(report: report, manifest: manifest, templates: templates),
                  let understanding = Optional(resolved.understanding),
                  let periodColumn = understanding.periodColumn,
                  let metricNameColumn = understanding.metricNameColumn,
                  let metricValueColumn = understanding.metricValueColumn else {
                return nil
            }
            guard [.metricPeriodValue, .tableauLong, .semiPivot].contains(understanding.shape) else {
                return nil
            }
            let headers = report.headers
            let valueColumnIndex = (headers.firstIndex(of: metricValueColumn) ?? 0) + 1
            var facts: [NormalizedFactRow] = []
            var warnings = understanding.warnings
            var lastPeriod = ""
            let dimensionColumn = understanding.dimensionColumns.first
            for (offset, row) in report.harnessRows.enumerated() {
                let rawPeriod = (row[periodColumn] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !rawPeriod.isEmpty { lastPeriod = rawPeriod }
                let period = rawPeriod.nilIfBlank ?? lastPeriod
                let metricName = (row[metricNameColumn] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let rawValue = (row[metricValueColumn] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !metricName.isEmpty, !rawValue.isEmpty else { continue }
                let range = HarnessPeriodResolver.range(from: period)
                let value = HarnessValueParser.number(from: rawValue)
                if value == nil {
                    continue
                }
                facts.append(NormalizedFactRow(
                    tableID: manifest.id,
                    tableName: manifest.displayName,
                    sourceSheet: report.sheetName ?? report.displayName,
                    sourceRow: offset + 2,
                    sourceColumn: valueColumnIndex,
                    periodRaw: period,
                    periodStart: range.start.map(HarnessValueParser.isoDateFormatter.string(from:)),
                    periodEnd: range.end.map(HarnessValueParser.isoDateFormatter.string(from:)),
                    periodBucket: range.start.flatMap(HarnessPeriodResolver.halfYearBucket(for:)),
                    metricName: metricName,
                    metricValue: value,
                    rawValue: rawValue,
                    unit: Self.unitGuess(for: metricName),
                    valueKind: TableManifestBuilder.valueKind(for: metricName),
                    dimensionName: dimensionColumn,
                    dimensionValue: dimensionColumn.flatMap { row[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank }
                ))
            }
            if facts.isEmpty {
                warnings.append("已识别为 \(understanding.shape.label)，但未能生成可计算事实行。")
                return nil
            }
            let rawCatalog = understanding.metricCatalog
            let factCatalog = Self.catalog(from: facts)
            return NormalizedFactTable(
                tableID: manifest.id,
                tableName: manifest.displayName,
                shape: understanding.shape,
                confidence: understanding.confidence,
                rows: facts,
                metricCatalog: Self.mergeCatalog(rawCatalog: rawCatalog, factCatalog: factCatalog),
                metricAliases: resolved.metricAliases,
                warnings: warnings.uniqued()
            )
        }
    }

    private static func resolvedUnderstanding(
        report: ImportedReport,
        manifest: TableManifest,
        templates: [AnalysisTableUnderstandingTemplate]
    ) -> (understanding: HarnessTableUnderstandingSummary, metricAliases: [String: String])? {
        if let template = matchingTemplate(for: report, templates: templates),
           let periodColumn = template.periodColumn,
           let metricNameColumn = template.metricNameColumn,
           let metricValueColumn = template.metricValueColumn,
           report.headers.contains(periodColumn),
           report.headers.contains(metricNameColumn),
           report.headers.contains(metricValueColumn) {
            let dimensionColumns = dimensionColumns(
                headers: report.headers,
                rows: report.harnessRows,
                excluded: [periodColumn, metricNameColumn, metricValueColumn]
            )
            let catalog = catalog(
                rows: report.harnessRows,
                metricNameColumn: metricNameColumn,
                metricValueColumn: metricValueColumn,
                periodColumn: periodColumn
            )
            let understanding = HarnessTableUnderstandingSummary(
                shape: templateShape(for: template, report: report, dimensionColumns: dimensionColumns),
                confidence: max(0.92, manifest.understanding?.confidence ?? 0),
                periodColumn: periodColumn,
                metricNameColumn: metricNameColumn,
                metricValueColumn: metricValueColumn,
                dimensionColumns: dimensionColumns,
                metricCatalog: catalog,
                warnings: (manifest.warnings + ["已使用已确认的表格理解模板。"]).uniqued()
            )
            return (understanding, template.metricAliases)
        }

        if let understanding = manifest.understanding,
           understanding.periodColumn != nil,
           understanding.metricNameColumn != nil,
           understanding.metricValueColumn != nil,
           [.metricPeriodValue, .tableauLong, .semiPivot].contains(understanding.shape) {
            var adjusted = understanding
            adjusted.dimensionColumns = dimensionColumns(
                headers: report.headers,
                rows: report.harnessRows,
                excluded: [
                    understanding.periodColumn ?? "",
                    understanding.metricNameColumn ?? "",
                    understanding.metricValueColumn ?? ""
                ]
            )
            return (adjusted, [:])
        }

        let headers = report.headers
        guard !headers.isEmpty else { return nil }
        let metricNameColumn = firstHeader(
            in: headers,
            aliases: ["指标", "指标名称", "measure names", "measure_names", "metric", "metric name", "metric_name"]
        )
        let metricValueColumn = firstHeader(
            in: headers,
            aliases: ["值", "数值", "value", "metric value", "metric_value", "measure values", "measure_values"]
        )
        let periodColumn = firstHeader(
            in: headers,
            aliases: ["周期", "日期", "date", "period", "week", "month", "月份", "周"]
        )

        guard let metricNameColumn, let metricValueColumn, let periodColumn else {
            return nil
        }

        let sourceLooksTableau = report.sourceFormat == .tableau ||
            metricNameColumn.localizedCaseInsensitiveContains("Measure Names") ||
            metricValueColumn.localizedCaseInsensitiveContains("Measure Values")
        let dimensionColumns = dimensionColumns(
            headers: headers,
            rows: report.harnessRows,
            excluded: [periodColumn, metricNameColumn, metricValueColumn]
        )
        let catalog = catalog(
            rows: report.harnessRows,
            metricNameColumn: metricNameColumn,
            metricValueColumn: metricValueColumn,
            periodColumn: periodColumn
        )
        var warnings = manifest.warnings
        warnings.append("已通过原始行列扫描识别周期列、指标列和值列。")

        let understanding = HarnessTableUnderstandingSummary(
            shape: sourceLooksTableau ? .tableauLong : (dimensionColumns.isEmpty ? .metricPeriodValue : .semiPivot),
            confidence: sourceLooksTableau ? 0.90 : 0.84,
            periodColumn: periodColumn,
            metricNameColumn: metricNameColumn,
            metricValueColumn: metricValueColumn,
            dimensionColumns: dimensionColumns,
            metricCatalog: catalog,
            warnings: warnings.uniqued()
        )
        return (understanding, [:])
    }

    private static func matchingTemplate(
        for report: ImportedReport,
        templates: [AnalysisTableUnderstandingTemplate]
    ) -> AnalysisTableUnderstandingTemplate? {
        let headers = report.headers.map(\.normalizedKey)
        return templates
            .filter { !$0.isDisabled }
            .max { lhs, rhs in
                templateScore(lhs, report: report, normalizedHeaders: headers) <
                    templateScore(rhs, report: report, normalizedHeaders: headers)
            }
            .flatMap { template in
                templateScore(template, report: report, normalizedHeaders: headers) >= 8 ? template : nil
            }
    }

    private static func templateScore(
        _ template: AnalysisTableUnderstandingTemplate,
        report: ImportedReport,
        normalizedHeaders: [String]
    ) -> Int {
        var score = 0
        let templateHeaders = template.headerSignature.map(\.normalizedKey)
        let overlap = Set(normalizedHeaders).intersection(Set(templateHeaders)).count
        score += overlap * 2
        if !templateHeaders.isEmpty && templateHeaders == normalizedHeaders { score += 20 }
        if !template.sourceFingerprintHint.isEmpty && template.sourceFingerprintHint == report.sourceFingerprint { score += 16 }
        if let column = template.periodColumn, normalizedHeaders.contains(column.normalizedKey) { score += 3 }
        if let column = template.metricNameColumn, normalizedHeaders.contains(column.normalizedKey) { score += 3 }
        if let column = template.metricValueColumn, normalizedHeaders.contains(column.normalizedKey) { score += 3 }
        return score
    }

    private static func templateShape(
        for template: AnalysisTableUnderstandingTemplate,
        report: ImportedReport,
        dimensionColumns: [String]
    ) -> HarnessTableUnderstandingShape {
        if report.sourceFormat == .tableau { return .tableauLong }
        let shapeKey = template.shape.normalizedKey
        if shapeKey.contains(HarnessTableUnderstandingShape.tableauLong.label.normalizedKey) { return .tableauLong }
        if shapeKey.contains(HarnessTableUnderstandingShape.semiPivot.label.normalizedKey) { return .semiPivot }
        if shapeKey.contains(HarnessTableUnderstandingShape.metricPeriodValue.label.normalizedKey) { return .metricPeriodValue }
        return dimensionColumns.isEmpty ? .metricPeriodValue : .semiPivot
    }

    private static func firstHeader(in headers: [String], aliases: [String]) -> String? {
        let aliasKeys = aliases.map(\.normalizedKey)
        if let exact = headers.first(where: { header in aliasKeys.contains(header.normalizedKey) }) {
            return exact
        }
        return headers.first { header in
            let key = header.normalizedKey
            return aliasKeys.contains { alias in key.contains(alias) || alias.contains(key) }
        }
    }

    private static func dimensionColumns(
        headers: [String],
        rows: [[String: String]],
        excluded: [String]
    ) -> [String] {
        let excludedKeys = Set(excluded.map(\.normalizedKey))
        return headers.filter { header in
            let key = header.normalizedKey
            guard !excludedKeys.contains(key),
                  !key.isEmpty,
                  !key.contains("占比"),
                  !key.contains("环比"),
                  !key.contains("率"),
                  !key.contains("金额"),
                  !key.contains("人数"),
                  !key.contains("笔数"),
                  !key.contains("数值"),
                  !key.contains("value") else {
                return false
            }
            let samples = rows.prefix(80)
                .compactMap { $0[header]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank }
            guard !samples.isEmpty else { return false }
            let numericCount = samples.filter { HarnessValueParser.number(from: $0) != nil }.count
            let numericShare = Double(numericCount) / Double(samples.count)
            guard numericShare < 0.45 else { return false }
            return Set(samples.map(\.normalizedKey)).count <= max(30, samples.count / 2)
        }
    }

    private static func catalog(from facts: [NormalizedFactRow]) -> [HarnessMetricCatalogEntry] {
        Dictionary(grouping: facts, by: \.metricName).map { metricName, rows in
            let sortedRows = rows.sorted { ($0.periodStart ?? "") < ($1.periodStart ?? "") }
            return HarnessMetricCatalogEntry(
                metricName: metricName,
                valueKind: TableManifestBuilder.valueKind(for: metricName),
                observationCount: rows.count,
                firstPeriod: sortedRows.first?.periodRaw,
                lastPeriod: sortedRows.last?.periodRaw,
                sampleValues: Array(sortedRows.compactMap { $0.rawValue.nilIfBlank }.prefix(4))
            )
        }
        .sorted {
            if $0.observationCount != $1.observationCount {
                return $0.observationCount > $1.observationCount
            }
            return $0.metricName.localizedStandardCompare($1.metricName) == .orderedAscending
        }
    }

    private static func catalog(
        rows: [[String: String]],
        metricNameColumn: String,
        metricValueColumn: String,
        periodColumn: String
    ) -> [HarnessMetricCatalogEntry] {
        struct Accumulator {
            var count = 0
            var firstPeriod: String?
            var lastPeriod: String?
            var sampleValues: [String] = []
        }
        var lastPeriod = ""
        var grouped: [String: Accumulator] = [:]
        var displayNames: [String: String] = [:]
        for row in rows {
            let rawPeriod = (row[periodColumn] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !rawPeriod.isEmpty { lastPeriod = rawPeriod }
            let period = rawPeriod.nilIfBlank ?? lastPeriod.nilIfBlank
            let metricName = (row[metricNameColumn] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !metricName.isEmpty else { continue }
            let key = metricName.normalizedKey
            displayNames[key] = displayNames[key] ?? metricName
            var accumulator = grouped[key] ?? Accumulator()
            accumulator.count += 1
            if let period {
                accumulator.firstPeriod = accumulator.firstPeriod ?? period
                accumulator.lastPeriod = period
            }
            if accumulator.sampleValues.count < 4,
               let value = (row[metricValueColumn] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
                accumulator.sampleValues.append(value)
            }
            grouped[key] = accumulator
        }
        return grouped.compactMap { key, accumulator -> HarnessMetricCatalogEntry? in
            guard let metricName = displayNames[key] else { return nil }
            return HarnessMetricCatalogEntry(
                metricName: metricName,
                valueKind: TableManifestBuilder.valueKind(for: metricName),
                observationCount: accumulator.count,
                firstPeriod: accumulator.firstPeriod,
                lastPeriod: accumulator.lastPeriod,
                sampleValues: accumulator.sampleValues
            )
        }
        .sorted {
            if $0.observationCount != $1.observationCount {
                return $0.observationCount > $1.observationCount
            }
            return $0.metricName.localizedStandardCompare($1.metricName) == .orderedAscending
        }
    }

    private static func mergeCatalog(
        rawCatalog: [HarnessMetricCatalogEntry],
        factCatalog: [HarnessMetricCatalogEntry]
    ) -> [HarnessMetricCatalogEntry] {
        var byKey: [String: HarnessMetricCatalogEntry] = [:]
        for entry in rawCatalog {
            byKey[entry.metricName.normalizedKey] = entry
        }
        for entry in factCatalog {
            byKey[entry.metricName.normalizedKey] = entry
        }
        return byKey.values.sorted {
            if $0.observationCount != $1.observationCount {
                return $0.observationCount > $1.observationCount
            }
            return $0.metricName.localizedStandardCompare($1.metricName) == .orderedAscending
        }
    }

    private static func unitGuess(for metricName: String) -> String {
        let key = metricName.normalizedKey
        if key.contains("金额") || key.contains("gmv") || key.contains("mxn") { return "MXN" }
        if key.contains("人数") || key.contains("用户") { return "人" }
        if key.contains("笔数") || key.contains("订单") || key.contains("次数") { return "笔" }
        if key.contains("占比") || key.contains("率") || metricName.contains("%") { return "%" }
        return ""
    }
}

private enum HarnessPeriodResolver {
    static func range(from raw: String) -> (start: Date?, end: Date?) {
        let matches = dateStrings(in: raw)
        let dates = matches.compactMap { HarnessValueParser.date(from: $0) }
        if dates.count >= 2 {
            return (dates[0], dates[1])
        }
        if let first = dates.first {
            return (first, first)
        }
        if let date = HarnessValueParser.date(from: raw) {
            return (date, date)
        }
        return (nil, nil)
    }

    static func halfYearBucket(for date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return "\(year)H\(month <= 6 ? 1 : 2)"
    }

    static func halfYearBucketLabel(_ bucket: String) -> String {
        guard bucket.count >= 6 else { return bucket }
        let year = String(bucket.prefix(4))
        let half = String(bucket.suffix(2))
        return "\(year) \(half)"
    }

    private static func dateStrings(in raw: String) -> [String] {
        let pattern = #"\d{4}[-/.]\d{1,2}[-/.]\d{1,2}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        return regex.matches(in: raw, range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: raw) else { return nil }
            return String(raw[range])
        }
    }
}

enum HarnessMetricIdentityResolver {
    private static let aliasGroups: [[String]] = [
        ["交易人数", "交易用户数", "交易用户人数", "支付人数", "支付用户数", "支付用户人数", "成交人数", "成交用户数", "下单人数", "下单用户数"],
        ["交易金额", "交易额", "gmv", "支付金额", "成交金额", "订单金额"],
        ["交易笔数", "交易次数", "订单数", "订单笔数", "支付笔数", "成交笔数", "成交次数"],
        ["申请人数", "申请用户数", "申办人数", "申办用户数", "进件人数", "进件用户数"],
        ["申请金额", "申请额度", "申请总额", "进件金额"],
        ["申请笔数", "申请次数", "进件笔数", "进件次数"],
        ["授信人数", "授信用户数", "审批通过人数", "批核人数", "批核用户数"],
        ["授信金额", "授信额度", "批核金额", "批核额度", "审批通过金额"],
        ["授信笔数", "授信次数", "批核笔数", "批核次数", "审批通过笔数"],
        ["放款人数", "放款用户数", "借款人数", "借款用户数", "提款人数", "提款用户数"],
        ["放款金额", "借款金额", "提款金额"],
        ["放款笔数", "放款次数", "借款笔数", "借款次数", "提款笔数", "提款次数"],
        ["还款人数", "还款用户数", "回款人数", "回款用户数"],
        ["还款金额", "回款金额"],
        ["还款笔数", "还款次数", "回款笔数", "回款次数"],
        ["注册人数", "注册用户数", "开户人数", "开户用户数"],
        ["活跃人数", "活跃用户数", "访问人数", "访问用户数", "登录人数", "登录用户数"],
        ["新用户数", "新增用户数", "新增人数"],
        ["老用户数", "存量用户数"],
        ["覆盖用户数", "覆盖人数"],
        ["累计覆盖用户数", "累计覆盖人数"]
    ]

    private static let neutralTerms = [
        "总", "总计", "合计", "整体", "全部", "全量", "去重", "唯一", "总数",
        "total", "overall", "all", "unique", "distinct"
    ]

    private static let discriminatorTerms = [
        "交易", "支付", "成交", "订单", "申请", "申办", "进件", "授信", "审批", "批核",
        "放款", "借款", "提款", "还款", "回款", "注册", "开户", "活跃", "访问", "登录",
        "新增", "新用户", "老用户", "存量", "初次", "首次", "本周", "周初", "累计",
        "覆盖", "占比", "比例", "转化", "留存", "逾期", "退款", "成功", "失败", "拒绝",
        "通过", "生活缴费", "话费充值", "娱乐", "押金卡", "普通卡", "渠道", "场景", "城市",
        "产品", "商户", "客群", "segment", "channel", "scene", "city", "product", "merchant",
        "new", "old", "first", "initial", "cumulative", "coverage", "active", "registered",
        "approved", "rejected", "refund", "success", "failed", "retention", "conversion"
    ]

    private static let tokenAliases: [(token: String, aliases: [String])] = [
        ("transaction", ["交易", "成交", "支付", "订单", "gmv", "transaction", "payment", "order"]),
        ("application", ["申请", "申办", "进件", "application", "apply"]),
        ("approval", ["授信", "审批", "批核", "通过", "approved", "approval", "credit"]),
        ("loan", ["放款", "借款", "提款", "loan", "disbursement", "withdraw"]),
        ("repayment", ["还款", "回款", "repay", "repayment"]),
        ("registration", ["注册", "开户", "register", "signup"]),
        ("active", ["活跃", "访问", "登录", "active", "visit", "login"]),
        ("new", ["新增", "新用户", "初次", "首次", "本周初次", "new", "first", "initial"]),
        ("old", ["老用户", "存量", "old", "existing"]),
        ("cumulative", ["累计", "累积", "cumulative"]),
        ("coverage", ["覆盖", "coverage"]),
        ("refund", ["退款", "退货", "refund"]),
        ("overdue", ["逾期", "overdue", "delinquency"]),
        ("life_payment", ["生活缴费"]),
        ("topup", ["话费充值", "充值"]),
        ("entertainment", ["娱乐"]),
        ("deposit_card", ["押金卡"]),
        ("normal_card", ["普通卡"]),
        ("people", ["人数", "用户数", "用户人数", "客户数", "客户人数", "人", "users", "user_count", "customer_count"]),
        ("amount", ["金额", "额度", "交易额", "gmv", "收入", "营收", "revenue", "amount", "money", "value"]),
        ("count", ["笔数", "次数", "单数", "订单数", "数量", "count", "times", "volume"]),
        ("rate", ["占比", "比例", "率", "%", "rate", "ratio", "share", "percent", "percentage"]),
        ("average", ["人均", "笔均", "单均", "客单价", "平均", "avg", "average", "per"])
    ]

    static func matches(sourceName: String, targetName: String) -> Bool {
        let sourceKey = sourceName.normalizedKey
        let targetKey = targetName.normalizedKey
        guard !sourceKey.isEmpty, !targetKey.isEmpty else { return false }
        if sourceKey == targetKey { return true }

        if let sourceAlias = aliasGroupKey(for: sourceKey),
           let targetAlias = aliasGroupKey(for: targetKey),
           sourceAlias == targetAlias {
            return true
        }

        let sourceStripped = stripNeutralTerms(sourceKey)
        let targetStripped = stripNeutralTerms(targetKey)
        if sourceStripped == targetStripped { return true }

        let sourceDiscriminators = discriminatorSet(in: sourceKey)
        let targetDiscriminators = discriminatorSet(in: targetKey)
        if sourceDiscriminators != targetDiscriminators {
            return false
        }

        let sourceTokens = semanticTokens(in: sourceKey)
        let targetTokens = semanticTokens(in: targetKey)
        guard !sourceTokens.isEmpty, !targetTokens.isEmpty else { return false }
        return sourceTokens == targetTokens
    }

    static func queryMentions(metricName: String, in query: String) -> Bool {
        let metricKey = metricName.normalizedKey
        let queryKey = query.normalizedKey
        guard !metricKey.isEmpty, !queryKey.isEmpty else { return false }
        if queryKey.contains(metricKey) || query.localizedCaseInsensitiveContains(metricName) {
            return true
        }

        if let aliasKey = aliasGroupKey(for: metricKey),
           aliasGroupsByKey[aliasKey]?.contains(where: { queryKey.contains($0.normalizedKey) }) == true {
            return true
        }

        let metricDiscriminators = discriminatorSet(in: metricKey)
        guard metricDiscriminators.isSubset(of: discriminatorSet(in: queryKey)) else {
            return false
        }
        let metricTokens = semanticTokens(in: metricKey)
        guard !metricTokens.isEmpty else { return false }
        return metricTokens.isSubset(of: semanticTokens(in: queryKey))
    }

    private static let aliasesByNormalizedKey: [String: String] = {
        var result: [String: String] = [:]
        for group in aliasGroups {
            guard let canonical = group.first?.normalizedKey else { continue }
            for alias in group {
                result[alias.normalizedKey] = canonical
            }
        }
        return result
    }()

    private static let aliasGroupsByKey: [String: [String]] = {
        var result: [String: [String]] = [:]
        for group in aliasGroups {
            guard let canonical = group.first?.normalizedKey else { continue }
            result[canonical] = group
        }
        return result
    }()

    private static func aliasGroupKey(for normalizedKey: String) -> String? {
        aliasesByNormalizedKey[normalizedKey]
    }

    private static func stripNeutralTerms(_ normalizedKey: String) -> String {
        neutralTerms.reduce(normalizedKey) { partial, term in
            partial.replacingOccurrences(of: term.normalizedKey, with: "")
        }
    }

    private static func discriminatorSet(in normalizedKey: String) -> Set<String> {
        Set(discriminatorTerms.compactMap { term in
            let key = term.normalizedKey
            return !key.isEmpty && normalizedKey.contains(key) ? key : nil
        })
    }

    private static func semanticTokens(in normalizedKey: String) -> Set<String> {
        Set(tokenAliases.compactMap { entry in
            entry.aliases.contains { alias in
                let key = alias.normalizedKey
                return !key.isEmpty && normalizedKey.contains(key)
            } ? entry.token : nil
        })
    }
}

struct NormalizedFactMetricAnalyzer {
    struct AnalysisIntent: Codable, Hashable {
        enum Source: String, Codable, Hashable {
            case deterministic
            case ai
            case merged
        }

        struct DerivedFormula: Codable, Hashable {
            var metric: String
            var numeratorMetric: String
            var denominatorMetric: String
            var formulaText: String
        }

        var requestedMetrics: [String]
        var supportingMetrics: [String]
        var derivedFormulas: [DerivedFormula]
        var wantsGrowthRate: Bool
        var aggregationMode: String
        var confidence: Double
        var source: Source
        var notes: [String]

        var needsSemanticAI: Bool {
            confidence < 0.75 || notes.contains { $0.contains("公式说明") || $0.contains("低置信") }
        }
    }

    enum AnalysisIntentParsingError: LocalizedError {
        case missingAPIKey
        case aiRequestFailed(String)
        case invalidAIResponse(String)
        case emptyRequestedMetrics
        case unmappedRequestedMetrics([String], available: [String])
        case unmappedFormula(metric: String, numerator: String, denominator: String, available: [String])

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "本轮需要 AI 先解析分析目标，请先在 AI 设置中填写 API Key。"
            case .aiRequestFailed(let message):
                return "AI 意图解析请求失败：\(message)"
            case .invalidAIResponse(let message):
                return "AI 意图解析返回格式无法解析：\(message)"
            case .emptyRequestedMetrics:
                return "AI 未返回可执行的主请求指标，系统不会用本地规则猜测用户语义。"
            case .unmappedRequestedMetrics(let metrics, let available):
                return "AI 返回的主请求指标无法映射到当前指标目录：\(metrics.joined(separator: "、"))。可用指标：\(available.prefix(30).joined(separator: "、"))。"
            case .unmappedFormula(let metric, let numerator, let denominator, let available):
                return "AI 返回的派生公式依赖无法映射到当前指标目录：\(metric)=\(numerator)/\(denominator)。可用指标：\(available.prefix(30).joined(separator: "、"))。"
            }
        }
    }

    struct AnalysisIntentParser {
        typealias AIIntentResolver = (String, [NormalizedFactTable], AISettings) async throws -> AnalysisIntent

        private let aiIntentResolver: AIIntentResolver

        init(aiIntentResolver: AIIntentResolver? = nil) {
            self.aiIntentResolver = aiIntentResolver ?? Self.aiIntent
        }

        func parse(
            userQuery: String,
            factTables: [NormalizedFactTable],
            settings: AISettings
        ) async throws -> AnalysisIntent {
            guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AnalysisIntentParsingError.missingAPIKey
            }
            do {
                let aiIntent = try await aiIntentResolver(userQuery, factTables, settings)
                return try Self.validatedAIIntent(aiIntent, factTables: factTables)
            } catch let error as AnalysisIntentParsingError {
                throw error
            } catch {
                throw AnalysisIntentParsingError.aiRequestFailed(error.localizedDescription)
            }
        }

        private static func aiIntent(
            userQuery: String,
            factTables: [NormalizedFactTable],
            settings: AISettings
        ) async throws -> AnalysisIntent {
            let prompt = intentPrompt(userQuery: userQuery, factTables: factTables)
            let output = try await AIAnalysisService().runAnalysis(
                prompt: prompt,
                settings: settings,
                timeout: NetworkTimeouts.analysisIntentRequest
            )
            let json = HarnessJSONExtractor.extractJSONObject(from: output)
            do {
                return try JSONDecoder.harnessDecoder.decode(AnalysisIntent.self, from: Data(json.utf8))
            } catch {
                throw AnalysisIntentParsingError.invalidAIResponse(error.localizedDescription)
            }
        }

        private static func validatedAIIntent(
            _ aiIntent: AnalysisIntent,
            factTables: [NormalizedFactTable]
        ) throws -> AnalysisIntent {
            let candidates = availableMetricCandidates(factTables: factTables)
            let requested = canonicalized(metrics: aiIntent.requestedMetrics, candidates: candidates)
            guard !requested.isEmpty else {
                if aiIntent.requestedMetrics.isEmpty {
                    throw AnalysisIntentParsingError.emptyRequestedMetrics
                }
                throw AnalysisIntentParsingError.unmappedRequestedMetrics(aiIntent.requestedMetrics, available: candidates)
            }
            let formulas = try aiIntent.derivedFormulas.map { formula -> AnalysisIntent.DerivedFormula in
                guard let metric = canonicalMetric(formula.metric, candidates: candidates),
                      let numerator = canonicalMetric(formula.numeratorMetric, candidates: candidates),
                      let denominator = canonicalMetric(formula.denominatorMetric, candidates: candidates) else {
                    throw AnalysisIntentParsingError.unmappedFormula(
                        metric: formula.metric,
                        numerator: formula.numeratorMetric,
                        denominator: formula.denominatorMetric,
                        available: candidates
                    )
                }
                return AnalysisIntent.DerivedFormula(
                    metric: metric,
                    numeratorMetric: numerator,
                    denominatorMetric: denominator,
                    formulaText: formula.formulaText
                )
            }.uniqued()
            let formulaDependencies = formulas.flatMap { [$0.numeratorMetric, $0.denominatorMetric] }
            let supporting = canonicalized(metrics: aiIntent.supportingMetrics + formulaDependencies, candidates: candidates)
                .filter { metric in !requested.contains(where: { HarnessMetricIdentityResolver.matches(sourceName: $0, targetName: metric) }) }
                .uniqued()
            return AnalysisIntent(
                requestedMetrics: requested,
                supportingMetrics: supporting,
                derivedFormulas: formulas,
                wantsGrowthRate: aiIntent.wantsGrowthRate,
                aggregationMode: aiIntent.aggregationMode.isEmpty ? "unknown" : aiIntent.aggregationMode,
                confidence: min(max(aiIntent.confidence, 0), 1),
                source: .ai,
                notes: (aiIntent.notes + ["AI 已完成意图解析；本地已校验指标名称和公式依赖。"]).uniqued()
            )
        }

        private static func intentPrompt(
            userQuery: String,
            factTables: [NormalizedFactTable]
        ) -> String {
            let metricCatalog = availableMetricCandidates(factTables: factTables).joined(separator: "、")
            return """
            你是 NexaFlow Analysis Harness 的意图解析器，只负责理解用户问题，不负责计算任何业务数字。
            请只输出 JSON 对象，字段必须符合：
            {
              "requestedMetrics": ["用户直接要求输出的指标"],
              "supportingMetrics": ["公式分子/分母等计算依赖，不是主回答指标"],
              "derivedFormulas": [{"metric":"派生指标","numeratorMetric":"分子指标","denominatorMetric":"分母指标","formulaText":"用户或默认公式"}],
              "wantsGrowthRate": false,
              "aggregationMode": "full_period_sum_ratio | period_average | unknown",
              "confidence": 0.0,
              "source": "ai",
              "notes": ["简短说明"]
            }

            关键规则：
            - 用户直接问“人均交易笔数和笔均交易金额”，后面解释“人均交易笔数是交易笔数除以交易人数”时，requestedMetrics 只包含派生指标；交易人数/交易金额/交易笔数进入 supportingMetrics。
            - 公式、定义、解释、等于、是每周... 里的基础指标不能当作用户主请求指标。
            - 只能使用下面指标目录里的名称；不确定时保留最接近目录名，不要发明新指标。
            - 语义识别完全由你完成；本地系统只会校验你的指标名和公式依赖是否存在，不会补猜主请求指标。
            - 不输出计算结果、数值或自然语言分析。

            指标目录：
            \(metricCatalog)

            用户问题：
            \(userQuery)
            """
        }

        private static func availableMetricCandidates(factTables: [NormalizedFactTable]) -> [String] {
            (defaultTradeMetrics + factTables.flatMap(\.metricCatalog).map(\.metricName)).uniqued()
        }

        private static func canonicalized(metrics: [String], candidates: [String]) -> [String] {
            metrics.compactMap { canonicalMetric($0, candidates: candidates) }.uniqued()
        }

        private static func canonicalMetric(_ metric: String, candidates: [String]) -> String? {
            candidates.first { HarnessMetricIdentityResolver.matches(sourceName: $0, targetName: metric) }
        }
    }

    struct Output {
        var plan: AnalysisPlan
        var results: [MetricResult]
        var issues: [ValidationIssue]
    }

    static func analyze(
        userQuery: String,
        factTables: [NormalizedFactTable],
        intent: AnalysisIntent? = nil
    ) -> Output? {
        guard let resolvedIntent = intent else { return nil }
        let requested = resolvedIntent.requestedMetrics
        guard !requested.isEmpty else { return nil }
        guard let table = bestTable(for: requested, factTables: factTables) else { return nil }
        let buckets = comparisonBuckets(userQuery: userQuery, table: table)
        guard buckets.count >= 2 else { return nil }
        let baseMetrics = requiredBaseMetrics(for: requested)
        let includeGrowth = resolvedIntent.wantsGrowthRate
        var results: [MetricResult] = []
        var baseValues: [String: [String: (value: Double, rows: [NormalizedFactRow])]] = [:]
        for metric in baseMetrics {
            for bucket in buckets {
                let rows = table.rows.filter {
                    $0.periodBucket == bucket &&
                        metricMatches($0.metricName, target: metric, aliases: table.metricAliases) &&
                        $0.valueKind != .ratio
                }
                guard !rows.isEmpty else { continue }
                let total = rows.compactMap(\.metricValue).reduce(0, +)
                baseValues[metric, default: [:]][bucket] = (total, rows)
                results.append(result(
                    label: "\(metric) \(HarnessPeriodResolver.halfYearBucketLabel(bucket))",
                    value: total,
                    unit: unit(for: metric),
                    format: metric.contains("人数") || metric.contains("笔数") ? .integer : .currency,
                    table: table,
                    operation: .sum,
                    metricName: metric,
                    bucket: bucket,
                    rows: rows,
                    methodology: "\(HarnessPeriodResolver.halfYearBucketLabel(bucket))：按周期起始日归桶，筛选“\(metric)”后对“值”列执行 SUM。",
                    presentationRole: requested.contains(metric) ? .requested : .supporting
                ))
            }
        }
        appendDerivedResults(requested: requested, buckets: buckets, table: table, baseValues: baseValues, into: &results)
        appendGrowthResults(
            requested: requested,
            buckets: buckets,
            table: table,
            baseValues: baseValues,
            includeAsPrimary: includeGrowth,
            into: &results
        )

        var issues: [ValidationIssue] = []
        let catalogNames = Set(table.metricCatalog.map { $0.metricName.normalizedKey })
        for metric in requested where !isDerived(metric) {
            let hasCatalogMatch = catalogNames.contains { catalogName in
                metricMatches(catalogName, target: metric, aliases: table.metricAliases)
            }
            guard !hasCatalogMatch else { continue }
            issues.append(ValidationIssue(
                severity: .warning,
                code: .missingField,
                stage: .tableUnderstanding,
                message: "标准事实表中未找到请求指标：\(metric)。",
                evidence: ["metricCatalog": table.metricCatalog.map(\.metricName).joined(separator: "、")]
            ))
        }
        let plan = AnalysisPlan(
            userQuestion: userQuery,
            tablesUsed: [table.tableID],
            metrics: [],
            assumptions: [
                HarnessAnalysisAssumption(label: "意图解析", detail: "用户主请求指标：\(requested.joined(separator: "、"))；计算依赖：\(resolvedIntent.supportingMetrics.joined(separator: "、"))；来源：\(resolvedIntent.source.rawValue)，置信度 \(String(format: "%.2f", resolvedIntent.confidence))。", affectsResult: true),
                HarnessAnalysisAssumption(label: "表格解释", detail: "已将 \(table.shape.label) 标准化为事实表后计算。", affectsResult: true),
                HarnessAnalysisAssumption(label: "半年度归桶", detail: "周区间按周期起始日归属 H1/H2。", affectsResult: true),
                HarnessAnalysisAssumption(label: "派生指标", detail: "人均/笔均由全周期 SUM 分子和 SUM 分母重算。", affectsResult: true)
            ],
            limitations: coverageWarnings(table: table, buckets: buckets) + resolvedIntent.notes,
            intendedOutput: "先直接回答 H2/H1 对比，再展示本地事实表证据。",
            createdBy: "normalized_fact_table"
        )
        return Output(plan: plan, results: results, issues: issues)
    }

    private static let defaultTradeMetrics = ["交易人数", "交易金额", "交易笔数", "人均交易金额", "人均交易笔数", "笔均交易金额"]
    private static let derivedDefinitions: [(label: String, numerator: String, denominator: String, unit: String)] = [
        ("人均交易金额", "交易金额", "交易人数", "MXN/人"),
        ("人均交易笔数", "交易笔数", "交易人数", "笔/人"),
        ("笔均交易金额", "交易金额", "交易笔数", "MXN/笔")
    ]

    private static func bestTable(
        for requested: [String],
        factTables: [NormalizedFactTable]
    ) -> NormalizedFactTable? {
        let baseMetrics = requiredBaseMetrics(for: requested)
        return factTables.max { lhs, rhs in
            score(table: lhs, baseMetrics: baseMetrics) < score(table: rhs, baseMetrics: baseMetrics)
        }
    }

    private static func score(table: NormalizedFactTable, baseMetrics: [String]) -> Int {
        let catalogNames = table.metricCatalog.map(\.metricName)
        let matchedMetrics = baseMetrics.filter { metric in
            catalogNames.contains { metricMatches($0, target: metric, aliases: table.metricAliases) }
        }.count
        let bucketCount = Set(table.rows.compactMap(\.periodBucket)).count
        return matchedMetrics * 10_000 + bucketCount * 100 + min(table.rows.count, 99)
    }

    private static func requiredBaseMetrics(for requested: [String]) -> [String] {
        var result = requested.filter { !isDerived($0) }
        if requested.contains(where: { $0.contains("人均交易金额") || $0.contains("笔均交易金额") }) {
            result.append("交易金额")
        }
        if requested.contains(where: { $0.contains("人均交易金额") || $0.contains("人均交易笔数") }) {
            result.append("交易人数")
        }
        if requested.contains(where: { $0.contains("人均交易笔数") || $0.contains("笔均交易金额") }) {
            result.append("交易笔数")
        }
        return result.uniqued()
    }

    private static func comparisonBuckets(userQuery: String, table: NormalizedFactTable) -> [String] {
        let available = Set(table.rows.compactMap(\.periodBucket)).sorted()
        guard available.count >= 2 else { return available }
        let query = userQuery.normalizedKey
        if query.contains("去年") && query.contains("今年") && query.contains("下半年") && query.contains("上半年") {
            let calendar = Calendar(identifier: .gregorian)
            let currentYear = calendar.component(.year, from: Date())
            let preferred = ["\(currentYear - 1)H2", "\(currentYear)H1"]
            if preferred.allSatisfy({ available.contains($0) }) {
                return preferred
            }
        }
        if available.contains("2025H2"), available.contains("2026H1") {
            return ["2025H2", "2026H1"]
        }
        return Array(available.suffix(2))
    }

    private static func appendDerivedResults(
        requested: [String],
        buckets: [String],
        table: NormalizedFactTable,
        baseValues: [String: [String: (value: Double, rows: [NormalizedFactRow])]],
        into results: inout [MetricResult]
    ) {
        let derivedDefinitions: [(label: String, numerator: String, denominator: String, unit: String)] = [
            ("人均交易金额", "交易金额", "交易人数", "MXN/人"),
            ("人均交易笔数", "交易笔数", "交易人数", "笔/人"),
            ("笔均交易金额", "交易金额", "交易笔数", "MXN/笔")
        ]
        for definition in derivedDefinitions where requested.contains(definition.label) {
            for bucket in buckets {
                guard let numerator = baseValues[definition.numerator]?[bucket],
                      let denominator = baseValues[definition.denominator]?[bucket],
                      denominator.value != 0 else { continue }
                let value = numerator.value / denominator.value
                results.append(result(
                    label: "\(definition.label) \(HarnessPeriodResolver.halfYearBucketLabel(bucket))",
                    value: value,
                    unit: definition.unit,
                    format: .decimal,
                    table: table,
                    operation: .calculateRatio,
                    metricName: definition.label,
                    bucket: bucket,
                    rows: numerator.rows + denominator.rows,
                    methodology: "\(HarnessPeriodResolver.halfYearBucketLabel(bucket))：\(definition.numerator) SUM ÷ \(definition.denominator) SUM。",
                    presentationRole: .derivedRequested
                ))
            }
        }
    }

    private static func appendGrowthResults(
        requested: [String],
        buckets: [String],
        table: NormalizedFactTable,
        baseValues: [String: [String: (value: Double, rows: [NormalizedFactRow])]],
        includeAsPrimary: Bool,
        into results: inout [MetricResult]
    ) {
        guard buckets.count >= 2 else { return }
        let baseBucket = buckets[0]
        let comparisonBucket = buckets[1]
        for metric in requiredBaseMetrics(for: requested) {
            guard let base = baseValues[metric]?[baseBucket],
                  let comparison = baseValues[metric]?[comparisonBucket],
                  base.value != 0 else { continue }
            let growth = (comparison.value / base.value - 1) * 100
            results.append(result(
                label: "\(metric) 增长率 \(HarnessPeriodResolver.halfYearBucketLabel(baseBucket)) → \(HarnessPeriodResolver.halfYearBucketLabel(comparisonBucket))",
                value: growth,
                unit: "%",
                format: .percent,
                table: table,
                operation: .calculateGrowthRate,
                metricName: metric,
                bucket: "\(baseBucket)→\(comparisonBucket)",
                rows: base.rows + comparison.rows,
                methodology: "(\(comparisonBucket) SUM ÷ \(baseBucket) SUM - 1) × 100。",
                presentationRole: includeAsPrimary && requested.contains(metric) ? .requested : .diagnostic
            ))
        }
    }

    private static func result(
        label: String,
        value: Double,
        unit: String,
        format: MetricResultFormat,
        table: NormalizedFactTable,
        operation: HarnessAnalysisOperation,
        metricName: String,
        bucket: String,
        rows: [NormalizedFactRow],
        methodology: String,
        presentationRole: MetricResultPresentationRole
    ) -> MetricResult {
        let sourceRows = rows.map(\.sourceRow)
        let sourceColumns = rows.map(\.sourceColumn)
        let rowRange = rangeText(values: sourceRows)
        let columnRange = rangeText(values: sourceColumns)
        let cells = sourceCells(rows: rows)
        let coverage = coverageSummary(rows: rows, bucket: bucket)
        let source = MetricResultSource(
            tableID: table.tableID,
            tableName: table.tableName,
            operation: operation,
            field: "metric_name=\(metricName); metric_value=值",
            groupKey: bucket,
            rowCount: rows.count,
            filtersApplied: [],
            methodology: methodology,
            factRowCount: rows.count,
            sourceRowRange: rowRange,
            sourceColumnRange: columnRange,
            sourceCells: cells,
            coverageSummary: coverage,
            lineageSummary: "事实表 \(rows.count) 行；原始行 \(rowRange)，原始列 \(columnRange)。"
        )
        var warnings: [String] = []
        if let warning = incompleteHalfYearWarning(rows: rows, bucket: bucket) {
            warnings.append(warning)
        }
        return MetricResult(
            metricID: UUID(),
            label: label,
            rawValue: value,
            unit: unit,
            format: format,
            source: source,
            confidence: warnings.isEmpty ? 1 : 0.85,
            warnings: warnings,
            presentationRole: presentationRole
        )
    }

    private static func sourceCells(rows: [NormalizedFactRow], maxCount: Int = 5_000) -> [HarnessSourceCellRef] {
        let sorted = rows.sorted { lhs, rhs in
            if lhs.sourceRow == rhs.sourceRow { return lhs.sourceColumn < rhs.sourceColumn }
            return lhs.sourceRow < rhs.sourceRow
        }
        var cells: [HarnessSourceCellRef] = []
        var seen = Set<String>()
        for row in sorted {
            let key = "\(row.sourceSheet)|\(row.sourceRow)|\(row.sourceColumn)"
            guard !seen.contains(key) else { continue }
            cells.append(HarnessSourceCellRef(
                sheetName: row.sourceSheet,
                row: row.sourceRow,
                column: row.sourceColumn,
                columnName: "值",
                value: row.rawValue
            ))
            seen.insert(key)
            if cells.count >= maxCount {
                break
            }
        }
        return cells
    }

    private static func coverageWarnings(table: NormalizedFactTable, buckets: [String]) -> [String] {
        buckets.compactMap { bucket in
            let rows = table.rows.filter { $0.periodBucket == bucket }
            return incompleteHalfYearWarning(rows: rows, bucket: bucket)
        }
        .uniqued()
    }

    private static func incompleteHalfYearWarning(rows: [NormalizedFactRow], bucket: String) -> String? {
        let periods = Set(rows.map(\.periodRaw)).filter { !$0.isEmpty }
        guard bucket.hasSuffix("H1") || bucket.hasSuffix("H2") else { return nil }
        let expectedMinimum = 25
        if periods.count < expectedMinimum {
            let latest = rows.compactMap(\.periodEnd).max() ?? rows.compactMap(\.periodStart).max() ?? ""
            return "\(HarnessPeriodResolver.halfYearBucketLabel(bucket)) 覆盖 \(periods.count) 个周期\(latest.isEmpty ? "" : "，截至 \(latest)")，可能不是完整半年度。"
        }
        return nil
    }

    private static func coverageSummary(rows: [NormalizedFactRow], bucket: String) -> String {
        let periods = Set(rows.map(\.periodRaw)).filter { !$0.isEmpty }
        let minStart = rows.compactMap(\.periodStart).min()
        let maxEnd = rows.compactMap(\.periodEnd).max() ?? rows.compactMap(\.periodStart).max()
        let range = [minStart, maxEnd].compactMap { $0 }.joined(separator: " 至 ")
        return "\(HarnessPeriodResolver.halfYearBucketLabel(bucket))：\(periods.count) 个周期\(range.isEmpty ? "" : "，\(range)")。"
    }

    private static func metricMatches(
        _ source: String,
        target: String,
        aliases: [String: String] = [:]
    ) -> Bool {
        if HarnessMetricIdentityResolver.matches(sourceName: source, targetName: target) {
            return true
        }
        let sourceKey = source.normalizedKey
        let targetKey = target.normalizedKey
        for (requested, actual) in aliases {
            let requestedKey = requested.normalizedKey
            let actualKey = actual.normalizedKey
            if targetKey == requestedKey,
               HarnessMetricIdentityResolver.matches(sourceName: sourceKey, targetName: actualKey) {
                return true
            }
            if targetKey == actualKey,
               HarnessMetricIdentityResolver.matches(sourceName: sourceKey, targetName: requestedKey) {
                return true
            }
        }
        return false
    }

    private static func isDerived(_ metric: String) -> Bool {
        metric.contains("人均") || metric.contains("笔均") || metric.contains("客单价")
    }

    private static func unit(for metric: String) -> String {
        if metric.contains("金额") { return "MXN" }
        if metric.contains("人数") { return "人" }
        if metric.contains("笔数") { return "笔" }
        return ""
    }

    private static func rangeText(values: [Int]) -> String {
        guard let min = values.min(), let max = values.max() else { return "-" }
        return min == max ? "\(min)" : "\(min)-\(max)"
    }
}

struct TableUnderstandingConfidenceGate {
    static func validate(
        userQuery: String,
        manifests: [TableManifest],
        factTables: [NormalizedFactTable]
    ) -> [ValidationIssue] {
        guard AnalysisHarnessRouter.userMessageLooksLikeTableComputation(userQuery) else { return [] }
        var issues: [ValidationIssue] = []
        let factTableIDs = Set(factTables.map(\.tableID))
        for manifest in manifests {
            guard let understanding = manifest.understanding else { continue }
            let hasPartialMapping = understanding.periodColumn != nil ||
                understanding.metricNameColumn != nil ||
                understanding.metricValueColumn != nil
            if hasPartialMapping, !factTableIDs.contains(manifest.id) {
                issues.append(ValidationIssue(
                    severity: .fatal,
                    code: .ambiguousFieldMapping,
                    stage: .tableUnderstanding,
                    message: "表“\(manifest.displayName)”像是指标/周期/数值结构，但没有成功转成标准事实表。需要确认周期列、指标列和数值列后再计算。",
                    expected: "明确的周期列、指标列、数值列映射",
                    actual: "周期列=\(understanding.periodColumn ?? "未识别")；指标列=\(understanding.metricNameColumn ?? "未识别")；数值列=\(understanding.metricValueColumn ?? "未识别")",
                    fixHint: "在分析资料中确认表格结构，或导入列名更明确的表格。",
                    evidence: [
                        "shape": understanding.shape.label,
                        "confidence": "\(Int(understanding.confidence * 100))%"
                    ]
                ))
            } else if understanding.confidence < 0.55, hasPartialMapping {
                issues.append(ValidationIssue(
                    severity: .error,
                    code: .ambiguousFieldMapping,
                    stage: .tableUnderstanding,
                    message: "表“\(manifest.displayName)”的表格理解置信度偏低（\(Int(understanding.confidence * 100))%），不允许直接输出新业务数字。",
                    expected: "表格理解置信度 >= 55%",
                    actual: "\(Int(understanding.confidence * 100))%",
                    fixHint: "请确认周期列、指标列、数值列和周归属规则；确认后可保存为分析模板。",
                    evidence: [
                        "shape": understanding.shape.label,
                        "periodColumn": understanding.periodColumn ?? "",
                        "metricNameColumn": understanding.metricNameColumn ?? "",
                        "metricValueColumn": understanding.metricValueColumn ?? ""
                    ]
                ))
            }
        }
        return issues
    }
}
