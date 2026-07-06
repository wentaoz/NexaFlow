import Foundation
import ZIPFoundation

enum WordDocumentExporter {
    static func exportMemo(packName: String, markdown: String, aiSupplement: String, to url: URL) throws {
        let report = ReportDocumentBuilder(packName: packName)
        let elements = report.buildElements(
            markdown: AnalysisOutputTextFormatter.normalizedPercentages(in: markdown),
            aiSupplement: AnalysisOutputTextFormatter.normalizedPercentages(in: aiSupplement)
        )
        let entries = makeDocumentEntries(elements: elements, title: report.title)

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let archive = try Archive(url: url, accessMode: .create)

        for entry in entries {
            let data = Data(entry.content.utf8)
            try archive.addEntry(
                with: entry.path,
                type: .file,
                uncompressedSize: Int64(data.count),
                compressionMethod: .deflate
            ) { position, size in
                let start = Int(position)
                let end = min(start + size, data.count)
                guard start < end else { return Data() }
                return data.subdata(in: start..<end)
            }
        }
    }

    private static func makeDocumentEntries(elements: [WordElement], title: String) -> [DocumentEntry] {
        [
            DocumentEntry(path: "[Content_Types].xml", content: contentTypesXML()),
            DocumentEntry(path: "_rels/.rels", content: rootRelationshipsXML()),
            DocumentEntry(path: "docProps/app.xml", content: appPropertiesXML()),
            DocumentEntry(path: "docProps/core.xml", content: corePropertiesXML(title: title)),
            DocumentEntry(path: "word/styles.xml", content: stylesXML()),
            DocumentEntry(path: "word/numbering.xml", content: numberingXML()),
            DocumentEntry(path: "word/_rels/document.xml.rels", content: documentRelationshipsXML()),
            DocumentEntry(path: "word/document.xml", content: documentXML(elements: elements))
        ]
    }

    private static func documentXML(elements: [WordElement]) -> String {
        let body = elements.map(\.xml).joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <w:body>
        \(body)
            <w:sectPr>
              <w:pgSz w:w="12240" w:h="15840"/>
              <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>
              <w:cols w:space="720"/>
              <w:docGrid w:linePitch="360"/>
            </w:sectPr>
          </w:body>
        </w:document>
        """
    }

    private static func contentTypesXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
          <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
          <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
          <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
          <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
        </Types>
        """
    }

