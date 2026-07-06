import Foundation

struct BusinessMapDraft {
    var domains: [BusinessDomain]
    var links: [BusinessDomainLink]
    var metricRules: String
    var anomalyRules: String
    var guardrails: String
    var sourceCategories: [ExternalReferenceIntelligenceCategory]
    var summary: String
}

struct BusinessSpaceProfileDraft {
    var name: String
    var countryRegion: String
    var timeZoneIdentifier: String
    var currencyCode: String
    var primaryLanguagesText: String
    var businessBackground: String
    var mapDraft: BusinessMapDraft
}

enum BusinessSpaceAIService {
    static func localProfileDraft(name: String, businessBackground: String) -> BusinessSpaceProfileDraft {
        var space = BusinessSpace(
            name: name.nilIfBlank ?? "新业务空间",
            businessBackground: businessBackground.nilIfBlank ?? BusinessSpace.backgroundPromptTemplate
        )
        let normalized = "\(name)\n\(businessBackground)".normalizedKey
        if containsAny(normalized, ["墨西哥", "mexico", "méxico"]) {
            space.countryRegion = "墨西哥"
            space.timeZoneIdentifier = "America/Mexico_City"
            space.currencyCode = "MXN"
            space.primaryLanguagesText = "zh-CN, es-MX, en"
        } else if containsAny(normalized, ["菲律宾", "philippines"]) {
            space.countryRegion = "菲律宾"
            space.timeZoneIdentifier = "Asia/Manila"
            space.currencyCode = "PHP"
            space.primaryLanguagesText = "zh-CN, fil-PH, en"
        } else if containsAny(normalized, ["哥伦比亚", "colombia"]) {
            space.countryRegion = "哥伦比亚"
            space.timeZoneIdentifier = "America/Bogota"
            space.currencyCode = "COP"
            space.primaryLanguagesText = "zh-CN, es-CO, en"
        }
        let mapDraft = localBusinessMapDraft(for: space)
        return BusinessSpaceProfileDraft(
            name: space.name,
            countryRegion: space.countryRegion,
            timeZoneIdentifier: space.timeZoneIdentifier,
            currencyCode: space.currencyCode,
            primaryLanguagesText: space.primaryLanguagesText,
            businessBackground: space.businessBackground,
            mapDraft: mapDraft
        )
    }

    static func profilePrompt(space: BusinessSpace) -> String {
        """
        你是 NexaFlow 的业务空间识别助手。请从用户自然语言背景中识别基础配置和业务地图，避免让用户手动填写语言、币种、时区。
        \(FinancialPromptPolicy.businessSpaceRules)

        # 用户填写
        名称：\(space.name)
        业务背景：
        \(space.businessBackground)

        # 输出 JSON
        只输出 JSON 对象：
        {
          "name": "业务空间名称",
          "country_region": "国家/地区",
          "timezone": "IANA 时区，例如 America/Mexico_City",
          "currency": "三位币种，例如 MXN",
          "languages": "主要语言，用逗号分隔",
          "summary": "业务地图摘要",
          "domains": [
            {"name": "业务域", "description": "说明", "core_flow": "核心链路", "role": "primary|supporting|evidence"}
          ],
          "links": [
            {"source": "来源业务域", "target": "目标业务域", "mechanism": "影响机制", "lag_days": 0, "evidence_rule": "证据规则"}
          ],
          "metric_rules": "指标分类规则",
          "anomaly_rules": "常见异常解释",
          "guardrails": "分析禁区和证据规则"
        }

        规则：
        - 如果无法确定字段，请给最合理候选并在 summary 里说明需要用户检查。
        - 业务地图只用于分类和归因组织，不能限制后续表格指标扫描范围。
        - 信用卡、小贷、本地生活缴费、钱包、支付等可以共存。
        """
    }

