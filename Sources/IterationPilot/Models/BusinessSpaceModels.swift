import Foundation

enum BusinessDomainRole: String, Codable, CaseIterable, Identifiable, Hashable {
    case primary
    case supporting
    case evidence

    var id: String { rawValue }

    var label: String {
        switch self {
        case .primary: return "主业务域"
        case .supporting: return "辅助业务域"
        case .evidence: return "旁证业务域"
        }
    }

    var explanation: String {
        switch self {
        case .primary:
            return "本业务空间的核心经营链路，AI 会优先围绕它组织分析和结论。"
        case .supporting:
            return "可能影响主业务或被主业务影响的业务域，用于联动分析。"
        case .evidence:
            return "用于解释或验证波动的辅助证据，不单独作为因果结论。"
        }
    }
}

struct BusinessDomain: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var description: String
    var coreFlowText: String
    var role: BusinessDomainRole

    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        coreFlowText: String = "",
        role: BusinessDomainRole = .supporting
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.coreFlowText = coreFlowText
        self.role = role
    }
}

struct BusinessDomainLink: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceDomainID: UUID?
    var targetDomainID: UUID?
    var sourceName: String
    var targetName: String
    var influenceMechanism: String
    var lagDays: Int?
    var evidenceRule: String

    init(
        id: UUID = UUID(),
        sourceDomainID: UUID? = nil,
        targetDomainID: UUID? = nil,
        sourceName: String,
        targetName: String,
        influenceMechanism: String,
        lagDays: Int? = nil,
        evidenceRule: String = ""
    ) {
        self.id = id
        self.sourceDomainID = sourceDomainID
        self.targetDomainID = targetDomainID
        self.sourceName = sourceName
        self.targetName = targetName
        self.influenceMechanism = influenceMechanism
        self.lagDays = lagDays
        self.evidenceRule = evidenceRule
    }
}

struct BusinessSpaceConfluenceRoot: Identifiable, Codable, Hashable {
    var id: UUID
    var rootPageID: String
    var title: String
    var businessDomainIDs: [UUID]
    var titleKeywordsText: String
    var exclusionKeywordsText: String
    var notes: String

    init(
        id: UUID = UUID(),
        rootPageID: String = "",
        title: String = "",
        businessDomainIDs: [UUID] = [],
        titleKeywordsText: String = "",
        exclusionKeywordsText: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.rootPageID = rootPageID
        self.title = title
        self.businessDomainIDs = businessDomainIDs
        self.titleKeywordsText = titleKeywordsText
        self.exclusionKeywordsText = exclusionKeywordsText
        self.notes = notes
    }

    var titleKeywords: [String] {
        Self.splitList(titleKeywordsText)
    }

    var exclusionKeywords: [String] {
        Self.splitList(exclusionKeywordsText)
    }

    private static func splitList(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",，;；\n\t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct BusinessSpaceMetricSemantic: Identifiable, Codable, Hashable {
    var id: UUID
    var metricName: String
    var sourceMessageID: UUID?
    var aliasesText: String
    var businessDomainIDs: [UUID]
    var businessStage: MetricBusinessStage
    var directionPreference: MetricDirectionPreference
    var maturityWindowDays: Int?
    var impactLagDays: Int?
    var relatedMetricsText: String
    var commonAnomalyExplanationsText: String
    var isUserConfirmed: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        metricName: String,
        sourceMessageID: UUID? = nil,
        aliasesText: String = "",
        businessDomainIDs: [UUID] = [],
        businessStage: MetricBusinessStage = .unknown,
        directionPreference: MetricDirectionPreference = .unknown,
        maturityWindowDays: Int? = nil,
        impactLagDays: Int? = nil,
        relatedMetricsText: String = "",
        commonAnomalyExplanationsText: String = "",
        isUserConfirmed: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.metricName = metricName
        self.sourceMessageID = sourceMessageID
        self.aliasesText = aliasesText
        self.businessDomainIDs = businessDomainIDs
        self.businessStage = businessStage
        self.directionPreference = directionPreference
        self.maturityWindowDays = maturityWindowDays
        self.impactLagDays = impactLagDays
        self.relatedMetricsText = relatedMetricsText
        self.commonAnomalyExplanationsText = commonAnomalyExplanationsText
        self.isUserConfirmed = isUserConfirmed
        self.updatedAt = updatedAt
    }
}

