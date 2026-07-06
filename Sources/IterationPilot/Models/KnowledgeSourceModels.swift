import Foundation

enum KnowledgeSourceConnectorType: String, Codable, Hashable, CaseIterable {
    case localFolder
    case confluence
    case jira
    case dingtalk
    case tableau

    var label: String {
        switch self {
        case .localFolder: return "本地文件夹"
        case .confluence: return "Confluence"
        case .jira: return "Jira 项目状态"
        case .dingtalk: return "钉钉在线文档"
        case .tableau: return "Tableau 数据源"
        }
    }
}

enum KnowledgeSourceConnectorStatus: String, Codable, Hashable {
    case available
    case needsAuthorization
    case disabled

    var label: String {
        switch self {
        case .available: return "可用"
        case .needsAuthorization: return "待授权"
        case .disabled: return "已停用"
        }
    }
}

enum KnowledgeSyncSchedule: String, Codable, Hashable, CaseIterable {
    case manual
    case daily1800

    var label: String {
        switch self {
        case .manual: return "手动同步"
        case .daily1800: return "每天 18:00"
        }
    }
}

struct KnowledgeSourceConnector: Identifiable, Codable, Hashable {
    var id: UUID
    var connectorType: KnowledgeSourceConnectorType
    var businessSpaceID: UUID?
    var displayName: String
    var status: KnowledgeSourceConnectorStatus
    var lastSyncAt: Date?
    var syncSchedule: KnowledgeSyncSchedule
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        connectorType: KnowledgeSourceConnectorType,
        businessSpaceID: UUID?,
        displayName: String,
        status: KnowledgeSourceConnectorStatus,
        lastSyncAt: Date? = nil,
        syncSchedule: KnowledgeSyncSchedule = .manual,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.connectorType = connectorType
        self.businessSpaceID = businessSpaceID
        self.displayName = displayName
        self.status = status
        self.lastSyncAt = lastSyncAt
        self.syncSchedule = syncSchedule
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct LocalKnowledgeFolderSource: Identifiable, Codable, Hashable {
    var id: UUID
    var businessSpaceID: UUID
    var displayName: String
    var folderPath: String
    var isEnabled: Bool
    var syncSchedule: KnowledgeSyncSchedule
    var lastSyncAt: Date?
    var lastFileCount: Int
    var lastAddedCount: Int
    var lastUpdatedCount: Int
    var lastFailedCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        businessSpaceID: UUID,
        displayName: String,
        folderPath: String,
        isEnabled: Bool = true,
        syncSchedule: KnowledgeSyncSchedule = .manual,
        lastSyncAt: Date? = nil,
        lastFileCount: Int = 0,
        lastAddedCount: Int = 0,
        lastUpdatedCount: Int = 0,
        lastFailedCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.businessSpaceID = businessSpaceID
        self.displayName = displayName
        self.folderPath = folderPath
        self.isEnabled = isEnabled
        self.syncSchedule = syncSchedule
        self.lastSyncAt = lastSyncAt
        self.lastFileCount = lastFileCount
        self.lastAddedCount = lastAddedCount
        self.lastUpdatedCount = lastUpdatedCount
        self.lastFailedCount = lastFailedCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct LocalKnowledgeFolderSyncRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceID: UUID
    var businessSpaceID: UUID
    var startedAt: Date
    var finishedAt: Date
    var status: ConfluenceSyncStatus
    var totalFiles: Int
    var supportedFiles: Int
    var addedKnowledgeEntries: Int
    var updatedKnowledgeEntries: Int
    var failedFiles: Int
    var message: String

    init(
        id: UUID = UUID(),
        sourceID: UUID,
        businessSpaceID: UUID,
        startedAt: Date,
        finishedAt: Date = Date(),
        status: ConfluenceSyncStatus,
        totalFiles: Int,
        supportedFiles: Int,
        addedKnowledgeEntries: Int,
        updatedKnowledgeEntries: Int,
        failedFiles: Int,
        message: String
    ) {
        self.id = id
        self.sourceID = sourceID
        self.businessSpaceID = businessSpaceID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.totalFiles = totalFiles
        self.supportedFiles = supportedFiles
        self.addedKnowledgeEntries = addedKnowledgeEntries
        self.updatedKnowledgeEntries = updatedKnowledgeEntries
        self.failedFiles = failedFiles
        self.message = message
    }
}

struct DingTalkDocumentSourceDraft: Hashable {
    var displayName = ""
    var clientID = ""
    var clientSecret = ""
    var agentID = ""
    var operatorID = ""
    var defaultSpaceID = ""
    var folderInputs = ""
    var titleKeywords = ""
    var excludedTitleKeywords = ""
    var syncSchedule: KnowledgeSyncSchedule = .manual
    var maxDocuments = 100
}

struct DingTalkDocumentSource: Identifiable, Codable, Hashable {
    var id: UUID
    var businessSpaceID: UUID
    var displayName: String
    var clientID: String
    var clientSecret: String
    var agentID: String
    var operatorID: String?
    var defaultSpaceID: String
    var folderInputs: String
    var titleKeywords: String
    var excludedTitleKeywords: String
    var isEnabled: Bool
    var syncSchedule: KnowledgeSyncSchedule
    var maxDocuments: Int
    var lastSyncAt: Date?
    var lastDocumentCount: Int
    var lastAddedCount: Int
    var lastUpdatedCount: Int
    var lastFailedCount: Int
    var lastSkippedCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        businessSpaceID: UUID,
        displayName: String,
        clientID: String,
        clientSecret: String,
        agentID: String = "",
        operatorID: String = "",
        defaultSpaceID: String = "",
        folderInputs: String,
        titleKeywords: String = "",
        excludedTitleKeywords: String = "",
        isEnabled: Bool = true,
        syncSchedule: KnowledgeSyncSchedule = .manual,
        maxDocuments: Int = 100,
        lastSyncAt: Date? = nil,
        lastDocumentCount: Int = 0,
        lastAddedCount: Int = 0,
        lastUpdatedCount: Int = 0,
        lastFailedCount: Int = 0,
        lastSkippedCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.businessSpaceID = businessSpaceID
        self.displayName = displayName
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.agentID = agentID
        self.operatorID = operatorID.nilIfBlank
        self.defaultSpaceID = defaultSpaceID
        self.folderInputs = folderInputs
        self.titleKeywords = titleKeywords
        self.excludedTitleKeywords = excludedTitleKeywords
        self.isEnabled = isEnabled
        self.syncSchedule = syncSchedule
        self.maxDocuments = maxDocuments
        self.lastSyncAt = lastSyncAt
        self.lastDocumentCount = lastDocumentCount
        self.lastAddedCount = lastAddedCount
        self.lastUpdatedCount = lastUpdatedCount
        self.lastFailedCount = lastFailedCount
        self.lastSkippedCount = lastSkippedCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var parsedFolderInputs: [String] {
        folderInputs
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
    }

