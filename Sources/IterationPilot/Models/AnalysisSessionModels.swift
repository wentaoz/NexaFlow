import Foundation

enum AnalysisSessionStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case draft
    case analyzing
    case waitingForUser
    case reportReady
    case archived

    var id: String { rawValue }

    var label: String {
        switch self {
        case .draft: return "草稿"
        case .analyzing: return "AI 分析中"
        case .waitingForUser: return "等待追问"
        case .reportReady: return "汇报已生成"
        case .archived: return "已归档"
        }
    }
}

enum AnalysisSessionMessageRole: String, Codable, Hashable {
    case user
    case assistant
    case system

    var label: String {
        switch self {
        case .user: return "你"
        case .assistant: return "AI"
        case .system: return "系统"
        }
    }
}

enum AnalysisSessionMessageKind: String, Codable, Hashable {
    case userRequest
    case aiAnalysis
    case aiMemo
    case simpleReport
    case systemCoverage
    case adoption
    case error
}

enum AnalysisMessageCorrectionStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case none
    case challenged
    case candidateGenerated
    case savedAsCorrectionRule
    case supersededByCorrection

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "未纠偏"
        case .challenged: return "被质疑"
        case .candidateGenerated: return "已生成纠偏候选"
        case .savedAsCorrectionRule: return "已保存纠偏规则"
        case .supersededByCorrection: return "已被纠偏覆盖"
        }
    }

    var excludesFromFinalConclusion: Bool {
        self == .supersededByCorrection
    }
}

enum AnalysisMessageReportInclusion: String, Codable, CaseIterable, Identifiable, Hashable {
    case automatic
    case included
    case excluded

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "自动判断"
        case .included: return "纳入汇报"
        case .excluded: return "不纳入汇报"
        }
    }
}

enum ReportGenerationScopeKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case fullConversation
    case selectedQuestions
    case customPeriod

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fullConversation: return "当前会话"
        case .selectedQuestions: return "指定问题"
        case .customPeriod: return "指定周期"
        }
    }

    var requiresQuestion: Bool {
        self == .selectedQuestions
    }

    var requiresPeriod: Bool {
        self == .customPeriod
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "fullConversation":
            self = .fullConversation
        case "selectedQuestion", "selectedQuestions", "customTopicAndPeriod":
            self = .selectedQuestions
        case "customPeriod":
            self = .customPeriod
        default:
            self = .fullConversation
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct ReportGenerationScope: Codable, Hashable {
    var kind: ReportGenerationScopeKind
    var selectedQuestionIDs: [UUID]
    var selectedQuestionTexts: [String]
    var selectedQuestionID: UUID?
    var selectedQuestionText: String
    var customPeriodText: String

    init(
        kind: ReportGenerationScopeKind = .fullConversation,
        selectedQuestionIDs: [UUID] = [],
        selectedQuestionTexts: [String] = [],
        selectedQuestionID: UUID? = nil,
        selectedQuestionText: String = "",
        customPeriodText: String = ""
    ) {
        self.kind = kind
        self.selectedQuestionIDs = selectedQuestionIDs
        self.selectedQuestionTexts = selectedQuestionTexts
        self.selectedQuestionID = selectedQuestionID
        self.selectedQuestionText = selectedQuestionText
        self.customPeriodText = customPeriodText
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case selectedQuestionIDs
        case selectedQuestionTexts
        case selectedQuestionID
        case selectedQuestionText
        case customPeriodText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(ReportGenerationScopeKind.self, forKey: .kind) ?? .fullConversation
        selectedQuestionIDs = try container.decodeIfPresent([UUID].self, forKey: .selectedQuestionIDs) ?? []
        selectedQuestionTexts = try container.decodeIfPresent([String].self, forKey: .selectedQuestionTexts) ?? []
        selectedQuestionID = try container.decodeIfPresent(UUID.self, forKey: .selectedQuestionID)
        selectedQuestionText = try container.decodeIfPresent(String.self, forKey: .selectedQuestionText) ?? ""
        customPeriodText = try container.decodeIfPresent(String.self, forKey: .customPeriodText) ?? ""

        if let selectedQuestionID, selectedQuestionIDs.isEmpty {
            selectedQuestionIDs = [selectedQuestionID]
        }
        if !selectedQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           selectedQuestionTexts.isEmpty {
            selectedQuestionTexts = [selectedQuestionText]
        }
        if kind == .selectedQuestions, selectedQuestionIDs.isEmpty, selectedQuestionTexts.isEmpty {
            kind = .fullConversation
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(selectedQuestionIDs, forKey: .selectedQuestionIDs)
        try container.encode(selectedQuestionTexts, forKey: .selectedQuestionTexts)
        try container.encode(selectedQuestionIDs.first, forKey: .selectedQuestionID)
        try container.encode(selectedQuestionTexts.first ?? "", forKey: .selectedQuestionText)
        try container.encode(customPeriodText, forKey: .customPeriodText)
    }

    var displayLabel: String {
        switch kind {
        case .fullConversation:
            return "当前会话"
        case .selectedQuestions:
            let count = max(selectedQuestionIDs.count, selectedQuestionTexts.count)
            return count > 0 ? "指定问题 \(count) 条" : "指定问题"
        case .customPeriod:
            let period = customPeriodText.trimmingCharacters(in: .whitespacesAndNewlines)
            return period.isEmpty ? "指定周期" : period
        }
    }

    var promptMarkdown: String {
        let questions = selectedQuestionTexts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let period = customPeriodText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .fullConversation:
            return """
            汇报范围：当前会话全部有效业务问题。
            周期要求：用户未在汇报范围中额外指定周期时，按当前会话和用户问题判断；如仍未指定，必须写明“全周期概览”。
            """
        case .selectedQuestions:
            let questionText = questions.enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
            return """
            汇报范围：只围绕以下用户问题生成汇报，其他会话内容只能作为背景证据。
            指定问题：
            \(questionText.isEmpty ? "未找到指定问题，需在汇报中说明范围缺失。" : questionText)
            周期要求：如这些问题未指定周期，必须写明周期来源或全周期概览。
            """
        case .customPeriod:
            return """
            汇报范围：围绕指定周期生成汇报。
            指定周期：\(period.isEmpty ? "未填写指定周期，需在汇报中说明范围缺失。" : period)
            周期要求：表格分析和外部证据采集必须优先围绕该周期；无法覆盖时写入缺口，不能静默换成其他周期。
            """
        }
    }
}

struct AnalysisSessionEvidence: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceType: String
    var title: String
    var detail: String
    var sourceID: String?
    var sourceURL: String?
    var analysisHarnessRun: AnalysisHarnessRun?

    init(
        id: UUID = UUID(),
        sourceType: String,
        title: String,
        detail: String,
        sourceID: String? = nil,
        sourceURL: String? = nil,
        analysisHarnessRun: AnalysisHarnessRun? = nil
    ) {
        self.id = id
        self.sourceType = sourceType
        self.title = title
        self.detail = detail
        self.sourceID = sourceID
        self.sourceURL = sourceURL
        self.analysisHarnessRun = analysisHarnessRun
    }
}