enum SmartMemoryKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case correctionRule
    case metricDefinition
    case analysisPreference
    case reportPreference
    case businessLinkRule
    case externalEventRule
    case dataSourceRule
    case analysisTemplate
    case reportKnowledge
    case knowledgeFact

    var id: String { rawValue }

    var label: String {
        switch self {
        case .correctionRule: return "纠偏规则"
        case .metricDefinition: return "指标口径"
        case .analysisPreference: return "分析偏好"
        case .reportPreference: return "报告偏好"
        case .businessLinkRule: return "业务链路"
        case .externalEventRule: return "外部事件规则"
        case .dataSourceRule: return "数据源经验"
        case .analysisTemplate: return "分析模板"
        case .reportKnowledge: return "报表解释"
        case .knowledgeFact: return "知识库事实"
        }
    }

    var tintName: String {
        switch self {
        case .correctionRule: return "red"
        case .metricDefinition: return "blue"
        case .analysisPreference: return "purple"
        case .reportPreference: return "green"
        case .businessLinkRule: return "orange"
        case .externalEventRule: return "teal"
        case .dataSourceRule: return "indigo"
        case .analysisTemplate: return "yellow"
        case .reportKnowledge: return "cyan"
        case .knowledgeFact: return "gray"
        }
    }
}

enum SmartMemoryCandidateStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case pending
    case adopted
    case ignored
    case archived

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pending: return "待确认"
        case .adopted: return "已采纳"
        case .ignored: return "已忽略"
        case .archived: return "已归档"
        }
    }
}

struct SmartMemoryCandidate: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var kind: SmartMemoryKind
    var status: SmartMemoryCandidateStatus
    var businessSpaceID: UUID?
    var sessionID: UUID?
    var messageID: UUID?
    var sourceReportID: UUID?
    var title: String
    var content: String
    var scope: String
    var rationale: String
    var confidence: Double
    var tags: [String]
    var adoptedMemoryID: UUID?
    var hitCount: Int
    var lastUsedAt: Date?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        kind: SmartMemoryKind,
        status: SmartMemoryCandidateStatus = .pending,
        businessSpaceID: UUID? = nil,
        sessionID: UUID? = nil,
        messageID: UUID? = nil,
        sourceReportID: UUID? = nil,
        title: String,
        content: String,
        scope: String = "当前业务空间",
        rationale: String = "",
        confidence: Double = 0.72,
        tags: [String] = [],
        adoptedMemoryID: UUID? = nil,
        hitCount: Int = 0,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.kind = kind
        self.status = status
        self.businessSpaceID = businessSpaceID
        self.sessionID = sessionID
        self.messageID = messageID
        self.sourceReportID = sourceReportID
        self.title = title
        self.content = content
        self.scope = scope
        self.rationale = rationale
        self.confidence = confidence
        self.tags = tags
        self.adoptedMemoryID = adoptedMemoryID
        self.hitCount = hitCount
        self.lastUsedAt = lastUsedAt
    }
}

struct SmartMemory: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: SmartMemoryKind
    var title: String
    var content: String
    var scope: String
    var businessSpaceID: UUID?
    var sourceID: String
    var sourceType: String
    var confidence: Double
    var priority: Int
    var tags: [String]
    var updatedAt: Date
    var hitCount: Int
    var lastUsedAt: Date?
    var isUserConfirmed: Bool

    init(
        id: UUID = UUID(),
        kind: SmartMemoryKind,
        title: String,
        content: String,
        scope: String,
        businessSpaceID: UUID? = nil,
        sourceID: String,
        sourceType: String,
        confidence: Double,
        priority: Int,
        tags: [String] = [],
        updatedAt: Date = Date(),
        hitCount: Int = 0,
        lastUsedAt: Date? = nil,
        isUserConfirmed: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.content = content
        self.scope = scope
        self.businessSpaceID = businessSpaceID
        self.sourceID = sourceID
        self.sourceType = sourceType
        self.confidence = confidence
        self.priority = priority
        self.tags = tags
        self.updatedAt = updatedAt
        self.hitCount = hitCount
        self.lastUsedAt = lastUsedAt
        self.isUserConfirmed = isUserConfirmed
    }
}

