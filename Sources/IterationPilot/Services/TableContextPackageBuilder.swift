import Foundation

enum TableContextPackageBuilder {
    private static let fullRowLimit = 500
    private static let storedDetailRowLimit = 20_000
    private static let fullRawCellLimit = 60_000
    private static let fullRawPivotCellLimit = 120_000
    private static let maxFulfilledRawCellLimit = 120_000

    static func build(for report: ImportedReport) -> TableContextPackage {
        let rows = effectiveRows(for: report)
        let rawRows = effectiveRawRows(for: report)
        let timeColumns = detectedTimeColumns(in: report)
        let duplicateHeaders = duplicatedHeaders(report.headers)
        let fieldProfiles = report.headers.map { fieldProfile(for: $0, rows: rows) }
        let metricSeries = metricSeries(for: report, rows: rows, timeColumns: timeColumns)
        let sendFullRows = rows.count <= fullRowLimit || report.shape == .pivotWide
        let rawMatrix = rawMatrixContext(for: report, rawRows: rawRows)
        let payloadRows = sendFullRows ? rows : []
        let rowSamples = sendFullRows ? [] : representativeSamples(from: rows)
        let sentRows = sendFullRows ? rows.count : rowSamples.count
        let resolvedMetricCount = metricSeries.isEmpty ? report.firstColumnValues.count : metricSeries.count
        let sentMetrics = metricSeries.isEmpty ? report.firstColumnValues.count : metricSeries.count

        let coverage = TableContextCoverage(
            totalRows: report.rowCount,
            sentRows: sentRows,
            totalColumns: report.headers.count,
            sentColumns: report.headers.count,
            totalMetrics: resolvedMetricCount,
            sentMetrics: sentMetrics,
            omittedRowsDescription: sendFullRows ? "未省略行" : "明细表较大，首轮只发送字段画像、聚合摘要和代表性样本；AI 如需结论必须请求具体行、列或聚合。",
            omittedColumnsDescription: "未省略列；字段清单和画像已全量发送。",
            limitations: limitations(for: report, rows: rows, rawMatrix: rawMatrix, sendFullRows: sendFullRows),
            rawDataMode: rawMatrix.mode,
            totalRawRows: rawMatrix.totalRows,
            sentRawRows: rawMatrix.sentRows,
            rawCoverageDescription: rawMatrix.mode == "full_raw_matrix"
                ? "原始二维表已全量发送 \(rawMatrix.sentRows)/\(rawMatrix.totalRows) 行"
                : "原始二维表以索引方式提供，首轮发送 \(rawMatrix.sentRows)/\(rawMatrix.totalRows) 行预览，AI 可继续请求原始行列范围"
        )

        return TableContextPackage(
            generatedAt: Date(),
            manifest: TableContextManifest(
                reportID: report.id,
                fileName: report.displayName,
                sourceFileName: report.sourceFileName.nilIfBlank ?? report.fileName,
                sheetName: report.sheetName,
                sourceFormat: report.sourceFormat,
                reportKind: report.kind,
                shape: report.shape,
                rowCount: report.rowCount,
                columnCount: report.headers.count,
                metricCount: resolvedMetricCount,
                timeColumnCount: timeColumns.count,
                parseWarnings: report.parseWarnings,
                timeAxisProfile: report.timeAxisProfile
            ),
            inventory: TableContextInventory(
                headers: report.headers,
                firstColumnMetrics: report.firstColumnValues,
                timeColumns: timeColumns,
                duplicateHeaders: duplicateHeaders,
                fieldProfiles: fieldProfiles
            ),
            dataPayload: TableDataPayload(
                mode: sendFullRows ? "full_rows" : "profile_samples_aggregates",
                fullRows: payloadRows,
                metricSeries: metricSeries,
                rowSamples: rowSamples,
                aggregateSummaries: aggregateSummaries(for: report, rows: rows)
            ),
            rawMatrix: rawMatrix,
            structureCandidates: structureCandidates(for: report, rawRows: rawRows, timeColumns: timeColumns),
            coverage: coverage
        )
    }

