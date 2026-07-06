import Foundation

struct ParsedTable {
    var headers: [String]
    var rows: [[String: String]]
    var firstColumnValues: [String]
    var fieldExamples: [String: String]
    var shape: CSVTableShape
    var sourceFormat: ReportSourceFormat
    var sheetName: String?
    var sheetIndex: Int?
    var parseWarnings: [String]
    var originalEncoding: String
    var delimiter: String
    var workbookWarnings: [String]
    var cellTypeHints: [String: String]
    var rawRows: [[String]] = []
}

typealias CSVTable = ParsedTable

enum CSVParser {
    static func parse(fileURL: URL) throws -> CSVTable {
        let data = try Data(contentsOf: fileURL)
        guard let decoded = decode(data) else {
            throw ImportError.unreadableFile(fileURL.lastPathComponent)
        }
        return parse(decoded.content, originalEncoding: decoded.encodingName)
    }

    static func parse(_ content: String) -> CSVTable {
        parse(content, originalEncoding: "memory")
    }

    private static func parse(_ content: String, originalEncoding: String) -> CSVTable {
        let normalizedContent = normalizeContent(content)
        let delimiter = detectDelimiter(in: normalizedContent)
        var warnings: [String] = []
        if content.contains("\r") {
            warnings.append("已标准化 CSV 换行符，兼容 \\r / \\r\\n / \\n。")
        }

        let rawRows = parseRows(normalizedContent, delimiter: delimiter)
            .map(trimTrailingEmptyCells)
            .filter { row in
                row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }

        guard !rawRows.isEmpty else {
            return CSVTable(
                headers: [],
                rows: [],
                firstColumnValues: [],
                fieldExamples: [:],
                shape: .unknown,
                sourceFormat: .csv,
                sheetName: nil,
                sheetIndex: nil,
                parseWarnings: ["CSV 为空或没有可识别内容。"],
                originalEncoding: originalEncoding,
                delimiter: String(delimiter),
                workbookWarnings: [],
                cellTypeHints: [:],
                rawRows: []
            )
        }

        return table(
            fromRawRows: rawRows,
            sourceFormat: .csv,
            sheetName: nil,
            sheetIndex: nil,
            parseWarnings: warnings,
            originalEncoding: originalEncoding,
            delimiter: String(delimiter),
            workbookWarnings: [],
            cellTypeHints: [:]
        )
    }

