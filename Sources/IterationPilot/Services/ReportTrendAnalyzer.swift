import Foundation

enum ReportTrendAnalyzer {
    static let currentAnalysisVersion = 4
    private static let stableTrendPointThreshold = 4
    private static let preferredTrendPointThreshold = 6
    private static let maxStoredTrendBullets = 160
    private static let maxStoredMetricTrends = 240
    private static let maxStoredDistributionBullets = 24
    private static let maxCombinedTrendBullets = 140
    private static let maxTrendBulletsPerReport = 80

    static func analyze(
        fileName: String,
        kind: ImportedReportKind,
        table: CSVTable,
        timeAxisProfile: ReportTimeAxisProfile? = nil
    ) -> ReportTrendSummary {
        let detectedProfile = timeAxisProfile ?? ReportTimeAxisDetector.detect(table: table)
        let trendResult: (bullets: [String], metrics: [ReportMetricTrend], distributions: [String], warnings: [String]) = switch table.shape {
        case .pivotWide:
            analyzeLongPeriodMetricTable(table, timeAxisProfile: detectedProfile) ?? analyzePivotWide(table)
        case .detail, .unknown:
            analyzeDetail(table, timeAxisProfile: detectedProfile)
        }

        let overview = "已完成「\(fileName)」的表格趋势扫描：\(table.shape.label)，\(table.rows.count) 行、\(table.headers.count) 列，识别为\(kind.label)。以下只描述数据走势和分布，不做原因判断。"
        return ReportTrendSummary(
            analysisVersion: currentAnalysisVersion,
            generatedAt: Date(),
            overview: overview,
            trendBullets: trendResult.bullets,
            distributionBullets: trendResult.distributions,
            warnings: trendResult.warnings,
            metricTrends: trendResult.metrics
        )
    }

    static func analyze(report: ImportedReport) -> ReportTrendSummary {
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
        return analyze(fileName: report.fileName, kind: report.kind, table: table, timeAxisProfile: report.timeAxisProfile)
    }

    static func combinedTrendOverview(for reports: [ImportedReport]) -> String {
        let reportsWithTrend = reports.filter { !$0.trendSummary.isEmpty }
        guard !reportsWithTrend.isEmpty else {
            return "暂未生成报表趋势摘要。"
        }
        let metricCount = reportsWithTrend.reduce(0) { $0 + $1.trendSummary.metricTrends.count }
        let partialCount = reportsWithTrend.reduce(0) { total, report in
            total + report.trendSummary.metricTrends.filter { $0.latestPointIsPartial == true }.count
        }
        let completeCounts = reportsWithTrend
            .flatMap(\.trendSummary.metricTrends)
            .map { $0.completePointCount ?? $0.pointCount }
        let windowText = observationWindowOverview(from: completeCounts)
        let shortWindowCount = completeCounts.filter { $0 < stableTrendPointThreshold }.count
        let partialText = partialCount > 0 ? "，其中 \(partialCount) 个指标存在候选成熟口径提示，本地未据此排除周期" : ""
        let shortText = shortWindowCount > 0 ? "；\(shortWindowCount) 个指标完整观察点少于 \(stableTrendPointThreshold) 个，只能作为低置信方向观察" : ""
        return "本次共参考 \(reportsWithTrend.count) 张报表，汇总 \(metricCount) 个数值趋势点\(windowText)\(partialText)\(shortText)。以下先逐表覆盖数据走势，再结合业务链路和上下文做分析，不直接跳到产品结论。"
    }