enum AnalysisMessageStreamingStatusState: String, Codable, Hashable {
    case reasoning
    case completed
    case correcting
    case fallback
}

struct AnalysisMessageStreamingStatus: Codable, Hashable {
    var state: AnalysisMessageStreamingStatusState
    var title: String
    var detail: String
    var updatedAt: Date

    init(
        state: AnalysisMessageStreamingStatusState,
        title: String,
        detail: String,
        updatedAt: Date = Date()
    ) {
        self.state = state
        self.title = title
        self.detail = detail
        self.updatedAt = updatedAt
    }
}

struct AnalysisSessionMessage: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var role: AnalysisSessionMessageRole
    var kind: AnalysisSessionMessageKind
    var content: String
    var streamingStatus: AnalysisMessageStreamingStatus?
    var evidence: [AnalysisSessionEvidence]
    var adoptedAs: [String]
    var replyToMessageID: UUID?
    var quotedMessageSummary: String?
    var correctionStatus: AnalysisMessageCorrectionStatus
    var supersededByMessageID: UUID?
    var savedCorrectionMemoryID: UUID?
    var reportInclusion: AnalysisMessageReportInclusion

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        role: AnalysisSessionMessageRole,
        kind: AnalysisSessionMessageKind,
        content: String,
        streamingStatus: AnalysisMessageStreamingStatus? = nil,
        evidence: [AnalysisSessionEvidence] = [],
        adoptedAs: [String] = [],
        replyToMessageID: UUID? = nil,
        quotedMessageSummary: String? = nil,
        correctionStatus: AnalysisMessageCorrectionStatus = .none,
        supersededByMessageID: UUID? = nil,
        savedCorrectionMemoryID: UUID? = nil,
        reportInclusion: AnalysisMessageReportInclusion = .automatic
    ) {
        self.id = id
        self.createdAt = createdAt
        self.role = role
        self.kind = kind
        self.content = content
        self.streamingStatus = streamingStatus
        self.evidence = evidence
        self.adoptedAs = adoptedAs
        self.replyToMessageID = replyToMessageID
        self.quotedMessageSummary = quotedMessageSummary
        self.correctionStatus = correctionStatus
        self.supersededByMessageID = supersededByMessageID
        self.savedCorrectionMemoryID = savedCorrectionMemoryID
        self.reportInclusion = reportInclusion
    }

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case role
        case kind
        case content
        case streamingStatus
        case evidence
        case adoptedAs
        case replyToMessageID
        case quotedMessageSummary
        case correctionStatus
        case supersededByMessageID
        case savedCorrectionMemoryID
        case reportInclusion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        role = try container.decodeIfPresent(AnalysisSessionMessageRole.self, forKey: .role) ?? .system
        kind = try container.decodeIfPresent(AnalysisSessionMessageKind.self, forKey: .kind) ?? .systemCoverage
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        streamingStatus = try container.decodeIfPresent(AnalysisMessageStreamingStatus.self, forKey: .streamingStatus)
        evidence = try container.decodeIfPresent([AnalysisSessionEvidence].self, forKey: .evidence) ?? []
        adoptedAs = try container.decodeIfPresent([String].self, forKey: .adoptedAs) ?? []
        replyToMessageID = try container.decodeIfPresent(UUID.self, forKey: .replyToMessageID)
        quotedMessageSummary = try container.decodeIfPresent(String.self, forKey: .quotedMessageSummary)
        correctionStatus = try container.decodeIfPresent(AnalysisMessageCorrectionStatus.self, forKey: .correctionStatus) ?? .none
        supersededByMessageID = try container.decodeIfPresent(UUID.self, forKey: .supersededByMessageID)
        savedCorrectionMemoryID = try container.decodeIfPresent(UUID.self, forKey: .savedCorrectionMemoryID)
        reportInclusion = try container.decodeIfPresent(AnalysisMessageReportInclusion.self, forKey: .reportInclusion) ?? .automatic
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(role, forKey: .role)
        try container.encode(kind, forKey: .kind)
        try container.encode(content, forKey: .content)
        try container.encode(evidence, forKey: .evidence)
        try container.encode(adoptedAs, forKey: .adoptedAs)
        try container.encodeIfPresent(replyToMessageID, forKey: .replyToMessageID)
        try container.encodeIfPresent(quotedMessageSummary, forKey: .quotedMessageSummary)
        try container.encode(correctionStatus, forKey: .correctionStatus)
        try container.encodeIfPresent(supersededByMessageID, forKey: .supersededByMessageID)
        try container.encodeIfPresent(savedCorrectionMemoryID, forKey: .savedCorrectionMemoryID)
        try container.encode(reportInclusion, forKey: .reportInclusion)
    }
}