    var normalizedOperatorID: String? {
        operatorID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    var parsedTitleKeywords: [String] {
        titleKeywords
            .components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
    }

    var parsedExcludedTitleKeywords: [String] {
        excludedTitleKeywords
            .components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
    }
}

enum DingTalkDocumentKind: String, Codable, Hashable {
    case document
    case spreadsheet
    case folder
    case file
    case unknown

    var label: String {
        switch self {
        case .document: return "在线文档"
        case .spreadsheet: return "在线表格"
        case .folder: return "文件夹"
        case .file: return "文件"
        case .unknown: return "未知类型"
        }
    }
}

struct DingTalkDocumentItem: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceID: UUID
    var businessSpaceID: UUID
    var folderInput: String
    var itemID: String
    var title: String
    var kind: DingTalkDocumentKind
    var sourceURL: String
    var spaceID: String
    var parentID: String
    var createdAt: Date?
    var updatedAt: Date?
    var summary: String
    var contentStatus: String
    var syncedAt: Date

    init(
        id: UUID = UUID(),
        sourceID: UUID,
        businessSpaceID: UUID,
        folderInput: String,
        itemID: String,
        title: String,
        kind: DingTalkDocumentKind,
        sourceURL: String = "",
        spaceID: String = "",
        parentID: String = "",
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        summary: String,
        contentStatus: String,
        syncedAt: Date = Date()
    ) {
        self.id = id
        self.sourceID = sourceID
        self.businessSpaceID = businessSpaceID
        self.folderInput = folderInput
        self.itemID = itemID
        self.title = title
        self.kind = kind
        self.sourceURL = sourceURL
        self.spaceID = spaceID
        self.parentID = parentID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.summary = summary
        self.contentStatus = contentStatus
        self.syncedAt = syncedAt
    }