    static func combinedTrendBullets(for reports: [ImportedReport]) -> [String] {
        let reportsWithTrend = reports.filter { !$0.trendSummary.isEmpty }
        guard !reportsWithTrend.isEmpty else { return [] }

        var bullets: [String] = []
        if reportsWithTrend.count > 1 {
            bullets.append("多表合并观察：\(reportsWithTrend.map(\.fileName).joined(separator: "、")) 已纳入同一轮趋势扫描。")
        }

        let namedTrends: [(reportName: String, trend: ReportMetricTrend)] = reportsWithTrend.flatMap { report in
            report.trendSummary.metricTrends.map { (report.displayName, $0) }
        }
        let trendCount = namedTrends.count
        if trendCount > 0 {
            bullets.append("趋势覆盖：本次识别 \(trendCount) 个指标趋势，按报表逐项列出；只有超过 \(maxCombinedTrendBullets) 条时才会截断展示。")
        }
        let shortWindowTrends = namedTrends.filter { ($0.trend.completePointCount ?? $0.trend.pointCount) < stableTrendPointThreshold }
        if !shortWindowTrends.isEmpty {
            let examples = shortWindowTrends.prefix(8).map {
                "\($0.trend.metricName)（\($0.trend.completePointCount ?? $0.trend.pointCount) 个完整点）"
            }.joined(separator: "、")
            bullets.append("时间范围不足：\(shortWindowTrends.count) 个指标完整观察点少于 \(stableTrendPointThreshold) 个，只能看方向，不能当作稳定趋势；包括 \(examples)。")
        } else {
            let limitedWindowTrends = namedTrends.filter {
                let count = $0.trend.completePointCount ?? $0.trend.pointCount
                return count < preferredTrendPointThreshold
            }
            if !limitedWindowTrends.isEmpty {
                let examples = limitedWindowTrends.prefix(8).map {
                    "\($0.trend.metricName)（\($0.trend.completePointCount ?? $0.trend.pointCount) 个完整点）"
                }.joined(separator: "、")
                bullets.append("观察周期偏短：\(limitedWindowTrends.count) 个指标完整观察点少于 \(preferredTrendPointThreshold) 个，适合看阶段方向，不适合直接判断长期稳定性；包括 \(examples)。")
            }
        }

        let partialTrends: [(reportName: String, trend: ReportMetricTrend)] = reportsWithTrend.flatMap { report in
            report.trendSummary.metricTrends
                .filter { $0.latestPointIsPartial == true }
                .map { (report.displayName, $0) }
        }
        if !partialTrends.isEmpty {
            let examples = partialTrends.prefix(8).map { item in
                let label = item.trend.partialLatestLabel ?? "最新周期"
                let reason = item.trend.partialLatestPointReason ?? "未完整"
                return "\(item.trend.metricName)（\(label)：\(reason)）"
            }.joined(separator: "、")
            bullets.append("候选成熟口径提示：\(partialTrends.count) 个指标的最新周期可能存在滞后口径；本地不预先排除周期，需由 AI 结合用户说明和原始表判断，包括 \(examples)。")
        }

        let grouped = Dictionary(grouping: namedTrends, by: { $0.trend.metricName.normalizedKey })
        for group in grouped.values
            .filter({ $0.count >= 2 })
            .sorted(by: { $0.count > $1.count })
            .prefix(6) {
            guard let metricName = group.first?.trend.metricName else { continue }
            let upCount = group.filter { $0.trend.direction == .up }.count
            let downCount = group.filter { $0.trend.direction == .down }.count
            let flatCount = group.count - upCount - downCount
            let reports = group.map(\.reportName).uniqued().joined(separator: "、")
            bullets.append("\(metricName)：在 \(group.count) 个趋势片段中，上升 \(upCount) 个、下降 \(downCount) 个、平稳 \(flatCount) 个；涉及 \(reports)。")
        }

        for report in reportsWithTrend {
            let displayName = report.displayName
            if !report.trendSummary.warnings.isEmpty {
                for warning in report.trendSummary.warnings.prefix(4) {
                    bullets.append("\(displayName)：\(warning)")
                }
            }
            for distribution in report.trendSummary.distributionBullets.prefix(4) {
                bullets.append("\(displayName)：\(distribution)")
            }
            bullets.append("\(displayName)：逐表趋势覆盖 \(report.trendSummary.metricTrends.count) 个指标；首列指标 \(report.firstColumnValues.count) 个，趋势判断优先使用完整时间周期。")
            for trend in report.trendSummary.trendBullets.prefix(maxTrendBulletsPerReport) {
                bullets.append("\(displayName)：\(trend)")
            }
            if report.trendSummary.trendBullets.count > maxTrendBulletsPerReport {
                bullets.append("\(displayName)：还有 \(report.trendSummary.trendBullets.count - maxTrendBulletsPerReport) 条趋势已识别但未在当前摘要展开，可在报表详情中继续查看。")
            }
        }
        return Array(bullets.uniqued().prefix(maxCombinedTrendBullets))
    }

    private static func analyzePivotWide(_ table: CSVTable) -> (bullets: [String], metrics: [ReportMetricTrend], distributions: [String], warnings: [String]) {
        guard let metricHeader = table.headers.first else {
            return ([], [], [], ["透视宽表没有可识别的首列指标。"])
        }

        var bullets: [String] = []
        var trends: [ReportMetricTrend] = []
        var distributions: [String] = []
        var warnings: [String] = []
        let axis = horizontalAxis(from: Array(table.headers.dropFirst()))
        if let note = axis.note {
            distributions.append(note)
        }
        if !axis.isTemporal {
            warnings.append("未识别横向时间轴，当前只做横向分组对比，不判断严格的时间趋势方向。")
        } else if axis.columns.count < stableTrendPointThreshold {
            warnings.append("横向时间轴只有 \(axis.columns.count) 个时间点，时间范围不足，只能作为低置信方向观察。")
        } else if axis.columns.count < preferredTrendPointThreshold {
            distributions.append("横向时间轴只有 \(axis.columns.count) 个时间点，适合判断阶段方向，不足以判断长期稳定趋势。")
        }
        if let partialNote = axis.partialLatestPeriodNote {
            distributions.append(partialNote)
        }

        for row in table.rows.prefix(80) {
            guard let metricName = row[metricHeader]?.nilIfBlank else { continue }
            let rawPoints: [(column: HorizontalColumn, point: NumericPoint)] = axis.columns.compactMap { column -> (HorizontalColumn, NumericPoint)? in
                let header = column.header
                guard let value = row[header] else { return nil }
                guard let point = parseNumericPoint(value) else { return nil }
                return (column, point)
            }
            let points = rawPoints.map(\.point.value)
            guard points.count >= 2 else { continue }
            let unit = dominantUnit(in: rawPoints.map(\.point), metricName: metricName)
            if !axis.isTemporal {
                let minValue = points.min() ?? 0
                let maxValue = points.max() ?? 0
                bullets.append("\(metricName)：横向 \(points.count) 个分组，最小 \(formatValue(minValue, unit: unit))、最大 \(formatValue(maxValue, unit: unit))、均值 \(formatValue(average(points), unit: unit))。")
                continue
            }

            let maturityHint = latestPartialMaturity(metricName: metricName, points: rawPoints)
            if let maturityHint {
                warnings.append("\(metricName)：候选成熟口径提示：\(maturityHint.reason)。本地不再据此排除最新周期，AI 必须结合用户说明和原始表确认。")
            }

            let trend = makeMetricTrend(
                metricName: metricName,
                values: points,
                partialLatest: nil,
                trendColumns: rawPoints.map(\.column),
                excludedPeriods: []
            )
            trends.append(trend)
            let qualifier = observationQualifier(for: points.count)
            let adjacentComparison = primaryComparisonText(for: trend, unit: unit)
            let maturityText = maturityHint.map { "；候选成熟口径提示：\($0.reason)，本地未排除该周期" } ?? ""
            bullets.append("\(metricName)：\(adjacentComparison)\(qualifier)历史验证为\(trend.historicalPattern ?? "未判断")，按时间从早到晚观察 \(points.count) 个周期，\(formatValue(trend.firstValue, unit: unit)) -> \(formatValue(trend.lastValue, unit: unit))，\(trend.direction.rawValue) \(formatDelta(trend, unit: unit))，区间最小 \(formatValue(points.min() ?? 0, unit: unit))、最大 \(formatValue(points.max() ?? 0, unit: unit))\(maturityText)。")
        }

        if bullets.isEmpty {
            warnings.append("未在透视宽表横向单元格中识别到足够的连续数值。")
        }
        return (
            Array(bullets.prefix(maxStoredTrendBullets)),
            Array(trends.prefix(maxStoredMetricTrends)),
            Array(distributions.prefix(maxStoredDistributionBullets)),
            warnings.uniqued()
        )
    }

