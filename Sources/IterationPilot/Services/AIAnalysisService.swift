import Foundation

enum AIAnalysisError: LocalizedError {
    case missingAPIKey
    case invalidEndpoint(String)
    case httpError(statusCode: Int, message: String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "请先在 AI 设置中填写 API Key。"
        case .invalidEndpoint(let endpoint): return "AI endpoint/base_url 不是有效 URL：\(endpoint)"
        case .httpError(let statusCode, let message):
            return "AI 服务请求失败：HTTP \(statusCode)。\(message)"
        case .invalidResponse(let message):
            return "AI 服务返回格式无法解析：\(message)"
        }
    }
}

struct AIAnalysisService {
    func runAnalysis(prompt: String, settings: AISettings, timeout: TimeInterval = NetworkTimeouts.longRequest) async throws -> String {
        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIAnalysisError.missingAPIKey
        }
        let endpoint = settings.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = Self.chatCompletionsURL(from: endpoint) else {
            throw AIAnalysisError.invalidEndpoint(endpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": settings.model,
            "messages": [
                ["role": "system", "content": settings.systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw AIAnalysisError.invalidResponse("服务未返回 HTTP 响应。")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AIAnalysisError.httpError(
                statusCode: httpResponse.statusCode,
                message: Self.responseMessage(from: data)
            )
        }

        let response: ChatCompletionResponse
        do {
            response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            throw AIAnalysisError.invalidResponse(AIServiceResponseParser.message(from: data))
        }
        let content = response.choices
            .compactMap { $0.message.content?.text.nilIfBlank }
            .joined(separator: "\n\n")
            .nilIfBlank
        guard let content else {
            let reasoning = response.choices
                .compactMap { $0.message.reasoningContent?.nilIfBlank }
                .joined(separator: "\n\n")
                .nilIfBlank
            if reasoning != nil {
                throw AIAnalysisError.invalidResponse("模型只返回 reasoning_content，没有返回最终回答 content。请确认当前模型和接口支持 Chat Completions 的 content 输出。")
            }
            throw AIAnalysisError.invalidResponse("响应中没有 choices[0].message.content。响应摘要：\(AIServiceResponseParser.message(from: data))")
        }
        return content
    }

    private static func chatCompletionsURL(from endpoint: String) -> URL? {
        guard var components = URLComponents(string: endpoint) else { return nil }
        let normalizedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedPath.hasSuffix("chat/completions") {
            return components.url
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([basePath, "chat/completions"].filter { !$0.isEmpty }.joined(separator: "/"))
        return components.url
    }

    private static func responseMessage(from data: Data) -> String {
        AIServiceResponseParser.message(from: data)
    }
}

private struct ChatCompletionResponse: Decodable {
    var choices: [Choice]

    struct Choice: Decodable {
        var message: Message
    }

    struct Message: Decodable {
        var content: ChatContent?
        var reasoningContent: String?

        private enum CodingKeys: String, CodingKey {
            case content
            case reasoningContent = "reasoning_content"
        }
    }
}

private enum ChatContent: Decodable {
    case text(String)

    var text: String {
        switch self {
        case .text(let value): return value
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .text(string)
            return
        }
        if let parts = try? container.decode([ContentPart].self) {
            self = .text(parts.compactMap(\.textValue).joined())
            return
        }
        self = .text("")
    }

    private struct ContentPart: Decodable {
        var text: String?
        var content: String?

        var textValue: String? {
            text?.nilIfBlank ?? content?.nilIfBlank
        }
    }
}
