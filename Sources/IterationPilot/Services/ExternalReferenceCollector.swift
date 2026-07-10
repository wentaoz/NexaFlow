import Foundation
import OSLog

enum ExternalReferenceCollectorError: LocalizedError {
    case invalidURL(String)
    case missingAPIKey(String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            return "参照数据源 URL 无效：\(value)"
        case .missingAPIKey(let name):
            return "\(name) 缺少 API Key"
        case .requestFailed(let detail):
            return "参照数据源请求失败：\(detail)"
        }
    }
}

struct ExternalReferenceCollector {
    private struct RequestDescriptor {
        var query: String
        var endpoint: String
        var tavilyCountryInput: String?
        var tavilyCountrySent: String?
        var tavilyCountryDecision: String?
    }

    private struct SourceCollectionResult {
        var items: [ExternalReferenceItem]
        var sourceLog: ExternalReferenceSourceRunLog
    }

    private enum CollectionEvent {
        case source(SourceCollectionResult)
        case deadline
        case cancelled
    }

    struct CollectionResult {
        var items: [ExternalReferenceItem]
        var sourceLogs: [ExternalReferenceSourceRunLog]
        var timedOut: Bool
    }

    private static let maxConcurrentSources = 4
    private static let logger = Logger(subsystem: "NexaFlow", category: "ExternalReference")

    func collect(
        sources: [ExternalReferenceSource],
        searchSettings: SearchAPISettings,
        evidenceWindow: ExternalEvidenceWindow? = nil
    ) async throws -> [ExternalReferenceItem] {
        try await collectDetailed(
            sources: sources,
            searchSettings: searchSettings,
            evidenceWindow: evidenceWindow,
            collectionRunID: nil
        ).items
    }

    func collectDetailed(
        sources: [ExternalReferenceSource],
        searchSettings: SearchAPISettings,
        evidenceWindow: ExternalEvidenceWindow? = nil,
        collectionRunID: UUID?,
        deadline: Date? = nil
    ) async throws -> CollectionResult {
        let effectiveDeadline = deadline ?? Date().addingTimeInterval(NetworkTimeouts.referenceCollectionRunBudget)
        guard !sources.isEmpty else {
            return CollectionResult(items: [], sourceLogs: [], timedOut: false)
        }
        return await withTaskGroup(of: CollectionEvent.self, returning: CollectionResult.self) { group in
            var nextIndex = 0
            var activeSourceCount = 0
            var items: [ExternalReferenceItem] = []
            var sourceLogs: [ExternalReferenceSourceRunLog] = []
            var timedOut = false

            func enqueueNextSource() {
                guard nextIndex < sources.count else { return }
                if Date() >= effectiveDeadline { return }
                let source = sources[nextIndex]
                nextIndex += 1
                activeSourceCount += 1
                group.addTask {
                    .source(
                        await collectOneSource(
                            source,
                            searchSettings: searchSettings,
                            evidenceWindow: evidenceWindow,
                            collectionRunID: collectionRunID
                        )
                    )
                }
            }

            group.addTask {
                let remaining = max(0, effectiveDeadline.timeIntervalSinceNow)
                do {
                    try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                    return .deadline
                } catch {
                    return .cancelled
                }
            }

            for _ in 0..<min(Self.maxConcurrentSources, sources.count) {
                enqueueNextSource()
            }

            collectionLoop: while let event = await group.next() {
                switch event {
                case .source(let result):
                    activeSourceCount -= 1
                    items.append(contentsOf: result.items)
                    sourceLogs.append(result.sourceLog)
                    if Date() >= effectiveDeadline {
                        timedOut = true
                        group.cancelAll()
                        break collectionLoop
                    }
                    enqueueNextSource()
                    if activeSourceCount == 0, nextIndex >= sources.count {
                        group.cancelAll()
                        break collectionLoop
                    }
                case .deadline:
                    timedOut = true
                    group.cancelAll()
                    break collectionLoop
                case .cancelled:
                    break collectionLoop
                }
            }

            return CollectionResult(
                items: items.sorted { $0.displayDate > $1.displayDate },
                sourceLogs: sourceLogs.sorted { $0.startedAt < $1.startedAt },
                timedOut: timedOut
            )
        }
    }

