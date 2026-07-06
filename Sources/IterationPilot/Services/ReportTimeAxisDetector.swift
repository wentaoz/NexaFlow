import Foundation

enum ReportTimeAxisDetector {
    static func detect(table: CSVTable) -> ReportTimeAxisProfile {
        let verticalProfile = detectVertical(table: table)
        if verticalProfile.primaryDateColumn != nil, verticalProfile.confidence >= 0.45 {
            return verticalProfile
        }
        switch table.shape {
        case .pivotWide:
            return detectHorizontal(table: table)
        case .detail, .unknown:
            return verticalProfile
        }
    }

    static func detect(report: ImportedReport) -> ReportTimeAxisProfile {
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
        return detect(table: table)
    }

    static func bestDateColumn(in table: CSVTable) -> String? {
        detect(table: table).primaryDateColumn
    }

    private static func detectHorizontal(table: CSVTable) -> ReportTimeAxisProfile {
        let timeHeaders = Array(table.headers.dropFirst()).filter { header in
            DateParsing.parse(normalizedDateText(header)) != nil || relativeTimeRank(header) != nil
        }
        guard !timeHeaders.isEmpty else {
            return ReportTimeAxisProfile(
                orientation: .unknown,
                primaryDateColumn: nil,
                candidateDateColumns: [],
                confidence: 0.35,
                warnings: ["透视宽表未识别到可靠横向时间列；AI 可直接检查原始表头。"],
                userConfirmed: false
            )
        }
        let confidence = min(0.92, 0.5 + Double(timeHeaders.count) * 0.08)
        return ReportTimeAxisProfile(
            orientation: .horizontalColumns,
            primaryDateColumn: nil,
            candidateDateColumns: [],
            confidence: confidence,
            detectedFormats: ["横向列名日期/相对周期"],
            warnings: timeHeaders.count < max(2, table.headers.count - 1) ? ["部分横向列未识别为时间列，可能是分组或维度。"] : [],
            userConfirmed: false,
            updatedAt: Date()
        )
    }

    private static func detectVertical(table: CSVTable) -> ReportTimeAxisProfile {
        guard !table.headers.isEmpty else { return .unknown }
        let candidates = table.headers.compactMap { header -> ReportTimeAxisCandidate? in
            candidate(for: header, rows: table.rows)
        }.sorted {
            if $0.confidence == $1.confidence { return $0.parsedCount > $1.parsedCount }
            return $0.confidence > $1.confidence
        }

        guard let best = candidates.first else {
            return ReportTimeAxisProfile(
                orientation: .unknown,
                confidence: 0.2,
                warnings: ["明细表未识别到可稳定解析的竖向日期列；AI 可直接查看原始表格并询问时间口径。"],
                userConfirmed: false
            )
        }
        var warnings: [String] = []
        if candidates.count > 1 {
            let names = candidates.prefix(5).map(\.columnName).joined(separator: "、")
            warnings.append("识别到多个日期列候选（\(names)），需要确认主分析时间口径。")
        }
        if best.confidence < 0.7 {
            warnings.append("主日期列候选置信度偏低，AI 不应把它当成绝对事实。")
        }
        let orientation: ReportTimeAxisOrientation = candidates.count > 1 ? .mixed : .verticalDateColumn
        return ReportTimeAxisProfile(
            orientation: orientation,
            primaryDateColumn: best.confidence >= 0.45 ? best.columnName : nil,
            candidateDateColumns: Array(candidates.prefix(12)),
            confidence: best.confidence,
            detectedFormats: candidates.flatMap(\.detectedFormats).uniqued(),
            warnings: warnings + candidates.flatMap(\.warnings).uniqued(),
            userConfirmed: false,
            updatedAt: Date()
        )
    }

