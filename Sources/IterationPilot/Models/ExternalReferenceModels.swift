import Foundation

struct SearchAPISettings: Codable, Equatable {
    var tavilyEndpoint: String
    var tavilyAPIKey: String
    var didImportRivalRadarSources: Bool
    var didImportMexicoEventSources: Bool
    var didImportMexicoUtilitySources: Bool

    static let `default` = SearchAPISettings(
        tavilyEndpoint: "https://api.tavily.com/search",
        tavilyAPIKey: "",
        didImportRivalRadarSources: false,
        didImportMexicoEventSources: false,
        didImportMexicoUtilitySources: false
    )

    enum CodingKeys: String, CodingKey {
        case tavilyEndpoint
        case tavilyAPIKey
        case didImportRivalRadarSources
        case didImportMexicoEventSources
        case didImportMexicoUtilitySources
    }

    init(
        tavilyEndpoint: String,
        tavilyAPIKey: String,
        didImportRivalRadarSources: Bool,
        didImportMexicoEventSources: Bool,
        didImportMexicoUtilitySources: Bool = false
    ) {
        self.tavilyEndpoint = tavilyEndpoint
        self.tavilyAPIKey = tavilyAPIKey
        self.didImportRivalRadarSources = didImportRivalRadarSources
        self.didImportMexicoEventSources = didImportMexicoEventSources
        self.didImportMexicoUtilitySources = didImportMexicoUtilitySources
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tavilyEndpoint = try container.decodeIfPresent(String.self, forKey: .tavilyEndpoint) ?? Self.default.tavilyEndpoint
        tavilyAPIKey = try container.decodeIfPresent(String.self, forKey: .tavilyAPIKey) ?? ""
        didImportRivalRadarSources = try container.decodeIfPresent(Bool.self, forKey: .didImportRivalRadarSources) ?? false
        didImportMexicoEventSources = try container.decodeIfPresent(Bool.self, forKey: .didImportMexicoEventSources) ?? false
        didImportMexicoUtilitySources = try container.decodeIfPresent(Bool.self, forKey: .didImportMexicoUtilitySources) ?? false
    }
}

enum ExternalReferenceDomain: String, Codable, CaseIterable, Identifiable {
    case competitor
    case policy
    case market
    case externalEvent
    case manual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .competitor: return "竞品舆情"
        case .policy: return "政策/监管"
        case .market: return "市场参照"
        case .externalEvent: return "社会/自然事件"
        case .manual: return "人工备注"
        }
    }
}

enum ExternalReferenceCollectorType: String, Codable, CaseIterable, Identifiable {
    case manual
    case webPage
    case rss
    case searchAPI
    case tavilySearch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: return "人工填写"
        case .webPage: return "网页"
        case .rss: return "RSS"
        case .searchAPI: return "通用搜索接口"
        case .tavilySearch: return "Tavily 搜索"
        }
    }
}

enum ReferenceSourceLifecycleStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case candidate
    case tested
    case enabled
    case ignored
    case needsConfirmation

    var id: String { rawValue }

    var label: String {
        switch self {
        case .candidate: return "候选"
        case .tested: return "已测试"
        case .enabled: return "已启用"
        case .ignored: return "已忽略"
        case .needsConfirmation: return "需要人工确认"
        }
    }
}

struct ReferenceSourceDraft: Identifiable, Hashable {
    var id: UUID = UUID()
    var domain: ExternalReferenceDomain
    var name: String
    var collectorType: ExternalReferenceCollectorType
    var url: String
    var keywordsText: String
    var queryTemplate: String
    var manualNote: String

    init(domain: ExternalReferenceDomain) {
        self.domain = domain
        self.name = Self.defaultName(for: domain)
        self.collectorType = domain == .manual ? .manual : .tavilySearch
        self.url = ""
        self.keywordsText = ""
        self.queryTemplate = ""
        self.manualNote = ""
    }

    static func defaultName(for domain: ExternalReferenceDomain) -> String {
        switch domain {
        case .competitor: return "新的竞品数据源"
        case .policy: return "新的政策数据源"
        case .market: return "新的市场数据源"
        case .externalEvent: return "新的社会/自然事件源"
        case .manual: return "新的人工备注源"
        }
    }

    var sheetTitle: String {
        switch domain {
        case .competitor: return "新增竞品数据源"
        case .policy: return "新增政策数据源"
        case .market: return "新增市场数据源"
        case .externalEvent: return "新增事件数据源"
        case .manual: return "新增人工备注源"
        }
    }
}

struct ExternalReferenceSource: Identifiable, Codable, Hashable {
    var id: UUID
    var isGlobal: Bool
    var businessSpaceIDs: [UUID]
    var businessDomainIDs: [UUID]
    var lifecycleStatus: ReferenceSourceLifecycleStatus
    var recommendationReason: String
    var possibleImpactedMetricsText: String
    var officialDomainHint: String
    var createdByAI: Bool
    var name: String
    var domain: ExternalReferenceDomain
    var collectorType: ExternalReferenceCollectorType
    var url: String
    var keywordsText: String
    var queryTemplate: String
    var apiKey: String
    var searchTitlePath: String
    var searchURLPath: String
    var competitorName: String
    var competitorAliasesText: String
    var tavilyTopic: String
    var tavilySearchDepth: String
    var tavilyTimeRange: String
    var tavilyMaxResults: Int
    var tavilyIncludeRawContent: Bool
    var tavilyIncludeDomainsText: String
    var tavilyExcludeDomainsText: String
    var tavilyCountry: String
    var tavilyLanguageHintsText: String
    var tavilyQueryGroup: String
    var tavilySourceProfile: String
    var enabled: Bool
    var manualNote: String
    var lastFetchedAt: Date?