    private struct HorizontalColumn {
        var header: String
        var temporalRank: Double?
        var startDate: Date?
        var endDate: Date?
        var originalIndex: Int
    }

    private struct HorizontalAxis {
        var columns: [HorizontalColumn]
        var isTemporal: Bool
        var note: String?
        var partialLatestPeriodNote: String?
    }

    private struct LatestPartialMaturity {
        var latestColumn: HorizontalColumn
        var latestPoint: (column: HorizontalColumn, point: NumericPoint)
        var completePoints: [(column: HorizontalColumn, point: NumericPoint)]
        var reason: String
    }

    private static func horizontalAxis(from headers: [String]) -> HorizontalAxis {
        let columns = headers.enumerated().map { index, header in
            let temporalInfo = horizontalTemporalInfo(for: header)
            return HorizontalColumn(
                header: header,
                temporalRank: temporalInfo?.rank ?? relativeTemporalRank(for: header),
                startDate: temporalInfo?.startDate,
                endDate: temporalInfo?.endDate,
                originalIndex: index
            )
        }
        let rankedColumns = columns.filter { $0.temporalRank != nil }
        guard rankedColumns.count >= 2 else {
            return HorizontalAxis(columns: columns, isTemporal: false, note: nil, partialLatestPeriodNote: nil)
        }

        let sorted = rankedColumns.sorted {
            guard let lhs = $0.temporalRank, let rhs = $1.temporalRank else {
                return $0.originalIndex < $1.originalIndex
            }
            if lhs == rhs { return $0.originalIndex < $1.originalIndex }
            return lhs < rhs
        }
        let note = horizontalAxisNote(originalColumns: rankedColumns, sortedColumns: sorted, ignoredCount: columns.count - rankedColumns.count)
        return HorizontalAxis(
            columns: sorted,
            isTemporal: true,
            note: note,
            partialLatestPeriodNote: partialLatestPeriodNote(sortedColumns: sorted)
        )
    }

    private static func horizontalAxisNote(originalColumns: [HorizontalColumn], sortedColumns: [HorizontalColumn], ignoredCount: Int) -> String {
        let originalRanks = originalColumns.compactMap(\.temporalRank)
        let ascending = zip(originalRanks, originalRanks.dropFirst()).allSatisfy { $0 <= $1 }
        let descending = zip(originalRanks, originalRanks.dropFirst()).allSatisfy { $0 >= $1 }
        let orderText: String
        if ascending {
            orderText = "原始列顺序已是从早到晚"
        } else if descending {
            orderText = "原始列顺序为最近在前，已按时间从早到晚重排"
        } else {
            orderText = "原始列时间顺序不连续，已按时间从早到晚重排"
        }
        let ignoredText = ignoredCount > 0 ? "；另有 \(ignoredCount) 列未识别为时间列，未用于周期候选画像" : ""
        return "横向时间轴识别：\(sortedColumns.first?.header ?? "-") -> \(sortedColumns.last?.header ?? "-")；\(orderText)\(ignoredText)。"
    }

    private static func partialLatestPeriodNote(sortedColumns: [HorizontalColumn], now: Date = Date()) -> String? {
        guard let latest = sortedColumns.last,
              let latestEnd = latest.endDate else { return nil }
        let calendar = Calendar.current
        if latestEnd >= calendar.startOfDay(for: now) {
            return "最新时间区间 \(latest.header) 尚未结束，涉及该列的趋势方向会被标记为未完整周期。"
        }

        let laggedMetricHints = ["3日", "7日", "14日", "30日", "注册后", "授信后", "消费后", "3d", "7d", "14d", "30d"]
        return "最新时间区间 \(latest.header) 已识别为最近周期；含 \(laggedMetricHints.prefix(5).joined(separator: "/")) 等滞后窗口的指标只作为候选口径提示，不由本地预先排除。"
    }

