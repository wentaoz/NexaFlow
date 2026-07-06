import Foundation

enum ReportRequirementDigestBuilder {
    static func build(session: AnalysisSession) -> ReportRequirementDigest {
        let userMessages = session.messages
            .filter { $0.role == .user && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        let reportScopedMessages = userMessages.filter { shouldIncludeInReport($0) }
        let requests = reportScopedMessages.map { message in
            "\(DateFormatting.shortDateTime.string(from: message.createdAt))：\(compact(message.content, limit: 700))"
        }
        let corrections = reportScopedMessages
            .filter { containsAny($0.content, keywords: correctionKeywords) }
            .map { message in
                "\(DateFormatting.shortDateTime.string(from: message.createdAt))：\(compact(message.content, limit: 700))"
            }
        let focus = reportScopedMessages
            .filter { containsAny($0.content, keywords: focusKeywords) }
            .map { message in
                "\(DateFormatting.shortDateTime.string(from: message.createdAt))：\(compact(message.content, limit: 700))"
            }
        let challenged = reportScopedMessages
            .filter { containsAny($0.content, keywords: challengeKeywords) }
            .map { message in
                "\(DateFormatting.shortDateTime.string(from: message.createdAt))：\(compact(message.content, limit: 700))"
            }
        let superseded = session.messages
            .filter { $0.correctionStatus.excludesFromFinalConclusion }
            .map { message in
                "\(DateFormatting.shortDateTime.string(from: message.createdAt))：\(compact(message.content, limit: 700))"
            }
        let adoptedRules = session.messages
            .filter { $0.correctionStatus == .savedAsCorrectionRule || $0.adoptedAs.contains("纠偏记忆") }
            .map { message in
                "\(DateFormatting.shortDateTime.string(from: message.createdAt))：\(compact(message.content, limit: 700))"
            }

        let goal = session.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackRequests = requests.isEmpty && !goal.isEmpty ? ["任务目标：\(compact(goal, limit: 700))"] : requests
        return ReportRequirementDigest(
            sessionGoal: goal,
            userRequests: fallbackRequests,
            corrections: corrections,
            requiredFocus: focus,
            challengedConclusions: challenged,
            supersededConclusions: superseded,
            adoptedCorrectionRules: adoptedRules
        )
    }

    static func questionCount(for session: AnalysisSession) -> Int {
        if let digest = session.reportRequirementDigest {
            return digest.coveredQuestionCount
        }

        var includedUserQuestionCount = 0
        for message in session.messages where message.role == .user {
            if shouldIncludeInReport(message) {
                includedUserQuestionCount += 1
            }
        }
        if includedUserQuestionCount == 0,
           !session.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return 1
        }
        return includedUserQuestionCount
    }

    private static let correctionKeywords = ["修正", "纠正", "口径", "以后", "应该", "按这个", "不是", "不能", "不要", "不对", "错误"]
    private static let focusKeywords = ["周期", "时间", "日期", "指标", "业务域", "外部", "竞品", "政策", "天气", "用电", "CFE", "Confluence", "Jira", "项目", "上线", "版本", "知识库", "报告", "Word", "百分比", "百分点"]
    private static let challengeKeywords = ["质疑", "不对", "错误", "误判", "遗漏", "没看到", "不要", "不能", "不应该", "不是", "为什么"]
    private static let businessQuestionKeywords = [
        "分析", "判断", "变化", "趋势", "原因", "异常", "归因", "指标", "周期", "同比", "环比", "转化", "漏斗", "注册", "申请", "KYC",
        "授信", "审批", "发卡", "激活", "交易", "消费", "留存", "复购", "还款", "逾期", "风控", "渠道", "获客", "活动", "投放",
        "收入", "成本", "ARPU", "LTV", "AUM", "入金", "申赎", "券商", "基金", "信用卡", "小贷", "竞品", "政策", "外部事件"
    ]
    private static let toolQuestionKeywords = [
        "按钮", "入口", "页面", "显示", "卡顿", "闪白", "hover", "havor", "样式", "图标", "颜色", "模式", "快速问答", "深度分析",
        "打包", "DMG", "启动", "GUI", "回归", "复制", "粘贴", "输入框", "导出完整汇报", "是什么意思", "在哪", "怎么用"
    ]

    private static func containsAny(_ text: String, keywords: [String]) -> Bool {
        keywords.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private static func shouldIncludeInReport(_ message: AnalysisSessionMessage) -> Bool {
        switch message.reportInclusion {
        case .included:
            return true
        case .excluded:
            return false
        case .automatic:
            let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return false }
            if containsAny(text, keywords: businessQuestionKeywords) {
                return true
            }
            if containsAny(text, keywords: toolQuestionKeywords) {
                return false
            }
            return text.count >= 18
        }
    }

    private static func compact(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)) + "..."
    }
}

enum AnalysisSessionAIService {
    private static let placeholderOutputRule = """
    - 禁止输出模板变量、占位符或示例字段名，例如 [H2_SUM]、[H1_Avg]、[Growth]、{{value}}、<metric_value>、TBD、待填、占位。
    - 禁止把“待计算”“待本地执行”“需全量 SUM 回填”“需补数据（待本地执行...）”或 `= SUM(...)`、`SUM(交易金额)/SUM(交易人数)` 这类公式草稿当成结果。
    - Markdown 表格单元格必须是真实数值、单位、百分比或明确缺失说明（未覆盖/无法从当前表格计算）。
    - 如果事实包、Notebook 或 SQL 证据没有对应值，不要猜测或保留模板，必须写明缺失边界。
    """

    private struct RetrievalLimits {
        var templateCount: Int
        var correctionCount: Int
        var reportMemoryCount: Int
        var knowledgeCount: Int
        var confluenceCount: Int
        var referenceCount: Int

        init(mode: AnalysisContextMode) {
            switch mode {
            case .quickFollowUp:
                templateCount = 3
                correctionCount = 5
                reportMemoryCount = 4
                knowledgeCount = 8
                confluenceCount = 6
                referenceCount = 10
            case .cachedFollowUp:
                templateCount = 4
                correctionCount = 6
                reportMemoryCount = 6
                knowledgeCount = 10
                confluenceCount = 8
                referenceCount = 12
            case .fullReanalysis, .reportGeneration:
                templateCount = 8
                correctionCount = 12
                reportMemoryCount = 12
                knowledgeCount = 24
                confluenceCount = 12
                referenceCount = 40
            }
        }
    }