    static func parseProfileDraft(_ text: String, fallback: BusinessSpace) -> BusinessSpaceProfileDraft? {
        let jsonText = extractJSONObject(from: text)
        guard let data = jsonText.data(using: .utf8),
              let payload = try? JSONDecoder().decode(BusinessSpaceProfilePayload.self, from: data) else {
            return nil
        }
        let baseMap = localBusinessMapDraft(for: fallback)
        let domains = (payload.domains ?? []).prefix(16).map { domain in
            BusinessDomain(
                name: domain.name?.nilIfBlank ?? "业务域",
                description: domain.description ?? "",
                coreFlowText: domain.coreFlow ?? "",
                role: BusinessDomainRole(rawValue: domain.role ?? "") ?? .supporting
            )
        }
        let domainByName = Dictionary(uniqueKeysWithValues: domains.map { ($0.name.normalizedKey, $0) })
        let links = (payload.links ?? []).prefix(24).map { link -> BusinessDomainLink in
            let source = link.source.flatMap { domainByName[$0.normalizedKey] }
            let target = link.target.flatMap { domainByName[$0.normalizedKey] }
            return BusinessDomainLink(
                sourceDomainID: source?.id,
                targetDomainID: target?.id,
                sourceName: link.source ?? source?.name ?? "",
                targetName: link.target ?? target?.name ?? "",
                influenceMechanism: link.mechanism ?? "",
                lagDays: link.lagDays,
                evidenceRule: link.evidenceRule ?? ""
            )
        }
        let mapDraft = BusinessMapDraft(
            domains: domains.isEmpty ? baseMap.domains : domains,
            links: links.isEmpty ? baseMap.links : links,
            metricRules: payload.metricRules?.nilIfBlank ?? baseMap.metricRules,
            anomalyRules: payload.anomalyRules?.nilIfBlank ?? baseMap.anomalyRules,
            guardrails: payload.guardrails?.nilIfBlank ?? baseMap.guardrails,
            sourceCategories: baseMap.sourceCategories,
            summary: payload.summary?.nilIfBlank ?? baseMap.summary
        )
        return BusinessSpaceProfileDraft(
            name: payload.name?.nilIfBlank ?? fallback.name,
            countryRegion: payload.countryRegion?.nilIfBlank ?? fallback.countryRegion,
            timeZoneIdentifier: BusinessTimeZoneResolver.resolve(
                timeZoneIdentifier: payload.timezone?.nilIfBlank ?? fallback.timeZoneIdentifier,
                countryRegion: payload.countryRegion?.nilIfBlank ?? fallback.countryRegion,
                businessBackground: fallback.businessBackground,
                businessSpaceName: payload.name?.nilIfBlank ?? fallback.name
            ),
            currencyCode: payload.currency?.nilIfBlank ?? fallback.currencyCode,
            primaryLanguagesText: payload.languages?.nilIfBlank ?? fallback.primaryLanguagesText,
            businessBackground: fallback.businessBackground,
            mapDraft: mapDraft
        )
    }

    static func businessMapPrompt(space: BusinessSpace) -> String {
        """
        你是 NexaFlow 的业务空间建模助手。请根据用户自然语言背景生成可编辑业务地图，不要把示例当成固定互斥模板。
        \(FinancialPromptPolicy.businessSpaceRules)

        # 业务空间
        名称：\(space.name)
        国家/地区：\(space.countryRegion.isEmpty ? "未填写" : space.countryRegion)
        时区：\(space.timeZoneIdentifier)
        币种：\(space.currencyCode.isEmpty ? "未填写" : space.currencyCode)
        语言：\(space.primaryLanguagesText.isEmpty ? "未填写" : space.primaryLanguagesText)

        # 用户填写的业务背景
        \(space.businessBackground)

        # 输出要求
        用 Markdown 输出，包含：
        ## 业务域
        ## 核心链路
        ## 跨业务域影响关系
        ## 指标分类规则
        ## 常见异常解释
        ## Confluence Root Page 配置建议
        ## 推荐外部数据源类别
        ## 分析禁区和证据规则

        注意：
        - 业务链路只用于分类、排序和归因组织，不能限制表格指标扫描范围。
        - 信用卡、小贷、本地生活缴费、钱包、支付等可以在同一业务空间共存。
        - “申请 / 审批 / 放款”等通用词不能单独判断业务域，必须结合 Root Page、表名、指标、上下文。
        - Confluence 文档创建/修改时间只代表需求记录时间，不等于真实上线时间。
        """
    }