    private func collectOneSource(
        _ source: ExternalReferenceSource,
        searchSettings: SearchAPISettings,
        evidenceWindow: ExternalEvidenceWindow?,
        collectionRunID: UUID?
    ) async -> SourceCollectionResult {
        let sourceLogID = UUID()
        let startedAt = Date()
        let descriptor = Self.requestDescriptor(for: source, searchSettings: searchSettings, evidenceWindow: evidenceWindow)
        do {
            let sourceItems: [ExternalReferenceItem]
            switch source.collectorType {
            case .manual:
                sourceItems = manualItem(from: source).map { [$0] } ?? []
            case .webPage:
                sourceItems = [try await webPageItem(from: source)]
            case .rss:
                sourceItems = try await rssItems(from: source)
            case .searchAPI:
                sourceItems = try await searchAPIItems(from: source, evidenceWindow: evidenceWindow)
            case .tavilySearch:
                sourceItems = try await tavilyItems(from: source, searchSettings: searchSettings, evidenceWindow: evidenceWindow)
            }
            let endedAt = Date()
            let taggedItems = sourceItems.map { item -> ExternalReferenceItem in
                var copy = item
                copy.collectionRunID = collectionRunID
                copy.sourceRunLogID = sourceLogID
                return copy
            }
            return SourceCollectionResult(
                items: taggedItems,
                sourceLog: Self.sourceRunLog(
                    id: sourceLogID,
                    source: source,
                    descriptor: descriptor,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    status: .succeeded,
                    httpStatusCode: source.collectorType == .manual ? nil : 200,
                    rawItemCount: taggedItems.count
                )
            )
        } catch {
            let endedAt = Date()
            return SourceCollectionResult(
                items: [],
                sourceLog: Self.sourceRunLog(
                    id: sourceLogID,
                    source: source,
                    descriptor: descriptor,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    status: .failed,
                    httpStatusCode: Self.httpStatusCode(from: error.localizedDescription),
                    rawItemCount: 0,
                    errorMessage: error.localizedDescription
                )
            )
        }
    }

