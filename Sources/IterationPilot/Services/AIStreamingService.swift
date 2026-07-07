import Foundation

struct AIStreamingResult {
    var output: String
    var didReceiveStreamDeltas: Bool
}

struct AIStreamingService {
    func runStreamingAnalysis(
        prompt: String,
        settings: AISettings,
        timeout: TimeInterval = NetworkTimeouts.aiRequest,
        onProgress: @escaping (_ progressText: String) async -> Void = { _ in },
        onDelta: @escaping (_ accumulatedText: String) async -> Void
    ) async throws -> AIStreamingResult {
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
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": settings.model,
            "messages": [
                ["role": "system", "content": settings.systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2,
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, urlResponse) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw AIAnalysisError.invalidResponse("服务未返回 HTTP 响应。")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = try await Self.collectResponseText(from: bytes)
            throw AIAnalysisError.httpError(statusCode: httpResponse.statusCode, message: Self.responseMessage(from: message))
        }

        var accumulated = ""
        var rawPreview = ""
        var didReceiveDeltas = false
        var didReceiveReasoningDeltas = false
        var accumulatedReasoning = ""
        var lastContentEmitAt = Date.distantPast
        var lastReasoningEmitAt = Date.distantPast
        var lastEmittedContentCount = 0
        var lastEmittedReasoningCount = 0
        let minimumEmitInterval: TimeInterval = 0.1

        func emitContentIfNeeded(force: Bool = false) async {
            guard accumulated.count > lastEmittedContentCount else { return }
            let now = Date()
            guard force || now.timeIntervalSince(lastContentEmitAt) >= minimumEmitInterval else { return }
            lastContentEmitAt = now
            lastEmittedContentCount = accumulated.count
            await onDelta(accumulated)
        }

        func emitReasoningIfNeeded(force: Bool = false) async {
            guard accumulatedReasoning.count > lastEmittedReasoningCount else { return }
            let now = Date()
            guard force || now.timeIntervalSince(lastReasoningEmitAt) >= minimumEmitInterval else { return }
            lastReasoningEmitAt = now
            lastEmittedReasoningCount = accumulatedReasoning.count
            await onProgress(accumulatedReasoning)
        }

        for try await line in bytes.lines {
            try Task.checkCancellation()
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }
            if rawPreview.count < 1_000 {
                rawPreview += trimmedLine + "\n"
            }
            guard trimmedLine.hasPrefix("data:") else { continue }
            let payload = trimmedLine
                .dropFirst(5)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if payload == "[DONE]" {
                await emitContentIfNeeded(force: true)
                await emitReasoningIfNeeded(force: true)
                return AIStreamingResult(output: accumulated, didReceiveStreamDeltas: didReceiveDeltas)
            }
            guard let data = payload.data(using: .utf8) else { continue }
            if let errorMessage = AIServiceResponseParser.errorMessageIfPresent(from: data) {
                throw AIAnalysisError.invalidResponse(errorMessage)
            }
            let chunk: StreamingChatCompletionChunk
            do {
                chunk = try JSONDecoder().decode(StreamingChatCompletionChunk.self, from: data)
            } catch {
                if rawPreview.count < 2_000 {
                    rawPreview += "DECODE_ERROR: \(error.localizedDescription)\n"
                }
                continue
            }
            let delta = chunk.choices
                .compactMap { $0.delta?.content ?? $0.message?.content }
                .joined()
            let reasoningDelta = chunk.choices
                .compactMap { $0.delta?.reasoningContent ?? $0.message?.reasoningContent }
                .joined()

            if !delta.isEmpty {
                accumulated += delta
                didReceiveDeltas = true
                await emitContentIfNeeded()
            } else if !reasoningDelta.isEmpty {
                didReceiveReasoningDeltas = true
                accumulatedReasoning += reasoningDelta
                await emitReasoningIfNeeded()
            }
        }

        if !accumulated.isEmpty {
            await emitContentIfNeeded(force: true)
            return AIStreamingResult(output: accumulated, didReceiveStreamDeltas: didReceiveDeltas)
        }
        if didReceiveReasoningDeltas {
            throw AIAnalysisError.invalidResponse("模型返回了推理流 reasoning_content，但没有返回最终回答 content，已准备降级为普通请求。")
        }
        throw AIAnalysisError.invalidResponse(Self.responseMessage(from: rawPreview))
    }

    private static func collectResponseText(from bytes: URLSession.AsyncBytes) async throws -> String {
        var text = ""
        for try await line in bytes.lines {
            if text.count < 2_000 {
                text += line + "\n"
            }
        }
        return text
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

    private static func responseMessage(from text: String) -> String {
        AIServiceResponseParser.message(from: text)
    }
}

private struct StreamingChatCompletionChunk: Decodable {
    var choices: [Choice]

    struct Choice: Decodable {
        var delta: Delta?
        var message: Message?
        var finishReason: String?

        private enum CodingKeys: String, CodingKey {
            case delta
            case message
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Decodable {
        var content: String?
        var reasoningContent: String?

        private enum CodingKeys: String, CodingKey {
            case content
            case reasoningContent = "reasoning_content"
        }
    }

    struct Message: Decodable {
        var content: String?
        var reasoningContent: String?

        private enum CodingKeys: String, CodingKey {
            case content
            case reasoningContent = "reasoning_content"
        }
    }
}