    static func localBusinessMapDraft(for space: BusinessSpace) -> BusinessMapDraft {
        let text = "\(space.name)\n\(space.businessBackground)".normalizedKey
        var domains: [BusinessDomain] = []

        func add(_ name: String, description: String, flow: String, role: BusinessDomainRole = .supporting) {
            guard !domains.contains(where: { $0.name.normalizedKey == name.normalizedKey }) else { return }
            domains.append(BusinessDomain(name: name, description: description, coreFlowText: flow, role: role))
        }

        if text.contains("信用卡") || text.contains("card") {
            add("信用卡", description: "信用卡申请、审批、授信、发卡、激活和消费链路。", flow: "获客 → 注册 → 申请 → KYC → 审批 → 授信 → 发卡 → 激活 → 首刷 → 持续消费", role: .primary)
        }
        if text.contains("小贷") || text.contains("loan") || text.contains("借款") {
            add("小贷", description: "现金贷/小额信贷申请、放款、还款和复借链路。", flow: "获客 → 注册 → KYC → 授信 → 借款申请 → 审核 → 放款 → 还款 → 复借", role: domains.isEmpty ? .primary : .supporting)
        }
        if text.contains("缴费") || text.contains("本地生活") || text.contains("电费") || text.contains("水费") {
            add("本地生活缴费", description: "生活账单查询、缴费提交、支付成功和复缴链路。", flow: "入口曝光 → 点击 → 账单查询 → 缴费提交 → 支付成功 → 复缴", role: domains.isEmpty ? .primary : .supporting)
        }
        if text.contains("钱包") || text.contains("支付") || text.contains("wallet") {
            add("钱包/支付", description: "钱包余额、支付、绑卡、充值和提现链路。", flow: "入口曝光 → 绑卡/充值 → 支付提交 → 支付成功 → 复用", role: .supporting)
        }
        if text.contains("基金") || text.contains("fund") || text.contains("aum") || text.contains("申购") || text.contains("赎回") {
            add("基金", description: "基金开户、风险测评、入金、申购、赎回、AUM 和留存链路。", flow: "获客 → 开户/KYC → 风险测评 → 入金 → 申购 → 持仓/AUM → 赎回/复投 → 留存", role: domains.isEmpty ? .primary : .supporting)
        }
        if text.contains("券商") || text.contains("broker") || text.contains("证券") || text.contains("股票") || text.contains("交易") {
            add("券商", description: "证券平台开户、入金、行情访问、下单、成交、活跃和合规链路。", flow: "获客 → 开户/KYC → 入金 → 行情访问 → 下单 → 成交 → 持续交易 → 留存", role: domains.isEmpty ? .primary : .supporting)
        }
        if text.contains("风控") || text.contains("risk") || text.contains("逾期") {
            add("风控", description: "身份、反欺诈、信用评估、拒绝原因和贷后风险。", flow: "资料采集 → 风控评分 → 策略命中 → 审批决策 → 贷后监控", role: .evidence)
        }
        if domains.isEmpty {
            add("主业务", description: "用户描述中的主要业务。", flow: "获客 → 转化 → 交易/使用 → 留存 → 复购", role: .primary)
        }

        let links = inferredLinks(domains: domains)
        let sourceCategories: [ExternalReferenceIntelligenceCategory] = [
            .product, .marketing, .policy, .weather, .disaster, .energy, .holiday, .traffic, .publicSafety, .localEconomy, .market
        ]

        return BusinessMapDraft(
            domains: domains,
            links: links,
            metricRules: """
            1. 表格导入后必须扫描全部字段、全部首列指标、全部时间列。
            2. 先把指标映射到业务域和链路节点；未映射指标进入体验、技术、客服、运营、财务、风控、营销或外部事件补充维度。
            3. 新增、疑似改名、疑似口径变化和缺失历史指标在分析会话中追问，不单独弹确认流程。
            4. 未确认指标可以参与趋势观察，但不能作为高置信结论的唯一依据。
            """,
            anomalyRules: """
            - 注册/申请上涨但下游交易或缴费弱：优先检查用户质量、入口曝光、页面行为、KYC/短信/支付稳定性和候选滞后口径。
            - 比例指标变化使用“百分点”；涉及滞后指标时只作为候选口径提示，不能预先替用户排除周期。
            - 外部事件必须核对发生时间、地区、人群和影响机制；只有采集时间的情报只能作为弱线索。
            """,
            guardrails: """
            - Confluence 文档创建/修改时间只代表需求记录时间，不等于真实上线时间。
            - 不允许只靠“申请/审批/放款”等通用词判断业务域。
            - 业务地图不限制指标范围，链路外指标必须保留并解释。
            """,
            sourceCategories: sourceCategories,
            summary: "已根据业务背景生成可编辑业务地图草稿：\(domains.map(\.name).joined(separator: "、"))。"
        )
    }

