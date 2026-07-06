import DuckDB
import Foundation

enum AnalysisSQLRuntime {
    private struct ReportTableMap {
        var reportID: UUID
        var reportName: String
        var rawTableName: String
        var headers: [String]
        var safeColumns: [String]
        var ingestedRows: Int
    }

    static func buildNotebookRun(
        userRequest: String,
        reports: [ImportedReport],
        workspace: ProductWorkspace,
        pack: DataPack,
        task: AnalysisTask?,
        sessionID: UUID?,
        messageID: UUID?,
        trigger: String,
        contextMode: AnalysisContextMode
    ) -> AnalysisNotebookRun {
        let startedAt = Date()
        let skillPlan = AnalysisSkillRouter.route(
            userRequest: userRequest,
            contextMode: contextMode,
            reports: reports
        )
        var cells: [AnalysisNotebookCell] = [
            AnalysisNotebookCell(
                kind: .markdown,
                title: "分析 Skill 路由",
                markdown: skillPlan.promptMarkdown
            )
        ]
        var warnings: [String] = []

        do {
            let database = try Database(store: .inMemory)
            let connection = try database.connect()
            try? connection.execute("SET threads TO 1")

            try connection.execute("""
            CREATE TABLE metric_period_values(
                source_report VARCHAR,
                source_report_id VARCHAR,
                source_order INTEGER,
                metric VARCHAR,
                metric_kind VARCHAR,
                period VARCHAR,
                raw_value VARCHAR,
                numeric_value DOUBLE
            )
            """)

            var tableMaps: [ReportTableMap] = []
            for (index, report) in reports.enumerated() {
                do {
                    let tableMap = try ingest(report: report, index: index, connection: connection)
                    tableMaps.append(tableMap)
                    try appendMetricPeriodValues(report: report, sourceOrder: index + 1, userRequest: userRequest, connection: connection)
                } catch {
                    warnings.append("\(report.displayName) 未能载入 SQL 临时库：\(error.localizedDescription)")
                }
            }

            cells.append(inventoryCell(tableMaps: tableMaps, reports: reports))
            cells.append(fieldMappingCell(tableMaps: tableMaps))
            cells.append(aggregationIntentCell(userRequest: userRequest, reports: reports))
            cells.append(contentsOf: executeAggregationAuditQueries(connection: connection, tableMaps: tableMaps))
            cells.append(executeRequestedPeriodComparisonCell(connection: connection, tableMaps: tableMaps, userRequest: userRequest))
            cells.append(derivedMetricAuditCell(reports: reports))
            cells.append(contentsOf: executeStandardQueries(connection: connection, tableMaps: tableMaps))
            cells.append(dateCandidateCell(reports: reports))

            if cells.count == 2 {
                warnings.append("未生成可执行 SQL 证据。可能是当前任务未选表，或报表没有可读取行。")
            }
        } catch {
            cells.append(AnalysisNotebookCell(
                kind: .sql,
                status: .failed,
                title: "初始化 DuckDB 计算引擎失败",
                markdown: "本轮仍可继续 AI 分析，但缺少本地 SQL 计算证据。",
                errorMessage: error.localizedDescription
            ))
        }

        let duration = Int(Date().timeIntervalSince(startedAt) * 1000)
        return AnalysisNotebookRun(
            businessSpaceID: task?.businessSpaceID ?? pack.businessSpaceID,
            packID: pack.id,
            taskID: task?.id,
            sessionID: sessionID,
            messageID: messageID,
            trigger: trigger,
            skillSummary: skillPlan.skills.map(\.label).joined(separator: "、"),
            cells: cells,
            warnings: warnings,
            createdAt: startedAt,
            durationMilliseconds: duration
        )
    }

