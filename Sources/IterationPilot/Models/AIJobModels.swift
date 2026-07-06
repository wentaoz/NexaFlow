import Foundation

enum AIJobStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case waiting
    case requesting
    case validating
    case correcting
    case completed
    case needsUserAction
    case cancelled
    case failed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .waiting: return "等待中"
        case .requesting: return "请求中"
        case .validating: return "校验中"
        case .correcting: return "自动修正中"
        case .completed: return "已完成"
        case .needsUserAction: return "需要用户处理"
        case .cancelled: return "已取消"
        case .failed: return "已失败"
        }
    }

    var isRunnable: Bool {
        self == .waiting
    }

    var isActive: Bool {
        self == .requesting || self == .validating || self == .correcting
    }
}

enum AnalysisContextMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case quickFollowUp
    case cachedFollowUp
    case fullReanalysis
    case reportGeneration

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quickFollowUp: return "快速问答"
        case .cachedFollowUp: return "快速问答"
        case .fullReanalysis: return "深度分析"
        case .reportGeneration: return "报告生成"
        }
    }

    var actionLabel: String {
        switch self {
        case .quickFollowUp: return "快速问答"
        case .cachedFollowUp: return "快速问答"
        case .fullReanalysis: return "深度分析"
        case .reportGeneration: return "生成完整汇报"
        }
    }

    var technicalDescription: String {
        switch self {
        case .quickFollowUp:
            return "会调用 AI，但只用最近对话、上轮结论、相关缓存和少量证据作答；不重新采集外部数据、不跑 SQL/Notebook。"
        case .cachedFollowUp:
            return "会调用 AI，并复用上次完整分析资料缓存；适合围绕同一批表和同一目标连续追问。"
        case .fullReanalysis:
            return "重新读取当前任务表格和计算证据；知识库、Confluence、外部参照是否纳入由本轮资料范围决定。"
        case .reportGeneration:
            return "使用完整上下文生成完整汇报，并优先保留便于导出的结构化表格。"
        }
    }

    var userFacingDescription: String {
        switch self {
        case .quickFollowUp:
            return "会调用 AI，但只回答本轮问题，不重写完整分析。"
        case .cachedFollowUp:
            return "会调用 AI，并复用上次完整分析资料，适合同一任务连续追问。"
        case .fullReanalysis:
            return "重新读取表格、知识库、外部数据和计算证据。"
        case .reportGeneration:
            return "用于生成完整汇报，使用完整上下文和汇报结构。"
        }
    }

    var usesFullContext: Bool {
        self == .fullReanalysis || self == .reportGeneration
    }
}

enum AnalysisContextSourcePolicy: String, Codable, CaseIterable, Identifiable, Hashable {
    case tableOnly
    case tableAndKnowledge
    case fullContext

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tableOnly: return "仅表格"
        case .tableAndKnowledge: return "表格+知识库"
        case .fullContext: return "全部资料"
        }
    }

    var shortDescription: String {
        switch self {
        case .tableOnly:
            return "只读取当前选表和本地计算证据。"
        case .tableAndKnowledge:
            return "读取当前选表、计算证据和内部知识库。"
        case .fullContext:
            return "读取表格、知识库，并允许拉取外部参照源。"
        }
    }

    var includeInternalKnowledge: Bool {
        self == .tableAndKnowledge || self == .fullContext
    }

    var includeExternalReferences: Bool {
        self == .fullContext
    }

    var refreshExternalReferences: Bool {
        self == .fullContext
    }
}

struct AnalysisContextCache: Codable, Hashable {
    var createdAt: Date
    var signature: String
    var mode: AnalysisContextMode
    var coverageSummary: String
    var reportNames: [String]
    var lastUserRequest: String
    var lastAssistantSummary: String
    var limitations: [String]

    init(
        createdAt: Date = Date(),
        signature: String,
        mode: AnalysisContextMode,
        coverageSummary: String,
        reportNames: [String],
        lastUserRequest: String,
        lastAssistantSummary: String,
        limitations: [String] = []
    ) {
        self.createdAt = createdAt
        self.signature = signature
        self.mode = mode
        self.coverageSummary = coverageSummary
        self.reportNames = reportNames
        self.lastUserRequest = lastUserRequest
        self.lastAssistantSummary = lastAssistantSummary
        self.limitations = limitations
    }
}

struct AIReasoningLogEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var step: String
    var status: AIJobStatus
    var detail: String

    init(id: UUID = UUID(), createdAt: Date = Date(), step: String, status: AIJobStatus, detail: String) {
        self.id = id
        self.createdAt = createdAt
        self.step = step
        self.status = status
        self.detail = detail
    }
}