    var keywords: [String] {
        keywordsText
            .components(separatedBy: CharacterSet(charactersIn: ",，;；\n\t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var competitorAliases: [String] {
        Self.splitList(competitorAliasesText)
    }

    var tavilyIncludeDomains: [String] {
        Self.splitList(tavilyIncludeDomainsText)
    }

    var tavilyExcludeDomains: [String] {
        Self.splitList(tavilyExcludeDomainsText)
    }

    var tavilyLanguageHints: [String] {
        Self.splitList(tavilyLanguageHintsText)
    }

    init(
        id: UUID,
        isGlobal: Bool = false,
        businessSpaceIDs: [UUID] = [],
        businessDomainIDs: [UUID] = [],
        lifecycleStatus: ReferenceSourceLifecycleStatus? = nil,
        recommendationReason: String = "",
        possibleImpactedMetricsText: String = "",
        officialDomainHint: String = "",
        createdByAI: Bool = false,
        name: String,
        domain: ExternalReferenceDomain,
        collectorType: ExternalReferenceCollectorType,
        url: String,
        keywordsText: String,
        queryTemplate: String,
        apiKey: String = "",
        searchTitlePath: String = "title",
        searchURLPath: String = "url",
        competitorName: String = "",
        competitorAliasesText: String = "",
        tavilyTopic: String = "news",
        tavilySearchDepth: String = "basic",
        tavilyTimeRange: String = "week",
        tavilyMaxResults: Int = 5,
        tavilyIncludeRawContent: Bool = true,
        tavilyIncludeDomainsText: String = "",
        tavilyExcludeDomainsText: String = "",
        tavilyCountry: String = "",
        tavilyLanguageHintsText: String = "",
        tavilyQueryGroup: String = "",
        tavilySourceProfile: String = "",
        enabled: Bool,
        manualNote: String,
        lastFetchedAt: Date?
    ) {
        self.id = id
        self.isGlobal = isGlobal
        self.businessSpaceIDs = businessSpaceIDs
        self.businessDomainIDs = businessDomainIDs
        self.lifecycleStatus = lifecycleStatus ?? (enabled ? .enabled : .ignored)
        self.recommendationReason = recommendationReason
        self.possibleImpactedMetricsText = possibleImpactedMetricsText
        self.officialDomainHint = officialDomainHint
        self.createdByAI = createdByAI
        self.name = name
        self.domain = domain
        self.collectorType = collectorType
        self.url = url
        self.keywordsText = keywordsText
        self.queryTemplate = queryTemplate
        self.apiKey = apiKey
        self.searchTitlePath = searchTitlePath.isEmpty ? "title" : searchTitlePath
        self.searchURLPath = searchURLPath.isEmpty ? "url" : searchURLPath
        self.competitorName = competitorName
        self.competitorAliasesText = competitorAliasesText
        self.tavilyTopic = tavilyTopic.isEmpty ? "news" : tavilyTopic
        self.tavilySearchDepth = tavilySearchDepth.isEmpty ? "basic" : tavilySearchDepth
        self.tavilyTimeRange = tavilyTimeRange.isEmpty ? "week" : tavilyTimeRange
        self.tavilyMaxResults = min(max(tavilyMaxResults, 1), 20)
        self.tavilyIncludeRawContent = tavilyIncludeRawContent
        self.tavilyIncludeDomainsText = tavilyIncludeDomainsText
        self.tavilyExcludeDomainsText = tavilyExcludeDomainsText
        self.tavilyCountry = tavilyCountry
        self.tavilyLanguageHintsText = tavilyLanguageHintsText
        self.tavilyQueryGroup = tavilyQueryGroup
        self.tavilySourceProfile = tavilySourceProfile
        self.enabled = enabled
        self.manualNote = manualNote
        self.lastFetchedAt = lastFetchedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case isGlobal
        case businessSpaceIDs
        case businessDomainIDs
        case lifecycleStatus
        case recommendationReason
        case possibleImpactedMetricsText
        case officialDomainHint
        case createdByAI
        case name
        case domain
        case collectorType
        case url
        case keywordsText
        case queryTemplate
        case apiKey
        case searchTitlePath
        case searchURLPath
        case competitorName
        case competitorAliasesText
        case tavilyTopic
        case tavilySearchDepth
        case tavilyTimeRange
        case tavilyMaxResults
        case tavilyIncludeRawContent
        case tavilyIncludeDomainsText
        case tavilyExcludeDomainsText
        case tavilyCountry
        case tavilyLanguageHintsText
        case tavilyQueryGroup
        case tavilySourceProfile
        case enabled
        case manualNote
        case lastFetchedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            isGlobal: try container.decodeIfPresent(Bool.self, forKey: .isGlobal) ?? false,
            businessSpaceIDs: try container.decodeIfPresent([UUID].self, forKey: .businessSpaceIDs) ?? [],
            businessDomainIDs: try container.decodeIfPresent([UUID].self, forKey: .businessDomainIDs) ?? [],
            lifecycleStatus: try container.decodeIfPresent(ReferenceSourceLifecycleStatus.self, forKey: .lifecycleStatus),
            recommendationReason: try container.decodeIfPresent(String.self, forKey: .recommendationReason) ?? "",
            possibleImpactedMetricsText: try container.decodeIfPresent(String.self, forKey: .possibleImpactedMetricsText) ?? "",
            officialDomainHint: try container.decodeIfPresent(String.self, forKey: .officialDomainHint) ?? "",
            createdByAI: try container.decodeIfPresent(Bool.self, forKey: .createdByAI) ?? false,
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名参照源",
            domain: try container.decodeIfPresent(ExternalReferenceDomain.self, forKey: .domain) ?? .competitor,
            collectorType: try container.decodeIfPresent(ExternalReferenceCollectorType.self, forKey: .collectorType) ?? .manual,
            url: try container.decodeIfPresent(String.self, forKey: .url) ?? "",
            keywordsText: try container.decodeIfPresent(String.self, forKey: .keywordsText) ?? "",
            queryTemplate: try container.decodeIfPresent(String.self, forKey: .queryTemplate) ?? "",
            apiKey: try container.decodeIfPresent(String.self, forKey: .apiKey) ?? "",
            searchTitlePath: try container.decodeIfPresent(String.self, forKey: .searchTitlePath) ?? "title",
            searchURLPath: try container.decodeIfPresent(String.self, forKey: .searchURLPath) ?? "url",
            competitorName: try container.decodeIfPresent(String.self, forKey: .competitorName) ?? "",
            competitorAliasesText: try container.decodeIfPresent(String.self, forKey: .competitorAliasesText) ?? "",
            tavilyTopic: try container.decodeIfPresent(String.self, forKey: .tavilyTopic) ?? "news",
            tavilySearchDepth: try container.decodeIfPresent(String.self, forKey: .tavilySearchDepth) ?? "basic",
            tavilyTimeRange: try container.decodeIfPresent(String.self, forKey: .tavilyTimeRange) ?? "week",
            tavilyMaxResults: try container.decodeIfPresent(Int.self, forKey: .tavilyMaxResults) ?? 5,
            tavilyIncludeRawContent: try container.decodeIfPresent(Bool.self, forKey: .tavilyIncludeRawContent) ?? true,
            tavilyIncludeDomainsText: try container.decodeIfPresent(String.self, forKey: .tavilyIncludeDomainsText) ?? "",
            tavilyExcludeDomainsText: try container.decodeIfPresent(String.self, forKey: .tavilyExcludeDomainsText) ?? "",
            tavilyCountry: try container.decodeIfPresent(String.self, forKey: .tavilyCountry) ?? "",
            tavilyLanguageHintsText: try container.decodeIfPresent(String.self, forKey: .tavilyLanguageHintsText) ?? "",
            tavilyQueryGroup: try container.decodeIfPresent(String.self, forKey: .tavilyQueryGroup) ?? "",
            tavilySourceProfile: try container.decodeIfPresent(String.self, forKey: .tavilySourceProfile) ?? "",
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            manualNote: try container.decodeIfPresent(String.self, forKey: .manualNote) ?? "",
            lastFetchedAt: try container.decodeIfPresent(Date.self, forKey: .lastFetchedAt)
        )
    }

    static let defaults: [ExternalReferenceSource] = [
        ExternalReferenceSource(
            id: UUID(),
            name: "竞品动态手工记录",
            domain: .competitor,
            collectorType: .manual,
            url: "",
            keywordsText: "竞品, pricing, app, promotion",
            queryTemplate: "",
            apiKey: "",
            enabled: true,
            manualNote: "",
            lastFetchedAt: nil
        ),
        ExternalReferenceSource(
            id: UUID(),
            name: "政策/监管手工记录",
            domain: .policy,
            collectorType: .manual,
            url: "",
            keywordsText: "监管, 合规, 央行, 信贷, 信用卡",
            queryTemplate: "",
            apiKey: "",
            enabled: true,
            manualNote: "",
            lastFetchedAt: nil
        )
    ]

    static let mexicoEventDefaults: [ExternalReferenceSource] = [
        mexicoEventSource(
            name: "Mexico · Clima extremo · SMN/CONAGUA",
            keywords: "Mexico clima extremo, SMN, CONAGUA, aviso meteorologico, lluvias, huracan, ola de calor",
            query: "Mexico SMN CONAGUA aviso meteorologico lluvias huracan ola de calor",
            domains: "smn.conagua.gob.mx,conagua.gob.mx,gob.mx"
        ),
        mexicoEventSource(
            name: "Mexico · Desastres naturales · CNPC/CENAPRED",
            keywords: "Mexico desastre natural, Proteccion Civil, CENAPRED, alerta, inundacion, incendio, volcan",
            query: "Mexico Proteccion Civil CENAPRED alerta desastre natural volcan inundacion",
            domains: "proteccioncivil.gob.mx,cenapred.unam.mx,gob.mx"
        ),
        mexicoEventSource(
            name: "Mexico · Sismos · SSN UNAM",
            keywords: "Mexico sismo, terremoto, SSN, Servicio Sismologico Nacional",
            query: "Mexico SSN Servicio Sismologico Nacional sismo reciente",
            domains: "ssn.unam.mx"
        ),
        mexicoEventSource(
            name: "Mexico · Energia y electricidad · CFE/CENACE",
            keywords: "Mexico electricidad, CFE, CENACE, apagón, demanda electrica, energia",
            query: "Mexico CFE CENACE apagón demanda electrica energia",
            domains: "cfe.mx,cenace.gob.mx,gob.mx"
        ),
        mexicoEventSource(
            name: "Mexico · Feriados y eventos masivos",
            keywords: "Mexico feriado, dia festivo, SEP calendario, evento masivo, puente",
            query: "Mexico feriado dia festivo SEP calendario evento masivo",
            domains: "gob.mx,sep.gob.mx"
        ),
        mexicoEventSource(
            name: "Mexico · Transporte e infraestructura · SICT",
            keywords: "Mexico carretera, SICT, transporte, cierre vial, infraestructura, aeropuerto",
            query: "Mexico SICT carretera transporte cierre vial infraestructura aeropuerto",
            domains: "sct.gob.mx,sict.gob.mx,gob.mx"
        ),
        mexicoEventSource(
            name: "Mexico · Seguridad publica y protestas",
            keywords: "Mexico seguridad publica, protesta, paro, huelga, bloqueo, violencia",
            query: "Mexico seguridad publica protesta paro huelga bloqueo violencia",
            domains: "gob.mx,inegi.org.mx"
        ),
        mexicoEventSource(
            name: "Mexico · Economia local y consumo · INEGI",
            keywords: "Mexico INEGI economia local, consumo, comercio, precios, empleo",
            query: "Mexico INEGI economia local consumo comercio precios empleo",
            domains: "inegi.org.mx"
        )
    ]

    static let mexicoUtilityTavilyDefaults: [ExternalReferenceSource] = [
        mexicoUtilityTavilySource(
            name: "Mexico · CFE recibo y calendario de facturación",
            keywords: "Mexico CFE recibo luz, fecha limite de pago, periodo facturacion, bimestral, tarifa, calendario",
            query: "Mexico CFE recibo luz fecha limite pago periodo facturacion bimestral calendario tarifa",
            domains: "cfe.gob.mx,cfe.mx,gob.mx",
            queryGroup: "mexico_cfe_billing_calendar",
            sourceProfile: "official_cfe_billing",
            reason: "用于发现 CFE 官方账单、缴费期限、双月周期、费率或服务说明。注意：CFE 真实账单日通常与用户账户、地区和服务周期相关，该源只能作为周期线索，不能替代业务侧真实账单日历。",
            metrics: "CFE/电费缴费人数、缴费金额、缴费入口点击、支付成功率、客服咨询、退款/失败"
        ),
        mexicoUtilityTavilySource(
            name: "Mexico · CFE cortes y servicio eléctrico",
            keywords: "Mexico CFE corte, apagón, interrupcion servicio electrico, restablecimiento, falla energia",
            query: "Mexico CFE corte apagon interrupcion servicio electrico restablecimiento falla energia",
            domains: "cfe.gob.mx,cfe.mx,gob.mx",
            queryGroup: "mexico_cfe_outage_service",
            sourceProfile: "official_cfe_service",
            reason: "用于发现 CFE 停电、服务中断、恢复公告或地区性电力服务异常，作为缴费、支付、客服和本地生活波动的候选外部证据。",
            metrics: "电费缴费、支付成功率、客服咨询、活跃、交易失败、地区性本地生活服务"
        ),
        mexicoUtilityTavilySource(
            name: "Mexico · Demanda eléctrica · CENACE",
            keywords: "Mexico CENACE demanda real, demanda maxima, sistema electrico nacional, electricidad, energia",
            query: "Mexico CENACE demanda real demanda maxima sistema electrico nacional energia electrica",
            domains: "cenace.gob.mx,gob.mx",
            queryGroup: "mexico_electricity_demand_index",
            sourceProfile: "official_cenace_energy_index",
            reason: "用于发现 CENACE 电力需求、负荷或系统用电信息，辅助判断高温、节假日或区域用电需求是否可能影响电费缴费场景。",
            metrics: "电费缴费金额、生活缴费金额、用电相关需求、支付峰值、地区交易波动"
        ),
        mexicoUtilityTavilySource(
            name: "Mexico · Weather index · Open-Meteo/SMN",
            keywords: "Mexico weather index, Open-Meteo historical weather, SMN CONAGUA temperatura lluvia ola de calor",
            query: "Mexico Open-Meteo historical weather SMN CONAGUA temperatura lluvia ola de calor precipitation",
            domains: "open-meteo.com,smn.conagua.gob.mx,conagua.gob.mx,gob.mx",
            queryGroup: "mexico_weather_index_third_party",
            sourceProfile: "third_party_weather_index_official_crosscheck",
            reason: "用于发现可回溯的第三方天气指数/API 与 SMN/CONAGUA 官方天气事件，适合解释历史周期内高温、降雨、飓风、极端天气对本地生活、用电和交易的影响。",
            metrics: "电费缴费、生活缴费、交易、活跃、出行/本地生活、异常峰值"
        )
    ]

    private static func splitList(_ value: String) -> [String] {
        value
            .components(separatedBy: CharacterSet(charactersIn: ",，;；\n\t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var isUnbound: Bool {
        !isGlobal && businessSpaceIDs.isEmpty
    }

    func isBound(to businessSpaceID: UUID?) -> Bool {
        guard let businessSpaceID else { return false }
        return businessSpaceIDs.contains(businessSpaceID)
    }

    func isVisible(in businessSpaceID: UUID?) -> Bool {
        isGlobal || isBound(to: businessSpaceID)
    }

    private static func mexicoEventSource(name: String, keywords: String, query: String, domains: String) -> ExternalReferenceSource {
        ExternalReferenceSource(
            id: UUID(),
            name: name,
            domain: .externalEvent,
            collectorType: .tavilySearch,
            url: "",
            keywordsText: keywords,
            queryTemplate: query,
            apiKey: "",
            competitorName: "Mexico",
            tavilyTopic: "news",
            tavilySearchDepth: "advanced",
            tavilyTimeRange: "month",
            tavilyMaxResults: 8,
            tavilyIncludeRawContent: true,
            tavilyIncludeDomainsText: domains,
            tavilyCountry: "mexico",
            tavilyLanguageHintsText: "es,es-MX,en",
            tavilyQueryGroup: "mexico_external_events",
            tavilySourceProfile: "official_first",
            enabled: true,
            manualNote: "",
            lastFetchedAt: nil
        )
    }

    private static func mexicoUtilityTavilySource(
        name: String,
        keywords: String,
        query: String,
        domains: String,
        queryGroup: String,
        sourceProfile: String,
        reason: String,
        metrics: String
    ) -> ExternalReferenceSource {
        ExternalReferenceSource(
            id: UUID(),
            lifecycleStatus: .candidate,
            recommendationReason: reason,
            possibleImpactedMetricsText: metrics,
            officialDomainHint: domains,
            createdByAI: false,
            name: name,
            domain: .externalEvent,
            collectorType: .tavilySearch,
            url: "",
            keywordsText: keywords,
            queryTemplate: query,
            apiKey: "",
            competitorName: "Mexico",
            tavilyTopic: "news",
            tavilySearchDepth: "advanced",
            tavilyTimeRange: "month",
            tavilyMaxResults: 8,
            tavilyIncludeRawContent: true,
            tavilyIncludeDomainsText: domains,
            tavilyCountry: "mexico",
            tavilyLanguageHintsText: "es,es-MX,en",
            tavilyQueryGroup: queryGroup,
            tavilySourceProfile: sourceProfile,
            enabled: false,
            manualNote: "",
            lastFetchedAt: nil
        )
    }
}

enum ExternalReferenceIntelligenceCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case product
    case pricing
    case marketing
    case customer
    case funding
    case hiring
    case partnership
    case risk
    case technology
    case policy
    case market
    case weather
    case disaster
    case energy
    case holiday
    case traffic
    case publicSafety
    case localEconomy
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .product: return "产品"
        case .pricing: return "价格/费率"
        case .marketing: return "营销"
        case .customer: return "用户/客户"
        case .funding: return "融资/财务"
        case .hiring: return "招聘/组织"
        case .partnership: return "合作"
        case .risk: return "风险/舆情"
        case .technology: return "技术"
        case .policy: return "政策"
        case .market: return "市场"
        case .weather: return "天气/极端天气"
        case .disaster: return "自然灾害"
        case .energy: return "能源/用电/停电"
        case .holiday: return "节假日/大型活动"
        case .traffic: return "交通/基础设施"
        case .publicSafety: return "治安/罢工/抗议"
        case .localEconomy: return "本地经济/消费"
        case .other: return "其他"
        }
    }
}

