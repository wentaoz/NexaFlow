import Foundation

enum BuiltInBusinessSpaceCatalog {
    static let catalogVersion = 1

    static var spaces: [BusinessSpace] {
        [
            creditCard(
                key: "mx_credit_card",
                name: "墨西哥信用卡",
                country: "墨西哥",
                timeZone: "America/Mexico_City",
                currency: "MXN",
                languages: "zh-CN, es-MX, en",
                regulator: "CNBV、Banxico、CONDUSEF",
                marketNotes: "墨西哥信用卡增长通常同时受现金经济、工资发放节奏、节假日、CFE/用电账单、本地消费活跃度、现金贷和数字信用卡竞品活动影响。产品分析要特别关注渠道质量、注册到申请的页面体验、短信/KYC 稳定性、审批/授信策略、实体卡配送、激活首刷权益、交易场景结构、还款与投诉。地区上需留意 CDMX、Estado de México、Jalisco、Nuevo León 等核心州的网络、物流和消费差异。",
                externalNotes: "优先纳入 CNBV、Banxico、CONDUSEF、CFE/CENACE、SMN/CONAGUA、CENAPRED、Google Play/App Store 评价、本地金融新闻、竞品官网/帮助中心/促销页、社媒投诉和消费者保护信息。CFE/用电和天气只能在事件发生时间与分析周期匹配时作为强证据；只有采集时间的新闻只能作为弱线索。"
            ),
            microLoan(
                key: "mx_microloan",
                name: "墨西哥小贷",
                country: "墨西哥",
                timeZone: "America/Mexico_City",
                currency: "MXN",
                languages: "zh-CN, es-MX, en",
                regulator: "CNBV、Banxico、CONDUSEF",
                marketNotes: "墨西哥小贷要重点看现金贷竞品、工资日和账单日、CFE/用电支出、节假日、渠道投放质量、KYC/设备识别、风控拒绝、资金供给、放款成功率、复借、逾期、投诉和催收合规。分析时不能只看注册或申请增长，还要检查后续授信、审核、放款、还款和复借是否承接；若流量增长但放款或复借没有同步，需要优先排查渠道质量、风控策略、资金约束和还款压力。",
                externalNotes: "优先纳入 CNBV/Banxico/CONDUSEF、CFE/CENACE、SMN/CONAGUA、CENAPRED、竞品 App 评价、现金贷广告/促销、当地财经新闻、消费者投诉、宏观通胀和就业信息。外部事件必须区分发生时间、发布时间和采集时间，避免把当前新闻误用于历史周期。"
            ),
            microLoan(
                key: "in_microloan",
                name: "印度小贷",
                country: "印度",
                timeZone: "Asia/Kolkata",
                currency: "INR",
                languages: "zh-CN, en-IN, hi",
                regulator: "RBI、NPCI、UIDAI、消费者保护相关公开信息",
                marketNotes: "印度小贷高度依赖 UPI 支付可用性、Aadhaar/eKYC 稳定性、NBFC 合作、地区语言、邦级节庆和监管口径。产品/运营分析要同时看渠道质量、注册/KYC 转化、授信评估、申请提交、审核通过、放款成功、还款、复借、逾期和催收投诉。需要特别警惕因 UPI 波动、KYC 服务异常、地区流量结构变化、节庆前后资金需求、监管/催收舆情导致的指标波动。",
                externalNotes: "优先纳入 RBI、NPCI、UIDAI、UPI 服务状态、NBFC/fintech 新闻、印度节庆日历、IMD 天气灾害、Google Play/App Store 评价、消费者投诉、竞品官网/活动、地区语言社媒反馈。监管、催收、隐私和消费者保护信息必须作为单独风险维度。"
            ),
            microLoan(
                key: "ph_microloan",
                name: "菲律宾小贷",
                country: "菲律宾",
                timeZone: "Asia/Manila",
                currency: "PHP",
                languages: "zh-CN, en-PH, fil",
                regulator: "BSP、SEC Philippines、NPC/消费者保护公开信息",
                marketNotes: "菲律宾小贷要把 e-wallet 生态、GCash/Maya 还款渠道、台风/暴雨、地区网络质量、现金贷竞品、客服投诉和监管舆情纳入分析。重点链路是渠道获客、注册、KYC、授信/审核、放款、还款、复借和逾期。若还款或放款异常，要同时排查钱包渠道、银行/支付通道、台风影响地区、客服工单和投诉舆情；若新增增长但授信或放款不动，要检查渠道质量和风控拒绝。",
                externalNotes: "优先纳入 BSP、SEC Philippines、PAGASA、GCash/Maya 生态动态、节假日、台风/洪水新闻、竞品 App 评价、消费者投诉、当地财经媒体和社媒反馈。自然灾害证据必须匹配地区和发生时间，不能仅凭发布时间做高置信归因。"
            ),
            microLoan(
                key: "id_microloan",
                name: "印尼小贷",
                country: "印尼",
                timeZone: "Asia/Jakarta",
                currency: "IDR",
                languages: "zh-CN, id, en",
                regulator: "OJK、Bank Indonesia、Kominfo、消费者保护公开信息",
                marketNotes: "印尼小贷需要重点考虑 OJK 合规、Bank Indonesia 支付环境、Ramadan/Eid 前后的借款与还款节奏、支付/电商生态、岛屿和城市层级差异、设备欺诈、催收合规和用户投诉。分析链路要覆盖获客、注册、KYC、授信/审核、申请、放款、还款、复借、逾期和投诉；对 Java、Sumatra、Sulawesi 等地区结构变化要谨慎拆分。",
                externalNotes: "优先纳入 OJK、Bank Indonesia、Kominfo、Ramadan/Eid 日历、BMKG 天气灾害、支付/电商平台动态、竞品 App 评价、当地财经新闻、消费者投诉和社媒反馈。节庆和天气对还款/借款影响要按发生时间和地区匹配。"
            ),
            creditCard(
                key: "id_credit_card",
                name: "印尼信用卡",
                country: "印尼",
                timeZone: "Asia/Jakarta",
                currency: "IDR",
                languages: "zh-CN, id, en",
                regulator: "OJK、Bank Indonesia、消费者保护公开信息",
                marketNotes: "印尼信用卡要同时看申请/KYC、审批授信、卡片激活、首刷、持续交易、分期、还款和投诉。Ramadan/Eid、支付/电商生态、分期/返现权益、地区差异、KYC 稳定性、审批风控、额度策略和 App 评价都会影响指标。若流量增长但首刷或交易未承接，需要拆分审批通过率、额度、卡片交付、权益触达、支付场景和用户分层。",
                externalNotes: "优先纳入 OJK、Bank Indonesia、Ramadan/Eid 日历、竞品权益/费率/活动、支付渠道、电商促销、本地金融新闻、Google Play/App Store 评价和社媒投诉。市场活动和外部事件必须和分析周期匹配，不能用后发生的促销解释前期波动。"
            ),
            microLoan(
                key: "pk_microloan",
                name: "巴基斯坦小贷",
                country: "巴基斯坦",
                timeZone: "Asia/Karachi",
                currency: "PKR",
                languages: "zh-CN, en-PK, ur",
                regulator: "SBP、SECP、消费者保护公开信息",
                marketNotes: "巴基斯坦小贷要重点关注 Easypaisa/JazzCash 钱包生态、SBP/SECP 监管、通胀/汇率、宗教节日、网络可用性、停电/能源、欺诈、还款渠道、催收合规和用户投诉。分析时要拆开新增、KYC、授信/审核、放款、还款、复借、逾期和投诉；渠道增长不等于有效放款，需验证钱包通道、风控拒绝和还款压力。",
                externalNotes: "优先纳入 SBP、SECP、Easypaisa/JazzCash 生态、PKR 汇率/通胀、Ramadan/Eid 等宗教节日、能源/停电影响、当地财经新闻、竞品评价和消费者投诉。宏观压力和宗教节日只能在周期匹配时作为强证据。"
            ),
            microLoan(
                key: "kz_microloan",
                name: "哈萨克斯坦小贷",
                country: "哈萨克斯坦",
                timeZone: "Asia/Almaty",
                currency: "KZT",
                languages: "zh-CN, ru, kk, en",
                regulator: "National Bank of Kazakhstan、金融市场监管公开信息",
                marketNotes: "哈萨克斯坦小贷要关注 NBK/金融监管、KZT 汇率、通胀和信用成本、俄语/哈语用户沟通、本地支付方式、地区经济差异、渠道质量、反欺诈、放款成功率、还款和逾期。分析需要区分 Almaty/Astana 等城市与其他地区，不把宏观汇率或监管新闻直接写成因果，必须结合发生时间和业务指标窗口。",
                externalNotes: "优先纳入 National Bank of Kazakhstan、金融监管公开信息、KZT 汇率/通胀、节假日、天气/交通、当地财经媒体、竞品 App 评价和社媒反馈。监管和宏观信息更多作为风险与背景，只有周期重合且影响机制明确时才提升证据等级。"
            ),
            microLoan(
                key: "ng_microloan",
                name: "尼日利亚小贷",
                country: "尼日利亚",
                timeZone: "Africa/Lagos",
                currency: "NGN",
                languages: "zh-CN, en-NG",
                regulator: "CBN、FCCPC、NDPR/消费者保护公开信息",
                marketNotes: "尼日利亚小贷要重点关注 CBN/FCCPC 监管、Naira 汇率和通胀、USSD/移动钱生态、停电/燃油、欺诈、还款渠道、催收合规、投诉和地区网络差异。分析链路必须同时看获客、注册、KYC、授信、申请、放款、还款、复借、逾期和投诉；若转化下降或还款恶化，要验证支付/USSD 可用性、燃油/停电影响、欺诈策略和用户现金流压力。",
                externalNotes: "优先纳入 CBN、FCCPC、NDPR/隐私、Naira 汇率/通胀、燃油/停电新闻、USSD/移动钱生态、竞品评价、消费者投诉和当地财经媒体。停电/燃油事件需匹配发生地区和分析周期，否则只能作为弱线索。"
            )
        ]
    }