    private static func rootRelationshipsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
          <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
        </Relationships>
        """
    }

    private static func documentRelationshipsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
        </Relationships>
        """
    }

    private static func appPropertiesXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
          <Application>NexaFlow</Application>
          <DocSecurity>0</DocSecurity>
          <ScaleCrop>false</ScaleCrop>
          <Company>Local</Company>
          <LinksUpToDate>false</LinksUpToDate>
          <SharedDoc>false</SharedDoc>
          <HyperlinksChanged>false</HyperlinksChanged>
          <AppVersion>1.0</AppVersion>
        </Properties>
        """
    }

    private static func corePropertiesXML(title: String) -> String {
        let now = ISO8601DateFormatter().string(from: Date())
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:title>\(xmlEscape(title))</dc:title>
          <dc:creator>NexaFlow</dc:creator>
          <cp:lastModifiedBy>NexaFlow</cp:lastModifiedBy>
          <dcterms:created xsi:type="dcterms:W3CDTF">\(now)</dcterms:created>
          <dcterms:modified xsi:type="dcterms:W3CDTF">\(now)</dcterms:modified>
        </cp:coreProperties>
        """
    }

    private static func stylesXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:docDefaults>
            <w:rPrDefault>
              <w:rPr>
                <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="PingFang SC"/>
                <w:sz w:val="21"/>
                <w:szCs w:val="21"/>
                <w:color w:val="1F2937"/>
              </w:rPr>
            </w:rPrDefault>
            <w:pPrDefault>
              <w:pPr>
                <w:spacing w:after="120" w:line="300" w:lineRule="auto"/>
              </w:pPr>
            </w:pPrDefault>
          </w:docDefaults>
          <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
            <w:name w:val="Normal"/>
            <w:qFormat/>
          </w:style>
          <w:style w:type="paragraph" w:styleId="Title">
            <w:name w:val="Title"/>
            <w:basedOn w:val="Normal"/>
            <w:next w:val="Normal"/>
            <w:qFormat/>
            <w:pPr><w:spacing w:after="280"/></w:pPr>
            <w:rPr>
              <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="PingFang SC"/>
              <w:b/>
              <w:color w:val="1F4D78"/>
              <w:sz w:val="42"/>
            </w:rPr>
          </w:style>
          <w:style w:type="paragraph" w:styleId="Heading1">
            <w:name w:val="heading 1"/>
            <w:basedOn w:val="Normal"/>
            <w:next w:val="Normal"/>
            <w:qFormat/>
            <w:pPr>
              <w:keepNext/>
              <w:spacing w:before="320" w:after="160"/>
              <w:outlineLvl w:val="0"/>
            </w:pPr>
            <w:rPr>
              <w:b/>
              <w:color w:val="2E74B5"/>
              <w:sz w:val="30"/>
            </w:rPr>
          </w:style>
          <w:style w:type="paragraph" w:styleId="Heading2">
            <w:name w:val="heading 2"/>
            <w:basedOn w:val="Normal"/>
            <w:next w:val="Normal"/>
            <w:qFormat/>
            <w:pPr>
              <w:keepNext/>
              <w:spacing w:before="220" w:after="120"/>
              <w:outlineLvl w:val="1"/>
            </w:pPr>
            <w:rPr>
              <w:b/>
              <w:color w:val="1F4D78"/>
              <w:sz w:val="24"/>
            </w:rPr>
          </w:style>
          <w:style w:type="paragraph" w:styleId="BodyText">
            <w:name w:val="Body Text"/>
            <w:basedOn w:val="Normal"/>
            <w:pPr><w:spacing w:after="140" w:line="300" w:lineRule="auto"/></w:pPr>
          </w:style>
          <w:style w:type="table" w:default="1" w:styleId="TableGrid">
            <w:name w:val="Table Grid"/>
            <w:tblPr>
              <w:tblBorders>
                <w:top w:val="single" w:sz="4" w:space="0" w:color="D0D5DD"/>
                <w:left w:val="single" w:sz="4" w:space="0" w:color="D0D5DD"/>
                <w:bottom w:val="single" w:sz="4" w:space="0" w:color="D0D5DD"/>
                <w:right w:val="single" w:sz="4" w:space="0" w:color="D0D5DD"/>
                <w:insideH w:val="single" w:sz="4" w:space="0" w:color="EAECF0"/>
                <w:insideV w:val="single" w:sz="4" w:space="0" w:color="EAECF0"/>
              </w:tblBorders>
              <w:tblCellMar>
                <w:top w:w="80" w:type="dxa"/>
                <w:left w:w="120" w:type="dxa"/>
                <w:bottom w:w="80" w:type="dxa"/>
                <w:right w:w="120" w:type="dxa"/>
              </w:tblCellMar>
            </w:tblPr>
          </w:style>
        </w:styles>
        """
    }

    private static func numberingXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:abstractNum w:abstractNumId="1">
            <w:multiLevelType w:val="hybridMultilevel"/>
            <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="•"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="360" w:hanging="180"/></w:pPr></w:lvl>
            <w:lvl w:ilvl="1"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="◦"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="720" w:hanging="180"/></w:pPr></w:lvl>
            <w:lvl w:ilvl="2"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="▪"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="1080" w:hanging="180"/></w:pPr></w:lvl>
          </w:abstractNum>
          <w:abstractNum w:abstractNumId="2">
            <w:multiLevelType w:val="hybridMultilevel"/>
            <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="420" w:hanging="240"/></w:pPr></w:lvl>
            <w:lvl w:ilvl="1"><w:start w:val="1"/><w:numFmt w:val="lowerLetter"/><w:lvlText w:val="%2."/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="840" w:hanging="240"/></w:pPr></w:lvl>
          </w:abstractNum>
          <w:num w:numId="1"><w:abstractNumId w:val="1"/></w:num>
          <w:num w:numId="2"><w:abstractNumId w:val="2"/></w:num>
        </w:numbering>
        """
    }
}

private enum WordExportError: LocalizedError {
    case cannotCreateArchive

