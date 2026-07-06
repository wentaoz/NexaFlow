import Foundation

enum SmartMemoryExtractionService {
    static func extractCandidates(
        from userText: String,
        sessionID: UUID?,
        messageID: UUID?,
        businessSpaceID: UUID?,
        reports: [ImportedReport]
    ) -> [SmartMemoryCandidate] {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let key = trimmed.normalizedKey
        let explicit = containsAny(key, [
            "以后", "后续", "每次", "默认", "必须", "不要", "不能", "不允许", "记住", "按这个", "按这种", "都要", "统一", "口径", "表示", "含义", "不是"
        ])
        guard explicit else { return [] }

        var candidates: [SmartMemoryCandidate] = []
        func append(kind: SmartMemoryKind, title: String, rationale: String, confidence: Double = 0.74, tags: [String]) {
            candidates.append(SmartMemoryCandidate(
                kind: kind,
                businessSpaceID: businessSpaceID,
                sessionID: sessionID,
                messageID: messageID,
                title: title,
                content: trimmed,
                scope: businessSpaceID == nil ? "全局候选" : "当前业务空间",
                rationale: rationale,
                confidence: confidence,
                tags: (["智能记忆候选"] + tags).uniqued()
            ))
        }

        if containsAny(key, ["不对", "误判", "错误", "不能", "不要", "不允许", "不是", "confluence", "上线", "采集时间", "同步时间", "未成熟"]) {
            append(kind: .correctionRule, title: "纠偏规则候选", rationale: "用户表达了需要 AI 避免的误判或禁区。", confidence: 0.82, tags: ["纠偏规则"])
        }
        if containsAny(key, ["指标", "口径", "含义", "表示", "越高越好", "越低越好", "成熟窗口", "时滞", "滞后", "时间列", "交易时间", "注册时间", "统计周期"]) {
            append(kind: .metricDefinition, title: "指标/时间口径候选", rationale: "用户解释了指标或时间口径，可用于后续同类报表。", confidence: 0.8, tags: ["指标口径"])
        }
        if containsAny(key, ["最新完整周期", "上一周期", "主比较", "多表", "联动", "传导", "漏斗", "归因", "外部事件", "竞品", "政策"]) {
            append(kind: .analysisPreference, title: "分析偏好候选", rationale: "用户描述了分析方法或固定检查项。", confidence: 0.76, tags: ["分析偏好"])
        }
        if containsAny(key, ["报告", "老板", "word", "表格", "结论", "证据", "百分点", "pp", "百分比", "小数", "摘要", "风险", "验证"]) {
            append(kind: .reportPreference, title: "报告偏好候选", rationale: "用户描述了报告输出规范或展示偏好。", confidence: 0.76, tags: ["报告偏好"])
        }
        if containsAny(key, ["业务链路", "上游", "下游", "承接", "跨业务", "影响", "传导"]) {
            append(kind: .businessLinkRule, title: "业务链路规则候选", rationale: "用户描述了业务域或指标之间的影响关系。", confidence: 0.7, tags: ["业务链路"])
        }
        if containsAny(key, ["天气", "用电", "停电", "cfe", "节假日", "地震", "火山", "自然事件", "社会事件", "外部事件"]) {
            append(kind: .externalEventRule, title: "外部事件归因规则候选", rationale: "用户描述了外部事件影响判断规则。", confidence: 0.72, tags: ["外部事件"])
        }

        if candidates.isEmpty {
            append(kind: .analysisPreference, title: "通用长期偏好候选", rationale: "用户使用了长期记忆触发词。", confidence: 0.62, tags: ["通用偏好"])
        }

        let metricNames = reports.flatMap { $0.firstColumnValues + $0.headers }.filter { metric in
            trimmed.normalizedKey.contains(metric.normalizedKey)
        }.prefix(6)
        if !metricNames.isEmpty {
            candidates = candidates.map { candidate in
                var copy = candidate
                copy.tags = (copy.tags + metricNames.map { "指标:\($0)" }).uniqued()
                return copy
            }
        }
        return candidates.uniqued()
    }

    private static func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains { text.contains($0.normalizedKey) }
    }
}

enum SmartMemoryRetriever {
    struct Result: Hashable {
        var used: [SmartMemory]
        var unused: [SmartMemory]