    static func space(for key: String) -> BusinessSpace? {
        spaces.first { $0.builtInKey == key }
    }

    private static func creditCard(
        key: String,
        name: String,
        country: String,
        timeZone: String,
        currency: String,
        languages: String,
        regulator: String,
        marketNotes: String,
        externalNotes: String
    ) -> BusinessSpace {
        let acquisition = BusinessDomain(name: "获客与渠道", description: "渠道投放、安装、注册入口和用户质量。当地重点：\(marketNotes)", coreFlowText: "曝光 → 点击 → 安装 → 注册 → 渠道质量复核", role: .supporting)
        let application = BusinessDomain(name: "申请/KYC", description: "信用卡申请、身份认证、资料提交和页面体验。需要结合当地 KYC、短信、设备、语言和监管要求判断转化断点。", coreFlowText: "注册 → 申请 → KYC → 资料提交 → 页面/短信/设备复核", role: .primary)
        let approval = BusinessDomain(name: "审批/授信", description: "审批策略、授信额度、拒绝原因和风险判断。监管参考：\(regulator)。", coreFlowText: "资料校验 → 风控评分 → 审批 → 授信 → 拒绝原因拆解", role: .primary)
        let card = BusinessDomain(name: "发卡/激活/首刷", description: "发卡、配送、激活、首笔消费和权益转化。需要同时检查实体/虚拟卡履约、权益触达、额度和支付场景。", coreFlowText: "授信 → 发卡 → 激活 → 首刷 → 权益/配送/场景复核", role: .primary)
        let usage = BusinessDomain(name: "持续消费/还款", description: "持续交易、复购、账单、还款、逾期、额度和收入。需要拆分新老客、场景、客单价、额度和风险表现。", coreFlowText: "首刷 → 持续消费 → 账单 → 还款 → 逾期/投诉/收入监控", role: .primary)
        let support = BusinessDomain(name: "运营/客服/合规", description: "活动、客服、投诉、合规与外部事件旁证。外部优先参考：\(externalNotes)", coreFlowText: "活动触达 → 客服反馈 → 投诉处理 → 合规复核 → 外部证据匹配", role: .evidence)
        let domains = [acquisition, application, approval, card, usage, support]
        return BusinessSpace(
            builtInKey: key,
            name: name,
            countryRegion: country,
            timeZoneIdentifier: timeZone,
            currencyCode: currency,
            primaryLanguagesText: languages,
            businessBackground: """
            我们在\(country)运营信用卡业务，主要用户是通过线上渠道进入 App 后完成注册、申请、KYC、审批、授信、发卡、激活、首刷和持续消费的用户。业务分析需要同时关注增长、用户质量、风控策略、授信额度、卡片履约、交易活跃、还款风险、投诉和合规风险。

            核心业务链路：获客/安装 → 注册 → 申请 → KYC → 审批 → 授信 → 发卡 → 激活 → 首刷 → 持续消费 → 还款/风险。重点指标包括安装、注册、申请提交、KYC 完成率、审批通过率、授信完成、平均额度、发卡/激活、首刷、交易人数、交易金额、还款率、逾期、投诉、渠道成本和活动 ROI。

            \(country)市场需要特别考虑：\(marketNotes)
            监管和外部证据优先参考：\(regulator)。外部事件和竞品情报优先参考：\(externalNotes)

            AI 分析禁区：不能提供投资建议、收益承诺、绕过风控、规避监管或降低必要 KYC/合规要求的建议。所有结论必须区分事实、推断、假设和需补数据。
            """,
            domains: domains,
            domainLinks: [
                link(acquisition, application, "渠道流量质量影响注册、申请和 KYC 完成率。", 0),
                link(application, approval, "申请资料质量和 KYC 稳定性影响审批通过与授信。", 0),
                link(approval, card, "审批和授信结果影响发卡、激活和首刷规模。", 1),
                link(card, usage, "激活和首刷质量影响后续消费、还款和收入。", 7),
                link(support, usage, "活动、客服、投诉、竞品和外部事件作为交易和还款波动旁证。", nil)
            ],
            metricClassificationRulesText: "信用卡指标按获客、注册/申请、KYC、审批/授信、发卡/激活/首刷、交易/收入、还款/风险、客服/投诉、渠道成本分类。比例指标看百分点，金额和人数分开判断。\(country)场景下还要结合当地支付、物流、节假日、监管和竞品权益判断指标承接。",
            anomalyRulesText: "必须检查增长未传导、审批/授信断点、渠道质量变差、KYC/短信/页面稳定性、发卡或激活履约异常、交易与还款背离、投诉或合规风险上升。当地高频异常包括：\(marketNotes)",
            analysisGuardrailsText: "不要把相关性写成确定因果；不要建议绕过风控或合规；监管、投诉、逾期和用户保护风险必须单独列出；外部证据必须区分事件发生时间、发布时间和采集时间。\(regulator)相关信息只能作为合规与风险参考，不能生成规避监管建议。",
            recommendedSourceCategories: [.policy, .market, .customer, .risk, .weather, .energy, .holiday, .localEconomy],
            generatedSummary: "内置信用卡业务空间：覆盖获客、申请/KYC、审批/授信、发卡/激活/首刷、持续消费、还款/风险和运营合规。"
        )
    }