    private static func latestPartialMaturity(
        metricName: String,
        points: [(column: HorizontalColumn, point: NumericPoint)],
        now: Date = Date()
    ) -> LatestPartialMaturity? {
        guard let latestPoint = points.last,
              let latestEndDate = latestPoint.column.endDate else { return nil }
        let calendar = Calendar.current
        let lagDays = maturityLagDays(for: metricName)
        let requiredCompleteDate = calendar.date(byAdding: .day, value: max(lagDays, 0), to: latestEndDate) ?? latestEndDate
        let today = calendar.startOfDay(for: now)
        guard latestEndDate >= today || requiredCompleteDate > today else { return nil }

        let completePoints = points.dropLast().filter { point in
            guard let endDate = point.column.endDate else { return true }
            let completeDate = calendar.date(byAdding: .day, value: max(lagDays, 0), to: endDate) ?? endDate
            return completeDate <= today
        }
        let reason: String
        if latestEndDate >= today {
            reason = "所在时间区间尚未完整结束"
        } else if lagDays > 0 {
            reason = "属于 \(lagDays) 日成熟窗口，需等到 \(DateFormatting.shortDate.string(from: requiredCompleteDate)) 后才完整"
        } else {
            reason = "最新时间区间可能未完整"
        }
        return LatestPartialMaturity(
            latestColumn: latestPoint.column,
            latestPoint: latestPoint,
            completePoints: Array(completePoints),
            reason: reason
        )
    }

    private static func maturityLagDays(for metricName: String) -> Int {
        let normalized = metricName.normalizedKey
        let matches = regexMatches(pattern: #"(\d{1,2})\s*(日|天|d|day|days)"#, in: normalized)
        let parsedDays = matches.compactMap { match -> Int? in
            let digits = match.filter(\.isNumber)
            return Int(String(digits))
        }
        if let maxDay = parsedDays.max() {
            return maxDay
        }
        if normalized.contains("注册后") || normalized.contains("授信后") || normalized.contains("消费后") {
            return 7
        }
        if normalized.contains("当日") || normalized.contains("same_day") {
            return 0
        }
        return 0
    }

    private struct HorizontalTemporalInfo {
        var startDate: Date
        var endDate: Date
        var rank: Double
    }

    private static func horizontalTemporalInfo(for header: String) -> HorizontalTemporalInfo? {
        let normalized = header
            .replacingOccurrences(of: "年", with: "/")
            .replacingOccurrences(of: "月", with: "/")
            .replacingOccurrences(of: "日", with: "")
        if let range = DateParsing.periodRange(normalized) {
            return HorizontalTemporalInfo(startDate: range.start, endDate: range.end, rank: range.end.timeIntervalSince1970)
        }
        let matches = regexMatches(
            pattern: #"\d{4}[-/.]\d{1,2}[-/.]\d{1,2}"#,
            in: normalized
        )
        let dates = matches.compactMap { DateParsing.parse($0.replacingOccurrences(of: ".", with: "/")) }
        if let first = dates.first, let last = dates.last {
            let start = min(first, last)
            let end = max(first, last)
            return HorizontalTemporalInfo(startDate: start, endDate: end, rank: end.timeIntervalSince1970)
        }
        if let date = DateParsing.parse(normalized) {
            return HorizontalTemporalInfo(startDate: date, endDate: date, rank: date.timeIntervalSince1970)
        }
        return nil
    }

    private static func relativeTemporalRank(for header: String) -> Double? {
        let value = header.normalizedKey
        if value.contains("上上周") || value.contains("前两周") || value.contains("上上期") { return 10 }
        if value.contains("上周") || value.contains("上一周") || value.contains("上期") || value.contains("上一期") { return 20 }
        if value.contains("本周") || value.contains("本期") || value.contains("当前") || value.contains("最近") { return 30 }
        if value.contains("上上月") || value.contains("前两月") { return 110 }
        if value.contains("上月") || value.contains("上一月") { return 120 }
        if value.contains("本月") || value.contains("当月") { return 130 }
        return nil
    }

    private static func regexMatches(pattern: String, in value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = value as NSString
        return regex.matches(in: value, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range)
        }
    }