    var timingSummary: String {
        [
            createdAt.map { "文档创建 \(DateFormatting.shortDate.string(from: $0))" },
            updatedAt.map { "文档更新 \(DateFormatting.shortDate.string(from: $0))" }
        ]
        .compactMap { $0 }
        .joined(separator: "；")
        .nilIfBlank ?? "文档时间未知"
    }
}

struct DingTalkDocumentSyncRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceID: UUID
    var businessSpaceID: UUID
    var startedAt: Date
    var finishedAt: Date
    var status: ConfluenceSyncStatus
    var folderCount: Int
    var totalDocuments: Int
    var addedKnowledgeEntries: Int
    var updatedKnowledgeEntries: Int
    var failedDocuments: Int
    var skippedDocuments: Int
    var message: String

    init(
        id: UUID = UUID(),
        sourceID: UUID,
        businessSpaceID: UUID,
        startedAt: Date,
        finishedAt: Date = Date(),
        status: ConfluenceSyncStatus,
        folderCount: Int,
        totalDocuments: Int,
        addedKnowledgeEntries: Int,
        updatedKnowledgeEntries: Int,
        failedDocuments: Int,
        skippedDocuments: Int,
        message: String
    ) {
        self.id = id
        self.sourceID = sourceID
        self.businessSpaceID = businessSpaceID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.folderCount = folderCount
        self.totalDocuments = totalDocuments
        self.addedKnowledgeEntries = addedKnowledgeEntries
        self.updatedKnowledgeEntries = updatedKnowledgeEntries
        self.failedDocuments = failedDocuments
        self.skippedDocuments = skippedDocuments
        self.message = message
    }
}

enum JiraAuthMode: String, Codable, Hashable, CaseIterable, Identifiable {
    case cloudAPIToken
    case dataCenterBearer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cloudAPIToken: return "Jira Cloud API Token"
        case .dataCenterBearer: return "Data Center PAT Bearer"
        }
    }
}

struct JiraProjectSourceDraft: Hashable {
    var displayName = ""
    var baseURL = ""
    var authMode: JiraAuthMode = .cloudAPIToken
    var username = ""
    var token = ""
    var projectKey = ""
    var jql = ""
    var syncSchedule: KnowledgeSyncSchedule = .manual
    var maxIssues = 100
}

struct JiraProjectSource: Identifiable, Codable, Hashable {
    var id: UUID
    var businessSpaceID: UUID
    var displayName: String
    var baseURL: String
    var authMode: JiraAuthMode
    var username: String
    var token: String
    var projectKey: String
    var jql: String
    var isEnabled: Bool
    var syncSchedule: KnowledgeSyncSchedule
    var maxIssues: Int
    var lastSyncAt: Date?
    var lastIssueCount: Int
    var lastAddedCount: Int
    var lastUpdatedCount: Int
    var lastFailedCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        businessSpaceID: UUID,
        displayName: String,
        baseURL: String,
        authMode: JiraAuthMode = .cloudAPIToken,
        username: String = "",
        token: String = "",
        projectKey: String,
        jql: String = "",
        isEnabled: Bool = true,
        syncSchedule: KnowledgeSyncSchedule = .manual,
        maxIssues: Int = 100,
        lastSyncAt: Date? = nil,
        lastIssueCount: Int = 0,
        lastAddedCount: Int = 0,
        lastUpdatedCount: Int = 0,
        lastFailedCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.businessSpaceID = businessSpaceID
        self.displayName = displayName
        self.baseURL = baseURL
        self.authMode = authMode
        self.username = username
        self.token = token
        self.projectKey = projectKey
        self.jql = jql
        self.isEnabled = isEnabled
        self.syncSchedule = syncSchedule
        self.maxIssues = maxIssues
        self.lastSyncAt = lastSyncAt
        self.lastIssueCount = lastIssueCount
        self.lastAddedCount = lastAddedCount
        self.lastUpdatedCount = lastUpdatedCount
        self.lastFailedCount = lastFailedCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct JiraProjectEvidence: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceID: UUID
    var businessSpaceID: UUID
    var issueKey: String
    var issueURL: String
    var projectKey: String
    var issueType: String
    var summary: String
    var status: String
    var assignee: String
    var priority: String
    var createdAt: Date?
    var updatedAt: Date?
    var resolvedAt: Date?
    var statusChangedAt: Date?
    var fixVersions: [String]
    var sprintNames: [String]
    var labels: [String]
    var components: [String]
    var commentSummary: String
    var changelogSummary: String
    var syncedAt: Date