        var promptText: String {
            let usedText = used.prefix(24).map { memory in
                "- [\(memory.kind.label)] \(memory.title)：\(memory.content)；范围：\(memory.scope)；置信度 \(Int(memory.confidence * 100))%；来源：\(memory.sourceType)"
            }.joined(separator: "\n")
            let unusedText = unused.prefix(8).map { memory in
                "- [\(memory.kind.label)] \(memory.title)：未命中本轮关键词或业务空间范围"
            }.joined(separator: "\n")
            return """
            本轮命中智能记忆：
            \(usedText.isEmpty ? "暂无" : usedText)

            本轮未使用的相关记忆：
            \(unusedText.isEmpty ? "暂无" : unusedText)
            """
        }
    }

    static func retrieve(
        workspace: ProductWorkspace,
        pack: DataPack,
        task: AnalysisTask?,
        session: AnalysisSession,
        reports: [ImportedReport],
        userText: String,
        limit: Int = 24
    ) -> Result {
        let spaceID = session.businessSpaceID ?? task?.businessSpaceID ?? pack.businessSpaceID ?? workspace.selectedBusinessSpaceID
        let queryTerms = queryTerms(userText: userText, task: task, reports: reports)
        let all = buildSmartMemories(workspace: workspace, spaceID: spaceID)
        let scoped = all.filter { memory in
            memory.businessSpaceID == nil || memory.businessSpaceID == spaceID
        }
        let scored = scoped.map { memory -> (SmartMemory, Int) in
            var score = memory.priority
            let haystack = [
                memory.title,
                memory.content,
                memory.scope,
                memory.tags.joined(separator: " ")
            ].joined(separator: " ").normalizedKey
            for term in queryTerms where !term.isEmpty && haystack.contains(term) {
                score += 3
            }
            if memory.isUserConfirmed { score += 4 }
            return (memory, score)
        }
        let sorted = scored.sorted { lhs, rhs in
            if lhs.1 == rhs.1 { return lhs.0.updatedAt > rhs.0.updatedAt }
            return lhs.1 > rhs.1
        }
        let used = sorted.filter { $0.1 > 0 }.prefix(limit).map(\.0)
        let usedIDs = Set(used.map(\.id))
        let unused = sorted.map(\.0).filter { !usedIDs.contains($0.id) }.prefix(12).map { $0 }
        return Result(used: Array(used), unused: Array(unused))
    }