    static func localReferenceSourceCandidates(for space: BusinessSpace) -> [ExternalReferenceSource] {
        let country = space.countryRegion.nilIfBlank ?? "目标国家"
        let countryAliases = searchCountryAliases(for: country)
        let countryQuery = countryAliases.joined(separator: " ")
        let spaceID = space.id
        let domainIDs = space.domains.map(\.id)
        let languageHints = space.primaryLanguagesText.nilIfBlank ?? defaultLanguageHints(for: country)
        let businessTerms = ([space.name] + space.domains.map(\.name)).filter { !$0.isEmpty }
        let commonKeywords = (businessTerms + countryAliases).uniqued().joined(separator: ", ")

        func candidate(
            name: String,
            domain: ExternalReferenceDomain,
            category: String,
            query: String,
            officialHint: String = "",
            metrics: String = "",
            queryGroup: String,
            sourceProfile: String,
            topic: String = "news",
            lifecycleStatus: ReferenceSourceLifecycleStatus = .candidate,
            competitorName: String? = nil,
            competitorAliases: String = ""
        ) -> ExternalReferenceSource {
            ExternalReferenceSource(
                id: UUID(),
                businessSpaceIDs: [spaceID],
                businessDomainIDs: domainIDs,
                lifecycleStatus: lifecycleStatus,
                recommendationReason: "根据业务空间「\(space.name)」推荐：\(category)",
                possibleImpactedMetricsText: metrics,
                officialDomainHint: officialHint,
                createdByAI: true,
                name: name,
                domain: domain,
                collectorType: .tavilySearch,
                url: "",
                keywordsText: commonKeywords,
                queryTemplate: query,
                apiKey: "",
                competitorName: competitorName ?? country,
                competitorAliasesText: competitorAliases,
                tavilyTopic: topic,
                tavilySearchDepth: "advanced",
                tavilyTimeRange: "month",
                tavilyMaxResults: 8,
                tavilyIncludeRawContent: true,
                tavilyIncludeDomainsText: officialHint,
                tavilyCountry: countryQuery.lowercased(),
                tavilyLanguageHintsText: languageHints,
                tavilyQueryGroup: queryGroup,
                tavilySourceProfile: sourceProfile,
                enabled: false,
                manualNote: "候选源：请先测试此源或编辑后启用。",
                lastFetchedAt: nil
            )
        }

        var candidates: [ExternalReferenceSource] = [
            candidate(
                name: "\(country) · 监管/政策候选源",
                domain: .policy,
                category: "监管政策会影响金融、支付、授信、费率、风控和合规口径。",
                query: "\(countryQuery) financial regulation credit loan payment policy consumer protection official \(businessTerms.joined(separator: " "))",
                officialHint: officialDomains(for: country, profile: "official_regulatory"),
                metrics: "审批通过率、授信、放款、支付成功率、投诉、风险指标",
                queryGroup: "regulation_trust",
                sourceProfile: "official_regulatory",
                topic: "general"
            ),
            candidate(
                name: "\(country) · 宏观消费/信贷数据候选源",
                domain: .market,
                category: "官方统计、央行和宏观消费数据可解释行业性波动。",
                query: "\(countryQuery) central bank statistics consumer credit inflation employment retail sales official",
                officialHint: officialDomains(for: country, profile: "macro_statistics"),
                metrics: "申请、授信、交易、消费、还款、逾期、活跃",
                queryGroup: "growth_market",
                sourceProfile: "official_regulatory",
                topic: "general"
            ),
            candidate(
                name: "\(country) · 金融/科技新闻候选源",
                domain: .market,
                category: "当地财经、金融科技和区域新闻用于发现市场、融资、活动和竞品动态。",
                query: "\(countryQuery) fintech credit card loan wallet payments market news \(businessTerms.joined(separator: " "))",
                officialHint: newsDomains(for: country),
                metrics: "获客、注册、申请、交易、留存、品牌声量",
                queryGroup: "growth_market",
                sourceProfile: "news_finance"
            ),
            candidate(
                name: "\(country) · 天气/灾害候选源",
                domain: .externalEvent,
                category: "天气、灾害和极端事件可能影响本地生活、用电、出行、支付和消费。",
                query: "\(countryQuery) weather disaster electricity outage official alert",
                officialHint: officialDomains(for: country, profile: "weather_disaster"),
                metrics: "缴费人数、交易金额、支付成功率、活跃、客服咨询",
                queryGroup: "external_events",
                sourceProfile: "official_first"
            ),
            candidate(
                name: "\(country) · 能源/用电/停电候选源",
                domain: .externalEvent,
                category: "能源、用电需求和停电会影响缴费、支付成功率、客服咨询和本地生活服务。",
                query: "\(countryQuery) electricity outage power demand energy grid official",
                officialHint: officialDomains(for: country, profile: "energy"),
                metrics: "电费缴费、支付成功率、客服咨询、交易、活跃",
                queryGroup: "external_events",
                sourceProfile: "official_first"
            ),
            candidate(
                name: "\(country) · 节假日/大型活动候选源",
                domain: .externalEvent,
                category: "节假日和大型活动可能影响申请、消费、还款和本地生活服务。",
                query: "\(countryQuery) holidays public events official calendar",
                officialHint: officialDomains(for: country, profile: "holidays"),
                metrics: "注册、申请、消费、缴费、还款、留存",
                queryGroup: "external_events",
                sourceProfile: "official_first"
            ),
            candidate(
                name: "\(country) · 交通/基础设施候选源",
                domain: .externalEvent,
                category: "交通、道路、机场和基础设施中断可能影响线下消费、支付和本地生活。",
                query: "\(countryQuery) transport infrastructure road closure airport official",
                officialHint: officialDomains(for: country, profile: "transport"),
                metrics: "交易、消费、出行相关服务、支付成功率、活跃",
                queryGroup: "external_events",
                sourceProfile: "official_first"
            ),
            candidate(
                name: "\(country) · 治安/罢工/抗议候选源",
                domain: .externalEvent,
                category: "治安、罢工、抗议和封锁会影响获客、交易、客服、门店或本地生活服务。",
                query: "\(countryQuery) public safety protest strike blockade official news",
                officialHint: officialDomains(for: country, profile: "public_safety"),
                metrics: "获客、交易、支付、活跃、投诉、客服咨询",
                queryGroup: "external_events",
                sourceProfile: "official_first"
            ),
            candidate(
                name: "\(country) · 竞品候选池",
                domain: .competitor,
                category: "先发现当前市场中需要跟踪的竞品，再由用户确认启用。",
                query: "\(countryQuery) fintech credit card loan wallet app competitors pricing promotion app reviews \(businessTerms.joined(separator: " "))",
                officialHint: newsDomains(for: country),
                metrics: "获客、注册、申请、交易、留存、品牌声量",
                queryGroup: "must_track",
                sourceProfile: "news",
                lifecycleStatus: .needsConfirmation
            )
        ]

        let competitorSeeds = seedCompetitors(for: space, countryAliases: countryAliases)
        for seed in competitorSeeds.prefix(5) {
            let aliases = seed.aliases.joined(separator: "\n")
            let competitorOfficialDomains = seed.officialDomains.joined(separator: "\n")
            candidates.append(candidate(
                name: "\(seed.name) · must_track · news",
                domain: .competitor,
                category: "RivalRadar 风格：跟踪竞品核心动态和市场新闻。",
                query: "\"{competitor}\" {aliases} \(countryQuery) fintech app credit card loan promotion news",
                officialHint: newsDomains(for: country),
                metrics: "获客、注册、申请、交易、留存、品牌声量",
                queryGroup: "must_track",
                sourceProfile: "news",
                competitorName: seed.name,
                competitorAliases: aliases
            ))
            candidates.append(candidate(
                name: "\(seed.name) · card_product_pricing · official_regulatory",
                domain: .competitor,
                category: "RivalRadar 风格：跟踪产品、价格、费率、权益、监管和投诉。",
                query: "\"{competitor}\" {aliases} \(countryQuery) card product pricing fees rewards regulation complaints",
                officialHint: ([competitorOfficialDomains] + [officialDomains(for: country, profile: "official_regulatory")]).filter { !$0.isEmpty }.joined(separator: "\n"),
                metrics: "申请、转化、授信、交易、投诉、风险",
                queryGroup: "card_product_pricing",
                sourceProfile: "official_regulatory",
                topic: "general",
                competitorName: seed.name,
                competitorAliases: aliases
            ))
            candidates.append(candidate(
                name: "\(seed.name) · app_reviews_complaints · social_reviews",
                domain: .competitor,
                category: "RivalRadar 风格：跟踪 App 评价、社媒讨论和用户投诉。",
                query: "\"{competitor}\" {aliases} app reviews complaints reddit youtube facebook app store google play \(countryQuery)",
                officialHint: socialReviewDomains(),
                metrics: "页面体验、注册、申请、KYC、客服、投诉、留存",
                queryGroup: "app_reviews_complaints",
                sourceProfile: "social_reviews",
                topic: "general",
                competitorName: seed.name,
                competitorAliases: aliases
            ))
        }

        return candidates
    }