    static func table(
        fromRawRows rawRows: [[String]],
        sourceFormat: ReportSourceFormat,
        sheetName: String?,
        sheetIndex: Int?,
        parseWarnings initialWarnings: [String],
        originalEncoding: String,
        delimiter: String,
        workbookWarnings: [String] = [],
        cellTypeHints: [String: String] = [:]
    ) -> CSVTable {
        let rawRows = rawRows
            .map(trimTrailingEmptyCells)
            .filter { row in
                row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
        guard !rawRows.isEmpty else {
            return CSVTable(
                headers: [],
                rows: [],
                firstColumnValues: [],
                fieldExamples: [:],
                shape: .unknown,
                sourceFormat: sourceFormat,
                sheetName: sheetName,
                sheetIndex: sheetIndex,
                parseWarnings: uniqueStrings(initialWarnings + ["表格为空或没有可识别内容。"]),
                originalEncoding: originalEncoding,
                delimiter: delimiter,
                workbookWarnings: workbookWarnings,
                cellTypeHints: cellTypeHints,
                rawRows: []
            )
        }

        var warnings = initialWarnings
        let shape = detectShape(rawRows)
        let headerRowCount = headerRowCount(for: rawRows, shape: shape)
        let headers = headers(for: rawRows, shape: shape, headerRowCount: headerRowCount)
        let dataRows = Array(rawRows.dropFirst(headerRowCount))
        let dictionaries = dictionaries(from: dataRows, headers: headers)
        let firstColumnValues = shape == .pivotWide
            ? uniqueNonEmptyValues(
                dataRows.compactMap { row in
                    row.first?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                }
            )
            : []
        let fieldExamples = fieldExamples(headers: headers, dataRows: dataRows, firstColumnValues: firstColumnValues)

        if shape == .pivotWide {
            warnings.append("识别为透视宽表：第一列按指标/行标签处理，横向列按日期、周或分组处理。")
        }
        if hasDuplicateNonEmptyValues(rawRows.prefix(headerRowCount).flatMap { $0 }) {
            warnings.append("检测到重复表头，已生成稳定内部列名避免数据覆盖。")
        }
        if headers.count > 200 {
            warnings.append("字段列数较多（\(headers.count) 列），可能是 BI 导出的宽表。")
        }
        if dictionaries.isEmpty && rawRows.count > 1 {
            warnings.append("未解析到有效数据行，请检查表头行或分隔符是否正确。")
        }

        return CSVTable(
            headers: headers,
            rows: dictionaries,
            firstColumnValues: firstColumnValues,
            fieldExamples: fieldExamples,
            shape: shape,
            sourceFormat: sourceFormat,
            sheetName: sheetName,
            sheetIndex: sheetIndex,
            parseWarnings: uniqueStrings(warnings + workbookWarnings),
            originalEncoding: originalEncoding,
            delimiter: delimiter,
            workbookWarnings: workbookWarnings,
            cellTypeHints: cellTypeHints,
            rawRows: rawRows
        )
    }

    private static func decode(_ data: Data) -> (content: String, encodingName: String)? {
        let encodings: [(String.Encoding, String)] = [
            (.utf8, data.starts(with: [0xEF, 0xBB, 0xBF]) ? "utf8BOM" : "utf8"),
            (.utf16, "utf16"),
            (gb18030Encoding, "gb18030")
        ]
        for (encoding, name) in encodings {
            if let content = String(data: data, encoding: encoding) {
                return (content, name)
            }
        }
        return nil
    }

    private static var gb18030Encoding: String.Encoding {
        let raw = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String.Encoding(rawValue: raw)
    }

    private static func normalizeContent(_ content: String) -> String {
        content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
    }

    private static func detectDelimiter(in content: String) -> Character {
        let sampleLines = normalizeContent(content)
            .split(whereSeparator: \.isNewline)
            .prefix(20)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let candidates: [Character] = [",", "\t", ";"]
        return candidates.max { lhs, rhs in
            sampleLines.reduce(0) { $0 + delimiterCount(in: $1, delimiter: lhs) }
                < sampleLines.reduce(0) { $0 + delimiterCount(in: $1, delimiter: rhs) }
        } ?? ","
    }

    private static func delimiterCount(in line: String, delimiter: Character) -> Int {
        var count = 0
        var inQuotes = false
        let characters = Array(line)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if inQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    index += 2
                    continue
                }
                inQuotes.toggle()
            } else if character == delimiter, !inQuotes {
                count += 1
            }
            index += 1
        }
        return count
    }

    private static func parseRows(_ content: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = content.makeIterator()

        while let character = iterator.next() {
            switch character {
            case "\"":
                if inQuotes {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            process(character: next, delimiter: delimiter, row: &row, rows: &rows, field: &field, inQuotes: &inQuotes)
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            default:
                process(character: character, delimiter: delimiter, row: &row, rows: &rows, field: &field, inQuotes: &inQuotes)
            }
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows
    }

    private static func process(
        character: Character,
        delimiter: Character,
        row: inout [String],
        rows: inout [[String]],
        field: inout String,
        inQuotes: inout Bool
    ) {
        if inQuotes {
            field.append(character)
            return
        }

        if character == delimiter {
            row.append(field)
            field = ""
        } else if character == "\n" {
            row.append(field)
            rows.append(row)
            row = []
            field = ""
        } else if character == "\r" {
            return
        } else {
            field.append(character)
        }
    }

    private static func trimTrailingEmptyCells(_ row: [String]) -> [String] {
        var copy = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        while copy.last?.isEmpty == true {
            copy.removeLast()
        }
        return copy
    }

    private static func detectShape(_ rows: [[String]]) -> CSVTableShape {
        guard let firstRow = rows.first else { return .unknown }
        let firstRowTail = firstRow.dropFirst()
        let duplicateCount = duplicateNonEmptyCount(in: Array(firstRowTail))
        let horizontalDateCells = rows.prefix(4).reduce(0) { total, row in
            total + row.dropFirst().filter { looksLikeHorizontalTimeHeader($0) }.count
        }
        let firstCellEmpty = firstRow.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        let wideEnough = firstRow.count >= 3 || rows.prefix(4).contains { $0.count >= 3 }
        if wideEnough && (horizontalDateCells >= 3 || duplicateCount >= 1 && horizontalDateCells >= 1 || firstCellEmpty && firstRowTail.count >= 2) {
            return .pivotWide
        }
        return firstRow.isEmpty ? .unknown : .detail
    }

    private static func headerRowCount(for rows: [[String]], shape: CSVTableShape) -> Int {
        guard shape == .pivotWide else { return 1 }
        let limit = min(rows.count, 6)
        for index in 1..<limit {
            let first = rows[index].first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let tail = rows[index].dropFirst().map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let hasDataTail = tail.contains { !$0.isEmpty }
            if !first.isEmpty, !isHeaderLabel(first), hasDataTail {
                return max(index, 1)
            }
        }
        return min(2, rows.count)
    }

    private static func headers(for rows: [[String]], shape: CSVTableShape, headerRowCount: Int) -> [String] {
        guard shape == .pivotWide else {
            return uniquedHeaders(from: rows.first ?? [])
        }
        let headerRows = Array(rows.prefix(headerRowCount))
        let maxColumns = rows.prefix(max(headerRowCount + 1, 1)).map(\.count).max() ?? 0
        let rawHeaders = (0..<maxColumns).map { column -> String in
            if column == 0 {
                let label = headerRows.compactMap { column < $0.count ? $0[column].nilIfBlank : nil }.first ?? "指标"
                return label.isEmpty ? "指标" : label
            }
            let parts = headerRows.compactMap { row -> String? in
                guard column < row.count else { return nil }
                return row[column].trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            }
            let collapsed = parts.reduce(into: [String]()) { result, value in
                if result.last?.normalizedKey != value.normalizedKey {
                    result.append(value)
                }
            }
            return collapsed.isEmpty ? "列 \(column + 1)" : collapsed.joined(separator: " / ")
        }
        return uniquedHeaders(from: rawHeaders)
    }

    private static func uniquedHeaders(from rawHeaders: [String]) -> [String] {
        var seen: [String: Int] = [:]
        return rawHeaders.enumerated().map { index, rawHeader in
            let base = rawHeader.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "未命名列 \(index + 1)"
            let key = base.normalizedKey
            let count = (seen[key] ?? 0) + 1
            seen[key] = count
            return count == 1 ? base : "\(base) #\(count)"
        }
    }

    private static func dictionaries(from dataRows: [[String]], headers: [String]) -> [[String: String]] {
        dataRows.compactMap { row -> [String: String]? in
            var result: [String: String] = [:]
            var hasValue = false
            for (index, header) in headers.enumerated() {
                let value = index < row.count ? row[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                result[header] = value
                if !value.isEmpty { hasValue = true }
            }
            return hasValue ? result : nil
        }
    }

    private static func fieldExamples(headers: [String], dataRows: [[String]], firstColumnValues: [String]) -> [String: String] {
        var examples: [String: String] = [:]
        for (index, header) in headers.enumerated() where !header.isEmpty {
            if let value = dataRows.compactMap({ row -> String? in
                guard index < row.count else { return nil }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            }).first {
                examples[header] = value
            }
        }
        for row in dataRows {
            guard let label = row.first?.trimmingCharacters(in: .whitespacesAndNewlines), firstColumnValues.contains(where: { $0.normalizedKey == label.normalizedKey }) else {
                continue
            }
            let value = row.dropFirst().map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? ""
            if !value.isEmpty, examples[label] == nil {
                examples[label] = value
            }
        }
        return examples
    }

    private static func uniqueNonEmptyValues(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.normalizedKey).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.normalizedKey).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    private static func hasDuplicateNonEmptyValues(_ values: [String]) -> Bool {
        duplicateNonEmptyCount(in: values) > 0
    }

    private static func duplicateNonEmptyCount(in values: [String]) -> Int {
        var seen = Set<String>()
        var duplicates = 0
        for value in values {
            let key = value.trimmingCharacters(in: .whitespacesAndNewlines).normalizedKey
            guard !key.isEmpty else { continue }
            if !seen.insert(key).inserted { duplicates += 1 }
        }
        return duplicates
    }

    private static func looksLikeHorizontalTimeHeader(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let normalized = trimmed.normalizedKey
        if DateParsing.parse(trimmed) != nil { return true }
        if trimmed.range(of: #"\d{4}[-/.年]\d{1,2}[-/.月]\d{1,2}"#, options: .regularExpression) != nil { return true }
        if trimmed.range(of: #"\d{4}[-/.年]\d{1,2}\s*[-至~—]\s*\d{1,2}"#, options: .regularExpression) != nil { return true }
        if trimmed.range(of: #"\d{1,2}[-/.月]\d{1,2}\s*[-至~—]\s*\d{1,2}[-/.月]\d{1,2}"#, options: .regularExpression) != nil { return true }
        return normalized.contains("week") ||
            normalized.contains("month") ||
            normalized.contains("date") ||
            normalized.contains("last") ||
            normalized.contains("current") ||
            trimmed.contains("周") ||
            trimmed.contains("月") ||
            trimmed.contains("日期") ||
            trimmed.contains("本期") ||
            trimmed.contains("上期") ||
            trimmed.contains("最近")
    }

    private static func isHeaderLabel(_ value: String) -> Bool {
        let normalized = value.normalizedKey
        return normalized == "week of date" ||
            normalized == "date" ||
            normalized == "metric" ||
            normalized == "指标" ||
            normalized == "日期" ||
            normalized.contains("week") ||
            normalized.contains("month") ||
            value.contains("周") ||
            value.contains("月")
    }
}

enum ImportError: LocalizedError {
    case unreadableFile(String)
    case unsupportedFolder(String)
    case unsupportedFile(String)

    var errorDescription: String? {
        switch self {
        case .unreadableFile(let file):
            return "无法读取文件：\(file)"
        case .unsupportedFolder(let folder):
            return "文件夹中没有可识别的数据文件：\(folder)"
        case .unsupportedFile(let file):
            return "暂不支持该文件格式：\(file)"
        }
    }
}
