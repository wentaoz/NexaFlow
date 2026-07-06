import Foundation

enum ImportedReportSourceType: String, Codable, Hashable {
    case localFile
    case tableau

    var label: String {
        switch self {
        case .localFile: return "本地文件"
        case .tableau: return "Tableau"
        }
    }
}

struct ImportedReportSourceMetadata: Codable, Hashable {
    var sourceType: ImportedReportSourceType
    var baseURL: String
    var siteContentURL: String
    var projectID: String
    var projectName: String
    var workbookID: String
    var workbookName: String
    var viewID: String
    var viewName: String
    var importMode: String
    var importedAt: Date
    var limitation: String

    init(
        sourceType: ImportedReportSourceType = .localFile,
        baseURL: String = "",
        siteContentURL: String = "",
        projectID: String = "",
        projectName: String = "",
        workbookID: String = "",
        workbookName: String = "",
        viewID: String = "",
        viewName: String = "",
        importMode: String = "",
        importedAt: Date = Date(),
        limitation: String = ""
    ) {
        self.sourceType = sourceType
        self.baseURL = baseURL
        self.siteContentURL = siteContentURL
        self.projectID = projectID
        self.projectName = projectName
        self.workbookID = workbookID
        self.workbookName = workbookName
        self.viewID = viewID
        self.viewName = viewName
        self.importMode = importMode
        self.importedAt = importedAt
        self.limitation = limitation
    }

    var stableImportKey: String? {
        guard sourceType == .tableau, !viewID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return [
            sourceType.rawValue,
            baseURL.normalizedKey,
            siteContentURL.normalizedKey,
            viewID.normalizedKey
        ].joined(separator: "|")
    }

    var displaySummary: String {
        guard sourceType == .tableau else { return sourceType.label }
        let location = [projectName.nilIfBlank, workbookName.nilIfBlank, viewName.nilIfBlank]
            .compactMap { $0 }
            .joined(separator: " / ")
        return location.isEmpty ? "Tableau 视图导出" : "Tableau：\(location)"
    }

    var aiContextDescription: String {
        guard sourceType == .tableau else { return "来源：\(sourceType.label)" }
        return [
            "来源：Tableau 视图导出",
            "Project：\(projectName.nilIfBlank ?? "未记录")",
            "Workbook：\(workbookName.nilIfBlank ?? "未记录")",
            "View：\(viewName.nilIfBlank ?? "未记录")",
            "导入时间：\(DateFormatting.shortDateTime.string(from: importedAt))",
            "限制：\(limitation.nilIfBlank ?? "当前读取的是视图导出数据，不一定等同 Tableau 底层完整数据。")"
        ].joined(separator: "；")
    }
}

extension DataPack {
    var tableauReportCount: Int {
        importedReports.filter { report in
            report.sourceMetadata?.sourceType == .tableau || report.sourceFormat == .tableau
        }.count
    }

    var localReportCount: Int {
        max(importedReports.count - tableauReportCount, 0)
    }

    var reportSourceSummary: String {
        guard !importedReports.isEmpty else { return "暂无报表" }
        var parts = ["共 \(importedReports.count) 张报表"]
        if tableauReportCount > 0 {
            parts.append("Tableau \(tableauReportCount) 张")
        }
        if localReportCount > 0 {
            parts.append("本地 \(localReportCount) 张")
        }
        return parts.joined(separator: " · ")
    }
}

struct TableauSourceDraft: Hashable {
    var displayName = ""
    var baseURL = ""
    var siteContentURL = ""
    var patName = ""
    var patToken = ""
    var projectFilter = ""
    var workbookFilter = ""
}

struct TableauSource: Identifiable, Codable, Hashable {
    var id: UUID
    var businessSpaceID: UUID
    var displayName: String
    var baseURL: String
    var siteContentURL: String
    var patName: String
    var patToken: String
    var projectFilter: String
    var workbookFilter: String
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastTestedAt: Date?
    var lastImportAt: Date?
    var lastStatusMessage: String

    init(
        id: UUID = UUID(),
        businessSpaceID: UUID,
        displayName: String,
        baseURL: String,
        siteContentURL: String = "",
        patName: String,
        patToken: String,
        projectFilter: String = "",
        workbookFilter: String = "",
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastTestedAt: Date? = nil,
        lastImportAt: Date? = nil,
        lastStatusMessage: String = ""
    ) {
        self.id = id
        self.businessSpaceID = businessSpaceID
        self.displayName = displayName
        self.baseURL = baseURL
        self.siteContentURL = siteContentURL
        self.patName = patName
        self.patToken = patToken
        self.projectFilter = projectFilter
        self.workbookFilter = workbookFilter
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastTestedAt = lastTestedAt
        self.lastImportAt = lastImportAt
        self.lastStatusMessage = lastStatusMessage
    }
}

struct TableauProject: Identifiable, Hashable {
    var id: String
    var name: String
}

struct TableauWorkbook: Identifiable, Hashable {
    var id: String
    var name: String
    var projectID: String
    var projectName: String
}

struct TableauView: Identifiable, Hashable {
    var id: String
    var name: String
    var workbookID: String
    var workbookName: String
    var projectID: String
    var projectName: String
}

struct TableauCatalog: Hashable {
    var projects: [TableauProject]
    var workbooks: [TableauWorkbook]
    var views: [TableauView]
}

struct TableauImportResult {
    var reports: [ImportedReport]
    var fieldDefinitions: [ReportFieldDefinition]
    var importedViewCount: Int
}

struct TableauSyncRecord: Identifiable, Codable, Hashable {
    enum Status: String, Codable, Hashable {
        case success
        case failed

        var label: String {
            switch self {
            case .success: return "成功"
            case .failed: return "失败"
            }
        }
    }

    var id: UUID
    var sourceID: UUID
    var businessSpaceID: UUID
    var dataPackID: UUID?
    var startedAt: Date
    var finishedAt: Date
    var status: Status
    var importedViewCount: Int
    var message: String

    init(
        id: UUID = UUID(),
        sourceID: UUID,
        businessSpaceID: UUID,
        dataPackID: UUID? = nil,
        startedAt: Date = Date(),
        finishedAt: Date = Date(),
        status: Status,
        importedViewCount: Int,
        message: String
    ) {
        self.id = id
        self.sourceID = sourceID
        self.businessSpaceID = businessSpaceID
        self.dataPackID = dataPackID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.importedViewCount = importedViewCount
        self.message = message
    }
}