    static func referenceSourceRecommendationPrompt(space: BusinessSpace) -> String {
        """
        你是产品数据情报源推荐助手。请根据业务空间推荐可采集的数据源候选，只生成候选，不要启用。
        \(FinancialPromptPolicy.sourceRecommendationRules)

        # 业务空间
        名称：\(space.name)
        国家/地区：\(space.countryRegion)
        业务背景：
        \(space.businessBackground)
        业务域：\(space.domains.map(\.name).joined(separator: "、"))

        # 要求
        - 按 RivalRadar 风格推荐采集范围：竞品核心动态、产品/价格/费率/权益、营销活动/返现/补贴、风控/授信/审批/投诉、增长/市场/获客、监管/信任、App 评价/社媒反馈。
        - 来源画像必须覆盖：official_regulatory、news_finance、social_reviews、official_first。
        - 同时覆盖政策/监管、官方统计、天气/灾害、能源/用电、节假日/大型活动、交通/基础设施、治安/罢工、宏观消费。
        - 如果业务背景里没有明确竞品，请生成“竞品候选池”或“候选竞品”来源，lifecycle_status 使用 needsConfirmation。
        - 不要编造需要登录或明显不可采集的内网源。
        - Tavily 只作为检索入口；official_domains/include_domains 用于限制官方域名、媒体域名或评价站域名。

        # 输出 JSON
        只输出 JSON 数组，每个对象：
        {
          "name": "源名称",
          "domain": "competitor|policy|market|externalEvent",
          "query": "Tavily 查询语句",
          "keywords": "逗号分隔关键词",
          "official_domains": "逗号分隔域名，可为空",
          "competitor": "竞品名，可为空",
          "aliases": "竞品别名，逗号分隔，可为空",
          "query_group": "must_track|card_product_pricing|rewards_marketing|risk_credit|growth_market|regulation_trust|app_reviews_complaints|external_events",
          "source_profile": "official_regulatory|news_finance|social_reviews|official_first|news|official|social_voice",
          "topic": "news|general|finance",
          "lifecycle_status": "candidate|needsConfirmation",
          "reason": "推荐理由",
          "metrics": "可能影响的指标"
        }
        """
    }