    private static func analyzeDetail(_ table: CSVTable, timeAxisProfile: ReportTimeAxisProfile?) -> (bullets: [String], metrics: [ReportMetricTrend], distributions: [String], warnings: [String]) {
        guard !table.headers.isEmpty else {
            return ([], [], [], ["明细表没有可识别字段。"])
        }

        let detectedProfile = timeAxisProfile ?? ReportTimeAxisDetector.detect(table: table)
        if let longTable = analyzeLongPeriodMetricTable(table, timeAxisProfile: detectedProfile) {
            return longTable
        }
        let dateHeader = detectedProfile.userConfirmed ? detectedProfile.primaryDateColumn : (detectedProfile.primaryDateColumn ?? bestDateHeader(in: table))
        let rows = sortedRows(table.rows, by: dateHeader)
        var bullets: [String] = []
        var trends: [ReportMetricTrend] = []
        var distributions: [String] = []
        var warnings: [String] = detectedProfile.warnings
        if detectedProfile.candidateDateColumns.count > 1, !detectedProfile.userConfirmed {
            warnings.append("明细表存在多个竖向日期列候选，当前趋势按「\(dateHeader ?? "未确认")」低置信观察；AI 可要求用户确认主时间口径。")
        }

        for header in table.headers.prefix(120) {
            let rawRows = rows.compactMap { row -> (point: NumericPoint, date: Date?)? in
                guard let point = parseNumericPoint(row[header] ?? "") else { return nil }
                let date = dateHeader.flatMap { parseDateOrPeriodEnd(row[$0] ?? "") }
                return (point, date)
            }
            let rawPoints = rawRows.map(\.point)
            let values = rawPoints.map(\.value)
            guard values.count >= 2 else { continue }
            let unit = dominantUnit(in: rawPoints, metricName: header)
            if dateHeader == nil {
                let minValue = values.min() ?? 0
                let maxValue = values.max() ?? 0
                distributions.append("\(header)：未识别时间字段，按全表数值分布观察，最小 \(formatValue(minValue, unit: unit))、最大 \(formatValue(maxValue, unit: unit))、均值 \(formatValue(average(values), unit: unit))。")
                continue
            }
            let datedRows = rawRows.compactMap(\.date)
            let trend = makeMetricTrend(
                metricName: header,
                values: values,
                trendStartDate: datedRows.first,
                trendEndDate: datedRows.last,
                trendStartLabel: datedRows.first.map { DateFormatting.shortDate.string(from: $0) },
                trendEndLabel: datedRows.last.map { DateFormatting.shortDate.string(from: $0) }
            )
            trends.append(trend)
            let qualifier = observationQualifier(for: values.count)
            let mainComparison = primaryComparisonText(for: trend, unit: unit)
            bullets.append("\(header)：\(mainComparison)\(qualifier)历史验证为\(trend.historicalPattern ?? "未判断")，按 \(dateHeader ?? "") 从早到晚观察 \(values.count) 个数值，\(formatValue(trend.firstValue, unit: unit)) -> \(formatValue(trend.lastValue, unit: unit))，\(trend.direction.rawValue) \(formatDelta(trend, unit: unit))，均值 \(formatValue(average(values), unit: unit))。")
        }

        distributions.append(contentsOf: distributionBullets(table: table, rows: rows, excluding: Set(([dateHeader] + trends.map(\.metricName)).compactMap { $0 })))
        if dateHeader == nil {
            warnings.append("未识别明细表时间字段，未按行序推断趋势方向。")
        }
        if bullets.isEmpty && distributions.isEmpty {
            warnings.append("未在明细表中识别到足够的数值字段，当前只保留字段分布观察。")
        }
        return (
            Array(bullets.prefix(maxStoredTrendBullets)),
            Array(trends.prefix(maxStoredMetricTrends)),
            Array(distributions.prefix(maxStoredDistributionBullets)),
            warnings.uniqued()
        )
    }

    private static func bestDateHeader(in table: CSVTable) -> String? {
        let candidates = table.headers.map { header -> (header: String, score: Int) in
            let values = table.rows.prefix(40).compactMap { parseDateOrPeriodEnd($0[header] ?? "") }
            let headerScore = ["date", "day", "week", "month", "日期", "时间", "周", "月"].contains { header.normalizedKey.contains($0.normalizedKey) } ? 2 : 0
            return (header, values.count + headerScore)
        }
        return candidates
            .filter { $0.score >= 2 }
            .sorted { $0.score > $1.score }
            .first?.header
    }

    private static func sortedRows(_ rows: [[String: String]], by dateHeader: String?) -> [[String: String]] {
        guard let dateHeader else { return rows }
        return rows.sorted {
            let lhs = parseDateOrPeriodEnd($0[dateHeader] ?? "") ?? .distantPast
            let rhs = parseDateOrPeriodEnd($1[dateHeader] ?? "") ?? .distantPast
            return lhs < rhs
        }
    }

    private struct LongPeriodMetricTable {
        var periodHeader: String
        var metricHeader: String
        var measureHeaders: [String]
    }

    private struct LongPeriodPoint {
        var periodLabel: String
        var startDate: Date?
        var endDate: Date?
        var value: Double
        var unit: TrendValueUnit
    }

