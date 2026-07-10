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
    var folderBookmarkData: Data?
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
        folderBookmarkData: Data? = nil,
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
        self.folderBookmarkData = folderBookmarkData
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
    private static let clientSecretService = "com.nexaflow.dingtalk-document-source"

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

    enum CodingKeys: String, CodingKey {
        case id
        case businessSpaceID
        case displayName
        case clientID
        case clientSecret
        case agentID
        case operatorID
        case defaultSpaceID
        case folderInputs
        case titleKeywords
        case excludedTitleKeywords
        case isEnabled
        case syncSchedule
        case maxDocuments
        case lastSyncAt
        case lastDocumentCount
        case lastAddedCount
        case lastUpdatedCount
        case lastFailedCount
        case lastSkippedCount
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let legacySecret = try container.decodeIfPresent(String.self, forKey: .clientSecret) ?? ""
        self.init(
            id: decodedID,
            businessSpaceID: try container.decode(UUID.self, forKey: .businessSpaceID),
            displayName: try container.decodeIfPresent(String.self, forKey: .displayName) ?? "钉钉文档源",
            clientID: try container.decodeIfPresent(String.self, forKey: .clientID) ?? "",
            clientSecret: try AppSecureStorage.secret(
                legacyPlaintext: legacySecret,
                service: Self.clientSecretService,
                account: decodedID.uuidString
            ),
            agentID: try container.decodeIfPresent(String.self, forKey: .agentID) ?? "",
            operatorID: try container.decodeIfPresent(String.self, forKey: .operatorID) ?? "",
            defaultSpaceID: try container.decodeIfPresent(String.self, forKey: .defaultSpaceID) ?? "",
            folderInputs: try container.decodeIfPresent(String.self, forKey: .folderInputs) ?? "",
            titleKeywords: try container.decodeIfPresent(String.self, forKey: .titleKeywords) ?? "",
            excludedTitleKeywords: try container.decodeIfPresent(String.self, forKey: .excludedTitleKeywords) ?? "",
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
            syncSchedule: try container.decodeIfPresent(KnowledgeSyncSchedule.self, forKey: .syncSchedule) ?? .manual,
            maxDocuments: try container.decodeIfPresent(Int.self, forKey: .maxDocuments) ?? 100,
            lastSyncAt: try container.decodeIfPresent(Date.self, forKey: .lastSyncAt),
            lastDocumentCount: try container.decodeIfPresent(Int.self, forKey: .lastDocumentCount) ?? 0,
            lastAddedCount: try container.decodeIfPresent(Int.self, forKey: .lastAddedCount) ?? 0,
            lastUpdatedCount: try container.decodeIfPresent(Int.self, forKey: .lastUpdatedCount) ?? 0,
            lastFailedCount: try container.decodeIfPresent(Int.self, forKey: .lastFailedCount) ?? 0,
            lastSkippedCount: try container.decodeIfPresent(Int.self, forKey: .lastSkippedCount) ?? 0,
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(businessSpaceID, forKey: .businessSpaceID)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(clientID, forKey: .clientID)
        if !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try AppSecureStorage.persistPassword(clientSecret, service: Self.clientSecretService, account: id.uuidString)
        } else {
            try AppSecureStorage.persistPassword("", service: Self.clientSecretService, account: id.uuidString)
        }
        try container.encode("", forKey: .clientSecret)
        try container.encode(agentID, forKey: .agentID)
        try container.encodeIfPresent(operatorID, forKey: .operatorID)
        try container.encode(defaultSpaceID, forKey: .defaultSpaceID)
        try container.encode(folderInputs, forKey: .folderInputs)
        try container.encode(titleKeywords, forKey: .titleKeywords)
        try container.encode(excludedTitleKeywords, forKey: .excludedTitleKeywords)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(syncSchedule, forKey: .syncSchedule)
        try container.encode(maxDocuments, forKey: .maxDocuments)
        try container.encodeIfPresent(lastSyncAt, forKey: .lastSyncAt)
        try container.encode(lastDocumentCount, forKey: .lastDocumentCount)
        try container.encode(lastAddedCount, forKey: .lastAddedCount)
        try container.encode(lastUpdatedCount, forKey: .lastUpdatedCount)
        try container.encode(lastFailedCount, forKey: .lastFailedCount)
        try container.encode(lastSkippedCount, forKey: .lastSkippedCount)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
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
    private static let tokenService = "com.nexaflow.jira-project-source"

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

    enum CodingKeys: String, CodingKey {
        case id
        case businessSpaceID
        case displayName
        case baseURL
        case authMode
        case username
        case token
        case projectKey
        case jql
        case isEnabled
        case syncSchedule
        case maxIssues
        case lastSyncAt
        case lastIssueCount
        case lastAddedCount
        case lastUpdatedCount
        case lastFailedCount
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let legacyToken = try container.decodeIfPresent(String.self, forKey: .token) ?? ""
        self.init(
            id: decodedID,
            businessSpaceID: try container.decode(UUID.self, forKey: .businessSpaceID),
            displayName: try container.decodeIfPresent(String.self, forKey: .displayName) ?? "Jira 项目源",
            baseURL: try container.decodeIfPresent(String.self, forKey: .baseURL) ?? "",
            authMode: try container.decodeIfPresent(JiraAuthMode.self, forKey: .authMode) ?? .cloudAPIToken,
            username: try container.decodeIfPresent(String.self, forKey: .username) ?? "",
            token: try AppSecureStorage.secret(
                legacyPlaintext: legacyToken,
                service: Self.tokenService,
                account: decodedID.uuidString
            ),
            projectKey: try container.decodeIfPresent(String.self, forKey: .projectKey) ?? "",
            jql: try container.decodeIfPresent(String.self, forKey: .jql) ?? "",
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
            syncSchedule: try container.decodeIfPresent(KnowledgeSyncSchedule.self, forKey: .syncSchedule) ?? .manual,
            maxIssues: try container.decodeIfPresent(Int.self, forKey: .maxIssues) ?? 100,
            lastSyncAt: try container.decodeIfPresent(Date.self, forKey: .lastSyncAt),
            lastIssueCount: try container.decodeIfPresent(Int.self, forKey: .lastIssueCount) ?? 0,
            lastAddedCount: try container.decodeIfPresent(Int.self, forKey: .lastAddedCount) ?? 0,
            lastUpdatedCount: try container.decodeIfPresent(Int.self, forKey: .lastUpdatedCount) ?? 0,
            lastFailedCount: try container.decodeIfPresent(Int.self, forKey: .lastFailedCount) ?? 0,
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(businessSpaceID, forKey: .businessSpaceID)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(authMode, forKey: .authMode)
        try container.encode(username, forKey: .username)
        if !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try AppSecureStorage.persistPassword(token, service: Self.tokenService, account: id.uuidString)
        } else {
            try AppSecureStorage.persistPassword("", service: Self.tokenService, account: id.uuidString)
        }
        try container.encode("", forKey: .token)
        try container.encode(projectKey, forKey: .projectKey)
        try container.encode(jql, forKey: .jql)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(syncSchedule, forKey: .syncSchedule)
        try container.encode(maxIssues, forKey: .maxIssues)
        try container.encodeIfPresent(lastSyncAt, forKey: .lastSyncAt)
        try container.encode(lastIssueCount, forKey: .lastIssueCount)
        try container.encode(lastAddedCount, forKey: .lastAddedCount)
        try container.encode(lastUpdatedCount, forKey: .lastUpdatedCount)
        try container.encode(lastFailedCount, forKey: .lastFailedCount)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
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