    static func parseReferenceSourceRecommendations(_ text: String, for space: BusinessSpace) -> [ExternalReferenceSource] {
        let jsonText = extractJSONArray(from: text)
        guard let data = jsonText.data(using: .utf8),
              let payloads = try? JSONDecoder().decode([ReferenceSourceRecommendationPayload].self, from: data) else {
            return []
        }
        let countryAliases = searchCountryAliases(for: space.countryRegion)
        let countryQuery = countryAliases.joined(separator: " ")
        let languageHints = space.primaryLanguagesText.nilIfBlank ?? defaultLanguageHints(for: space.countryRegion)
        return payloads.prefix(40).map { payload in
            let domain = ExternalReferenceDomain(rawValue: payload.domain) ?? .externalEvent
            let lifecycle = ReferenceSourceLifecycleStatus(rawValue: payload.lifecycleStatus ?? "") ?? .candidate
            let sourceProfile = (payload.sourceProfile ?? "").nilIfBlank ?? "official_first"
            let queryGroup = (payload.queryGroup ?? "").nilIfBlank ?? "business_space_ai_\(space.id.uuidString.prefix(8))"
            return ExternalReferenceSource(
                id: UUID(),
                businessSpaceIDs: [space.id],
                businessDomainIDs: space.domains.map(\.id),
                lifecycleStatus: lifecycle,
                recommendationReason: payload.reason,
                possibleImpactedMetricsText: payload.metrics,
                officialDomainHint: payload.officialDomains ?? "",
                createdByAI: true,
                name: payload.name,
                domain: domain,
                collectorType: .tavilySearch,
                url: "",
                keywordsText: payload.keywords,
                queryTemplate: payload.query,
                apiKey: "",
                competitorName: (payload.competitor ?? "").nilIfBlank ?? space.countryRegion,
                competitorAliasesText: payload.aliases ?? "",
                tavilyTopic: (payload.topic ?? "").nilIfBlank ?? "news",
                tavilySearchDepth: "advanced",
                tavilyTimeRange: "month",
                tavilyMaxResults: 8,
                tavilyIncludeRawContent: true,
                tavilyIncludeDomainsText: payload.officialDomains ?? "",
                tavilyCountry: countryQuery.lowercased(),
                tavilyLanguageHintsText: languageHints,
                tavilyQueryGroup: queryGroup,
                tavilySourceProfile: sourceProfile,
                enabled: false,
                manualNote: "AI 候选源：请先测试此源或编辑后启用。",
                lastFetchedAt: nil
            )
        }
    }