    private static func analyzeLongPeriodMetricTable(
        _ table: CSVTable,
        timeAxisProfile: ReportTimeAxisProfile
    ) -> (bullets: [String], metrics: [ReportMetricTrend], distributions: [String], warnings: [String])? {
        guard let structure = longPeriodMetricStructure(in: table) else { return nil }
        var grouped: [String: [LongPeriodPoint]] = [:]
        var unitsBySeries: [String: [NumericPoint]] = [:]

        for row in table.rows {
            guard let metricName = row[structure.metricHeader]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank else { continue }
            let periodText = row[structure.periodHeader]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let periodRange = DateParsing.periodRange(periodText) else { continue }
            for measureHeader in structure.measureHeaders {
                guard let point = parseNumericPoint(row[measureHeader] ?? "") else { continue }
                let seriesName = "\(metricName) / \(measureHeader)"
                grouped[seriesName, default: []].append(LongPeriodPoint(
                    periodLabel: periodText,
                    startDate: periodRange.start,
                    endDate: periodRange.end,
                    value: point.value,
                    unit: point.unit
                ))
                unitsBySeries[seriesName, default: []].append(point)
            }
        }

        guard !grouped.isEmpty else { return nil }
        var bullets: [String] = []
        var trends: [ReportMetricTrend] = []
        var warnings = timeAxisProfile.warnings
        warnings.append("识别到「\(structure.periodHeader) + \(structure.metricHeader) + 数值列」长表候选；本地仅按周期结束日排序生成候选趋势，AI 仍需确认统计周期和指标口径。")

        for seriesName in grouped.keys.sorted().prefix(maxStoredMetricTrends) {
            let points = (grouped[seriesName] ?? []).sorted {
                if ($0.endDate ?? .distantPast) == ($1.endDate ?? .distantPast) {
                    return $0.periodLabel < $1.periodLabel
                }
                return ($0.endDate ?? .distantPast) < ($1.endDate ?? .distantPast)
            }
            guard points.count >= 2 else { continue }
            let values = points.map(\.value)
            let labels = points.map(\.periodLabel)
            let unit = dominantUnit(in: unitsBySeries[seriesName] ?? [], metricName: seriesName)
            let trend = makeMetricTrend(
                metricName: seriesName,
                values: values,
                labels: labels,
                trendStartDate: points.first?.startDate ?? points.first?.endDate,
                trendEndDate: points.last?.endDate ?? points.last?.startDate,
                trendStartLabel: labels.first,
                trendEndLabel: labels.last
            )
            trends.append(trend)
            let qualifier = observationQualifier(for: values.count)
            let mainComparison = primaryComparisonText(for: trend, unit: unit)
            bullets.append("\(seriesName)：\(mainComparison)\(qualifier)历史验证为\(trend.historicalPattern ?? "未判断")，按 \(structure.periodHeader) 从早到晚观察 \(values.count) 个周期，\(formatValue(trend.firstValue, unit: unit)) -> \(formatValue(trend.lastValue, unit: unit))，\(trend.direction.rawValue) \(formatDelta(trend, unit: unit))。")
        }

        if trends.isEmpty {
            return nil
        }
        let distributions = [
            "长表周期候选：按「\(structure.periodHeader)」识别 \(Set(grouped.values.flatMap { $0.map(\.periodLabel) }).count) 个周期，按「\(structure.metricHeader)」和 \(structure.measureHeaders.count) 个数值列组合生成指标序列。"
        ]
        return (
            Array(bullets.prefix(maxStoredTrendBullets)),
            Array(trends.prefix(maxStoredMetricTrends)),
            distributions,
            warnings.uniqued()
        )
    }

