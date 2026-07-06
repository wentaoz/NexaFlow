import Foundation
import SwiftUI

struct MarkdownMessageRenderer: View {
    private let blocks: [MarkdownRenderableBlock]

    init(_ markdown: String) {
        self.blocks = MarkdownRenderCache.shared.blocks(for: markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let text):
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if text.isLongerThan(Self.maxRichTextCharacters) {
                            LongTextPreview(
                                text: text,
                                previewLimit: 3_000,
                                expandedHeight: 280
                            )
                        } else {
                            Text(MarkdownMessageRenderer.attributedMarkdown(text))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                case .table(let table):
                    MarkdownTableView(table: table)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    fileprivate static func attributedMarkdown(_ text: String) -> AttributedString {
        MarkdownRenderCache.shared.attributedString(for: text)
    }

    private static let maxRichTextCharacters = 24_000
}

private final class MarkdownBlockBox {
    let blocks: [MarkdownRenderableBlock]

    init(_ blocks: [MarkdownRenderableBlock]) {
        self.blocks = blocks
    }
}

private final class AttributedStringBox {
    let value: AttributedString

    init(_ value: AttributedString) {
        self.value = value
    }
}

private final class MarkdownRenderCache {
    static let shared = MarkdownRenderCache()

    private let blockCache = NSCache<NSString, MarkdownBlockBox>()
    private let attributedCache = NSCache<NSString, AttributedStringBox>()
    private let markdownOptions = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)

    private init() {
        blockCache.countLimit = 48
        blockCache.totalCostLimit = 700_000
        attributedCache.countLimit = 96
        attributedCache.totalCostLimit = 420_000
    }

    func blocks(for markdown: String) -> [MarkdownRenderableBlock] {
        let key = cacheKey(for: markdown)
        if let cached = blockCache.object(forKey: key) {
            return cached.blocks
        }

        let parsed = PerformanceTrace.measure(
            "markdown.blocks",
            metadata: "chars=\(markdown.utf8.count)"
        ) {
            MarkdownMessageParser.parse(markdown)
        }
        blockCache.setObject(MarkdownBlockBox(parsed), forKey: key, cost: markdown.count)
        return parsed
    }

    func attributedString(for text: String) -> AttributedString {
        let key = cacheKey(for: text)
        if let cached = attributedCache.object(forKey: key) {
            return cached.value
        }

        let parsed = PerformanceTrace.measure(
            "markdown.attributed",
            metadata: "chars=\(text.utf8.count)"
        ) {
            (try? AttributedString(markdown: text, options: markdownOptions)) ?? AttributedString(text)
        }
        attributedCache.setObject(AttributedStringBox(parsed), forKey: key, cost: text.count)
        return parsed
    }

    private func cacheKey(for text: String) -> NSString {
        text as NSString
    }
}

private enum MarkdownRenderableBlock {
    case text(String)
    case table(MarkdownTableModel)
}

private struct MarkdownTableModel {
    var header: [String]
    var alignments: [MarkdownTableAlignment]
    var rows: [[String]]
    var totalRowCount: Int
    var columnWidths: [CGFloat]

    var visibleRows: [[String]] {
        rows
    }

    var isTruncated: Bool {
        totalRowCount > rows.count
    }

    var truncatedRowCount: Int {
        max(0, totalRowCount - rows.count)
    }

    static func columnWidths(header: [String], visibleRows: [[String]]) -> [CGFloat] {
        header.indices.map { index in
            let headerLength = header[index].displayLength
            let bodyLength = visibleRows.map { row in
                index < row.count ? row[index].displayLength : 0
            }.max() ?? 0
            let length = max(headerLength, bodyLength)
            return min(max(CGFloat(length) * 8 + 36, 110), 260)
        }
    }

    fileprivate static let maxVisibleRows = 60
}

private enum MarkdownTableAlignment {
    case leading
    case center
    case trailing

    var frameAlignment: Alignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

private enum MarkdownMessageParser {
    static func parse(_ markdown: String) -> [MarkdownRenderableBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [MarkdownRenderableBlock] = []
        var textBuffer: [String] = []
        var lineIndex = 0
        var isInsideCodeFence = false

        func flushTextBuffer() {
            guard !textBuffer.isEmpty else { return }
            blocks.append(.text(textBuffer.joined(separator: "\n")))
            textBuffer.removeAll(keepingCapacity: true)
        }

        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                isInsideCodeFence.toggle()
                textBuffer.append(line)
                lineIndex += 1
                continue
            }

            if !isInsideCodeFence,
               lineIndex + 1 < lines.count,
               let table = parseTable(startingAt: lineIndex, lines: lines) {
                flushTextBuffer()
                blocks.append(.table(table.model))
                lineIndex = table.nextLineIndex
                continue
            }

            textBuffer.append(line)
            lineIndex += 1
        }

        flushTextBuffer()
        return blocks
    }

