import Foundation
import OSLog

enum JiraServiceError: LocalizedError {
    case invalidBaseURL
    case missingProjectKey
    case missingToken
    case missingUsername
    case requestFailed(statusCode: Int, body: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Jira Base URL 无效。"
        case .missingProjectKey:
            return "请填写 Jira Project Key。"
        case .missingToken:
            return "请填写 Jira Token。"
        case .missingUsername:
            return "Jira Cloud API Token 模式需要填写用户名或邮箱。"
        case let .requestFailed(statusCode, _):
            if statusCode == 401 || statusCode == 403 {
                return "Jira 请求失败：HTTP \(statusCode)。Token 无效、过期，或没有项目权限。"
            }
            return "Jira 请求失败：HTTP \(statusCode)。请检查网络、Base URL、Project Key、JQL 和 Token 配置。"
        case .invalidResponse:
            return "Jira 返回数据无法解析。"
        }
    }
}

struct JiraService {
    private static let logger = Logger(subsystem: "NexaFlow", category: "Jira")

    func testConnection(source: JiraProjectSource) async throws -> String {
        var testSource = source
        testSource.maxIssues = 1
        let page = try await fetchSearchPage(source: testSource, startAt: 0, maxResults: 1)
        return "Jira 连接成功：项目 \(source.projectKey)，可读取 \(page.total ?? page.issues.count) 条 Issue。"
    }

    func fetchProjectEvidence(source: JiraProjectSource) async throws -> [JiraProjectEvidence] {
        let maxIssues = max(1, min(source.maxIssues, 500))
        var startAt = 0
        var results: [JiraProjectEvidence] = []

        while results.count < maxIssues {
            let pageSize = min(50, maxIssues - results.count)
            let page = try await fetchSearchPage(source: source, startAt: startAt, maxResults: pageSize)
            let mapped = page.issues.map { $0.evidence(source: source) }
            results.append(contentsOf: mapped)

            guard !page.issues.isEmpty else { break }
            startAt += page.issues.count
            if let total = page.total, startAt >= total { break }
        }

        return results
    }

    private func fetchSearchPage(source: JiraProjectSource, startAt: Int, maxResults: Int) async throws -> JiraSearchResponse {
        let trimmedBaseURL = source.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: trimmedBaseURL), !trimmedBaseURL.isEmpty else {
            throw JiraServiceError.invalidBaseURL
        }

        let projectKey = source.projectKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectKey.isEmpty else { throw JiraServiceError.missingProjectKey }
        let token = source.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw JiraServiceError.missingToken }
        if source.authMode == .cloudAPIToken,
           source.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw JiraServiceError.missingUsername
        }

        let endpoint = baseURL
            .appendingPathComponent("rest")
            .appendingPathComponent("api")
            .appendingPathComponent("2")
            .appendingPathComponent("search")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = NetworkTimeouts.longRequest
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch source.authMode {
        case .cloudAPIToken:
            let username = source.username.trimmingCharacters(in: .whitespacesAndNewlines)
            let credentials = "\(username):\(token)"
            let encoded = Data(credentials.utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        case .dataCenterBearer:
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body = JiraSearchRequest(
            jql: normalizedJQL(source: source),
            startAt: startAt,
            maxResults: maxResults,
            fields: [
                "summary",
                "issuetype",
                "status",
                "assignee",
                "priority",
                "created",
                "updated",
                "resolutiondate",
                "fixVersions",
                "labels",
                "components",
                "comment",
                "customfield_10020"
            ],
            expand: ["changelog"]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw JiraServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(600), encoding: .utf8) ?? ""
            let sanitizedBody = Self.sanitizedErrorBody(body, source: source)
            Self.logger.error("Request failed: status=\(http.statusCode, privacy: .public), url=\(endpoint.absoluteString, privacy: .private), body=\(sanitizedBody, privacy: .private)")
            throw JiraServiceError.requestFailed(statusCode: http.statusCode, body: "")
        }

        do {
            return try JSONDecoder().decode(JiraSearchResponse.self, from: data)
        } catch {
            throw JiraServiceError.invalidResponse
        }
    }

    private static func sanitizedErrorBody(_ body: String, source: JiraProjectSource) -> String {
        var description = body
        let username = source.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = source.token.trimmingCharacters(in: .whitespacesAndNewlines)
        var secrets: [(secret: String, replacement: String)] = []
        if !username.isEmpty, !token.isEmpty {
            secrets.append((Data("\(username):\(token)".utf8).base64EncodedString(), "[redacted]"))
        }
        if !token.isEmpty {
            secrets.append((token, "[token]"))
        }
        if !username.isEmpty {
            secrets.append((username, "[username]"))
        }
        for (secret, replacement) in secrets where !secret.isEmpty {
            description = description.replacingOccurrences(of: secret, with: replacement)
        }
        return description
    }

    private func normalizedJQL(source: JiraProjectSource) -> String {
        let custom = source.jql.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        let projectKey = source.projectKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return "project = \(projectKey) AND updated >= -90d ORDER BY updated DESC"
    }
}

private struct JiraSearchRequest: Encodable {
    var jql: String
    var startAt: Int
    var maxResults: Int
    var fields: [String]
    var expand: [String]
}

private struct JiraSearchResponse: Decodable {
    var issues: [JiraIssueDTO]
    var total: Int?
}

private struct JiraIssueDTO: Decodable {
    var key: String
    var fields: JiraIssueFields
    var changelog: JiraChangelogDTO?

