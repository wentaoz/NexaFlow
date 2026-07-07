import CLibXLS
import CoreXLSX
import Foundation

enum ExcelParser {
    static func parse(fileURL: URL) throws -> [CSVTable] {
        try ImportFileSizePolicy.validateSingleFile(fileURL)
        switch fileURL.pathExtension.lowercased() {
        case "xlsx":
            return try parseXLSX(fileURL: fileURL)
        case "xls":
            return try parseXLS(fileURL: fileURL)
        default:
            throw ImportError.unsupportedFile(fileURL.lastPathComponent)
        }
    }

    private static func parseXLSX(fileURL: URL) throws -> [CSVTable] {
        guard let file = XLSXFile(filepath: fileURL.path) else {
            throw ImportError.unreadableFile(fileURL.lastPathComponent)
        }
        let sharedStrings = try? file.parseSharedStrings()
        let styles = try? file.parseStyles()
        var result: [CSVTable] = []
        var workbookWarnings: [String] = []
        if styles == nil {
            workbookWarnings.append("XLSX 未读取到样式信息，日期格式只能按单元格类型和原始值推断。")
        }

        for workbook in try file.parseWorkbooks() {
            let sheets = try file.parseWorksheetPathsAndNames(workbook: workbook)
            for (index, item) in sheets.enumerated() {
                let sheetName = item.name?.nilIfBlank ?? "Sheet\(index + 1)"
                let worksheet = try file.parseWorksheet(at: item.path)
                let converted = rawRows(from: worksheet, sharedStrings: sharedStrings, styles: styles)
                guard !converted.rows.isEmpty else { continue }
                let warnings = converted.warnings + [
                    converted.mergedRangeCount > 0 ? "已还原 \(converted.mergedRangeCount) 个 XLSX 合并单元格，用于表头和首列标签识别。" : nil
                ].compactMap { $0 }
                result.append(CSVParser.table(
                    fromRawRows: converted.rows,
                    sourceFormat: .xlsx,
                    sheetName: sheetName,
                    sheetIndex: index,
                    parseWarnings: warnings,
                    originalEncoding: "xlsx",
                    delimiter: "sheet",
                    workbookWarnings: workbookWarnings,
                    cellTypeHints: converted.cellTypeHints
                ))
            }
        }

        guard !result.isEmpty else {
            throw ImportError.unreadableFile("\(fileURL.lastPathComponent)：没有可识别的非空 sheet，或文件已加密/受保护。")
        }
        return result
    }

    private static func rawRows(
        from worksheet: Worksheet,
        sharedStrings: SharedStrings?,
        styles: Styles?
    ) -> (rows: [[String]], cellTypeHints: [String: String], warnings: [String], mergedRangeCount: Int) {
        var cellsByRow: [Int: [Int: String]] = [:]
        var hints: [String: String] = [:]
        var warnings: [String] = []
        var maxRow = 0
        var maxColumn = 0

        for row in worksheet.data?.rows ?? [] {
            for cell in row.cells {
                let rowIndex = Int(cell.reference.row)
                let columnIndex = columnNumber(cell.reference.column.description)
                maxRow = max(maxRow, rowIndex)
                maxColumn = max(maxColumn, columnIndex)
                let converted = stringValue(for: cell, sharedStrings: sharedStrings, styles: styles)
                if !converted.value.isEmpty {
                    cellsByRow[rowIndex, default: [:]][columnIndex] = converted.value
                }
                if let hint = converted.typeHint {
                    hints[cell.reference.description] = hint
                }
                if cell.formula != nil, cell.value?.nilIfBlank == nil {
                    warnings.append("公式单元格 \(cell.reference.description) 没有缓存值，已按空值处理。")
                }
            }
        }

        let mergedRangeCount = fillMergedCells(worksheet.mergeCells?.items ?? [], cellsByRow: &cellsByRow, maxRow: &maxRow, maxColumn: &maxColumn)
        guard maxRow > 0, maxColumn > 0 else { return ([], hints, warnings.uniqued(), mergedRangeCount) }

        let rows = (1...maxRow).map { rowIndex in
            (1...maxColumn).map { columnIndex in
                cellsByRow[rowIndex]?[columnIndex] ?? ""
            }
        }
        return (rows, hints, warnings.uniqued(), mergedRangeCount)
    }

