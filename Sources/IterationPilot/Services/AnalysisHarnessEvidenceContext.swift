import Foundation

struct ContextEvidenceManifestBuilder {
    static func build(
        userQuery: String,
        workspace: ProductWorkspace,
        pack: DataPack,
        task: AnalysisTask?,
        session: AnalysisSession,
        sourcePolicy: AnalysisContextSourcePolicy
    ) -> ContextEvidenceManifest {
        guard sourcePolicy.includeInternalKnowledge || sourcePolicy.includeExternalReferences else {
            return ContextEvidenceManifest(
                sourcePolicy: sourcePolicy,
                items: [],
                warnings: ["本轮资料范围为“\(sourcePolicy.label)”，未启用知识库或外部参照。"]
            )
        }
        let spaceID = session.businessSpaceID ?? task?.businessSpaceID ?? pack.businessSpaceID ?? workspace.selectedBusinessSpaceID
        var items: [ContextEvidenceItem] = []

        if sourcePolicy.includeInternalKnowledge {
            items.append(contentsOf: workspace.correctionMemories
                .filter(\.appliesToFuture)
                .prefix(12)
                .enumerated()
                .map { index, memory in
                    ContextEvidenceItem(
                        sourceType: .correctionMemory,
                        sourceID: memory.id.uuidString,
                        title: memory.metric.isEmpty ? memory.findingTitle : memory.metric,
                        summary: clippedContext(memory.summaryText, to: 420),
                        citationLabel: "M\(index + 1)",
                        confidence: .high,
                        limitations: ["纠偏记忆是内部经验规则，不能替代表格计算。"]
                    )
                })
            items.append(contentsOf: workspace.reportKnowledgeMemories
                .filter { !$0.isArchived }
                .prefix(12)
                .enumerated()
                .map { index, memory in
                    ContextEvidenceItem(
                        sourceType: .reportKnowledge,
                        sourceID: memory.id.uuidString,
                        title: memory.title,
                        summary: clippedContext(memory.content, to: 520),
                        citationLabel: "R\(index + 1)",
                        confidence: .medium,
                        limitations: ["报表知识只解释字段/口径，不产生指标数值。"]
                    )
                })
            items.append(contentsOf: workspace.knowledgeEntries
                .filter { entry in entry.isGlobal || entry.businessSpaceID == nil || entry.businessSpaceID == spaceID }
                .prefix(16)
                .enumerated()
                .map { index, entry in
                    ContextEvidenceItem(
                        sourceType: .knowledgeBase,
                        sourceID: entry.id.uuidString,
                        title: entry.scenario.nilIfBlank ?? entry.problem,
                        summary: clippedContext([entry.problem, entry.action, entry.result].filter { !$0.isEmpty }.joined(separator: "；"), to: 620),
                        citationLabel: "K\(index + 1)",
                        sourceURL: entry.sourceURL,
                        eventDate: entry.sourceUpdatedAt ?? entry.createdAt,
                        confidence: entry.evidenceLevel.rawValue.localizedCaseInsensitiveContains("高") ? .high : .medium,
                        limitations: ["知识库是内部沉淀，只能作为解释证据。"]
                    )
                })
            items.append(contentsOf: filteredConfluencePages(workspace: workspace, spaceID: spaceID)
                .prefix(12)
                .enumerated()
                .map { index, page in
                    ContextEvidenceItem(
                        sourceType: .confluence,
                        sourceID: page.id,
                        title: page.title,
                        summary: clippedContext(page.compactSummary, to: 700),
                        citationLabel: "C\(index + 1)",
                        sourceURL: page.url,
                        eventDate: page.lastUpdated ?? page.createdAt,
                        confidence: .medium,
                        limitations: ["文档创建/更新时间不等于真实上线或业务生效时间。"]
                    )
                })
            items.append(contentsOf: workspace.jiraProjectEvidences
                .filter { evidence in
                    guard let spaceID else { return true }
                    return evidence.businessSpaceID == spaceID
                }
                .sorted { ($0.updatedAt ?? $0.statusChangedAt ?? $0.syncedAt) > ($1.updatedAt ?? $1.statusChangedAt ?? $1.syncedAt) }
                .prefix(12)
                .enumerated()
                .map { index, evidence in
                    ContextEvidenceItem(
                        sourceType: .jira,
                        sourceID: evidence.id.uuidString,
                        title: "\(evidence.issueKey) \(evidence.summary)",
                        summary: clippedContext([evidence.status, evidence.commentSummary, evidence.changelogSummary].filter { !$0.isEmpty }.joined(separator: "；"), to: 620),
                        citationLabel: "J\(index + 1)",
                        sourceURL: evidence.issueURL,
                        eventDate: evidence.updatedAt ?? evidence.statusChangedAt ?? evidence.syncedAt,
                        confidence: .medium,
                        limitations: ["Jira 时间只能作为项目管理证据，不等同真实上线/灰度/生效时间。"]
                    )
                })
            items.append(contentsOf: workspace.dingtalkDocumentItems
                .filter { item in
                    guard let spaceID else { return true }
                    return item.businessSpaceID == spaceID
                }
                .sorted { ($0.updatedAt ?? $0.syncedAt) > ($1.updatedAt ?? $1.syncedAt) }
                .prefix(12)
                .enumerated()
                .map { index, item in
                    ContextEvidenceItem(
                        sourceType: .dingtalk,
                        sourceID: item.id.uuidString,
                        title: item.title,
                        summary: clippedContext(item.summary, to: 620),
                        citationLabel: "D\(index + 1)",
                        sourceURL: item.sourceURL.nilIfBlank,
                        eventDate: item.updatedAt ?? item.syncedAt,
                        confidence: item.contentStatus.localizedCaseInsensitiveContains("metadata") ? .low : .medium,
                        limitations: ["钉钉文档时间只代表记录时间，不等同真实上线或业务生效时间。"]
                    )
                })
        }

        if sourcePolicy.includeExternalReferences {
            items.append(contentsOf: workspace.referenceItems
                .filter { item in
                    item.isRelevant && (item.businessSpaceID == nil || item.businessSpaceID == spaceID)
                }
                .sorted { $0.displayDate > $1.displayDate }
                .prefix(30)
                .enumerated()
                .map { index, item in
                    ContextEvidenceItem(
                        sourceType: .externalReference,
                        sourceID: item.id.uuidString,
                        title: item.title,
                        summary: clippedContext(item.summary.nilIfBlank ?? item.impact.nilIfBlank ?? item.rawContent, to: 700),
                        citationLabel: "E\(index + 1)",
                        sourceURL: item.url.nilIfBlank,
                        eventDate: item.displayDate,
                        confidence: item.resolvedDateConfidence >= 0.75 ? .high : (item.resolvedDateConfidence >= 0.5 ? .medium : .low),
                        limitations: [item.dateCaveat].filter { !$0.isEmpty }
                    )
                })
        }

        var warnings: [String] = []
        if items.isEmpty {
            warnings.append("本轮启用了“\(sourcePolicy.label)”，但没有命中可引用的知识库或外部参照。")
        }
        if sourcePolicy.includeExternalReferences && !items.contains(where: { $0.sourceType == .externalReference }) {
            warnings.append("外部参照范围已开启，但当前缓存/采集结果没有可引用条目。")
        }
        return ContextEvidenceManifest(sourcePolicy: sourcePolicy, items: items, warnings: warnings)
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

    private static func clippedContext(_ text: String, to limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "...[已截断]"
    }
}