    var errorDescription: String? {
        switch self {
        case .cannotCreateArchive:
            return "无法创建 Word 文档压缩包"
        }
    }
}

private struct DocumentEntry {
    let path: String
    let content: String
}

private enum WordElement {
    case paragraph(WordParagraph)
    case table(WordTable)

    var xml: String {
        switch self {
        case .paragraph(let paragraph):
            return paragraph.xml
        case .table(let table):
            return table.xml
        }
    }
}

private struct WordParagraph {
    var text: String
    var style: String = "BodyText"
    var bold: Bool = false
    var color: String?
    var listKind: WordListKind?
    var listLevel: Int = 0
    var keepNext: Bool = false

    var xml: String {
        let styleXML = "<w:pStyle w:val=\"\(style)\"/>"
        let keepXML = keepNext ? "<w:keepNext/>" : ""
        let numberingXML: String
        if let listKind {
            numberingXML = "<w:numPr><w:ilvl w:val=\"\(min(max(listLevel, 0), 2))\"/><w:numId w:val=\"\(listKind.numId)\"/></w:numPr>"
        } else {
            numberingXML = ""
        }
        let paragraphProps = "<w:pPr>\(styleXML)\(keepXML)\(numberingXML)</w:pPr>"
        let runProps = [
            bold ? "<w:b/>" : "",
            color.map { "<w:color w:val=\"\($0)\"/>" } ?? ""
        ].joined()
        return """
            <w:p>\(paragraphProps)<w:r><w:rPr>\(runProps)</w:rPr><w:t xml:space="preserve">\(xmlEscape(text))</w:t></w:r></w:p>
        """
    }
}

private enum WordListKind {
    case bullet
    case numbered

    var numId: Int {
        switch self {
        case .bullet: return 1
        case .numbered: return 2
        }
    }
}

private struct WordTable {
    var columns: [WordTableColumn]
    var rows: [[String]]
    var headerFill: String = "F2F4F7"

    var xml: String {
        guard !columns.isEmpty else { return "" }
        let grid = columns.map { "<w:gridCol w:w=\"\($0.width)\"/>" }.joined()
        let headerRow = rowXML(columns.map(\.title), isHeader: true)
        let bodyRows = rows.map { rowXML($0, isHeader: false) }.joined(separator: "\n")
        return """
            <w:tbl>
              <w:tblPr>
                <w:tblStyle w:val="TableGrid"/>
                <w:tblW w:w="9360" w:type="dxa"/>
                <w:tblInd w:w="0" w:type="dxa"/>
                <w:tblLayout w:type="fixed"/>
                <w:tblLook w:firstRow="1" w:lastRow="0" w:firstColumn="0" w:lastColumn="0" w:noHBand="0" w:noVBand="1"/>
              </w:tblPr>
              <w:tblGrid>\(grid)</w:tblGrid>
        \(headerRow)
        \(bodyRows)
            </w:tbl>
        """
    }

    private func rowXML(_ values: [String], isHeader: Bool) -> String {
        let cells = columns.enumerated().map { index, column in
            let value = index < values.count ? values[index] : ""
            return cellXML(value, width: column.width, isHeader: isHeader)
        }.joined(separator: "\n")
        let cantSplit = "<w:trPr><w:cantSplit/>\(isHeader ? "<w:tblHeader/>" : "")</w:trPr>"
        return "<w:tr>\(cantSplit)\n\(cells)\n</w:tr>"
    }

    private func cellXML(_ value: String, width: Int, isHeader: Bool) -> String {
        let fill = isHeader ? "<w:shd w:fill=\"\(headerFill)\"/>" : ""
        let paragraphs = splitCellParagraphs(value).map { part in
            WordParagraph(
                text: part,
                style: "Normal",
                bold: isHeader,
                color: isHeader ? "344054" : nil
            ).xml
        }.joined()
        return """
          <w:tc>
            <w:tcPr>
              <w:tcW w:w="\(width)" w:type="dxa"/>
              <w:vAlign w:val="top"/>
              \(fill)
            </w:tcPr>
            \(paragraphs)
          </w:tc>
        """
    }
}

private struct WordTableColumn {
    var title: String
    var width: Int
}

