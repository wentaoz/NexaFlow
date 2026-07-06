import Foundation

enum ReferenceSourceHealthStatus: String, Hashable {
    case collectable
    case missingTavilyKey
    case missingQuery
    case missingURL
    case emptyManualNote
    case lastTestFailed
    case lastCollectionSucceeded

    var label: String {
        switch self {
        case .collectable: return "可采集"
        case .missingTavilyKey: return "缺少 Tavily Key"
        case .missingQuery: return "缺少 Query/关键词"
        case .missingURL: return "缺少 URL"
        case .emptyManualNote: return "人工备注为空"
        case .lastTestFailed: return "上次测试失败"
        case .lastCollectionSucceeded: return "上次采集成功"
        }
    }

    var isCollectable: Bool {
        switch self {
        case .collectable, .lastCollectionSucceeded:
            return true
        case .missingTavilyKey, .missingQuery, .missingURL, .emptyManualNote, .lastTestFailed:
            return false
        }
    }
}

struct ReferenceSourceHealth: Hashable {
    var status: ReferenceSourceHealthStatus
    var detail: String
    var latestRunID: UUID?
    var latestLog: ExternalReferenceSourceRunLog?

    var isCollectable: Bool {
        status.isCollectable
    }
}

enum ReferenceSourceHealthEvaluator {
    static func evaluate(
        source: ExternalReferenceSource,
        searchSettings: SearchAPISettings,
        collectionRuns: [ExternalReferenceCollectionRun]
    ) -> ReferenceSourceHealth {
        if let configurationIssue = configurationIssue(for: source, searchSettings: searchSettings) {
            return configurationIssue
        }

        if let latest = latestLog(for: source.id, in: collectionRuns),
           latest.log.status == .succeeded {
            return ReferenceSourceHealth(
                status: .lastCollectionSucceeded,
                detail: "最近一次采集成功：返回 \(latest.log.rawItemCount) 条，有效 \(latest.log.validItemCount) 条，沉淀 \(latest.log.knowledgeEntryCount) 条。",
                latestRunID: latest.run.id,
                latestLog: latest.log
            )
        }

        if let latestTest = latestLog(for: source.id, in: collectionRuns, trigger: .singleSourceTest),
           latestTest.log.status == .failed {
            return ReferenceSourceHealth(
                status: .lastTestFailed,
                detail: latestTest.log.errorMessage.nilIfBlank ?? "上次测试失败，请查看采集日志或修改配置后重试。",
                latestRunID: latestTest.run.id,
                latestLog: latestTest.log
            )
        }

        let tavilyCountryNote: String
        if source.collectorType == .tavilySearch {
            let decision = TavilyCountryResolver.decision(country: source.tavilyCountry, topic: source.tavilyTopic)
            tavilyCountryNote = decision.original.isEmpty ? "" : "；\(decision.reason)"
        } else {
            tavilyCountryNote = ""
        }
        return ReferenceSourceHealth(
            status: .collectable,
            detail: "配置已满足采集条件，可先测试此源，也可参与下一次正式采集\(tavilyCountryNote)。",
            latestRunID: nil,
            latestLog: nil
        )
    }

    static func configurationIssue(
        for source: ExternalReferenceSource,
        searchSettings: SearchAPISettings
    ) -> ReferenceSourceHealth? {
        let url = source.url.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = source.queryTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let keywords = source.keywordsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = source.manualNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasQueryOrKeywords = !query.isEmpty || !keywords.isEmpty

        switch source.collectorType {
        case .manual:
            guard !note.isEmpty else {
                return ReferenceSourceHealth(status: .emptyManualNote, detail: "人工填写源需要备注内容，否则采集不会产生情报。")
            }
        case .webPage, .rss:
            guard !url.isEmpty else {
                return ReferenceSourceHealth(status: .missingURL, detail: "\(source.collectorType.label) 数据源需要填写 URL。")
            }
        case .searchAPI:
            guard !url.isEmpty else {
                return ReferenceSourceHealth(status: .missingURL, detail: "通用搜索接口需要填写 Endpoint URL。")
            }
            guard hasQueryOrKeywords else {
                return ReferenceSourceHealth(status: .missingQuery, detail: "通用搜索接口需要填写查询语句或关键词。")
            }
        case .tavilySearch:
            guard !searchSettings.tavilyAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return ReferenceSourceHealth(status: .missingTavilyKey, detail: "Tavily 数据源需要先在全局搜索 API 填写 Tavily Key。")
            }
            guard hasQueryOrKeywords else {
                return ReferenceSourceHealth(status: .missingQuery, detail: "可以不填 URL，走全局 Tavily Endpoint；但必须填 Query 或关键词，否则保存后即使是启用状态，正式采集也会跳过它。")
            }
        }

        return nil
    }

    static func latestLog(
        for sourceID: UUID,
        in collectionRuns: [ExternalReferenceCollectionRun],
        trigger: ExternalReferenceCollectionTrigger? = nil
    ) -> (run: ExternalReferenceCollectionRun, log: ExternalReferenceSourceRunLog)? {
        collectionRuns
            .filter { run in trigger.map { run.trigger == $0 } ?? true }
            .compactMap { run -> (ExternalReferenceCollectionRun, ExternalReferenceSourceRunLog)? in
                guard let log = run.sourceLogs.first(where: { $0.sourceID == sourceID }) else { return nil }
                return (run, log)
            }
            .sorted { lhs, rhs in
                let left = lhs.1.endedAt ?? lhs.1.startedAt
                let right = rhs.1.endedAt ?? rhs.1.startedAt
                return left > right
            }
            .first
    }
}
