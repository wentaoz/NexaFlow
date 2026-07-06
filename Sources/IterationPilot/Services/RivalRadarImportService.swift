import Foundation
import SQLite3

enum RivalRadarImportError: LocalizedError {
    case databaseMissing(String)
    case openFailed(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .databaseMissing(let path):
            return "未找到竞品雷达数据库：\(path)"
        case .openFailed(let detail):
            return "无法打开竞品雷达数据库：\(detail)"
        case .queryFailed(let detail):
            return "读取竞品雷达数据源失败：\(detail)"
        }
    }
}

struct RivalRadarImportResult {
    var sources: [ExternalReferenceSource]
    var tavilyAPIKey: String?
}

struct RivalRadarImportService {
    func load() throws -> RivalRadarImportResult {
        let databaseURL = defaultDatabaseURL()
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw RivalRadarImportError.databaseMissing(databaseURL.path)
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let detail = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw RivalRadarImportError.openFailed(detail)
        }
        defer { sqlite3_close(db) }

        let query = """
        SELECT c.name,
               c.aliases_json,
               s.name,
               s.type,
               s.url,
               s.keywords_json,
               s.search_endpoint,
               s.search_query_template,
               s.search_title_path,
               s.search_url_path,
               s.tavily_topic,
               s.tavily_search_depth,
               s.tavily_max_results,
               s.tavily_time_range,
               s.tavily_include_raw_content,
               s.tavily_include_domains_json,
               s.tavily_exclude_domains_json,
               s.tavily_country,
               s.tavily_language_hints_json,
               s.tavily_query_group,
               s.tavily_source_profile
        FROM sources s
        JOIN competitors c ON c.id = s.competitor_id
        WHERE c.is_enabled = 1 AND s.is_enabled = 1
        ORDER BY c.name ASC, s.name ASC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let detail = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw RivalRadarImportError.queryFailed(detail)
        }
        defer { sqlite3_finalize(statement) }

        var sources: [ExternalReferenceSource] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let competitorName = columnText(statement, 0)
            let aliases = decodeStringArray(columnText(statement, 1))
            let sourceName = columnText(statement, 2)
            let type = columnText(statement, 3)
            let url = columnText(statement, 4)
            let keywords = decodeStringArray(columnText(statement, 5))
            let searchEndpoint = columnText(statement, 6)
            let queryTemplate = columnText(statement, 7)
            let searchTitlePath = columnText(statement, 8)
            let searchURLPath = columnText(statement, 9)
            let topic = columnText(statement, 10)
            let searchDepth = columnText(statement, 11)
            let maxResults = Int(sqlite3_column_int(statement, 12))
            let timeRange = columnText(statement, 13)
            let includeRawContent = sqlite3_column_int(statement, 14) == 1
            let includeDomains = decodeStringArray(columnText(statement, 15))
            let excludeDomains = decodeStringArray(columnText(statement, 16))
            let country = columnText(statement, 17)
            let languageHints = decodeStringArray(columnText(statement, 18))
            let queryGroup = columnText(statement, 19)
            let sourceProfile = columnText(statement, 20)

            sources.append(ExternalReferenceSource(
                id: UUID(),
                name: sourceName,
                domain: .competitor,
                collectorType: collectorType(from: type),
                url: (type == "tavilySearch" || type == "searchAPI") ? searchEndpoint.nilIfBlank ?? url : url,
                keywordsText: keywords.joined(separator: "\n"),
                queryTemplate: queryTemplate,
                apiKey: "",
                searchTitlePath: searchTitlePath.nilIfBlank ?? "title",
                searchURLPath: searchURLPath.nilIfBlank ?? "url",
                competitorName: competitorName,
                competitorAliasesText: aliases.joined(separator: "\n"),
                tavilyTopic: topic.nilIfBlank ?? "news",
                tavilySearchDepth: searchDepth.nilIfBlank ?? "basic",
                tavilyTimeRange: timeRange.nilIfBlank ?? "week",
                tavilyMaxResults: maxResults == 0 ? 5 : maxResults,
                tavilyIncludeRawContent: includeRawContent,
                tavilyIncludeDomainsText: includeDomains.joined(separator: "\n"),
                tavilyExcludeDomainsText: excludeDomains.joined(separator: "\n"),
                tavilyCountry: country,
                tavilyLanguageHintsText: languageHints.joined(separator: "\n"),
                tavilyQueryGroup: queryGroup,
                tavilySourceProfile: sourceProfile,
                enabled: true,
                manualNote: "",
                lastFetchedAt: nil
            ))
        }

        return RivalRadarImportResult(
            sources: sources,
            tavilyAPIKey: UserDefaults(suiteName: "com.local.RivalRadar")?.string(forKey: "tavily.apiKey")?.nilIfBlank
        )
    }

    private func defaultDatabaseURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RivalRadar", isDirectory: true)
            .appendingPathComponent("rivalradar.sqlite")
    }

    private func collectorType(from rivalType: String) -> ExternalReferenceCollectorType {
        switch rivalType {
        case "rss":
            return .rss
        case "tavilySearch", "searchAPI":
            return rivalType == "searchAPI" ? .searchAPI : .tavilySearch
        case "searchapi":
            return .searchAPI
        case "tavilysearch":
            return .tavilySearch
        default:
            return .webPage
        }
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    private func decodeStringArray(_ value: String) -> [String] {
        guard let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
