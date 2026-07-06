import Foundation

struct ProductWorkspace: Codable {
    var businessSpaces: [BusinessSpace]
    var selectedBusinessSpaceID: UUID?
    var dataPacks: [DataPack]
    var knowledgeEntries: [KnowledgeEntry]
    var correctionMemories: [AnalysisCorrectionMemory]
    var fieldDictionaryMemories: [FieldDictionaryMemory]
    var reportKnowledgeMemories: [ReportKnowledgeMemory]
    var analysisTemplateMemories: [AnalysisTemplateMemory]
    var analysisTableUnderstandingTemplates: [AnalysisTableUnderstandingTemplate]
    var smartMemoryCandidates: [SmartMemoryCandidate]
    var analysisSessions: [AnalysisSession]
    var selectedAnalysisSessionID: UUID?
    var aiJobRecords: [AIJobRecord]
    var persistentAIJobs: [PersistentAIJob]
    var aiSettings: AISettings
    var notificationSettings: AppNotificationSettings

    var confluencePages: [ConfluencePage]
    var confluenceSyncRecords: [ConfluenceSyncRecord]
    var knowledgeSourceConnectors: [KnowledgeSourceConnector]
    var localKnowledgeFolderSources: [LocalKnowledgeFolderSource]
    var localKnowledgeFolderSyncRecords: [LocalKnowledgeFolderSyncRecord]
    var dingtalkDocumentSources: [DingTalkDocumentSource]
    var dingtalkDocumentItems: [DingTalkDocumentItem]
    var dingtalkDocumentSyncRecords: [DingTalkDocumentSyncRecord]
    var jiraProjectSources: [JiraProjectSource]
    var jiraProjectEvidences: [JiraProjectEvidence]
    var jiraProjectSyncRecords: [JiraProjectSyncRecord]
    var tableauSources: [TableauSource]
    var tableauSyncRecords: [TableauSyncRecord]
    var confluenceSettings: ConfluenceSettings
    var searchSettings: SearchAPISettings
    var referenceSources: [ExternalReferenceSource]
    var referenceItems: [ExternalReferenceItem]
    var referenceCollectionRuns: [ExternalReferenceCollectionRun]

    init(
        businessSpaces: [BusinessSpace] = [BusinessSpace.defaultSpace],
        selectedBusinessSpaceID: UUID? = nil,
        dataPacks: [DataPack],
        knowledgeEntries: [KnowledgeEntry],
        correctionMemories: [AnalysisCorrectionMemory] = [],
        fieldDictionaryMemories: [FieldDictionaryMemory] = [],
        reportKnowledgeMemories: [ReportKnowledgeMemory] = [],
        analysisTemplateMemories: [AnalysisTemplateMemory] = [],
        analysisTableUnderstandingTemplates: [AnalysisTableUnderstandingTemplate] = [],
        smartMemoryCandidates: [SmartMemoryCandidate] = [],
        analysisSessions: [AnalysisSession] = [],
        selectedAnalysisSessionID: UUID? = nil,
        aiJobRecords: [AIJobRecord] = [],
        persistentAIJobs: [PersistentAIJob] = [],
        aiSettings: AISettings,
        notificationSettings: AppNotificationSettings = .default,
        confluencePages: [ConfluencePage] = [],
        confluenceSyncRecords: [ConfluenceSyncRecord] = [],
        knowledgeSourceConnectors: [KnowledgeSourceConnector] = [],
        localKnowledgeFolderSources: [LocalKnowledgeFolderSource] = [],
        localKnowledgeFolderSyncRecords: [LocalKnowledgeFolderSyncRecord] = [],
        dingtalkDocumentSources: [DingTalkDocumentSource] = [],
        dingtalkDocumentItems: [DingTalkDocumentItem] = [],
        dingtalkDocumentSyncRecords: [DingTalkDocumentSyncRecord] = [],
        jiraProjectSources: [JiraProjectSource] = [],
        jiraProjectEvidences: [JiraProjectEvidence] = [],
        jiraProjectSyncRecords: [JiraProjectSyncRecord] = [],
        tableauSources: [TableauSource] = [],
        tableauSyncRecords: [TableauSyncRecord] = [],
        confluenceSettings: ConfluenceSettings = .default,
        searchSettings: SearchAPISettings = .default,
        referenceSources: [ExternalReferenceSource] = ExternalReferenceSource.defaults,
        referenceItems: [ExternalReferenceItem] = [],
        referenceCollectionRuns: [ExternalReferenceCollectionRun] = []
    ) {
        self.businessSpaces = businessSpaces.isEmpty ? [BusinessSpace.defaultSpace] : businessSpaces
        self.selectedBusinessSpaceID = selectedBusinessSpaceID ?? self.businessSpaces.first?.id
        self.dataPacks = dataPacks
        self.knowledgeEntries = knowledgeEntries
        self.correctionMemories = correctionMemories
        self.fieldDictionaryMemories = fieldDictionaryMemories
        self.reportKnowledgeMemories = reportKnowledgeMemories
        self.analysisTemplateMemories = analysisTemplateMemories
        self.analysisTableUnderstandingTemplates = analysisTableUnderstandingTemplates
        self.smartMemoryCandidates = smartMemoryCandidates
        self.analysisSessions = analysisSessions
        self.selectedAnalysisSessionID = selectedAnalysisSessionID
        self.aiJobRecords = aiJobRecords
        self.persistentAIJobs = persistentAIJobs
        self.aiSettings = aiSettings
        self.notificationSettings = notificationSettings
        self.confluencePages = confluencePages
        self.confluenceSyncRecords = confluenceSyncRecords
        self.knowledgeSourceConnectors = knowledgeSourceConnectors
        self.localKnowledgeFolderSources = localKnowledgeFolderSources
        self.localKnowledgeFolderSyncRecords = localKnowledgeFolderSyncRecords
        self.dingtalkDocumentSources = dingtalkDocumentSources
        self.dingtalkDocumentItems = dingtalkDocumentItems
        self.dingtalkDocumentSyncRecords = dingtalkDocumentSyncRecords
        self.jiraProjectSources = jiraProjectSources
        self.jiraProjectEvidences = jiraProjectEvidences
        self.jiraProjectSyncRecords = jiraProjectSyncRecords
        self.tableauSources = tableauSources
        self.tableauSyncRecords = tableauSyncRecords
        self.confluenceSettings = confluenceSettings
        self.searchSettings = searchSettings
        self.referenceSources = referenceSources
        self.referenceItems = referenceItems
        self.referenceCollectionRuns = referenceCollectionRuns
    }

    enum CodingKeys: String, CodingKey {
        case businessSpaces
        case selectedBusinessSpaceID
        case dataPacks
        case knowledgeEntries
        case correctionMemories
        case fieldDictionaryMemories
        case reportKnowledgeMemories
        case analysisTemplateMemories
        case analysisTableUnderstandingTemplates
        case smartMemoryCandidates
        case analysisSessions
        case selectedAnalysisSessionID
        case aiJobRecords
        case persistentAIJobs
        case aiSettings
        case notificationSettings
        case confluencePages
        case confluenceSyncRecords
        case knowledgeSourceConnectors
        case localKnowledgeFolderSources
        case localKnowledgeFolderSyncRecords
        case dingtalkDocumentSources
        case dingtalkDocumentItems
        case dingtalkDocumentSyncRecords
        case jiraProjectSources
        case jiraProjectEvidences
        case jiraProjectSyncRecords
        case tableauSources
        case tableauSyncRecords
        case confluenceSettings
        case searchSettings
        case referenceSources
        case referenceItems
        case referenceCollectionRuns
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        businessSpaces = try container.decodeIfPresent([BusinessSpace].self, forKey: .businessSpaces) ?? [BusinessSpace.defaultSpace]
        if businessSpaces.isEmpty {
            businessSpaces = [BusinessSpace.defaultSpace]
        }
        let decodedBusinessSpaceID = try container.decodeIfPresent(UUID.self, forKey: .selectedBusinessSpaceID) ?? businessSpaces.first?.id
        selectedBusinessSpaceID = businessSpaces.contains(where: { $0.id == decodedBusinessSpaceID }) ? decodedBusinessSpaceID : businessSpaces.first?.id
        dataPacks = try container.decodeIfPresent([DataPack].self, forKey: .dataPacks) ?? []
        knowledgeEntries = try container.decodeIfPresent([KnowledgeEntry].self, forKey: .knowledgeEntries) ?? []
        correctionMemories = try container.decodeIfPresent([AnalysisCorrectionMemory].self, forKey: .correctionMemories) ?? []
        fieldDictionaryMemories = try container.decodeIfPresent([FieldDictionaryMemory].self, forKey: .fieldDictionaryMemories) ?? []
        reportKnowledgeMemories = try container.decodeIfPresent([ReportKnowledgeMemory].self, forKey: .reportKnowledgeMemories) ?? []
        analysisTemplateMemories = try container.decodeIfPresent([AnalysisTemplateMemory].self, forKey: .analysisTemplateMemories) ?? []
        analysisTableUnderstandingTemplates = try container.decodeIfPresent([AnalysisTableUnderstandingTemplate].self, forKey: .analysisTableUnderstandingTemplates) ?? []
        smartMemoryCandidates = try container.decodeIfPresent([SmartMemoryCandidate].self, forKey: .smartMemoryCandidates) ?? []
        analysisSessions = try container.decodeIfPresent([AnalysisSession].self, forKey: .analysisSessions) ?? []
        selectedAnalysisSessionID = try container.decodeIfPresent(UUID.self, forKey: .selectedAnalysisSessionID)
        aiJobRecords = try container.decodeIfPresent([AIJobRecord].self, forKey: .aiJobRecords) ?? []
        persistentAIJobs = try container.decodeIfPresent([PersistentAIJob].self, forKey: .persistentAIJobs) ?? []
        aiSettings = try container.decodeIfPresent(AISettings.self, forKey: .aiSettings) ?? .default
        notificationSettings = try container.decodeIfPresent(AppNotificationSettings.self, forKey: .notificationSettings) ?? .default
        confluencePages = try container.decodeIfPresent([ConfluencePage].self, forKey: .confluencePages) ?? []
        confluenceSyncRecords = try container.decodeIfPresent([ConfluenceSyncRecord].self, forKey: .confluenceSyncRecords) ?? []
        knowledgeSourceConnectors = try container.decodeIfPresent([KnowledgeSourceConnector].self, forKey: .knowledgeSourceConnectors) ?? []
        localKnowledgeFolderSources = try container.decodeIfPresent([LocalKnowledgeFolderSource].self, forKey: .localKnowledgeFolderSources) ?? []
        localKnowledgeFolderSyncRecords = try container.decodeIfPresent([LocalKnowledgeFolderSyncRecord].self, forKey: .localKnowledgeFolderSyncRecords) ?? []
        dingtalkDocumentSources = try container.decodeIfPresent([DingTalkDocumentSource].self, forKey: .dingtalkDocumentSources) ?? []
        dingtalkDocumentItems = try container.decodeIfPresent([DingTalkDocumentItem].self, forKey: .dingtalkDocumentItems) ?? []
        dingtalkDocumentSyncRecords = try container.decodeIfPresent([DingTalkDocumentSyncRecord].self, forKey: .dingtalkDocumentSyncRecords) ?? []
        jiraProjectSources = try container.decodeIfPresent([JiraProjectSource].self, forKey: .jiraProjectSources) ?? []
        jiraProjectEvidences = try container.decodeIfPresent([JiraProjectEvidence].self, forKey: .jiraProjectEvidences) ?? []
        jiraProjectSyncRecords = try container.decodeIfPresent([JiraProjectSyncRecord].self, forKey: .jiraProjectSyncRecords) ?? []
        tableauSources = try container.decodeIfPresent([TableauSource].self, forKey: .tableauSources) ?? []
        tableauSyncRecords = try container.decodeIfPresent([TableauSyncRecord].self, forKey: .tableauSyncRecords) ?? []
        confluenceSettings = try container.decodeIfPresent(ConfluenceSettings.self, forKey: .confluenceSettings) ?? .default
        searchSettings = try container.decodeIfPresent(SearchAPISettings.self, forKey: .searchSettings) ?? .default
        referenceSources = try container.decodeIfPresent([ExternalReferenceSource].self, forKey: .referenceSources) ?? ExternalReferenceSource.defaults
        referenceItems = try container.decodeIfPresent([ExternalReferenceItem].self, forKey: .referenceItems) ?? []
        referenceCollectionRuns = try container.decodeIfPresent([ExternalReferenceCollectionRun].self, forKey: .referenceCollectionRuns) ?? []
    }
}

struct DataPack: Identifiable, Codable {
    var id: UUID
    var businessSpaceID: UUID?
    var name: String
    var period: String
    var importedAt: Date
    var sourcePath: String?
    var manifest: DataManifest
    var productUpdates: [ProductUpdate]
    var metrics: [MetricPoint]
    var events: [ProductEvent]
    var feedback: [FeedbackItem]
    var importedReports: [ImportedReport]
    var fieldDefinitions: [ReportFieldDefinition]
    var qualityReport: QualityReport
    var analysisReport: AnalysisReport
    var decisionMemo: DecisionMemo
    var analysisGateStatus: DataPackAnalysisGateStatus
    var reportRelationshipProfile: ReportRelationshipProfile
    var analysisTasks: [AnalysisTask]
    var selectedAnalysisTaskID: UUID?
    var correctionMessages: [CorrectionMessage]
    var fieldDictionaryMessages: [FieldDictionaryMessage]
    var aiJobRecords: [AIJobRecord]
    var externalEventImpacts: [ExternalEventImpactRecord]

    init(
        id: UUID,
        businessSpaceID: UUID? = nil,
        name: String,
        period: String,
        importedAt: Date,
        sourcePath: String?,
        manifest: DataManifest,
        productUpdates: [ProductUpdate],
        metrics: [MetricPoint],
        events: [ProductEvent],
        feedback: [FeedbackItem],
        importedReports: [ImportedReport] = [],
        fieldDefinitions: [ReportFieldDefinition] = [],
        qualityReport: QualityReport,
        analysisReport: AnalysisReport,
        decisionMemo: DecisionMemo,
        analysisGateStatus: DataPackAnalysisGateStatus = .readyForAnalysis,
        reportRelationshipProfile: ReportRelationshipProfile = .empty,
        analysisTasks: [AnalysisTask] = [],
        selectedAnalysisTaskID: UUID? = nil,
        correctionMessages: [CorrectionMessage] = [],
        fieldDictionaryMessages: [FieldDictionaryMessage] = [],
        aiJobRecords: [AIJobRecord] = [],
        externalEventImpacts: [ExternalEventImpactRecord] = []
    ) {
        self.id = id
        self.businessSpaceID = businessSpaceID
        self.name = name
        self.period = period
        self.importedAt = importedAt
        self.sourcePath = sourcePath
        self.manifest = manifest
        self.productUpdates = productUpdates
        self.metrics = metrics
        self.events = events
        self.feedback = feedback
        self.importedReports = importedReports
        self.fieldDefinitions = fieldDefinitions
        self.qualityReport = qualityReport
        self.analysisReport = analysisReport
        self.decisionMemo = decisionMemo
        self.analysisGateStatus = analysisGateStatus
        self.reportRelationshipProfile = reportRelationshipProfile
        self.analysisTasks = analysisTasks
        self.selectedAnalysisTaskID = selectedAnalysisTaskID
        self.correctionMessages = correctionMessages
        self.fieldDictionaryMessages = fieldDictionaryMessages
        self.aiJobRecords = aiJobRecords
        self.externalEventImpacts = externalEventImpacts
    }