    private static func stringValue(
        for cell: Cell,
        sharedStrings: SharedStrings?,
        styles: Styles?
    ) -> (value: String, typeHint: String?) {
        if let sharedStrings,
           let text = cell.stringValue(sharedStrings)?.nilIfBlank {
            return (text, "sharedString")
        }
        if let inline = cell.inlineString?.text?.nilIfBlank {
            return (inline, "inlineString")
        }
        if cell.type == .bool, let value = cell.value {
            return ((value == "1" || value.lowercased() == "true") ? "true" : "false", "boolean")
        }
        if shouldTreatAsDate(cell: cell, styles: styles),
           let date = cell.dateValue {
            return (DateFormatting.shortDate.string(from: date), "date")
        }
        if let raw = cell.value?.nilIfBlank {
            return (raw, cell.formula == nil ? cell.type?.rawValue : "formulaCachedValue")
        }
        return ("", cell.formula == nil ? cell.type?.rawValue : "formulaWithoutCachedValue")
    }

    private static func shouldTreatAsDate(cell: Cell, styles: Styles?) -> Bool {
        if cell.type == .date { return true }
        guard cell.type != .sharedString,
              cell.value.flatMap(Double.init) != nil,
              let format = styles.flatMap({ cell.format(in: $0) }) else {
            return false
        }
        let builtInDateFormats: Set<Int> = Set(Array(14...22) + Array(27...36) + Array(45...47) + Array(50...58))
        if builtInDateFormats.contains(format.numberFormatId) { return true }
        let customCode = styles?.numberFormats?.items.first { $0.id == format.numberFormatId }?.formatCode.lowercased() ?? ""
        guard !customCode.isEmpty else { return false }
        return customCode.contains("yy") || customCode.contains("dd") || customCode.contains("m/")
            || customCode.contains("月") || customCode.contains("日")
    }

    private static func fillMergedCells(
        _ mergedCells: [MergeCell],
        cellsByRow: inout [Int: [Int: String]],
        maxRow: inout Int,
        maxColumn: inout Int
    ) -> Int {
        var count = 0
        for merge in mergedCells {
            guard let range = cellRange(merge.reference),
                  let anchor = cellsByRow[range.startRow]?[range.startColumn]?.nilIfBlank else {
                continue
            }
            count += 1
            maxRow = max(maxRow, range.endRow)
            maxColumn = max(maxColumn, range.endColumn)
            for row in range.startRow...range.endRow {
                for column in range.startColumn...range.endColumn where cellsByRow[row]?[column]?.nilIfBlank == nil {
                    cellsByRow[row, default: [:]][column] = anchor
                }
            }
        }
        return count
    }

    private static func parseXLS(fileURL: URL) throws -> [CSVTable] {
        var error = LIBXLS_OK
        let workbook = fileURL.path.withCString { pathPointer in
            "UTF-8".withCString { encodingPointer in
                xls_open_file(pathPointer, encodingPointer, &error)
            }
        }
        guard let workbook else {
            let message = xls_getError(error).map { String(cString: $0) } ?? "未知错误"
            throw ImportError.unreadableFile("\(fileURL.lastPathComponent)：XLS 解析失败，\(message)")
        }
        defer { xls_close_WB(workbook) }

        let sheetCount = Int(workbook.pointee.sheets.count)
        guard sheetCount > 0, let sheetPointer = workbook.pointee.sheets.sheet else {
            throw ImportError.unreadableFile("\(fileURL.lastPathComponent)：XLS 中没有可读取 sheet。")
        }

        var result: [CSVTable] = []
        var skippedHidden = 0
        for index in 0..<sheetCount {
            let sheetInfo = sheetPointer.advanced(by: index).pointee
            guard sheetInfo.type == 0 else { continue }
            if sheetInfo.visibility != 0 {
                skippedHidden += 1
                continue
            }
            let sheetName = sheetInfo.name.map { String(cString: $0) }?.nilIfBlank ?? "Sheet\(index + 1)"
            guard let worksheet = xls_getWorkSheet(workbook, Int32(index)) else { continue }
            defer { xls_close_WS(worksheet) }
            let parseError = xls_parseWorkSheet(worksheet)
            guard parseError == LIBXLS_OK else { continue }
            let converted = rawRows(from: worksheet)
            guard !converted.rows.isEmpty else { continue }
            var warnings = converted.warnings
            if skippedHidden > 0 {
                warnings.append("已跳过 \(skippedHidden) 个隐藏 XLS sheet。")
            }
            result.append(CSVParser.table(
                fromRawRows: converted.rows,
                sourceFormat: .xls,
                sheetName: sheetName,
                sheetIndex: index,
                parseWarnings: warnings,
                originalEncoding: "xls",
                delimiter: "sheet",
                workbookWarnings: ["XLS 为旧版 BIFF 格式，日期单元格可能只能读取到显示值或序列值。"],
                cellTypeHints: converted.cellTypeHints
            ))
        }

        guard !result.isEmpty else {
            throw ImportError.unreadableFile("\(fileURL.lastPathComponent)：没有可识别的非空可见 XLS sheet，或文件已加密/受保护。")
        }
        return result
    }

