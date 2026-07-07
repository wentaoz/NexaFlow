import Foundation
import OSLog

enum ConfluenceError: LocalizedError {
    case missingToken
    case invalidBaseURL
    case invalidResponse
    case requestFailed(statusCode: Int, url: String, body: String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "没有找到 Confluence Token。请在设置里直接填写 Confluence Bearer Token。"
        case .invalidBaseURL:
            return "Confluence Base URL 无效。"
        case .invalidResponse:
            return "Confluence 返回数据无法解析。"
        case .requestFailed(let statusCode, _, _):
            if statusCode == 404 {
                return "Confluence 请求失败：HTTP 404。请检查 Base URL 是否只填写站点根地址、Root Page ID 是否存在，以及当前 token 是否有该页面权限。"
            }
            if statusCode == 401 || statusCode == 403 {
                return "Confluence 请求失败：HTTP \(statusCode)。Token 无效、过期，或没有页面权限。"
            }
            return "Confluence 请求失败：HTTP \(statusCode)。请检查网络、Base URL 和 Token 配置。"
        }
    }
}

struct ConfluenceService {
    private static let logger = Logger(subsystem: "NexaFlow", category: "Confluence")

    func testConnection(settings: ConfluenceSettings) async throws -> String {
        let token = try resolveToken(settings: settings)
        var identityText: String?
        var identityError: Error?
        do {
            let current = try await get(path: "/rest/api/user/current", settings: settings, token: token, params: [:], responseType: ConfluenceUser.self)
            identityText = current.displayName ?? current.username ?? "未知用户"
        } catch {
            identityError = error
        }

        if let rootID = rootPageIDs(from: settings).first {
            do {
                let page = try await fetchPage(id: rootID, settings: settings, token: token)
                if let identityText {
                    return "已连接 Confluence：\(identityText)；Root Page 可访问：\(page.title)"
                }
                return "已连接 Confluence：Root Page 可访问：\(page.title)"
            } catch {
                if let identityText {
                    return "Confluence Token 可用：\(identityText)，但 Root Page 测试失败：\(error.localizedDescription)"
                }
                throw error
            }
        }

        if let identityText {
            return "已连接 Confluence：\(identityText)"
        }
        throw identityError ?? ConfluenceError.invalidResponse
    }

    func fetchTree(settings: ConfluenceSettings) async throws -> [ConfluencePage] {
        let token = try resolveToken(settings: settings)
        let rootIDs = rootPageIDs(from: settings)

        guard !rootIDs.isEmpty else { return [] }

        var pagesByID: [String: ConfluencePage] = [:]
        var queue = rootIDs
        var seen = Set<String>()

        while !queue.isEmpty && pagesByID.count < settings.maxPages {
            let pageID = queue.removeFirst()
            guard seen.insert(pageID).inserted else { continue }

            let page = try await fetchPage(id: pageID, settings: settings, token: token)
            pagesByID[page.id] = page

            let children = try await fetchChildren(parentID: pageID, settings: settings, token: token)
            for child in children where !seen.contains(child.id) && pagesByID.count + queue.count < settings.maxPages {
                queue.append(child.id)
            }
        }

        return pagesByID.values.sorted {
            ($0.lastUpdated ?? $0.createdAt ?? .distantPast) > ($1.lastUpdated ?? $1.createdAt ?? .distantPast)
        }
    }

    private func rootPageIDs(from settings: ConfluenceSettings) -> [String] {
        settings.rootPageIDs
            .split { $0 == "," || $0 == "\n" || $0 == " " }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func importPagesJSON(from url: URL) throws -> [ConfluencePage] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let rows = try decoder.decode([LocalConfluencePageDTO].self, from: data)
        let importedAt = Date()
        return rows.map { $0.page(syncedAt: importedAt) }.sorted {
            ($0.lastUpdated ?? $0.createdAt ?? .distantPast) > ($1.lastUpdated ?? $1.createdAt ?? .distantPast)
        }
    }