    enum CodingKeys: String, CodingKey {
        case id
        case businessSpaceID
        case name
        case period
        case importedAt
        case sourcePath
        case manifest
        case productUpdates
        case metrics
        case events
        case feedback
        case importedReports
        case fieldDefinitions
        case qualityReport
        case analysisReport
        case decisionMemo
        case analysisGateStatus
        case reportRelationshipProfile
        case analysisTasks
        case selectedAnalysisTaskID
        case correctionMessages
        case fieldDictionaryMessages
        case aiJobRecords
        case externalEventImpacts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        businessSpaceID = try container.decodeIfPresent(UUID.self, forKey: .businessSpaceID)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名数据包"
        period = try container.decodeIfPresent(String.self, forKey: .period) ?? ""
        importedAt = try container.decodeIfPresent(Date.self, forKey: .importedAt) ?? Date()
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath)
        manifest = try container.decodeIfPresent(DataManifest.self, forKey: .manifest) ?? .fallback(period: period, sourcePath: sourcePath)
        productUpdates = try container.decodeIfPresent([ProductUpdate].self, forKey: .productUpdates) ?? []
        metrics = try container.decodeIfPresent([MetricPoint].self, forKey: .metrics) ?? []
        events = try container.decodeIfPresent([ProductEvent].self, forKey: .events) ?? []
        feedback = try container.decodeIfPresent([FeedbackItem].self, forKey: .feedback) ?? []
        importedReports = try container.decodeIfPresent([ImportedReport].self, forKey: .importedReports) ?? []
        fieldDefinitions = try container.decodeIfPresent([ReportFieldDefinition].self, forKey: .fieldDefinitions) ?? []
        qualityReport = try container.decodeIfPresent(QualityReport.self, forKey: .qualityReport) ?? QualityReport(
            generatedAt: Date(),
            verdict: .caution,
            issues: [],
            stats: QualityStats(updateCount: productUpdates.count, metricCount: metrics.count, eventCount: events.count, feedbackCount: feedback.count, metricDateCount: Set(metrics.map(\.date)).count)
        )
        analysisReport = try container.decodeIfPresent(AnalysisReport.self, forKey: .analysisReport) ?? AnalysisReport(generatedAt: Date(), summary: "", metricInsights: [], attributionFindings: [], opportunities: [])
        decisionMemo = try container.decodeIfPresent(DecisionMemo.self, forKey: .decisionMemo) ?? DecisionMemo(generatedAt: Date(), markdown: "", aiSupplement: "")
        analysisGateStatus = try container.decodeIfPresent(DataPackAnalysisGateStatus.self, forKey: .analysisGateStatus) ?? .readyForAnalysis
        reportRelationshipProfile = try container.decodeIfPresent(ReportRelationshipProfile.self, forKey: .reportRelationshipProfile) ?? .empty
        analysisTasks = try container.decodeIfPresent([AnalysisTask].self, forKey: .analysisTasks) ?? []
        selectedAnalysisTaskID = try container.decodeIfPresent(UUID.self, forKey: .selectedAnalysisTaskID)
        if analysisTasks.isEmpty {
            let activeReportIDs = importedReports
                .filter { !$0.isIgnoredFromAnalysis }
                .map(\.id)
            analysisTasks = AnalysisTask.legacyDefaultTasks(
                reportIDs: activeReportIDs,
                relationshipProfile: reportRelationshipProfile,
                analysisReport: analysisReport,
                decisionMemo: decisionMemo
            )
            selectedAnalysisTaskID = analysisTasks.first?.id
        } else {
            let decodedSelectedTaskID = selectedAnalysisTaskID
            if decodedSelectedTaskID == nil || !analysisTasks.contains(where: { task in task.id == decodedSelectedTaskID }) {
                selectedAnalysisTaskID = analysisTasks.first?.id
            }
        }
        correctionMessages = try container.decodeIfPresent([CorrectionMessage].self, forKey: .correctionMessages) ?? []
        fieldDictionaryMessages = try container.decodeIfPresent([FieldDictionaryMessage].self, forKey: .fieldDictionaryMessages) ?? []
        aiJobRecords = try container.decodeIfPresent([AIJobRecord].self, forKey: .aiJobRecords) ?? []
        externalEventImpacts = try container.decodeIfPresent([ExternalEventImpactRecord].self, forKey: .externalEventImpacts) ?? []
    }

    var dateRangeText: String {
        let dates = metrics.map(\.date) + productUpdates.map(\.date) + events.map(\.date)
        guard let start = dates.min(), let end = dates.max() else { return "无日期数据" }
        return "\(DateFormatting.shortDate.string(from: start)) - \(DateFormatting.shortDate.string(from: end))"
    }
}

enum DataPackAnalysisGateStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case needsImportReview
    case readyForAnalysis
    case analyzed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .needsImportReview: return "待审核"
        case .readyForAnalysis: return "可分析"
        case .analyzed: return "已分析"
        }
    }
}

enum ImportedReportKind: String, Codable, CaseIterable, Identifiable {
    case productUpdates
    case coreMetrics
    case funnelMetrics
    case eventTracking
    case userFeedback
    case contextEvents
    case generic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .productUpdates: return "产品更新"
        case .coreMetrics: return "核心指标"
        case .funnelMetrics: return "漏斗指标"
        case .eventTracking: return "埋点数据"
        case .userFeedback: return "用户反馈"
        case .contextEvents: return "上下文事件"
        case .generic: return "通用报表"
        }
    }
}

enum CSVTableShape: String, Codable, CaseIterable, Identifiable, Hashable {
    case detail
    case pivotWide
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .detail: return "明细表"
        case .pivotWide: return "透视宽表"
        case .unknown: return "未知结构"
        }
    }
}

enum ReportSourceFormat: String, Codable, CaseIterable, Identifiable, Hashable {
    case csv
    case xlsx
    case xls
    case tableau

    var id: String { rawValue }

    var label: String {
        switch self {
        case .csv: return "CSV"
        case .xlsx: return "XLSX"
        case .xls: return "XLS"
        case .tableau: return "Tableau"
        }
    }
}

enum ImportedReportSemanticStatus: String, Codable, Hashable {
    case needsReview
    case inProgress
    case autoInferred
    case confirmed

    var label: String {
        switch self {
        case .needsReview: return "待确认"
        case .inProgress: return "确认中"
        case .autoInferred: return "自动识别"
        case .confirmed: return "已确认"
        }
    }
}

enum ImportAuditStepKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case parsing
    case sheetSplit
    case structureDetection
    case typeDetection
    case timeAxisDetection
    case latestPeriodCompleteness
    case fieldDictionary
    case reportSemantic
    case aiTableUnderstanding
    case aiCoverageValidation
    case memoryMatch
    case analysisAdmission

    var id: String { rawValue }

    var label: String {
        switch self {
        case .parsing: return "解析"
        case .sheetSplit: return "Sheet 拆分"
        case .structureDetection: return "结构识别"
        case .typeDetection: return "类型识别"
        case .timeAxisDetection: return "时间轴识别"
        case .latestPeriodCompleteness: return "最新周期完整性"
        case .fieldDictionary: return "字段字典"
        case .reportSemantic: return "报表语义"
        case .aiTableUnderstanding: return "AI 表格理解"
        case .aiCoverageValidation: return "AI 数据覆盖校验"
        case .memoryMatch: return "记忆命中"
        case .analysisAdmission: return "分析准入"
        }
    }
}

enum ImportAuditStepStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case completed
    case needsConfirmation
    case acceptedRisk
    case blocked

    var id: String { rawValue }

    var label: String {
        switch self {
        case .completed: return "已完成"
        case .needsConfirmation: return "需要确认"
        case .acceptedRisk: return "有风险，已接受"
        case .blocked: return "无法进入分析"
        }
    }
}

struct ImportAuditStep: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: ImportAuditStepKind
    var status: ImportAuditStepStatus
    var confidence: Double?
    var details: String
    var warnings: [String]
    var usedAI: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: ImportAuditStepKind,
        status: ImportAuditStepStatus,
        confidence: Double? = nil,
        details: String,
        warnings: [String] = [],
        usedAI: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.confidence = confidence
        self.details = details
        self.warnings = warnings
        self.usedAI = usedAI
        self.createdAt = createdAt
    }
}

enum ReportRelationshipConfirmationStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case needsReview
    case confirmed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .needsReview: return "需要确认"
        case .confirmed: return "已完成"
        }
    }
}

struct ReportRelationshipProfile: Codable, Hashable {
    var primaryReportID: UUID?
    var supportingReportIDs: [UUID]
    var incompatibleReportIDs: [UUID]
    var periodConsistency: String
    var audienceConsistency: String
    var channelConsistency: String
    var versionConsistency: String
    var experimentConsistency: String
    var confirmationStatus: ReportRelationshipConfirmationStatus
    var updatedAt: Date?

    static var empty: ReportRelationshipProfile {
        ReportRelationshipProfile(
            primaryReportID: nil,
            supportingReportIDs: [],
            incompatibleReportIDs: [],
            periodConsistency: "未检查",
            audienceConsistency: "未检查",
            channelConsistency: "未检查",
            versionConsistency: "未检查",
            experimentConsistency: "未检查",
            confirmationStatus: .confirmed,
            updatedAt: nil
        )
    }
}

enum AnalysisTaskReportRole: String, Codable, CaseIterable, Identifiable, Hashable {
    case primaryBusiness
    case impactSource
    case outcome
    case evidence
    case excluded

    var id: String { rawValue }

    var label: String {
        switch self {
        case .primaryBusiness: return "主业务"
        case .impactSource: return "影响来源"
        case .outcome: return "结果指标"
        case .evidence: return "旁证"
        case .excluded: return "本任务排除"
        }
    }

    var explanation: String {
        switch self {
        case .primaryBusiness:
            return "本次分析最核心的结果表，AI 优先回答它的变化和原因。"
        case .impactSource:
            return "可能解释主业务变化的上游表，例如渠道、页面埋点、风控、活动。"
        case .outcome:
            return "下游结果表，例如交易、留存、复购、收入。"
        case .evidence:
            return "只作为辅助验证或背景，不单独证明因果。"
        case .excluded:
            return "不进入本次 AI 分析、报告和机会评分。"
        }
    }
}

enum BusinessLinkConfirmationStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case needsReview
    case confirmed
    case rejected

    var id: String { rawValue }

    var label: String {
        switch self {
        case .needsReview: return "需要确认"
        case .confirmed: return "已完成"
        case .rejected: return "已排除"
        }
    }
}

enum CrossTableMetricRelationType: String, Codable, CaseIterable, Identifiable, Hashable {
    case upstreamDriver
    case downstreamOutcome
    case sameFunnelStep
    case pageBehaviorImpact
    case evidence
    case incompatible

    var id: String { rawValue }

    var label: String {
        switch self {
        case .upstreamDriver: return "上游驱动"
        case .downstreamOutcome: return "下游结果"
        case .sameFunnelStep: return "同一漏斗环节"
        case .pageBehaviorImpact: return "页面行为影响业务指标"
        case .evidence: return "旁证"
        case .incompatible: return "不可合并"
        }
    }
}

struct BusinessLinkNode: Identifiable, Codable, Hashable {
    var id: UUID
    var reportID: UUID
    var businessDomain: String
    var businessObject: String
    var metricRole: String
    var grain: String
    var period: String
    var maturityWindow: String
    var confidence: Double
    var notes: String

    init(
        id: UUID = UUID(),
        reportID: UUID,
        businessDomain: String,
        businessObject: String,
        metricRole: String,
        grain: String,
        period: String,
        maturityWindow: String,
        confidence: Double,
        notes: String
    ) {
        self.id = id
        self.reportID = reportID
        self.businessDomain = businessDomain
        self.businessObject = businessObject
        self.metricRole = metricRole
        self.grain = grain
        self.period = period
        self.maturityWindow = maturityWindow
        self.confidence = confidence
        self.notes = notes
    }
}

struct BusinessLinkEdge: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceReportID: UUID
    var targetReportID: UUID
    var relationType: String
    var hypothesis: String
    var lagDays: Int?
    var confidence: Double
    var evidence: [String]
    var confirmationStatus: BusinessLinkConfirmationStatus

    init(
        id: UUID = UUID(),
        sourceReportID: UUID,
        targetReportID: UUID,
        relationType: String,
        hypothesis: String,
        lagDays: Int? = nil,
        confidence: Double,
        evidence: [String] = [],
        confirmationStatus: BusinessLinkConfirmationStatus = .needsReview
    ) {
        self.id = id
        self.sourceReportID = sourceReportID
        self.targetReportID = targetReportID
        self.relationType = relationType
        self.hypothesis = hypothesis
        self.lagDays = lagDays
        self.confidence = confidence
        self.evidence = evidence
        self.confirmationStatus = confirmationStatus
    }
}

struct CrossTableMetricLink: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceReportID: UUID
    var sourceMetric: String
    var targetReportID: UUID
    var targetMetric: String
    var relationType: CrossTableMetricRelationType
    var lagDays: Int?
    var directionAlignment: String
    var evidenceLevel: EvidenceLevel
    var confidence: Double
    var evidence: [String]
    var confirmationStatus: BusinessLinkConfirmationStatus

    init(
        id: UUID = UUID(),
        sourceReportID: UUID,
        sourceMetric: String,
        targetReportID: UUID,
        targetMetric: String,
        relationType: CrossTableMetricRelationType,
        lagDays: Int? = nil,
        directionAlignment: String,
        evidenceLevel: EvidenceLevel,
        confidence: Double,
        evidence: [String] = [],
        confirmationStatus: BusinessLinkConfirmationStatus = .needsReview
    ) {
        self.id = id
        self.sourceReportID = sourceReportID
        self.sourceMetric = sourceMetric
        self.targetReportID = targetReportID
        self.targetMetric = targetMetric
        self.relationType = relationType
        self.lagDays = lagDays
        self.directionAlignment = directionAlignment
        self.evidenceLevel = evidenceLevel
        self.confidence = confidence
        self.evidence = evidence
        self.confirmationStatus = confirmationStatus
    }
}

enum MetricLinkageAnomalyType: String, Codable, CaseIterable, Identifiable, Hashable {
    case growthNotTransmitted
    case directionConflict
    case ratioDecoupling
    case funnelBreak
    case crossDomainHandoffGap
    case externalIndependentDriver
    case mixShiftOrCohortMismatch
    case periodOrDefinitionMismatch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .growthNotTransmitted: return "增长未传导"
        case .directionConflict: return "方向冲突"
        case .ratioDecoupling: return "比例脱钩"
        case .funnelBreak: return "漏斗链路断点"
        case .crossDomainHandoffGap: return "跨业务承接不足"
        case .externalIndependentDriver: return "疑似外部独立驱动"
        case .mixShiftOrCohortMismatch: return "结构或 cohort 不匹配"
        case .periodOrDefinitionMismatch: return "周期或口径不可比"
        }
    }
}

struct MetricLinkageAnomaly: Identifiable, Codable, Hashable {
    var id: UUID
    var anomalyType: MetricLinkageAnomalyType
    var sourceReportID: UUID
    var sourceReportName: String
    var sourceMetric: String
    var targetReportID: UUID
    var targetReportName: String
    var targetMetric: String
    var sourceChangeText: String
    var targetChangeText: String
    var comparisonPeriod: String
    var changeGapText: String
    var businessRelation: String
    var possibleExplanations: [String]
    var evidenceLevel: EvidenceLevel
    var confidence: Double
    var limitations: [String]
    var confirmationStatus: BusinessLinkConfirmationStatus

    init(
        id: UUID = UUID(),
        anomalyType: MetricLinkageAnomalyType,
        sourceReportID: UUID,
        sourceReportName: String,
        sourceMetric: String,
        targetReportID: UUID,
        targetReportName: String,
        targetMetric: String,
        sourceChangeText: String,
        targetChangeText: String,
        comparisonPeriod: String,
        changeGapText: String,
        businessRelation: String,
        possibleExplanations: [String],
        evidenceLevel: EvidenceLevel,
        confidence: Double,
        limitations: [String] = [],
        confirmationStatus: BusinessLinkConfirmationStatus = .needsReview
    ) {
        self.id = id
        self.anomalyType = anomalyType
        self.sourceReportID = sourceReportID
        self.sourceReportName = sourceReportName
        self.sourceMetric = sourceMetric
        self.targetReportID = targetReportID
        self.targetReportName = targetReportName
        self.targetMetric = targetMetric
        self.sourceChangeText = sourceChangeText
        self.targetChangeText = targetChangeText
        self.comparisonPeriod = comparisonPeriod
        self.changeGapText = changeGapText
        self.businessRelation = businessRelation
        self.possibleExplanations = possibleExplanations
        self.evidenceLevel = evidenceLevel
        self.confidence = confidence
        self.limitations = limitations
        self.confirmationStatus = confirmationStatus
    }
}