struct ReportRequirementDigest: Codable, Hashable {
    var generatedAt: Date
    var sessionGoal: String
    var userRequests: [String]
    var corrections: [String]
    var requiredFocus: [String]
    var challengedConclusions: [String]
    var supersededConclusions: [String]
    var adoptedCorrectionRules: [String]

    enum CodingKeys: String, CodingKey {
        case generatedAt
        case sessionGoal
        case userRequests
        case corrections
        case requiredFocus
        case challengedConclusions
        case supersededConclusions
        case adoptedCorrectionRules
    }

    init(
        generatedAt: Date = Date(),
        sessionGoal: String = "",
        userRequests: [String] = [],
        corrections: [String] = [],
        requiredFocus: [String] = [],
        challengedConclusions: [String] = [],
        supersededConclusions: [String] = [],
        adoptedCorrectionRules: [String] = []
    ) {
        self.generatedAt = generatedAt
        self.sessionGoal = sessionGoal
        self.userRequests = userRequests
        self.corrections = corrections
        self.requiredFocus = requiredFocus
        self.challengedConclusions = challengedConclusions
        self.supersededConclusions = supersededConclusions
        self.adoptedCorrectionRules = adoptedCorrectionRules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt) ?? Date()
        sessionGoal = try container.decodeIfPresent(String.self, forKey: .sessionGoal) ?? ""
        userRequests = try container.decodeIfPresent([String].self, forKey: .userRequests) ?? []
        corrections = try container.decodeIfPresent([String].self, forKey: .corrections) ?? []
        requiredFocus = try container.decodeIfPresent([String].self, forKey: .requiredFocus) ?? []
        challengedConclusions = try container.decodeIfPresent([String].self, forKey: .challengedConclusions) ?? []
        supersededConclusions = try container.decodeIfPresent([String].self, forKey: .supersededConclusions) ?? []
        adoptedCorrectionRules = try container.decodeIfPresent([String].self, forKey: .adoptedCorrectionRules) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(sessionGoal, forKey: .sessionGoal)
        try container.encode(userRequests, forKey: .userRequests)
        try container.encode(corrections, forKey: .corrections)
        try container.encode(requiredFocus, forKey: .requiredFocus)
        try container.encode(challengedConclusions, forKey: .challengedConclusions)
        try container.encode(supersededConclusions, forKey: .supersededConclusions)
        try container.encode(adoptedCorrectionRules, forKey: .adoptedCorrectionRules)
    }

    var coveredQuestionCount: Int {
        max(userRequests.count, sessionGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
    }

    var markdown: String {
        func list(_ items: [String], empty: String) -> String {
            guard !items.isEmpty else { return empty }
            return items.enumerated().map { index, item in
                "\(index + 1). \(item)"
            }.joined(separator: "\n")
        }

        return """
        生成时间：\(DateFormatting.shortDateTime.string(from: generatedAt))
        首问目标：\(sessionGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未记录" : sessionGoal)

        用户明确问题（\(coveredQuestionCount) 个）：
        \(list(userRequests, empty: "暂无明确用户问题。"))

        用户修正的口径：
        \(list(corrections, empty: "暂无明确口径修正。"))

        必须关注的周期、指标、业务域或外部事件：
        \(list(requiredFocus, empty: "暂无额外指定重点。"))

        用户明确质疑或否定过的结论：
        \(list(challengedConclusions, empty: "暂无明确质疑。"))

        已被纠偏覆盖、不能作为最终结论的旧 AI 内容：
        \(list(supersededConclusions, empty: "暂无被纠偏覆盖的旧结论。"))

        最终应采用的纠偏规则 / 修正口径：
        \(list(adoptedCorrectionRules, empty: "暂无已保存纠偏规则。"))
        """
    }
}