    func evidence(source: JiraProjectSource) -> JiraProjectEvidence {
        let baseURL = source.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let issueURL = "\(baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/browse/\(key)"
        let statusChanges = statusChangeItems
        let changelogSummary = statusChanges
            .prefix(5)
            .map { change in
                "\(DateFormatting.shortDate.string(from: change.date))：\(change.from?.nilIfBlank ?? "未知") → \(change.to?.nilIfBlank ?? "未知")"
            }
            .joined(separator: "；")
        let commentSummary = fields.comment?.comments
            .suffix(3)
            .map { comment in
                let author = comment.author?.displayName?.nilIfBlank ?? "未知用户"
                let date = comment.updated.flatMap(JiraDateParser.parse).map { DateFormatting.shortDate.string(from: $0) } ?? "未知时间"
                return "\(date) \(author)：\(comment.body?.textContent.prefix(160) ?? "")"
            }
            .joined(separator: "；") ?? ""

        return JiraProjectEvidence(
            sourceID: source.id,
            businessSpaceID: source.businessSpaceID,
            issueKey: key,
            issueURL: issueURL,
            projectKey: source.projectKey,
            issueType: fields.issuetype?.name ?? "Issue",
            summary: fields.summary ?? "",
            status: fields.status?.name ?? "",
            assignee: fields.assignee?.displayName ?? "",
            priority: fields.priority?.name ?? "",
            createdAt: fields.created.flatMap(JiraDateParser.parse),
            updatedAt: fields.updated.flatMap(JiraDateParser.parse),
            resolvedAt: fields.resolutiondate.flatMap(JiraDateParser.parse),
            statusChangedAt: statusChanges.first?.date,
            fixVersions: fields.fixVersions?.map(\.name) ?? [],
            sprintNames: fields.sprintNames,
            labels: fields.labels ?? [],
            components: fields.components?.map(\.name) ?? [],
            commentSummary: commentSummary,
            changelogSummary: changelogSummary,
            syncedAt: Date()
        )
    }

    private var statusChangeItems: [(date: Date, from: String?, to: String?)] {
        let changes = (changelog?.histories ?? []).flatMap { history -> [(date: Date, from: String?, to: String?)] in
            guard let date = JiraDateParser.parse(history.created) else { return [] }
            return history.items
                .filter { ($0.field ?? "").lowercased() == "status" }
                .map { (date: date, from: $0.fromString, to: $0.toString) }
        }
        return changes.sorted { $0.date > $1.date }
    }
}

private struct JiraIssueFields: Decodable {
    var summary: String?
    var issuetype: JiraNamedDTO?
    var status: JiraNamedDTO?
    var assignee: JiraUserDTO?
    var priority: JiraNamedDTO?
    var created: String?
    var updated: String?
    var resolutiondate: String?
    var fixVersions: [JiraNamedDTO]?
    var labels: [String]?
    var components: [JiraNamedDTO]?
    var comment: JiraCommentsDTO?
    var customfield10020: JSONValue?

    enum CodingKeys: String, CodingKey {
        case summary
        case issuetype
        case status
        case assignee
        case priority
        case created
        case updated
        case resolutiondate
        case fixVersions
        case labels
        case components
        case comment
        case customfield10020 = "customfield_10020"
    }

    var sprintNames: [String] {
        guard let customfield10020 else { return [] }
        return customfield10020.sprintNames.uniqued()
    }
}

private struct JiraNamedDTO: Decodable {
    var name: String
}

private struct JiraUserDTO: Decodable {
    var displayName: String?
    var emailAddress: String?
}

private struct JiraCommentsDTO: Decodable {
    var comments: [JiraCommentDTO]
}

private struct JiraCommentDTO: Decodable {
    var author: JiraUserDTO?
    var body: JSONValue?
    var updated: String?
}

private struct JiraChangelogDTO: Decodable {
    var histories: [JiraHistoryDTO]
}

private struct JiraHistoryDTO: Decodable {
    var created: String
    var items: [JiraHistoryItemDTO]
}

private struct JiraHistoryItemDTO: Decodable {
    var field: String?
    var fromString: String?
    var toString: String?
}

private enum JSONValue: Decodable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .null
        }
    }

    var textContent: String {
        switch self {
        case let .string(value):
            return value
        case let .number(value):
            return String(value)
        case let .bool(value):
            return String(value)
        case let .array(values):
            return values.map(\.textContent).filter { !$0.isEmpty }.joined(separator: " ")
        case let .object(values):
            if case let .string(text)? = values["text"] {
                return text
            }
            return values.values.map(\.textContent).filter { !$0.isEmpty }.joined(separator: " ")
        case .null:
            return ""
        }
    }

    var sprintNames: [String] {
        switch self {
        case let .array(values):
            return values.flatMap(\.sprintNames)
        case let .object(values):
            if case let .string(name)? = values["name"] {
                return [name]
            }
            return values.values.flatMap(\.sprintNames)
        case let .string(value):
            if let name = extractSprintName(from: value) {
                return [name]
            }
            return []
        default:
            return []
        }
    }

    private func extractSprintName(from rawValue: String) -> String? {
        guard let range = rawValue.range(of: "name=") else { return nil }
        let tail = rawValue[range.upperBound...]
        let end = tail.firstIndex(of: ",") ?? tail.endIndex
        return String(tail[..<end]).trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }
}

private enum JiraDateParser {
    private static let jiraDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func parse(_ value: String) -> Date? {
        jiraDateFormatter.date(from: value)
            ?? isoFormatter.date(from: value)
            ?? ISO8601DateFormatter().date(from: value)
    }
}