    private static func rawRows(from worksheet: UnsafeMutablePointer<xlsWorkSheet>) -> (rows: [[String]], cellTypeHints: [String: String], warnings: [String]) {
        let maxRow = Int(worksheet.pointee.rows.lastrow)
        let maxColumn = Int(worksheet.pointee.rows.lastcol)
        guard maxRow >= 0, maxColumn >= 0 else { return ([], [:], []) }
        var rows = Array(repeating: Array(repeating: "", count: maxColumn + 1), count: maxRow + 1)
        var hints: [String: String] = [:]
        var warnings: [String] = []

        for rowIndex in 0...maxRow {
            for columnIndex in 0...maxColumn {
                guard let cell = xls_cell(worksheet, WORD(rowIndex), WORD(columnIndex)) else { continue }
                let value = stringValue(for: cell.pointee)
                rows[rowIndex][columnIndex] = value.text
                hints["\(columnName(columnIndex + 1))\(rowIndex + 1)"] = value.hint
                if cell.pointee.rowspan > 1 || cell.pointee.colspan > 1 {
                    let rowSpan = max(Int(cell.pointee.rowspan), 1)
                    let columnSpan = max(Int(cell.pointee.colspan), 1)
                    for mergedRow in rowIndex..<min(rowIndex + rowSpan, rows.count) {
                        for mergedColumn in columnIndex..<min(columnIndex + columnSpan, rows[mergedRow].count) where rows[mergedRow][mergedColumn].isEmpty {
                            rows[mergedRow][mergedColumn] = value.text
                        }
                    }
                }
                if value.hint == "formulaWithoutCachedValue" {
                    warnings.append("公式单元格 \(columnName(columnIndex + 1))\(rowIndex + 1) 没有缓存值，已按空值处理。")
                }
            }
        }
        return (rows, hints, warnings.uniqued())
    }

    private static func stringValue(for cell: xlsCell) -> (text: String, hint: String) {
        let id = Int(cell.id)
        let numericIDs = [0x027E, 0x00BD, 0x0203]
        let formulaIDs = [0x0006, 0x0406]
        if numericIDs.contains(id) {
            return (formatNumber(cell.d), "number")
        }
        if formulaIDs.contains(id) {
            if cell.l == 0 {
                return (formatNumber(cell.d), "formulaCachedNumber")
            }
            guard let text = cell.str.map({ String(cString: $0) }) else {
                return ("", "formulaWithoutCachedValue")
            }
            if text == "bool" {
                return (cell.d == 0 ? "false" : "true", "formulaCachedBoolean")
            }
            if text == "error" {
                return ("*error*", "formulaError")
            }
            return (text, "formulaCachedString")
        }
        if let text = cell.str.map({ String(cString: $0) }) {
            return (text, "string")
        }
        return ("", "blank")
    }

    private static func formatNumber(_ value: Double) -> String {
        if value.isFinite, value.rounded() == value, abs(value) < 9_007_199_254_740_992 {
            return String(Int64(value))
        }
        return String(format: "%.15g", value)
    }

    private static func columnNumber(_ columnName: String) -> Int {
        columnName.uppercased().unicodeScalars.reduce(0) { result, scalar in
            guard scalar.value >= 65, scalar.value <= 90 else { return result }
            return result * 26 + Int(scalar.value - 64)
        }
    }

    private static func columnName(_ columnNumber: Int) -> String {
        var number = columnNumber
        var result = ""
        while number > 0 {
            number -= 1
            guard let scalar = UnicodeScalar(65 + number % 26) else { break }
            result = String(scalar) + result
            number /= 26
        }
        return result.isEmpty ? "A" : result
    }

    private static func cellRange(_ raw: String) -> (startColumn: Int, startRow: Int, endColumn: Int, endRow: Int)? {
        let parts = raw.components(separatedBy: ":")
        guard parts.count == 2,
              let start = cellAddress(parts[0]),
              let end = cellAddress(parts[1]) else { return nil }
        return (
            min(start.column, end.column),
            min(start.row, end.row),
            max(start.column, end.column),
            max(start.row, end.row)
        )
    }

    private static func cellAddress(_ raw: String) -> (column: Int, row: Int)? {
        let letters = raw.prefix { $0.isLetter }
        let digits = raw.drop { $0.isLetter }
        guard !letters.isEmpty, let row = Int(digits) else { return nil }
        return (columnNumber(String(letters)), row)
    }
}
