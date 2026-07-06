import Foundation

enum DingTalkDocumentServiceError: LocalizedError {
    case missingClientID
    case missingClientSecret
    case missingOperatorID
    case missingFolder
    case missingSpaceID(folder: String)
    case invalidSpaceID
    case invalidURL
    case invalidTokenResponse
    case requestFailed(statusCode: Int, body: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "请填写钉钉 Client ID。"
        case .missingClientSecret:
            return "请填写钉钉 Client Secret。"
        case .missingOperatorID:
            return "请填写钉钉操作人 User ID（operatorId）。这是有文档访问权限的钉钉用户 UserID，不是 AgentId。"
        case .missingFolder:
            return "请至少填写一个钉钉文件夹链接或文件夹 ID。"
        case let .missingSpaceID(folder):
            return "文件夹缺少 Space ID：\(folder)。请粘贴完整文件夹链接，或填写默认 Space ID；普通 alidocs 文件夹链接会自动反查 Space ID。"
        case .invalidSpaceID:
            return "钉钉 Space ID 无效。"
        case .invalidURL:
            return "钉钉请求地址无法生成。"
        case .invalidTokenResponse:
            return "钉钉 access token 返回无法解析。"
        case let .requestFailed(statusCode, body):
            return "钉钉请求失败：HTTP \(statusCode)。\(body)"
        case .invalidResponse:
            return "钉钉返回数据无法解析。"
        }
    }
}

struct DingTalkDocumentFetchResult {
    var items: [DingTalkDocumentItem]
    var folderCount: Int
    var skippedCount: Int
    var failures: [String]
}

struct DingTalkDocumentService {
    func testConnection(source: DingTalkDocumentSource) async throws -> String {
        _ = try await accessToken(source: source)
        let folderCount = source.parsedFolderInputs.count
        let scope = folderCount > 0 ? "已配置 \(folderCount) 个文件夹" : "尚未配置文件夹"
        let operatorStatus = source.normalizedOperatorID == nil ? "未填写 operatorId，同步文件夹会失败" : "已配置 operatorId"
        return "钉钉连接成功：\(source.displayName)，\(scope)，\(operatorStatus)。"
    }

    func fetchDocuments(source: DingTalkDocumentSource) async throws -> DingTalkDocumentFetchResult {
        let token = try await accessToken(source: source)
        guard let operatorID = source.normalizedOperatorID else {
            throw DingTalkDocumentServiceError.missingOperatorID
        }
        let folders = source.parsedFolderInputs
        guard !folders.isEmpty else { throw DingTalkDocumentServiceError.missingFolder }

        let maxDocuments = max(1, min(source.maxDocuments, 500))
        var items: [DingTalkDocumentItem] = []
        var failures: [String] = []
        var skipped = 0

        for folder in folders where items.count < maxDocuments {
            do {
                let locator = try await folderLocator(from: folder, source: source, token: token, operatorID: operatorID)
                var nextToken: String?
                repeat {
                    let page = try await fetchDentriesPage(
                        token: token,
                        operatorID: operatorID,
                        spaceID: locator.spaceID,
                        parentID: locator.parentID,
                        nextToken: nextToken
                    )
                    for raw in page.items {
                        guard items.count < maxDocuments else { break }
                        guard let item = documentItem(
                            from: raw,
                            source: source,
                            folderInput: folder,
                            fallbackSpaceID: locator.spaceID,
                            fallbackParentID: locator.parentID
                        ) else {
                            skipped += 1
                            continue
                        }
                        guard passesFilters(item, source: source) else {
                            skipped += 1
                            continue
                        }
                        items.append(item)
                    }
                    nextToken = page.nextToken
                } while nextToken?.isEmpty == false && items.count < maxDocuments
            } catch {
                failures.append("\(folder)：\(sanitize(error.localizedDescription, source: source))")
            }
        }

        return DingTalkDocumentFetchResult(
            items: items,
            folderCount: folders.count,
            skippedCount: skipped,
            failures: failures
        )
    }

    private func accessToken(source: DingTalkDocumentSource) async throws -> String {
        let clientID = source.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = source.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else { throw DingTalkDocumentServiceError.missingClientID }
        guard !clientSecret.isEmpty else { throw DingTalkDocumentServiceError.missingClientSecret }

        guard let url = URL(string: "https://api.dingtalk.com/v1.0/oauth2/accessToken") else {
            throw DingTalkDocumentServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = NetworkTimeouts.longRequest
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "appKey": clientID,
            "appSecret": clientSecret
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DingTalkDocumentServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DingTalkDocumentServiceError.requestFailed(
                statusCode: http.statusCode,
                body: sanitizedBody(data, source: source)
            )
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DingTalkDocumentServiceError.invalidTokenResponse
        }
        let token = stringValue(json["accessToken"])
            ?? stringValue(json["access_token"])
            ?? stringValue((json["result"] as? [String: Any])?["accessToken"])
        guard let token, !token.isEmpty else {
            throw DingTalkDocumentServiceError.invalidTokenResponse
        }
        return token
    }