    private static func inferredLinks(domains: [BusinessDomain]) -> [BusinessDomainLink] {
        var links: [BusinessDomainLink] = []
        func find(_ name: String) -> BusinessDomain? {
            domains.first { $0.name.normalizedKey.contains(name.normalizedKey) }
        }
        func link(_ source: BusinessDomain?, _ target: BusinessDomain?, mechanism: String, lag: Int? = nil) {
            guard let source, let target, source.id != target.id else { return }
            links.append(BusinessDomainLink(
                sourceDomainID: source.id,
                targetDomainID: target.id,
                sourceName: source.name,
                targetName: target.name,
                influenceMechanism: mechanism,
                lagDays: lag,
                evidenceRule: "需要时间窗口可比、指标方向一致，并说明候选滞后口径和外部事件干扰。"
            ))
        }
        link(find("信用卡"), find("本地生活缴费"), mechanism: "信用卡新客和激活用户可能带来本地生活缴费交叉使用。", lag: 7)
        link(find("小贷"), find("本地生活缴费"), mechanism: "小贷用户现金流和还款压力可能影响本地生活缴费行为。", lag: 7)
        link(find("钱包"), find("本地生活缴费"), mechanism: "钱包/支付稳定性和绑卡成功率会影响缴费支付成功。", lag: 0)
        link(find("风控"), find("信用卡"), mechanism: "风控策略会影响审批、授信、发卡和风险指标。", lag: 1)
        link(find("风控"), find("小贷"), mechanism: "风控策略会影响授信、审核、放款和逾期。", lag: 1)
        return links
    }

    private struct ReferenceSourceRecommendationPayload: Codable {
        var name: String
        var domain: String
        var query: String
        var keywords: String
        var officialDomains: String?
        var competitor: String?
        var aliases: String?
        var queryGroup: String?
        var sourceProfile: String?
        var topic: String?
        var lifecycleStatus: String?
        var reason: String
        var metrics: String

        enum CodingKeys: String, CodingKey {
            case name
            case domain
            case query
            case keywords
            case officialDomains = "official_domains"
            case competitor
            case aliases
            case queryGroup = "query_group"
            case sourceProfile = "source_profile"
            case topic
            case lifecycleStatus = "lifecycle_status"
            case reason
            case metrics
        }
    }

    private struct CompetitorSeed {
        var name: String
        var aliases: [String]
        var officialDomains: [String]
    }