private struct ParsedReportDocument {
    var title: String
    var introLines: [String]
    var sections: [ParsedSection]
}

private struct ParsedSection {
    var title: String
    var lines: [String]

    var cleanTitle: String {
        title.replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression)
    }
}

private struct ReportDocumentBuilder {
    let packName: String
    private(set) var title = "产品迭代决策报告"

    func buildElements(markdown: String, aiSupplement: String) -> [WordElement] {
        let combined = combinedMarkdown(markdown: markdown, aiSupplement: aiSupplement)
        let document = parseDocument(combined)
        var output: [WordElement] = []

        output.append(.paragraph(WordParagraph(text: document.title, style: "Title", bold: true)))
        if !document.introLines.isEmpty {
            output.append(.paragraph(WordParagraph(text: "报告信息", style: "Heading1", bold: true, keepNext: true)))
            output.append(.table(keyValueTable(rows: keyValueRows(from: document.introLines, fallbackKey: "信息"))))
        }

        for section in document.sections {
            output.append(contentsOf: elements(for: section))
        }

        return output
    }

    private func combinedMarkdown(markdown: String, aiSupplement: String) -> String {
        var parts = [markdown.trimmingCharacters(in: .whitespacesAndNewlines)]
        let supplement = aiSupplement.trimmingCharacters(in: .whitespacesAndNewlines)
        if !supplement.isEmpty {
            parts.append("## AI 补充分析\n\(supplement)")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private func parseDocument(_ markdown: String) -> ParsedReportDocument {
        var title = "产品迭代决策报告 - \(packName)"
        var introLines: [String] = []
        var sections: [ParsedSection] = []
        var currentTitle: String?
        var currentLines: [String] = []
        var hasSeenSection = false

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("# ") {
                title = String(line.dropFirst(2)).trimmed
                continue
            }
            if line.hasPrefix("## ") {
                if let currentTitle {
                    sections.append(ParsedSection(title: currentTitle, lines: currentLines))
                }
                currentTitle = String(line.dropFirst(3)).trimmed
                currentLines = []
                hasSeenSection = true
                continue
            }
            guard !line.isEmpty else { continue }
            if hasSeenSection {
                currentLines.append(rawLine)
            } else {
                introLines.append(line)
            }
        }

        if let currentTitle {
            sections.append(ParsedSection(title: currentTitle, lines: currentLines))
        }

        return ParsedReportDocument(title: title, introLines: introLines, sections: sections)
    }

    private func elements(for section: ParsedSection) -> [WordElement] {
        let title = section.title
        let cleanTitle = section.cleanTitle
        var elements: [WordElement] = [
            .paragraph(WordParagraph(text: title, style: "Heading1", bold: true, keepNext: true))
        ]

        switch cleanTitle {
        case let value where value.contains("表格数据趋势"):
            elements.append(contentsOf: trendElements(from: section.lines))
        case let value where value.contains("指标级多表联动"):
            elements.append(.table(WordTable(
                columns: [
                    WordTableColumn(title: "指标关系", width: 3600),
                    WordTableColumn(title: "证据与置信度", width: 5760)
                ],
                rows: splitRows(from: bulletTexts(from: section.lines))
            )))
        case let value where value.contains("业务链路"):
            elements.append(.table(twoColumnTable(firstTitle: "链路对象", secondTitle: "影响关系与证据", rows: splitRows(from: bulletTexts(from: section.lines)))))
        case let value where value.contains("综合上下文信号"):
            elements.append(contentsOf: contextSignalElements(from: section.lines))
        case let value where value.contains("时间线匹配证据"):
            elements.append(contentsOf: evidenceElements(from: section.lines))
        case let value where value.contains("关键数据变化"):
            elements.append(.table(twoColumnTable(firstTitle: "变化项", secondTitle: "说明", rows: splitRows(from: bulletTexts(from: section.lines)))))
        case let value where value.contains("知识库产品文档") || value.contains("事件轴"):
            elements.append(contentsOf: knowledgeEventElements(from: section.lines))
        case let value where value.contains("竞品") || value.contains("政策") || value.contains("市场参照"):
            elements.append(contentsOf: referenceElements(from: section.lines))
        case let value where value.contains("已应用纠偏记忆"):
            elements.append(.table(twoColumnTable(firstTitle: "对象", secondTitle: "纠偏说明", rows: splitRows(from: bulletTexts(from: section.lines)))))
        case let value where value.contains("仍需补充的数据"):
            elements.append(.table(numberedTable(title: "需要补充的数据", values: bulletTexts(from: section.lines))))
        case let value where value.contains("验证方式"):
            elements.append(.table(keyValueTable(rows: keyValueRows(from: bulletTexts(from: section.lines), fallbackKey: "项目"))))
        case let value where value.contains("最后结论"):
            elements.append(contentsOf: conclusionElements(from: section.lines))
        case let value where value.contains("人工决策"):
            elements.append(.table(keyValueTable(rows: keyValueRows(from: bulletTexts(from: section.lines), fallbackKey: "项目"))))
        default:
            elements.append(contentsOf: genericElements(from: section.lines))
        }

        return elements
    }

    private func trendElements(from lines: [String]) -> [WordElement] {
        var elements: [WordElement] = []
        let paragraphs = plainParagraphs(from: lines)
        for paragraph in paragraphs {
            elements.append(.paragraph(WordParagraph(text: paragraph)))
        }
        let rows = trendRows(from: bulletTexts(from: lines))
        if rows.isEmpty {
            elements.append(contentsOf: genericElements(from: lines))
        } else {
            elements.append(.table(WordTable(
                columns: [
                    WordTableColumn(title: "对象", width: 3000),
                    WordTableColumn(title: "趋势或说明", width: 6360)
                ],
                rows: rows
            )))
        }
        return elements
    }

    private func contextSignalElements(from lines: [String]) -> [WordElement] {
        let rows = contextRows(from: bulletTexts(from: lines))
        guard !rows.isEmpty else { return genericElements(from: lines) }
        return [
            .table(WordTable(
                columns: [
                    WordTableColumn(title: "日期", width: 1450),
                    WordTableColumn(title: "类型", width: 1350),
                    WordTableColumn(title: "信号", width: 2600),
                    WordTableColumn(title: "说明/来源", width: 3960)
                ],
                rows: rows
            ))
        ]
    }

    private func evidenceElements(from lines: [String]) -> [WordElement] {
        let rows = evidenceRows(from: bulletTexts(from: lines))
        guard !rows.isEmpty else { return genericElements(from: lines) }
        return [
            .table(WordTable(
                columns: [
                    WordTableColumn(title: "证据", width: 3000),
                    WordTableColumn(title: "说明", width: 6360)
                ],
                rows: rows
            ))
        ]
    }

    private func knowledgeEventElements(from lines: [String]) -> [WordElement] {
        let rows = knowledgeRows(from: bulletTexts(from: lines))
        guard !rows.isEmpty else { return genericElements(from: lines) }
        return [
            .table(WordTable(
                columns: [
                    WordTableColumn(title: "日期/时间线", width: 2000),
                    WordTableColumn(title: "事件", width: 3100),
                    WordTableColumn(title: "说明/来源", width: 4260)
                ],
                rows: rows
            ))
        ]
    }

    private func referenceElements(from lines: [String]) -> [WordElement] {
        let rows = referenceRows(from: bulletTexts(from: lines))
        guard !rows.isEmpty else { return genericElements(from: lines) }
        return [
            .table(WordTable(
                columns: [
                    WordTableColumn(title: "类型", width: 1450),
                    WordTableColumn(title: "标题", width: 3000),
                    WordTableColumn(title: "摘要", width: 4910)
                ],
                rows: rows
            ))
        ]
    }

    private func conclusionElements(from lines: [String]) -> [WordElement] {
        var elements: [WordElement] = []
        let normalized = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var index = 0
        var findingRows: [[String]] = []
        var opportunityRows: [[String]] = []
        var otherRows: [[String]] = []

        while index < normalized.count {
            let rawLine = normalized[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if let bullet = bulletText(from: rawLine), rawLine.leadingWhitespaceCount < 2 {
                var nested: [String] = []
                var cursor = index + 1
                while cursor < normalized.count {
                    let next = normalized[cursor]
                    if next.leadingWhitespaceCount >= 2, let nestedText = bulletText(from: next) {
                        nested.append(nestedText)
                        cursor += 1
                    } else {
                        break
                    }
                }

                if bullet.hasPrefix("可选产品方案") {
                    for item in nested {
                        let row = splitFirst(item)
                        opportunityRows.append([row.0, row.1])
                    }
                    if nested.isEmpty {
                        let row = splitFirst(bullet)
                        otherRows.append([row.0, row.1])
                    }
                } else if bullet.hasPrefix("推荐方案") {
                    let row = splitFirst(bullet)
                    otherRows.append([row.0, row.1])
                } else if nested.contains(where: { $0.hasPrefix("证据等级") || $0.hasPrefix("主要判断") || $0.hasPrefix("置信度") }) {
                    let evidence = nested.valueAfterPrefix("证据等级")
                    let judgement = nested.valueAfterPrefix("主要判断")
                    let confidence = nested.valueAfterPrefix("置信度")
                    findingRows.append([bullet, emptyToDash(evidence), emptyToDash(judgement), emptyToDash(confidence)])
                } else {
                    let row = splitFirst(bullet)
                    otherRows.append([row.0, row.1])
                }
                index = cursor
            } else {
                elements.append(.paragraph(WordParagraph(text: trimmed)))
                index += 1
            }
        }

        if !findingRows.isEmpty {
            elements.append(.paragraph(WordParagraph(text: "归因观察", style: "Heading2", bold: true, keepNext: true)))
            elements.append(.table(WordTable(
                columns: [
                    WordTableColumn(title: "观察", width: 2500),
                    WordTableColumn(title: "证据等级", width: 1700),
                    WordTableColumn(title: "主要判断", width: 3900),
                    WordTableColumn(title: "置信度", width: 1260)
                ],
                rows: findingRows
            )))
        }

        if !opportunityRows.isEmpty {
            elements.append(.paragraph(WordParagraph(text: "可选产品方案", style: "Heading2", bold: true, keepNext: true)))
            elements.append(.table(twoColumnTable(firstTitle: "方案", secondTitle: "依据与影响", rows: opportunityRows)))
        }

        if !otherRows.isEmpty {
            elements.append(.paragraph(WordParagraph(text: "决策提示", style: "Heading2", bold: true, keepNext: true)))
            elements.append(.table(twoColumnTable(firstTitle: "项目", secondTitle: "说明", rows: otherRows)))
        }

        return elements.isEmpty ? genericElements(from: lines) : elements
    }

    private func genericElements(from lines: [String]) -> [WordElement] {
        var elements: [WordElement] = []
        var index = 0
        while index < lines.count {
            if let parsed = markdownTable(from: lines, startingAt: index) {
                elements.append(.table(parsed.table))
                index = parsed.nextIndex
                continue
            }
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                index += 1
                continue
            }
            if trimmed.hasPrefix("### ") {
                elements.append(.paragraph(WordParagraph(text: String(trimmed.dropFirst(4)).trimmed, style: "Heading2", bold: true, keepNext: true)))
            } else if let bullet = bulletText(from: line) {
                elements.append(.paragraph(WordParagraph(
                    text: bullet,
                    listKind: .bullet,
                    listLevel: line.leadingWhitespaceCount / 2
                )))
            } else if let numbered = numberedText(from: trimmed) {
                elements.append(.paragraph(WordParagraph(text: numbered, listKind: .numbered)))
            } else {
                elements.append(.paragraph(WordParagraph(text: trimmed)))
            }
            index += 1
        }
        return elements
    }

    private func markdownTable(from lines: [String], startingAt index: Int) -> (table: WordTable, nextIndex: Int)? {
        guard index + 1 < lines.count else { return nil }
        let header = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard isMarkdownTableRow(header), isMarkdownTableSeparator(separator) else { return nil }
        let titles = markdownCells(from: header)
        guard !titles.isEmpty else { return nil }

        var cursor = index + 2
        var rows: [[String]] = []
        while cursor < lines.count {
            let line = lines[cursor].trimmingCharacters(in: .whitespacesAndNewlines)
            guard isMarkdownTableRow(line) else { break }
            var cells = markdownCells(from: line)
            if cells.count < titles.count {
                cells.append(contentsOf: Array(repeating: "", count: titles.count - cells.count))
            }
            rows.append(cells.prefix(titles.count).map { cleanCellText($0, maxLength: 900) })
            cursor += 1
        }

        let width = max(900, 9360 / max(1, titles.count))
        return (
            WordTable(
                columns: titles.map { WordTableColumn(title: cleanCellText($0, maxLength: 80), width: width) },
                rows: rows.isEmpty ? [Array(repeating: "-", count: titles.count)] : rows
            ),
            cursor
        )
    }

    private func isMarkdownTableRow(_ line: String) -> Bool {
        line.hasPrefix("|") && line.hasSuffix("|") && line.filter { $0 == "|" }.count >= 2
    }

    private func isMarkdownTableSeparator(_ line: String) -> Bool {
        guard isMarkdownTableRow(line) else { return false }
        let cells = markdownCells(from: line)
        return !cells.isEmpty && cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: CharacterSet(charactersIn: " :-"))
            return trimmed.isEmpty && cell.contains("-")
        }
    }

    private func markdownCells(from line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func plainParagraphs(from lines: [String]) -> [String] {
        lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, bulletText(from: line) == nil, numberedText(from: trimmed) == nil else {
                return nil
            }
            return trimmed
        }
    }

    private func bulletTexts(from lines: [String]) -> [String] {
        lines.compactMap { bulletText(from: $0) }
    }

    private func bulletText(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("- ") {
            return String(trimmed.dropFirst(2)).trimmed
        }
        if trimmed.hasPrefix("• ") {
            return String(trimmed.dropFirst(2)).trimmed
        }
        return nil
    }

    private func numberedText(from trimmed: String) -> String? {
        guard let range = trimmed.range(of: #"^\d+[\.)]\s+"#, options: .regularExpression) else {
            return nil
        }
        return String(trimmed[range.upperBound...]).trimmed
    }

    private func keyValueRows(from lines: [String], fallbackKey: String) -> [[String]] {
        let rows = lines.map { splitFirst($0, fallbackKey: fallbackKey) }
        return rows.map { [emptyToDash($0.0), emptyToDash($0.1)] }
    }

    private func trendRows(from bullets: [String]) -> [[String]] {
        bullets.map { text in
            let parts = text.components(separatedBy: "：")
            if parts.count >= 3, parts[0].localizedCaseInsensitiveContains(".csv") || parts[0].localizedCaseInsensitiveContains(".xlsx") || parts[0].localizedCaseInsensitiveContains(".xls") {
                return [cleanCellText("\(parts[0]) / \(parts[1])", maxLength: 140), cleanCellText(parts.dropFirst(2).joined(separator: "："), maxLength: 900)]
            }
            let row = splitFirst(text)
            return [cleanCellText(row.0, maxLength: 180), cleanCellText(row.1, maxLength: 900)]
        }
    }

    private func contextRows(from bullets: [String]) -> [[String]] {
        bullets.map { text in
            let parts = text.components(separatedBy: "；").map(\.trimmed).filter { !$0.isEmpty }
            if parts.count >= 4 {
                return [
                    cleanCellText(parts[0], maxLength: 60),
                    cleanCellText(parts[1].strippingBrackets, maxLength: 80),
                    cleanCellText(parts[2], maxLength: 160),
                    cleanCellText(parts.dropFirst(3).joined(separator: "；"), maxLength: 900)
                ]
            }
            let row = splitFirst(text)
            return ["-", cleanCellText(row.0, maxLength: 120), cleanCellText(row.1, maxLength: 180), cleanCellText(text, maxLength: 900)]
        }
    }

    private func evidenceRows(from bullets: [String]) -> [[String]] {
        bullets.map { text in
            let row = splitFirst(text)
            return [cleanCellText(row.0, maxLength: 240), cleanCellText(row.1, maxLength: 900)]
        }
    }

    private func knowledgeRows(from bullets: [String]) -> [[String]] {
        bullets.map { text in
            let parts = text.components(separatedBy: "；").map(\.trimmed).filter { !$0.isEmpty }
            guard let first = parts.first else { return ["-", "-", "-"] }
            let dateAndEvent = first.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "　" })
            let dateText = dateAndEvent.first.map(String.init) ?? "-"
            let eventText = dateAndEvent.count > 1 ? String(dateAndEvent[1]) : first
            return [
                cleanCellText(dateText, maxLength: 100),
                cleanCellText(eventText, maxLength: 220),
                cleanCellText(parts.dropFirst().joined(separator: "；"), maxLength: 1000)
            ]
        }
    }

    private func referenceRows(from bullets: [String]) -> [[String]] {
        bullets.map { text in
            var type = "-"
            var remainder = text
            if text.hasPrefix("[") {
                let parts = text.components(separatedBy: "]")
                if parts.count >= 2 {
                    type = parts[0].replacingOccurrences(of: "[", with: "")
                    remainder = parts.dropFirst().joined(separator: "]").trimmed
                }
            }
            let row = splitFirst(remainder)
            return [
                cleanCellText(type, maxLength: 80),
                cleanCellText(row.0, maxLength: 180),
                cleanCellText(row.1, maxLength: 900)
            ]
        }
    }

    private func splitRows(from values: [String]) -> [[String]] {
        values.map { value in
            let row = splitFirst(value)
            return [cleanCellText(row.0, maxLength: 200), cleanCellText(row.1, maxLength: 900)]
        }
    }

    private func splitFirst(_ text: String, fallbackKey: String = "项目") -> (String, String) {
        for separator in ["：", ":"] {
            if let range = text.range(of: separator) {
                let key = String(text[..<range.lowerBound]).trimmed
                let value = String(text[range.upperBound...]).trimmed
                return (key.isEmpty ? fallbackKey : key, value.isEmpty ? text.trimmed : value)
            }
        }
        return (fallbackKey, text.trimmed)
    }

    private func keyValueTable(rows: [[String]]) -> WordTable {
        WordTable(
            columns: [
                WordTableColumn(title: "项目", width: 2200),
                WordTableColumn(title: "内容", width: 7160)
            ],
            rows: rows
        )
    }

    private func twoColumnTable(firstTitle: String, secondTitle: String, rows: [[String]]) -> WordTable {
        WordTable(
            columns: [
                WordTableColumn(title: firstTitle, width: 3000),
                WordTableColumn(title: secondTitle, width: 6360)
            ],
            rows: rows.isEmpty ? [["-", "暂无。"]] : rows
        )
    }

    private func numberedTable(title: String, values: [String]) -> WordTable {
        let rows = values.enumerated().map { index, value in
            [String(index + 1), cleanCellText(value, maxLength: 900)]
        }
        return WordTable(
            columns: [
                WordTableColumn(title: "序号", width: 900),
                WordTableColumn(title: title, width: 8460)
            ],
            rows: rows.isEmpty ? [["-", "暂无。"]] : rows
        )
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var strippingBrackets: String {
        trimmingCharacters(in: CharacterSet(charactersIn: "[]【】"))
    }

    var leadingWhitespaceCount: Int {
        var count = 0
        for character in self {
            if character == " " || character == "\t" {
                count += character == "\t" ? 2 : 1
            } else {
                break
            }
        }
        return count
    }
}

private extension Array where Element == String {
    func valueAfterPrefix(_ prefix: String) -> String {
        for item in self {
            let trimmed = item.trimmed
            if trimmed.hasPrefix(prefix) {
                for separator in ["：", ":"] {
                    if let range = trimmed.range(of: separator) {
                        return String(trimmed[range.upperBound...]).trimmed
                    }
                }
                return String(trimmed.dropFirst(prefix.count)).trimmed
            }
        }
        return ""
    }
}

private func splitCellParagraphs(_ text: String) -> [String] {
    let parts = text
        .components(separatedBy: .newlines)
        .map(\.trimmed)
        .filter { !$0.isEmpty }
    return parts.isEmpty ? ["-"] : parts
}

private func cleanCellText(_ value: String, maxLength: Int) -> String {
    let normalized = value
        .replacingOccurrences(of: "\t", with: " ")
        .replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
        .trimmed
    guard normalized.count > maxLength else { return emptyToDash(normalized) }
    return String(normalized.prefix(maxLength)).trimmed + "..."
}

private func emptyToDash(_ value: String) -> String {
    let trimmed = value.trimmed
    return trimmed.isEmpty ? "-" : trimmed
}

private func xmlEscape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}