    static func buildChatPrompt(
        userMessage: String,
        session: AnalysisSession,
        pack: DataPack,
        task: AnalysisTask?,
        reports: [ImportedReport],
        workspace: ProductWorkspace,
        contextMode: AnalysisContextMode = .fullReanalysis,
        sourcePolicy: AnalysisContextSourcePolicy = .tableOnly,
        referencedMessage: AnalysisSessionMessage? = nil
    ) -> String {
        let limits = RetrievalLimits(mode: contextMode)
        if !contextMode.usesFullContext {
            return buildLightweightFollowUpPrompt(
                userMessage: userMessage,
                session: session,
                pack: pack,
                task: task,
                reports: reports,
                workspace: workspace,
                contextMode: contextMode,
                sourcePolicy: sourcePolicy,
                referencedMessage: referencedMessage,
                limits: limits
            )
        }
        return """
        你是 NexaFlow 的 AI 直接分析引擎。你是唯一的业务分析、归因、追问、结论和报告作者；本地系统只负责无损读数、事实计算、数据覆盖和校验。

        \(FinancialPromptPolicy.coreSystemPrompt)

        # 必须遵守
        \(FinancialPromptPolicy.analysisRules)

        - 只分析“当前分析任务”选择的报表，不要把同一 Data Pack 里的其他报表混入结论。
        - 分析计算模式是 AI 主算 + 本地校验：你必须自己基于事实包计算比较、趋势、联动和归因；本地校验只用于拦截明显事实错误。
        - 没有收到或没有请求到的数据，不允许下确定结论；只能写成假设或需补数据。
        - 你可以质疑本地识别的类型、时间顺序或候选成熟口径，但必须明确说明依据，不能跳过覆盖快照中的限制。
        - 表格事实包包含 rawMatrix 原始二维表通道。rawMatrix.mode = full_raw_matrix 时你已拿到原始单元格；rawMatrix.mode = indexed_raw_matrix 时你只能把预览当线索，精确结论必须要求补充原始行列范围。
        - SQL/Notebook 是辅助计算证据，不是唯一数据来源。若 rawMatrix.mode = full_raw_matrix 且原始表已覆盖用户指定指标和周期，即使 SQL/Notebook 的某个辅助表没有命中，你也必须基于原始单元格直接计算或核对，不能写“取不到数据”“待本地执行”“需回填”。
        - 只有当 rawMatrix、字段/指标清单和 SQL/Notebook 都无法定位到具体指标、字段或周期时，才允许写“未覆盖/需补数据”；并且必须说明缺少哪个字段、指标或周期。
        - manifest、inventory、structureCandidates、dataPayload 是本地候选解释，不是最终口径；你可以基于原始矩阵推翻本地对表头、日期顺序、周期完整性和字段含义的判断。
        - 对“周期 + 指标 + 数值列”长表，本地生成的时间列、周期排序和指标序列只是候选画像；你必须结合原始行、用户问题和业务语义确认最终统计周期，不能直接照抄本地候选。
        - 覆盖快照里的“周期覆盖事实”是从原始行直接统计出来的硬事实。如果它显示某张表的周期列覆盖了某个时间范围，你不得在“未覆盖/需补数据”中写该整段周期完全缺失；只能在核对具体指标、维度或行后写“某指标/维度在该周期缺失”。
        - 小表和透视宽表上下文会尽量包含完整原始数据；大明细表首轮可能只有原始预览、字段画像、聚合摘要和样本，如不足请明确提出需要补充的数据。
        - 周期优先级固定为：用户本轮明确指定周期 > 当前任务目标周期 > 全周期概览。不要自行默认“最新完整周期 vs 上一周期”。
        - “最新周期 / 最近周期 / 本期 / latest period”属于用户本轮指定周期，必须按当前选表里可排序的最新周期理解；不得沿用会话目标或任务目标中的历史周期。
        - 如果用户未指定周期，本轮只能做全周期概览：可以说明所有可见周期的整体趋势和异常，但不要输出确定的“主比较周期”结论。
        - 如果用户指定周期，必须写清实际分析周期、对比周期和周期来源（用户指定 / 表格字段 / AI 判断 / 本地候选）。如果本地候选与用户问题冲突，以用户问题为准。
        - 每次多表分析都必须做通用“指标联动异常扫描”，不是只看用户举例的指标。你必须检查增长未传导、方向冲突、比例脱钩、漏斗断点、跨业务承接不足、外部独立驱动、结构/cohort 不匹配、周期或口径不可比。
        - 本地提供的 metricLinkageAnomalies 只是候选事实和差异证据；你负责解释候选为什么成立或不成立，不得直接写成确定因果。
        - Confluence 只能参考需求文档自身的创建/修改时间，不允许使用知识库同步时间或知识库条目创建时间；这些时间仍不等同于真实上线时间。
        - Jira 只能作为项目管理证据；Issue 创建/更新时间、状态流转时间、解决时间和 Fix Version 不等同于真实上线、灰度或业务生效时间。
        - 页面埋点只能解释用户行为路径，不能单独证明业务结果原因。
        - 竞品、政策、社会/自然事件只能按时间窗口、地区、人群和影响机制判断证据等级，不能机械归因。
        - 外部参照必须区分事件发生时间、内容发布时间和采集时间；只有采集时间的参照不能作为高置信同期归因。
        - 本轮外部证据必须优先匹配覆盖快照里的“外部证据窗口”。如果参照数据没有覆盖用户指定或报表对应的历史周期，必须明确写“当前外部证据未覆盖该历史周期，需要按该周期重新采集”，不能用当前新闻替代过去事件。
        - 如果用户修正过口径，本轮必须继承已确认口径，并说明本轮相对上一轮改变了什么。
        - 已标记为“已被纠偏覆盖”的历史 AI 回复只能作为反例，不能进入最终结论；如果旧结论与纠偏规则冲突，必须采用纠偏规则。
        - 本轮命中的智能记忆是高优先级约束，但只能在适用业务空间、指标和报表范围内使用；若记忆冲突，必须提示冲突，不得静默覆盖。
        - 涉及转化率、占比、通过率等比例指标变化时，用“百分点”表达绝对差值，不要使用未解释的“pp”。例如 10% 到 12% 写作“提升 2 个百分点”；相对变化才写作“相对提升 20%”。
        - 所有百分比数值必须四舍五入并固定保留两位小数，例如 8% 写作 8.00%、-8.7% 写作 -8.70%；“百分点”数值也固定两位，例如 1.936 个百分点写作 1.94 个百分点。其他小数最多保留两位。日期、版本号、ID、表名和原始字段名不要改写。
        - 本轮必须遵守下方“输出契约”。快速追问和定向追问不是完整报告，不要为了凑标题而重写整份分析。
        - 完整分析必须先直接回答用户问题，再说明“AI 读取到的数据”，让用户能核对你是否看到了正确的表、字段、指标、周期和外部证据。
        - 缺数据时不要输出追问式标题。应写成“建议补充的数据与证据”，明确缺少哪张表、哪些字段/指标、哪个周期、用于验证哪个假设。

        # 本轮用户需求
        \(userMessage)

        \(AggregationSemantics.promptContract(userRequest: userMessage, reports: reports))

        # 本轮上下文模式
        模式：\(contextMode.label)
        技术说明：\(contextMode.technicalDescription)
        资料范围：\(sourcePolicy.label)。\(sourcePolicy.shortDescription)
        执行动作：\(contextMode.actionLabel)
        \(contextMode.usesFullContext ? "本轮会重新读取当前任务资料，但只能使用上面资料范围允许的来源。" : "本轮不是完整重算；如果你发现缺少原始数据，必须要求用户点击“重新分析当前任务”或把结论降级为假设。")

        # 针对某条 AI 回复追问
        \(referencedMessageContext(referencedMessage))

        # 上下文缓存
        \(cacheContext(session.contextCache, mode: contextMode))

        # 当前会话
        \(sessionContext(session))

        # 当前分析任务
        \(taskContext(task, reports: reports))

        # 当前业务空间
        \(businessSpaceContext(workspace: workspace, pack: pack, task: task, session: session))

        # 本轮数据覆盖快照
        \(coverageContext(session.coverageSnapshots?.last))

        # 表格事实包
        \(reportsContext(reports, mode: contextMode))

        # 历史记忆和知识
        \(memoryContext(workspace, pack: pack, task: task, session: session, reports: reports, userMessage: userMessage, limits: limits, sourcePolicy: sourcePolicy))

        # 外部参照数据
        \(referenceContext(workspace, pack: pack, task: task, session: session, limits: limits, sourcePolicy: sourcePolicy))

        # 输出契约
        \(chatOutputContract(mode: contextMode, referencedMessage: referencedMessage))
        """
    }

    private static func buildLightweightFollowUpPrompt(
        userMessage: String,
        session: AnalysisSession,
        pack: DataPack,
        task: AnalysisTask?,
        reports: [ImportedReport],
        workspace: ProductWorkspace,
        contextMode: AnalysisContextMode,
        sourcePolicy: AnalysisContextSourcePolicy,
        referencedMessage: AnalysisSessionMessage?,
        limits: RetrievalLimits
    ) -> String {
        """
        你是 NexaFlow 的 AI 快速问答助手，面向海外金融产品经理和产品运营。你仍然调用大模型回答，但本轮不是深度分析，不要重写完整报告。

        \(FinancialPromptPolicy.coreSystemPrompt)

        # 快速问答边界
        - 只回答本轮用户问题；如果用户引用了某条 AI 回复，只围绕那条回复和本轮问题回答。
        - 只使用最近对话、上次完整分析缓存、当前会话确认口径、相关报表索引和少量证据摘要。
        - 本轮不会重新全量读表、不会主动采集外部数据、不会运行 SQL/Notebook、不会刷新机会评分、不会生成完整汇报。
        - 如果问题需要重新读取原始表格、重新采集外部源、重新计算指标或生成完整结论，请直接说明“需要点击深度分析”，不要假装已经完成重算。
        - 快速问答中的用户业务问题会进入后续汇报需求清单；你的本轮临时回答只是会话背景，不自动成为最终汇报结论。
        - 已被纠偏覆盖的历史 AI 回复只能作为反例，不能当成当前口径。
        - 缺数据时只写“需补数据/需深度分析”，不要补写完整分析章节。
        - 百分比和百分点固定保留两位小数；比例绝对差值用“百分点”，不要写 pp。
        - 本轮资料范围：\(sourcePolicy.label)。\(sourcePolicy.shortDescription)
        - 如果本轮用户说“最新周期 / 最近周期 / 本期 / latest period”，必须按当前选表里可排序的最新周期理解；不得沿用会话目标、任务目标或缓存里的历史周期。

        # 本轮用户问题
        \(userMessage)

        \(AggregationSemantics.promptContract(userRequest: userMessage, reports: reports))

        # 针对某条 AI 回复追问
        \(referencedMessageContext(referencedMessage))

        # 上下文缓存
        \(cacheContext(session.contextCache, mode: contextMode))

        # 当前会话
        \(sessionContext(session))

        # 当前任务与少量报表线索
        \(taskContext(task, reports: reports))

        # 数据覆盖摘要
        \(coverageContext(session.coverageSnapshots?.last))

        # 报表索引和趋势摘要
        \(reportsContext(reports, mode: contextMode))

        # 相关记忆和证据摘要
        \(memoryContext(workspace, pack: pack, task: task, session: session, reports: reports, userMessage: userMessage, limits: limits, sourcePolicy: sourcePolicy))

        # 已有外部参照缓存
        \(referenceContext(workspace, pack: pack, task: task, session: session, limits: limits, sourcePolicy: sourcePolicy))

        # 输出契约
        \(chatOutputContract(mode: contextMode, referencedMessage: referencedMessage))
        """
    }