enum ExternalReferenceCollectionTrigger: String, Codable, CaseIterable, Identifiable, Hashable {
    case manual
    case singleSourceTest
    case analysisFullContext
    case reportGeneration
    case backgroundRefresh

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: return "手动采集"
        case .singleSourceTest: return "测试此源"
        case .analysisFullContext: return "完整分析采集"
        case .reportGeneration: return "报告生成采集"
        case .backgroundRefresh: return "后台刷新"
        }
    }
}

enum ExternalReferenceCollectionStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case running
    case succeeded
    case partialFailed
    case failed
    case cancelled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .running: return "运行中"
        case .succeeded: return "成功"
        case .partialFailed: return "部分失败"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }
}

struct ExternalReferenceSourceRunLog: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceID: UUID?
    var sourceName: String
    var collectorType: ExternalReferenceCollectorType
    var domain: ExternalReferenceDomain
    var sourceProfile: String
    var queryGroup: String
    var renderedQuery: String
    var endpoint: String
    var tavilyTopic: String
    var tavilySearchDepth: String
    var tavilyTimeRange: String
    var tavilyMaxResults: Int
    var tavilyCountryInput: String?
    var tavilyCountrySent: String?
    var tavilyCountryDecision: String?
    var startedAt: Date
    var endedAt: Date?
    var durationMs: Int
    var status: ExternalReferenceCollectionStatus
    var httpStatusCode: Int?
    var rawItemCount: Int
    var validItemCount: Int
    var insertedItemCount: Int
    var knowledgeEntryCount: Int
    var errorMessage: String
    var cancellationReason: String?
    var timeoutReason: String?
    var networkDurationMs: Int?
    var analysisDurationMs: Int?

    init(
        id: UUID = UUID(),
        sourceID: UUID?,
        sourceName: String,
        collectorType: ExternalReferenceCollectorType,
        domain: ExternalReferenceDomain,
        sourceProfile: String = "",
        queryGroup: String = "",
        renderedQuery: String = "",
        endpoint: String = "",
        tavilyTopic: String = "",
        tavilySearchDepth: String = "",
        tavilyTimeRange: String = "",
        tavilyMaxResults: Int = 0,
        tavilyCountryInput: String? = nil,
        tavilyCountrySent: String? = nil,
        tavilyCountryDecision: String? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        durationMs: Int = 0,
        status: ExternalReferenceCollectionStatus = .running,
        httpStatusCode: Int? = nil,
        rawItemCount: Int = 0,
        validItemCount: Int = 0,
        insertedItemCount: Int = 0,
        knowledgeEntryCount: Int = 0,
        errorMessage: String = ""
    ) {
        self.id = id
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.collectorType = collectorType
        self.domain = domain
        self.sourceProfile = sourceProfile
        self.queryGroup = queryGroup
        self.renderedQuery = renderedQuery
        self.endpoint = endpoint
        self.tavilyTopic = tavilyTopic
        self.tavilySearchDepth = tavilySearchDepth
        self.tavilyTimeRange = tavilyTimeRange
        self.tavilyMaxResults = tavilyMaxResults
        self.tavilyCountryInput = tavilyCountryInput
        self.tavilyCountrySent = tavilyCountrySent
        self.tavilyCountryDecision = tavilyCountryDecision
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMs = durationMs
        self.status = status
        self.httpStatusCode = httpStatusCode
        self.rawItemCount = rawItemCount
        self.validItemCount = validItemCount
        self.insertedItemCount = insertedItemCount
        self.knowledgeEntryCount = knowledgeEntryCount
        self.errorMessage = errorMessage
        self.cancellationReason = nil
        self.timeoutReason = nil
        self.networkDurationMs = nil
        self.analysisDurationMs = nil
    }
}