    private func fetchPage(id: String, settings: ConfluenceSettings, token: String) async throws -> ConfluencePage {
        let dto = try await get(
            path: "/rest/api/content/\(id)",
            settings: settings,
            token: token,
            params: [
                "expand": "space,history,history.lastUpdated,history.createdBy,version,ancestors,metadata.labels,body.storage"
            ],
            responseType: ConfluenceContentDTO.self
        )
        return dto.page(baseURL: normalizedBaseURL(settings.baseURL))
    }

    private func fetchChildren(parentID: String, settings: ConfluenceSettings, token: String) async throws -> [ConfluenceContentDTO] {
        var start = 0
        let requestLimit = 100
        var results: [ConfluenceContentDTO] = []

        while true {
            let response = try await get(
                path: "/rest/api/content/\(parentID)/child/page",
                settings: settings,
                token: token,
                params: [
                    "limit": "\(requestLimit)",
                    "start": "\(start)",
                    "expand": "space,history,history.lastUpdated,version,ancestors,metadata.labels"
                ],
                responseType: ConfluenceContentListDTO.self
            )
            results.append(contentsOf: response.results)
            let returnedCount = response.size ?? response.results.count
            guard returnedCount > 0 else { break }
            let responseStart = response.start ?? start
            let responseLimit = response.limit ?? requestLimit

            if response.links?.next != nil {
                start = responseStart + returnedCount
                continue
            }
            if returnedCount >= responseLimit {
                start = responseStart + returnedCount
                continue
            }
            break
        }

        return results
    }

    private func get<T: Decodable>(
        path: String,
        settings: ConfluenceSettings,
        token: String,
        params: [String: String],
        responseType: T.Type
    ) async throws -> T {
        let baseURL = normalizedBaseURL(settings.baseURL)
        guard baseURL.hasPrefix("https://"),
              var components = URLComponents(string: baseURL + path),
              components.host != nil else {
            throw ConfluenceError.invalidBaseURL
        }
        if !params.isEmpty {
            components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw ConfluenceError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = NetworkTimeouts.longRequest
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("NexaFlow/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await NetworkRetry.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data.prefix(500), encoding: .utf8) ?? ""
            Self.logger.error("Request failed: status=\(http.statusCode, privacy: .public), url=\(url.absoluteString, privacy: .private), body=\(body, privacy: .private)")
            throw ConfluenceError.requestFailed(statusCode: http.statusCode, url: url.absoluteString, body: body)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ConfluenceError.invalidResponse
        }
    }

    private func resolveToken(settings: ConfluenceSettings) throws -> String {
        let explicit = settings.bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return explicit }

        if let stored = AppSecureStorage.password(
            service: settings.keychainService,
            account: settings.keychainAccount
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
           !stored.isEmpty {
            return stored
        }

        if let env = ProcessInfo.processInfo.environment["CONFLUENCE_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return env
        }

        throw ConfluenceError.missingToken
    }

    private func normalizedBaseURL(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
    }
}

private struct ConfluenceUser: Decodable {
    var username: String?
    var displayName: String?
}

private struct ConfluenceContentListDTO: Decodable {
    var results: [ConfluenceContentDTO]
    var size: Int?
    var limit: Int?
    var start: Int?
    var links: Links?

    enum CodingKeys: String, CodingKey {
        case results
        case size
        case limit
        case start
        case links = "_links"
    }

    struct Links: Decodable {
        var next: String?
    }
}

private struct ConfluenceContentDTO: Decodable {
    var id: String
    var title: String?
    var space: Space?
    var history: History?
    var version: Version?
    var ancestors: [Ancestor]?
    var metadata: Metadata?
    var body: Body?
    var links: Links?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case space
        case history
        case version
        case ancestors
        case metadata
        case body
        case links = "_links"
    }

    struct Space: Decodable {
        var key: String?
        var name: String?
    }

    struct History: Decodable {
        var createdDate: String?
        var lastUpdated: LastUpdated?
        var createdBy: Person?
    }