    private static func searchCountryAliases(for country: String) -> [String] {
        let normalized = country.normalizedKey
        if normalized.contains("mexico") || country.contains("墨西哥") || country.contains("México") {
            return ["Mexico", "México", "MX", "墨西哥"]
        }
        if normalized.contains("philippines") || country.contains("菲律宾") {
            return ["Philippines", "PH", "菲律宾"]
        }
        if normalized.contains("colombia") || country.contains("哥伦比亚") {
            return ["Colombia", "CO", "哥伦比亚"]
        }
        return [country].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func defaultLanguageHints(for country: String) -> String {
        let normalized = country.normalizedKey
        if normalized.contains("mexico") || country.contains("墨西哥") || country.contains("México") {
            return "es,es-MX,en"
        }
        if normalized.contains("philippines") || country.contains("菲律宾") {
            return "en,fil,tl"
        }
        if normalized.contains("colombia") || country.contains("哥伦比亚") {
            return "es,es-CO,en"
        }
        return "en"
    }

    private static func officialDomains(for country: String, profile: String) -> String {
        let normalized = country.normalizedKey
        if normalized.contains("mexico") || country.contains("墨西哥") || country.contains("México") {
            switch profile {
            case "official_regulatory":
                return "gob.mx\ncondusef.gob.mx\ncnbv.gob.mx\nbanxico.org.mx\ndof.gob.mx"
            case "macro_statistics":
                return "inegi.org.mx\nbanxico.org.mx\ngob.mx"
            case "weather_disaster":
                return "smn.conagua.gob.mx\nconagua.gob.mx\nproteccioncivil.gob.mx\ncenapred.unam.mx\nssn.unam.mx\ngob.mx"
            case "energy":
                return "cfe.mx\ncenace.gob.mx\ngob.mx"
            case "holidays":
                return "gob.mx\nsep.gob.mx"
            case "transport":
                return "sict.gob.mx\nsct.gob.mx\ngob.mx"
            case "public_safety":
                return "gob.mx\ninegi.org.mx"
            default:
                return "gob.mx"
            }
        }
        return ""
    }

    private static func newsDomains(for country: String) -> String {
        let normalized = country.normalizedKey
        if normalized.contains("mexico") || country.contains("墨西哥") || country.contains("México") {
            return "reuters.com\nbloomberg.com\nbusinesswire.com\nelfinanciero.com.mx\neleconomista.com.mx\nexpansion.mx\nforbes.com.mx\nelpais.com\nlatamfintech.co\ncontxto.com\nfintechfutures.com\nbnamericas.com"
        }
        return "reuters.com\nbloomberg.com\nbusinesswire.com\ntechcrunch.com\nfintechfutures.com\nbnamericas.com"
    }

    private static func socialReviewDomains() -> String {
        "reddit.com\nyoutube.com\nx.com\nfacebook.com\nplay.google.com\napps.apple.com\ntrustpilot.com\napestan.com"
    }

    private static func seedCompetitors(for space: BusinessSpace, countryAliases: [String]) -> [CompetitorSeed] {
        let text = ([space.name, space.businessBackground] + space.domains.map(\.name))
            .joined(separator: " ")
            .normalizedKey
        let isMexico = countryAliases.contains { $0.localizedCaseInsensitiveContains("Mexico") || $0.contains("墨西哥") }
        guard isMexico else { return [] }

        if text.contains("小贷") || text.contains("loan") || text.contains("prestamo") || text.contains("préstamo") {
            return [
                CompetitorSeed(name: "Kueski", aliases: ["Kueski Pay"], officialDomains: ["kueski.com"]),
                CompetitorSeed(name: "Tala México", aliases: ["Tala"], officialDomains: ["tala.co"]),
                CompetitorSeed(name: "Baubap", aliases: [], officialDomains: ["baubap.com"]),
                CompetitorSeed(name: "YoTePresto", aliases: ["yotepresto"], officialDomains: ["yotepresto.com"]),
                CompetitorSeed(name: "Mercado Crédito", aliases: ["Mercado Pago", "Mercado Libre"], officialDomains: ["mercadopago.com.mx", "mercadolibre.com.mx"])
            ]
        }

        return [
            CompetitorSeed(name: "Nu México", aliases: ["Nu", "Nubank México"], officialDomains: ["nu.com.mx"]),
            CompetitorSeed(name: "Stori", aliases: ["Stori Card"], officialDomains: ["storicard.com"]),
            CompetitorSeed(name: "Klar", aliases: ["Klar México"], officialDomains: ["klar.mx"]),
            CompetitorSeed(name: "RappiCard México", aliases: ["RappiCard", "Rappi"], officialDomains: ["rappicard.mx", "rappi.com.mx"]),
            CompetitorSeed(name: "Mercado Pago", aliases: ["Mercado Crédito", "Mercado Libre"], officialDomains: ["mercadopago.com.mx", "mercadolibre.com.mx"])
        ]
    }

    private static func extractJSONArray(from text: String) -> String {
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]"),
              start <= end else {
            return text
        }
        return String(text[start...end])
    }

    private static func extractJSONObject(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else {
            return text
        }
        return String(text[start...end])
    }

    private static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0.normalizedKey) || text.contains($0.lowercased()) }
    }

    private struct BusinessSpaceProfilePayload: Decodable {
        var name: String?
        var countryRegion: String?
        var timezone: String?
        var currency: String?
        var languages: String?
        var summary: String?
        var domains: [DomainPayload]?
        var links: [LinkPayload]?
        var metricRules: String?
        var anomalyRules: String?
        var guardrails: String?

        enum CodingKeys: String, CodingKey {
            case name
            case countryRegion = "country_region"
            case timezone
            case currency
            case languages
            case summary
            case domains
            case links
            case metricRules = "metric_rules"
            case anomalyRules = "anomaly_rules"
            case guardrails
        }
    }

    private struct DomainPayload: Decodable {
        var name: String?
        var description: String?
        var coreFlow: String?
        var role: String?

        enum CodingKeys: String, CodingKey {
            case name
            case description
            case coreFlow = "core_flow"
            case role
        }
    }

    private struct LinkPayload: Decodable {
        var source: String?
        var target: String?
        var mechanism: String?
        var lagDays: Int?
        var evidenceRule: String?

        enum CodingKeys: String, CodingKey {
            case source
            case target
            case mechanism
            case lagDays = "lag_days"
            case evidenceRule = "evidence_rule"
        }
    }
}