enum AnalysisPeriodIntentSource: String, Codable, CaseIterable, Identifiable, Hashable {
    case userMessage
    case taskGoal
    case unspecifiedOverview
    case systemDefault

    var id: String { rawValue }

    var label: String {
        switch self {
        case .userMessage: return "用户本轮指定周期"
        case .taskGoal: return "任务目标指定周期"
        case .unspecifiedOverview: return "未指定周期，全周期概览"
        case .systemDefault: return "旧默认周期口径，按全周期概览处理"
        }
    }
}

struct AnalysisPeriodIntent: Codable, Hashable {
    var source: AnalysisPeriodIntentSource
    var summary: String
    var requestedPeriods: [String]
    var excludedPeriods: [String]
    var isUserSpecified: Bool
    var allowsIncompletePeriod: Bool
    var warnings: [String]

    var isPeriodSpecified: Bool {
        source == .userMessage || source == .taskGoal || !requestedPeriods.isEmpty
    }

    static var unspecifiedOverview: AnalysisPeriodIntent {
        AnalysisPeriodIntent(
            source: .unspecifiedOverview,
            summary: "未指定主分析周期，本轮仅做全周期概览；不要输出默认主比较结论。",
            requestedPeriods: [],
            excludedPeriods: [],
            isUserSpecified: false,
            allowsIncompletePeriod: true,
            warnings: ["用户未指定主分析周期，AI 只能做全周期概览；如需精确对比，请让用户指定分析期和对比期。"]
        )
    }

    static var systemDefault: AnalysisPeriodIntent {
        .unspecifiedOverview
    }
}

struct ExternalEvidenceWindow: Codable, Hashable {
    var analysisStartDate: Date?
    var analysisEndDate: Date?
    var comparisonStartDate: Date?
    var comparisonEndDate: Date?
    var userSpecifiedPeriod: Bool
    var timeZone: String

    var hasDateRange: Bool {
        analysisStartDate != nil || analysisEndDate != nil || comparisonStartDate != nil || comparisonEndDate != nil
    }

    var summary: String {
        let analysis = Self.rangeText(start: analysisStartDate, end: analysisEndDate).nilIfBlank ?? "未识别"
        let comparison = Self.rangeText(start: comparisonStartDate, end: comparisonEndDate).nilIfBlank ?? "未识别"
        let source = userSpecifiedPeriod ? "用户指定周期" : "系统识别周期"
        return "\(source)：分析期 \(analysis)，对比期 \(comparison)，时区 \(timeZone)"
    }

    var querySuffix: String {
        let parts = [
            Self.rangeText(start: analysisStartDate, end: analysisEndDate),
            Self.rangeText(start: comparisonStartDate, end: comparisonEndDate)
        ]
            .compactMap { $0.nilIfBlank }
            .uniqued()
        guard !parts.isEmpty else { return "" }
        let monthHints = [analysisStartDate, analysisEndDate, comparisonStartDate, comparisonEndDate]
            .compactMap { $0 }
            .map { DateFormatting.monthYear.string(from: $0) }
            .uniqued()
        return (parts + monthHints).joined(separator: " ")
    }

    func contains(_ item: ExternalReferenceItem) -> Bool {
        guard hasDateRange else { return true }
        guard let range = paddedEvidenceRange else { return true }
        if let eventStart = item.eventStartedAt {
            let eventEnd = item.eventEndedAt ?? eventStart
            return eventEnd >= range.start && eventStart <= range.end
        }
        return item.displayDate >= range.start && item.displayDate <= range.end
    }

    private var paddedEvidenceRange: (start: Date, end: Date)? {
        let dates = [analysisStartDate, analysisEndDate, comparisonStartDate, comparisonEndDate].compactMap { $0 }
        guard let minDate = dates.min(), let maxDate = dates.max() else { return nil }
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -3, to: minDate) ?? minDate
        let end = calendar.date(byAdding: .day, value: 3, to: maxDate) ?? maxDate
        return (start, end)
    }

    private static func rangeText(start: Date?, end: Date?) -> String {
        switch (start, end) {
        case let (start?, end?):
            let startText = DateFormatting.shortDate.string(from: start)
            let endText = DateFormatting.shortDate.string(from: end)
            return startText == endText ? startText : "\(startText) 至 \(endText)"
        case let (start?, nil):
            return DateFormatting.shortDate.string(from: start)
        case let (nil, end?):
            return DateFormatting.shortDate.string(from: end)
        default:
            return ""
        }
    }
}

enum MetricBusinessStage: String, Codable, CaseIterable, Identifiable, Hashable {
    case acquisition
    case install
    case registration
    case application
    case creditReview
    case cardActivation
    case payment
    case retention
    case pageBehavior
    case risk
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .acquisition: return "投放获客"
        case .install: return "安装"
        case .registration: return "注册"
        case .application: return "申请/提交"
        case .creditReview: return "授信/审核"
        case .cardActivation: return "发卡/激活"
        case .payment: return "消费/交易"
        case .retention: return "留存/活跃"
        case .pageBehavior: return "页面行为"
        case .risk: return "风险/质量"
        case .unknown: return "未确认"
        }
    }
}

enum MetricDirectionPreference: String, Codable, CaseIterable, Identifiable, Hashable {
    case higherIsBetter
    case lowerIsBetter
    case neutral
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .higherIsBetter: return "越高越好"
        case .lowerIsBetter: return "越低越好"
        case .neutral: return "中性"
        case .unknown: return "未确认"
        }
    }
}

struct MetricSemanticProfile: Identifiable, Codable, Hashable {
    var id: UUID
    var metricName: String
    var aliases: [String]
    var businessStage: MetricBusinessStage
    var directionPreference: MetricDirectionPreference
    var maturityWindowDays: Int?
    var impactLagDays: Int?
    var relatedMetrics: [String]
    var commonAnomalyExplanations: [String]
    var source: String
    var confidence: Double
    var isUserConfirmed: Bool
    var updatedAt: Date?

    init(
        id: UUID = UUID(),
        metricName: String,
        aliases: [String] = [],
        businessStage: MetricBusinessStage = .unknown,
        directionPreference: MetricDirectionPreference = .unknown,
        maturityWindowDays: Int? = nil,
        impactLagDays: Int? = nil,
        relatedMetrics: [String] = [],
        commonAnomalyExplanations: [String] = [],
        source: String = "auto",
        confidence: Double = 0.5,
        isUserConfirmed: Bool = false,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.metricName = metricName
        self.aliases = aliases
        self.businessStage = businessStage
        self.directionPreference = directionPreference
        self.maturityWindowDays = maturityWindowDays
        self.impactLagDays = impactLagDays
        self.relatedMetrics = relatedMetrics
        self.commonAnomalyExplanations = commonAnomalyExplanations
        self.source = source
        self.confidence = confidence
        self.isUserConfirmed = isUserConfirmed
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case metricName
        case aliases
        case businessStage
        case directionPreference
        case maturityWindowDays
        case impactLagDays
        case relatedMetrics
        case commonAnomalyExplanations
        case source
        case confidence
        case isUserConfirmed
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        metricName = try container.decodeIfPresent(String.self, forKey: .metricName) ?? "未知指标"
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        businessStage = try container.decodeIfPresent(MetricBusinessStage.self, forKey: .businessStage) ?? .unknown
        directionPreference = try container.decodeIfPresent(MetricDirectionPreference.self, forKey: .directionPreference) ?? .unknown
        maturityWindowDays = try container.decodeIfPresent(Int.self, forKey: .maturityWindowDays)
        impactLagDays = try container.decodeIfPresent(Int.self, forKey: .impactLagDays)
        relatedMetrics = try container.decodeIfPresent([String].self, forKey: .relatedMetrics) ?? []
        commonAnomalyExplanations = try container.decodeIfPresent([String].self, forKey: .commonAnomalyExplanations) ?? []
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "auto"
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.5
        isUserConfirmed = try container.decodeIfPresent(Bool.self, forKey: .isUserConfirmed) ?? false
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

struct AnalysisCoverageReportSnapshot: Identifiable, Codable, Hashable {
    var id: UUID
    var reportID: UUID
    var reportName: String
    var sourceFormat: ReportSourceFormat
    var shape: CSVTableShape
    var kind: ImportedReportKind
    var rowCount: Int
    var columnCount: Int
    var metricCount: Int
    var timeColumnCount: Int
    var sentRows: Int
    var sentColumns: Int
    var sentMetrics: Int
    var dataMode: String
    var rawDataMode: String? = nil
    var totalRawRows: Int? = nil
    var sentRawRows: Int? = nil
    var rawCoverageDescription: String? = nil
    var timeAxisSummary: String? = nil
    var periodCoverageSummary: String? = nil
    var latestObservedPeriod: String? = nil
    var primaryComparisonPeriod: String? = nil
    var downgradedMetricCount: Int = 0
    var trendAnalysisVersion: Int? = nil
    var fieldNames: [String]
    var metricNames: [String]
    var timeColumnNames: [String]
    var omittedRowsDescription: String
    var omittedColumnsDescription: String
    var excludedPeriods: [String]
    var coreMetricNames: [String]
    var limitations: [String]

    init(
        id: UUID = UUID(),
        reportID: UUID,
        reportName: String,
        sourceFormat: ReportSourceFormat,
        shape: CSVTableShape,
        kind: ImportedReportKind,
        rowCount: Int,
        columnCount: Int,
        metricCount: Int,
        timeColumnCount: Int,
        sentRows: Int,
        sentColumns: Int,
        sentMetrics: Int,
        dataMode: String,
        rawDataMode: String? = nil,
        totalRawRows: Int? = nil,
        sentRawRows: Int? = nil,
        rawCoverageDescription: String? = nil,
        timeAxisSummary: String? = nil,
        periodCoverageSummary: String? = nil,
        latestObservedPeriod: String? = nil,
        primaryComparisonPeriod: String? = nil,
        downgradedMetricCount: Int = 0,
        trendAnalysisVersion: Int? = nil,
        fieldNames: [String] = [],
        metricNames: [String] = [],
        timeColumnNames: [String] = [],
        omittedRowsDescription: String,
        omittedColumnsDescription: String,
        excludedPeriods: [String],
        coreMetricNames: [String],
        limitations: [String]
    ) {
        self.id = id
        self.reportID = reportID
        self.reportName = reportName
        self.sourceFormat = sourceFormat
        self.shape = shape
        self.kind = kind
        self.rowCount = rowCount
        self.columnCount = columnCount
        self.metricCount = metricCount
        self.timeColumnCount = timeColumnCount
        self.sentRows = sentRows
        self.sentColumns = sentColumns
        self.sentMetrics = sentMetrics
        self.dataMode = dataMode
        self.rawDataMode = rawDataMode
        self.totalRawRows = totalRawRows
        self.sentRawRows = sentRawRows
        self.rawCoverageDescription = rawCoverageDescription
        self.timeAxisSummary = timeAxisSummary
        self.periodCoverageSummary = periodCoverageSummary
        self.latestObservedPeriod = latestObservedPeriod
        self.primaryComparisonPeriod = primaryComparisonPeriod
        self.downgradedMetricCount = downgradedMetricCount
        self.trendAnalysisVersion = trendAnalysisVersion
        self.fieldNames = fieldNames
        self.metricNames = metricNames
        self.timeColumnNames = timeColumnNames
        self.omittedRowsDescription = omittedRowsDescription
        self.omittedColumnsDescription = omittedColumnsDescription
        self.excludedPeriods = excludedPeriods
        self.coreMetricNames = coreMetricNames
        self.limitations = limitations
    }

    var summary: String {
        let rawText = rawCoverageDescription.map { "；\($0)" } ?? ""
        let timeText = timeAxisSummary.map { "；时间口径：\($0)" } ?? ""
        let periodText = periodCoverageSummary.map { "；周期覆盖：\($0)" } ?? ""
        return "\(reportName)：读取 \(rowCount) 行、\(columnCount) 列、\(metricCount) 个指标、\(timeColumnCount) 个时间列；发送 \(sentRows) 行、\(sentColumns) 列、\(sentMetrics) 个指标\(rawText)\(timeText)\(periodText)"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case reportID
        case reportName
        case sourceFormat
        case shape
        case kind
        case rowCount
        case columnCount
        case metricCount
        case timeColumnCount
        case sentRows
        case sentColumns
        case sentMetrics
        case dataMode
        case rawDataMode
        case totalRawRows
        case sentRawRows
        case rawCoverageDescription
        case timeAxisSummary
        case periodCoverageSummary
        case latestObservedPeriod
        case primaryComparisonPeriod
        case downgradedMetricCount
        case trendAnalysisVersion
        case fieldNames
        case metricNames
        case timeColumnNames
        case omittedRowsDescription
        case omittedColumnsDescription
        case excludedPeriods
        case coreMetricNames
        case limitations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        reportID = try container.decodeIfPresent(UUID.self, forKey: .reportID) ?? UUID()
        reportName = try container.decodeIfPresent(String.self, forKey: .reportName) ?? "未知报表"
        sourceFormat = try container.decodeIfPresent(ReportSourceFormat.self, forKey: .sourceFormat) ?? .csv
        shape = try container.decodeIfPresent(CSVTableShape.self, forKey: .shape) ?? .unknown
        kind = try container.decodeIfPresent(ImportedReportKind.self, forKey: .kind) ?? .generic
        rowCount = try container.decodeIfPresent(Int.self, forKey: .rowCount) ?? 0
        columnCount = try container.decodeIfPresent(Int.self, forKey: .columnCount) ?? 0
        metricCount = try container.decodeIfPresent(Int.self, forKey: .metricCount) ?? 0
        timeColumnCount = try container.decodeIfPresent(Int.self, forKey: .timeColumnCount) ?? 0
        sentRows = try container.decodeIfPresent(Int.self, forKey: .sentRows) ?? 0
        sentColumns = try container.decodeIfPresent(Int.self, forKey: .sentColumns) ?? 0
        sentMetrics = try container.decodeIfPresent(Int.self, forKey: .sentMetrics) ?? 0
        dataMode = try container.decodeIfPresent(String.self, forKey: .dataMode) ?? "unknown"
        rawDataMode = try container.decodeIfPresent(String.self, forKey: .rawDataMode)
        totalRawRows = try container.decodeIfPresent(Int.self, forKey: .totalRawRows)
        sentRawRows = try container.decodeIfPresent(Int.self, forKey: .sentRawRows)
        rawCoverageDescription = try container.decodeIfPresent(String.self, forKey: .rawCoverageDescription)
        timeAxisSummary = try container.decodeIfPresent(String.self, forKey: .timeAxisSummary)
        periodCoverageSummary = try container.decodeIfPresent(String.self, forKey: .periodCoverageSummary)
        latestObservedPeriod = try container.decodeIfPresent(String.self, forKey: .latestObservedPeriod)
        primaryComparisonPeriod = try container.decodeIfPresent(String.self, forKey: .primaryComparisonPeriod)
        downgradedMetricCount = try container.decodeIfPresent(Int.self, forKey: .downgradedMetricCount) ?? 0
        trendAnalysisVersion = try container.decodeIfPresent(Int.self, forKey: .trendAnalysisVersion)
        fieldNames = try container.decodeIfPresent([String].self, forKey: .fieldNames) ?? []
        metricNames = try container.decodeIfPresent([String].self, forKey: .metricNames) ?? []
        timeColumnNames = try container.decodeIfPresent([String].self, forKey: .timeColumnNames) ?? []
        omittedRowsDescription = try container.decodeIfPresent(String.self, forKey: .omittedRowsDescription) ?? ""
        omittedColumnsDescription = try container.decodeIfPresent(String.self, forKey: .omittedColumnsDescription) ?? ""
        excludedPeriods = try container.decodeIfPresent([String].self, forKey: .excludedPeriods) ?? []
        coreMetricNames = try container.decodeIfPresent([String].self, forKey: .coreMetricNames) ?? []
        limitations = try container.decodeIfPresent([String].self, forKey: .limitations) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(reportID, forKey: .reportID)
        try container.encode(reportName, forKey: .reportName)
        try container.encode(sourceFormat, forKey: .sourceFormat)
        try container.encode(shape, forKey: .shape)
        try container.encode(kind, forKey: .kind)
        try container.encode(rowCount, forKey: .rowCount)
        try container.encode(columnCount, forKey: .columnCount)
        try container.encode(metricCount, forKey: .metricCount)
        try container.encode(timeColumnCount, forKey: .timeColumnCount)
        try container.encode(sentRows, forKey: .sentRows)
        try container.encode(sentColumns, forKey: .sentColumns)
        try container.encode(sentMetrics, forKey: .sentMetrics)
        try container.encode(dataMode, forKey: .dataMode)
        try container.encodeIfPresent(rawDataMode, forKey: .rawDataMode)
        try container.encodeIfPresent(totalRawRows, forKey: .totalRawRows)
        try container.encodeIfPresent(sentRawRows, forKey: .sentRawRows)
        try container.encodeIfPresent(rawCoverageDescription, forKey: .rawCoverageDescription)
        try container.encodeIfPresent(timeAxisSummary, forKey: .timeAxisSummary)
        try container.encodeIfPresent(periodCoverageSummary, forKey: .periodCoverageSummary)
        try container.encodeIfPresent(latestObservedPeriod, forKey: .latestObservedPeriod)
        try container.encodeIfPresent(primaryComparisonPeriod, forKey: .primaryComparisonPeriod)
        try container.encode(downgradedMetricCount, forKey: .downgradedMetricCount)
        try container.encodeIfPresent(trendAnalysisVersion, forKey: .trendAnalysisVersion)
        try container.encode(fieldNames, forKey: .fieldNames)
        try container.encode(metricNames, forKey: .metricNames)
        try container.encode(timeColumnNames, forKey: .timeColumnNames)
        try container.encode(omittedRowsDescription, forKey: .omittedRowsDescription)
        try container.encode(omittedColumnsDescription, forKey: .omittedColumnsDescription)
        try container.encode(excludedPeriods, forKey: .excludedPeriods)
        try container.encode(coreMetricNames, forKey: .coreMetricNames)
        try container.encode(limitations, forKey: .limitations)
    }
}

struct ExternalEvidenceCoverageSnapshot: Codable, Hashable {
    var searchTriggered: Bool
    var reason: String
    var enabledSourceCount: Int
    var collectableSourceCount: Int?
    var skippedSourceCount: Int?
    var skippedSourceReasons: [String]?
    var candidateSourceCount: Int
    var tavilySourceCount: Int
    var cachedMatchedItemCount: Int
    var recentCollectedItemCount: Int
    var competitorItemCount: Int
    var newsLikeItemCount: Int
    var policyItemCount: Int
    var marketItemCount: Int
    var externalEventItemCount: Int
    var sourceNames: [String]

    var summary: String {
        let status = searchTriggered ? "会主动搜索" : "未主动搜索"
        let recentText = recentCollectedItemCount > 0 ? "，最近采集 \(recentCollectedItemCount) 条" : ""
        let sourceText = sourceNames.isEmpty ? "无启用源" : sourceNames.prefix(6).joined(separator: "、")
        let collectableText = collectableSourceCount.map { "，可采集 \($0) 个" } ?? ""
        let skippedText = skippedSourceCount.map { "，跳过 \($0) 个" } ?? ""
        let skippedReasonText = skippedSourceReasons?.prefix(4).joined(separator: "；").nilIfBlank.map { "；跳过原因：\($0)" } ?? ""
        return "\(status)：\(reason)。启用 \(enabledSourceCount) 个源\(collectableText)\(skippedText)，候选未启用 \(candidateSourceCount) 个，Tavily 源 \(tavilySourceCount) 个；周期内缓存命中 \(cachedMatchedItemCount) 条\(recentText)；竞品 \(competitorItemCount) 条，新闻/财经 \(newsLikeItemCount) 条，政策 \(policyItemCount) 条，市场 \(marketItemCount) 条，社会/自然事件 \(externalEventItemCount) 条；来源：\(sourceText)\(skippedReasonText)。"
    }
}

struct AnalysisCoverageSnapshot: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var userRequest: String
    var contextMode: AnalysisContextMode?
    var contextStrategyDescription: String?
    var reportSnapshots: [AnalysisCoverageReportSnapshot]
    var periodIntent: AnalysisPeriodIntent?
    var externalEvidenceWindow: ExternalEvidenceWindow?
    var externalEvidenceMatchedCount: Int?
    var externalEvidencePublishedOnlyCount: Int?
    var externalEvidenceCollectedOnlyCount: Int?
    var externalEvidenceCoverage: ExternalEvidenceCoverageSnapshot?
    var metricLinkageAnomalies: [MetricLinkageAnomaly]?
    var scannedMetricCount: Int?
    var totalReports: Int
    var totalRows: Int
    var totalColumns: Int
    var totalMetrics: Int
    var totalTimeColumns: Int
    var excludedPeriodCount: Int
    var profileOnlyReportCount: Int
    var knowledgeEntryCount: Int
    var confluencePageCount: Int
    var jiraProjectEvidenceCount: Int?
    var referenceItemCount: Int
    var correctionMemoryCount: Int
    var limitations: [String]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        userRequest: String,
        contextMode: AnalysisContextMode? = nil,
        contextStrategyDescription: String? = nil,
        reportSnapshots: [AnalysisCoverageReportSnapshot],
        periodIntent: AnalysisPeriodIntent? = nil,
        externalEvidenceWindow: ExternalEvidenceWindow? = nil,
        externalEvidenceMatchedCount: Int? = nil,
        externalEvidencePublishedOnlyCount: Int? = nil,
        externalEvidenceCollectedOnlyCount: Int? = nil,
        externalEvidenceCoverage: ExternalEvidenceCoverageSnapshot? = nil,
        metricLinkageAnomalies: [MetricLinkageAnomaly] = [],
        scannedMetricCount: Int? = nil,
        knowledgeEntryCount: Int,
        confluencePageCount: Int,
        jiraProjectEvidenceCount: Int? = nil,
        referenceItemCount: Int,
        correctionMemoryCount: Int,
        limitations: [String] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.userRequest = userRequest
        self.contextMode = contextMode
        self.contextStrategyDescription = contextStrategyDescription
        self.reportSnapshots = reportSnapshots
        self.periodIntent = periodIntent
        self.externalEvidenceWindow = externalEvidenceWindow
        self.externalEvidenceMatchedCount = externalEvidenceMatchedCount
        self.externalEvidencePublishedOnlyCount = externalEvidencePublishedOnlyCount
        self.externalEvidenceCollectedOnlyCount = externalEvidenceCollectedOnlyCount
        self.externalEvidenceCoverage = externalEvidenceCoverage
        self.metricLinkageAnomalies = metricLinkageAnomalies
        self.scannedMetricCount = scannedMetricCount
        self.totalReports = reportSnapshots.count
        self.totalRows = reportSnapshots.reduce(0) { $0 + $1.rowCount }
        self.totalColumns = reportSnapshots.reduce(0) { $0 + $1.columnCount }
        self.totalMetrics = reportSnapshots.reduce(0) { $0 + $1.metricCount }
        self.totalTimeColumns = reportSnapshots.reduce(0) { $0 + $1.timeColumnCount }
        self.excludedPeriodCount = reportSnapshots.reduce(0) { $0 + $1.excludedPeriods.count }
        self.profileOnlyReportCount = reportSnapshots.filter { $0.dataMode != "full_rows" }.count
        self.knowledgeEntryCount = knowledgeEntryCount
        self.confluencePageCount = confluencePageCount
        self.jiraProjectEvidenceCount = jiraProjectEvidenceCount
        self.referenceItemCount = referenceItemCount
        self.correctionMemoryCount = correctionMemoryCount
        self.limitations = limitations
    }