struct AIJobRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var jobType: String
    var targetID: UUID?
    var targetName: String
    var status: AIJobStatus
    var attemptCount: Int
    var maxAttempts: Int
    var nextRunAt: Date?
    var lastError: String
    var logs: [AIReasoningLogEntry]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        jobType: String,
        targetID: UUID? = nil,
        targetName: String = "",
        status: AIJobStatus = .waiting,
        attemptCount: Int = 0,
        maxAttempts: Int = 6,
        nextRunAt: Date? = nil,
        lastError: String = "",
        logs: [AIReasoningLogEntry] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.jobType = jobType
        self.targetID = targetID
        self.targetName = targetName
        self.status = status
        self.attemptCount = attemptCount
        self.maxAttempts = maxAttempts
        self.nextRunAt = nextRunAt
        self.lastError = lastError
        self.logs = logs
    }
}

enum PersistentAIJobKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case analysisSession
    case memo
    case simpleReportGeneration
    case opportunityExtraction
    case businessSpaceProfile
    case businessMap
    case referenceSourceRecommendation
    case externalEventImpact
    case tableFirstAnalysis
    case metricSemanticExtraction
    case userQuestionMemoryExtraction

    var id: String { rawValue }

    var label: String {
        switch self {
        case .analysisSession: return "分析会话"
        case .memo: return "完整汇报生成"
        case .simpleReportGeneration: return "简洁汇报生成"
        case .opportunityExtraction: return "AI 机会评分抽取"
        case .businessSpaceProfile: return "AI 业务空间识别"
        case .businessMap: return "AI 业务地图生成"
        case .referenceSourceRecommendation: return "AI 数据源推荐"
        case .externalEventImpact: return "外部事件影响分析"
        case .tableFirstAnalysis: return "AI 表格理解"
        case .metricSemanticExtraction: return "指标语义抽取"
        case .userQuestionMemoryExtraction: return "提问记忆抽取"
        }
    }
}

struct PersistentAIJobPayload: Codable, Hashable {
    var prompt: String
    var userMessage: String
    var aiOutput: String
    var messageID: UUID?
    var sessionID: UUID?
    var packID: UUID?
    var taskID: UUID?
    var reportID: UUID?
    var businessSpaceID: UUID?
    var targetName: String
    var coverageSnapshot: AnalysisCoverageSnapshot?
    var contextMode: AnalysisContextMode?
    var contextSourcePolicy: AnalysisContextSourcePolicy?
    var reportScope: ReportGenerationScope?

    init(
        prompt: String = "",
        userMessage: String = "",
        aiOutput: String = "",
        messageID: UUID? = nil,
        sessionID: UUID? = nil,
        packID: UUID? = nil,
        taskID: UUID? = nil,
        reportID: UUID? = nil,
        businessSpaceID: UUID? = nil,
        targetName: String = "",
        coverageSnapshot: AnalysisCoverageSnapshot? = nil,
        contextMode: AnalysisContextMode? = nil,
        contextSourcePolicy: AnalysisContextSourcePolicy? = nil,
        reportScope: ReportGenerationScope? = nil
    ) {
        self.prompt = prompt
        self.userMessage = userMessage
        self.aiOutput = aiOutput
        self.messageID = messageID
        self.sessionID = sessionID
        self.packID = packID
        self.taskID = taskID
        self.reportID = reportID
        self.businessSpaceID = businessSpaceID
        self.targetName = targetName
        self.coverageSnapshot = coverageSnapshot
        self.contextMode = contextMode
        self.contextSourcePolicy = contextSourcePolicy
        self.reportScope = reportScope
    }
}

struct PersistentAIJob: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var kind: PersistentAIJobKind
    var status: AIJobStatus
    var attemptCount: Int
    var maxImmediateAttempts: Int
    var delayedRetryCount: Int
    var nextRunAt: Date?
    var lastError: String
    var payload: PersistentAIJobPayload
    var record: AIJobRecord
    var logs: [AIReasoningLogEntry]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        kind: PersistentAIJobKind,
        status: AIJobStatus = .waiting,
        attemptCount: Int = 0,
        maxImmediateAttempts: Int = 6,
        delayedRetryCount: Int = 0,
        nextRunAt: Date? = nil,
        lastError: String = "",
        payload: PersistentAIJobPayload,
        record: AIJobRecord? = nil,
        logs: [AIReasoningLogEntry] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.kind = kind
        self.status = status
        self.attemptCount = attemptCount
        self.maxImmediateAttempts = maxImmediateAttempts
        self.delayedRetryCount = delayedRetryCount
        self.nextRunAt = nextRunAt
        self.lastError = lastError
        self.payload = payload
        self.record = record ?? AIJobRecord(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            jobType: kind.label,
            targetID: payload.sessionID ?? payload.reportID ?? payload.businessSpaceID ?? payload.packID,
            targetName: payload.targetName,
            status: status,
            attemptCount: attemptCount,
            maxAttempts: maxImmediateAttempts,
            nextRunAt: nextRunAt,
            lastError: lastError,
            logs: logs
        )
        self.logs = logs
    }

    var targetID: UUID? {
        payload.sessionID ?? payload.reportID ?? payload.businessSpaceID ?? payload.packID
    }

    var targetName: String {
        payload.targetName
    }
}