    static func buildSmartMemories(workspace: ProductWorkspace, spaceID: UUID?) -> [SmartMemory] {
        var memories: [SmartMemory] = []
        memories.append(contentsOf: workspace.correctionMemories.filter(\.appliesToFuture).map { memory in
            SmartMemory(
                id: memory.id,
                kind: .correctionRule,
                title: memory.metric.nilIfBlank ?? memory.findingTitle.nilIfBlank ?? "历史纠偏规则",
                content: memory.summaryText,
                scope: memory.scope.nilIfBlank ?? memory.packName,
                businessSpaceID: memory.businessSpaceID,
                sourceID: "correction-\(memory.id.uuidString)",
                sourceType: "纠偏记忆",
                confidence: 0.9,
                priority: 80,
                tags: memory.tags,
                updatedAt: memory.updatedAt,
                isUserConfirmed: true
            )
        })
        for space in workspace.businessSpaces where spaceID == nil || space.id == spaceID {
            memories.append(contentsOf: space.metricSemanticLibrary.map { semantic in
                SmartMemory(
                    id: semantic.id,
                    kind: .metricDefinition,
                    title: semantic.metricName,
                    content: [
                        semantic.businessStage.label,
                        semantic.directionPreference.label,
                        semantic.maturityWindowDays.map { "成熟窗口 \($0) 天" },
                        semantic.impactLagDays.map { "影响时滞 \($0) 天" },
                        semantic.commonAnomalyExplanationsText
                    ].compactMap { $0 }.joined(separator: "；"),
                    scope: space.name,
                    businessSpaceID: space.id,
                    sourceID: "metric-semantic-\(semantic.id.uuidString)",
                    sourceType: "指标语义",
                    confidence: semantic.isUserConfirmed ? 0.88 : 0.62,
                    priority: semantic.isUserConfirmed ? 70 : 30,
                    tags: ["指标口径", semantic.businessStage.label],
                    updatedAt: semantic.updatedAt,
                    isUserConfirmed: semantic.isUserConfirmed
                )
            })
        }
        memories.append(contentsOf: workspace.analysisTemplateMemories.filter { !$0.isArchived }.map { template in
            SmartMemory(
                id: template.id,
                kind: .analysisTemplate,
                title: template.name,
                content: template.goal.nilIfBlank ?? template.relationshipSummary,
                scope: template.sourceTaskName.nilIfBlank ?? "分析模板",
                businessSpaceID: template.businessSpaceID,
                sourceID: "analysis-template-\(template.id.uuidString)",
                sourceType: "分析模板",
                confidence: 0.78,
                priority: 45 + min(template.useCount, 10),
                tags: ["分析模板"] + template.outputInstructions,
                updatedAt: template.updatedAt,
                hitCount: template.useCount,
                lastUsedAt: template.lastUsedAt,
                isUserConfirmed: true
            )
        })
        memories.append(contentsOf: workspace.reportKnowledgeMemories.filter { !$0.isArchived }.map { memory in
            SmartMemory(
                id: memory.id,
                kind: .reportKnowledge,
                title: memory.title,
                content: memory.content,
                scope: memory.reportNamePattern,
                businessSpaceID: nil,
                sourceID: "report-memory-\(memory.id.uuidString)",
                sourceType: "报表知识",
                confidence: 0.72,
                priority: 36 + min(memory.hitCount, 10),
                tags: ["报表解释", memory.reportKind.label, memory.reportShape.label],
                updatedAt: memory.updatedAt,
                hitCount: memory.hitCount,
                lastUsedAt: memory.lastMatchedAt,
                isUserConfirmed: true
            )
        })
        memories.append(contentsOf: workspace.knowledgeEntries.filter { entry in
            entry.isGlobal || entry.businessSpaceID == nil || entry.businessSpaceID == spaceID
        }.map { entry in
            let kind = smartKind(for: entry)
            return SmartMemory(
                id: entry.id,
                kind: kind,
                title: entry.problem.nilIfBlank ?? entry.scenario,
                content: entry.result.nilIfBlank ?? entry.action,
                scope: entry.scenario,
                businessSpaceID: entry.businessSpaceID,
                sourceID: entry.sourceID ?? "knowledge-\(entry.id.uuidString)",
                sourceType: "知识库",
                confidence: entry.evidenceLevel == .a ? 0.88 : entry.evidenceLevel == .b ? 0.75 : 0.55,
                priority: kind == .knowledgeFact ? 20 : 42,
                tags: entry.tags,
                updatedAt: entry.sourceUpdatedAt ?? entry.createdAt,
                isUserConfirmed: entry.tags.contains { $0.normalizedKey.contains("提问记忆") || $0.normalizedKey.contains("人工") }
            )
        })
        return memories.uniqued()
    }

    private static func smartKind(for entry: KnowledgeEntry) -> SmartMemoryKind {
        let tags = entry.tags.joined(separator: " ").normalizedKey
        let text = "\(entry.scenario) \(entry.problem) \(entry.action) \(entry.result)".normalizedKey
        if tags.contains("纠偏") || text.contains("不要") || text.contains("不能") { return .correctionRule }
        if tags.contains("指标口径") || text.contains("口径") || text.contains("指标") { return .metricDefinition }
        if tags.contains("报告偏好") || text.contains("报告") || text.contains("word") { return .reportPreference }
        if tags.contains("分析偏好") || text.contains("主比较") || text.contains("联动") { return .analysisPreference }
        if tags.contains("外部事件") || text.contains("事件发生时间") || text.contains("采集时间") { return .externalEventRule }
        if tags.contains("报表知识") || tags.contains("ai问答沉淀") { return .reportKnowledge }
        return .knowledgeFact
    }

    private static func queryTerms(userText: String, task: AnalysisTask?, reports: [ImportedReport]) -> [String] {
        let rawTerms = [userText, task?.goal ?? "", task?.name ?? ""]
            + reports.flatMap {
                [$0.displayName, $0.kind.label, $0.shape.label]
                    + Array($0.headers.prefix(12))
                    + Array($0.firstColumnValues.prefix(24))
            }
        return rawTerms
            .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: " ，,。；;\n\t/|：:（）()[]【】")) }
            .map { $0.normalizedKey }
            .filter { $0.count >= 2 }
            .uniqued()
            .prefix(120)
            .map { $0 }
    }
}