    static func buildMemoPrompt(
        session: AnalysisSession,
        pack: DataPack,
        task: AnalysisTask?,
        reports: [ImportedReport],
        workspace: ProductWorkspace,
        contextMode: AnalysisContextMode = .reportGeneration,
        reportScope: ReportGenerationScope = ReportGenerationScope()
    ) -> String {
        let limits = RetrievalLimits(mode: contextMode)
        let requirementDigest = session.reportRequirementDigest ?? ReportRequirementDigestBuilder.build(session: session)
        let aggregationRequest = [reportScope.promptMarkdown, requirementDigest.markdown]
            .joined(separator: "\n")
        return """
        你是 NexaFlow 的 AI 汇报作者。请基于当前分析会话和事实包，直接生成可给业务负责人阅读的完整汇报。不要说你无法访问数据；你只能使用下方事实包和会话内容，缺失部分写入“需补数据”。

        \(FinancialPromptPolicy.coreSystemPrompt)

        # 完整汇报要求
        \(FinancialPromptPolicy.reportRules)

        - 必须同时包含用户明确要求的分析和你发现的其他重要分析。
        - 本轮汇报类型：完整汇报。
        - 下方“本次汇报范围”是最高优先级输入。你必须在开头写清：汇报类型、汇报范围、覆盖的问题、使用周期。
        - 如果范围是“指定问题”，只围绕该问题生成汇报，其他会话内容只能作为背景证据，不能扩展成全会话复盘。
        - 如果范围指定周期，表格分析和外部证据必须围绕该周期；无法覆盖时写入缺口，不能静默换成其他周期。
        - 下方“汇报需求清单”是最高优先级输入。报告必须逐项覆盖清单里的所有用户问题、追问、口径修正、质疑和重点关注项。
        - 汇报需求清单里的“已被纠偏覆盖”内容只能用于避免重复错误，不能作为最终结论写入；“最终应采用的纠偏规则 / 修正口径”必须优先执行。
        - 如果某个清单问题数据不足，不能忽略，必须写入“需补数据”，并说明缺少哪张表、哪个指标、哪个周期或哪类外部证据。
        - AI 额外发现可以加入，但不能覆盖、替代或淡化用户明确提出的问题。
        - 分析计算模式是 AI 主算 + 本地校验：你负责计算和判断，本地只提供覆盖快照、事实包和错误拦截。
        - 表格事实包包含 rawMatrix 原始二维表通道；当 rawMatrix 是全量时你要直接基于原始单元格判断，当 rawMatrix 只是索引预览时必须把未覆盖部分写入“需补数据”。
        - 本地表头、时间顺序、周期完整性和结构识别都是候选解释；你可以质疑，但必须说明依据。
        - 对“周期 + 指标 + 数值列”长表，本地长表趋势和周期排序只是候选画像；必须在报告中说明最终采用的周期来源和是否已由用户确认。
        - 覆盖快照里的“周期覆盖事实”来自原始行统计。如果它显示某张表已经覆盖某个时间范围，不得把该整段时间写成“周期完全缺失”；只有逐指标或逐维度验证后，才能写“某指标/维度缺少该周期数据”。
        - 先写数据覆盖和限制，再写本轮周期口径，再写用户指定周期分析或全周期概览，再写多表指标联动，最后写结论。
        - 周期优先级固定为：用户本轮明确指定周期 > 当前任务目标周期 > 全周期概览。不要自行默认“最新完整周期 vs 上一周期”。
        - 报告必须写清实际分析周期、对比周期、周期来源（用户指定 / 任务指定 / 全周期概览 / 表格字段 / AI 判断 / 本地候选）和外部证据是否覆盖该周期。用户未指定周期时，报告必须明确标注“用户未指定主分析周期，本汇报为全周期概览”。
        - 每次多表分析都必须纳入“指标联动异常扫描”，覆盖增长未传导、方向冲突、比例脱钩、漏斗断点、跨业务承接不足、外部独立驱动、结构/cohort 不匹配、周期或口径不可比。
        - 所有结论必须区分：事实、推断、假设、需补数据。
        - Confluence 需求文档自身创建/修改时间不等于真实上线时间，不能使用知识库同步/创建时间做归因。
        - Jira Issue 创建/更新时间、状态流转时间、解决时间和 Fix Version 不等于真实上线时间；只能作为项目状态佐证，不能单独作为业务波动原因。
        - 外部参照必须报告时间依据：事件发生时间优先，其次内容发布时间；只有采集时间时只能作为弱线索。
        - 外部证据必须匹配本汇报的分析周期；如果没有覆盖对应历史周期，必须写入“外部事件影响表”的限制说明。
        - 如果已有结构化机会评分，必须在报告中引用；如果没有，写明“本轮未形成可排序机会，需要补充哪些数据或证据后再分析”。
        - 必须在“数据覆盖与限制”或“事实/推断/假设/需补数据”中说明本汇报采用了哪些已确认记忆和纠偏口径。
        - 报告必须包含“AI 读取到的数据”，让用户能快速核对报表、字段、指标、周期、外部证据和未覆盖范围是否与原始数据一致。
        - 缺数据时使用“建议补充的数据与证据”，不要写成追问式标题。补数项要明确缺少的表、字段/指标、周期和验证目的。
        - 使用 Markdown 表格呈现关键证据，便于导出完整汇报。
        - 涉及转化率、占比、通过率等比例指标变化时，用“百分点”表达绝对差值，不要使用未解释的“pp”。例如 10% 到 12% 写作“提升 2 个百分点”；相对变化才写作“相对提升 20%”。
        - 所有百分比数值必须四舍五入并固定保留两位小数，例如 8% 写作 8.00%、-8.7% 写作 -8.70%；“百分点”数值也固定两位，例如 1.936 个百分点写作 1.94 个百分点。其他小数最多保留两位。日期、版本号、ID、表名和原始字段名不要改写。
        \(placeholderOutputRule)

        # 本次汇报范围（最高优先级）
        \(reportScope.promptMarkdown)

        \(AggregationSemantics.promptContract(userRequest: aggregationRequest, reports: reports))

        # 汇报需求清单（高优先级）
        本汇报将覆盖 \(requirementDigest.coveredQuestionCount) 个会话问题。
        \(requirementDigest.markdown)

        # 当前会话
        \(sessionContext(session, includeAllRecentMessages: true))

        # 本轮上下文模式
        模式：\(contextMode.label)
        技术说明：\(contextMode.technicalDescription)

        # 上下文缓存
        \(cacheContext(session.contextCache, mode: contextMode))

        # 当前分析任务
        \(taskContext(task, reports: reports))

        # 当前业务空间
        \(businessSpaceContext(workspace: workspace, pack: pack, task: task, session: session))

        # 本轮数据覆盖快照
        \(coverageContext(session.coverageSnapshots?.last))

        # 表格事实包
        \(reportsContext(reports, mode: contextMode))

        # 历史记忆和知识
        \(memoryContext(workspace, pack: pack, task: task, session: session, reports: reports, userMessage: requirementDigest.markdown, limits: limits, sourcePolicy: .fullContext))

        # 外部参照数据
        \(referenceContext(workspace, pack: pack, task: task, session: session, limits: limits, sourcePolicy: .fullContext))

        # 输出结构
        # 完整经营汇报
        ## 0. 汇报范围说明
        ## 1. 执行摘要
        ## 2. 用户问题与分析范围
        ## 3. 业务空间与涉及业务域
        ## 4. AI 读取到的数据
        ## 5. 数据覆盖与限制
        ## 6. 外部数据采集覆盖
        ## 7. 本轮周期口径
        ## 8. 用户指定周期分析或全周期概览
        ## 9. 关键指标变化表
        ## 10. 多表联动证据表
        ## 11. 外部事件影响表
        ## 12. 新增 / 变化指标说明
        ## 13. 事实 / 推断 / 假设 / 需补数据
        ## 14. 建议补充的数据与证据
        ## 15. 机会评分表
        ## 16. 最终建议动作与验证方案

        表格要求：
        - 第 0 部分必须列出：汇报类型、汇报范围、覆盖的问题、使用周期。
        - 第 4 到第 14 部分优先使用 Markdown 表格。
        - AI 读取到的数据表列至少包括：表名、Sheet、格式、行数、列数、已发送范围、字段/指标/周期摘要、未覆盖范围。
        - 外部数据采集覆盖表列至少包括：触发来源、分析周期、采集状态、启用源数、命中/新增/去重/过滤、失败源、限制说明。
        - 关键指标变化表列至少包括：指标、涉及周期、变化、AI 判断、已读取事实、限制。用户未指定周期时不得把某一组相邻周期称为默认主比较。
        - 多表联动证据表列至少包括：来源指标、结果指标、关系类型、时间窗口、证据等级、结论。
        - 指标联动异常表列至少包括：异常类型、来源指标、目标指标、变化差异、AI 判断、证据等级、需补数据。
        - 外部事件影响表列至少包括：事件/标题、来源、原始 URL、发生时间、内容发布时间、采集时间、时间依据、地区/人群、影响机制、对应指标、证据等级、限制说明。
        - 第 12 部分必须按事实、推断、假设、需补数据分行列出。
        - 第 13 部分必须列出补数项、缺少的数据、缺少周期、验证目的、建议用户动作；如果无需补充，写“本轮无需额外补数”。
        - 机会评分表列至少包括：机会、问题、影响用户、评分维度、优先级、建议动作。
        """
    }