    static func validateReadOnlySQL(_ sql: String) -> String? {
        let trimmed = sql
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard !trimmed.isEmpty else { return "SQL 为空。" }
        let normalized = trimmed.lowercased()
        guard normalized.hasPrefix("select ") || normalized.hasPrefix("with ") else {
            return "只允许 SELECT 或 WITH 只读查询。"
        }
        let forbidden = [
            "drop", "delete", "update", "insert", "attach", "copy", "install", "load",
            "read_csv", "read_parquet", "httpfs", "pragma", "create", "alter", "detach",
            "export", "import", "call", "set", "vacuum"
        ]
        let tokens = normalized
            .replacingOccurrences(of: #"[^a-z0-9_]+"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
        if let bad = forbidden.first(where: { tokens.contains($0) }) {
            return "SQL 包含禁止关键字：\(bad)。"
        }
        return nil
    }

    private static func ingest(report: ImportedReport, index: Int, connection: Connection) throws -> ReportTableMap {
        let rawTableName = "report_\(index + 1)_raw"
        let headers = report.headers.isEmpty ? inferredHeaders(for: report) : report.headers
        let safeColumns = headers.indices.map { "c_\($0 + 1)" }
        let columnSQL = safeColumns.map { "\(quoteIdentifier($0)) VARCHAR" }.joined(separator: ", ")
        let createSQL = """
        CREATE TABLE \(quoteIdentifier(rawTableName))(
            row_index BIGINT,
            \(columnSQL),
            source_report VARCHAR
        )
        """
        try connection.execute(createSQL)

        let rows = normalizedRows(for: report, headers: headers)
        let appender = try Appender(connection: connection, table: rawTableName)
        for (rowIndex, row) in rows.enumerated() {
            try appender.append(Int64(rowIndex + 1))
            for columnIndex in headers.indices {
                try appender.append(value(at: columnIndex, in: row))
            }
            try appender.append(report.displayName)
            try appender.endRow()
        }
        try appender.flush()

        return ReportTableMap(
            reportID: report.id,
            reportName: report.displayName,
            rawTableName: rawTableName,
            headers: headers,
            safeColumns: safeColumns,
            ingestedRows: rows.count
        )
    }

    private static func appendMetricPeriodValues(
        report: ImportedReport,
        sourceOrder: Int,
        userRequest: String,
        connection: Connection
    ) throws {
        let headers = report.headers.isEmpty ? inferredHeaders(for: report) : report.headers
        guard headers.count >= 2 else { return }
        let rows = normalizedRows(for: report, headers: headers)
        guard !rows.isEmpty else { return }

        if try appendLongMetricPeriodValues(
            report: report,
            headers: headers,
            rows: rows,
            sourceOrder: sourceOrder,
            userRequest: userRequest,
            connection: connection
        ) {
            return
        }

        let appender = try Appender(connection: connection, table: "metric_period_values")
        let metricColumnIndex = 0
        for row in rows {
            let metricName = value(at: metricColumnIndex, in: row)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !metricName.isEmpty else { continue }
            let metricKind = AggregationSemantics.classify(metricName: metricName).kind.label
            for columnIndex in headers.indices.dropFirst() {
                let period = headers[columnIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                let rawValue = value(at: columnIndex, in: row)
                try appender.append(report.displayName)
                try appender.append(report.id.uuidString)
                try appender.append(Int32(sourceOrder))
                try appender.append(metricName)
                try appender.append(metricKind)
                try appender.append(period)
                try appender.append(rawValue)
                try appender.append(parseNumeric(rawValue))
                try appender.endRow()
            }
        }
        try appender.flush()
    }

    private static func appendLongMetricPeriodValues(
        report: ImportedReport,
        headers: [String],
        rows: [[String]],
        sourceOrder: Int,
        userRequest: String,
        connection: Connection
    ) throws -> Bool {
        guard headers.count >= 3 else { return false }
        let sampleRows = Array(rows.prefix(160))
        guard let periodColumnIndex = bestPeriodColumnIndex(headers: headers, rows: sampleRows) else {
            return false
        }
        let metricColumnIndexes = bestMetricColumnIndexes(
            headers: headers,
            rows: sampleRows,
            excluding: periodColumnIndex,
            userRequest: userRequest
        )
        guard !metricColumnIndexes.isEmpty else { return false }

        let appender = try Appender(connection: connection, table: "metric_period_values")
        var appended = 0
        var insertedKeys = Set<String>()
        for metricColumnIndex in metricColumnIndexes.prefix(3) {
            let valueColumnIndexes = bestValueColumnIndexes(
                headers: headers,
                rows: sampleRows,
                excluding: Set([periodColumnIndex, metricColumnIndex])
            )
            guard !valueColumnIndexes.isEmpty else { continue }
            for row in rows {
                let baseMetricName = value(at: metricColumnIndex, in: row).trimmingCharacters(in: .whitespacesAndNewlines)
                let period = value(at: periodColumnIndex, in: row).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !baseMetricName.isEmpty, !period.isEmpty else { continue }
                for valueColumnIndex in valueColumnIndexes {
                    let rawValue = value(at: valueColumnIndex, in: row)
                    guard parseNumeric(rawValue) != nil else { continue }
                    let valueHeader = headers[valueColumnIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                    let metricName: String
                    if valueColumnIndexes.count == 1 || isGenericValueHeader(valueHeader) {
                        metricName = baseMetricName
                    } else {
                        metricName = "\(baseMetricName) / \(valueHeader)"
                    }
                    let dedupeKey = [
                        report.id.uuidString,
                        metricName.normalizedKey,
                        period.normalizedKey,
                        valueHeader.normalizedKey,
                        rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    ].joined(separator: "|")
                    guard insertedKeys.insert(dedupeKey).inserted else { continue }
                    let metricKind = AggregationSemantics.classify(metricName: metricName).kind.label
                    try appender.append(report.displayName)
                    try appender.append(report.id.uuidString)
                    try appender.append(Int32(sourceOrder))
                    try appender.append(metricName)
                    try appender.append(metricKind)
                    try appender.append(period)
                    try appender.append(rawValue)
                    try appender.append(parseNumeric(rawValue))
                    try appender.endRow()
                    appended += 1
                }
            }
        }
        try appender.flush()
        return appended > 0
    }

    private static func bestPeriodColumnIndex(headers: [String], rows: [[String]]) -> Int? {
        scoredColumnIndexes(headers: headers, rows: rows) { _, header, values in
            let key = header.normalizedKey
            let namedScore = containsAny(key, ["周期", "日期", "时间", "period", "week", "month", "date", "semana", "mes"]) ? 6 : 0
            let nonEmpty = values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard !nonEmpty.isEmpty else { return namedScore }
            let dateLike = nonEmpty.filter { isDateLike($0) }.count
            let ratioScore = dateLike >= max(2, nonEmpty.count / 3) ? 6 : 0
            let distinctScore = Set(nonEmpty).count >= 2 ? 1 : 0
            return namedScore + ratioScore + distinctScore
        }
    }

    private static func bestMetricColumnIndex(headers: [String], rows: [[String]], excluding excluded: Int) -> Int? {
        bestMetricColumnIndexes(headers: headers, rows: rows, excluding: excluded, userRequest: "").first
    }

    private static func bestMetricColumnIndexes(
        headers: [String],
        rows: [[String]],
        excluding excluded: Int,
        userRequest: String
    ) -> [Int] {
        let requested = requestedMetricKeywords(userRequest)
        let scored = headers.indices.map { index -> (Int, Int) in
            guard index != excluded else { return (index, 0) }
            let header = headers[index]
            let key = header.normalizedKey
            let values = rows.map { value(at: index, in: $0) }
            let nonEmpty = values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let namedScore: Int
            if containsAny(key, ["measure names", "measurenames"]) {
                namedScore = 14
            } else if containsAny(key, ["metric", "指标名称", "指标名"]) {
                namedScore = 12
            } else if containsAny(key, ["指标", "名称", "name"]) {
                namedScore = 7
            } else {
                namedScore = 0
            }
            guard !nonEmpty.isEmpty else { return (index, namedScore) }

            let numericCount = nonEmpty.compactMap(parseNumeric).count
            let dateLikeCount = nonEmpty.filter { isDateLike($0) }.count
            let requestedMatches = requested.reduce(0) { partial, keyword in
                partial + nonEmpty.filter { value in
                    let valueKey = value.normalizedKey
                    let keywordKey = keyword.normalizedKey
                    return value.localizedCaseInsensitiveContains(keyword) ||
                        valueKey.contains(keywordKey) ||
                        keywordKey.contains(valueKey)
                }.count
            }
            let metricWordMatches = nonEmpty.filter { value in
                containsAny(value.normalizedKey, [
                    "交易人数", "交易金额", "交易笔数", "人均", "笔均", "客单价",
                    "金额", "人数", "用户", "笔数", "订单", "gmv", "amount", "users", "orders", "rate", "ratio", "占比", "率"
                ])
            }.count
            let textScore = numericCount <= max(1, nonEmpty.count / 3) ? 3 : -8
            let notDateScore = dateLikeCount < max(2, nonEmpty.count / 4) ? 2 : -6
            let distinctScore = Set(nonEmpty).count >= 2 ? 1 : 0
            let dimensionPenalty = containsAny(key, ["scene", "场景", "channel", "渠道", "category", "分类", "维度", "dimension"]) ? -6 : 0
            let score = namedScore +
                min(requestedMatches * 8, 32) +
                min(metricWordMatches * 3, 18) +
                textScore +
                notDateScore +
                distinctScore +
                dimensionPenalty
            return (index, score)
        }
        return scored
            .filter { $0.1 >= 8 }
            .sorted {
                if $0.1 == $1.1 { return $0.0 < $1.0 }
                return $0.1 > $1.1
            }
            .map(\.0)
    }

    private static func legacyBestMetricColumnIndex(headers: [String], rows: [[String]], excluding excluded: Int) -> Int? {
        scoredColumnIndexes(headers: headers, rows: rows) { index, header, values in
            let key = header.normalizedKey
            guard index != excluded else { return 0 }
            let namedScore = containsAny(key, ["measure names", "measurenames", "metric", "指标", "名称", "name"]) ? 6 : 0
            let nonEmpty = values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard !nonEmpty.isEmpty else { return namedScore }
            let numericCount = nonEmpty.compactMap(parseNumeric).count
            let textScore = numericCount <= max(1, nonEmpty.count / 3) ? 3 : 0
            let dateLikeCount = nonEmpty.filter { isDateLike($0) }.count
            let notDateScore = dateLikeCount < max(2, nonEmpty.count / 4) ? 2 : 0
            let distinctScore = Set(nonEmpty).count >= 2 ? 1 : 0
            return namedScore + textScore + notDateScore + distinctScore
        }
    }

    private static func bestValueColumnIndexes(headers: [String], rows: [[String]], excluding excluded: Set<Int>) -> [Int] {
        headers.indices.compactMap { index -> (Int, Int)? in
            guard !excluded.contains(index) else { return nil }
            let values = rows.map { value(at: index, in: $0) }
            let nonEmpty = values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard !nonEmpty.isEmpty else { return nil }
            let numericCount = nonEmpty.compactMap(parseNumeric).count
            guard numericCount >= max(2, nonEmpty.count / 2) else { return nil }
            let key = headers[index].normalizedKey
            let namedScore = containsAny(key, ["measure values", "measurevalues", "value", "values", "值", "数值", "金额", "amount", "mxn"]) ? 4 : 0
            return (index, numericCount + namedScore)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(3)
        .map(\.0)
    }

    private static func scoredColumnIndexes(
        headers: [String],
        rows: [[String]],
        scorer: (Int, String, [String]) -> Int
    ) -> Int? {
        headers.indices
            .map { index in
                (index, scorer(index, headers[index], rows.map { value(at: index, in: $0) }))
            }
            .filter { $0.1 >= 6 }
            .sorted { $0.1 > $1.1 }
            .first?
            .0
    }

    private static func isGenericValueHeader(_ header: String) -> Bool {
        let key = header.normalizedKey
        return containsAny(key, ["measure values", "measurevalues", "value", "values", "值", "数值"])
    }

    private static func executeAggregationAuditQueries(connection: Connection, tableMaps: [ReportTableMap]) -> [AnalysisNotebookCell] {
        let auditSQL = """
        WITH metric_totals AS (
            SELECT
                source_order,
                source_report,
                source_report_id,
                metric,
                metric_kind,
                MIN(period) AS first_period,
                MAX(period) AS last_period,
                COUNT(numeric_value) AS period_count,
                SUM(numeric_value) AS full_period_sum,
                AVG(numeric_value) AS period_average
            FROM metric_period_values
            WHERE numeric_value IS NOT NULL
            GROUP BY source_order, source_report, source_report_id, metric, metric_kind
        ),
        paired AS (
            SELECT
                cur.source_report,
                cur.metric,
                cur.metric_kind,
                cur.first_period,
                cur.last_period,
                cur.period_count,
                cur.full_period_sum,
                cur.period_average,
                previous.source_report AS comparison_report,
                previous.full_period_sum AS comparison_full_period_sum,
                previous.period_average AS comparison_period_average,
                CASE
                    WHEN previous.full_period_sum IS NULL OR previous.full_period_sum = 0 THEN NULL
                    ELSE (cur.full_period_sum - previous.full_period_sum) / ABS(previous.full_period_sum) * 100
                END AS full_sum_change_percent,
                CASE
                    WHEN previous.period_average IS NULL OR previous.period_average = 0 THEN NULL
                    ELSE (cur.period_average - previous.period_average) / ABS(previous.period_average) * 100
                END AS period_average_change_percent
            FROM metric_totals cur
            LEFT JOIN metric_totals previous
                ON cur.metric = previous.metric
                AND previous.source_order = cur.source_order - 1
        )
        SELECT
            source_report,
            metric,
            metric_kind,
            CASE
                WHEN metric_kind = '可加指标' THEN '默认主口径=全周期SUM；周均只作趋势补充'
                WHEN metric_kind = '派生均值' THEN '用分子/分母重算或加权，不简单平均'
                WHEN metric_kind = '比例指标' THEN '用分子/分母或加权，不简单平均'
                ELSE '不可直接加总，需说明取值口径'
            END AS aggregation_rule,
            first_period,
            last_period,
            CAST(period_count AS VARCHAR) AS period_count,
            CAST(ROUND(full_period_sum, 2) AS VARCHAR) AS full_period_sum,
            CAST(ROUND(period_average, 2) AS VARCHAR) AS period_average,
            COALESCE(comparison_report, '') AS comparison_report,
            COALESCE(CAST(ROUND(comparison_full_period_sum, 2) AS VARCHAR), '') AS comparison_full_period_sum,
            COALESCE(CAST(ROUND(full_sum_change_percent, 2) AS VARCHAR), '') AS full_sum_change_percent,
            COALESCE(CAST(ROUND(comparison_period_average, 2) AS VARCHAR), '') AS comparison_period_average,
            COALESCE(CAST(ROUND(period_average_change_percent, 2) AS VARCHAR), '') AS period_average_change_percent
        FROM paired
        ORDER BY
            CASE metric_kind WHEN '可加指标' THEN 1 WHEN '派生均值' THEN 2 WHEN '比例指标' THEN 3 ELSE 4 END,
            ABS(COALESCE(full_sum_change_percent, period_average_change_percent, full_period_sum, 0)) DESC
        LIMIT 80
        """

        return [
            executeQueryCell(
                connection: connection,
                title: "聚合口径审计",
                sql: auditSQL,
                sourceReportIDs: tableMaps.map(\.reportID)
            )
        ]
    }

    private static func executeRequestedPeriodComparisonCell(
        connection: Connection,
        tableMaps: [ReportTableMap],
        userRequest: String
    ) -> AnalysisNotebookCell {
        let h2Year = requestedYear(in: userRequest, halfKeywords: ["H2", "下半年"]) ?? 2025
        let h1Year = requestedYear(in: userRequest, halfKeywords: ["H1", "上半年"]) ?? 2026
        let h2Label = "\(h2Year) 下半年 (H2)"
        let h1Label = "\(h1Year) 上半年 (H1)"
        let h2YearText = String(h2Year)
        let h1YearText = String(h1Year)
        let metricPriorityOrder = metricPriorityOrderSQL(
            userRequest: userRequest,
            expression: "COALESCE(h1.metric, h2.metric)"
        )
        let sql = """
        WITH bucketed AS (
            SELECT
                source_report,
                metric,
                metric_kind,
                period,
                numeric_value,
                CASE
                    WHEN regexp_matches(period, '\(h2YearText).*([Hh]2|下半年)')
                        OR regexp_matches(period, '\(h2YearText)[-/](0?[7-9]|1[0-2])')
                        OR regexp_matches(period, '\(h2YearText)年(0?[7-9]|1[0-2])月')
                    THEN '\(sqlLiteral(h2Label))'
                    WHEN regexp_matches(period, '\(h1YearText).*([Hh]1|上半年)')
                        OR regexp_matches(period, '\(h1YearText)[-/](0?[1-6])')
                        OR regexp_matches(period, '\(h1YearText)年(0?[1-6])月')
                    THEN '\(sqlLiteral(h1Label))'
                    ELSE NULL
                END AS bucket
            FROM metric_period_values
            WHERE numeric_value IS NOT NULL
        ),
        summed AS (
            SELECT
                source_report,
                metric,
                metric_kind,
                bucket,
                COUNT(*) AS value_count,
                SUM(numeric_value) AS bucket_sum,
                MIN(period) AS first_period,
                MAX(period) AS last_period
            FROM bucketed
            WHERE bucket IS NOT NULL
            GROUP BY source_report, metric, metric_kind, bucket
        ),
        h2 AS (
            SELECT * FROM summed WHERE bucket = '\(sqlLiteral(h2Label))'
        ),
        h1 AS (
            SELECT * FROM summed WHERE bucket = '\(sqlLiteral(h1Label))'
        )
        SELECT
            COALESCE(h1.source_report, h2.source_report) AS source_report,
            COALESCE(h1.metric, h2.metric) AS metric,
            COALESCE(h1.metric_kind, h2.metric_kind) AS metric_kind,
            COALESCE(h2.first_period, '') AS h2_first_period,
            COALESCE(h2.last_period, '') AS h2_last_period,
            COALESCE(CAST(h2.value_count AS VARCHAR), '') AS h2_value_count,
            COALESCE(CAST(ROUND(h2.bucket_sum, 2) AS VARCHAR), '') AS h2_sum,
            COALESCE(h1.first_period, '') AS h1_first_period,
            COALESCE(h1.last_period, '') AS h1_last_period,
            COALESCE(CAST(h1.value_count AS VARCHAR), '') AS h1_value_count,
            COALESCE(CAST(ROUND(h1.bucket_sum, 2) AS VARCHAR), '') AS h1_sum,
            COALESCE(CAST(ROUND(h1.bucket_sum - h2.bucket_sum, 2) AS VARCHAR), '') AS absolute_diff,
            CASE
                WHEN h2.bucket_sum IS NULL OR h2.bucket_sum = 0 THEN ''
                ELSE CAST(ROUND((h1.bucket_sum - h2.bucket_sum) / ABS(h2.bucket_sum) * 100, 2) AS VARCHAR)
            END AS relative_change_percent,
            CASE
                WHEN COALESCE(h1.metric_kind, h2.metric_kind) = '可加指标' THEN '按周期范围 SUM；可直接作为主事实'
                WHEN COALESCE(h1.metric_kind, h2.metric_kind) IN ('派生均值', '比例指标') THEN '必须用分子/分母重算；本行仅用于核对原始派生值'
                ELSE '不可直接加总，需说明取值口径'
            END AS calculation_rule
        FROM h1
        FULL OUTER JOIN h2
            ON h1.source_report = h2.source_report
            AND h1.metric = h2.metric
        ORDER BY
            \(metricPriorityOrder),
            CASE COALESCE(h1.metric_kind, h2.metric_kind) WHEN '可加指标' THEN 1 WHEN '派生均值' THEN 2 WHEN '比例指标' THEN 3 ELSE 4 END,
            ABS(COALESCE((h1.bucket_sum - h2.bucket_sum) / NULLIF(ABS(h2.bucket_sum), 0) * 100, h1.bucket_sum, h2.bucket_sum, 0)) DESC
        LIMIT 80
        """
        let cell = executeQueryCell(
            connection: connection,
            title: "关键指标计算结果",
            sql: sql,
            sourceReportIDs: tableMaps.map(\.reportID)
        )
        if cell.rows.isEmpty && cell.status == .success {
            return AnalysisNotebookCell(
                kind: cell.kind,
                status: cell.status,
                title: cell.title,
                sql: cell.sql,
                columns: cell.columns,
                rows: cell.rows,
                rowCount: cell.rowCount,
                sourceReportIDs: cell.sourceReportIDs,
                errorMessage: "未从当前周期标签中匹配到 \(h2Label) 与 \(h1Label)。如果用户问题指定了其他周期，AI 必须说明当前关键结果表未覆盖该周期，不能输出待回填占位符。",
                durationMilliseconds: cell.durationMilliseconds
            )
        }
        return cell
    }

    private static func executeStandardQueries(connection: Connection, tableMaps: [ReportTableMap]) -> [AnalysisNotebookCell] {
        var cells: [AnalysisNotebookCell] = []
        if !tableMaps.isEmpty {
            let sql = tableMaps.map { map in
                """
                SELECT
                    '\(sqlLiteral(map.reportName))' AS report_name,
                    CAST(COUNT(*) AS VARCHAR) AS ingested_rows,
                    CAST(COUNT(DISTINCT source_report) AS VARCHAR) AS source_names,
                    CAST(\(map.headers.count) AS VARCHAR) AS column_count
                FROM \(quoteIdentifier(map.rawTableName))
                """
            }.joined(separator: "\nUNION ALL\n")
            cells.append(executeQueryCell(
                connection: connection,
                title: "报表载入校验",
                sql: sql,
                sourceReportIDs: tableMaps.map(\.reportID)
            ))

            let qualitySQL = tableMaps.map { map in
                let firstColumn = map.safeColumns.first ?? "source_report"
                let secondColumn = map.safeColumns.dropFirst().first ?? firstColumn
                return """
                SELECT
                    '\(sqlLiteral(map.reportName))' AS report_name,
                    CAST(COUNT(*) AS VARCHAR) AS row_count,
                    CAST(SUM(CASE WHEN \(quoteIdentifier(firstColumn)) IS NULL OR TRIM(\(quoteIdentifier(firstColumn))) = '' THEN 1 ELSE 0 END) AS VARCHAR) AS first_column_missing,
                    CAST(SUM(CASE WHEN \(quoteIdentifier(secondColumn)) IS NULL OR TRIM(\(quoteIdentifier(secondColumn))) = '' THEN 1 ELSE 0 END) AS VARCHAR) AS second_column_missing
                FROM \(quoteIdentifier(map.rawTableName))
                """
            }.joined(separator: "\nUNION ALL\n")
            cells.append(executeQueryCell(
                connection: connection,
                title: "基础数据质量检查",
                sql: qualitySQL,
                sourceReportIDs: tableMaps.map(\.reportID)
            ))
        }

        let profileSQL = """
        SELECT
            source_report,
            CAST(COUNT(*) AS VARCHAR) AS value_points,
            CAST(COUNT(DISTINCT metric) AS VARCHAR) AS metric_count,
            CAST(COUNT(DISTINCT period) AS VARCHAR) AS period_count,
            CAST(COUNT(numeric_value) AS VARCHAR) AS numeric_points
        FROM metric_period_values
        GROUP BY source_report
        ORDER BY source_report
        LIMIT 80
        """
        cells.append(executeQueryCell(
            connection: connection,
            title: "透视宽表长表画像",
            sql: profileSQL,
            sourceReportIDs: tableMaps.map(\.reportID)
        ))

        let movementSQL = """
        WITH ranked AS (
            SELECT
                source_report,
                metric,
                period,
                numeric_value,
                ROW_NUMBER() OVER (PARTITION BY source_report, metric ORDER BY period DESC) AS rn
            FROM metric_period_values
            WHERE numeric_value IS NOT NULL
        ),
        paired AS (
            SELECT
                latest.source_report,
                latest.metric,
                latest.period AS latest_period,
                latest.numeric_value AS latest_value,
                previous.period AS previous_period,
                previous.numeric_value AS previous_value,
                latest.numeric_value - previous.numeric_value AS diff_value,
                CASE
                    WHEN previous.numeric_value IS NULL OR previous.numeric_value = 0 THEN NULL
                    ELSE (latest.numeric_value - previous.numeric_value) / ABS(previous.numeric_value) * 100
                END AS diff_percent
            FROM ranked latest
            LEFT JOIN ranked previous
                ON latest.source_report = previous.source_report
                AND latest.metric = previous.metric
                AND previous.rn = 2
            WHERE latest.rn = 1
        )
        SELECT
            source_report,
            metric,
            latest_period,
            CAST(ROUND(latest_value, 2) AS VARCHAR) AS latest_value,
            previous_period,
            CAST(ROUND(previous_value, 2) AS VARCHAR) AS previous_value,
            CAST(ROUND(diff_value, 2) AS VARCHAR) AS diff_value,
            CAST(ROUND(diff_percent, 2) AS VARCHAR) AS diff_percent
        FROM paired
        ORDER BY ABS(COALESCE(diff_percent, diff_value, 0)) DESC
        LIMIT 40
        """
        cells.append(executeQueryCell(
            connection: connection,
            title: "候选最新周期变化",
            sql: movementSQL,
            sourceReportIDs: tableMaps.map(\.reportID)
        ))

        let anomalySQL = """
        WITH movement AS (
            WITH ranked AS (
                SELECT
                    source_report,
                    metric,
                    period,
                    numeric_value,
                    ROW_NUMBER() OVER (PARTITION BY source_report, metric ORDER BY period DESC) AS rn
                FROM metric_period_values
                WHERE numeric_value IS NOT NULL
            )
            SELECT
                latest.source_report,
                latest.metric,
                latest.numeric_value AS latest_value,
                previous.numeric_value AS previous_value,
                CASE
                    WHEN previous.numeric_value IS NULL OR previous.numeric_value = 0 THEN NULL
                    ELSE (latest.numeric_value - previous.numeric_value) / ABS(previous.numeric_value) * 100
                END AS diff_percent
            FROM ranked latest
            LEFT JOIN ranked previous
                ON latest.source_report = previous.source_report
                AND latest.metric = previous.metric
                AND previous.rn = 2
            WHERE latest.rn = 1
        )
        SELECT
            source_report,
            metric,
            CAST(ROUND(latest_value, 2) AS VARCHAR) AS latest_value,
            CAST(ROUND(previous_value, 2) AS VARCHAR) AS previous_value,
            CAST(ROUND(diff_percent, 2) AS VARCHAR) AS diff_percent,
            CASE
                WHEN ABS(diff_percent) >= 15 THEN '明显变化'
                WHEN ABS(diff_percent) >= 5 THEN '中等变化'
                ELSE '轻微变化'
            END AS signal
        FROM movement
        WHERE diff_percent IS NOT NULL
        ORDER BY ABS(diff_percent) DESC
        LIMIT 40
        """
        cells.append(executeQueryCell(
            connection: connection,
            title: "指标异常候选",
            sql: anomalySQL,
            sourceReportIDs: tableMaps.map(\.reportID)
        ))

        return cells
    }

    private static func executeQueryCell(
        connection: Connection,
        title: String,
        sql: String,
        sourceReportIDs: [UUID]
    ) -> AnalysisNotebookCell {
        let startedAt = Date()
        if let validationError = validateReadOnlySQL(sql) {
            return AnalysisNotebookCell(
                kind: .sql,
                status: .failed,
                title: title,
                sql: sql,
                sourceReportIDs: sourceReportIDs,
                errorMessage: validationError,
                durationMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000)
            )
        }
        do {
            let result = try connection.query(sql)
            let columns = (0..<Int(result.columnCount)).map { result.columnName(at: UInt64($0)) }
            var rows: [[String]] = []
            let rowLimit = min(Int(result.rowCount), 80)
            let stringColumns = (0..<Int(result.columnCount)).map { result.column(at: UInt64($0)).cast(to: String.self) }
            for rowIndex in 0..<rowLimit {
                rows.append(stringColumns.map { column in
                    column[UInt64(rowIndex)] ?? ""
                })
            }
            return AnalysisNotebookCell(
                kind: .sql,
                status: .success,
                title: title,
                sql: sql,
                columns: columns,
                rows: rows,
                rowCount: Int(result.rowCount),
                sourceReportIDs: sourceReportIDs,
                durationMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000)
            )
        } catch {
            return AnalysisNotebookCell(
                kind: .sql,
                status: .failed,
                title: title,
                sql: sql,
                sourceReportIDs: sourceReportIDs,
                errorMessage: error.localizedDescription,
                durationMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000)
            )
        }
    }

    private static func inventoryCell(tableMaps: [ReportTableMap], reports: [ImportedReport]) -> AnalysisNotebookCell {
        let columns = ["报表", "格式", "结构", "原始行数", "SQL载入行", "字段数", "首列指标"]
        let rows = reports.map { report in
            let map = tableMaps.first { $0.reportID == report.id }
            return [
                report.displayName,
                report.sourceFormat.label,
                report.shape.label,
                "\(report.rowCount)",
                "\(map?.ingestedRows ?? 0)",
                "\(report.headers.count)",
                "\(report.firstColumnValues.count)"
            ]
        }
        return AnalysisNotebookCell(
            kind: .resultTable,
            title: "当前任务报表清单",
            columns: columns,
            rows: rows,
            rowCount: rows.count,
            sourceReportIDs: reports.map(\.id)
        )
    }

    private static func fieldMappingCell(tableMaps: [ReportTableMap]) -> AnalysisNotebookCell {
        var rows: [[String]] = []
        for map in tableMaps {
            for (index, header) in map.headers.enumerated().prefix(80) {
                rows.append([
                    map.reportName,
                    map.safeColumns[index],
                    header
                ])
            }
        }
        return AnalysisNotebookCell(
            kind: .resultTable,
            title: "SQL 安全列名映射",
            columns: ["报表", "SQL列名", "原始字段"],
            rows: rows,
            rowCount: rows.count,
            sourceReportIDs: tableMaps.map(\.reportID)
        )
    }

    private static func aggregationIntentCell(userRequest: String, reports: [ImportedReport]) -> AnalysisNotebookCell {
        let intent = AggregationSemantics.intent(userRequest: userRequest, reports: reports)
        let additiveExamples = reports
            .flatMap(\.firstColumnValues)
            .filter { AggregationSemantics.classify(metricName: $0).kind == .additive }
            .uniqued()
            .prefix(10)
            .joined(separator: "、")
            .nilIfBlank ?? "未识别"
        let derivedExamples = reports
            .flatMap(\.firstColumnValues)
            .filter { AggregationSemantics.classify(metricName: $0).kind == .derivedAverage || AggregationSemantics.classify(metricName: $0).kind == .ratio }
            .uniqued()
            .prefix(10)
            .joined(separator: "、")
            .nilIfBlank ?? "未识别"

        let rows = [
            ["本轮聚合意图", intent.label, intentRule(for: intent)],
            ["可加指标示例", additiveExamples, "文件/全周期对比时使用 SUM，不用周均替代总账变化。"],
            ["派生/比例指标示例", derivedExamples, "使用分子/分母重算或加权，不直接平均周期值。"]
        ]
        return AnalysisNotebookCell(
            kind: .resultTable,
            title: "聚合口径判定",
            columns: ["判定项", "结果", "执行规则"],
            rows: rows,
            rowCount: rows.count,
            sourceReportIDs: reports.map(\.id)
        )
    }

    private static func derivedMetricAuditCell(reports: [ImportedReport]) -> AnalysisNotebookCell {
        let reportTotals = reports.enumerated().map { index, report in
            (report: report, totals: metricTotals(for: report, sourceOrder: index + 1))
        }
        var rows: [[String]] = []
        var previousRecomputedByMetric: [String: (reportName: String, value: Double)] = [:]

        for item in reportTotals {
            let totals = item.totals
            let derivedMetrics = totals.filter {
                $0.kind == .derivedAverage || $0.kind == .ratio
            }
            for derived in derivedMetrics {
                guard let formula = inferredDerivedFormula(metricName: derived.metricName, totals: totals),
                      formula.denominator.totalSum != 0 else {
                    continue
                }
                let recomputed = formula.numerator.totalSum / formula.denominator.totalSum
                let previous = previousRecomputedByMetric[derived.metricName.normalizedKey]
                let changePercent = previous.flatMap { previousValue -> Double? in
                    guard previousValue.value != 0 else { return nil }
                    return (recomputed - previousValue.value) / abs(previousValue.value) * 100
                }
                rows.append([
                    item.report.displayName,
                    derived.metricName,
                    formula.rule,
                    formula.numerator.metricName,
                    formatNumber(formula.numerator.totalSum),
                    formula.denominator.metricName,
                    formatNumber(formula.denominator.totalSum),
                    formatNumber(recomputed),
                    formatNumber(derived.periodAverage),
                    previous?.reportName ?? "",
                    changePercent.map(formatPercent) ?? ""
                ])
                previousRecomputedByMetric[derived.metricName.normalizedKey] = (item.report.displayName, recomputed)
            }
        }

        return AnalysisNotebookCell(
            kind: .resultTable,
            title: "派生指标重算审计",
            columns: ["报表", "派生指标", "正确口径", "分子指标", "分子SUM", "分母指标", "分母SUM", "重算值", "周期值均值", "对比报表", "重算变化%"],
            rows: rows,
            rowCount: rows.count,
            sourceReportIDs: reports.map(\.id),
            errorMessage: rows.isEmpty ? "未识别到可自动重算的常见派生指标；AI 仍必须说明派生/比例指标口径。" : nil
        )
    }

    private static func dateCandidateCell(reports: [ImportedReport]) -> AnalysisNotebookCell {
        var rows: [[String]] = []
        for report in reports {
            let headers = report.headers
            let samples = normalizedRows(for: report, headers: headers).prefix(80)
            for (index, header) in headers.enumerated() {
                let key = header.normalizedKey
                let looksNamed = ["日期", "时间", "周期", "week", "month", "date", "semana", "mes"].contains { key.contains($0.normalizedKey) }
                let nonEmptySamples = samples.map { value(at: index, in: $0) }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                let dateLikeCount = nonEmptySamples.filter { isDateLike($0) }.count
                guard looksNamed || dateLikeCount >= max(3, nonEmptySamples.count / 2) else { continue }
                rows.append([
                    report.displayName,
                    header,
                    "\(nonEmptySamples.count)",
                    "\(dateLikeCount)",
                    nonEmptySamples.prefix(3).joined(separator: " / ")
                ])
            }
        }
        return AnalysisNotebookCell(
            kind: .resultTable,
            title: "竖向日期/周期候选列",
            columns: ["报表", "字段", "样例数", "疑似日期数", "样例"],
            rows: rows,
            rowCount: rows.count,
            sourceReportIDs: reports.map(\.id),
            errorMessage: rows.isEmpty ? "未发现高置信竖向日期列；AI 仍可根据原始表格自行判断周期语义。" : nil
        )
    }

    private struct MetricTotal {
        var metricName: String
        var kind: MetricAggregationKind
        var periodCount: Int
        var totalSum: Double
        var periodAverage: Double
    }

    private struct DerivedFormula {
        var numerator: MetricTotal
        var denominator: MetricTotal
        var rule: String
    }

    private static func metricTotals(for report: ImportedReport, sourceOrder: Int) -> [MetricTotal] {
        let headers = report.headers.isEmpty ? inferredHeaders(for: report) : report.headers
        guard headers.count >= 2 else { return [] }
        let rows = normalizedRows(for: report, headers: headers)
        if let longTotals = longMetricTotals(headers: headers, rows: rows), !longTotals.isEmpty {
            return longTotals
        }
        var totals: [MetricTotal] = []
        for row in rows {
            let metricName = value(at: 0, in: row).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !metricName.isEmpty else { continue }
            let values = headers.indices.dropFirst().compactMap { parseNumeric(value(at: $0, in: row)) }
            guard !values.isEmpty else { continue }
            let total = values.reduce(0, +)
            let classification = AggregationSemantics.classify(metricName: metricName)
            totals.append(MetricTotal(
                metricName: metricName,
                kind: classification.kind,
                periodCount: values.count,
                totalSum: total,
                periodAverage: total / Double(values.count)
            ))
        }
        return totals
    }

    private static func longMetricTotals(headers: [String], rows: [[String]]) -> [MetricTotal]? {
        guard headers.count >= 3,
              let periodColumnIndex = bestPeriodColumnIndex(headers: headers, rows: Array(rows.prefix(160))) else {
            return nil
        }
        let sampleRows = Array(rows.prefix(160))
        let metricColumnIndexes = bestMetricColumnIndexes(
            headers: headers,
            rows: sampleRows,
            excluding: periodColumnIndex,
            userRequest: ""
        )
        guard !metricColumnIndexes.isEmpty else { return nil }

        var valuesByMetric: [String: [Double]] = [:]
        var insertedKeys = Set<String>()
        for metricColumnIndex in metricColumnIndexes.prefix(3) {
            let valueColumnIndexes = bestValueColumnIndexes(
                headers: headers,
                rows: sampleRows,
                excluding: Set([periodColumnIndex, metricColumnIndex])
            )
            guard !valueColumnIndexes.isEmpty else { continue }
            for row in rows {
                let baseMetric = value(at: metricColumnIndex, in: row).trimmingCharacters(in: .whitespacesAndNewlines)
                let period = value(at: periodColumnIndex, in: row).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !baseMetric.isEmpty else { continue }
                for valueColumnIndex in valueColumnIndexes {
                    let rawValue = value(at: valueColumnIndex, in: row)
                    guard let number = parseNumeric(rawValue) else { continue }
                    let valueHeader = headers[valueColumnIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                    let metricName = (valueColumnIndexes.count == 1 || isGenericValueHeader(valueHeader))
                        ? baseMetric
                        : "\(baseMetric) / \(valueHeader)"
                    let dedupeKey = [
                        metricName.normalizedKey,
                        period.normalizedKey,
                        valueHeader.normalizedKey,
                        rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    ].joined(separator: "|")
                    guard insertedKeys.insert(dedupeKey).inserted else { continue }
                    valuesByMetric[metricName, default: []].append(number)
                }
            }
        }
        guard !valuesByMetric.isEmpty else { return nil }
        return valuesByMetric.map { metricName, values in
            let total = values.reduce(0, +)
            let classification = AggregationSemantics.classify(metricName: metricName)
            return MetricTotal(
                metricName: metricName,
                kind: classification.kind,
                periodCount: values.count,
                totalSum: total,
                periodAverage: values.isEmpty ? 0 : total / Double(values.count)
            )
        }
    }

    private static func inferredDerivedFormula(metricName: String, totals: [MetricTotal]) -> DerivedFormula? {
        let metricKey = metricName.normalizedKey
        let additiveTotals = totals.filter { $0.kind == .additive }
        func find(_ candidates: [String], excluding excludedKey: String = "") -> MetricTotal? {
            additiveTotals.first { total in
                let key = total.metricName.normalizedKey
                guard key != excludedKey else { return false }
                return candidates.contains { key.contains($0.normalizedKey) }
            }
        }

        if metricName.localizedCaseInsensitiveContains("人均") && (metricName.contains("金额") || metricKey.contains("amount")) {
            if let numerator = find(["交易金额", "金额", "gmv", "收入"], excluding: metricKey),
               let denominator = find(["交易人数", "人数", "用户数", "客户数"], excluding: metricKey) {
                return DerivedFormula(numerator: numerator, denominator: denominator, rule: "\(numerator.metricName) ÷ \(denominator.metricName)")
            }
        }
        if (metricName.localizedCaseInsensitiveContains("笔均") || metricName.localizedCaseInsensitiveContains("单均")) && (metricName.contains("金额") || metricKey.contains("amount")) {
            if let numerator = find(["交易金额", "金额", "gmv", "收入"], excluding: metricKey),
               let denominator = find(["交易笔数", "笔数", "订单数", "次数"], excluding: metricKey) {
                return DerivedFormula(numerator: numerator, denominator: denominator, rule: "\(numerator.metricName) ÷ \(denominator.metricName)")
            }
        }
        if metricName.localizedCaseInsensitiveContains("人均") && (metricName.contains("笔") || metricName.contains("次")) {
            if let numerator = find(["交易笔数", "笔数", "次数", "订单数"], excluding: metricKey),
               let denominator = find(["交易人数", "人数", "用户数", "客户数"], excluding: metricKey) {
                return DerivedFormula(numerator: numerator, denominator: denominator, rule: "\(numerator.metricName) ÷ \(denominator.metricName)")
            }
        }
        if metricName.localizedCaseInsensitiveContains("客单价") {
            if let numerator = find(["交易金额", "订单金额", "gmv", "金额"], excluding: metricKey),
               let denominator = find(["订单数", "交易笔数", "笔数"], excluding: metricKey) {
                return DerivedFormula(numerator: numerator, denominator: denominator, rule: "\(numerator.metricName) ÷ \(denominator.metricName)")
            }
        }
        return nil
    }

    private static func intentRule(for intent: AnalysisAggregationIntent) -> String {
        switch intent {
        case .fileTotalComparison:
            return "默认按全周期 SUM 做主结论；周均只能作为补充趋势。"
        case .periodAverageTrend:
            return "按周均/周期均值观察趋势，并明确不是总账 SUM。"
        case .ambiguousNeedsConfirmation:
            return "先请用户确认 SUM 还是周均，不输出确定结论。"
        }
    }

    private static func requestedYear(in userRequest: String, halfKeywords: [String]) -> Int? {
        let text = userRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lowered = text.lowercased()
        let keywordRanges = halfKeywords.compactMap { keyword -> Range<String.Index>? in
            lowered.range(of: keyword.lowercased())
        }
        guard !keywordRanges.isEmpty else { return nil }

        let nsText = text as NSString
        let nsLowered = lowered as NSString
        let regex = try? NSRegularExpression(pattern: #"(20\d{2})"#)
        let matches = regex?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? []
        let keywordLocations = halfKeywords.compactMap { keyword -> Int? in
            let location = nsLowered.range(of: keyword.lowercased()).location
            return location == NSNotFound ? nil : location
        }
        let yearCandidates = matches.compactMap { match -> (Int, Int)? in
            guard let year = Int(nsText.substring(with: match.range(at: 1))) else { return nil }
            let distance = keywordLocations.map { abs($0 - match.range.location) }.min() ?? Int.max
            return (year, distance)
        }
        if let nearest = yearCandidates.sorted(by: { $0.1 < $1.1 }).first, nearest.1 <= 36 {
            return nearest.0
        }

        let currentYear = Calendar.current.component(.year, from: Date())
        let relativeYearTokens: [(String, Int)] = [
            ("前年", currentYear - 2),
            ("去年", currentYear - 1),
            ("今年", currentYear),
            ("明年", currentYear + 1)
        ]
        var relativeCandidates: [(year: Int, distance: Int)] = []
        for (token, year) in relativeYearTokens {
            var searchRange = NSRange(location: 0, length: nsText.length)
            while searchRange.location < nsText.length {
                let tokenRange = nsText.range(of: token, options: [], range: searchRange)
                guard tokenRange.location != NSNotFound else { break }
                let tokenCenter = tokenRange.location + tokenRange.length / 2
                let distance = keywordLocations.map { abs($0 - tokenCenter) }.min() ?? Int.max
                if distance <= 24 {
                    relativeCandidates.append((year, distance))
                }
                let nextLocation = tokenRange.location + max(tokenRange.length, 1)
                searchRange = NSRange(location: nextLocation, length: max(nsText.length - nextLocation, 0))
            }
        }
        if let nearestRelative = relativeCandidates.sorted(by: { $0.distance < $1.distance }).first {
            return nearestRelative.year
        }
        let globalRelativeYears = relativeYearTokens.compactMap { token, year in
            text.contains(token) ? year : nil
        }
        if Set(globalRelativeYears).count == 1 {
            return globalRelativeYears.first
        }
        return yearCandidates.first?.0
    }

    private static func requestedMetricKeywords(_ userRequest: String) -> [String] {
        let candidates = [
            "交易人数",
            "交易金额",
            "交易笔数",
            "人均交易金额",
            "人均交易笔数",
            "笔均交易金额",
            "客单价",
            "交易用户",
            "订单金额",
            "订单数",
            "支付金额",
            "用户数",
            "收入",
            "GMV"
        ]
        let trimmed = userRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let key = trimmed.normalizedKey
        let matches = candidates.filter { candidate in
            trimmed.localizedCaseInsensitiveContains(candidate) ||
                key.contains(candidate.normalizedKey)
        }
        if !matches.isEmpty {
            return matches
        }
        if containsAny(key, ["交易", "transaction", "gmv"]) {
            return ["交易人数", "交易金额", "交易笔数", "人均交易金额", "人均交易笔数", "笔均交易金额"]
        }
        return []
    }

    private static func metricPriorityOrderSQL(userRequest: String, expression: String) -> String {
        let keywords = requestedMetricKeywords(userRequest)
        guard !keywords.isEmpty else { return "99" }
        let whens = keywords.enumerated().map { index, keyword in
            "WHEN \(expression) LIKE '%\(sqlLiteral(keyword))%' THEN \(index)"
        }.joined(separator: " ")
        return "CASE \(whens) ELSE 99 END"
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.localizedCaseInsensitiveContains($0) || text.contains($0.normalizedKey) }
    }

    private static func formatNumber(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func formatPercent(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func normalizedRows(for report: ImportedReport, headers: [String]) -> [[String]] {
        let rawRows = report.rawRows
        if rawRows.count > 1 {
            return Array(rawRows.dropFirst()).map { row in
                headers.indices.map { value(at: $0, in: row) }
            }
        }
        let rows = report.storedDataRows.isEmpty ? report.sampleRows : report.storedDataRows
        return rows.map { row in
            headers.map { row[$0] ?? "" }
        }
    }

    private static func inferredHeaders(for report: ImportedReport) -> [String] {
        if !report.headers.isEmpty { return report.headers }
        if let first = report.rawRows.first, !first.isEmpty {
            return first.indices.map { "列\($0 + 1)" }
        }
        if let first = (report.storedDataRows.first ?? report.sampleRows.first) {
            return first.keys.sorted()
        }
        return []
    }

    private static func value(at index: Int, in row: [String]) -> String {
        guard row.indices.contains(index) else { return "" }
        return row[index]
    }

    private static func parseNumeric(_ text: String) -> Double? {
        var value = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "MXN", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "％", with: "%")
        if value.hasSuffix("%") {
            value.removeLast()
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return Double(value)
    }

    private static func isDateLike(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 4 else { return false }
        let patterns = [
            #"^\d{4}[-/]\d{1,2}[-/]\d{1,2}$"#,
            #"^\d{1,2}[-/]\d{1,2}[-/]\d{2,4}$"#,
            #"^\d{4}[-/]\d{1,2}[-/]\d{1,2}\s*[~至-]\s*\d{4}?[-/]?\d{0,2}[-/]?\d{0,2}$"#,
            #"^\d{4}[-/]\d{1,2}$"#,
            #"^\d{4}\s*W\d{1,2}$"#
        ]
        return patterns.contains { pattern in
            value.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func quoteIdentifier(_ identifier: String) -> String {
        "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func sqlLiteral(_ text: String) -> String {
        text.replacingOccurrences(of: "'", with: "''")
    }
}