    private func manualItem(from source: ExternalReferenceSource) -> ExternalReferenceItem? {
        let note = source.manualNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return nil }
        return ExternalReferenceItem(
            id: UUID(),
            sourceID: source.id,
            sourceName: source.name,
            domain: source.domain,
            title: source.name,
            url: source.url,
            summary: note,
            rawContent: note,
            collectedAt: Date(),
            publishedAt: nil,
            keywords: source.keywords
        )
    }

    private func webPageItem(from source: ExternalReferenceSource) async throws -> ExternalReferenceItem {
        guard let url = URL(string: source.url.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ExternalReferenceCollectorError.invalidURL(source.url)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = NetworkTimeouts.externalReferenceRequest
        let (data, response) = try await NetworkRetry.data(for: request)
        try validate(response: response, data: data, service: source.name)
        let html = String(data: data, encoding: .utf8) ?? ""
        let text = Self.htmlToText(html)
        return ExternalReferenceItem(
            id: UUID(),
            sourceID: source.id,
            sourceName: source.name,
            domain: source.domain,
            title: Self.title(fromHTML: html) ?? source.name,
            url: url.absoluteString,
            summary: text.clipped(to: 1200),
            rawContent: text.clipped(to: 20_000),
            collectedAt: Date(),
            publishedAt: Self.publishedDate(fromHTML: html),
            keywords: source.keywords
        )
    }

    private func rssItems(from source: ExternalReferenceSource) async throws -> [ExternalReferenceItem] {
        guard let url = URL(string: source.url.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ExternalReferenceCollectorError.invalidURL(source.url)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = NetworkTimeouts.externalReferenceRequest
        let (data, response) = try await NetworkRetry.data(for: request)
        try validate(response: response, data: data, service: source.name)
        let xml = String(data: data, encoding: .utf8) ?? ""
        let rawItems = Self.matches(pattern: "(?is)<item[^>]*>(.*?)</item>", in: xml)
        return rawItems.prefix(20).compactMap { item in
            let title = Self.firstTag("title", in: item) ?? source.name
            let link = Self.firstTag("link", in: item) ?? source.url
            let description = Self.htmlToText(Self.firstTag("description", in: item) ?? "")
            return ExternalReferenceItem(
                id: UUID(),
                sourceID: source.id,
                sourceName: source.name,
                domain: source.domain,
                title: title,
                url: link,
                summary: description.clipped(to: 1200),
                rawContent: description.clipped(to: 20_000),
                collectedAt: Date(),
                publishedAt: DateParsing.parse(Self.firstTag("pubDate", in: item) ?? ""),
                keywords: source.keywords
            )
        }
    }

    private func searchAPIItems(from source: ExternalReferenceSource, evidenceWindow: ExternalEvidenceWindow?) async throws -> [ExternalReferenceItem] {
        let template = source.queryTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "{competitor} {keywords}"
            : source.queryTemplate
        let renderedQuery = Self.renderQueryTemplate(template, source: source)
        let query = Self.appendEvidenceWindow(
            evidenceWindow,
            to: renderedQuery
        )
        let endpoint = source.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: endpoint) else {
            throw ExternalReferenceCollectorError.invalidURL(endpoint)
        }

        let url: URL
        if endpoint.contains("{query}") {
            guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let resolved = URL(string: endpoint.replacingOccurrences(of: "{query}", with: encodedQuery)) else {
                throw ExternalReferenceCollectorError.invalidURL(endpoint)
            }
            url = resolved
        } else {
            var queryItems = components.queryItems ?? []
            if !query.isEmpty, !queryItems.contains(where: { $0.name == "q" || $0.name == "query" }) {
                queryItems.append(URLQueryItem(name: "q", value: query))
            }
            components.queryItems = queryItems
            guard let resolved = components.url else {
                throw ExternalReferenceCollectorError.invalidURL(endpoint)
            }
            url = resolved
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = NetworkTimeouts.externalReferenceRequest
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey = source.apiKey.nilIfBlank {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await NetworkRetry.data(for: request)
        try validate(response: response, data: data, service: source.name)

        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ExternalReferenceCollectorError.requestFailed("\(source.name) 返回格式无法解析：\(error.localizedDescription)")
        }

        return Self.findCandidateDictionaries(in: json).compactMap { dictionary in
            let title = Self.string(at: source.searchTitlePath, in: dictionary)
                ?? Self.firstString(named: ["title", "name", "headline"], in: dictionary)
            let url = Self.string(at: source.searchURLPath, in: dictionary)
                ?? Self.firstString(named: ["url", "link", "href"], in: dictionary)
            let content = Self.firstString(named: ["raw_content", "rawContent", "snippet", "description", "summary", "content"], in: dictionary)
                ?? title

            guard let title = title?.nilIfBlank,
                  let url = url?.nilIfBlank else {
                return nil
            }
            let rawContent = content ?? title
            let publishedAt = Self.firstDate(named: ["publishedAt", "published", "published_date", "datePublished", "date_published", "pubDate", "date"], in: dictionary)
            let eventStartedAt = source.domain == .externalEvent
                ? Self.firstDate(named: ["eventStartedAt", "event_start", "eventStart", "start_date", "startDate", "event_date", "eventDate", "occurred_at", "occurredAt"], in: dictionary)
                : nil
            let eventEndedAt = source.domain == .externalEvent
                ? Self.firstDate(named: ["eventEndedAt", "event_end", "eventEnd", "end_date", "endDate"], in: dictionary)
                : nil
            return ExternalReferenceItem(
                id: UUID(),
                sourceID: source.id,
                sourceName: source.name,
                domain: source.domain,
                title: title,
                url: url,
                summary: rawContent.clipped(to: 1200),
                rawContent: rawContent.clipped(to: 20_000),
                collectedAt: Date(),
                publishedAt: publishedAt,
                eventStartedAt: eventStartedAt,
                eventEndedAt: eventEndedAt,
                keywords: source.keywords
            )
        }
    }

    private func tavilyItems(from source: ExternalReferenceSource, searchSettings: SearchAPISettings, evidenceWindow: ExternalEvidenceWindow?) async throws -> [ExternalReferenceItem] {
        let endpoint = searchSettings.tavilyEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "https://api.tavily.com/search"
            : searchSettings.tavilyEndpoint
        guard let url = URL(string: endpoint) else {
            throw ExternalReferenceCollectorError.invalidURL(endpoint)
        }
        let apiKey = searchSettings.tavilyAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw ExternalReferenceCollectorError.missingAPIKey("全局 Tavily Search")
        }

        let countryDecision = TavilyCountryResolver.decision(country: source.tavilyCountry, topic: source.tavilyTopic)
        let rawQuery = source.queryTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "\(source.name) \(source.keywords.joined(separator: " "))"
            : Self.renderQueryTemplate(source.queryTemplate, source: source)
        let queryWithCountryAliases = Self.appendCountryAliasesIfNeeded(countryDecision.queryAliases, to: rawQuery)
        let query = Self.compactTavilyQuery(Self.appendEvidenceWindow(evidenceWindow, to: queryWithCountryAliases))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = NetworkTimeouts.externalReferenceRequest
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(TavilyRequest(
            query: query,
            searchDepth: source.tavilySearchDepth,
            topic: source.tavilyTopic,
            timeRange: source.tavilyTimeRange,
            maxResults: source.tavilyMaxResults,
            includeRawContent: source.tavilyIncludeRawContent,
            includeDomains: source.tavilyIncludeDomains,
            excludeDomains: source.tavilyExcludeDomains,
            country: countryDecision.sentCountry
        ))

        let (data, response) = try await NetworkRetry.data(for: request)
        try validate(response: response, data: data, service: source.name)
        let decoded = try JSONDecoder().decode(TavilyResponse.self, from: data)

        return decoded.results.map { result in
            ExternalReferenceItem(
                id: UUID(),
                sourceID: source.id,
                sourceName: source.name,
                domain: source.domain,
                title: result.title,
                url: result.url,
                summary: (result.rawContent ?? result.content ?? "").clipped(to: 1200),
                rawContent: (result.rawContent ?? result.content ?? result.title).clipped(to: 20_000),
                collectedAt: Date(),
                publishedAt: result.publishedDate.flatMap(DateParsing.parse),
                keywords: source.keywords
            )
        }
    }

    private func validate(response: URLResponse, data: Data, service: String) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(400), encoding: .utf8) ?? ""
            Self.logger.error("Request failed: service=\(service, privacy: .public), status=\(http.statusCode, privacy: .public), body=\(body, privacy: .private)")
            throw ExternalReferenceCollectorError.requestFailed("\(service) HTTP \(http.statusCode)")
        }
    }

    private static func title(fromHTML html: String) -> String? {
        firstTag("title", in: html)
    }

    private static func publishedDate(fromHTML html: String) -> Date? {
        let patterns = [
            #"(?is)<meta[^>]+(?:property|name|itemprop)=["'](?:article:published_time|datePublished|date|pubdate|publishdate)["'][^>]+content=["']([^"']+)["']"#,
            #"(?is)<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name|itemprop)=["'](?:article:published_time|datePublished|date|pubdate|publishdate)["']"#,
            #"(?is)<time[^>]+datetime=["']([^"']+)["']"#
        ]
        for pattern in patterns {
            for value in matches(pattern: pattern, in: html) {
                if let date = DateParsing.parse(value) { return date }
            }
        }
        return nil
    }

    private static func firstTag(_ tag: String, in value: String) -> String? {
        matches(pattern: "(?is)<\(tag)[^>]*>(.*?)</\(tag)>", in: value).first.map(htmlToText)
    }

    private static func matches(pattern: String, in value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = value as NSString
        return regex.matches(in: value, range: NSRange(location: 0, length: ns.length)).compactMap {
            guard $0.numberOfRanges > 1 else { return nil }
            return ns.substring(with: $0.range(at: 1))
        }
    }

    private static func findCandidateDictionaries(in value: Any) -> [[String: Any]] {
        if let array = value as? [[String: Any]] {
            return array
        }
        if let dictionary = value as? [String: Any] {
            let likelyArrays = ["items", "results", "data", "webPages", "organic_results"]
            for key in likelyArrays {
                if let nested = dictionary[key] {
                    let found = findCandidateDictionaries(in: nested)
                    if !found.isEmpty { return found }
                }
            }
            return dictionary.values.flatMap { findCandidateDictionaries(in: $0) }
        }
        if let array = value as? [Any] {
            return array.flatMap { findCandidateDictionaries(in: $0) }
        }
        return []
    }

    private static func string(at path: String, in dictionary: [String: Any]) -> String? {
        let parts = path.split(separator: ".").map(String.init)
        guard !parts.isEmpty else { return nil }
        var current: Any? = dictionary
        for part in parts {
            if let dictionary = current as? [String: Any] {
                current = dictionary[part]
            } else {
                return nil
            }
        }
        return current as? String
    }

    private static func firstString(named keys: [String], in dictionary: [String: Any]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                return value
            }
        }
        for value in dictionary.values {
            if let nested = value as? [String: Any],
               let match = firstString(named: keys, in: nested) {
                return match
            }
        }
        return nil
    }

    private static func firstDate(named keys: [String], in dictionary: [String: Any]) -> Date? {
        for key in keys {
            if let value = dictionary[key] as? String,
               let date = DateParsing.parse(value) {
                return date
            }
            if let value = dictionary[key] as? Double {
                return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
            }
            if let value = dictionary[key] as? Int {
                let doubleValue = Double(value)
                return Date(timeIntervalSince1970: doubleValue > 10_000_000_000 ? doubleValue / 1000 : doubleValue)
            }
        }
        for value in dictionary.values {
            if let nested = value as? [String: Any],
               let match = firstDate(named: keys, in: nested) {
                return match
            }
        }
        return nil
    }

    private static func htmlToText(_ html: String) -> String {
        var value = html
        value = value.replacingOccurrences(of: "(?is)<(script|style).*?>.*?</\\1>", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        value = value.replacingOccurrences(of: "(?is)<[^>]+>", with: " ", options: .regularExpression)
        value = value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
        value = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func renderQueryTemplate(_ template: String, source: ExternalReferenceSource) -> String {
        let competitor = source.competitorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? source.name
            : source.competitorName
        let replacements: [String: String] = [
            "{competitor}": competitor,
            "{aliases}": source.competitorAliases.joined(separator: " "),
            "{keywords}": source.keywords.joined(separator: " "),
            "{market}": source.tavilyCountry,
            "{focus_market}": source.tavilyCountry,
            "{languages}": source.tavilyLanguageHints.joined(separator: " "),
            "{query_group}": source.tavilyQueryGroup,
            "{source_profile}": source.tavilySourceProfile
        ]
        return replacements.reduce(template) { partial, pair in
            partial.replacingOccurrences(of: pair.key, with: pair.value)
        }
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func requestDescriptor(
        for source: ExternalReferenceSource,
        searchSettings: SearchAPISettings,
        evidenceWindow: ExternalEvidenceWindow?
    ) -> RequestDescriptor {
        switch source.collectorType {
        case .manual:
            return RequestDescriptor(query: "", endpoint: "manual")
        case .webPage, .rss:
            return RequestDescriptor(query: "", endpoint: source.url)
        case .searchAPI:
            let template = source.queryTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "{competitor} {keywords}"
                : source.queryTemplate
            let query = appendEvidenceWindow(evidenceWindow, to: renderQueryTemplate(template, source: source))
            return RequestDescriptor(query: query, endpoint: source.url)
        case .tavilySearch:
            let countryDecision = TavilyCountryResolver.decision(country: source.tavilyCountry, topic: source.tavilyTopic)
            let rawQuery = source.queryTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "\(source.name) \(source.keywords.joined(separator: " "))"
                : renderQueryTemplate(source.queryTemplate, source: source)
            let queryWithCountryAliases = appendCountryAliasesIfNeeded(countryDecision.queryAliases, to: rawQuery)
            let query = compactTavilyQuery(appendEvidenceWindow(evidenceWindow, to: queryWithCountryAliases))
            let endpoint = searchSettings.tavilyEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "https://api.tavily.com/search"
                : searchSettings.tavilyEndpoint
            return RequestDescriptor(
                query: query,
                endpoint: endpoint,
                tavilyCountryInput: countryDecision.original.nilIfBlank,
                tavilyCountrySent: countryDecision.sentCountry,
                tavilyCountryDecision: countryDecision.reason
            )
        }
    }

    private static func sourceRunLog(
        id: UUID,
        source: ExternalReferenceSource,
        descriptor: RequestDescriptor,
        startedAt: Date,
        endedAt: Date,
        status: ExternalReferenceCollectionStatus,
        httpStatusCode: Int?,
        rawItemCount: Int,
        errorMessage: String = ""
    ) -> ExternalReferenceSourceRunLog {
        ExternalReferenceSourceRunLog(
            id: id,
            sourceID: source.id,
            sourceName: source.name,
            collectorType: source.collectorType,
            domain: source.domain,
            sourceProfile: source.tavilySourceProfile,
            queryGroup: source.tavilyQueryGroup,
            renderedQuery: descriptor.query,
            endpoint: descriptor.endpoint,
            tavilyTopic: source.tavilyTopic,
            tavilySearchDepth: source.tavilySearchDepth,
            tavilyTimeRange: source.tavilyTimeRange,
            tavilyMaxResults: source.tavilyMaxResults,
            tavilyCountryInput: descriptor.tavilyCountryInput,
            tavilyCountrySent: descriptor.tavilyCountrySent,
            tavilyCountryDecision: descriptor.tavilyCountryDecision,
            startedAt: startedAt,
            endedAt: endedAt,
            durationMs: Int(endedAt.timeIntervalSince(startedAt) * 1000),
            status: status,
            httpStatusCode: httpStatusCode,
            rawItemCount: rawItemCount,
            validItemCount: rawItemCount,
            errorMessage: errorMessage
        )
    }

    private static func httpStatusCode(from text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"HTTP\s+(\d{3})"#) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else {
            return nil
        }
        return Int(ns.substring(with: match.range(at: 1)))
    }

    private static func appendEvidenceWindow(_ window: ExternalEvidenceWindow?, to query: String) -> String {
        guard let suffix = window?.querySuffix.nilIfBlank else { return query }
        return "\(suffix) \(query)"
    }

    private static func appendCountryAliasesIfNeeded(_ aliases: [String], to query: String) -> String {
        let missingAliases = aliases.filter { alias in
            !query.localizedCaseInsensitiveContains(alias)
        }
        guard !missingAliases.isEmpty else { return query }
        return "\(missingAliases.prefix(4).joined(separator: " ")) \(query)"
    }

    private static func compactTavilyQuery(_ rawQuery: String) -> String {
        let normalized = rawQuery
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > 390 else { return normalized }

        var keptTokens: [String] = []
        var currentLength = 0
        for token in normalized.components(separatedBy: " ") {
            let nextLength = currentLength + token.count + (keptTokens.isEmpty ? 0 : 1)
            guard nextLength <= 390 else { break }
            keptTokens.append(token)
            currentLength = nextLength
        }
        let clipped = keptTokens.joined(separator: " ")
        return clipped.isEmpty ? String(normalized.prefix(390)) : clipped
    }
}

private struct TavilyRequest: Encodable {
    var query: String
    var searchDepth: String
    var topic: String
    var timeRange: String
    var maxResults: Int
    var includeRawContent: Bool
    var includeDomains: [String]
    var excludeDomains: [String]
    var country: String?

    enum CodingKeys: String, CodingKey {
        case query
        case searchDepth = "search_depth"
        case topic
        case timeRange = "time_range"
        case maxResults = "max_results"
        case includeRawContent = "include_raw_content"
        case includeDomains = "include_domains"
        case excludeDomains = "exclude_domains"
        case country
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(query, forKey: .query)
        try container.encode(searchDepth.isEmpty ? "basic" : searchDepth, forKey: .searchDepth)
        try container.encode(topic.isEmpty ? "news" : topic, forKey: .topic)
        if !timeRange.isEmpty && timeRange != "none" {
            try container.encode(timeRange, forKey: .timeRange)
        }
        try container.encode(min(max(maxResults, 1), 20), forKey: .maxResults)
        if includeRawContent {
            try container.encode("text", forKey: .includeRawContent)
        } else {
            try container.encode(false, forKey: .includeRawContent)
        }
        if !includeDomains.isEmpty {
            try container.encode(includeDomains, forKey: .includeDomains)
        }
        if !excludeDomains.isEmpty {
            try container.encode(excludeDomains, forKey: .excludeDomains)
        }
        if let country, !country.isEmpty {
            try container.encode(country, forKey: .country)
        }
    }
}

private struct TavilyResponse: Decodable {
    var results: [Result]

    struct Result: Decodable {
        var title: String
        var url: String
        var content: String?
        var rawContent: String?
        var publishedDate: String?

        enum CodingKeys: String, CodingKey {
            case title
            case url
            case content
            case rawContent = "raw_content"
            case publishedDate = "published_date"
        }
    }
}

private extension String {
    func clipped(to limit: Int) -> String {
        count > limit ? String(prefix(limit)) : self
    }
}