    static func buildSimpleReportPrompt(
        session: AnalysisSession,
        pack: DataPack,
        task: AnalysisTask?,
        reports: [ImportedReport],
        workspace: ProductWorkspace,
        contextMode: AnalysisContextMode = .reportGeneration,
        reportScope: ReportGenerationScope = ReportGenerationScope()
    ) -> String {
        let limits = RetrievalLimits(mode: contextMode)
        let requirementDigest = session.reportRequirementDigest ?? ReportRequirementDigestBuilder.build(session: session)
        let aggregationRequest = [reportScope.promptMarkdown, requirementDigest.markdown]
            .joined(separator: "\n")
        return """
        你是 NexaFlow 的 AI 日常汇报作者。请基于当前分析会话和事实包，生成一份简洁、可直接发给产品/运营团队的日常汇报。不要说你无法访问数据；你只能使用下方事实包和会话内容，缺失部分在相关段落中简短说明。

        \(FinancialPromptPolicy.coreSystemPrompt)

        # 简洁汇报要求
        - 本轮是“简洁汇报 / 日常汇报”，不是完整汇报。
        - 必须全量理解当前任务表格、数据覆盖、周期画像、知识库、Confluence、外部证据、记忆、纠偏口径和 SQL/Notebook 计算证据。
        - 下方“本次汇报范围”是最高优先级输入。你必须在开头用 1-2 行写清：汇报类型、汇报范围、覆盖的问题、使用周期。
        - 如果范围是“指定问题”，只围绕该问题生成汇报，其他会话内容只能作为背景证据，不能扩展成全会话复盘。
        - 如果范围指定周期，表格分析和外部证据必须围绕该周期；无法覆盖时写入缺口，不能静默换成其他周期。
        - 输出必须轻量，只允许以下结构：
          # 日常汇报
          汇报范围：...
          ## 1. 周期内数据变化
          ## 2. 原因分析
          ## 3. 动作建议
        - 不要输出完整汇报里的复杂章节：AI 读取到的数据长表、完整外部证据表、机会评分表、事实/推断/假设/需补数据大表、完整补数清单、业务空间详情、汇报需求清单。
        - 如果存在关键数据限制、外部证据不足、周期口径不明或用户纠偏口径，必须在对应段落中用 1-2 句话简短说明。
        - 周期优先级固定为：用户本轮明确指定周期 > 当前任务目标周期 > 全周期概览。用户未指定周期时，写明“用户未指定主分析周期，本汇报为全周期概览”，不要自行默认“最新完整周期 vs 上一周期”。
        - 成熟窗口、本地周期识别和表格结构识别都是候选解释；最终语义由你根据事实包、用户口径和记忆判断。
        - 覆盖快照里的“周期覆盖事实”来自原始行统计。如果它显示某张表已经覆盖某个时间范围，不得把该整段时间写成“周期完全缺失”；只能在核对具体指标或维度后写“某指标/维度在该周期缺失”。
        - 必须区分事实和推断，但不要展开复杂分级表。可在原因分析中用“事实上 / 推测上 / 仍需验证”表达。
        - Confluence 文档创建/修改时间只代表需求记录时间，不等于真实上线时间。
        - Jira Issue 创建/更新时间、状态流转时间、解决时间和 Fix Version 只代表项目管理记录，不等于真实上线时间。
        - 外部参照必须使用事件发生时间或内容发布时间判断；只有采集时间时只能作为弱线索。
        - 百分比数值必须四舍五入并固定保留两位小数，例如 8% 写作 8.00%、-8.7% 写作 -8.70%；百分点数值也固定两位，例如 1.936 个百分点写作 1.94 个百分点。其他小数最多保留两位。日期、版本号、ID、表名和原始字段名不要改写。
        \(placeholderOutputRule)

        # 本次汇报范围（最高优先级）
        \(reportScope.promptMarkdown)

        \(AggregationSemantics.promptContract(userRequest: aggregationRequest, reports: reports))

        # 汇报需求清单（用于确定本次日常汇报范围）
        本汇报将覆盖 \(requirementDigest.coveredQuestionCount) 个会话问题。
        \(requirementDigest.markdown)

        # 当前会话
        \(sessionContext(session, includeAllRecentMessages: true))

        # 本轮上下文模式
        模式：\(contextMode.label)
        技术说明：\(contextMode.technicalDescription)

        # 上下文缓存
        \(cacheContext(session.contextCache, mode: contextMode))

        # 当前分析任务
        \(taskContext(task, reports: reports))

        # 当前业务空间
        \(businessSpaceContext(workspace: workspace, pack: pack, task: task, session: session))

        # 本轮数据覆盖快照
        \(coverageContext(session.coverageSnapshots?.last))

        # 表格事实包
        \(reportsContext(reports, mode: contextMode))

        # 历史记忆和知识
        \(memoryContext(workspace, pack: pack, task: task, session: session, reports: reports, userMessage: requirementDigest.markdown, limits: limits, sourcePolicy: .fullContext))

        # 外部参照数据
        \(referenceContext(workspace, pack: pack, task: task, session: session, limits: limits, sourcePolicy: .fullContext))

        # 输出结构
        # 日常汇报
        ## 1. 周期内数据变化
        用 3-6 条说明本周期或全周期内最重要的数据变化。优先写业务负责人需要知道的变化，不要铺开所有指标。

        ## 2. 原因分析
        用 3-6 条说明最可能原因。必须说明哪些是事实支撑，哪些只是推测或仍需验证。

        ## 3. 动作建议
        给出 3-5 条可执行动作，尽量包含负责人能落地的排查、补数、实验或运营动作。
        """
    }

    static func evidence(for reports: [ImportedReport], workspace: ProductWorkspace, businessSpaceID: UUID?) -> [AnalysisSessionEvidence] {
        let reportEvidence = reports.map { report in
            let sourceText = report.sourceMetadata.map { " · \($0.displaySummary)" } ?? ""
            return AnalysisSessionEvidence(
                sourceType: "报表",
                title: report.displayName,
                detail: "\(report.sourceFormat.label) · \(report.shape.label) · \(report.kind.label) · \(report.rowCount) 行 · \(report.headers.count) 列 · 首列指标 \(report.firstColumnValues.count) 个\(sourceText)",
                sourceID: report.id.uuidString
            )
        }
        let knowledgeEvidence = workspace.knowledgeEntries.prefix(6).map { entry in
            AnalysisSessionEvidence(
                sourceType: "知识库",
                title: entry.problem.nilIfBlank ?? entry.scenario,
                detail: entry.result.nilIfBlank ?? entry.action,
                sourceID: entry.id.uuidString,
                sourceURL: entry.sourceURL
            )
        }
        let sourceByID = Dictionary(uniqueKeysWithValues: workspace.referenceSources.map { ($0.id, $0) })
        let referenceEvidence = workspace.referenceItems
            .filter { $0.isVisible(in: businessSpaceID, sourceByID: sourceByID) }
            .sorted { $0.displayDate > $1.displayDate }
            .prefix(6)
            .map { item in
            AnalysisSessionEvidence(
                sourceType: item.domain.label,
                title: item.title,
                detail: "\(referenceTimingText(item))；\(item.summary.nilIfBlank ?? item.impact)",
                sourceID: item.id.uuidString,
                sourceURL: item.url
            )
        }
        return Array(reportEvidence + knowledgeEvidence + referenceEvidence)
    }