    private static func parseTable(startingAt index: Int, lines: [String]) -> (model: MarkdownTableModel, nextLineIndex: Int)? {
        guard index + 1 < lines.count else { return nil }
        let header = splitTableRow(lines[index])
        let separator = splitTableRow(lines[index + 1])
        guard header.count >= 2, separator.count >= 2, isSeparatorRow(separator) else {
            return nil
        }

        let columnCount = header.count
        let alignments = normalized(separator, count: columnCount).map(alignment)
        var rows: [[String]] = []
        var totalRowCount = 0
        var cursor = index + 2

        while cursor < lines.count {
            let candidate = lines[cursor]
            guard candidate.contains("|"),
                  !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                break
            }

            if rows.count < MarkdownTableModel.maxVisibleRows {
                let cells = splitTableRow(candidate)
                guard cells.count >= 2 else { break }
                if isSeparatorRow(cells) {
                    cursor += 1
                    continue
                }
                rows.append(normalized(cells, count: columnCount))
            } else {
                guard looksLikeTableContinuation(candidate, minimumPipeCount: max(1, columnCount - 1)) else {
                    break
                }
            }

            totalRowCount += 1
            cursor += 1
        }

        let normalizedHeader = normalized(header, count: columnCount)
        let normalizedRows = rows
        let columnWidths = MarkdownTableModel.columnWidths(
            header: normalizedHeader,
            visibleRows: normalizedRows
        )
        return (
            MarkdownTableModel(
                header: normalizedHeader,
                alignments: alignments,
                rows: normalizedRows,
                totalRowCount: totalRowCount,
                columnWidths: columnWidths
            ),
            cursor
        )
    }

    private static func looksLikeTableContinuation(_ line: String, minimumPipeCount: Int) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        var pipeCount = 0
        for character in trimmed where character == "|" {
            pipeCount += 1
            if pipeCount >= minimumPipeCount {
                return true
            }
        }
        return false
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var working = line.trimmingCharacters(in: .whitespaces)
        if working.hasPrefix("|") {
            working.removeFirst()
        }
        if working.hasSuffix("|") {
            working.removeLast()
        }

        var cells: [String] = []
        var current = ""
        var isEscaped = false

        for character in working {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }

            if character == "\\" {
                isEscaped = true
            } else if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(character)
            }
        }

        if isEscaped {
            current.append("\\")
        }
        cells.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return cells
    }

    private static func isSeparatorRow(_ cells: [String]) -> Bool {
        cells.allSatisfy { cell in
            let compact = cell.replacingOccurrences(of: " ", with: "")
            guard compact.filter({ $0 == "-" }).count >= 3 else { return false }
            return compact.allSatisfy { character in
                character == "-" || character == ":"
            }
        }
    }

    private static func alignment(for separator: String) -> MarkdownTableAlignment {
        let compact = separator.replacingOccurrences(of: " ", with: "")
        let startsWithColon = compact.hasPrefix(":")
        let endsWithColon = compact.hasSuffix(":")
        if startsWithColon && endsWithColon {
            return .center
        }
        if endsWithColon {
            return .trailing
        }
        return .leading
    }

    private static func normalized(_ cells: [String], count: Int) -> [String] {
        if cells.count == count {
            return cells
        }
        if cells.count > count {
            return Array(cells.prefix(count))
        }
        return cells + Array(repeating: "", count: count - cells.count)
    }
}

private struct MarkdownTableView: View {
    var table: MarkdownTableModel

    var body: some View {
        let visibleRows = table.visibleRows
        let columnWidths = table.columnWidths

        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                MarkdownTableRowView(
                    cells: table.header,
                    alignments: table.alignments,
                    columnWidths: columnWidths,
                    isHeader: true,
                    rowIndex: 0
                )
                Divider()
                ForEach(Array(visibleRows.enumerated()), id: \.offset) { rowIndex, row in
                    MarkdownTableRowView(
                        cells: row,
                        alignments: table.alignments,
                        columnWidths: columnWidths,
                        isHeader: false,
                        rowIndex: rowIndex
                    )
                    if rowIndex < visibleRows.count - 1 {
                        Divider()
                    }
                }
                if table.isTruncated {
                    Divider()
                    Text("表格较长，仅渲染前 \(visibleRows.count) 行，另有 \(table.truncatedRowCount) 行未展开；完整内容仍保留在原始回复中。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
            }
            .background(AppTheme.card.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownTableRowView: View {
    var cells: [String]
    var alignments: [MarkdownTableAlignment]
    var columnWidths: [CGFloat]
    var isHeader: Bool
    var rowIndex: Int

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { columnIndex, cell in
                Text(cell)
                    .font(isHeader ? .callout.weight(.semibold) : .callout)
                    .multilineTextAlignment(alignment(at: columnIndex).textAlignment)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(
                        width: width(at: columnIndex),
                        alignment: alignment(at: columnIndex).frameAlignment
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(cellBackground)
                    .overlay(alignment: .trailing) {
                        if columnIndex < cells.count - 1 {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.12))
                                .frame(width: 1)
                        }
                    }
            }
        }
    }

    private var cellBackground: Color {
        if isHeader {
            return Color.secondary.opacity(0.12)
        }
        return rowIndex.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.04)
    }

    private func alignment(at index: Int) -> MarkdownTableAlignment {
        index < alignments.count ? alignments[index] : .leading
    }

    private func width(at index: Int) -> CGFloat {
        index < columnWidths.count ? columnWidths[index] : 140
    }
}

private extension String {
    func isLongerThan(_ limit: Int) -> Bool {
        guard let boundary = index(startIndex, offsetBy: limit, limitedBy: endIndex) else {
            return false
        }
        return boundary < endIndex
    }

    var displayLength: Int {
        reduce(0) { partialResult, character in
            partialResult + (character.isASCII ? 1 : 2)
        }
    }
}