    private func fetchDentriesPage(
        token: String,
        operatorID: String,
        spaceID: String,
        parentID: String,
        nextToken: String?
    ) async throws -> (items: [[String: Any]], nextToken: String?) {
        let endpoint = try makeDingTalkDentriesURL(spaceID: spaceID)
        let legacyEndpoint = try makeDingTalkDentriesURL(spaceID: spaceID, suffix: "/listAll")
        let params: [String: Any] = [
            "operatorId": operatorID,
            "parentId": parentID,
            "maxResults": 50,
            "nextToken": nextToken ?? ""
        ]

        do {
            return try await requestDentries(endpoint: endpoint, token: token, method: "GET", params: params)
        } catch {
            do {
                return try await requestDentries(endpoint: endpoint, token: token, method: "POST", params: params)
            } catch {
                do {
                    return try await requestDentries(endpoint: legacyEndpoint, token: token, method: "GET", params: params)
                } catch {
                    return try await requestDentries(endpoint: legacyEndpoint, token: token, method: "POST", params: params)
                }
            }
        }
    }

    private func makeDingTalkDentriesURL(spaceID: String, suffix: String = "") throws -> URL {
        let trimmedSpaceID = spaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        var allowedPathSegmentCharacters = CharacterSet.urlPathAllowed
        allowedPathSegmentCharacters.remove(charactersIn: "/%")
        guard !trimmedSpaceID.isEmpty,
              let encodedSpaceID = trimmedSpaceID.addingPercentEncoding(withAllowedCharacters: allowedPathSegmentCharacters) else {
            throw DingTalkDocumentServiceError.invalidSpaceID
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.dingtalk.com"
        components.percentEncodedPath = "/v1.0/storage/spaces/\(encodedSpaceID)/dentries\(suffix)"
        guard let url = components.url else {
            throw DingTalkDocumentServiceError.invalidURL
        }
        return url
    }

    private func requestDentries(
        endpoint: URL,
        token: String,
        method: String,
        params: [String: Any]
    ) async throws -> (items: [[String: Any]], nextToken: String?) {
        var url = endpoint
        var request: URLRequest
        if method == "GET" {
            var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
            components?.queryItems = params.compactMap { key, value in
                guard let string = stringValue(value), !string.isEmpty else { return nil }
                return URLQueryItem(name: key, value: string)
            }
            url = components?.url ?? endpoint
            request = URLRequest(url: url)
        } else {
            request = URLRequest(url: endpoint)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: params)
        }
        request.httpMethod = method
        request.timeoutInterval = NetworkTimeouts.longRequest
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "x-acs-dingtalk-access-token")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DingTalkDocumentServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DingTalkDocumentServiceError.requestFailed(
                statusCode: http.statusCode,
                body: sanitizedBody(data, token: token)
            )
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DingTalkDocumentServiceError.invalidResponse
        }
        let items = extractArray(from: json)
        let nextToken = stringValue(json["nextToken"])
            ?? stringValue((json["result"] as? [String: Any])?["nextToken"])
            ?? stringValue((json["data"] as? [String: Any])?["nextToken"])
        return (items, nextToken)
    }

    private func folderLocator(
        from input: String,
        source: DingTalkDocumentSource,
        token: String,
        operatorID: String
    ) async throws -> (spaceID: String, parentID: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultSpaceID = source.defaultSpaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedURL = URL(string: trimmed)
        let queryItems = parsedURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        let queryValue: (String) -> String? = { name in
            queryItems.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
        let spaceID = queryValue("spaceId")
            ?? queryValue("space_id")
            ?? queryValue("space")
            ?? valueAfterLabel(in: trimmed, labels: ["spaceId", "space_id", "space"])
            ?? defaultSpaceID.nilIfBlank
        let explicitParentID = queryValue("folderId")
            ?? queryValue("folder_id")
            ?? queryValue("parentId")
            ?? queryValue("parent_id")
            ?? queryValue("dentryId")
            ?? valueAfterLabel(in: trimmed, labels: ["folderId", "folder_id", "parentId", "parent_id", "dentryId"])
        let folderUUID = folderUUIDCandidate(from: trimmed)
        let parentID = explicitParentID
            ?? folderUUID
            ?? rawIDCandidate(from: trimmed)

        if let folderUUID, explicitParentID == nil {
            return try await resolveDentryIDByUUID(token: token, operatorID: operatorID, dentryUUID: folderUUID)
        }

        if let spaceID, !spaceID.isEmpty {
            return (spaceID, parentID)
        }

        if let dentryUUID = rawIDCandidate(from: trimmed).nilIfBlank {
            let resolved = try await resolveDentryIDByUUID(token: token, operatorID: operatorID, dentryUUID: dentryUUID)
            return resolved
        }

        throw DingTalkDocumentServiceError.missingSpaceID(folder: trimmed)
    }

    private func resolveDentryIDByUUID(token: String, operatorID: String, dentryUUID: String) async throws -> (spaceID: String, parentID: String) {
        let encodedUUID = dentryUUID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? dentryUUID
        guard let endpoint = URL(string: "https://api.dingtalk.com/v2.0/doc/dentries/\(encodedUUID)/queryDentryId"),
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw DingTalkDocumentServiceError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "operatorId", value: operatorID)]
        guard let url = components.url else {
            throw DingTalkDocumentServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = NetworkTimeouts.longRequest
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "x-acs-dingtalk-access-token")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DingTalkDocumentServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DingTalkDocumentServiceError.requestFailed(
                statusCode: http.statusCode,
                body: sanitizedBody(data, token: token)
            )
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DingTalkDocumentServiceError.invalidResponse
        }
        let flattened = flatten(json)
        let spaceID = firstFlattenedString(flattened, keys: ["spaceId", "spaceID", "space_id"])
        let dentryID = firstFlattenedString(flattened, keys: ["dentryId", "dentryID", "id", "parentId"])
        guard let spaceID, let dentryID else {
            throw DingTalkDocumentServiceError.invalidResponse
        }
        return (spaceID, dentryID)
    }

    private func documentItem(
        from raw: [String: Any],
        source: DingTalkDocumentSource,
        folderInput: String,
        fallbackSpaceID: String,
        fallbackParentID: String
    ) -> DingTalkDocumentItem? {
        let itemID = firstString(raw, keys: ["id", "dentryId", "fileId", "nodeId", "docId"]) ?? UUID().uuidString
        let title = firstString(raw, keys: ["name", "title", "fileName", "displayName"]) ?? "未命名钉钉文档"
        let kind = documentKind(from: raw)
        guard kind != .folder else { return nil }
        let summary = firstString(raw, keys: ["summary", "description", "content", "text", "markdown"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let contentStatus = summary?.isEmpty == false ? "已读取接口返回内容" : "仅同步元数据；若需要正文/表格内容，请确认钉钉文档或表格读取权限。"
        let metadataSummary = """
        标题：\(title)
        类型：\(kind.label)
        来源文件夹：\(folderInput)
        URL：\(firstString(raw, keys: ["url", "webUrl", "resourceUrl", "downloadUrl"]) ?? "未返回")
        内容状态：\(contentStatus)
        注意：钉钉文档创建/更新时间只代表文档记录，不等同真实上线或业务生效时间。
        """
        let readableSummary = summary.flatMap { $0.nilIfBlank } ?? metadataSummary
        return DingTalkDocumentItem(
            sourceID: source.id,
            businessSpaceID: source.businessSpaceID,
            folderInput: folderInput,
            itemID: itemID,
            title: title,
            kind: kind,
            sourceURL: firstString(raw, keys: ["url", "webUrl", "resourceUrl", "downloadUrl"]) ?? "",
            spaceID: firstString(raw, keys: ["spaceId", "spaceID"]) ?? fallbackSpaceID,
            parentID: firstString(raw, keys: ["parentId", "parentID"]) ?? fallbackParentID,
            createdAt: firstDate(raw, keys: ["createdAt", "createTime", "createdTime"]),
            updatedAt: firstDate(raw, keys: ["updatedAt", "modifiedTime", "lastModifiedTime", "updateTime"]),
            summary: capped(readableSummary, maxLength: 6000),
            contentStatus: contentStatus
        )
    }

    private func passesFilters(_ item: DingTalkDocumentItem, source: DingTalkDocumentSource) -> Bool {
        let title = item.title.normalizedKey
        let includes = source.parsedTitleKeywords.map(\.normalizedKey)
        let excludes = source.parsedExcludedTitleKeywords.map(\.normalizedKey)
        if !includes.isEmpty, !includes.contains(where: { title.contains($0) }) {
            return false
        }
        if excludes.contains(where: { title.contains($0) }) {
            return false
        }
        return true
    }

    private func documentKind(from raw: [String: Any]) -> DingTalkDocumentKind {
        let values = [
            firstString(raw, keys: ["type", "dentryType", "objectType", "fileType"]),
            firstString(raw, keys: ["extension", "fileExtension", "suffix"]),
            firstString(raw, keys: ["name", "title", "fileName"])
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
        if values.contains("folder") || values.contains("dir") { return .folder }
        if values.contains("sheet") || values.contains("spreadsheet") || values.contains("xlsx") || values.contains("xls") { return .spreadsheet }
        if values.contains("doc") || values.contains("document") { return .document }
        if values.contains("file") { return .file }
        return .unknown
    }

    private func extractArray(from json: [String: Any]) -> [[String: Any]] {
        for key in ["dentries", "items", "list", "files", "documents"] {
            if let array = json[key] as? [[String: Any]] {
                return array
            }
        }
        for key in ["result", "data"] {
            if let dict = json[key] as? [String: Any] {
                let nested = extractArray(from: dict)
                if !nested.isEmpty { return nested }
            }
        }
        return []
    }

    private func firstString(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = stringValue(dict[key])?.nilIfBlank {
                return value
            }
        }
        return nil
    }

    private func firstDate(_ dict: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            if let date = dateValue(dict[key]) {
                return date
            }
        }
        return nil
    }

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let int as Int:
            return "\(int)"
        case let double as Double:
            return "\(double)"
        default:
            return nil
        }
    }

    private func dateValue(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            let seconds = raw > 10_000_000_000 ? raw / 1000 : raw
            return Date(timeIntervalSince1970: seconds)
        }
        guard let string = stringValue(value)?.nilIfBlank else { return nil }
        if let milliseconds = Double(string), milliseconds > 1_000_000 {
            let seconds = milliseconds > 10_000_000_000 ? milliseconds / 1000 : milliseconds
            return Date(timeIntervalSince1970: seconds)
        }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: string) {
            return date
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }

    private func valueAfterLabel(in text: String, labels: [String]) -> String? {
        for label in labels {
            let pattern = "\(label)[=:：/]([A-Za-z0-9_\\-]+)"
            if let range = text.range(of: pattern, options: .regularExpression) {
                let fragment = String(text[range])
                return fragment
                    .replacingOccurrences(of: "\(label)", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "=:：/ "))
                    .nilIfBlank
            }
        }
        return nil
    }

    private func rawIDCandidate(from input: String) -> String {
        input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet(charactersIn: "/?&#"))
            .last?
            .nilIfBlank ?? input
    }

    private func folderUUIDCandidate(from input: String) -> String? {
        guard let url = URL(string: input) else { return nil }
        let components = url.pathComponents
        guard let foldersIndex = components.firstIndex(where: { $0.lowercased() == "folders" }),
              components.indices.contains(foldersIndex + 1) else {
            return nil
        }
        return components[foldersIndex + 1].nilIfBlank
    }

    private func flatten(_ value: Any) -> [String: Any] {
        var result: [String: Any] = [:]
        func walk(_ current: Any) {
            if let dict = current as? [String: Any] {
                for (key, value) in dict {
                    result[key] = value
                    walk(value)
                }
            } else if let array = current as? [Any] {
                for item in array {
                    walk(item)
                }
            }
        }
        walk(value)
        return result
    }

    private func firstFlattenedString(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let direct = stringValue(dict[key])?.nilIfBlank {
                return direct
            }
            if let match = dict.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }),
               let value = stringValue(match.value)?.nilIfBlank {
                return value
            }
        }
        return nil
    }

    private func sanitizedBody(_ data: Data, source: DingTalkDocumentSource? = nil, token: String? = nil) -> String {
        let raw = String(data: data, encoding: .utf8) ?? ""
        var text = String(raw.prefix(600))
        if let source {
            text = sanitize(text, source: source)
        }
        if let token {
            text = text.replacingOccurrences(of: token, with: "[access-token]")
        }
        return text
    }

    private func sanitize(_ text: String, source: DingTalkDocumentSource) -> String {
        var sanitized = text
        let secret = source.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        if !secret.isEmpty {
            sanitized = sanitized.replacingOccurrences(of: secret, with: "[client-secret]")
        }
        return sanitized
    }

    private func capped(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        return String(text.prefix(maxLength)) + "\n…（钉钉内容已截断）"
    }
}