    private static func longPeriodMetricStructure(in table: CSVTable) -> LongPeriodMetricTable? {
        guard table.headers.count >= 3 else { return nil }
        let periodCandidates = table.headers.compactMap { header -> (String, Int)? in
            let key = header.normalizedKey
            let sample = table.rows.prefix(80).map { $0[header] ?? "" }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let rangeCount = sample.filter { DateParsing.periodRange($0) != nil }.count
            var score = rangeCount
            if key.contains("周期") || key.contains("period") || key.contains("week") || key.contains("semana") { score += 4 }
            return score >= 3 ? (header, score) : nil
        }.sorted { $0.1 > $1.1 }
        guard let periodHeader = periodCandidates.first?.0 else { return nil }

        let metricCandidates = table.headers.filter { header in
            guard header != periodHeader else { return false }
            let key = header.normalizedKey
            let values = table.rows.prefix(120).map { ($0[header] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let numericCount = values.filter { parseNumericPoint($0) != nil }.count
            return key.contains("指标") || key == "metric" || key.contains("metric_name") || (numericCount < max(1, values.count / 3) && Set(values.map(\.normalizedKey)).count >= 2)
        }
        guard let metricHeader = metricCandidates.first else { return nil }

        let excluded = Set([periodHeader, metricHeader])
        let measureHeaders = table.headers.filter { header in
            guard !excluded.contains(header) else { return false }
            let values = table.rows.prefix(120).map { ($0[header] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard values.count >= 2 else { return false }
            let numericCount = values.filter { parseNumericPoint($0) != nil }.count
            return numericCount >= max(2, values.count / 2)
        }
        guard !measureHeaders.isEmpty else { return nil }
        return LongPeriodMetricTable(periodHeader: periodHeader, metricHeader: metricHeader, measureHeaders: measureHeaders)
    }

    private static func parseDateOrPeriodEnd(_ rawValue: String) -> Date? {
        DateParsing.periodRange(rawValue)?.end ?? DateParsing.parse(rawValue)
    }

    private static func distributionBullets(table: CSVTable, rows: [[String: String]], excluding excludedHeaders: Set<String>) -> [String] {
        table.headers
            .filter { !excludedHeaders.contains($0) }
            .prefix(80)
            .compactMap { header -> String? in
                let values = rows.compactMap { $0[header]?.nilIfBlank }
                guard values.count >= 2, values.count <= 200 else { return nil }
                let counts = Dictionary(grouping: values, by: { $0 }).mapValues(\.count)
                guard counts.count >= 2, counts.count <= 20 else { return nil }
                let top = counts.sorted { $0.value > $1.value }.prefix(3).map { "\($0.key) \($0.value)" }.joined(separator: "，")
                return "\(header)：共 \(counts.count) 个取值，Top 分布为 \(top)。"
            }
            .prefix(12)
            .map { $0 }
    }

    private static func observationWindowOverview(from counts: [Int]) -> String {
        guard !counts.isEmpty else { return "" }
        let sorted = counts.sorted()
        let minCount = sorted.first ?? 0
        let maxCount = sorted.last ?? 0
        let median = sorted[sorted.count / 2]
        return "；完整观察点范围 \(minCount)-\(maxCount) 个，中位数 \(median) 个"
    }

    private static func observationQualifier(for pointCount: Int) -> String {
        if pointCount < stableTrendPointThreshold {
            return "时间范围不足（完整观察点 \(pointCount) 个，仅低置信方向观察），"
        }
        if pointCount < preferredTrendPointThreshold {
            return "观察周期偏短（完整观察点 \(pointCount) 个，适合看阶段方向），"
        }
        return ""
    }

    private static func primaryComparison(
        values: [Double],
        labels: [String],
        confidence: Double,
        evidenceLevel: EvidenceLevel
    ) -> PrimaryMetricComparison? {
        guard values.count >= 2 else { return nil }
        let previous = values[values.count - 2]
        let current = values[values.count - 1]
        let delta = current - previous
        let percentChange = abs(previous) > 0.000_001 ? delta / abs(previous) : nil
        let direction: ChangeDirection
        if abs(delta) < max(0.000_001, abs(previous) * 0.01) {
            direction = .flat
        } else {
            direction = delta > 0 ? .up : .down
        }
        let previousLabel = labels.indices.contains(values.count - 2) ? labels[values.count - 2] : "上一相邻周期"
        let currentLabel = labels.indices.contains(values.count - 1) ? labels[values.count - 1] : "最新出现周期"
        let reason = values.count < stableTrendPointThreshold ? "观察点少于 \(stableTrendPointThreshold) 个，仅作为相邻周期候选观察，不能替代用户指定周期口径" : ""
        return PrimaryMetricComparison(
            previousLabel: previousLabel,
            currentLabel: currentLabel,
            previousValue: previous,
            currentValue: current,
            delta: delta,
            percentChange: percentChange,
            direction: direction,
            isComparable: true,
            incomparabilityReason: reason,
            confidence: confidence,
            evidenceLevel: evidenceLevel
        )
    }

    private static func makeMetricTrend(
        metricName: String,
        values: [Double],
        labels: [String],
        trendStartDate: Date?,
        trendEndDate: Date?,
        trendStartLabel: String?,
        trendEndLabel: String?
    ) -> ReportMetricTrend {
        let confidence = analysisConfidence(pointCount: values.count, partialLatest: nil)
        let evidence = trendEvidenceLevel(pointCount: values.count, partialLatest: nil)
        let first = values.first ?? 0
        let last = values.last ?? 0
        let delta = last - first
        let percentChange = abs(first) > 0.000_001 ? delta / abs(first) : nil
        let direction: ChangeDirection
        if abs(delta) < max(0.000_001, abs(first) * 0.01) {
            direction = .flat
        } else {
            direction = delta > 0 ? .up : .down
        }
        return ReportMetricTrend(
            metricName: metricName,
            firstValue: first,
            lastValue: last,
            delta: delta,
            percentChange: percentChange,
            direction: direction,
            pointCount: values.count,
            trendStartDate: trendStartDate,
            trendEndDate: trendEndDate,
            trendStartLabel: trendStartLabel,
            trendEndLabel: trendEndLabel,
            primaryComparison: primaryComparison(values: values, labels: labels, confidence: confidence, evidenceLevel: evidence),
            historicalPattern: historicalPattern(values: values, direction: direction),
            analysisConfidence: confidence,
            evidenceLevel: evidence
        )
    }

    private static func primaryComparisonText(for trend: ReportMetricTrend, unit: TrendValueUnit) -> String {
        guard let comparison = trend.primaryComparison else { return "相邻周期候选不足，" }
        let deltaText: String
        switch unit {
        case .number:
            deltaText = comparison.delta >= 0 ? "+\(comparison.delta.compactText)" : comparison.delta.compactText
        case .percent:
            deltaText = "\(comparison.delta >= 0 ? "+" : "")\(comparison.delta.compactText) 个百分点"
        }
        let percentText = comparison.percentChange.flatMap {
            DateFormatting.percent.string(from: NSNumber(value: $0))
        }
        let relativeText = percentText.map { "（\($0)）" } ?? ""
        let caveat = comparison.incomparabilityReason.isEmpty ? "" : "，\(comparison.incomparabilityReason)"
        return "相邻周期候选 \(comparison.currentLabel) vs \(comparison.previousLabel)：\(formatValue(comparison.previousValue, unit: unit)) -> \(formatValue(comparison.currentValue, unit: unit))，\(comparison.direction.rawValue) \(deltaText)\(relativeText)，证据\(comparison.evidenceLevel.rawValue)、置信度 \(Int(comparison.confidence * 100))%\(caveat)；"
    }

    private static func historicalPattern(values: [Double], direction: ChangeDirection) -> String {
        guard values.count >= stableTrendPointThreshold else { return "样本不足" }
        if direction == .flat { return "整体平稳" }
        let deltas = zip(values, values.dropFirst()).map { $1 - $0 }
        let positiveCount = deltas.filter { $0 > max(0.000_001, abs(values.first ?? 0) * 0.003) }.count
        let negativeCount = deltas.filter { $0 < -max(0.000_001, abs(values.first ?? 0) * 0.003) }.count
        if positiveCount > 0, negativeCount > 0 { return "阶段波动" }
        if direction == .up, positiveCount >= max(1, deltas.count - 1) { return "持续上升" }
        if direction == .down, negativeCount >= max(1, deltas.count - 1) { return "持续下降" }
        return direction == .up ? "阶段性上升" : "阶段性下降"
    }

    private static func analysisConfidence(pointCount: Int, partialLatest: LatestPartialMaturity?) -> Double {
        var confidence: Double
        if pointCount >= preferredTrendPointThreshold {
            confidence = 0.82
        } else if pointCount >= stableTrendPointThreshold {
            confidence = 0.68
        } else {
            confidence = 0.46
        }
        if partialLatest != nil {
            confidence -= 0.08
        }
        return min(0.92, max(0.2, confidence))
    }

    private static func trendEvidenceLevel(pointCount: Int, partialLatest: LatestPartialMaturity?) -> EvidenceLevel {
        if pointCount >= preferredTrendPointThreshold, partialLatest == nil { return .b }
        if pointCount >= stableTrendPointThreshold { return .c }
        return .d
    }

    private static func makeMetricTrend(
        metricName: String,
        values: [Double],
        partialLatest: LatestPartialMaturity? = nil,
        trendColumns: [HorizontalColumn]? = nil,
        trendStartDate: Date? = nil,
        trendEndDate: Date? = nil,
        trendStartLabel: String? = nil,
        trendEndLabel: String? = nil,
        excludedPeriods: [ExcludedTrendPeriod] = []
    ) -> ReportMetricTrend {
        let first = values.first ?? 0
        let last = values.last ?? 0
        let delta = last - first
        let percentChange = abs(first) > 0.000_001 ? delta / abs(first) : nil
        let direction: ChangeDirection
        if abs(delta) < max(0.000_001, abs(first) * 0.01) {
            direction = .flat
        } else {
            direction = delta > 0 ? .up : .down
        }
        let labels = trendColumns?.map(\.header) ?? []
        let confidence = analysisConfidence(pointCount: values.count, partialLatest: partialLatest)
        let evidence = trendEvidenceLevel(pointCount: values.count, partialLatest: partialLatest)
        return ReportMetricTrend(
            metricName: metricName,
            firstValue: first,
            lastValue: last,
            delta: delta,
            percentChange: percentChange,
            direction: direction,
            pointCount: values.count,
            trendStartDate: trendStartDate ?? trendColumns?.first?.startDate,
            trendEndDate: trendEndDate ?? trendColumns?.last?.endDate ?? trendColumns?.last?.startDate,
            trendStartLabel: trendStartLabel ?? trendColumns?.first?.header,
            trendEndLabel: trendEndLabel ?? trendColumns?.last?.header,
            latestPointIsPartial: partialLatest != nil ? true : nil,
            partialLatestPointReason: partialLatest?.reason,
            partialLatestValue: partialLatest?.latestPoint.point.value,
            partialLatestLabel: partialLatest?.latestColumn.header,
            completePointCount: partialLatest != nil ? values.count : nil,
            primaryComparison: primaryComparison(values: values, labels: labels, confidence: confidence, evidenceLevel: evidence),
            historicalPattern: historicalPattern(values: values, direction: direction),
            analysisConfidence: confidence,
            evidenceLevel: evidence,
            excludedPeriods: excludedPeriods.isEmpty ? nil : excludedPeriods
        )
    }

    private enum TrendValueUnit {
        case number
        case percent
    }

    private struct NumericPoint {
        var value: Double
        var unit: TrendValueUnit
    }

    private static func formatDelta(_ trend: ReportMetricTrend, unit: TrendValueUnit) -> String {
        let deltaText: String
        switch unit {
        case .number:
            deltaText = trend.delta >= 0 ? "+\(trend.delta.compactText)" : trend.delta.compactText
        case .percent:
            deltaText = "\(trend.delta >= 0 ? "+" : "")\(trend.delta.compactText) 个百分点"
        }
        guard let percent = trend.percentChange else { return deltaText }
        let percentText = DateFormatting.percent.string(from: NSNumber(value: percent)) ?? "\(percent)"
        return "\(deltaText)（\(percentText)）"
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func formatValue(_ value: Double, unit: TrendValueUnit) -> String {
        switch unit {
        case .number:
            return value.compactText
        case .percent:
            return "\(value.compactText)%"
        }
    }

    private static func dominantUnit(in points: [NumericPoint], metricName: String) -> TrendValueUnit {
        if points.filter({ $0.unit == .percent }).count >= max(1, points.count / 2) {
            return .percent
        }
        let normalized = metricName.normalizedKey
        if normalized.contains("率") || normalized.contains("ratio") || normalized.contains("rate") || normalized.contains("conversion") || metricName.contains("/") {
            return .percent
        }
        return .number
    }

    private static func parseNumericPoint(_ rawValue: String) -> NumericPoint? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let unit: TrendValueUnit = trimmed.contains("%") ? .percent : .number
        let cleaned = trimmed
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: " ", with: "")
        if cleaned.hasPrefix("("), cleaned.hasSuffix(")") {
            return Double("-" + cleaned.dropFirst().dropLast()).map { NumericPoint(value: $0, unit: unit) }
        }
        return Double(cleaned).map { NumericPoint(value: $0, unit: unit) }
    }
}
