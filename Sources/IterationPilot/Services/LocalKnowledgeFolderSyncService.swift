import Foundation
import PDFKit
import ZIPFoundation

struct LocalKnowledgeParsedFile {
    var url: URL
    var title: String
    var summary: String
    var modifiedAt: Date?
    var fileExtension: String
}

enum LocalKnowledgeFolderSyncService {
    static let supportedExtensions: Set<String> = [
        "csv", "xlsx", "xls", "md", "txt", "json", "pdf", "docx"
    ]

    static func parseSupportedFiles(in folderURL: URL) -> (files: [LocalKnowledgeParsedFile], totalFiles: Int, failures: [String]) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else {
            return ([], 0, ["无法读取文件夹：\(folderURL.path)"])
        }

        var parsedFiles: [LocalKnowledgeParsedFile] = []
        var failures: [String] = []
        var totalFiles = 0

        for case let fileURL as URL in enumerator {
            do {
                let values = try fileURL.resourceValues(forKeys: Set(keys))
                guard values.isRegularFile == true, values.isHidden != true else { continue }
                totalFiles += 1
                let ext = fileURL.pathExtension.lowercased()
                guard supportedExtensions.contains(ext) else { continue }
                let parsed = try parse(fileURL: fileURL, modifiedAt: values.contentModificationDate)
                parsedFiles.append(parsed)
            } catch {
                failures.append("\(fileURL.lastPathComponent)：\(error.localizedDescription)")
            }
        }

        return (parsedFiles, totalFiles, failures)
    }

    static func knowledgeEntry(
        from parsed: LocalKnowledgeParsedFile,
        source: LocalKnowledgeFolderSource,
        businessSpace: BusinessSpace?
    ) -> KnowledgeEntry {
        let sourceID = sourceID(for: parsed.url, businessSpaceID: source.businessSpaceID)
        let spaceName = businessSpace?.name ?? "当前业务空间"
        let tags = ["本地文件夹", parsed.fileExtension.uppercased(), spaceName].uniqued()
        return KnowledgeEntry(
            id: UUID(),
            createdAt: Date(),
            businessSpaceID: source.businessSpaceID,
            businessDomainIDs: [],
            rootPageID: nil,
            isGlobal: false,
            scenario: "本地文件夹知识",
            problem: parsed.title,
            action: "本地文件：\(parsed.url.path)",
            result: parsed.summary,
            evidenceLevel: .b,
            relatedPackName: source.displayName,
            sourceID: sourceID,
            sourcePath: parsed.url.path,
            sourceURL: parsed.url.absoluteString,
            sourceUpdatedAt: parsed.modifiedAt,
            sourceCreatedAt: parsed.modifiedAt,
            tags: tags
        )
    }

    static func sourceID(for fileURL: URL, businessSpaceID: UUID) -> String {
        "local-folder-\(businessSpaceID.uuidString)-\(fileURL.path.normalizedKey)"
    }

    private static func parse(fileURL: URL, modifiedAt: Date?) throws -> LocalKnowledgeParsedFile {
        let ext = fileURL.pathExtension.lowercased()
        let content: String
        switch ext {
        case "md", "txt", "json", "csv":
            content = try parseTextLikeFile(fileURL)
        case "xlsx", "xls":
            content = try parseSpreadsheet(fileURL)
        case "pdf":
            content = parsePDF(fileURL)
        case "docx":
            content = try parseDOCX(fileURL)
        default:
            content = ""
        }
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return LocalKnowledgeParsedFile(
            url: fileURL,
            title: fileURL.deletingPathExtension().lastPathComponent,
            summary: capped(normalized.isEmpty ? "文件已同步，但未抽取到可读正文。" : normalized, maxLength: 6000),
            modifiedAt: modifiedAt,
            fileExtension: ext
        )
    }

    private static func parseTextLikeFile(_ fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .utf16) {
            return text
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }
        return ""
    }

    private static func parseSpreadsheet(_ fileURL: URL) throws -> String {
        let tables = try ExcelParser.parse(fileURL: fileURL)
        return tables.prefix(8).enumerated().map { index, table in
            let sheet = table.sheetName ?? "Sheet \(index + 1)"
            let headers = table.headers.prefix(40).joined(separator: "、")
            let metrics = table.firstColumnValues.prefix(40).joined(separator: "、")
            return """
            Sheet：\(sheet)
            结构：\(table.shape.label)
            行数：\(table.rawRows.count)
            字段：\(headers)
            首列指标：\(metrics)
            """
        }.joined(separator: "\n\n")
    }

    private static func parsePDF(_ fileURL: URL) -> String {
        guard let document = PDFDocument(url: fileURL) else { return "" }
        let pageLimit = min(document.pageCount, 30)
        return (0..<pageLimit)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
    }

    private static func parseDOCX(_ fileURL: URL) throws -> String {
        let archive = try Archive(url: fileURL, accessMode: .read)
        let documentPaths = ["word/document.xml", "word/footnotes.xml", "word/endnotes.xml"]
        var parts: [String] = []
        for path in documentPaths {
            guard let entry = archive[path] else { continue }
            var data = Data()
            _ = try archive.extract(entry) { chunk in
                data.append(chunk)
            }
            if let xml = String(data: data, encoding: .utf8) {
                parts.append(xmlToPlainText(xml))
            }
        }
        return parts.joined(separator: "\n")
    }

    private static func xmlToPlainText(_ xml: String) -> String {
        xml
            .replacingOccurrences(of: "</w:p>", with: "\n")
            .replacingOccurrences(of: "</w:tr>", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func capped(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        return String(text.prefix(maxLength)) + "\n…（内容已截断，完整文件见本地路径）"
    }
}