struct BusinessSpaceSnapshot: Codable, Hashable {
    var id: UUID
    var name: String
    var countryRegion: String
    var timeZoneIdentifier: String
    var currencyCode: String
    var primaryLanguagesText: String
    var businessBackground: String
    var domainNames: [String]
    var generatedSummary: String
    var capturedAt: Date
}

struct BusinessSpace: Identifiable, Codable, Hashable {
    var id: UUID
    var builtInKey: String?
    var name: String
    var countryRegion: String
    var timeZoneIdentifier: String
    var currencyCode: String
    var primaryLanguagesText: String
    var businessBackground: String
    var domains: [BusinessDomain]
    var domainLinks: [BusinessDomainLink]
    var metricClassificationRulesText: String
    var anomalyRulesText: String
    var analysisGuardrailsText: String
    var confluenceRoots: [BusinessSpaceConfluenceRoot]
    var recommendedSourceCategories: [ExternalReferenceIntelligenceCategory]
    var metricSemanticLibrary: [BusinessSpaceMetricSemantic]
    var generatedSummary: String
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        builtInKey: String? = nil,
        name: String,
        countryRegion: String = "",
        timeZoneIdentifier: String = TimeZone.current.identifier,
        currencyCode: String = Locale.current.currency?.identifier ?? "",
        primaryLanguagesText: String = Locale.current.language.languageCode?.identifier ?? "",
        businessBackground: String = "",
        domains: [BusinessDomain] = [],
        domainLinks: [BusinessDomainLink] = [],
        metricClassificationRulesText: String = "",
        anomalyRulesText: String = "",
        analysisGuardrailsText: String = "",
        confluenceRoots: [BusinessSpaceConfluenceRoot] = [],
        recommendedSourceCategories: [ExternalReferenceIntelligenceCategory] = [],
        metricSemanticLibrary: [BusinessSpaceMetricSemantic] = [],
        generatedSummary: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false
    ) {
        self.id = id
        self.builtInKey = builtInKey
        self.name = name
        self.countryRegion = countryRegion
        self.timeZoneIdentifier = timeZoneIdentifier
        self.currencyCode = currencyCode
        self.primaryLanguagesText = primaryLanguagesText
        self.businessBackground = businessBackground
        self.domains = domains
        self.domainLinks = domainLinks
        self.metricClassificationRulesText = metricClassificationRulesText
        self.anomalyRulesText = anomalyRulesText
        self.analysisGuardrailsText = analysisGuardrailsText
        self.confluenceRoots = confluenceRoots
        self.recommendedSourceCategories = recommendedSourceCategories
        self.metricSemanticLibrary = metricSemanticLibrary
        self.generatedSummary = generatedSummary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
    }

    var snapshot: BusinessSpaceSnapshot {
        BusinessSpaceSnapshot(
            id: id,
            name: name,
            countryRegion: countryRegion,
            timeZoneIdentifier: BusinessTimeZoneResolver.normalized(timeZoneIdentifier, for: self),
            currencyCode: currencyCode,
            primaryLanguagesText: primaryLanguagesText,
            businessBackground: businessBackground,
            domainNames: domains.map(\.name),
            generatedSummary: generatedSummary,
            capturedAt: Date()
        )
    }

    static var defaultSpace: BusinessSpace {
        BusinessSpace(
            name: "默认业务空间",
            businessBackground: BusinessSpace.backgroundPromptTemplate,
            generatedSummary: "旧 workspace 自动迁移到默认业务空间。请补充国家、业务域、核心链路和分析偏好后再生成业务地图。"
        )
    }

    static let backgroundPromptTemplate = """
    请描述这个业务空间：
    1. 我们在哪个国家/地区运营？
    2. 这是一个什么类型的产品？例如金融 App、本地生活 App、综合 App。
    3. 包含哪些业务域？例如信用卡、小贷、本地生活缴费、钱包、支付、活动、风控、客服。
    4. 每个业务域的核心流程是什么？
    5. 最关心哪些指标？这些指标越高越好还是越低越好？
    6. 哪些指标有成熟窗口或滞后影响？
    7. 哪些外部事件可能影响业务？例如天气、用电、节假日、政策、竞品活动。
    8. AI 分析时有哪些禁区或特别偏好？
    """
}