    private static func chatOutputContract(
        mode: AnalysisContextMode,
        referencedMessage: AnalysisSessionMessage?
    ) -> String {
        if referencedMessage != nil {
            return """
            请用 Markdown 简洁回答。本轮是“定向追问”，只围绕用户引用的那条 AI 回复和本轮问题作答。
            必须包含且只建议包含以下标题：
            ## 回答
            ## 依据
            ## 不确定性或下一步
            约束：
            - 不要重写整份分析报告。
            - 不要主动展开所有未被问到的多表联动、外部事件、机会评分或 AI 额外发现。
            - 如果用户只问某个证据或结论，直接解释该点；只有用户明确要求“重新完整分析 / 重算 / 全量看 / 从头分析”时，才建议使用深度分析。
            - 如果这条历史回复缺证据或口径不清，直接指出缺口，并说明需要补哪类数据。
            \(placeholderOutputRule)
            """
        }

        switch mode {
        case .quickFollowUp:
            return """
            请用 Markdown 简洁回答。本轮是“快速追问”，目标是回答用户这一句问题，不是重新生成完整分析。
            必须包含且只建议包含以下标题：
            ## 回答
            ## 必要证据
            ## 不确定性或下一步
            约束：
            - 不要重写整份分析报告。
            - 不要主动输出完整的多表联动、外部事件影响、机会评分、AI 额外发现或可采纳记忆。
            - 只引用与本轮问题直接相关的指标、周期、知识或外部证据。
            - 如果发现需要全量重算，请明确建议用户使用“深度分析”，不要在快速问答里假装已经重算。
            \(placeholderOutputRule)
            """
        case .cachedFollowUp:
            return """
            请用 Markdown 简洁回答。本轮是“快速问答（复用缓存）”，可以引用上次完整分析缓存，但不要重写整份报告。
            必须包含且只建议包含以下标题：
            ## 回答
            ## 必要依据
            ## 不确定性或下一步
            约束：
            - 只围绕本轮问题展开。
            - 可以引用上次覆盖快照、上次 AI 结论和相关缓存，但不要重新输出完整数据覆盖、多表联动和外部事件全量章节。
            - 如果缓存不足以回答，直接说明需要点击“深度分析”。
            \(placeholderOutputRule)
            """
        case .fullReanalysis, .reportGeneration:
            return """
            请用 Markdown 输出完整分析，固定包含以下标题：
            ## 直接回答你的问题
            ## 本地已校验事实
            ## 关键数据证据
            ## AI 读取到的数据
            ## 多表联动判断
            ### 指标联动异常扫描
            ## 外部证据影响
            ### 外部证据覆盖与限制
            ## AI 额外发现
            ## 未覆盖/需补数据
            ## 建议补充的数据与证据
            ## 可采纳为记忆的内容

            “直接回答你的问题”必须是第一个正文标题，先给结论、关键数值、分析口径、分析周期、对比周期和计算方式，不要先罗列读取范围。

            “AI 读取到的数据”必须让用户能核对：
            - 读了几张表，每张表的名称、Sheet、格式、行数、列数。
            - 看到了哪些字段、首列指标、时间周期。
            - 哪些表全量发送，哪些只发送样本/画像/聚合。
            - 用户指定了哪些周期；若未指定，说明本轮是全周期概览；哪些周期只是本地候选或风险提示。
            - 哪些知识库、Confluence、外部参照被纳入。
            - 哪些数据没有覆盖，你不得下确定结论。

            “建议补充的数据与证据”必须列出缺少的表、字段/指标、周期和验证目的，不要写成让用户继续追问的问题。
            \(placeholderOutputRule)
            """
        }
    }

    static func validateAnalysisOutput(
        _ output: String,
        reports: [ImportedReport],
        coverageSnapshot: AnalysisCoverageSnapshot?,
        contextMode: AnalysisContextMode = .fullReanalysis,
        referencedMessage: AnalysisSessionMessage? = nil
    ) -> [String] {
        var warnings: [String] = []
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 80 {
            warnings.append("AI 输出过短，必须至少回答问题并说明必要证据或不确定性。")
        }
        if referencedMessage != nil || contextMode == .quickFollowUp {
            if !output.contains("回答") {
                warnings.append("快速/定向追问输出缺少「回答」部分。")
            }
            if !output.contains("依据") && !output.contains("证据") {
                warnings.append("快速/定向追问输出缺少依据或必要证据。")
            }
            return warnings.uniqued()
        } else if contextMode == .cachedFollowUp {
            if !output.contains("回答") {
                warnings.append("快速问答输出缺少「回答」部分。")
            }
            if !output.contains("依据") && !output.contains("证据") {
                warnings.append("快速问答输出缺少依据或必要证据。")
            }
        } else {
            for heading in ["直接回答你的问题", "本地已校验事实", "关键数据证据", "AI 读取到的数据", "未覆盖/需补数据", "建议补充的数据与证据", "可采纳为记忆的内容"] where !output.contains(heading) {
                warnings.append("AI 输出缺少「\(heading)」部分。")
            }
            if let firstHeading = firstMarkdownHeading(in: output),
               !firstHeading.contains("直接回答你的问题") {
                warnings.append("AI 输出必须以「## 直接回答你的问题」作为第一个正文标题，先给结论和关键数值。")
            }
            if let answerRange = output.range(of: "## 直接回答你的问题"),
               let readRange = output.range(of: "## AI 读取到的数据"),
               readRange.lowerBound < answerRange.lowerBound {
                warnings.append("AI 输出必须先直接回答用户问题，再说明「AI 读取到的数据」。")
            }
            if let coverageSnapshot,
               !(coverageSnapshot.metricLinkageAnomalies ?? []).isEmpty,
               !output.contains("指标联动异常扫描") {
                warnings.append("本轮存在指标联动异常候选，AI 输出必须包含「指标联动异常扫描」小节。")
            }
        }
        warnings.append(contentsOf: sharedValidationWarnings(output, reports: reports, coverageSnapshot: coverageSnapshot, isMemo: false))
        return warnings.uniqued()
    }

    private static func firstMarkdownHeading(in output: String) -> String? {
        output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { line in
                line.trimmingCharacters(in: .whitespaces).hasPrefix("## ")
            }
    }

    static func validateMemoOutput(
        _ output: String,
        reports: [ImportedReport],
        coverageSnapshot: AnalysisCoverageSnapshot?
    ) -> [String] {
        var warnings: [String] = []
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 300 {
            warnings.append("Memo 输出过短，必须生成完整报告。")
        }
        for heading in ["执行摘要", "用户问题与分析范围", "AI 读取到的数据", "数据覆盖", "最终建议动作", "机会评分", "验证方案"] where !output.contains(heading) {
            warnings.append("Memo 缺少「\(heading)」部分。")
        }
        warnings.append(contentsOf: sharedValidationWarnings(output, reports: reports, coverageSnapshot: coverageSnapshot, isMemo: true))
        return warnings.uniqued()
    }

    private static func sharedValidationWarnings(
        _ output: String,
        reports: [ImportedReport],
        coverageSnapshot: AnalysisCoverageSnapshot?,
        isMemo: Bool
    ) -> [String] {
        var warnings: [String] = []
        if output.normalizedKey.contains("confluence") &&
            output.contains("上线") &&
            !output.contains("不等于") &&
            !output.contains("不能单独") {
            warnings.append("提到 Confluence 时必须说明文档自身创建/修改时间不等于真实上线时间。")
        }
        if containsAmbiguousPP(output) {
            warnings.append("\(isMemo ? "Memo" : "分析") 中不要使用未解释的 pp，请改用“百分点”，例如从 10% 到 12% 是提升 2 个百分点。")
        }
        let knownMetrics = Set(reports.flatMap { $0.firstColumnValues + $0.trendSummary.metricTrends.map(\.metricName) }.map(\.normalizedKey))
        if !knownMetrics.isEmpty {
            let text = output.normalizedKey
            let mentioned = knownMetrics.filter { !$0.isEmpty && text.contains($0) }.count
            if mentioned == 0 {
                warnings.append("\(isMemo ? "Memo" : "AI") 没有引用任何当前任务报表中的已知指标，必须基于实际指标分析。")
            }
        }
        if let coverageSnapshot {
            if coverageSnapshot.periodIntent?.isUserSpecified == true {
                let requestedPeriods = coverageSnapshot.periodIntent?.requestedPeriods ?? []
                let mentionedPeriods = requestedPeriods.filter { output.normalizedKey.contains($0.normalizedKey) || output.normalizedKey.contains($0.replacingOccurrences(of: "（[^）]*）", with: "", options: .regularExpression).normalizedKey) }
                if !requestedPeriods.isEmpty, mentionedPeriods.isEmpty {
                    warnings.append("用户本轮明确指定了周期，AI 必须按指定周期回应，不能改用系统默认周期。")
                }
            }
            if coverageSnapshot.excludedPeriodCount > 0 &&
                !output.contains("风险") &&
                !output.contains("排除") &&
                !output.contains("不可比") {
                warnings.append("覆盖快照显示存在周期风险或用户排除项，输出必须说明这些周期风险。")
            }
            if coverageSnapshot.profileOnlyReportCount > 0 &&
                !output.contains("画像") &&
                !output.contains("样本") &&
                !output.contains("补数") {
                warnings.append("覆盖快照显示有大表未发送全量明细，输出必须说明细分结论需要补数或只能作为观察。")
            }
            let highValueAnomalies = (coverageSnapshot.metricLinkageAnomalies ?? []).filter { $0.confidence >= 0.56 }
            if !highValueAnomalies.isEmpty {
                let anomalyTerms = ["联动异常", "不同步", "断点", "脱钩", "方向冲突", "承接不足", "未传导", "结构变化", "口径不可比"]
                if !anomalyTerms.contains(where: { output.contains($0) }) {
                    warnings.append("覆盖快照发现 \(highValueAnomalies.count) 个高价值指标联动异常候选，AI 必须解释不同步、断点、脱钩、方向冲突或承接不足等问题。")
                }
            }
            let coreMetrics = Set(coverageSnapshot.reportSnapshots.flatMap(\.coreMetricNames).map(\.normalizedKey))
            if !coreMetrics.isEmpty {
                let text = output.normalizedKey
                let mentionedCore = coreMetrics.filter { !$0.isEmpty && text.contains($0) }.count
                if mentionedCore == 0 {
                    warnings.append("AI 没有引用覆盖快照中的关键候选指标，必须基于覆盖快照重新分析或说明为什么不适用。")
                }
            }
        }
        warnings.append(contentsOf: directionConflictWarnings(output, reports: reports))
        return warnings.uniqued()
    }