    var summary: String {
        let periodText = periodIntent.map { "周期口径：\($0.summary)" } ?? "周期口径：未指定周期，全周期概览"
        let anomalyCount = metricLinkageAnomalies?.count ?? 0
        let metricText = scannedMetricCount.map { "已扫描 \($0) 个指标" } ?? "已扫描当前任务指标"
        let modeText = contextMode.map { "\($0.label)：\($0.technicalDescription)" } ?? "上下文模式：未记录"
        let evidenceText: String
        if let externalEvidenceCoverage {
            evidenceText = "外部证据：\(externalEvidenceCoverage.summary)"
        } else if let externalEvidenceWindow {
            evidenceText = "外部证据窗口：\(externalEvidenceWindow.summary)，命中 \(externalEvidenceMatchedCount ?? 0) 条"
        } else {
            evidenceText = "外部证据窗口：未识别明确周期"
        }
        let excludedText = excludedPeriodCount > 0 ? "\(excludedPeriodCount) 个周期被用户口径或候选风险标记" : "没有预先排除周期"
        return "本轮 AI 将读取 \(totalReports) 张表、\(totalMetrics) 个指标、\(totalTimeColumns) 个时间周期；\(excludedText)；\(profileOnlyReportCount) 张大表仅发送画像/样本/聚合；\(periodText)；\(evidenceText)；\(metricText)，发现 \(anomalyCount) 个指标联动异常候选；\(modeText)。"
    }
}

enum AIDataRequestKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case getMetricSeries
    case getColumns
    case getRows
    case getAggregate
    case getComparisonWindow
    case getRawRange
    case getFullSheet

    var id: String { rawValue }
}

enum AIDataRequestStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case requested
    case fulfilled
    case unavailable

    var id: String { rawValue }
}

struct AIDataRequest: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: AIDataRequestKind
    var target: String
    var reason: String
    var status: AIDataRequestStatus
    var responseSummary: String

    init(
        id: UUID = UUID(),
        kind: AIDataRequestKind,
        target: String,
        reason: String,
        status: AIDataRequestStatus = .requested,
        responseSummary: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.target = target
        self.reason = reason
        self.status = status
        self.responseSummary = responseSummary
    }
}

struct TableContextCoverage: Codable, Hashable {
    var totalRows: Int
    var sentRows: Int
    var totalColumns: Int
    var sentColumns: Int
    var totalMetrics: Int
    var sentMetrics: Int
    var omittedRowsDescription: String
    var omittedColumnsDescription: String
    var limitations: [String]
    var rawDataMode: String? = nil
    var totalRawRows: Int? = nil
    var sentRawRows: Int? = nil
    var rawCoverageDescription: String? = nil

    var summary: String {
        var parts = [
            "覆盖 \(sentRows)/\(totalRows) 行、\(sentColumns)/\(totalColumns) 列、\(sentMetrics)/\(totalMetrics) 个指标"
        ]
        if let rawCoverageDescription, !rawCoverageDescription.isEmpty {
            parts.append(rawCoverageDescription)
        }
        return parts.joined(separator: "；")
    }
}

struct TableFieldProfile: Codable, Hashable {
    var name: String
    var inferredType: String
    var missingCount: Int
    var nonEmptyCount: Int
    var exampleValues: [String]
}

struct TableSeriesPoint: Codable, Hashable {
    var label: String
    var value: Double?
    var rawValue: String
    var isPartial: Bool
}

struct TableMetricSeries: Codable, Hashable {
    var metricName: String
    var points: [TableSeriesPoint]
}

struct TableContextManifest: Codable, Hashable {
    var reportID: UUID
    var fileName: String
    var sourceFileName: String
    var sheetName: String?
    var sourceFormat: ReportSourceFormat
    var reportKind: ImportedReportKind
    var shape: CSVTableShape
    var rowCount: Int
    var columnCount: Int
    var metricCount: Int
    var timeColumnCount: Int
    var parseWarnings: [String]
    var timeAxisProfile: ReportTimeAxisProfile?
}

struct TableContextInventory: Codable, Hashable {
    var headers: [String]
    var firstColumnMetrics: [String]
    var timeColumns: [String]
    var duplicateHeaders: [String]
    var fieldProfiles: [TableFieldProfile]
}

struct TableDataPayload: Codable, Hashable {
    var mode: String
    var fullRows: [[String: String]]
    var metricSeries: [TableMetricSeries]
    var rowSamples: [[String: String]]
    var aggregateSummaries: [String]
}

struct RawTablePreviewRange: Codable, Hashable {
    var name: String
    var rowStart: Int
    var rowEnd: Int
    var colStart: Int
    var colEnd: Int
    var rows: [[String]]
}

struct RawTableMatrixContext: Codable, Hashable {
    var mode: String
    var totalRows: Int
    var totalColumns: Int
    var sentRows: Int
    var sentColumns: Int
    var fullRawRows: [[String]]
    var previewRanges: [RawTablePreviewRange]
    var omittedDescription: String
    var cellTypeHints: [String: String]
    var structureRisks: [String]
    var availableRequests: [String]
}

struct TableStructureCandidate: Codable, Hashable {
    var name: String
    var shape: CSVTableShape
    var headerRows: [Int]
    var dataStartRow: Int
    var metricColumnIndex: Int?
    var timeColumnIndexes: [Int]
    var dimensionColumnIndexes: [Int]
    var confidence: Double
    var risks: [String]
}

struct TableContextPackage: Codable, Hashable {
    var generatedAt: Date
    var manifest: TableContextManifest
    var inventory: TableContextInventory
    var dataPayload: TableDataPayload
    var rawMatrix: RawTableMatrixContext? = nil
    var structureCandidates: [TableStructureCandidate]? = nil
    var coverage: TableContextCoverage
}

struct AITableFirstAnalysis: Codable, Hashable {
    var generatedAt: Date
    var readyForAnalysis: Bool
    var summary: String
    var dataAvailability: String
    var primaryComparison: [String]
    var historicalTrend: [String]
    var keyChanges: [String]
    var anomalies: [String]
    var missingDataRequests: [AIDataRequest]
    var metricLinkCandidates: [String]
    var externalEventHypotheses: [String]
    var validationWarnings: [String]
    var coverageSummary: String

    static var empty: AITableFirstAnalysis {
        AITableFirstAnalysis(
            generatedAt: Date(),
            readyForAnalysis: false,
            summary: "",
            dataAvailability: "",
            primaryComparison: [],
            historicalTrend: [],
            keyChanges: [],
            anomalies: [],
            missingDataRequests: [],
            metricLinkCandidates: [],
            externalEventHypotheses: [],
            validationWarnings: [],
            coverageSummary: ""
        )
    }
}

struct ExternalEventImpactRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var eventTitle: String
    var eventDomain: ExternalReferenceDomain
    var eventDate: Date?
    var region: String
    var affectedAudience: String
    var mechanism: String
    var relatedMetrics: [String]
    var overlapWithDataWindow: String
    var evidenceLevel: EvidenceLevel
    var confidence: Double
    var sourceItemID: UUID?
    var sourceURL: String?
    var isUserAccepted: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        eventTitle: String,
        eventDomain: ExternalReferenceDomain,
        eventDate: Date? = nil,
        region: String,
        affectedAudience: String,
        mechanism: String,
        relatedMetrics: [String],
        overlapWithDataWindow: String,
        evidenceLevel: EvidenceLevel,
        confidence: Double,
        sourceItemID: UUID? = nil,
        sourceURL: String? = nil,
        isUserAccepted: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.eventTitle = eventTitle
        self.eventDomain = eventDomain
        self.eventDate = eventDate
        self.region = region
        self.affectedAudience = affectedAudience
        self.mechanism = mechanism
        self.relatedMetrics = relatedMetrics
        self.overlapWithDataWindow = overlapWithDataWindow
        self.evidenceLevel = evidenceLevel
        self.confidence = confidence
        self.sourceItemID = sourceItemID
        self.sourceURL = sourceURL
        self.isUserAccepted = isUserAccepted
    }
}

struct BusinessLinkProfile: Codable, Hashable {
    var nodes: [BusinessLinkNode]
    var edges: [BusinessLinkEdge]
    var metricLinks: [CrossTableMetricLink]
    var metricLinkageAnomalies: [MetricLinkageAnomaly]
    var summary: String
    var confirmationStatus: BusinessLinkConfirmationStatus
    var updatedAt: Date?

    init(
        nodes: [BusinessLinkNode],
        edges: [BusinessLinkEdge],
        metricLinks: [CrossTableMetricLink] = [],
        metricLinkageAnomalies: [MetricLinkageAnomaly] = [],
        summary: String,
        confirmationStatus: BusinessLinkConfirmationStatus,
        updatedAt: Date?
    ) {
        self.nodes = nodes
        self.edges = edges
        self.metricLinks = metricLinks
        self.metricLinkageAnomalies = metricLinkageAnomalies
        self.summary = summary
        self.confirmationStatus = confirmationStatus
        self.updatedAt = updatedAt
    }