    init(
        id: UUID = UUID(),
        sourceID: UUID,
        businessSpaceID: UUID,
        issueKey: String,
        issueURL: String,
        projectKey: String,
        issueType: String,
        summary: String,
        status: String,
        assignee: String = "",
        priority: String = "",
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        resolvedAt: Date? = nil,
        statusChangedAt: Date? = nil,
        fixVersions: [String] = [],
        sprintNames: [String] = [],
        labels: [String] = [],
        components: [String] = [],
        commentSummary: String = "",
        changelogSummary: String = "",
        syncedAt: Date = Date()
    ) {
        self.id = id
        self.sourceID = sourceID
        self.businessSpaceID = businessSpaceID
        self.issueKey = issueKey
        self.issueURL = issueURL
        self.projectKey = projectKey
        self.issueType = issueType
        self.summary = summary
        self.status = status
        self.assignee = assignee
        self.priority = priority
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.resolvedAt = resolvedAt
        self.statusChangedAt = statusChangedAt
        self.fixVersions = fixVersions
        self.sprintNames = sprintNames
        self.labels = labels
        self.components = components
        self.commentSummary = commentSummary
        self.changelogSummary = changelogSummary
        self.syncedAt = syncedAt
    }

    var compactSummary: String {
        let owner = assignee.nilIfBlank.map { "负责人 \($0)" } ?? "未分配"
        return "\(issueKey) · \(issueType) · \(status) · \(owner)：\(summary)"
    }

    var timingSummary: String {
        [
            createdAt.map { "创建 \(DateFormatting.shortDate.string(from: $0))" },
            updatedAt.map { "更新 \(DateFormatting.shortDate.string(from: $0))" },
            statusChangedAt.map { "状态变更 \(DateFormatting.shortDate.string(from: $0))" },
            resolvedAt.map { "解决 \(DateFormatting.shortDate.string(from: $0))" }
        ]
        .compactMap { $0 }
        .joined(separator: "；")
        .nilIfBlank ?? "时间未知"
    }
}

struct JiraProjectSyncRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceID: UUID
    var businessSpaceID: UUID
    var startedAt: Date
    var finishedAt: Date
    var status: ConfluenceSyncStatus
    var totalIssues: Int
    var addedKnowledgeEntries: Int
    var updatedKnowledgeEntries: Int
    var failedIssues: Int
    var message: String

    init(
        id: UUID = UUID(),
        sourceID: UUID,
        businessSpaceID: UUID,
        startedAt: Date,
        finishedAt: Date = Date(),
        status: ConfluenceSyncStatus,
        totalIssues: Int,
        addedKnowledgeEntries: Int,
        updatedKnowledgeEntries: Int,
        failedIssues: Int,
        message: String
    ) {
        self.id = id
        self.sourceID = sourceID
        self.businessSpaceID = businessSpaceID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.totalIssues = totalIssues
        self.addedKnowledgeEntries = addedKnowledgeEntries
        self.updatedKnowledgeEntries = updatedKnowledgeEntries
        self.failedIssues = failedIssues
        self.message = message
    }
}
