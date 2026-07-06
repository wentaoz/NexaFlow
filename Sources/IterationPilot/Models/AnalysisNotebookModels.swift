import Foundation

enum AnalysisNotebookCellKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case markdown
    case sql
    case resultTable
    case chartSpec
    case aiInterpretation

    var id: String { rawValue }

    var label: String {
        switch self {
        case .markdown: return "说明"
        case .sql: return "SQL"
        case .resultTable: return "结果表"
        case .chartSpec: return "图表建议"
        case .aiInterpretation: return "AI 解读"
        }
    }
}

enum AnalysisNotebookCellStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case success
    case failed
    case skipped

    var id: String { rawValue }

    var label: String {
        switch self {
        case .success: return "成功"
        case .failed: return "失败"
        case .skipped: return "跳过"
        }
    }
}

struct AnalysisNotebookCell: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: AnalysisNotebookCellKind
    var status: AnalysisNotebookCellStatus
    var title: String
    var markdown: String
    var sql: String
    var columns: [String]
    var rows: [[String]]
    var rowCount: Int
    var sourceReportIDs: [UUID]
    var errorMessage: String?
    var durationMilliseconds: Int?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: AnalysisNotebookCellKind,
        status: AnalysisNotebookCellStatus = .success,
        title: String,
        markdown: String = "",
        sql: String = "",
        columns: [String] = [],
        rows: [[String]] = [],
        rowCount: Int = 0,
        sourceReportIDs: [UUID] = [],
        errorMessage: String? = nil,
        durationMilliseconds: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.title = title
        self.markdown = markdown
        self.sql = sql
        self.columns = columns
        self.rows = rows
        self.rowCount = rowCount
        self.sourceReportIDs = sourceReportIDs
        self.errorMessage = errorMessage
        self.durationMilliseconds = durationMilliseconds
        self.createdAt = createdAt
    }
}

struct AnalysisNotebookRun: Identifiable, Codable, Hashable {
    var id: UUID
    var businessSpaceID: UUID?
    var packID: UUID
    var taskID: UUID?
    var sessionID: UUID?
    var messageID: UUID?
    var trigger: String
    var engine: String
    var skillSummary: String
    var cells: [AnalysisNotebookCell]
    var warnings: [String]
    var createdAt: Date
    var durationMilliseconds: Int?

    init(
        id: UUID = UUID(),
        businessSpaceID: UUID?,
        packID: UUID,
        taskID: UUID?,
        sessionID: UUID?,
        messageID: UUID?,
        trigger: String,
        engine: String = "DuckDB",
        skillSummary: String,
        cells: [AnalysisNotebookCell],
        warnings: [String] = [],
        createdAt: Date = Date(),
        durationMilliseconds: Int? = nil
    ) {
        self.id = id
        self.businessSpaceID = businessSpaceID
        self.packID = packID
        self.taskID = taskID
        self.sessionID = sessionID
        self.messageID = messageID
        self.trigger = trigger
        self.engine = engine
        self.skillSummary = skillSummary
        self.cells = cells
        self.warnings = warnings
        self.createdAt = createdAt
        self.durationMilliseconds = durationMilliseconds
    }

    var successCount: Int {
        cells.filter { $0.status == .success }.count
    }

    var failedCount: Int {
        cells.filter { $0.status == .failed }.count
    }

    var resultCells: [AnalysisNotebookCell] {
        cells.filter { !$0.columns.isEmpty || !$0.rows.isEmpty || !$0.sql.isEmpty }
    }

    var summary: String {
        "执行 \(cells.count) 个计算单元，成功 \(successCount) 个，失败 \(failedCount) 个"
    }

    var promptMarkdown: String {
        var lines: [String] = [
            "## 本轮 SQL/Notebook 计算证据",
            "- 引擎：\(engine)",
            "- 触发：\(trigger)",
            "- 生成时间：\(DateFormatting.shortDateTime.string(from: createdAt))",
            "- Skill 路由：\(skillSummary)",
            "- 执行结果：\(summary)"
        ]
        if !warnings.isEmpty {
            lines.append("- 限制：\(warnings.prefix(6).joined(separator: "；"))")
        }
        for cell in cells.prefix(8) {
            lines.append("")
            lines.append("### \(cell.title)")
            lines.append("- 类型：\(cell.kind.label)；状态：\(cell.status.label)；结果行数：\(cell.rowCount)")
            if !cell.sql.isEmpty {
                lines.append("```sql")
                lines.append(cell.sql)
                lines.append("```")
            }
            if !cell.columns.isEmpty {
                lines.append(markdownTable(columns: cell.columns, rows: Array(cell.rows.prefix(12))))
            }
            if let errorMessage = cell.errorMessage, !errorMessage.isEmpty {
                lines.append("- 错误：\(errorMessage)")
            }
            if !cell.markdown.isEmpty {
                lines.append(cell.markdown)
            }
        }
        lines.append("")
        lines.append("请在分析和报告中优先引用这些已计算事实；没有 SQL 验证的内容必须标为 AI 推断、弱假设或需补数据。")
        return lines.joined(separator: "\n")
    }

    var evidenceMarkdown: String {
        var lines: [String] = [
            "\(engine) · \(summary)",
            "Skill 路由：\(skillSummary)"
        ]
        if !warnings.isEmpty {
            lines.append("限制：\(warnings.prefix(5).joined(separator: "；"))")
        }
        for cell in resultCells.prefix(5) {
            lines.append("• \(cell.title)：\(cell.status.label)，\(cell.rowCount) 行结果")
        }
        return lines.joined(separator: "\n")
    }

    private func markdownTable(columns: [String], rows: [[String]]) -> String {
        guard !columns.isEmpty else { return "" }
        let header = "| " + columns.joined(separator: " | ") + " |"
        let divider = "| " + Array(repeating: "---", count: columns.count).joined(separator: " | ") + " |"
        let body = rows.map { row in
            let padded = (0..<columns.count).map { index in
                index < row.count ? row[index].replacingOccurrences(of: "\n", with: " ") : ""
            }
            return "| " + padded.joined(separator: " | ") + " |"
        }
        return ([header, divider] + body).joined(separator: "\n")
    }
}