    static var empty: BusinessLinkProfile {
        BusinessLinkProfile(
            nodes: [],
            edges: [],
            metricLinks: [],
            metricLinkageAnomalies: [],
            summary: "尚未识别业务链路。",
            confirmationStatus: .confirmed,
            updatedAt: nil
        )
    }

    enum CodingKeys: String, CodingKey {
        case nodes
        case edges
        case metricLinks
        case metricLinkageAnomalies
        case summary
        case confirmationStatus
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodes = try container.decodeIfPresent([BusinessLinkNode].self, forKey: .nodes) ?? []
        edges = try container.decodeIfPresent([BusinessLinkEdge].self, forKey: .edges) ?? []
        metricLinks = try container.decodeIfPresent([CrossTableMetricLink].self, forKey: .metricLinks) ?? []
        metricLinkageAnomalies = try container.decodeIfPresent([MetricLinkageAnomaly].self, forKey: .metricLinkageAnomalies) ?? []
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? "尚未识别业务链路。"
        confirmationStatus = try container.decodeIfPresent(BusinessLinkConfirmationStatus.self, forKey: .confirmationStatus) ?? .confirmed
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

struct AnalysisTask: Identifiable, Codable {
    var id: UUID
    var businessSpaceID: UUID?
    var businessSpaceSnapshot: BusinessSpaceSnapshot?
    var name: String
    var goal: String
    var selectedReportIDs: [UUID]
    var reportRoles: [UUID: AnalysisTaskReportRole]
    var relationshipProfile: ReportRelationshipProfile
    var businessLinkProfile: BusinessLinkProfile
    var analysisReport: AnalysisReport
    var decisionMemo: DecisionMemo
    var aiObservationGeneratedAt: Date?
    var aiObservationSignature: String?
    var createdAt: Date
    var updatedAt: Date
    var lastAnalyzedAt: Date?

    init(
        id: UUID = UUID(),
        businessSpaceID: UUID? = nil,
        businessSpaceSnapshot: BusinessSpaceSnapshot? = nil,
        name: String,
        goal: String = "",
        selectedReportIDs: [UUID] = [],
        reportRoles: [UUID: AnalysisTaskReportRole] = [:],
        relationshipProfile: ReportRelationshipProfile = .empty,
        businessLinkProfile: BusinessLinkProfile = .empty,
        analysisReport: AnalysisReport = AnalysisReport(generatedAt: Date(), summary: "", metricInsights: [], attributionFindings: [], opportunities: []),
        decisionMemo: DecisionMemo = DecisionMemo(generatedAt: Date(), markdown: "", aiSupplement: ""),
        aiObservationGeneratedAt: Date? = nil,
        aiObservationSignature: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastAnalyzedAt: Date? = nil
    ) {
        self.id = id
        self.businessSpaceID = businessSpaceID
        self.businessSpaceSnapshot = businessSpaceSnapshot
        self.name = name
        self.goal = goal
        self.selectedReportIDs = selectedReportIDs.uniqued()
        self.reportRoles = reportRoles
        self.relationshipProfile = relationshipProfile
        self.businessLinkProfile = businessLinkProfile
        self.analysisReport = analysisReport
        self.decisionMemo = decisionMemo
        self.aiObservationGeneratedAt = aiObservationGeneratedAt
        self.aiObservationSignature = aiObservationSignature
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastAnalyzedAt = lastAnalyzedAt
    }

    var activeReportIDs: [UUID] {
        selectedReportIDs.filter { reportRoles[$0] != .excluded }
    }

    func role(for reportID: UUID) -> AnalysisTaskReportRole {
        reportRoles[reportID] ?? (relationshipProfile.primaryReportID == reportID ? .primaryBusiness : .evidence)
    }

    static func emptyDefault(
        name: String = "新分析任务",
        businessSpaceID: UUID? = nil,
        businessSpaceSnapshot: BusinessSpaceSnapshot? = nil
    ) -> AnalysisTask {
        AnalysisTask(
            businessSpaceID: businessSpaceID,
            businessSpaceSnapshot: businessSpaceSnapshot,
            name: name,
            relationshipProfile: .empty,
            businessLinkProfile: .empty
        )
    }

    static func legacyDefaultTasks(
        reportIDs: [UUID],
        relationshipProfile: ReportRelationshipProfile,
        analysisReport: AnalysisReport,
        decisionMemo: DecisionMemo
    ) -> [AnalysisTask] {
        guard !reportIDs.isEmpty || !analysisReport.summary.isEmpty || !decisionMemo.markdown.isEmpty else {
            return [AnalysisTask.emptyDefault(name: "默认分析任务")]
        }
        var roles: [UUID: AnalysisTaskReportRole] = [:]
        for id in reportIDs {
            if relationshipProfile.primaryReportID == id {
                roles[id] = .primaryBusiness
            } else if relationshipProfile.incompatibleReportIDs.contains(id) {
                roles[id] = .excluded
            } else {
                roles[id] = .evidence
            }
        }
        return [
            AnalysisTask(
                name: "默认分析任务",
                selectedReportIDs: reportIDs,
                reportRoles: roles,
                relationshipProfile: relationshipProfile,
                analysisReport: analysisReport,
                decisionMemo: decisionMemo,
                lastAnalyzedAt: analysisReport.summary.isEmpty ? nil : analysisReport.generatedAt
            )
        ]
    }
}

struct AnalysisTemplateReportRule: Identifiable, Codable, Hashable {
    var id: UUID
    var role: AnalysisTaskReportRole
    var reportNameKeywords: [String]
    var kind: ImportedReportKind
    var shape: CSVTableShape
    var sourceFormat: ReportSourceFormat
    var businessObjectKeywords: [String]
    var fieldKeywords: [String]
    var metricKeywords: [String]
    var notes: String

    init(
        id: UUID = UUID(),
        role: AnalysisTaskReportRole,
        reportNameKeywords: [String],
        kind: ImportedReportKind,
        shape: CSVTableShape,
        sourceFormat: ReportSourceFormat,
        businessObjectKeywords: [String],
        fieldKeywords: [String],
        metricKeywords: [String],
        notes: String = ""
    ) {
        self.id = id
        self.role = role
        self.reportNameKeywords = reportNameKeywords
        self.kind = kind
        self.shape = shape
        self.sourceFormat = sourceFormat
        self.businessObjectKeywords = businessObjectKeywords
        self.fieldKeywords = fieldKeywords
        self.metricKeywords = metricKeywords
        self.notes = notes
    }
}

struct AnalysisTemplateMetricLinkRule: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceMetric: String
    var targetMetric: String
    var relationType: CrossTableMetricRelationType
    var lagDays: Int?
    var evidenceLevel: EvidenceLevel
    var notes: String

    init(
        id: UUID = UUID(),
        sourceMetric: String,
        targetMetric: String,
        relationType: CrossTableMetricRelationType,
        lagDays: Int? = nil,
        evidenceLevel: EvidenceLevel,
        notes: String = ""
    ) {
        self.id = id
        self.sourceMetric = sourceMetric
        self.targetMetric = targetMetric
        self.relationType = relationType
        self.lagDays = lagDays
        self.evidenceLevel = evidenceLevel
        self.notes = notes
    }
}

struct AnalysisTableUnderstandingTemplate: Identifiable, Codable, Hashable {
    var id: UUID
    var businessSpaceID: UUID?
    var name: String
    var sourceFingerprintHint: String
    var headerSignature: [String]
    var shape: String
    var periodColumn: String?
    var metricNameColumn: String?
    var metricValueColumn: String?
    var fillDownPeriod: Bool
    var halfYearBucketRule: String
    var metricAliases: [String: String]
    var createdAt: Date
    var updatedAt: Date
    var useCount: Int
    var lastUsedAt: Date?
    var isDisabled: Bool

    init(
        id: UUID = UUID(),
        businessSpaceID: UUID? = nil,
        name: String,
        sourceFingerprintHint: String = "",
        headerSignature: [String],
        shape: String,
        periodColumn: String? = nil,
        metricNameColumn: String? = nil,
        metricValueColumn: String? = nil,
        fillDownPeriod: Bool = true,
        halfYearBucketRule: String = "period_start_date",
        metricAliases: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        useCount: Int = 0,
        lastUsedAt: Date? = nil,
        isDisabled: Bool = false
    ) {
        self.id = id
        self.businessSpaceID = businessSpaceID
        self.name = name
        self.sourceFingerprintHint = sourceFingerprintHint
        self.headerSignature = headerSignature
        self.shape = shape
        self.periodColumn = periodColumn
        self.metricNameColumn = metricNameColumn
        self.metricValueColumn = metricValueColumn
        self.fillDownPeriod = fillDownPeriod
        self.halfYearBucketRule = halfYearBucketRule
        self.metricAliases = metricAliases
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
        self.isDisabled = isDisabled
    }
}

struct AnalysisTemplateMemory: Identifiable, Codable, Hashable {
    var id: UUID
    var businessSpaceID: UUID?
    var name: String
    var goal: String
    var reportRules: [AnalysisTemplateReportRule]
    var metricLinkRules: [AnalysisTemplateMetricLinkRule]
    var relationshipSummary: String
    var outputInstructions: [String]
    var sourcePackName: String
    var sourceTaskName: String
    var createdAt: Date
    var updatedAt: Date
    var useCount: Int
    var lastUsedAt: Date?
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        businessSpaceID: UUID? = nil,
        name: String,
        goal: String,
        reportRules: [AnalysisTemplateReportRule],
        metricLinkRules: [AnalysisTemplateMetricLinkRule] = [],
        relationshipSummary: String = "",
        outputInstructions: [String] = [],
        sourcePackName: String = "",
        sourceTaskName: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        useCount: Int = 0,
        lastUsedAt: Date? = nil,
        isArchived: Bool = false
    ) {
        self.id = id
        self.businessSpaceID = businessSpaceID
        self.name = name
        self.goal = goal
        self.reportRules = reportRules
        self.metricLinkRules = metricLinkRules
        self.relationshipSummary = relationshipSummary
        self.outputInstructions = outputInstructions
        self.sourcePackName = sourcePackName
        self.sourceTaskName = sourceTaskName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
        self.isArchived = isArchived
    }
}

enum ReportUnderstandingMessageRole: String, Codable, Hashable {
    case assistant
    case user
    case system

    var label: String {
        switch self {
        case .assistant: return "报表助手"
        case .user: return "你"
        case .system: return "系统"
        }
    }
}

struct ReportUnderstandingMessage: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var role: ReportUnderstandingMessageRole
    var content: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        role: ReportUnderstandingMessageRole,
        content: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.role = role
        self.content = content
    }
}

struct ReportQAMemoryCandidate: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var content: String
    var scope: String
    var relatedFieldName: String?

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        scope: String = "similarReports",
        relatedFieldName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.scope = scope
        self.relatedFieldName = relatedFieldName
    }
}

struct ReportQAFieldPatch: Identifiable, Codable, Hashable {
    var id: UUID
    var fieldName: String
    var meaning: String
    var notes: String

    init(id: UUID = UUID(), fieldName: String, meaning: String, notes: String = "") {
        self.id = id
        self.fieldName = fieldName
        self.meaning = meaning
        self.notes = notes
    }
}

struct ReportQAMessage: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var role: ReportUnderstandingMessageRole
    var content: String
    var evidence: [String]
    var uncertainties: [String]
    var suggestedMemories: [ReportQAMemoryCandidate]
    var profilePatch: ReportSemanticProfile?
    var fieldPatches: [ReportQAFieldPatch]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        role: ReportUnderstandingMessageRole,
        content: String,
        evidence: [String] = [],
        uncertainties: [String] = [],
        suggestedMemories: [ReportQAMemoryCandidate] = [],
        profilePatch: ReportSemanticProfile? = nil,
        fieldPatches: [ReportQAFieldPatch] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.role = role
        self.content = content
        self.evidence = evidence
        self.uncertainties = uncertainties
        self.suggestedMemories = suggestedMemories
        self.profilePatch = profilePatch
        self.fieldPatches = fieldPatches
    }
}

struct ReportSemanticProfile: Codable, Hashable {
    var summary: String
    var purpose: String
    var businessObject: String
    var grain: String
    var keyMetrics: [String]
    var dimensions: [String]
    var filters: String
    var useCases: [String]
    var caveats: [String]
    var openQuestions: [String]
    var updatedAt: Date?

    static var empty: ReportSemanticProfile {
        ReportSemanticProfile(
            summary: "",
            purpose: "",
            businessObject: "",
            grain: "",
            keyMetrics: [],
            dimensions: [],
            filters: "",
            useCases: [],
            caveats: [],
            openQuestions: [],
            updatedAt: nil
        )
    }
}

struct ReportMetricTrend: Codable, Hashable {
    var metricName: String
    var firstValue: Double
    var lastValue: Double
    var delta: Double
    var percentChange: Double?
    var direction: ChangeDirection
    var pointCount: Int
    var trendStartDate: Date? = nil
    var trendEndDate: Date? = nil
    var trendStartLabel: String? = nil
    var trendEndLabel: String? = nil
    var latestPointIsPartial: Bool? = nil
    var partialLatestPointReason: String? = nil
    var partialLatestValue: Double? = nil
    var partialLatestLabel: String? = nil
    var completePointCount: Int? = nil
    var primaryComparison: PrimaryMetricComparison? = nil
    var historicalPattern: String? = nil
    var analysisConfidence: Double? = nil
    var evidenceLevel: EvidenceLevel? = nil
    var excludedPeriods: [ExcludedTrendPeriod]? = nil
}

struct PrimaryMetricComparison: Codable, Hashable {
    var previousLabel: String
    var currentLabel: String
    var previousValue: Double
    var currentValue: Double
    var delta: Double
    var percentChange: Double?
    var direction: ChangeDirection
    var isComparable: Bool
    var incomparabilityReason: String
    var confidence: Double
    var evidenceLevel: EvidenceLevel
}

struct ExcludedTrendPeriod: Codable, Hashable {
    var label: String
    var value: Double?
    var reason: String
}

struct ReportTrendSummary: Codable, Hashable {
    var analysisVersion: Int?
    var generatedAt: Date?
    var overview: String
    var trendBullets: [String]
    var distributionBullets: [String]
    var warnings: [String]
    var metricTrends: [ReportMetricTrend]

    static var empty: ReportTrendSummary {
        ReportTrendSummary(
            analysisVersion: nil,
            generatedAt: nil,
            overview: "",
            trendBullets: [],
            distributionBullets: [],
            warnings: [],
            metricTrends: []
        )
    }

    var isEmpty: Bool {
        overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            trendBullets.isEmpty &&
            distributionBullets.isEmpty &&
            warnings.isEmpty &&
            metricTrends.isEmpty
    }
}

enum ReportTimeAxisOrientation: String, Codable, CaseIterable, Identifiable, Hashable {
    case horizontalColumns
    case verticalDateColumn
    case mixed
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .horizontalColumns: return "横向时间列"
        case .verticalDateColumn: return "竖向日期列"
        case .mixed: return "混合时间轴"
        case .unknown: return "未知时间轴"
        }
    }
}

struct ReportTimeAxisCandidate: Identifiable, Codable, Hashable {
    var id: UUID
    var columnName: String
    var roleHint: String
    var confidence: Double
    var parsedCount: Int
    var nonEmptyCount: Int
    var missingCount: Int
    var firstDate: Date?
    var lastDate: Date?
    var detectedFormats: [String]
    var exampleValues: [String]
    var warnings: [String]

    init(
        id: UUID = UUID(),
        columnName: String,
        roleHint: String = "",
        confidence: Double,
        parsedCount: Int,
        nonEmptyCount: Int,
        missingCount: Int,
        firstDate: Date? = nil,
        lastDate: Date? = nil,
        detectedFormats: [String] = [],
        exampleValues: [String] = [],
        warnings: [String] = []
    ) {
        self.id = id
        self.columnName = columnName
        self.roleHint = roleHint
        self.confidence = confidence
        self.parsedCount = parsedCount
        self.nonEmptyCount = nonEmptyCount
        self.missingCount = missingCount
        self.firstDate = firstDate
        self.lastDate = lastDate
        self.detectedFormats = detectedFormats
        self.exampleValues = exampleValues
        self.warnings = warnings
    }