struct AnalysisSession: Identifiable, Codable, Hashable {
    var id: UUID
    var packID: UUID
    var taskID: UUID?
    var businessSpaceID: UUID?
    var businessSpaceSnapshot: BusinessSpaceSnapshot?
    var title: String
    var goal: String
    var selectedReportIDs: [UUID]
    var status: AnalysisSessionStatus
    var messages: [AnalysisSessionMessage]
    var coverageSnapshots: [AnalysisCoverageSnapshot]?
    var notebookRuns: [AnalysisNotebookRun]
    var contextSummary: String
    var finalMemoMarkdown: String
    var finalReportMarkdown: String
    var simpleReportMarkdown: String
    var reportRequirementDigest: ReportRequirementDigest?
    var contextCache: AnalysisContextCache?
    var tags: [String]
    var sourcePackDeleted: Bool?
    var sourcePackName: String?
    var createdAt: Date
    var updatedAt: Date
    var lastReportGeneratedAt: Date?
    var lastSimpleReportGeneratedAt: Date?

    init(
        id: UUID = UUID(),
        packID: UUID,
        taskID: UUID? = nil,
        businessSpaceID: UUID? = nil,
        businessSpaceSnapshot: BusinessSpaceSnapshot? = nil,
        title: String,
        goal: String = "",
        selectedReportIDs: [UUID] = [],
        status: AnalysisSessionStatus = .draft,
        messages: [AnalysisSessionMessage] = [],
        coverageSnapshots: [AnalysisCoverageSnapshot] = [],
        notebookRuns: [AnalysisNotebookRun] = [],
        contextSummary: String = "",
        finalMemoMarkdown: String = "",
        finalReportMarkdown: String = "",
        simpleReportMarkdown: String = "",
        reportRequirementDigest: ReportRequirementDigest? = nil,
        contextCache: AnalysisContextCache? = nil,
        tags: [String] = [],
        sourcePackDeleted: Bool? = nil,
        sourcePackName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastReportGeneratedAt: Date? = nil,
        lastSimpleReportGeneratedAt: Date? = nil
    ) {
        self.id = id
        self.packID = packID
        self.taskID = taskID
        self.businessSpaceID = businessSpaceID
        self.businessSpaceSnapshot = businessSpaceSnapshot
        self.title = title
        self.goal = goal
        self.selectedReportIDs = selectedReportIDs.uniqued()
        self.status = status
        self.messages = messages
        self.coverageSnapshots = coverageSnapshots
        self.notebookRuns = notebookRuns
        self.contextSummary = contextSummary
        self.finalMemoMarkdown = finalMemoMarkdown
        self.finalReportMarkdown = finalReportMarkdown
        self.simpleReportMarkdown = simpleReportMarkdown
        self.reportRequirementDigest = reportRequirementDigest
        self.contextCache = contextCache
        self.tags = tags
        self.sourcePackDeleted = sourcePackDeleted
        self.sourcePackName = sourcePackName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastReportGeneratedAt = lastReportGeneratedAt
        self.lastSimpleReportGeneratedAt = lastSimpleReportGeneratedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case packID
        case taskID
        case businessSpaceID
        case businessSpaceSnapshot
        case title
        case goal
        case selectedReportIDs
        case status
        case messages
        case coverageSnapshots
        case notebookRuns
        case contextSummary
        case finalMemoMarkdown
        case finalReportMarkdown
        case simpleReportMarkdown
        case reportRequirementDigest
        case contextCache
        case tags
        case sourcePackDeleted
        case sourcePackName
        case createdAt
        case updatedAt
        case lastReportGeneratedAt
        case lastSimpleReportGeneratedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        packID = try container.decodeIfPresent(UUID.self, forKey: .packID) ?? UUID()
        taskID = try container.decodeIfPresent(UUID.self, forKey: .taskID)
        businessSpaceID = try container.decodeIfPresent(UUID.self, forKey: .businessSpaceID)
        businessSpaceSnapshot = try container.decodeIfPresent(BusinessSpaceSnapshot.self, forKey: .businessSpaceSnapshot)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "分析会话"
        goal = try container.decodeIfPresent(String.self, forKey: .goal) ?? ""
        selectedReportIDs = try container.decodeIfPresent([UUID].self, forKey: .selectedReportIDs) ?? []
        status = try container.decodeIfPresent(AnalysisSessionStatus.self, forKey: .status) ?? .draft
        messages = try container.decodeIfPresent([AnalysisSessionMessage].self, forKey: .messages) ?? []
        coverageSnapshots = try container.decodeIfPresent([AnalysisCoverageSnapshot].self, forKey: .coverageSnapshots) ?? []
        notebookRuns = try container.decodeIfPresent([AnalysisNotebookRun].self, forKey: .notebookRuns) ?? []
        contextSummary = try container.decodeIfPresent(String.self, forKey: .contextSummary) ?? ""
        finalMemoMarkdown = try container.decodeIfPresent(String.self, forKey: .finalMemoMarkdown) ?? ""
        finalReportMarkdown = try container.decodeIfPresent(String.self, forKey: .finalReportMarkdown) ?? ""
        simpleReportMarkdown = try container.decodeIfPresent(String.self, forKey: .simpleReportMarkdown) ?? ""
        reportRequirementDigest = try container.decodeIfPresent(ReportRequirementDigest.self, forKey: .reportRequirementDigest)
        contextCache = try container.decodeIfPresent(AnalysisContextCache.self, forKey: .contextCache)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        sourcePackDeleted = try container.decodeIfPresent(Bool.self, forKey: .sourcePackDeleted)
        sourcePackName = try container.decodeIfPresent(String.self, forKey: .sourcePackName)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        lastReportGeneratedAt = try container.decodeIfPresent(Date.self, forKey: .lastReportGeneratedAt)
        lastSimpleReportGeneratedAt = try container.decodeIfPresent(Date.self, forKey: .lastSimpleReportGeneratedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(packID, forKey: .packID)
        try container.encodeIfPresent(taskID, forKey: .taskID)
        try container.encodeIfPresent(businessSpaceID, forKey: .businessSpaceID)
        try container.encodeIfPresent(businessSpaceSnapshot, forKey: .businessSpaceSnapshot)
        try container.encode(title, forKey: .title)
        try container.encode(goal, forKey: .goal)
        try container.encode(selectedReportIDs, forKey: .selectedReportIDs)
        try container.encode(status, forKey: .status)
        try container.encode(messages, forKey: .messages)
        try container.encodeIfPresent(coverageSnapshots, forKey: .coverageSnapshots)
        try container.encode(notebookRuns, forKey: .notebookRuns)
        try container.encode(contextSummary, forKey: .contextSummary)
        try container.encode(finalMemoMarkdown, forKey: .finalMemoMarkdown)
        try container.encode(finalReportMarkdown, forKey: .finalReportMarkdown)
        try container.encode(simpleReportMarkdown, forKey: .simpleReportMarkdown)
        try container.encodeIfPresent(reportRequirementDigest, forKey: .reportRequirementDigest)
        try container.encodeIfPresent(contextCache, forKey: .contextCache)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(sourcePackDeleted, forKey: .sourcePackDeleted)
        try container.encodeIfPresent(sourcePackName, forKey: .sourcePackName)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(lastReportGeneratedAt, forKey: .lastReportGeneratedAt)
        try container.encodeIfPresent(lastSimpleReportGeneratedAt, forKey: .lastSimpleReportGeneratedAt)
    }
}