struct ExternalReferenceCollectionRun: Identifiable, Codable, Hashable {
    var id: UUID
    var trigger: ExternalReferenceCollectionTrigger
    var status: ExternalReferenceCollectionStatus
    var businessSpaceID: UUID?
    var packID: UUID?
    var taskID: UUID?
    var sessionID: UUID?
    var contextMode: AnalysisContextMode?
    var evidenceWindow: ExternalEvidenceWindow?
    var startedAt: Date
    var endedAt: Date?
    var sourceLogs: [ExternalReferenceSourceRunLog]
    var enabledSourceCount: Int
    var successfulSourceCount: Int
    var failedSourceCount: Int
    var rawItemCount: Int
    var insertedItemCount: Int
    var duplicateItemCount: Int
    var irrelevantItemCount: Int
    var knowledgeEntryCount: Int
    var errorMessage: String
    var timeBudgetSeconds: Int?
    var timedOut: Bool?
    var cancelledByUser: Bool?
    var phase: String?
    var completedSourceCount: Int?
    var analyzedItemCount: Int?
    var pendingItemCount: Int?

    init(
        id: UUID = UUID(),
        trigger: ExternalReferenceCollectionTrigger,
        status: ExternalReferenceCollectionStatus = .running,
        businessSpaceID: UUID? = nil,
        packID: UUID? = nil,
        taskID: UUID? = nil,
        sessionID: UUID? = nil,
        contextMode: AnalysisContextMode? = nil,
        evidenceWindow: ExternalEvidenceWindow? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        sourceLogs: [ExternalReferenceSourceRunLog] = [],
        enabledSourceCount: Int = 0,
        successfulSourceCount: Int = 0,
        failedSourceCount: Int = 0,
        rawItemCount: Int = 0,
        insertedItemCount: Int = 0,
        duplicateItemCount: Int = 0,
        irrelevantItemCount: Int = 0,
        knowledgeEntryCount: Int = 0,
        errorMessage: String = "",
        timeBudgetSeconds: Int? = nil,
        timedOut: Bool? = nil,
        cancelledByUser: Bool? = nil,
        phase: String? = nil,
        completedSourceCount: Int? = nil,
        analyzedItemCount: Int? = nil,
        pendingItemCount: Int? = nil
    ) {
        self.id = id
        self.trigger = trigger
        self.status = status
        self.businessSpaceID = businessSpaceID
        self.packID = packID
        self.taskID = taskID
        self.sessionID = sessionID
        self.contextMode = contextMode
        self.evidenceWindow = evidenceWindow
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sourceLogs = sourceLogs
        self.enabledSourceCount = enabledSourceCount
        self.successfulSourceCount = successfulSourceCount
        self.failedSourceCount = failedSourceCount
        self.rawItemCount = rawItemCount
        self.insertedItemCount = insertedItemCount
        self.duplicateItemCount = duplicateItemCount
        self.irrelevantItemCount = irrelevantItemCount
        self.knowledgeEntryCount = knowledgeEntryCount
        self.errorMessage = errorMessage
        self.timeBudgetSeconds = timeBudgetSeconds
        self.timedOut = timedOut
        self.cancelledByUser = cancelledByUser
        self.phase = phase
        self.completedSourceCount = completedSourceCount
        self.analyzedItemCount = analyzedItemCount
        self.pendingItemCount = pendingItemCount
    }