    var summary: String {
        let rangeText: String
        if let firstDate, let lastDate {
            rangeText = "\(DateFormatting.shortDate.string(from: firstDate)) 至 \(DateFormatting.shortDate.string(from: lastDate))"
        } else {
            rangeText = "无可确认范围"
        }
        return "\(columnName)：\(roleHint.nilIfBlank ?? "日期候选")，解析 \(parsedCount)/\(nonEmptyCount)，置信度 \(Int(confidence * 100))%，范围 \(rangeText)"
    }
}

struct ReportTimeAxisProfile: Codable, Hashable {
    var orientation: ReportTimeAxisOrientation
    var primaryDateColumn: String?
    var candidateDateColumns: [ReportTimeAxisCandidate]
    var confidence: Double
    var detectedFormats: [String]
    var warnings: [String]
    var userConfirmed: Bool
    var updatedAt: Date?

    init(
        orientation: ReportTimeAxisOrientation = .unknown,
        primaryDateColumn: String? = nil,
        candidateDateColumns: [ReportTimeAxisCandidate] = [],
        confidence: Double = 0,
        detectedFormats: [String] = [],
        warnings: [String] = [],
        userConfirmed: Bool = false,
        updatedAt: Date? = nil
    ) {
        self.orientation = orientation
        self.primaryDateColumn = primaryDateColumn
        self.candidateDateColumns = candidateDateColumns
        self.confidence = confidence
        self.detectedFormats = detectedFormats
        self.warnings = warnings
        self.userConfirmed = userConfirmed
        self.updatedAt = updatedAt
    }

    static var unknown: ReportTimeAxisProfile {
        ReportTimeAxisProfile(
            orientation: .unknown,
            primaryDateColumn: nil,
            candidateDateColumns: [],
            confidence: 0,
            warnings: ["未识别到可靠时间轴，AI 仍可直接检查原始表格并提出时间口径问题。"],
            userConfirmed: false
        )
    }

    var summary: String {
        let primary = primaryDateColumn?.nilIfBlank ?? "未确认"
        let candidateText = candidateDateColumns.prefix(4).map(\.summary).joined(separator: "；")
        let warningText = warnings.isEmpty ? "" : "；提醒：\(warnings.prefix(3).joined(separator: "；"))"
        return "\(orientation.label)，主时间列：\(primary)，候选 \(candidateDateColumns.count) 个，置信度 \(Int(confidence * 100))%\(candidateText.isEmpty ? "" : "；\(candidateText)")\(warningText)"
    }
}

struct ImportedReport: Identifiable, Codable, Hashable {
    var id: UUID
    var fileName: String
    var kind: ImportedReportKind
    var importedAt: Date
    var sourceFileName: String
    var sourceFingerprint: String
    var userReportAlias: String
    var rowCount: Int
    var headers: [String]
    var firstColumnValues: [String]
    var fieldExamples: [String: String]
    var sampleRows: [[String: String]]
    var storedDataRows: [[String: String]]
    var rawRows: [[String]]
    var shape: CSVTableShape
    var sourceFormat: ReportSourceFormat
    var sheetName: String?
    var sheetIndex: Int?
    var sourceMetadata: ImportedReportSourceMetadata?
    var parseWarnings: [String]
    var cellTypeHints: [String: String]
    var detectedConfidence: Double
    var originalEncoding: String
    var delimiter: String
    var semanticStatus: ImportedReportSemanticStatus
    var semanticConfidence: Double
    var semanticProfile: ReportSemanticProfile
    var understandingMessages: [ReportUnderstandingMessage]
    var qaMessages: [ReportQAMessage]
    var trendSummary: ReportTrendSummary
    var tableContextCoverage: TableContextCoverage?
    var aiFirstAnalysis: AITableFirstAnalysis?
    var aiDataRequests: [AIDataRequest]
    var aiReasoningLogs: [AIReasoningLogEntry]
    var metricSemanticProfiles: [MetricSemanticProfile]
    var timeAxisProfile: ReportTimeAxisProfile
    var auditSteps: [ImportAuditStep]
    var isIgnoredFromAnalysis: Bool

    init(
        id: UUID,
        fileName: String,
        kind: ImportedReportKind,
        importedAt: Date,
        sourceFileName: String = "",
        sourceFingerprint: String = "",
        userReportAlias: String = "",
        rowCount: Int,
        headers: [String],
        firstColumnValues: [String] = [],
        fieldExamples: [String: String] = [:],
        sampleRows: [[String: String]],
        storedDataRows: [[String: String]] = [],
        rawRows: [[String]] = [],
        shape: CSVTableShape = .unknown,
        sourceFormat: ReportSourceFormat = .csv,
        sheetName: String? = nil,
        sheetIndex: Int? = nil,
        sourceMetadata: ImportedReportSourceMetadata? = nil,
        parseWarnings: [String] = [],
        cellTypeHints: [String: String] = [:],
        detectedConfidence: Double = 0.5,
        originalEncoding: String = "",
        delimiter: String = ",",
        semanticStatus: ImportedReportSemanticStatus = .needsReview,
        semanticConfidence: Double = 0,
        semanticProfile: ReportSemanticProfile = .empty,
        understandingMessages: [ReportUnderstandingMessage] = [],
        qaMessages: [ReportQAMessage] = [],
        trendSummary: ReportTrendSummary = .empty,
        tableContextCoverage: TableContextCoverage? = nil,
        aiFirstAnalysis: AITableFirstAnalysis? = nil,
        aiDataRequests: [AIDataRequest] = [],
        aiReasoningLogs: [AIReasoningLogEntry] = [],
        metricSemanticProfiles: [MetricSemanticProfile] = [],
        timeAxisProfile: ReportTimeAxisProfile = .unknown,
        auditSteps: [ImportAuditStep] = [],
        isIgnoredFromAnalysis: Bool = false
    ) {
        self.id = id
        self.fileName = fileName
        self.kind = kind
        self.importedAt = importedAt
        self.sourceFileName = sourceFileName
        self.sourceFingerprint = sourceFingerprint
        self.userReportAlias = userReportAlias
        self.rowCount = rowCount
        self.headers = headers
        self.firstColumnValues = firstColumnValues
        self.fieldExamples = fieldExamples
        self.sampleRows = sampleRows
        self.storedDataRows = storedDataRows.isEmpty ? sampleRows : storedDataRows
        self.rawRows = rawRows.isEmpty
            ? ImportedReport.reconstructedRawRows(headers: headers, rows: self.storedDataRows)
            : rawRows
        self.shape = shape
        self.sourceFormat = sourceFormat
        self.sheetName = sheetName
        self.sheetIndex = sheetIndex
        self.sourceMetadata = sourceMetadata
        self.parseWarnings = parseWarnings
        self.cellTypeHints = cellTypeHints
        self.detectedConfidence = detectedConfidence
        self.originalEncoding = originalEncoding
        self.delimiter = delimiter
        self.semanticStatus = semanticStatus
        self.semanticConfidence = semanticConfidence
        self.semanticProfile = semanticProfile
        self.understandingMessages = understandingMessages
        self.qaMessages = qaMessages
        self.trendSummary = trendSummary
        self.tableContextCoverage = tableContextCoverage
        self.aiFirstAnalysis = aiFirstAnalysis
        self.aiDataRequests = aiDataRequests
        self.aiReasoningLogs = aiReasoningLogs
        self.metricSemanticProfiles = metricSemanticProfiles
        self.timeAxisProfile = timeAxisProfile
        self.auditSteps = auditSteps
        self.isIgnoredFromAnalysis = isIgnoredFromAnalysis
    }

    enum CodingKeys: String, CodingKey {
        case id
        case fileName
        case kind
        case importedAt
        case sourceFileName
        case sourceFingerprint
        case userReportAlias
        case rowCount
        case headers
        case firstColumnValues
        case fieldExamples
        case sampleRows
        case storedDataRows
        case rawRows
        case shape
        case sourceFormat
        case sheetName
        case sheetIndex
        case sourceMetadata
        case parseWarnings
        case cellTypeHints
        case detectedConfidence
        case originalEncoding
        case delimiter
        case semanticStatus
        case semanticConfidence
        case semanticProfile
        case understandingMessages
        case qaMessages
        case trendSummary
        case tableContextCoverage
        case aiFirstAnalysis
        case aiDataRequests
        case aiReasoningLogs
        case metricSemanticProfiles
        case timeAxisProfile
        case auditSteps
        case isIgnoredFromAnalysis
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ?? "未知报表.csv"
        kind = try container.decodeIfPresent(ImportedReportKind.self, forKey: .kind) ?? .generic
        importedAt = try container.decodeIfPresent(Date.self, forKey: .importedAt) ?? Date()
        sourceFileName = try container.decodeIfPresent(String.self, forKey: .sourceFileName) ?? fileName
        sourceFingerprint = try container.decodeIfPresent(String.self, forKey: .sourceFingerprint) ?? ""
        userReportAlias = try container.decodeIfPresent(String.self, forKey: .userReportAlias) ?? ""
        rowCount = try container.decodeIfPresent(Int.self, forKey: .rowCount) ?? 0
        headers = try container.decodeIfPresent([String].self, forKey: .headers) ?? []
        firstColumnValues = try container.decodeIfPresent([String].self, forKey: .firstColumnValues) ?? []
        fieldExamples = try container.decodeIfPresent([String: String].self, forKey: .fieldExamples) ?? [:]
        sampleRows = try container.decodeIfPresent([[String: String]].self, forKey: .sampleRows) ?? []
        storedDataRows = try container.decodeIfPresent([[String: String]].self, forKey: .storedDataRows) ?? sampleRows
        rawRows = try container.decodeIfPresent([[String]].self, forKey: .rawRows)
            ?? ImportedReport.reconstructedRawRows(headers: headers, rows: storedDataRows)
        shape = try container.decodeIfPresent(CSVTableShape.self, forKey: .shape) ?? .unknown
        sourceFormat = try container.decodeIfPresent(ReportSourceFormat.self, forKey: .sourceFormat) ?? .csv
        sheetName = try container.decodeIfPresent(String.self, forKey: .sheetName)
        sheetIndex = try container.decodeIfPresent(Int.self, forKey: .sheetIndex)
        sourceMetadata = try container.decodeIfPresent(ImportedReportSourceMetadata.self, forKey: .sourceMetadata)
        parseWarnings = try container.decodeIfPresent([String].self, forKey: .parseWarnings) ?? []
        cellTypeHints = try container.decodeIfPresent([String: String].self, forKey: .cellTypeHints) ?? [:]
        detectedConfidence = try container.decodeIfPresent(Double.self, forKey: .detectedConfidence) ?? 0.5
        originalEncoding = try container.decodeIfPresent(String.self, forKey: .originalEncoding) ?? ""
        delimiter = try container.decodeIfPresent(String.self, forKey: .delimiter) ?? ","
        semanticStatus = try container.decodeIfPresent(ImportedReportSemanticStatus.self, forKey: .semanticStatus) ?? .needsReview
        semanticConfidence = try container.decodeIfPresent(Double.self, forKey: .semanticConfidence) ?? 0
        semanticProfile = try container.decodeIfPresent(ReportSemanticProfile.self, forKey: .semanticProfile) ?? .empty
        understandingMessages = try container.decodeIfPresent([ReportUnderstandingMessage].self, forKey: .understandingMessages) ?? []
        qaMessages = try container.decodeIfPresent([ReportQAMessage].self, forKey: .qaMessages) ?? []
        trendSummary = try container.decodeIfPresent(ReportTrendSummary.self, forKey: .trendSummary) ?? .empty
        tableContextCoverage = try container.decodeIfPresent(TableContextCoverage.self, forKey: .tableContextCoverage)
        aiFirstAnalysis = try container.decodeIfPresent(AITableFirstAnalysis.self, forKey: .aiFirstAnalysis)
        aiDataRequests = try container.decodeIfPresent([AIDataRequest].self, forKey: .aiDataRequests) ?? []
        aiReasoningLogs = try container.decodeIfPresent([AIReasoningLogEntry].self, forKey: .aiReasoningLogs) ?? []
        metricSemanticProfiles = try container.decodeIfPresent([MetricSemanticProfile].self, forKey: .metricSemanticProfiles) ?? []
        timeAxisProfile = try container.decodeIfPresent(ReportTimeAxisProfile.self, forKey: .timeAxisProfile) ?? .unknown
        auditSteps = try container.decodeIfPresent([ImportAuditStep].self, forKey: .auditSteps) ?? []
        isIgnoredFromAnalysis = try container.decodeIfPresent(Bool.self, forKey: .isIgnoredFromAnalysis) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(kind, forKey: .kind)
        try container.encode(importedAt, forKey: .importedAt)
        try container.encode(sourceFileName, forKey: .sourceFileName)
        try container.encode(sourceFingerprint, forKey: .sourceFingerprint)
        try container.encode(userReportAlias, forKey: .userReportAlias)
        try container.encode(rowCount, forKey: .rowCount)
        try container.encode(headers, forKey: .headers)
        try container.encode(firstColumnValues, forKey: .firstColumnValues)
        try container.encode(fieldExamples, forKey: .fieldExamples)
        try container.encode(sampleRows, forKey: .sampleRows)
        try container.encode(storedDataRows, forKey: .storedDataRows)
        try container.encode(rawRows, forKey: .rawRows)
        try container.encode(shape, forKey: .shape)
        try container.encode(sourceFormat, forKey: .sourceFormat)
        try container.encodeIfPresent(sheetName, forKey: .sheetName)
        try container.encodeIfPresent(sheetIndex, forKey: .sheetIndex)
        try container.encode(parseWarnings, forKey: .parseWarnings)
        try container.encode(cellTypeHints, forKey: .cellTypeHints)
        try container.encode(detectedConfidence, forKey: .detectedConfidence)
        try container.encode(originalEncoding, forKey: .originalEncoding)
        try container.encode(delimiter, forKey: .delimiter)
        try container.encode(semanticStatus, forKey: .semanticStatus)
        try container.encode(semanticConfidence, forKey: .semanticConfidence)
        try container.encode(semanticProfile, forKey: .semanticProfile)
        try container.encode(understandingMessages, forKey: .understandingMessages)
        try container.encode(qaMessages, forKey: .qaMessages)
        try container.encode(trendSummary, forKey: .trendSummary)
        try container.encodeIfPresent(tableContextCoverage, forKey: .tableContextCoverage)
        try container.encodeIfPresent(aiFirstAnalysis, forKey: .aiFirstAnalysis)
        try container.encode(aiDataRequests, forKey: .aiDataRequests)
        try container.encode(aiReasoningLogs, forKey: .aiReasoningLogs)
        try container.encode(metricSemanticProfiles, forKey: .metricSemanticProfiles)
        try container.encode(timeAxisProfile, forKey: .timeAxisProfile)
        try container.encode(auditSteps, forKey: .auditSteps)
        try container.encode(isIgnoredFromAnalysis, forKey: .isIgnoredFromAnalysis)
    }

    var displayName: String {
        userReportAlias.nilIfBlank ?? fileName
    }

    var blockingAuditSteps: [ImportAuditStep] {
        isIgnoredFromAnalysis ? [] : auditSteps.filter { $0.status == .blocked }
    }

    var unresolvedAuditSteps: [ImportAuditStep] {
        isIgnoredFromAnalysis ? [] : auditSteps.filter { $0.status == .needsConfirmation || $0.status == .blocked }
    }

    var acceptedRiskAuditSteps: [ImportAuditStep] {
        auditSteps.filter { $0.status == .acceptedRisk }
    }

    var canEnterAnalysis: Bool {
        isIgnoredFromAnalysis || unresolvedAuditSteps.isEmpty
    }

    private static func reconstructedRawRows(headers: [String], rows: [[String: String]]) -> [[String]] {
        guard !headers.isEmpty else { return [] }
        var rawRows = [headers]
        rawRows.append(contentsOf: rows.map { row in
            headers.map { row[$0] ?? "" }
        })
        return rawRows
    }
}