    private static func directionConflictWarnings(_ output: String, reports: [ImportedReport]) -> [String] {
        let fragments = output
            .components(separatedBy: CharacterSet(charactersIn: "\n。；;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var warnings: [String] = []
        for trend in reports.flatMap(\.trendSummary.metricTrends).prefix(80) {
            guard let comparison = trend.primaryComparison else { continue }
            let key = trend.metricName.normalizedKey
            guard !key.isEmpty else { continue }
            let metricFragments = fragments.filter { $0.normalizedKey.contains(key) }
            guard !metricFragments.isEmpty else { continue }
            let metricText = metricFragments.joined(separator: "。").normalizedKey
            switch comparison.direction {
            case .up:
                if metricText.contains("下降") || metricText.contains("下滑") || metricText.contains("降低") {
                    warnings.append("指标「\(trend.metricName)」本地主比较方向为上升，AI 输出中出现下降类描述，请复核并修正。")
                }
            case .down:
                if metricText.contains("上升") || metricText.contains("上涨") || metricText.contains("提升") || metricText.contains("增长") {
                    warnings.append("指标「\(trend.metricName)」本地主比较方向为下降，AI 输出中出现上升类描述，请复核并修正。")
                }
            case .flat:
                break
            }
        }
        return warnings
    }

    private static func sessionContext(_ session: AnalysisSession, includeAllRecentMessages: Bool = false) -> String {
        let recentLimit = includeAllRecentMessages ? 30 : 14
        let messages = session.messages.suffix(recentLimit).map { message in
            let correctionNote: String
            switch message.correctionStatus {
            case .none:
                correctionNote = ""
            case .challenged:
                correctionNote = "【被质疑】"
            case .candidateGenerated:
                correctionNote = "【已生成纠偏候选】"
            case .savedAsCorrectionRule:
                correctionNote = "【已保存为纠偏规则】"
            case .supersededByCorrection:
                correctionNote = "【已被纠偏覆盖，不能作为最终结论】"
            }
            return "\(DateFormatting.shortDateTime.string(from: message.createdAt)) \(message.role.label)\(correctionNote)：\(clipped(message.content, to: 3_000))"
        }.joined(separator: "\n\n")
        return """
        会话标题：\(session.title)
        会话目标：\(session.goal.isEmpty ? "未填写" : session.goal)
        会话摘要：\(session.contextSummary.isEmpty ? "暂无" : session.contextSummary)
        最新覆盖快照：\(session.coverageSnapshots?.last?.summary ?? "暂无")
        最近消息：
        \(messages.isEmpty ? "暂无" : messages)
        """
    }

    private static func referencedMessageContext(_ message: AnalysisSessionMessage?) -> String {
        guard let message else {
            return "本轮不是针对某一条历史 AI 回复的定向追问。"
        }
        let evidence = message.evidence.prefix(8).map {
            "- \($0.sourceType)：\($0.title)；\($0.detail)"
        }.joined(separator: "\n")
        return """
        本轮用户正在针对以下历史回复继续追问或质疑。请优先围绕这条回复和它的证据回答，不要泛泛重写整份报告。
        消息时间：\(DateFormatting.shortDateTime.string(from: message.createdAt))
        消息类型：\(message.kind == .aiMemo ? "完整汇报" : (message.kind == .simpleReport ? "简洁汇报" : "AI 分析"))
        历史回复摘要：
        \(clipped(message.content, to: 4_000))
        该回复引用证据：
        \(evidence.isEmpty ? "无结构化证据" : evidence)
        """
    }

    private static func cacheContext(_ cache: AnalysisContextCache?, mode: AnalysisContextMode) -> String {
        guard let cache else {
            return "暂无可复用上下文缓存。本轮如果不是深度分析，请只基于最近会话和可见证据谨慎追问。"
        }
        let limitationText = cache.limitations.prefix(10).map { "- \($0)" }.joined(separator: "\n")
        return """
        缓存创建时间：\(DateFormatting.shortDateTime.string(from: cache.createdAt))
        缓存来源模式：\(cache.mode.label)
        本轮是否复用缓存：\(mode == .cachedFollowUp || mode == .quickFollowUp ? "是，作为追问背景" : "否，本轮会刷新完整上下文")
        缓存关联报表：\(cache.reportNames.joined(separator: "、").nilIfBlank ?? "未记录")
        上次覆盖摘要：\(cache.coverageSummary)
        上次用户需求：\(cache.lastUserRequest)
        上次 AI 结论摘要：
        \(cache.lastAssistantSummary.isEmpty ? "暂无" : clipped(cache.lastAssistantSummary, to: 3_000))
        缓存限制：
        \(limitationText.isEmpty ? "无" : limitationText)
        """
    }

    private static func coverageContext(_ snapshot: AnalysisCoverageSnapshot?) -> String {
        guard let snapshot else {
            return "暂无覆盖快照。本轮必须先明确数据覆盖与限制。"
        }
        return """
        \(AnalysisCoverageSnapshotBuilder.markdown(snapshot))

        \(AnalysisCoverageSnapshotBuilder.aiReadRangeMarkdown(snapshot))
        """
    }

    private static func taskContext(_ task: AnalysisTask?, reports: [ImportedReport]) -> String {
        guard let task else {
            return "当前任务：未选择。"
        }
        let roles = reports.map { report in
            "- \(report.displayName)：\(task.role(for: report.id).label)"
        }.joined(separator: "\n")
        let links = task.businessLinkProfile.metricLinks
            .filter { $0.confirmationStatus != .rejected }
            .prefix(24)
            .map { "- \($0.sourceMetric) -> \($0.targetMetric)：\($0.relationType.label)，证据 \($0.evidenceLevel.rawValue)，置信度 \(Int($0.confidence * 100))%" }
            .joined(separator: "\n")
        let anomalies = task.businessLinkProfile.metricLinkageAnomalies
            .filter { $0.confirmationStatus != .rejected }
            .prefix(24)
            .map { "- [\($0.anomalyType.label)] \($0.sourceMetric) -> \($0.targetMetric)：\($0.changeGapText)，证据 \($0.evidenceLevel.rawValue)，置信度 \(Int($0.confidence * 100))%" }
            .joined(separator: "\n")
        let opportunities = task.analysisReport.opportunities
            .sorted { $0.score > $1.score }
            .prefix(12)
            .map { "- \($0.title)：优先级 \($0.priorityLabel)，评分 \($0.score.compactText)，证据：\($0.evidenceSummary.nilIfBlank ?? $0.problem)" }
            .joined(separator: "\n")
        return """
        任务名称：\(task.name)
        任务目标：\(task.goal.isEmpty ? "未填写" : task.goal)
        报表角色：
        \(roles.isEmpty ? "暂无" : roles)
        业务链路：\(task.businessLinkProfile.summary)
        指标联动：
        \(links.isEmpty ? "暂无已识别指标联动" : links)
        指标联动异常：
        \(anomalies.isEmpty ? "暂无高价值指标联动异常候选" : anomalies)
        当前结构化机会评分：
        \(opportunities.isEmpty ? "暂无" : opportunities)
        """
    }

    private static func businessSpaceContext(
        workspace: ProductWorkspace,
        pack: DataPack,
        task: AnalysisTask?,
        session: AnalysisSession
    ) -> String {
        let spaceID = session.businessSpaceID ?? task?.businessSpaceID ?? pack.businessSpaceID ?? workspace.selectedBusinessSpaceID
        let space = spaceID.flatMap { id in workspace.businessSpaces.first { $0.id == id } }
        let snapshot = session.businessSpaceSnapshot ?? task?.businessSpaceSnapshot ?? space?.snapshot
        guard let snapshot else {
            return "未设置业务空间。请基于用户当前问题谨慎分析，并提示需要补充国家、业务域、核心链路和指标口径。"
        }

        let liveDomains = space?.domains ?? []
        let domains = liveDomains.isEmpty
            ? snapshot.domainNames.map { "- \($0)" }.joined(separator: "\n")
            : liveDomains.map {
                "- \($0.name)：\($0.role.label)。\($0.description.nilIfBlank ?? "无描述")；核心链路：\($0.coreFlowText.nilIfBlank ?? "未填写")"
            }.joined(separator: "\n")
        let links = (space?.domainLinks ?? []).map {
            "- \($0.sourceName) → \($0.targetName)：\($0.influenceMechanism)；时滞：\($0.lagDays.map { "\($0) 天" } ?? "未确认")；证据规则：\($0.evidenceRule.nilIfBlank ?? "未填写")"
        }.joined(separator: "\n")
        let roots = (space?.confluenceRoots ?? []).map {
            "- Root \(($0.title.nilIfBlank ?? $0.rootPageID))：绑定业务域 \($0.businessDomainIDs.count) 个；标题关键字 \($0.titleKeywords.joined(separator: "、").nilIfBlank ?? "未设置")；排除词 \($0.exclusionKeywords.joined(separator: "、").nilIfBlank ?? "未设置")"
        }.joined(separator: "\n")
        let metricLibrary = (space?.metricSemanticLibrary ?? []).prefix(40).map {
            "- \($0.metricName)：\($0.businessStage.label)，\($0.directionPreference.label)，成熟窗口 \($0.maturityWindowDays.map { "\($0) 天" } ?? "未确认")，影响时滞 \($0.impactLagDays.map { "\($0) 天" } ?? "未确认")，用户确认：\($0.isUserConfirmed ? "是" : "否")"
        }.joined(separator: "\n")
        let resolvedTimeZone = BusinessTimeZoneResolver.resolve(
            timeZoneIdentifier: space?.timeZoneIdentifier ?? snapshot.timeZoneIdentifier,
            countryRegion: space?.countryRegion.nilIfBlank ?? snapshot.countryRegion,
            businessBackground: space?.businessBackground.nilIfBlank ?? snapshot.businessBackground,
            businessSpaceName: space?.name.nilIfBlank ?? snapshot.name
        )

        return """
        业务空间：\(snapshot.name)
        国家/地区：\(snapshot.countryRegion.isEmpty ? "未填写" : snapshot.countryRegion)
        时区：\(resolvedTimeZone)
        币种：\(snapshot.currencyCode.isEmpty ? "未填写" : snapshot.currencyCode)
        主要语言：\(snapshot.primaryLanguagesText.isEmpty ? "未填写" : snapshot.primaryLanguagesText)
        业务背景：
        \(snapshot.businessBackground.isEmpty ? "未填写" : clipped(snapshot.businessBackground, to: 4_000))

        业务域：
        \(domains.isEmpty ? "尚未生成业务域。AI 需要先从表名、指标和用户目标推断，并明确不确定性。" : domains)

        跨业务域影响关系：
        \(links.isEmpty ? "暂无已确认跨业务链路。可提出候选链路，但不能限制指标扫描范围。" : links)

        指标分类规则：
        \(space?.metricClassificationRulesText.nilIfBlank ?? "必须扫描全部字段、全部首列指标和全部时间列；链路外指标进入补充维度。")

        常见异常解释：
        \(space?.anomalyRulesText.nilIfBlank ?? "暂无。请结合数据趋势和外部事件生成假设。")

        分析禁区和证据规则：
        \(space?.analysisGuardrailsText.nilIfBlank ?? "Confluence 文档时间、Jira Issue 创建/更新时间和状态流转时间都不等于真实上线时间；通用关键词不能单独判定业务域；未覆盖数据不能下结论。")

        Confluence Root Page 配置：
        \(roots.isEmpty ? "未配置业务空间 Root Page；只能使用全局知识作为弱上下文。" : roots)

        指标语义库：
        \(metricLibrary.isEmpty ? "暂无业务空间级指标语义。新增/疑似改名/口径变化指标请在本轮会话中提示并追问。" : metricLibrary)
        """
    }

    private static func reportsContext(_ reports: [ImportedReport], mode: AnalysisContextMode) -> String {
        guard !reports.isEmpty else { return "当前任务没有选择报表。" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return reports.map { report in
            let package = TableContextPackageBuilder.build(for: report)
            let packageText: String
            if mode.usesFullContext,
               let data = try? encoder.encode(package),
               let text = String(data: data, encoding: .utf8) {
                packageText = clipped(text, to: mode == .reportGeneration ? 140_000 : 120_000)
            } else if mode.usesFullContext {
                packageText = "事实包编码失败。"
            } else {
                let headers = report.headers.prefix(40).joined(separator: "、")
                let metrics = report.firstColumnValues.prefix(80).joined(separator: "、")
                let trendLines = report.trendSummary.metricTrends.prefix(24).map { trend in
                    let comparison = trend.primaryComparison.map { comparison in
                        let deltaText = comparison.delta >= 0 ? "+\(comparison.delta.compactText)" : comparison.delta.compactText
                        return "\(comparison.previousLabel) -> \(comparison.currentLabel)，方向 \(comparison.direction.rawValue)，变化 \(deltaText)"
                    } ?? "暂无相邻周期候选"
                    return "- \(trend.metricName)：\(comparison)"
                }.joined(separator: "\n")
                packageText = """
                快速问答不重新发送完整 rawMatrix。以下只是报表索引、相关趋势摘要和缓存线索；请只回答本轮问题，不要主动重新扫描全部指标或重写完整分析。如需重算原始单元格，请要求用户点击“深度分析”。
                字段：\(headers.nilIfBlank ?? "暂无")
                首列指标：\(metrics.nilIfBlank ?? "暂无")
                趋势摘要：
                \(trendLines.isEmpty ? "暂无趋势摘要" : trendLines)
                覆盖：\(package.coverage.summary)。\(package.coverage.rawCoverageDescription ?? "")
                """
            }
            let aiObservation = report.aiFirstAnalysis.map { analysis in
                """
                AI 预读：\(analysis.summary)
                AI 预读相邻候选：\(analysis.primaryComparison.prefix(20).joined(separator: "；"))
                异常：\(analysis.anomalies.prefix(12).joined(separator: "；"))
                """
            } ?? "AI 预读：尚未生成。"
            let metricSemantics = report.metricSemanticProfiles.prefix(40).map { profile in
                let maturity = profile.maturityWindowDays.map { "\($0)天成熟窗口" } ?? "无成熟窗口"
                let lag = profile.impactLagDays.map { "\($0)天影响时滞" } ?? "无明确时滞"
                let anomalies = profile.commonAnomalyExplanations.prefix(4).joined(separator: "、")
                let confirmed = profile.isUserConfirmed ? "用户已确认" : "AI/本地推断"
                return "- \(profile.metricName)：\(profile.businessStage.label)，\(profile.directionPreference.label)，\(maturity)，\(lag)，\(confirmed)，常见异常：\(anomalies)"
            }.joined(separator: "\n")
            return """
            ## 报表：\(report.displayName)
            元信息：\(report.sourceFormat.label) · \(report.shape.label) · \(report.kind.label) · \(report.rowCount) 行 · \(report.headers.count) 列 · 首列指标 \(report.firstColumnValues.count) 个
            来源说明：\(report.sourceMetadata?.aiContextDescription ?? "本地/文件导入报表。")
            解析提醒：\(report.parseWarnings.isEmpty ? "无" : report.parseWarnings.joined(separator: "；"))
            时间口径候选：\(report.timeAxisProfile.summary)
            趋势版本：\(report.trendSummary.analysisVersion ?? 0)，本轮必须以当前事实包中的周期画像为准；用户未指定周期时只能做全周期概览，不要把本地相邻候选写成默认主比较。
            \(aiObservation)
            指标语义层：
            \(metricSemantics.isEmpty ? "暂无指标语义，请基于事实包谨慎推断并标注不确定性。" : metricSemantics)
            表格事实包：
            \(packageText)
            """
        }.joined(separator: "\n\n")
    }

    private static func memoryContext(
        _ workspace: ProductWorkspace,
        pack: DataPack,
        task: AnalysisTask?,
        session: AnalysisSession,
        reports: [ImportedReport],
        userMessage: String,
        limits: RetrievalLimits,
        sourcePolicy: AnalysisContextSourcePolicy
    ) -> String {
        guard sourcePolicy.includeInternalKnowledge else {
            return "本轮资料范围为“\(sourcePolicy.label)”，未启用智能记忆、纠偏记忆、知识库、Confluence、Jira 或钉钉资料。"
        }
        let spaceID = session.businessSpaceID ?? task?.businessSpaceID ?? pack.businessSpaceID ?? workspace.selectedBusinessSpaceID
        let smartMemory = SmartMemoryRetriever.retrieve(
            workspace: workspace,
            pack: pack,
            task: task,
            session: session,
            reports: reports,
            userText: userMessage,
            limit: limits.correctionCount + limits.reportMemoryCount
        )
        let templates = workspace.analysisTemplateMemories
            .filter { !$0.isArchived && ($0.businessSpaceID == nil || $0.businessSpaceID == spaceID) }
            .prefix(limits.templateCount)
            .map {
            "- 模板：\($0.name)；目标：\($0.goal)；规则 \($0.reportRules.count) 张表；使用 \($0.useCount) 次"
        }.joined(separator: "\n")
        let corrections = workspace.correctionMemories.filter(\.appliesToFuture).prefix(limits.correctionCount).map {
            "- 纠偏：\($0.metric.isEmpty ? $0.findingTitle : $0.metric)：\($0.summaryText)"
        }.joined(separator: "\n")
        let reportMemories = workspace.reportKnowledgeMemories.filter { !$0.isArchived }.prefix(limits.reportMemoryCount).map {
            "- 报表知识：\($0.title)：\($0.content)"
        }.joined(separator: "\n")
        let knowledge = workspace.knowledgeEntries
            .filter { entry in entry.isGlobal || entry.businessSpaceID == nil || entry.businessSpaceID == spaceID }
            .prefix(limits.knowledgeCount)
            .map {
            "- [\($0.evidenceLevel.rawValue)] \($0.scenario)：\($0.problem)；\($0.result)"
        }.joined(separator: "\n")
        let confluencePages = filteredConfluencePages(workspace: workspace, spaceID: spaceID)
        let confluence = confluencePages.prefix(limits.confluenceCount).map {
            "- Confluence：\($0.title)；文档创建 \(($0.createdAt.map { DateFormatting.shortDate.string(from: $0) }) ?? "未知")；文档修改 \(($0.lastUpdated.map { DateFormatting.shortDate.string(from: $0) }) ?? "未知")；摘要：\($0.compactSummary)"
        }.joined(separator: "\n")
        let jira = workspace.jiraProjectEvidences
            .filter { evidence in
                guard let spaceID else { return true }
                return evidence.businessSpaceID == spaceID
            }
            .sorted { ($0.updatedAt ?? $0.statusChangedAt ?? $0.syncedAt) > ($1.updatedAt ?? $1.statusChangedAt ?? $1.syncedAt) }
            .prefix(limits.confluenceCount)
            .map { evidence in
                let versions = evidence.fixVersions.isEmpty ? "未记录" : evidence.fixVersions.joined(separator: "、")
                let sprints = evidence.sprintNames.isEmpty ? "未记录" : evidence.sprintNames.joined(separator: "、")
                return "- Jira：\(evidence.compactSummary)；\(evidence.timingSummary)；Fix Version：\(versions)；Sprint：\(sprints)；URL：\(evidence.issueURL)"
            }
            .joined(separator: "\n")
        let dingtalk = workspace.dingtalkDocumentItems
            .filter { item in
                guard let spaceID else { return true }
                return item.businessSpaceID == spaceID
            }
            .sorted { ($0.updatedAt ?? $0.syncedAt) > ($1.updatedAt ?? $1.syncedAt) }
            .prefix(limits.confluenceCount)
            .map { item in
                "- 钉钉：\(item.kind.label)《\(item.title)》；\(item.timingSummary)；内容状态：\(item.contentStatus)；摘要：\(clipped(item.summary, to: 900))；URL：\(item.sourceURL.nilIfBlank ?? "未返回")"
            }
            .joined(separator: "\n")
        return """
        智能记忆检索：
        \(smartMemory.promptText)

        分析模板：
        \(templates.isEmpty ? "暂无" : templates)

        纠偏记忆：
        \(corrections.isEmpty ? "暂无" : corrections)

        报表知识记忆：
        \(reportMemories.isEmpty ? "暂无" : reportMemories)

        知识库：
        \(knowledge.isEmpty ? "暂无" : knowledge)

        Confluence：
        \(confluence.isEmpty ? "暂无" : confluence)

        Jira 项目证据：
        \(jira.isEmpty ? "暂无" : jira)
        规则：Jira 创建时间、更新时间、状态变更时间、解决时间和 Fix Version 只能作为项目管理证据；不能自动等同真实上线、灰度或业务生效时间。若需要作为高置信原因，必须有发布日志、埋点、版本记录或用户确认补充。

        钉钉文档证据：
        \(dingtalk.isEmpty ? "暂无" : dingtalk)
        规则：钉钉文档创建/更新时间只代表文档记录；不能自动等同真实上线、灰度或业务生效时间。若文档仅同步元数据，只能作为线索，不能作为高置信归因。
        """
    }

    private static func referenceContext(
        _ workspace: ProductWorkspace,
        pack: DataPack,
        task: AnalysisTask?,
        session: AnalysisSession,
        limits: RetrievalLimits,
        sourcePolicy: AnalysisContextSourcePolicy
    ) -> String {
        guard sourcePolicy.includeExternalReferences else {
            return "本轮资料范围为“\(sourcePolicy.label)”，未启用历史外部参照缓存，也不会拉取新的外部参照源。"
        }
        let spaceID = session.businessSpaceID ?? task?.businessSpaceID ?? pack.businessSpaceID ?? workspace.selectedBusinessSpaceID
        let window = session.coverageSnapshots?.last?.externalEvidenceWindow
        let sourceByID = Dictionary(uniqueKeysWithValues: workspace.referenceSources.map { ($0.id, $0) })
        let baseItems = workspace.referenceItems
            .filter { item in
                item.isRelevant && item.isVisible(in: spaceID, sourceByID: sourceByID)
            }
        let scopedItems = window.map { evidenceWindow in
            baseItems.filter { evidenceWindow.contains($0) }
        } ?? baseItems
        let runIDs = Set(scopedItems.compactMap(\.collectionRunID))
        let matchedRuns = workspace.referenceCollectionRuns
            .filter { runIDs.contains($0.id) || $0.sessionID == session.id }
            .sorted { $0.startedAt > $1.startedAt }
        let items = scopedItems
            .sorted { $0.displayDate > $1.displayDate }
            .prefix(limits.referenceCount)
            .map { item in
                """
                - [\(item.domain.label)/\(item.intelligenceCategory.label)] \(item.sourceName)：\(item.title)
                  URL：\(item.url.nilIfBlank ?? "无原始 URL")
                  时间：\(referenceTimingText(item))
                  摘要：\(item.summary.nilIfBlank ?? item.impact.nilIfBlank ?? clipped(item.rawContent, to: 600))
                  时间依据：\(item.dateBasisLabel)，证据置信度 \(Int(item.resolvedDateConfidence * 100))%
                  限制：\(item.dateCaveat.isEmpty ? "无" : item.dateCaveat)
                """
            }
            .joined(separator: "\n")
        let coverage: String
        if let window {
            let publishedOnlyCount = scopedItems.filter { $0.resolvedDateBasis == .publishedAt }.count
            let collectedOnlyCount = scopedItems.filter { $0.resolvedDateBasis == .collectedAt }.count
            let collectionText = matchedRuns.prefix(5).map { run in
                "- \(run.trigger.label) \(DateFormatting.shortDateTime.string(from: run.startedAt))：\(run.summary)"
            }.joined(separator: "\n")
            coverage = """
            外部证据窗口：\(window.summary)
            已按该窗口匹配 \(scopedItems.count) 条参照；其中仅内容发布时间 \(publishedOnlyCount) 条、仅采集时间 \(collectedOnlyCount) 条。
            外部数据采集覆盖：
            \(collectionText.isEmpty ? "未找到与本轮窗口直接关联的采集任务；当前外部证据可能来自历史缓存。" : collectionText)
            \(scopedItems.isEmpty && !baseItems.isEmpty ? "当前外部证据未覆盖该历史周期，需要按该周期重新采集；不能把缓存里的当前新闻当作该周期原因。" : "")
            """
        } else {
            let collectionText = matchedRuns.prefix(5).map { run in
                "- \(run.trigger.label) \(DateFormatting.shortDateTime.string(from: run.startedAt))：\(run.summary)"
            }.joined(separator: "\n")
            coverage = """
            外部证据窗口：未识别明确周期，参照只能作为一般背景。
            外部数据采集覆盖：
            \(collectionText.isEmpty ? "未找到与本轮会话关联的采集任务。" : collectionText)
            """
        }
        return """
        \(coverage)

        \(items.isEmpty ? "暂无匹配本轮周期的参照数据。" : items)
        """
    }

    private static func filteredConfluencePages(workspace: ProductWorkspace, spaceID: UUID?) -> [ConfluencePage] {
        guard let spaceID,
              let space = workspace.businessSpaces.first(where: { $0.id == spaceID }),
              !space.confluenceRoots.isEmpty else {
            return Array(workspace.confluencePages.prefix(12))
        }
        return workspace.confluencePages.filter { page in
            space.confluenceRoots.contains { root in
                let rootID = root.rootPageID.trimmingCharacters(in: .whitespacesAndNewlines)
                let rootMatches = rootID.isEmpty || page.id == rootID || page.ancestors.contains(rootID)
                guard rootMatches else { return false }
                let titleKey = page.title.normalizedKey
                let includeMatches = root.titleKeywords.isEmpty || root.titleKeywords.contains { titleKey.contains($0.normalizedKey) }
                let excluded = root.exclusionKeywords.contains { titleKey.contains($0.normalizedKey) }
                return includeMatches && !excluded
            }
        }
    }

    private static func referenceTimingText(_ item: ExternalReferenceItem) -> String {
        let start = item.eventStartedAt.map { "事件开始 \(DateFormatting.shortDate.string(from: $0))" }
        let published = item.publishedAt.map { "内容发布 \(DateFormatting.shortDate.string(from: $0))" }
        let collected = "采集 \(DateFormatting.shortDateTime.string(from: item.collectedAt))"
        return [
            "分析日期 \(DateFormatting.shortDate.string(from: item.displayDate))",
            "依据 \(item.dateBasisLabel)",
            "置信度 \(Int(item.resolvedDateConfidence * 100))%",
            start,
            published,
            collected
        ].compactMap { $0 }.joined(separator: "，")
    }

    private static func containsAmbiguousPP(_ text: String) -> Bool {
        guard !text.contains("百分点") else { return false }
        return text.range(of: #"(?i)(^|[^A-Za-z])pp([^A-Za-z]|$)"#, options: .regularExpression) != nil
    }

    private static func clipped(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n...[已截断，AI 如需更多数据必须请求补充或说明限制]"
    }
}