    private static func candidate(for header: String, rows: [[String: String]]) -> ReportTimeAxisCandidate? {
        let values = rows.map { ($0[header] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        let nonEmpty = values.filter { !$0.isEmpty }
        guard !nonEmpty.isEmpty else { return nil }
        let sample = Array(nonEmpty.prefix(120))
        let parsedPairs = sample.compactMap { value -> (String, Date)? in
            if let range = DateParsing.periodRange(normalizedDateText(value)) {
                return (value, range.end)
            }
            guard let date = DateParsing.parse(normalizedDateText(value)) else { return nil }
            return (value, date)
        }
        guard parsedPairs.count >= 2 else { return nil }
        let headerScore = headerKeywordScore(header)
        let parseRatio = Double(parsedPairs.count) / Double(max(sample.count, 1))
        let coverageRatio = Double(nonEmpty.count) / Double(max(rows.count, 1))
        let uniquenessRatio = Double(Set(parsedPairs.map { DateFormatting.shortDate.string(from: $0.1) }).count) / Double(max(parsedPairs.count, 1))
        let roleHint = roleHint(for: header)
        let confidence = min(0.96, max(0.15, parseRatio * 0.45 + coverageRatio * 0.2 + uniquenessRatio * 0.15 + headerScore))
        guard confidence >= 0.35 else { return nil }
        let dates = parsedPairs.map(\.1).sorted()
        var warnings: [String] = []
        if parseRatio < 0.65 {
            warnings.append("\(header) 只有 \(Int(parseRatio * 100))% 样例能解析为日期。")
        }
        if headerScore < 0.1 {
            warnings.append("\(header) 表头不像日期字段，但样例值可解析。")
        }
        return ReportTimeAxisCandidate(
            columnName: header,
            roleHint: roleHint,
            confidence: confidence,
            parsedCount: parsedPairs.count,
            nonEmptyCount: nonEmpty.count,
            missingCount: rows.count - nonEmpty.count,
            firstDate: dates.first,
            lastDate: dates.last,
            detectedFormats: detectedFormats(values: parsedPairs.map(\.0)),
            exampleValues: Array(sample.prefix(6)),
            warnings: warnings
        )
    }

    private static func headerKeywordScore(_ header: String) -> Double {
        let key = header.normalizedKey
        if ["date", "datetime", "timestamp", "day", "week", "month", "period", "周期", "日期", "时间", "发生时间", "交易时间", "注册时间", "申请时间", "审核时间", "支付时间"].contains(where: { key.contains($0.normalizedKey) }) {
            return 0.25
        }
        if key.contains("created") || key.contains("updated") || key.contains("_at") {
            return 0.18
        }
        return 0
    }

    private static func roleHint(for header: String) -> String {
        let key = header.normalizedKey
        if key.contains("注册") || key.contains("register") || key.contains("signup") { return "注册时间" }
        if key.contains("申请") || key.contains("apply") || key.contains("application") { return "申请时间" }
        if key.contains("审核") || key.contains("审批") || key.contains("kyc") || key.contains("review") { return "审核/审批时间" }
        if key.contains("交易") || key.contains("支付") || key.contains("缴费") || key.contains("payment") || key.contains("transaction") { return "交易/支付时间" }
        if key.contains("事件") || key.contains("event") { return "事件发生时间" }
        if key.contains("创建") || key.contains("created") { return "记录创建时间" }
        if key.contains("更新") || key.contains("updated") { return "记录更新时间" }
        return "日期候选"
    }

    private static func detectedFormats(values: [String]) -> [String] {
        values.prefix(20).compactMap { value in
            if value.range(of: #"^\d{4}-\d{1,2}-\d{1,2}"#, options: .regularExpression) != nil { return "yyyy-MM-dd" }
            if value.range(of: #"^\d{4}/\d{1,2}/\d{1,2}"#, options: .regularExpression) != nil { return "yyyy/MM/dd" }
            if value.range(of: #"^\d{1,2}/\d{1,2}/\d{4}"#, options: .regularExpression) != nil { return "MM/dd/yyyy" }
            if value.range(of: #"^\d{4}\.\d{1,2}\.\d{1,2}"#, options: .regularExpression) != nil { return "yyyy.M.d" }
            if value.range(of: #"\d{4}-\d{1,2}-\d{1,2}T"#, options: .regularExpression) != nil { return "ISO8601" }
            if DateParsing.periodRange(value) != nil { return "日期区间/周期" }
            return nil
        }.uniqued()
    }

    private static func normalizedDateText(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "年", with: "/")
            .replacingOccurrences(of: "月", with: "/")
            .replacingOccurrences(of: "日", with: "")
            .replacingOccurrences(of: ".", with: "/")
    }

    private static func relativeTimeRank(_ header: String) -> Double? {
        let value = header.normalizedKey
        if value.contains("上上周") || value.contains("前两周") || value.contains("上上期") { return 10 }
        if value.contains("上周") || value.contains("上一周") || value.contains("上期") || value.contains("上一期") { return 20 }
        if value.contains("本周") || value.contains("本期") || value.contains("当前") || value.contains("最近") { return 30 }
        if value.contains("上上月") || value.contains("前两月") { return 110 }
        if value.contains("上月") || value.contains("上一月") { return 120 }
        if value.contains("本月") || value.contains("当月") { return 130 }
        return nil
    }
}