struct ReportFieldDefinition: Identifiable, Codable, Hashable {
    var id: UUID
    var reportID: UUID
    var reportName: String
    var reportKind: ImportedReportKind
    var reportShape: CSVTableShape
    var fieldName: String
    var meaning: String
    var dataType: String
    var exampleValue: String
    var notes: String
    var isConfirmed: Bool
    var updatedAt: Date?

    init(
        id: UUID,
        reportID: UUID,
        reportName: String,
        reportKind: ImportedReportKind,
        reportShape: CSVTableShape = .unknown,
        fieldName: String,
        meaning: String,
        dataType: String,
        exampleValue: String,
        notes: String,
        isConfirmed: Bool = false,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.reportID = reportID
        self.reportName = reportName
        self.reportKind = reportKind
        self.reportShape = reportShape
        self.fieldName = fieldName
        self.meaning = meaning
        self.dataType = dataType
        self.exampleValue = exampleValue
        self.notes = notes
        self.isConfirmed = isConfirmed
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case reportID
        case reportName
        case reportKind
        case reportShape
        case fieldName
        case meaning
        case dataType
        case exampleValue
        case notes
        case isConfirmed
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        reportID = try container.decodeIfPresent(UUID.self, forKey: .reportID) ?? UUID()
        reportName = try container.decodeIfPresent(String.self, forKey: .reportName) ?? "未知报表"
        reportKind = try container.decodeIfPresent(ImportedReportKind.self, forKey: .reportKind) ?? .generic
        reportShape = try container.decodeIfPresent(CSVTableShape.self, forKey: .reportShape) ?? .unknown
        fieldName = try container.decodeIfPresent(String.self, forKey: .fieldName) ?? "未知字段"
        meaning = try container.decodeIfPresent(String.self, forKey: .meaning) ?? ""
        dataType = try container.decodeIfPresent(String.self, forKey: .dataType) ?? "string"
        exampleValue = try container.decodeIfPresent(String.self, forKey: .exampleValue) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        isConfirmed = try container.decodeIfPresent(Bool.self, forKey: .isConfirmed) ?? false
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

enum FieldDictionaryMessageRole: String, Codable {
    case assistant
    case user
    case system

    var label: String {
        switch self {
        case .assistant: return "字段助手"
        case .user: return "你"
        case .system: return "系统"
        }
    }
}

struct FieldDictionaryMessage: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var role: FieldDictionaryMessageRole
    var fieldDefinitionID: UUID?
    var reportName: String
    var fieldName: String
    var content: String
}

struct FieldDictionaryMemory: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var reportName: String
    var reportKind: ImportedReportKind
    var fieldName: String
    var meaning: String
    var dataType: String
    var notes: String
    var exampleValue: String
    var sourcePackName: String

    var matchKey: String {
        Self.matchKey(reportName: reportName, reportKind: reportKind, fieldName: fieldName)
    }

    static func matchKey(reportName: String, reportKind: ImportedReportKind, fieldName: String) -> String {
        "\(reportName.normalizedKey)|\(reportKind.rawValue)|\(fieldName.normalizedKey)"
    }
}

struct ReportKnowledgeMemory: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var reportNamePattern: String
    var reportKind: ImportedReportKind
    var reportShape: CSVTableShape
    var sourceFormat: ReportSourceFormat?
    var fieldKeywords: [String]
    var title: String
    var content: String
    var sourceQuestion: String
    var sourceAnswer: String
    var sourcePackName: String
    var sourceReportName: String
    var knowledgeEntryID: UUID?
    var hitCount: Int
    var lastMatchedAt: Date?
    var isArchived: Bool

    init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        reportNamePattern: String,
        reportKind: ImportedReportKind,
        reportShape: CSVTableShape,
        sourceFormat: ReportSourceFormat?,
        fieldKeywords: [String],
        title: String,
        content: String,
        sourceQuestion: String,
        sourceAnswer: String,
        sourcePackName: String,
        sourceReportName: String,
        knowledgeEntryID: UUID?,
        hitCount: Int = 0,
        lastMatchedAt: Date? = nil,
        isArchived: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.reportNamePattern = reportNamePattern
        self.reportKind = reportKind
        self.reportShape = reportShape
        self.sourceFormat = sourceFormat
        self.fieldKeywords = fieldKeywords
        self.title = title
        self.content = content
        self.sourceQuestion = sourceQuestion
        self.sourceAnswer = sourceAnswer
        self.sourcePackName = sourcePackName
        self.sourceReportName = sourceReportName
        self.knowledgeEntryID = knowledgeEntryID
        self.hitCount = hitCount
        self.lastMatchedAt = lastMatchedAt
        self.isArchived = isArchived
    }

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case reportNamePattern
        case reportKind
        case reportShape
        case sourceFormat
        case fieldKeywords
        case title
        case content
        case sourceQuestion
        case sourceAnswer
        case sourcePackName
        case sourceReportName
        case knowledgeEntryID
        case hitCount
        case lastMatchedAt
        case isArchived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        reportNamePattern = try container.decodeIfPresent(String.self, forKey: .reportNamePattern) ?? ""
        reportKind = try container.decodeIfPresent(ImportedReportKind.self, forKey: .reportKind) ?? .generic
        reportShape = try container.decodeIfPresent(CSVTableShape.self, forKey: .reportShape) ?? .unknown
        sourceFormat = try container.decodeIfPresent(ReportSourceFormat.self, forKey: .sourceFormat)
        fieldKeywords = try container.decodeIfPresent([String].self, forKey: .fieldKeywords) ?? []
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "报表知识规则"
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        sourceQuestion = try container.decodeIfPresent(String.self, forKey: .sourceQuestion) ?? ""
        sourceAnswer = try container.decodeIfPresent(String.self, forKey: .sourceAnswer) ?? ""
        sourcePackName = try container.decodeIfPresent(String.self, forKey: .sourcePackName) ?? ""
        sourceReportName = try container.decodeIfPresent(String.self, forKey: .sourceReportName) ?? ""
        knowledgeEntryID = try container.decodeIfPresent(UUID.self, forKey: .knowledgeEntryID)
        hitCount = try container.decodeIfPresent(Int.self, forKey: .hitCount) ?? 0
        lastMatchedAt = try container.decodeIfPresent(Date.self, forKey: .lastMatchedAt)
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }

    var matchKey: String {
        [
            reportNamePattern.normalizedKey,
            reportKind.rawValue,
            reportShape.rawValue,
            fieldKeywords.map(\.normalizedKey).sorted().joined(separator: ",")
        ].joined(separator: "|")
    }

    func matchScore(for report: ImportedReport) -> Int {
        if isArchived { return 0 }
        var score = 0
        let reportNameKey = report.fileName.normalizedKey
        let patternKey = reportNamePattern.normalizedKey
        if !patternKey.isEmpty, reportNameKey.contains(patternKey) || patternKey.contains(reportNameKey) {
            score += 5
        }
        if report.kind == reportKind { score += 3 }
        if report.shape == reportShape { score += 2 }
        if sourceFormat == nil || sourceFormat == report.sourceFormat { score += 1 }
        let fieldText = (report.headers + report.firstColumnValues + report.semanticProfile.keyMetrics).joined(separator: " ").normalizedKey
        score += min(4, fieldKeywords.filter { !$0.normalizedKey.isEmpty && fieldText.contains($0.normalizedKey) }.count)
        return score
    }
}

struct DataManifest: Codable {
    var period: String
    var exportedAt: Date?
    var exportedBy: String
    var sources: [ManifestSource]
    var knownIssues: [String]

    enum CodingKeys: String, CodingKey {
        case period
        case exportedAt = "exported_at"
        case exportedBy = "exported_by"
        case sources
        case knownIssues = "known_issues"
    }

    static func fallback(period: String, sourcePath: String?) -> DataManifest {
        DataManifest(
            period: period,
            exportedAt: nil,
            exportedBy: "未记录",
            sources: sourcePath.map { [ManifestSource(name: "本地文件夹", platform: $0, dateRange: "", exportMethod: "manual_folder")] } ?? [],
            knownIssues: []
        )
    }
}

struct ManifestSource: Codable, Identifiable {
    var id = UUID()
    var name: String
    var platform: String
    var dateRange: String
    var exportMethod: String

    enum CodingKeys: String, CodingKey {
        case name
        case platform
        case dateRange = "date_range"
        case exportMethod = "export_method"
    }
}

struct ProductUpdate: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var module: String
    var changeType: String
    var targetUser: String
    var expectedMetric: String
    var owner: String
    var releaseNote: String
    var riskNote: String
}

struct MetricPoint: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var metric: String
    var value: Double
    var segment: String
    var platform: String
    var channel: String

    var scopeKey: String {
        [segment, platform, channel]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "全量" }
            .joined(separator: " / ")
    }
}

struct ProductEvent: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var eventType: String
    var title: String
    var scope: String
    var note: String
}

struct FeedbackItem: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var source: String
    var module: String
    var segment: String
    var sentiment: String
    var text: String
}

struct QualityReport: Codable {
    var generatedAt: Date
    var verdict: QualityVerdict
    var issues: [DataQualityIssue]
    var stats: QualityStats
}

enum QualityVerdict: String, Codable {
    case usable = "可用于分析"
    case caution = "谨慎使用"
    case blocked = "不可使用"

    var systemImage: String {
        switch self {
        case .usable: return "checkmark.circle"
        case .caution: return "exclamationmark.triangle"
        case .blocked: return "xmark.octagon"
        }
    }
}

struct DataQualityIssue: Identifiable, Codable, Hashable {
    var id: UUID
    var severity: IssueSeverity
    var title: String
    var detail: String
    var recommendedAction: String
}

enum IssueSeverity: String, Codable, CaseIterable {
    case info = "提示"
    case warning = "警告"
    case critical = "严重"

    var systemImage: String {
        switch self {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .critical: return "xmark.octagon"
        }
    }
}

struct QualityStats: Codable {
    var updateCount: Int
    var metricCount: Int
    var eventCount: Int
    var feedbackCount: Int
    var metricDateCount: Int
}

enum AnalysisContextDomain: String, Codable, CaseIterable, Identifiable, Hashable {
    case tableTrend
    case knowledge
    case competitor
    case policy
    case market
    case externalEvent
    case correction
    case manual
    case sourceCoverage
    case timeline

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tableTrend: return "表格趋势"
        case .knowledge: return "知识库"
        case .competitor: return "竞品舆情"
        case .policy: return "政策/监管"
        case .market: return "市场参照"
        case .externalEvent: return "社会/自然事件"
        case .correction: return "纠偏记忆"
        case .manual: return "人工备注"
        case .sourceCoverage: return "数据源状态"
        case .timeline: return "时间线证据"
        }
    }

    var systemImage: String {
        switch self {
        case .tableTrend: return "tablecells"
        case .knowledge: return "books.vertical"
        case .competitor: return "newspaper"
        case .policy: return "building.columns"
        case .market: return "chart.xyaxis.line"
        case .externalEvent: return "cloud.bolt.rain"
        case .correction: return "brain.head.profile"
        case .manual: return "note.text"
        case .sourceCoverage: return "antenna.radiowaves.left.and.right"
        case .timeline: return "calendar.badge.clock"
        }
    }
}

struct AnalysisContextSignal: Identifiable, Codable, Hashable {
    var id: UUID
    var domain: AnalysisContextDomain
    var title: String
    var detail: String
    var relatedMetric: String
    var sourceName: String
    var sourceURL: String?
    var observedAt: Date?
    var strength: Int
    var relationReason: String
    var isInferredRelation: Bool

    init(
        id: UUID = UUID(),
        domain: AnalysisContextDomain,
        title: String,
        detail: String,
        relatedMetric: String = "",
        sourceName: String = "",
        sourceURL: String? = nil,
        observedAt: Date? = nil,
        strength: Int = 3,
        relationReason: String = "",
        isInferredRelation: Bool = true
    ) {
        self.id = id
        self.domain = domain
        self.title = title
        self.detail = detail
        self.relatedMetric = relatedMetric
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.observedAt = observedAt
        self.strength = min(max(strength, 1), 10)
        self.relationReason = relationReason
        self.isInferredRelation = isInferredRelation
    }
}

struct AnalysisReport: Codable {
    var generatedAt: Date
    var summary: String
    var tableTrendOverview: String
    var tableTrendBullets: [String]
    var contextSignals: [AnalysisContextSignal]
    var metricInsights: [MetricInsight]
    var attributionFindings: [AttributionFinding]
    var opportunities: [ProductOpportunity]

    init(
        generatedAt: Date,
        summary: String,
        tableTrendOverview: String = "",
        tableTrendBullets: [String] = [],
        contextSignals: [AnalysisContextSignal] = [],
        metricInsights: [MetricInsight],
        attributionFindings: [AttributionFinding],
        opportunities: [ProductOpportunity]
    ) {
        self.generatedAt = generatedAt
        self.summary = summary
        self.tableTrendOverview = tableTrendOverview
        self.tableTrendBullets = tableTrendBullets
        self.contextSignals = contextSignals
        self.metricInsights = metricInsights
        self.attributionFindings = attributionFindings
        self.opportunities = opportunities
    }

    enum CodingKeys: String, CodingKey {
        case generatedAt
        case summary
        case tableTrendOverview
        case tableTrendBullets
        case contextSignals
        case metricInsights
        case attributionFindings
        case opportunities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt) ?? Date()
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        tableTrendOverview = try container.decodeIfPresent(String.self, forKey: .tableTrendOverview) ?? ""
        tableTrendBullets = try container.decodeIfPresent([String].self, forKey: .tableTrendBullets) ?? []
        contextSignals = try container.decodeIfPresent([AnalysisContextSignal].self, forKey: .contextSignals) ?? []
        metricInsights = try container.decodeIfPresent([MetricInsight].self, forKey: .metricInsights) ?? []
        attributionFindings = try container.decodeIfPresent([AttributionFinding].self, forKey: .attributionFindings) ?? []
        opportunities = try container.decodeIfPresent([ProductOpportunity].self, forKey: .opportunities) ?? []
    }
}

struct MetricInsight: Identifiable, Codable, Hashable {
    var id: UUID
    var metric: String
    var scope: String
    var previousAverage: Double
    var currentAverage: Double
    var absoluteDelta: Double
    var percentChange: Double
    var direction: ChangeDirection
    var severity: InsightSeverity
    var startDate: Date
    var endDate: Date

    var formattedChange: String {
        let sign = percentChange >= 0 ? "+" : ""
        return "\(sign)\(DateFormatting.percent.string(from: NSNumber(value: percentChange)) ?? "0%")"
    }
}

enum ChangeDirection: String, Codable {
    case up = "上升"
    case down = "下降"
    case flat = "平稳"
}

enum InsightSeverity: String, Codable {
    case low = "低"
    case medium = "中"
    case high = "高"
}

struct AttributionFinding: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var evidenceLevel: EvidenceLevel
    var confidence: Int
    var relatedMetric: String
    var relatedScope: String
    var primaryCause: String
    var supportingSignals: [String]
    var counterSignals: [String]
    var recommendedNextData: [String]
}

enum EvidenceLevel: String, Codable, CaseIterable {
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"
    case e = "E"

    var label: String {
        switch self {
        case .a: return "A 实验或准实验支持"
        case .b: return "B 时间/人群/指标吻合"
        case .c: return "C 相关性较弱"
        case .d: return "D 仅为待验证假设"
        case .e: return "E 不可用或不可合并"
        }
    }
}