    var summary: String {
        let timeoutText = timedOut == true ? " · 已超时降级" : ""
        let phaseText = phase.map { " · \($0)" } ?? ""
        return "\(trigger.label) · \(status.label)\(timeoutText)\(phaseText) · 源 \(successfulSourceCount)/\(enabledSourceCount) · 命中 \(rawItemCount) · 新增 \(insertedItemCount) · 去重 \(duplicateItemCount) · 过滤 \(irrelevantItemCount)"
    }
}

struct ExternalReferenceItem: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceID: UUID
    var businessSpaceID: UUID?
    var businessDomainIDs: [UUID]
    var sourceName: String
    var domain: ExternalReferenceDomain
    var title: String
    var url: String
    var summary: String
    var rawContent: String
    var collectedAt: Date
    var publishedAt: Date?
    var eventStartedAt: Date?
    var eventEndedAt: Date?
    var dateBasis: ExternalReferenceDateBasis
    var dateConfidence: Double
    var keywords: [String]
    var normalizedURL: String
    var urlHash: String
    var titleHash: String
    var contentHash: String
    var intelligenceCategory: ExternalReferenceIntelligenceCategory
    var impact: String
    var importance: Int
    var isRelevant: Bool
    var relevanceReason: String
    var analyzedAt: Date?
    var analysisWarning: String?
    var knowledgeEntryID: UUID?
    var collectionRunID: UUID?
    var sourceRunLogID: UUID?

    var displayDate: Date {
        eventStartedAt ?? publishedAt ?? collectedAt
    }

    var resolvedDateBasis: ExternalReferenceDateBasis {
        if eventStartedAt != nil { return .eventTime }
        if publishedAt != nil { return .publishedAt }
        return .collectedAt
    }

    var resolvedDateConfidence: Double {
        switch resolvedDateBasis {
        case .eventTime:
            return max(dateConfidence, 0.75)
        case .publishedAt:
            return max(dateConfidence, 0.6)
        case .collectedAt:
            return min(dateConfidence, 0.35)
        }
    }

    var dateBasisLabel: String {
        resolvedDateBasis.label
    }

    var dateCaveat: String {
        resolvedDateBasis.caveat
    }

    func isVisible(in businessSpaceID: UUID?, sourceByID: [UUID: ExternalReferenceSource]) -> Bool {
        if self.businessSpaceID == businessSpaceID, businessSpaceID != nil {
            return true
        }
        guard self.businessSpaceID == nil,
              let source = sourceByID[sourceID] else {
            return false
        }
        return source.isGlobal
    }

    init(
        id: UUID = UUID(),
        sourceID: UUID,
        businessSpaceID: UUID? = nil,
        businessDomainIDs: [UUID] = [],
        sourceName: String,
        domain: ExternalReferenceDomain,
        title: String,
        url: String,
        summary: String,
        rawContent: String = "",
        collectedAt: Date,
        publishedAt: Date?,
        eventStartedAt: Date? = nil,
        eventEndedAt: Date? = nil,
        dateBasis: ExternalReferenceDateBasis? = nil,
        dateConfidence: Double? = nil,
        keywords: [String],
        normalizedURL: String = "",
        urlHash: String = "",
        titleHash: String = "",
        contentHash: String = "",
        intelligenceCategory: ExternalReferenceIntelligenceCategory = .other,
        impact: String = "",
        importance: Int = 2,
        isRelevant: Bool = true,
        relevanceReason: String = "",
        analyzedAt: Date? = nil,
        analysisWarning: String? = nil,
        knowledgeEntryID: UUID? = nil,
        collectionRunID: UUID? = nil,
        sourceRunLogID: UUID? = nil
    ) {
        self.id = id
        self.sourceID = sourceID
        self.businessSpaceID = businessSpaceID
        self.businessDomainIDs = businessDomainIDs
        self.sourceName = sourceName
        self.domain = domain
        self.title = title
        self.url = url
        self.summary = summary
        self.rawContent = rawContent
        self.collectedAt = collectedAt
        self.publishedAt = publishedAt
        self.eventStartedAt = eventStartedAt
        self.eventEndedAt = eventEndedAt
        self.dateBasis = dateBasis ?? Self.inferredDateBasis(eventStartedAt: eventStartedAt, publishedAt: publishedAt)
        self.dateConfidence = min(max(dateConfidence ?? Self.defaultDateConfidence(eventStartedAt: eventStartedAt, publishedAt: publishedAt), 0), 1)
        self.keywords = keywords
        self.normalizedURL = normalizedURL
        self.urlHash = urlHash
        self.titleHash = titleHash
        self.contentHash = contentHash
        self.intelligenceCategory = intelligenceCategory
        self.impact = impact
        self.importance = min(max(importance, 1), 5)
        self.isRelevant = isRelevant
        self.relevanceReason = relevanceReason
        self.analyzedAt = analyzedAt
        self.analysisWarning = analysisWarning
        self.knowledgeEntryID = knowledgeEntryID
        self.collectionRunID = collectionRunID
        self.sourceRunLogID = sourceRunLogID
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sourceID
        case businessSpaceID
        case businessDomainIDs
        case sourceName
        case domain
        case title
        case url
        case summary
        case rawContent
        case collectedAt
        case publishedAt
        case eventStartedAt
        case eventEndedAt
        case dateBasis
        case dateConfidence
        case keywords
        case normalizedURL
        case urlHash
        case titleHash
        case contentHash
        case intelligenceCategory
        case impact
        case importance
        case isRelevant
        case relevanceReason
        case analyzedAt
        case analysisWarning
        case knowledgeEntryID
        case collectionRunID
        case sourceRunLogID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            sourceID: try container.decodeIfPresent(UUID.self, forKey: .sourceID) ?? UUID(),
            businessSpaceID: try container.decodeIfPresent(UUID.self, forKey: .businessSpaceID),
            businessDomainIDs: try container.decodeIfPresent([UUID].self, forKey: .businessDomainIDs) ?? [],
            sourceName: try container.decodeIfPresent(String.self, forKey: .sourceName) ?? "未知来源",
            domain: try container.decodeIfPresent(ExternalReferenceDomain.self, forKey: .domain) ?? .competitor,
            title: try container.decodeIfPresent(String.self, forKey: .title) ?? "未命名情报",
            url: try container.decodeIfPresent(String.self, forKey: .url) ?? "",
            summary: try container.decodeIfPresent(String.self, forKey: .summary) ?? "",
            rawContent: try container.decodeIfPresent(String.self, forKey: .rawContent) ?? "",
            collectedAt: try container.decodeIfPresent(Date.self, forKey: .collectedAt) ?? Date(),
            publishedAt: try container.decodeIfPresent(Date.self, forKey: .publishedAt),
            eventStartedAt: try container.decodeIfPresent(Date.self, forKey: .eventStartedAt),
            eventEndedAt: try container.decodeIfPresent(Date.self, forKey: .eventEndedAt),
            dateBasis: try container.decodeIfPresent(ExternalReferenceDateBasis.self, forKey: .dateBasis),
            dateConfidence: try container.decodeIfPresent(Double.self, forKey: .dateConfidence),
            keywords: try container.decodeIfPresent([String].self, forKey: .keywords) ?? [],
            normalizedURL: try container.decodeIfPresent(String.self, forKey: .normalizedURL) ?? "",
            urlHash: try container.decodeIfPresent(String.self, forKey: .urlHash) ?? "",
            titleHash: try container.decodeIfPresent(String.self, forKey: .titleHash) ?? "",
            contentHash: try container.decodeIfPresent(String.self, forKey: .contentHash) ?? "",
            intelligenceCategory: try container.decodeIfPresent(ExternalReferenceIntelligenceCategory.self, forKey: .intelligenceCategory) ?? .other,
            impact: try container.decodeIfPresent(String.self, forKey: .impact) ?? "",
            importance: try container.decodeIfPresent(Int.self, forKey: .importance) ?? 2,
            isRelevant: try container.decodeIfPresent(Bool.self, forKey: .isRelevant) ?? true,
            relevanceReason: try container.decodeIfPresent(String.self, forKey: .relevanceReason) ?? "",
            analyzedAt: try container.decodeIfPresent(Date.self, forKey: .analyzedAt),
            analysisWarning: try container.decodeIfPresent(String.self, forKey: .analysisWarning),
            knowledgeEntryID: try container.decodeIfPresent(UUID.self, forKey: .knowledgeEntryID),
            collectionRunID: try container.decodeIfPresent(UUID.self, forKey: .collectionRunID),
            sourceRunLogID: try container.decodeIfPresent(UUID.self, forKey: .sourceRunLogID)
        )
    }

    private static func inferredDateBasis(eventStartedAt: Date?, publishedAt: Date?) -> ExternalReferenceDateBasis {
        if eventStartedAt != nil { return .eventTime }
        if publishedAt != nil { return .publishedAt }
        return .collectedAt
    }

    private static func defaultDateConfidence(eventStartedAt: Date?, publishedAt: Date?) -> Double {
        if eventStartedAt != nil { return 0.85 }
        if publishedAt != nil { return 0.65 }
        return 0.25
    }
}

enum ExternalReferenceDateBasis: String, Codable, CaseIterable, Identifiable, Hashable {
    case eventTime
    case publishedAt
    case collectedAt

    var id: String { rawValue }

    var label: String {
        switch self {
        case .eventTime: return "事件发生时间"
        case .publishedAt: return "内容发布时间"
        case .collectedAt: return "采集时间"
        }
    }

    var caveat: String {
        switch self {
        case .eventTime:
            return ""
        case .publishedAt:
            return "这是内容发布时间，不一定等于事件真实发生时间；归因时需要核对事件窗口。"
        case .collectedAt:
            return "没有拿到内容发布时间或事件发生时间，当前只能按采集时间作为弱线索，不能作为高置信归因依据。"
        }
    }

    var reliabilityScore: Int {
        switch self {
        case .eventTime: return 4
        case .publishedAt: return 3
        case .collectedAt: return 1
        }
    }
}
