import CryptoKit
import Foundation

enum TableauServiceError: LocalizedError {
    case invalidBaseURL
    case missingCredential
    case invalidResponse
    case httpError(Int, String)
    case missingSessionToken
    case missingSiteID
    case emptyViewData(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Tableau Base URL 无效。"
        case .missingCredential:
            return "请填写 Tableau Base URL、PAT Name 和 PAT Token。"
        case .invalidResponse:
            return "Tableau 返回内容无法解析。"
        case let .httpError(status, body):
            let readableBody = Self.readableHTTPBody(body)
            if status == 406 {
                let detail = readableBody.map { "原始响应：\($0)" } ?? "Tableau 未返回可读错误详情。"
                return "Tableau 请求失败：HTTP 406。Tableau Server 不接受当前请求的返回格式；系统已尝试兼容格式重试。请检查该视图是否允许下载数据，以及 Tableau Server/反向代理是否允许 REST API 返回 JSON 或 CSV。\(detail)"
            }
            if status == 502 {
                var message = "Tableau 请求失败：HTTP 502。Tableau Server 返回内部错误，通常是 Tableau 视图导出服务或反向代理临时失败，不是 NexaFlow 解析失败。请稍后重试，或在 Tableau 中确认该视图可以下载 Crosstab/CSV。"
                if let requestID = Self.tableauRequestID(from: body) {
                    message += "Request ID：\(requestID)。"
                } else if let readableBody {
                    message += "服务器摘要：\(readableBody)"
                }
                return message
            }
            if [429, 503, 504].contains(status) {
                let suffix = readableBody.map { "服务器摘要：\($0)" } ?? "Tableau 未返回可读错误详情。"
                return "Tableau 请求失败：HTTP \(status)。Tableau 服务暂时不可用或请求被限流，系统已自动重试一次但仍失败。请稍后重试。\(suffix)"
            }
            let suffix = readableBody.map { "服务器摘要：\($0)" } ?? "Tableau 未返回可读错误详情。"
            return "Tableau 请求失败：HTTP \(status)。\(suffix)"
        case .missingSessionToken:
            return "Tableau 登录成功但未返回 session token。"
        case .missingSiteID:
            return "Tableau 登录成功但未返回 Site ID。"
        case let .emptyViewData(name):
            return "Tableau 视图“\(name)”没有返回可导入数据。请检查视图下载权限或筛选条件。"
        }
    }

    private static func readableHTTPBody(_ body: String) -> String? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let requestID = tableauRequestID(from: trimmed)
        var text = decodeHTMLEntities(trimmed)
        if looksLikeHTML(text) {
            text = stripHTML(text)
        }
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty, let requestID {
            return "Tableau 返回 HTML 错误页。Request ID：\(requestID)"
        }
        guard !text.isEmpty else { return nil }

        if let requestID, !text.localizedCaseInsensitiveContains(requestID) {
            text += " Request ID：\(requestID)"
        }
        let maxLength = 500
        if text.count > maxLength {
            return String(text.prefix(maxLength)) + "..."
        }
        return text
    }

    private static func tableauRequestID(from body: String) -> String? {
        firstCapture(in: body, pattern: #"requestId=([^"'&<>\s]+)"#)
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }

    private static func looksLikeHTML(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("<html") ||
            normalized.contains("<body") ||
            normalized.contains("<iframe") ||
            normalized.contains("<!doctype")
    }

    private static func stripHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"(?is)<script[^>]*>.*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<style[^>]*>.*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

struct TableauService {
    func testConnection(source: TableauSource) async throws -> String {
        let session = try await signIn(source: source)
        try await signOut(source: source, session: session)
        return "连接成功：Site ID \(session.siteID)，REST API \(session.apiVersion)"
    }

    func fetchCatalog(source: TableauSource) async throws -> TableauCatalog {
        let session = try await signIn(source: source)
        defer {
            Task {
                try? await signOut(source: source, session: session)
            }
        }

        async let projects = fetchProjects(source: source, session: session)
        async let workbooks = fetchWorkbooks(source: source, session: session)
        let projectList = try await projects
        let workbookList = try await workbooks
        let views = try await fetchViews(source: source, session: session, workbooks: workbookList)

        let projectFilter = source.projectFilter.normalizedKey
        let workbookFilter = source.workbookFilter.normalizedKey
        let filteredWorkbooks = workbookList.filter { workbook in
            projectFilter.isEmpty || workbook.projectName.normalizedKey.contains(projectFilter)
        }.filter { workbook in
            workbookFilter.isEmpty || workbook.name.normalizedKey.contains(workbookFilter)
        }
        let allowedWorkbookIDs = Set(filteredWorkbooks.map(\.id))
        let filteredViews = views.filter { allowedWorkbookIDs.isEmpty || allowedWorkbookIDs.contains($0.workbookID) }

        return TableauCatalog(projects: projectList, workbooks: filteredWorkbooks, views: filteredViews)
    }

    func importViews(source: TableauSource, views: [TableauView]) async throws -> TableauImportResult {
        let session = try await signIn(source: source)
        defer {
            Task {
                try? await signOut(source: source, session: session)
            }
        }

        var reports: [ImportedReport] = []
        for view in views {
            let csv = try await fetchViewData(source: source, session: session, viewID: view.id)
            guard !csv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TableauServiceError.emptyViewData(view.name)
            }
            let metadata = ImportedReportSourceMetadata(
                sourceType: .tableau,
                baseURL: normalizedBaseURL(source.baseURL),
                siteContentURL: source.siteContentURL,
                projectID: view.projectID,
                projectName: view.projectName,
                workbookID: view.workbookID,
                workbookName: view.workbookName,
                viewID: view.id,
                viewName: view.name,
                importMode: "view-data-csv",
                importedAt: Date(),
                limitation: "当前读取的是 Tableau View Export / Crosstab 数据，可能受视图筛选器、聚合粒度、权限和下载范围限制，不等同底层完整数据源。"
            )
            var table = CSVParser.parse(csv)
            table.sheetName = view.name
            let report = try DataImportService.importTableauReport(
                fileName: "\(view.workbookName.nilIfBlank ?? "Tableau") / \(view.name)",
                sourceFileName: "Tableau View Export",
                sourceFingerprint: sourceFingerprint(source: source, view: view, csv: csv),
                table: table,
                metadata: metadata
            )
            reports.append(report)
        }

        return TableauImportResult(
            reports: reports,
            fieldDefinitions: DataImportService.rebuildFieldDefinitions(for: reports, preserving: []),
            importedViewCount: reports.count
        )
    }

    private struct Session {
        var token: String
        var siteID: String
        var apiVersion: String
    }

    private func signIn(source: TableauSource) async throws -> Session {
        guard !source.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !source.patName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !source.patToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TableauServiceError.missingCredential
        }
        var lastVersionError: Error?
        for apiVersion in candidateAPIVersions {
            do {
                return try await signIn(source: source, apiVersion: apiVersion)
            } catch {
                if isInvalidAPIVersion(error) {
                    lastVersionError = error
                    continue
                }
                throw error
            }
        }
        throw lastVersionError ?? TableauServiceError.invalidResponse
    }

    private func signIn(source: TableauSource, apiVersion: String) async throws -> Session {
        let url = try endpoint(source: source, path: "/api/\(apiVersion)/auth/signin")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "credentials": [
                "personalAccessTokenName": source.patName,
                "personalAccessTokenSecret": source.patToken,
                "site": [
                    "contentUrl": source.siteContentURL
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let object = try await requestJSON(request)
        guard let credentials = object["credentials"] as? [String: Any] else {
            throw TableauServiceError.invalidResponse
        }
        guard let token = credentials["token"] as? String, !token.isEmpty else {
            throw TableauServiceError.missingSessionToken
        }
        guard let site = credentials["site"] as? [String: Any],
              let siteID = site["id"] as? String,
              !siteID.isEmpty else {
            throw TableauServiceError.missingSiteID
        }
        return Session(token: token, siteID: siteID, apiVersion: apiVersion)
    }

    private func signOut(source: TableauSource, session: Session) async throws {
        let url = try endpoint(source: source, path: "/api/\(session.apiVersion)/auth/signout")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(session.token, forHTTPHeaderField: "X-Tableau-Auth")
        _ = try await URLSession.shared.data(for: request)
    }

    private func fetchProjects(source: TableauSource, session: Session) async throws -> [TableauProject] {
        let url = try endpoint(source: source, path: "/api/\(session.apiVersion)/sites/\(session.siteID)/projects", queryItems: [
            URLQueryItem(name: "pageSize", value: "1000")
        ])
        let object = try await authenticatedJSON(url: url, token: session.token)
        let values = nestedArray(object, path: ["projects", "project"])
        return values.compactMap { value in
            guard let id = value["id"] as? String else { return nil }
            return TableauProject(id: id, name: value["name"] as? String ?? "未命名 Project")
        }
    }

    private func fetchWorkbooks(source: TableauSource, session: Session) async throws -> [TableauWorkbook] {
        let url = try endpoint(source: source, path: "/api/\(session.apiVersion)/sites/\(session.siteID)/workbooks", queryItems: [
            URLQueryItem(name: "pageSize", value: "1000")
        ])
        let object = try await authenticatedJSON(url: url, token: session.token)
        let values = nestedArray(object, path: ["workbooks", "workbook"])
        return values.compactMap { value in
            guard let id = value["id"] as? String else { return nil }
            let project = value["project"] as? [String: Any]
            return TableauWorkbook(
                id: id,
                name: value["name"] as? String ?? "未命名 Workbook",
                projectID: project?["id"] as? String ?? "",
                projectName: project?["name"] as? String ?? ""
            )
        }
    }

    private func fetchViews(source: TableauSource, session: Session, workbooks: [TableauWorkbook]) async throws -> [TableauView] {
        let workbookByID = Dictionary(uniqueKeysWithValues: workbooks.map { ($0.id, $0) })
        let url = try endpoint(source: source, path: "/api/\(session.apiVersion)/sites/\(session.siteID)/views", queryItems: [
            URLQueryItem(name: "pageSize", value: "1000")
        ])
        let object = try await authenticatedJSON(url: url, token: session.token)
        let values = nestedArray(object, path: ["views", "view"])
        return values.compactMap { value in
            guard let id = value["id"] as? String else { return nil }
            let workbookObject = value["workbook"] as? [String: Any]
            let workbookID = workbookObject?["id"] as? String ?? ""
            let workbook = workbookByID[workbookID]
            let projectObject = value["project"] as? [String: Any]
            return TableauView(
                id: id,
                name: value["name"] as? String ?? "未命名 View",
                workbookID: workbookID,
                workbookName: workbookObject?["name"] as? String ?? workbook?.name ?? "",
                projectID: projectObject?["id"] as? String ?? workbook?.projectID ?? "",
                projectName: projectObject?["name"] as? String ?? workbook?.projectName ?? ""
            )
        }
    }

    private func fetchViewData(source: TableauSource, session: Session, viewID: String) async throws -> String {
        let url = try endpoint(source: source, path: "/api/\(session.apiVersion)/sites/\(session.siteID)/views/\(viewID)/data", queryItems: [
            URLQueryItem(name: "maxAge", value: "1")
        ])
        var request = URLRequest(url: url)
        request.setValue(session.token, forHTTPHeaderField: "X-Tableau-Auth")
        request.setValue("text/csv", forHTTPHeaderField: "Accept")
        let (data, _) = try await requestData(request)
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    private func authenticatedJSON(url: URL, token: String) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "X-Tableau-Auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await requestJSON(request)
    }

    private func requestJSON(_ request: URLRequest) async throws -> [String: Any] {
        let (data, _) = try await requestData(request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TableauServiceError.invalidResponse
        }
        return object
    }

    private func requestData(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await requestDataOnce(request)
        } catch {
            if isTransientHTTPError(error) {
                try await Task.sleep(nanoseconds: 700_000_000)
                do {
                    return try await requestDataOnce(request)
                } catch {
                    return try await requestDataWithAcceptFallback(request, originalError: error)
                }
            }
            return try await requestDataWithAcceptFallback(request, originalError: error)
        }
    }

    private func requestDataWithAcceptFallback(_ request: URLRequest, originalError: Error) async throws -> (Data, URLResponse) {
        guard isNotAcceptable(originalError),
              request.value(forHTTPHeaderField: "Accept") != "*/*" else {
            throw originalError
        }
        var fallback = request
        fallback.setValue("*/*", forHTTPHeaderField: "Accept")
        do {
            return try await requestDataOnce(fallback)
        } catch {
            guard isNotAcceptable(error) else {
                throw error
            }
            var noAcceptFallback = request
            noAcceptFallback.setValue(nil, forHTTPHeaderField: "Accept")
            return try await requestDataOnce(noAcceptFallback)
        }
    }

    private func requestDataOnce(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return (data, response)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TableauServiceError.httpError(http.statusCode, body)
        }
    }

    private func endpoint(source: TableauSource, path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(string: normalizedBaseURL(source.baseURL) + path) else {
            throw TableauServiceError.invalidBaseURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw TableauServiceError.invalidBaseURL
        }
        return url
    }

    private func nestedArray(_ object: [String: Any], path: [String]) -> [[String: Any]] {
        var current: Any = object
        for key in path {
            guard let dictionary = current as? [String: Any],
                  let value = dictionary[key] else {
                return []
            }
            current = value
        }
        if let array = current as? [[String: Any]] {
            return array
        }
        if let single = current as? [String: Any] {
            return [single]
        }
        return []
    }

    private func normalizedBaseURL(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func sourceFingerprint(source: TableauSource, view: TableauView, csv: String) -> String {
        let input = [
            normalizedBaseURL(source.baseURL),
            source.siteContentURL,
            view.id,
            csv
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private var candidateAPIVersions: [String] {
        let v3 = stride(from: 35, through: 0, by: -1).map { "3.\($0)" }
        let v2 = stride(from: 8, through: 0, by: -1).map { "2.\($0)" }
        return v3 + v2
    }

    private func isInvalidAPIVersion(_ error: Error) -> Bool {
        guard case let TableauServiceError.httpError(status, body) = error else {
            return false
        }
        let normalized = body.lowercased()
        return status == 404 && (
            normalized.contains("api version") ||
            normalized.contains("404001") ||
            normalized.contains("not a valid") ||
            normalized.contains("不是有效")
        )
    }

    private func isNotAcceptable(_ error: Error) -> Bool {
        guard case let TableauServiceError.httpError(status, _) = error else {
            return false
        }
        return status == 406
    }

    private func isTransientHTTPError(_ error: Error) -> Bool {
        guard case let TableauServiceError.httpError(status, _) = error else {
            return false
        }
        return [429, 502, 503, 504].contains(status)
    }
}