struct ProductOpportunity: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var problem: String
    var affectedUsers: String
    var expectedImpact: Int
    var confidence: Int
    var urgency: Int
    var effort: Int
    var risk: Int
    var strategicFit: Int
    var sourceSessionID: UUID?
    var sourceSessionTitle: String
    var generatedAt: Date
    var isAIGenerated: Bool
    var isUserConfirmed: Bool
    var evidenceSummary: String

    init(
        id: UUID = UUID(),
        title: String,
        problem: String,
        affectedUsers: String,
        expectedImpact: Int,
        confidence: Int,
        urgency: Int,
        effort: Int,
        risk: Int,
        strategicFit: Int,
        sourceSessionID: UUID? = nil,
        sourceSessionTitle: String = "",
        generatedAt: Date = Date(),
        isAIGenerated: Bool = false,
        isUserConfirmed: Bool = false,
        evidenceSummary: String = ""
    ) {
        self.id = id
        self.title = title
        self.problem = problem
        self.affectedUsers = affectedUsers
        self.expectedImpact = min(max(expectedImpact, 1), 10)
        self.confidence = min(max(confidence, 1), 10)
        self.urgency = min(max(urgency, 1), 10)
        self.effort = min(max(effort, 1), 10)
        self.risk = min(max(risk, 1), 10)
        self.strategicFit = min(max(strategicFit, 1), 10)
        self.sourceSessionID = sourceSessionID
        self.sourceSessionTitle = sourceSessionTitle
        self.generatedAt = generatedAt
        self.isAIGenerated = isAIGenerated
        self.isUserConfirmed = isUserConfirmed
        self.evidenceSummary = evidenceSummary
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case problem
        case affectedUsers
        case expectedImpact
        case confidence
        case urgency
        case effort
        case risk
        case strategicFit
        case sourceSessionID
        case sourceSessionTitle
        case generatedAt
        case isAIGenerated
        case isUserConfirmed
        case evidenceSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            title: try container.decodeIfPresent(String.self, forKey: .title) ?? "未命名机会",
            problem: try container.decodeIfPresent(String.self, forKey: .problem) ?? "",
            affectedUsers: try container.decodeIfPresent(String.self, forKey: .affectedUsers) ?? "未限定",
            expectedImpact: try container.decodeIfPresent(Int.self, forKey: .expectedImpact) ?? 3,
            confidence: try container.decodeIfPresent(Int.self, forKey: .confidence) ?? 3,
            urgency: try container.decodeIfPresent(Int.self, forKey: .urgency) ?? 3,
            effort: try container.decodeIfPresent(Int.self, forKey: .effort) ?? 5,
            risk: try container.decodeIfPresent(Int.self, forKey: .risk) ?? 5,
            strategicFit: try container.decodeIfPresent(Int.self, forKey: .strategicFit) ?? 5,
            sourceSessionID: try container.decodeIfPresent(UUID.self, forKey: .sourceSessionID),
            sourceSessionTitle: try container.decodeIfPresent(String.self, forKey: .sourceSessionTitle) ?? "",
            generatedAt: try container.decodeIfPresent(Date.self, forKey: .generatedAt) ?? Date(),
            isAIGenerated: try container.decodeIfPresent(Bool.self, forKey: .isAIGenerated) ?? false,
            isUserConfirmed: try container.decodeIfPresent(Bool.self, forKey: .isUserConfirmed) ?? false,
            evidenceSummary: try container.decodeIfPresent(String.self, forKey: .evidenceSummary) ?? ""
        )
    }

    var score: Double {
        let numerator = Double(expectedImpact * confidence * urgency * strategicFit)
        return numerator / Double(max(effort + risk, 1))
    }

    var priorityLabel: String {
        if score >= 120 { return "高" }
        if score >= 60 { return "中" }
        return "低"
    }
}

struct DecisionMemo: Codable {
    var generatedAt: Date
    var markdown: String
    var aiSupplement: String
}

enum CorrectionMessageRole: String, Codable {
    case user
    case assistant

    var label: String {
        switch self {
        case .user: return "你"
        case .assistant: return "AI"
        }
    }
}

struct CorrectionMessage: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var role: CorrectionMessageRole
    var findingID: UUID?
    var findingTitle: String
    var content: String
}

struct AnalysisCorrectionMemory: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var packID: UUID
    var packName: String
    var findingID: UUID?
    var findingTitle: String
    var metric: String
    var scope: String
    var originalConclusion: String
    var userCorrection: String
    var revisedConclusion: String
    var reusableRule: String
    var tags: [String]
    var appliesToFuture: Bool
    var businessSpaceID: UUID?

    var summaryText: String {
        if !reusableRule.isEmpty { return reusableRule }
        if !revisedConclusion.isEmpty { return revisedConclusion }
        return userCorrection
    }
}

struct KnowledgeEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var businessSpaceID: UUID?
    var businessDomainIDs: [UUID]
    var rootPageID: String?
    var isGlobal: Bool
    var scenario: String
    var problem: String
    var action: String
    var result: String
    var evidenceLevel: EvidenceLevel
    var relatedPackName: String
    var sourceID: String?
    var sourcePath: String?
    var sourceURL: String?
    var sourceUpdatedAt: Date?
    var sourceCreatedAt: Date?
    var tags: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case businessSpaceID
        case businessDomainIDs
        case rootPageID
        case isGlobal
        case scenario
        case problem
        case action
        case result
        case evidenceLevel
        case relatedPackName
        case sourceID
        case sourcePath
        case sourceURL
        case sourceUpdatedAt
        case sourceCreatedAt
        case tags
    }

    init(
        id: UUID,
        createdAt: Date,
        businessSpaceID: UUID? = nil,
        businessDomainIDs: [UUID] = [],
        rootPageID: String? = nil,
        isGlobal: Bool = false,
        scenario: String,
        problem: String,
        action: String,
        result: String,
        evidenceLevel: EvidenceLevel,
        relatedPackName: String,
        sourceID: String? = nil,
        sourcePath: String? = nil,
        sourceURL: String? = nil,
        sourceUpdatedAt: Date? = nil,
        sourceCreatedAt: Date? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.businessSpaceID = businessSpaceID
        self.businessDomainIDs = businessDomainIDs
        self.rootPageID = rootPageID
        self.isGlobal = isGlobal
        self.scenario = scenario
        self.problem = problem
        self.action = action
        self.result = result
        self.evidenceLevel = evidenceLevel
        self.relatedPackName = relatedPackName
        self.sourceID = sourceID
        self.sourcePath = sourcePath
        self.sourceURL = sourceURL
        self.sourceUpdatedAt = sourceUpdatedAt
        self.sourceCreatedAt = sourceCreatedAt
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        businessSpaceID = try container.decodeIfPresent(UUID.self, forKey: .businessSpaceID)
        businessDomainIDs = try container.decodeIfPresent([UUID].self, forKey: .businessDomainIDs) ?? []
        rootPageID = try container.decodeIfPresent(String.self, forKey: .rootPageID)
        isGlobal = try container.decodeIfPresent(Bool.self, forKey: .isGlobal) ?? false
        scenario = try container.decodeIfPresent(String.self, forKey: .scenario) ?? "未归类场景"
        problem = try container.decodeIfPresent(String.self, forKey: .problem) ?? ""
        action = try container.decodeIfPresent(String.self, forKey: .action) ?? ""
        result = try container.decodeIfPresent(String.self, forKey: .result) ?? ""
        evidenceLevel = try container.decodeIfPresent(EvidenceLevel.self, forKey: .evidenceLevel) ?? .d
        relatedPackName = try container.decodeIfPresent(String.self, forKey: .relatedPackName) ?? ""
        sourceID = try container.decodeIfPresent(String.self, forKey: .sourceID)
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath)
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        sourceUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .sourceUpdatedAt)
        sourceCreatedAt = try container.decodeIfPresent(Date.self, forKey: .sourceCreatedAt)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

struct AISettings: Codable, Equatable {
    var endpoint: String
    var model: String
    var apiKey: String
    var systemPrompt: String

    init(endpoint: String, model: String, apiKey: String, systemPrompt: String) {
        self.endpoint = endpoint
        self.model = model
        self.apiKey = apiKey
        self.systemPrompt = systemPrompt
    }

    private enum CodingKeys: String, CodingKey {
        case endpoint
        case model
        case apiKey
        case systemPrompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? Self.default.endpoint
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? Self.default.model
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? Self.default.systemPrompt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(endpoint, forKey: .endpoint)
        try container.encode(model, forKey: .model)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(systemPrompt, forKey: .systemPrompt)
    }

    static let `default` = AISettings(
        endpoint: "https://api.openai.com/v1/chat/completions",
        model: "gpt-4o-mini",
        apiKey: "",
        systemPrompt: "你是严谨的金融产品/运营数据分析与迭代决策助手，面向海外小贷、信用卡、基金和券商业务。你必须区分事实、推断、假设和需补数据，为归因结论标注证据等级，不提供投资建议、收益承诺、规避监管或绕过风控的建议。"
    )
}

struct AppNotificationSettings: Codable, Equatable {
    var isEnabled: Bool
    var notifyWhenAppActive: Bool
    var notifyAIReplyCompleted: Bool
    var notifyReportGenerated: Bool

    static let `default` = AppNotificationSettings(
        isEnabled: true,
        notifyWhenAppActive: false,
        notifyAIReplyCompleted: true,
        notifyReportGenerated: true
    )
}

enum ConfluenceSyncStatus: String, Codable, Hashable {
    case success
    case failed

    var label: String {
        switch self {
        case .success: return "成功"
        case .failed: return "失败"
        }
    }
}

struct ConfluenceSyncRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var startedAt: Date
    var finishedAt: Date
    var sourceName: String
    var status: ConfluenceSyncStatus
    var totalPages: Int
    var matchedPages: Int
    var pageCountAfterSync: Int
    var addedKnowledgeEntries: Int
    var updatedKnowledgeEntries: Int
    var message: String

    init(
        id: UUID = UUID(),
        startedAt: Date,
        finishedAt: Date,
        sourceName: String,
        status: ConfluenceSyncStatus,
        totalPages: Int,
        matchedPages: Int,
        pageCountAfterSync: Int,
        addedKnowledgeEntries: Int,
        updatedKnowledgeEntries: Int,
        message: String
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.sourceName = sourceName
        self.status = status
        self.totalPages = totalPages
        self.matchedPages = matchedPages
        self.pageCountAfterSync = pageCountAfterSync
        self.addedKnowledgeEntries = addedKnowledgeEntries
        self.updatedKnowledgeEntries = updatedKnowledgeEntries
        self.message = message
    }
}

struct ConfluencePage: Identifiable, Codable, Hashable {
    static let storedTextLimit = 12_000

    var id: String
    var title: String
    var spaceKey: String
    var spaceName: String
    var createdAt: Date?
    var lastUpdated: Date?
    var syncedAt: Date?
    var updatedBy: String
    var version: Int?
    var url: String
    var ancestors: [String]
    var labels: [String]
    var excerpt: String
    var text: String
    var charCount: Int

    var scenario: String {
        KnowledgeClassifier.scenario(for: title, text: text, ancestors: ancestors)
    }

    var compactSummary: String {
        if !excerpt.isEmpty { return excerpt }
        return String(text.prefix(240))
    }

    func optimizedForStorage() -> ConfluencePage {
        guard text.count > Self.storedTextLimit else { return self }
        var copy = self
        copy.text = String(text.prefix(Self.storedTextLimit))
        return copy
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case spaceKey
        case spaceName
        case createdAt
        case lastUpdated
        case syncedAt
        case updatedBy
        case version
        case url
        case ancestors
        case labels
        case excerpt
        case text
        case charCount
    }

    init(
        id: String,
        title: String,
        spaceKey: String,
        spaceName: String,
        createdAt: Date? = nil,
        lastUpdated: Date?,
        syncedAt: Date? = nil,
        updatedBy: String,
        version: Int?,
        url: String,
        ancestors: [String],
        labels: [String],
        excerpt: String,
        text: String,
        charCount: Int
    ) {
        self.id = id
        self.title = title
        self.spaceKey = spaceKey
        self.spaceName = spaceName
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
        self.syncedAt = syncedAt
        self.updatedBy = updatedBy
        self.version = version
        self.url = url
        self.ancestors = ancestors
        self.labels = labels
        self.excerpt = excerpt
        self.text = text
        self.charCount = charCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        spaceKey = try container.decodeIfPresent(String.self, forKey: .spaceKey) ?? ""
        spaceName = try container.decodeIfPresent(String.self, forKey: .spaceName) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated)
        syncedAt = try container.decodeIfPresent(Date.self, forKey: .syncedAt)
        updatedBy = try container.decodeIfPresent(String.self, forKey: .updatedBy) ?? ""
        version = try container.decodeIfPresent(Int.self, forKey: .version)
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        ancestors = try container.decodeIfPresent([String].self, forKey: .ancestors) ?? []
        labels = try container.decodeIfPresent([String].self, forKey: .labels) ?? []
        excerpt = try container.decodeIfPresent(String.self, forKey: .excerpt) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        charCount = try container.decodeIfPresent(Int.self, forKey: .charCount) ?? text.count
    }
}

struct ConfluenceSettings: Codable, Equatable {
    var baseURL: String
    var rootPageIDs: String
    var titleKeywords: String
    var keychainService: String
    var keychainAccount: String
    var bearerToken: String
    var maxPages: Int

    static let `default` = ConfluenceSettings(
        baseURL: "https://docs.surfin-cn.com",
        rootPageIDs: "3637801",
        titleKeywords: "",
        keychainService: "confluence-docs-token",
        keychainAccount: NSUserName(),
        bearerToken: "",
        maxPages: 500
    )

    enum CodingKeys: String, CodingKey {
        case baseURL
        case rootPageIDs
        case titleKeywords
        case keychainService
        case keychainAccount
        case bearerToken
        case maxPages
    }

    init(
        baseURL: String,
        rootPageIDs: String,
        titleKeywords: String,
        keychainService: String,
        keychainAccount: String,
        bearerToken: String,
        maxPages: Int
    ) {
        self.baseURL = baseURL
        self.rootPageIDs = rootPageIDs
        self.titleKeywords = titleKeywords
        self.keychainService = keychainService
        self.keychainAccount = keychainAccount
        self.bearerToken = bearerToken
        self.maxPages = maxPages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? Self.default.baseURL
        rootPageIDs = try container.decodeIfPresent(String.self, forKey: .rootPageIDs) ?? Self.default.rootPageIDs
        titleKeywords = try container.decodeIfPresent(String.self, forKey: .titleKeywords) ?? ""
        keychainService = try container.decodeIfPresent(String.self, forKey: .keychainService) ?? Self.default.keychainService
        keychainAccount = try container.decodeIfPresent(String.self, forKey: .keychainAccount) ?? Self.default.keychainAccount
        bearerToken = try container.decodeIfPresent(String.self, forKey: .bearerToken) ?? ""
        maxPages = try container.decodeIfPresent(Int.self, forKey: .maxPages) ?? Self.default.maxPages
    }

    var parsedTitleKeywords: [String] {
        titleKeywords
            .components(separatedBy: CharacterSet(charactersIn: ",，;；\n\t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func matchesTitle(_ title: String) -> Bool {
        let keywords = parsedTitleKeywords
        guard !keywords.isEmpty else { return true }
        let normalizedTitle = title.lowercased()
        return keywords.contains { normalizedTitle.contains($0.lowercased()) }
    }
}

enum KnowledgeClassifier {
    static func scenario(for title: String, text: String, ancestors: [String]) -> String {
        let value = ([title] + ancestors + [String(text.prefix(800))]).joined(separator: " ").lowercased()
        let rules: [(String, [String])] = [
            ("注册/KYC/信审", ["注册", "kyc", "ocr", "活体", "授信", "信审", "征信", "buro", "circulo"]),
            ("风控/反欺诈", ["风控", "反欺诈", "falcon", "advance", "黑名单", "欺诈"]),
            ("卡生命周期/额度", ["额度", "开卡", "激活", "虚拟卡", "实体卡", "冻结", "锁卡", "tokenization", "token"]),
            ("账单/费用/利息", ["账单", "费用", "利息", "罚息", "年费", "statement"]),
            ("还款/分期", ["还款", "分期", "repayment", "installment", "stp", "toku", "openpay", "oxxo"]),
            ("交易/Dock/清算", ["交易", "dock", "visa", "授权", "清算", "冲正", "退款", "mcc"]),
            ("营销/活动/权益", ["营销", "活动", "优惠", "权益", "弹窗", "push", "短信", "coupon"]),
            ("数据/埋点/报表", ["数据", "埋点", "报表", "firebase", "adjust", "看板", "监控"]),
            ("后台/运营工具", ["后台", "客服", "催收", "运营", "工单", "导出"])
        ]

        return rules.first { _, keywords in
            keywords.contains { value.contains($0.lowercased()) }
        }?.0 ?? "产品文档"
    }
}