    static func storedRows(for table: CSVTable) -> [[String: String]] {
        Array(table.rows.prefix(storedDetailRowLimit))
    }

    static func fulfillment(for request: AIDataRequest, report: ImportedReport) -> AIDataRequest {
        let rows = effectiveRows(for: report)
        var copy = request
        switch request.kind {
        case .getMetricSeries:
            let package = build(for: report)
            let match = package.dataPayload.metricSeries.first {
                $0.metricName.normalizedKey == request.target.normalizedKey ||
                    $0.metricName.normalizedKey.contains(request.target.normalizedKey) ||
                    request.target.normalizedKey.contains($0.metricName.normalizedKey)
            }
            if let match {
                copy.status = .fulfilled
                copy.responseSummary = clipped(match.points.map { "\($0.label)=\($0.rawValue)" }.joined(separator: "；"), to: 2_000)
            } else {
                copy.status = .unavailable
                copy.responseSummary = "未找到指标「\(request.target)」的完整时间序列。"
            }
        case .getColumns:
            let targets = request.target
                .components(separatedBy: CharacterSet(charactersIn: ",，;；\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let profiles = targets.compactMap { target in
                report.headers.first { $0.normalizedKey == target.normalizedKey || $0.normalizedKey.contains(target.normalizedKey) }
            }.map { fieldProfile(for: $0, rows: rows) }
            if profiles.isEmpty {
                copy.status = .unavailable
                copy.responseSummary = "未找到请求字段。"
            } else {
                copy.status = .fulfilled
                copy.responseSummary = clipped(profiles.map {
                    "\($0.name)：类型 \($0.inferredType)，非空 \($0.nonEmptyCount)，缺失 \($0.missingCount)，样例 \($0.exampleValues.joined(separator: "/"))"
                }.joined(separator: "；"), to: 2_000)
            }
        case .getRows:
            copy.status = rows.isEmpty ? .unavailable : .fulfilled
            copy.responseSummary = clipped(rows.prefix(80).map { row in
                report.headers.prefix(12).map { "\($0)=\(row[$0] ?? "")" }.joined(separator: ", ")
            }.joined(separator: "\n"), to: 3_000)
        case .getAggregate:
            let summaries = aggregateSummaries(for: report, rows: rows)
            copy.status = summaries.isEmpty ? .unavailable : .fulfilled
            copy.responseSummary = clipped(summaries.joined(separator: "\n"), to: 3_000)
        case .getComparisonWindow:
            let comparisons = report.trendSummary.metricTrends.compactMap { trend -> String? in
                guard let comparison = trend.primaryComparison else { return nil }
                return "\(trend.metricName)：\(comparison.currentLabel) vs \(comparison.previousLabel)，\(comparison.previousValue.compactText) -> \(comparison.currentValue.compactText)，\(comparison.direction.rawValue)"
            }
            copy.status = comparisons.isEmpty ? .unavailable : .fulfilled
            copy.responseSummary = clipped(comparisons.prefix(80).joined(separator: "\n"), to: 3_000)
        case .getRawRange:
            let rawRows = effectiveRawRows(for: report)
            guard !rawRows.isEmpty else {
                copy.status = .unavailable
                copy.responseSummary = "没有可返回的原始二维表。"
                return copy
            }
            let range = rawRange(from: request.target, rowCount: rawRows.count, columnCount: maxColumnCount(rawRows))
            let sliced = slice(rawRows: rawRows, rowStart: range.rowStart, rowEnd: range.rowEnd, colStart: range.colStart, colEnd: range.colEnd)
            copy.status = sliced.isEmpty ? .unavailable : .fulfilled
            copy.responseSummary = clipped(renderRawRows(sliced, rowOffset: range.rowStart, colOffset: range.colStart), to: 12_000)
        case .getFullSheet:
            let rawRows = effectiveRawRows(for: report)
            let cellCount = rawRows.reduce(0) { $0 + $1.count }
            guard !rawRows.isEmpty else {
                copy.status = .unavailable
                copy.responseSummary = "没有可返回的原始二维表。"
                return copy
            }
            guard cellCount <= maxFulfilledRawCellLimit else {
                copy.status = .unavailable
                copy.responseSummary = "整张表 \(rawRows.count) 行、约 \(cellCount) 个单元格，超过单次补数上限；请使用 getRawRange 按行列范围分块请求。"
                return copy
            }
            copy.status = .fulfilled
            copy.responseSummary = clipped(renderRawRows(rawRows, rowOffset: 1, colOffset: 1), to: 60_000)
        }
        return copy
    }

    private static func effectiveRows(for report: ImportedReport) -> [[String: String]] {
        if !report.storedDataRows.isEmpty { return report.storedDataRows }
        return report.sampleRows
    }

    private static func effectiveRawRows(for report: ImportedReport) -> [[String]] {
        if !report.rawRows.isEmpty { return report.rawRows }
        guard !report.headers.isEmpty else { return [] }
        return [report.headers] + effectiveRows(for: report).map { row in
            report.headers.map { row[$0] ?? "" }
        }
    }

    private static func rawMatrixContext(for report: ImportedReport, rawRows: [[String]]) -> RawTableMatrixContext {
        let totalRows = rawRows.count
        let totalColumns = maxColumnCount(rawRows)
        let cellCount = rawRows.reduce(0) { $0 + $1.count }
        let fullLimit = report.shape == .pivotWide ? fullRawPivotCellLimit : fullRawCellLimit
        let sendFullRaw = cellCount <= fullLimit
        let previewRanges = sendFullRaw ? [] : previewRanges(for: rawRows)
        let sentRows = sendFullRaw
            ? totalRows
            : Set(previewRanges.flatMap { Array($0.rowStart...$0.rowEnd) }).count
        let structureRisks = structureRisks(for: report, rawRows: rawRows, cellCount: cellCount, sendFullRaw: sendFullRaw)

        return RawTableMatrixContext(
            mode: sendFullRaw ? "full_raw_matrix" : "indexed_raw_matrix",
            totalRows: totalRows,
            totalColumns: totalColumns,
            sentRows: sentRows,
            sentColumns: sendFullRaw ? totalColumns : min(totalColumns, 40),
            fullRawRows: sendFullRaw ? rawRows : [],
            previewRanges: previewRanges,
            omittedDescription: sendFullRaw
                ? "原始二维表已全量发送。AI 应优先直接读取原始单元格，而不是只相信本地识别出的结构。"
                : "原始二维表较大，首轮发送表头、首部、中部和尾部预览；AI 必须用 getRawRange 或 getFullSheet 补数后，才能对未覆盖区域下确定结论。",
            cellTypeHints: report.cellTypeHints,
            structureRisks: structureRisks,
            availableRequests: AIDataRequestKind.allCases.map(\.rawValue)
        )
    }

    private static func previewRanges(for rawRows: [[String]]) -> [RawTablePreviewRange] {
        guard !rawRows.isEmpty else { return [] }
        let totalRows = rawRows.count
        let totalColumns = maxColumnCount(rawRows)
        let colEnd = min(totalColumns, 40)
        var ranges: [RawTablePreviewRange] = []
        ranges.append(rawPreviewRange(name: "表头与前部", rawRows: rawRows, rowStart: 1, rowEnd: min(totalRows, 80), colStart: 1, colEnd: colEnd))
        if totalRows > 160 {
            let midStart = max(1, totalRows / 2 - 30)
            ranges.append(rawPreviewRange(name: "中部样本", rawRows: rawRows, rowStart: midStart, rowEnd: min(totalRows, midStart + 59), colStart: 1, colEnd: colEnd))
        }
        if totalRows > 100 {
            ranges.append(rawPreviewRange(name: "尾部样本", rawRows: rawRows, rowStart: max(1, totalRows - 59), rowEnd: totalRows, colStart: 1, colEnd: colEnd))
        }
        return ranges
    }

    private static func rawPreviewRange(
        name: String,
        rawRows: [[String]],
        rowStart: Int,
        rowEnd: Int,
        colStart: Int,
        colEnd: Int
    ) -> RawTablePreviewRange {
        RawTablePreviewRange(
            name: name,
            rowStart: rowStart,
            rowEnd: rowEnd,
            colStart: colStart,
            colEnd: colEnd,
            rows: slice(rawRows: rawRows, rowStart: rowStart, rowEnd: rowEnd, colStart: colStart, colEnd: colEnd)
        )
    }

    private static func structureCandidates(for report: ImportedReport, rawRows: [[String]], timeColumns: [String]) -> [TableStructureCandidate] {
        guard !rawRows.isEmpty else { return [] }
        let headerRows = report.shape == .pivotWide
            ? Array(1...min(3, rawRows.count))
            : [1]
        let totalColumns = maxColumnCount(rawRows)
        let timeIndexes = report.headers.enumerated().compactMap { index, header in
            timeColumns.contains(header) ? index + 1 : nil
        }
        let dimensionIndexes = Array(1...min(totalColumns, 8)).filter { !timeIndexes.contains($0) }
        return [
            TableStructureCandidate(
                name: "本地结构识别候选，AI 可质疑并重新判断",
                shape: report.shape,
                headerRows: headerRows,
                dataStartRow: min(rawRows.count, headerRows.count + 1),
                metricColumnIndex: report.shape == .pivotWide ? 1 : nil,
                timeColumnIndexes: timeIndexes,
                dimensionColumnIndexes: dimensionIndexes,
                confidence: max(0.1, min(0.95, report.detectedConfidence)),
                risks: structureRisks(for: report, rawRows: rawRows, cellCount: rawRows.reduce(0) { $0 + $1.count }, sendFullRaw: true)
            )
        ]
    }

    private static func structureRisks(
        for report: ImportedReport,
        rawRows: [[String]],
        cellCount: Int,
        sendFullRaw: Bool
    ) -> [String] {
        var risks = report.parseWarnings
        if !report.timeAxisProfile.warnings.isEmpty {
            risks.append(contentsOf: report.timeAxisProfile.warnings)
        }
        if report.timeAxisProfile.orientation == .verticalDateColumn || report.timeAxisProfile.orientation == .mixed {
            risks.append("本地识别到竖向时间列候选：\(report.timeAxisProfile.summary)。AI 需要结合用户目标确认使用注册时间、交易时间、审核时间或其他时间口径。")
        }
        if report.shape == .unknown {
            risks.append("本地未能高置信识别表格结构，AI 需要直接检查原始二维表。")
        }
        if report.shape == .pivotWide {
            risks.append("本地把第一列视作指标、横向列视作时间或分组；AI 需要确认这是否符合业务口径。")
        }
        if duplicatedHeaders(report.headers).isEmpty == false {
            risks.append("存在重复或合并后的表头，AI 需要检查多行表头是否被正确还原。")
        }
        if rawRows.prefix(5).contains(where: { row in row.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count <= 1 }) {
            risks.append("表格前部存在稀疏行，可能是标题、说明或合并单元格残留。")
        }
        if !sendFullRaw {
            risks.append("首轮未发送完整原始矩阵；AI 做精确判断前应请求原始行列范围。")
        }
        if cellCount > fullRawCellLimit {
            risks.append("表格较大，需通过可追问索引分块读取，不能凭样本覆盖全表。")
        }
        return risks.uniqued()
    }

    private static func detectedTimeColumns(in report: ImportedReport) -> [String] {
        let headerMatches = report.headers.filter { header in
            DateParsing.parse(header) != nil ||
                header.normalizedKey.contains("date") ||
                header.normalizedKey.contains("week") ||
                header.normalizedKey.contains("month") ||
                header.contains("日") ||
                header.contains("周") ||
                header.contains("月")
        }
        let profileMatches = report.timeAxisProfile.candidateDateColumns.map(\.columnName)
        let sampleMatches = report.headers.filter { header in
            let rows = effectiveRows(for: report)
            let sample = rows.prefix(40).map { $0[header] ?? "" }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard sample.count >= 2 else { return false }
            let parsed = sample.filter { DateParsing.periodRange($0) != nil || DateParsing.parse($0) != nil }.count
            return parsed >= max(2, sample.count * 2 / 3)
        }
        return (headerMatches + profileMatches + sampleMatches).uniqued()
    }

    private static func duplicatedHeaders(_ headers: [String]) -> [String] {
        let grouped = Dictionary(grouping: headers, by: { $0.normalizedKey })
        return grouped.values.filter { $0.count > 1 }.flatMap { $0 }.uniqued()
    }

    private static func fieldProfile(for header: String, rows: [[String: String]]) -> TableFieldProfile {
        let values = rows.map { ($0[header] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        let nonEmpty = values.filter { !$0.isEmpty }
        return TableFieldProfile(
            name: header,
            inferredType: inferredType(values: nonEmpty),
            missingCount: values.count - nonEmpty.count,
            nonEmptyCount: nonEmpty.count,
            exampleValues: Array(nonEmpty.uniqued().prefix(6))
        )
    }

    private static func inferredType(values: [String]) -> String {
        guard !values.isEmpty else { return "empty" }
        let sample = Array(values.prefix(30))
        let numericCount = sample.filter { parseNumber($0) != nil }.count
        let dateCount = sample.filter { DateParsing.periodRange($0) != nil || DateParsing.parse($0) != nil }.count
        if numericCount >= max(2, sample.count * 2 / 3) { return "number" }
        if dateCount >= max(2, sample.count * 2 / 3) { return "date" }
        if Set(sample.map(\.normalizedKey)).count <= max(3, sample.count / 3) { return "category" }
        return "text"
    }

    private static func metricSeries(for report: ImportedReport, rows: [[String: String]], timeColumns: [String]) -> [TableMetricSeries] {
        if let longSeries = longPeriodMetricSeries(for: report, rows: rows) {
            return longSeries
        }
        guard report.shape == .pivotWide, let metricHeader = report.headers.first else {
            return []
        }
        let columns = timeColumns.isEmpty ? Array(report.headers.dropFirst()) : timeColumns
        return rows.compactMap { row in
            guard let metricName = row[metricHeader]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank else {
                return nil
            }
            let points = columns.map { column in
                let raw = row[column]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let trend = report.trendSummary.metricTrends.first { $0.metricName.normalizedKey == metricName.normalizedKey }
                let partial = trend?.excludedPeriods?.contains { $0.label.normalizedKey == column.normalizedKey } ?? false
                return TableSeriesPoint(label: column, value: parseNumber(raw), rawValue: raw, isPartial: partial)
            }
            return TableMetricSeries(metricName: metricName, points: points)
        }
    }

    private static func longPeriodMetricSeries(for report: ImportedReport, rows: [[String: String]]) -> [TableMetricSeries]? {
        guard report.headers.count >= 3 else { return nil }
        let periodHeader = report.headers
            .map { header -> (header: String, score: Int) in
                let sample = rows.prefix(80).map { $0[header] ?? "" }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                let parsed = sample.filter { DateParsing.periodRange($0) != nil }.count
                var score = parsed
                let key = header.normalizedKey
                if key.contains("周期") || key.contains("period") || key.contains("week") || key.contains("semana") { score += 4 }
                return (header, score)
            }
            .filter { $0.score >= 3 }
            .sorted { $0.score > $1.score }
            .first?.header
        guard let periodHeader else { return nil }

        let metricHeader = report.headers.first { header in
            guard header != periodHeader else { return false }
            let key = header.normalizedKey
            let values = rows.prefix(120).map { ($0[header] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let numericCount = values.filter { parseNumber($0) != nil }.count
            return key.contains("指标") || key == "metric" || key.contains("metric_name") || numericCount < max(1, values.count / 3)
        }
        guard let metricHeader else { return nil }
        let measureHeaders = report.headers.filter { header in
            guard header != periodHeader, header != metricHeader else { return false }
            let values = rows.prefix(120).map { ($0[header] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard values.count >= 2 else { return false }
            let numericCount = values.filter { parseNumber($0) != nil }.count
            return numericCount >= max(2, values.count / 2)
        }
        guard !measureHeaders.isEmpty else { return nil }

        var grouped: [String: [(label: String, endDate: Date, rawValue: String, value: Double?)]] = [:]
        for row in rows {
            guard let metricName = row[metricHeader]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank else { continue }
            let periodLabel = row[periodHeader]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let range = DateParsing.periodRange(periodLabel) else { continue }
            for measureHeader in measureHeaders {
                let raw = row[measureHeader]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let seriesName = "\(metricName) / \(measureHeader)"
                grouped[seriesName, default: []].append((periodLabel, range.end, raw, parseNumber(raw)))
            }
        }
        guard !grouped.isEmpty else { return nil }
        return grouped.keys.sorted().compactMap { name in
            let points = (grouped[name] ?? [])
                .sorted {
                    if $0.endDate == $1.endDate { return $0.label < $1.label }
                    return $0.endDate < $1.endDate
                }
                .map { TableSeriesPoint(label: $0.label, value: $0.value, rawValue: $0.rawValue, isPartial: false) }
            guard points.count >= 2 else { return nil }
            return TableMetricSeries(metricName: name, points: points)
        }
    }

    private static func representativeSamples(from rows: [[String: String]]) -> [[String: String]] {
        guard rows.count > 120 else { return rows }
        let head = rows.prefix(40)
        let midStart = max(0, rows.count / 2 - 20)
        let middle = rows.dropFirst(midStart).prefix(40)
        let tail = rows.suffix(40)
        return Array(head) + Array(middle) + Array(tail)
    }

    private static func aggregateSummaries(for report: ImportedReport, rows: [[String: String]]) -> [String] {
        if !report.trendSummary.trendBullets.isEmpty {
            return Array(report.trendSummary.trendBullets.prefix(40))
        }
        let numericProfiles = report.headers.compactMap { header -> String? in
            let values = rows.compactMap { parseNumber($0[header] ?? "") }
            guard values.count >= 2 else { return nil }
            let minValue = values.min() ?? 0
            let maxValue = values.max() ?? 0
            let avg = values.reduce(0, +) / Double(values.count)
            return "\(header)：数值 \(values.count) 个，最小 \(minValue.compactText)，最大 \(maxValue.compactText)，均值 \(avg.compactText)"
        }
        return Array(numericProfiles.prefix(40))
    }

    private static func limitations(
        for report: ImportedReport,
        rows: [[String: String]],
        rawMatrix: RawTableMatrixContext,
        sendFullRows: Bool
    ) -> [String] {
        var result = report.parseWarnings
        if report.rowCount > rows.count {
            result.append("workspace 只保存了 \(rows.count)/\(report.rowCount) 行；AI 不能对未保存行直接下结论。")
        }
        if !sendFullRows {
            result.append("首轮未发送全部明细行；需要通过 dataRequests 补充后才能做细分结论。")
        }
        if rawMatrix.mode != "full_raw_matrix" {
            result.append("原始二维表首轮仅发送预览；AI 需要用 getRawRange 分块读取后再做未覆盖区域结论。")
        }
        if report.trendSummary.metricTrends.contains(where: { $0.latestPointIsPartial == true }) {
            result.append("存在候选成熟口径提示；本地不预先排除周期，AI 必须结合用户说明和原始表判断。")
        }
        return result.uniqued()
    }

    private static func maxColumnCount(_ rawRows: [[String]]) -> Int {
        rawRows.map(\.count).max() ?? 0
    }

    private static func rawRange(from target: String, rowCount: Int, columnCount: Int) -> (rowStart: Int, rowEnd: Int, colStart: Int, colEnd: Int) {
        let lower = target.lowercased()
        let rowStart = labeledInteger(in: lower, labels: ["rowstart", "row_start", "startrow", "start_row", "rs", "行起", "起始行"])
        let rowEnd = labeledInteger(in: lower, labels: ["rowend", "row_end", "endrow", "end_row", "re", "行止", "结束行"])
        let colStart = labeledInteger(in: lower, labels: ["colstart", "col_start", "startcol", "start_col", "cs", "列起", "起始列"])
        let colEnd = labeledInteger(in: lower, labels: ["colend", "col_end", "endcol", "end_col", "ce", "列止", "结束列"])
        if let rowStart, let rowEnd {
            return normalizeRange(
                rowStart: clamp(rowStart, lower: 1, upper: rowCount),
                rowEnd: clamp(rowEnd, lower: 1, upper: rowCount),
                colStart: clamp(colStart ?? 1, lower: 1, upper: max(1, columnCount)),
                colEnd: clamp(colEnd ?? columnCount, lower: 1, upper: max(1, columnCount))
            )
        }

        let numbers = integers(in: target)
        if numbers.count >= 4 {
            return normalizeRange(
                rowStart: clamp(numbers[0], lower: 1, upper: rowCount),
                rowEnd: clamp(numbers[1], lower: 1, upper: rowCount),
                colStart: clamp(numbers[2], lower: 1, upper: max(1, columnCount)),
                colEnd: clamp(numbers[3], lower: 1, upper: max(1, columnCount))
            )
        }
        if numbers.count >= 2 {
            return normalizeRange(
                rowStart: clamp(numbers[0], lower: 1, upper: rowCount),
                rowEnd: clamp(numbers[1], lower: 1, upper: rowCount),
                colStart: 1,
                colEnd: max(1, columnCount)
            )
        }
        return normalizeRange(rowStart: 1, rowEnd: min(rowCount, 120), colStart: 1, colEnd: max(1, min(columnCount, 40)))
    }

    private static func labeledInteger(in text: String, labels: [String]) -> Int? {
        for label in labels {
            let escaped = NSRegularExpression.escapedPattern(for: label)
            let pattern = "\(escaped)\\s*[:=：]\\s*(\\d+)"
            if let match = text.range(of: pattern, options: .regularExpression) {
                let segment = String(text[match])
                if let number = integers(in: segment).last {
                    return number
                }
            }
        }
        return nil
    }

    private static func integers(in text: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: #"\d+"#) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let valueRange = Range(match.range, in: text) else { return nil }
            return Int(text[valueRange])
        }
    }

    private static func slice(
        rawRows: [[String]],
        rowStart: Int,
        rowEnd: Int,
        colStart: Int,
        colEnd: Int
    ) -> [[String]] {
        guard !rawRows.isEmpty else { return [] }
        let startRowIndex = max(0, min(rowStart, rowEnd) - 1)
        let endRowIndex = min(rawRows.count - 1, max(rowStart, rowEnd) - 1)
        guard startRowIndex <= endRowIndex else { return [] }
        let startColumnIndex = max(0, min(colStart, colEnd) - 1)
        let endColumnIndex = max(0, max(colStart, colEnd) - 1)
        return rawRows[startRowIndex...endRowIndex].map { row in
            guard !row.isEmpty, startColumnIndex < row.count else { return [] }
            let safeEnd = min(row.count - 1, endColumnIndex)
            return Array(row[startColumnIndex...safeEnd])
        }
    }

    private static func renderRawRows(_ rows: [[String]], rowOffset: Int, colOffset: Int) -> String {
        let header = rows.first?.indices.map { "C\($0 + colOffset)" }.joined(separator: "\t") ?? ""
        var lines = ["row\\col\t" + header]
        for (index, row) in rows.enumerated() {
            let values = row.map { $0.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ") }
            lines.append("R\(index + rowOffset)\t" + values.joined(separator: "\t"))
        }
        return lines.joined(separator: "\n")
    }

    private static func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
        min(max(value, lower), max(lower, upper))
    }

    private static func normalizeRange(
        rowStart: Int,
        rowEnd: Int,
        colStart: Int,
        colEnd: Int
    ) -> (rowStart: Int, rowEnd: Int, colStart: Int, colEnd: Int) {
        (
            min(rowStart, rowEnd),
            max(rowStart, rowEnd),
            min(colStart, colEnd),
            max(colStart, colEnd)
        )
    }

    private static func parseNumber(_ raw: String) -> Double? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var multiplier = 1.0
        if text.hasSuffix("%") {
            multiplier = 0.01
            text.removeLast()
        }
        text = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: " ", with: "")
        return Double(text).map { $0 * multiplier }
    }

    private static func clipped(_ value: String, to limit: Int) -> String {
        value.count > limit ? String(value.prefix(limit)) : value
    }
}