    struct LastUpdated: Decodable {
        var when: String?
        var by: Person?
    }

    struct Person: Decodable {
        var displayName: String?
        var username: String?
    }

    struct Version: Decodable {
        var number: Int?
    }

    struct Ancestor: Decodable {
        var id: String?
        var title: String?
    }

    struct Metadata: Decodable {
        var labels: LabelResults?
    }

    struct LabelResults: Decodable {
        var results: [Label]?
    }

    struct Label: Decodable {
        var name: String?
    }

    struct Body: Decodable {
        var storage: Storage?
    }

    struct Storage: Decodable {
        var value: String?
    }

    struct Links: Decodable {
        var webui: String?
    }

    func page(baseURL: String) -> ConfluencePage {
        let bodyHTML = body?.storage?.value ?? ""
        let text = HTMLTextExtractor.extract(bodyHTML)
        let labels = metadata?.labels?.results?.compactMap(\.name) ?? []
        let ancestorTitles = ancestors?.compactMap(\.title) ?? []
        let created = DateParsing.parse(history?.createdDate ?? "")
        let updated = DateParsing.parse(history?.lastUpdated?.when ?? "")
        let webui = links?.webui ?? ""
        return ConfluencePage(
            id: id,
            title: title ?? "Untitled",
            spaceKey: space?.key ?? "",
            spaceName: space?.name ?? "",
            createdAt: created,
            lastUpdated: updated,
            syncedAt: Date(),
            updatedBy: history?.lastUpdated?.by?.displayName ?? "",
            version: version?.number,
            url: webui.hasPrefix("http") ? webui : baseURL + webui,
            ancestors: ancestorTitles,
            labels: labels,
            excerpt: HTMLTextExtractor.compactExcerpt(title: title ?? "", text: text),
            text: text,
            charCount: text.count
        )
        .optimizedForStorage()
    }
}

private struct LocalConfluencePageDTO: Decodable {
    var id: String
    var title: String
    var spaceKey: String?
    var spaceName: String?
    var createdAt: String?
    var createdDate: String?
    var lastUpdated: String?
    var updatedBy: String?
    var version: Int?
    var url: String?
    var labels: [String]?
    var ancestors: [Ancestor]?
    var excerpt: String?
    var text: String?
    var charCount: Int?

    struct Ancestor: Decodable {
        var title: String?
    }

    func page(syncedAt: Date) -> ConfluencePage {
        let textValue = text ?? ""
        return ConfluencePage(
            id: id,
            title: title,
            spaceKey: spaceKey ?? "",
            spaceName: spaceName ?? "",
            createdAt: DateParsing.parse(createdAt ?? createdDate ?? ""),
            lastUpdated: DateParsing.parse(lastUpdated ?? ""),
            syncedAt: syncedAt,
            updatedBy: updatedBy ?? "",
            version: version,
            url: url ?? "",
            ancestors: ancestors?.compactMap(\.title) ?? [],
            labels: labels ?? [],
            excerpt: excerpt ?? HTMLTextExtractor.compactExcerpt(title: title, text: textValue),
            text: textValue,
            charCount: charCount ?? textValue.count
        )
        .optimizedForStorage()
    }
}

enum HTMLTextExtractor {
    static func extract(_ html: String) -> String {
        var value = html
        value = value.replacingOccurrences(of: "(?is)<(script|style).*?>.*?</\\1>", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        value = value.replacingOccurrences(of: "(?i)</(p|div|li|tr|h[1-6])>", with: "\n", options: .regularExpression)
        value = value.replacingOccurrences(of: "(?is)<[^>]+>", with: " ", options: .regularExpression)
        value = unescape(value)
        value = value.replacingOccurrences(of: "[ \\t\\r\\f\\u{00a0}]+", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func compactExcerpt(title: String, text: String, length: Int = 260) -> String {
        let combined = "\(title)\n\(text)"
        guard combined.count > length else { return combined.trimmingCharacters(in: .whitespacesAndNewlines) }
        return String(combined.prefix(length)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