    private static func microLoan(
        key: String,
        name: String,
        country: String,
        timeZone: String,
        currency: String,
        languages: String,
        regulator: String,
        marketNotes: String,
        externalNotes: String
    ) -> BusinessSpace {
        let acquisition = BusinessDomain(name: "获客与注册", description: "渠道投放、安装、注册和新客质量。当地重点：\(marketNotes)", coreFlowText: "曝光 → 点击 → 安装 → 注册 → 渠道质量复核", role: .supporting)
        let identity = BusinessDomain(name: "身份认证/KYC", description: "身份认证、资料采集、设备和反欺诈。需要结合当地证件/KYC、短信、设备、语言、网络和欺诈风险判断。", coreFlowText: "注册 → 身份认证 → 资料采集 → 设备/反欺诈 → KYC 稳定性复核", role: .primary)
        let credit = BusinessDomain(name: "授信/审核", description: "信用评估、风控策略、拒绝原因和额度。监管参考：\(regulator)。", coreFlowText: "资料校验 → 风控评分 → 授信 → 审核 → 拒绝原因拆解", role: .primary)
        let disbursement = BusinessDomain(name: "申请/放款", description: "借款申请、合同确认、放款成功和资金约束。需要拆分资方、支付通道、合同确认和放款失败原因。", coreFlowText: "授信 → 借款申请 → 合同确认 → 审核 → 放款 → 通道/资金复核", role: .primary)
        let repayment = BusinessDomain(name: "还款/复借/风险", description: "还款、复借、逾期、催收、投诉和坏账。需要结合账单日、支付渠道、宏观压力、节假日和用户现金流。", coreFlowText: "放款 → 到期提醒 → 还款 → 复借 → 逾期/催收 → 投诉/坏账监控", role: .primary)
        let support = BusinessDomain(name: "运营/客服/外部事件", description: "活动、客服、投诉、政策、宏观和社会自然事件。外部优先参考：\(externalNotes)", coreFlowText: "活动 → 客服反馈 → 投诉/政策 → 外部事件复核 → 经营动作验证", role: .evidence)
        let domains = [acquisition, identity, credit, disbursement, repayment, support]
        return BusinessSpace(
            builtInKey: key,
            name: name,
            countryRegion: country,
            timeZoneIdentifier: timeZone,
            currencyCode: currency,
            primaryLanguagesText: languages,
            businessBackground: """
            我们在\(country)运营小贷业务，核心目标是通过 App 完成获客、注册、身份认证、授信评估、借款申请、审核、放款、还款、复借和风险管理。分析需要同时关注增长规模、用户质量、风控通过、资金供给、放款效率、还款表现、逾期、投诉和合规风险。

            核心业务链路：获客 → 注册 → 身份认证/KYC → 授信评估 → 借款申请 → 审核 → 放款 → 还款 → 复借 → 逾期/催收。重点指标包括安装、注册、KYC 完成、授信通过率、申请率、审核通过率、放款人数、放款金额、首借、复借、还款率、逾期率、拒绝原因、风控命中、客服投诉、渠道成本和 ROI。

            \(country)市场需要特别考虑：\(marketNotes)
            监管和外部证据优先参考：\(regulator)。外部事件和竞品情报优先参考：\(externalNotes)

            AI 分析禁区：不能建议绕过风控、规避监管、弱化必要 KYC、诱导过度借贷或不合规催收。所有建议必须兼顾增长、风险、用户保护和合规。
            """,
            domains: domains,
            domainLinks: [
                link(acquisition, identity, "渠道质量影响注册后的 KYC 完成和欺诈风险。", 0),
                link(identity, credit, "身份认证质量、设备和资料完整性影响授信与审核。", 0),
                link(credit, disbursement, "授信策略、拒绝原因和额度影响借款申请与放款。", 0),
                link(disbursement, repayment, "放款用户质量和资金约束影响还款、复借和逾期。", 7),
                link(support, repayment, "政策、宏观、节假日、天气、客服投诉和竞品动作作为风险与还款波动旁证。", nil)
            ],
            metricClassificationRulesText: "小贷指标按获客、注册/KYC、授信/审核、申请/放款、还款/复借、逾期/坏账、客服/投诉、渠道成本分类。增长指标和风险指标必须分开判断。\(country)场景下还要结合当地支付/钱包、监管、节假日、宏观压力、地区和渠道结构判断指标承接。",
            anomalyRulesText: "必须检查渠道质量恶化、KYC 或短信异常、风控策略收紧、资方/放款约束、放款与还款背离、逾期和投诉上升、复借下降、节假日或宏观压力影响。当地高频异常包括：\(marketNotes)",
            analysisGuardrailsText: "不要建议绕过风控、规避监管或不合规催收；审批、放款和逾期变化必须同时评估风险收益；外部证据必须按本轮分析周期匹配。\(regulator)相关信息只能作为合规与风险参考，不能生成规避监管或弱化用户保护的建议。",
            recommendedSourceCategories: [.policy, .market, .risk, .customer, .holiday, .weather, .localEconomy],
            generatedSummary: "内置小贷业务空间：覆盖获客、注册/KYC、授信/审核、申请/放款、还款/复借、逾期/催收和外部事件旁证。"
        )
    }

    private static func link(_ source: BusinessDomain, _ target: BusinessDomain, _ mechanism: String, _ lagDays: Int?) -> BusinessDomainLink {
        BusinessDomainLink(
            sourceDomainID: source.id,
            targetDomainID: target.id,
            sourceName: source.name,
            targetName: target.name,
            influenceMechanism: mechanism,
            lagDays: lagDays,
            evidenceRule: "只有时间周期、人群/渠道和指标口径可比时，才提升为强证据；否则作为假设或旁证。"
        )
    }
}