enum BusinessSpaceExampleKind: String, CaseIterable, Identifiable {
    case comprehensiveFinance
    case creditCardLocalLife
    case microLoan
    case blank

    var id: String { rawValue }

    var label: String {
        switch self {
        case .comprehensiveFinance: return "综合金融 App 示例"
        case .creditCardLocalLife: return "信用卡 + 本地生活缴费示例"
        case .microLoan: return "小贷业务示例"
        case .blank: return "空白自定义"
        }
    }

    var defaultName: String {
        switch self {
        case .comprehensiveFinance: return "综合金融 App"
        case .creditCardLocalLife: return "墨西哥 App"
        case .microLoan: return "小贷业务"
        case .blank: return "新业务空间"
        }
    }

    var countryRegion: String {
        switch self {
        case .comprehensiveFinance, .creditCardLocalLife, .microLoan: return "墨西哥"
        case .blank: return ""
        }
    }

    var currencyCode: String {
        switch self {
        case .comprehensiveFinance, .creditCardLocalLife, .microLoan: return "MXN"
        case .blank: return ""
        }
    }

    var languages: String {
        switch self {
        case .comprehensiveFinance, .creditCardLocalLife, .microLoan: return "zh-CN, es-MX, en"
        case .blank: return ""
        }
    }

    var background: String {
        switch self {
        case .blank:
            return BusinessSpace.backgroundPromptTemplate
        case .comprehensiveFinance:
            return """
            我们在墨西哥运营一个综合金融 App，包含信用卡、小贷、本地生活缴费、钱包、支付、风控、客服和活动运营。
            信用卡链路包括获客、申请、KYC、审批、授信、发卡、激活、首刷、复购和逾期风险；小贷链路包括获客、注册、授信、借款申请、审核、放款、还款和展期；本地生活缴费包括服务曝光、账单查询、缴费提交、支付成功和复缴。
            最关心新增用户、申请提交、审批通过率、授信完成、放款/发卡、首笔交易、本地生活缴费人数、交易金额、支付成功率、逾期和投诉。转化类指标通常越高越好，风险、失败、投诉、逾期越低越好。
            部分指标有成熟窗口：授信/审核可能滞后 1-7 天，首刷/消费可能滞后 7 天，还款和逾期需要更长窗口。天气、用电、节假日、政策、竞品补贴、渠道结构和系统稳定性都可能影响指标。
            AI 分析时必须先区分业务域，再做跨业务联动；Confluence 只代表需求记录时间，不等于上线时间；外部事件必须核对发生时间和地区。
            """
        case .creditCardLocalLife:
            return """
            我们在墨西哥运营一个 App，业务同时包含信用卡和本地生活缴费，两者不是互斥业务，而是同一个 App 内可能互相影响的业务域。
            信用卡核心流程：获客/安装、注册、申请、KYC、审批、授信、发卡、激活、首刷、持续消费。本地生活缴费核心流程：服务入口曝光、账单查询、电费/水费等账单确认、支付提交、支付成功、复缴。
            重点指标包括注册量、申请提交、KYC 完成、审批通过、授信完成、发卡/激活、首刷、缴费入口点击、缴费人数、缴费金额、支付成功率和投诉/失败。信用卡转化和缴费使用可能受到用户增长质量、页面体验、支付稳定性、用电需求、CFE/能源事件、天气和节假日影响。
            比例指标要看百分点变化，最新未成熟周期不能作为主比较周期。AI 要同时发现信用卡表内部问题、本地生活缴费表内部问题，以及两者是否出现“用户增长快但缴费增长弱”这类跨业务背离。
            """
        case .microLoan:
            return """
            我们在墨西哥运营小贷业务，核心流程包括渠道获客、注册、身份认证、授信评估、借款申请、审核、放款、还款、复借和逾期管理。
            重点指标包括安装、注册、KYC 完成、授信通过率、申请率、审核通过率、放款人数、放款金额、首借、复借、还款率、逾期率、拒绝原因、风控命中和客服投诉。转化和放款越高越好，但坏账、逾期、投诉、失败越低越好。
            风控策略、资金供给、政策监管、节假日、经济压力、渠道质量和竞品利率/额度变化都可能影响指标。AI 分析必须区分增长质量、风控收紧、资方约束和外部事件，不能只看单一转化率做因果判断。
            """
        }
    }
}
