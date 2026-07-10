import Foundation
@testable import IterationPilotCore

final class AIRequestScenarioTests: XCTestCase {
    private let settings = AISettings(
        endpoint: "https://mock.ai.test/chat/completions",
        model: "gpt-4o-mini",
        apiKey: "mock-key",
        systemPrompt: "You are a test assistant."
    )

    func testAIAnalysisServiceReturnsContentFromMockEndpoint() async throws {
        MockAIServiceProtocol.prepare(for: .nonStreamingSuccess)
        defer {
            MockAIServiceProtocol.clear()
        }

        let output = try await AIAnalysisService().runAnalysis(
            prompt: "Say: hello",
            settings: settings
        )

        XCTAssert(output == "analysis response")
        XCTAssert(MockAIServiceProtocol.requestCount == 1)
    }

    func testAIStreamingServiceReturnsIncrementalEvents() async throws {
        MockAIServiceProtocol.prepare(for: .streamingSuccess)
        defer {
            MockAIServiceProtocol.clear()
        }

        var deltaCount = 0
        let result = try await AIStreamingService().runStreamingAnalysis(
            prompt: "Stream this",
            settings: settings,
            onDelta: { _ in
                deltaCount += 1
            }
        )

        XCTAssert(!result.output.isEmpty)
        XCTAssert(result.didReceiveStreamDeltas)
        XCTAssert(deltaCount > 0)
        XCTAssert(MockAIServiceProtocol.requestCount == 1)
    }

    func testStreamingTextJobRetriesWithCorrectionPrompt() async throws {
        MockAIServiceProtocol.prepare(for: .streamingValidationRetry)
        defer {
            MockAIServiceProtocol.clear()
        }

        let queue = AIJobQueue(maxAttempts: 3, baseDelay: 0)
        var deltaCount = 0
        let (output, record) = try await queue.runStreamingTextJob(
            prompt: "Draft a short answer.",
            settings: settings,
            jobType: "scenario-streaming-retry",
            validation: { output in
                output.contains("final answer") ? [] : ["output-not-finalized"]
            },
            onDelta: { _ in
                deltaCount += 1
            }
        )

        XCTAssert(output == "final answer ready")
        XCTAssert(record.status == AIJobStatus.completed)
        XCTAssert(record.attemptCount == 2)
        XCTAssert(MockAIServiceProtocol.requestCount == 2)
        XCTAssert(MockAIServiceProtocol.capturedPrompts.count == 2)
        let secondPrompt = MockAIServiceProtocol.capturedPrompts[1]
        XCTAssert(!secondPrompt.isEmpty)
        XCTAssert(
            secondPrompt.contains("上一次流式输出未通过本地校验")
            || secondPrompt.contains("上次输出")
            || secondPrompt.contains("校验问题")
        )
        XCTAssert(deltaCount > 0)
    }

    func testTextJobRetriesAfterTimeoutErrorAndEventuallySucceeds() async throws {
        MockAIServiceProtocol.prepare(for: .textTimeoutThenSuccess)
        defer {
            MockAIServiceProtocol.clear()
        }

        let queue = AIJobQueue(maxAttempts: 2, baseDelay: 0)
        let (output, record) = try await queue.runTextJob(
            prompt: "Calculate summary",
            settings: settings,
            jobType: "scenario-timeout-retry",
            correctionPrompt: { _, output, _ in output }
        )

        XCTAssert(output == "recovered answer")
        XCTAssert(record.status == AIJobStatus.completed)
        XCTAssert(record.attemptCount == 2)
        XCTAssert(MockAIServiceProtocol.requestCount == 2)
    }

    func testTextJobDoesNotRetryOnNonRetryableHTTPError() async throws {
        MockAIServiceProtocol.prepare(for: .nonRetryableHTTPError(statusCode: 403))
        defer {
            MockAIServiceProtocol.clear()
        }

        let queue = AIJobQueue(maxAttempts: 2, baseDelay: 0)
        do {
            _ = try await queue.runTextJob(
                prompt: "Should fail",
                settings: settings,
                jobType: "scenario-http-403",
                correctionPrompt: { _, output, _ in output }
            )
            XCTAssert(false)
        } catch {
            guard case AIJobQueueError.pausedForUserAction = error else {
                XCTAssert(false)
                return
            }
            if case let .pausedForUserAction(_, record) = error as? AIJobQueueError {
                XCTAssert(record.attemptCount == 1)
                XCTAssert(record.status == AIJobStatus.needsUserAction)
                XCTAssert(MockAIServiceProtocol.requestCount == 1)
                XCTAssert(record.lastError.contains("HTTP 403"))
            } else {
                XCTAssert(false)
            }
        }
    }
}

private final class MockAIServiceProtocol: URLProtocol {
    enum Scenario {
        case nonStreamingSuccess
        case streamingSuccess
        case streamingValidationRetry
        case textTimeoutThenSuccess
        case nonRetryableHTTPError(statusCode: Int)
        case inactive
    }

    final class State {
        var scenario: Scenario = .inactive
        var requestCount = 0
        var capturedPrompts: [String] = []
    }

    static var state = State()
    private static let lock = NSLock()

    static func prepare(for scenario: Scenario) {
        lock.lock()
        state.scenario = scenario
        state.requestCount = 0
        state.capturedPrompts = []
        lock.unlock()
        URLProtocol.registerClass(MockAIServiceProtocol.self)
    }

    static func clear() {
        URLProtocol.unregisterClass(MockAIServiceProtocol.self)
        resetState()
    }

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return state.requestCount
    }

    static var capturedPrompts: [String] {
        lock.lock()
        defer { lock.unlock() }
        return state.capturedPrompts
    }

    private static func resetState() {
        lock.lock()
        state.scenario = .inactive
        state.requestCount = 0
        state.capturedPrompts = []
        lock.unlock()
    }

    override static func canInit(with request: URLRequest) -> Bool {
        guard request.url?.host == "mock.ai.test" else { return false }
        return true
    }

    override class func canInit(with task: URLSessionTask) -> Bool {
        guard let request = task.currentRequest else { return false }
        return canInit(with: request)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let response = Self.nextResponse(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        if let error = response.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func nextResponse(for request: URLRequest) -> MockResponse? {
        guard request.url != nil else { return nil }
        lock.lock()
        state.requestCount += 1
        let requestIndex = state.requestCount
        let scenario = state.scenario
        state.capturedPrompts.append(Self.extractUserPrompt(from: request))
        lock.unlock()

        switch scenario {
        case .inactive:
            return MockResponse(
                statusCode: 500,
                body: Data("{}".utf8)
            )
        case .nonStreamingSuccess:
            return MockResponse(statusCode: 200, body: makeTextCompletionBody(output: "analysis response"))
        case .streamingSuccess:
            return MockResponse(statusCode: 200, body: makeStreamingBody(chunks: ["analysis", " streaming"]))
        case .streamingValidationRetry:
            if requestIndex == 1 {
                return MockResponse(
                    statusCode: 200,
                    body: makeStreamingBody(chunks: ["bad output"])
                )
            } else if requestIndex == 2 {
                return MockResponse(
                    statusCode: 200,
                    body: makeStreamingBody(chunks: ["final answer ready"])
                )
            } else {
                return MockResponse(
                    statusCode: 500,
                    body: Data("{}".utf8)
                )
            }
        case .textTimeoutThenSuccess:
            if requestIndex == 1 {
                return MockResponse(statusCode: 200, body: Data(), error: URLError(.timedOut))
            }
            return MockResponse(statusCode: 200, body: makeTextCompletionBody(output: "recovered answer"))
        case let .nonRetryableHTTPError(statusCode):
            let body = (try? JSONSerialization.data(
                withJSONObject: ["error": "permission denied"],
                options: []
            )) ?? Data()
            return MockResponse(statusCode: statusCode, body: body)
        }
    }

    private static func extractUserPrompt(from request: URLRequest) -> String {
        guard let body = bodyData(from: request),
              let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return ""
        }

        if let messages = payload["messages"] as? [[String: Any]],
           let userMessage = messages.last(where: { ($0["role"] as? String) == "user" }) {
            if let content = userMessage["content"] as? String {
                return content
            }
            if let contentParts = userMessage["content"] as? [[String: Any]] {
                return contentParts.compactMap { part in
                    if let text = part["text"] as? String {
                        return text
                    }
                    if let content = part["content"] as? String {
                        return content
                    }
                    return nil
                }.joined()
            }
        }

        if let prompt = payload["prompt"] as? String {
            return prompt
        }

        return ""
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            if bytesRead <= 0 { break }
            data.append(buffer, count: bytesRead)
        }

        return data.isEmpty ? nil : data
    }

    private static func makeTextCompletionBody(output: String) -> Data {
        let response: [String: Any] = [
            "id": "chatcmpl-mock",
            "object": "chat.completion",
            "choices": [
                [
                    "index": 0,
                    "message": ["role": "assistant", "content": output]
                ]
            ],
            "model": "gpt-4o-mini"
        ]
        return (try? JSONSerialization.data(withJSONObject: response)) ?? Data()
    }

    private static func makeStreamingBody(chunks: [String]) -> Data {
        let lines = chunks.map { chunk in
            "data: \(streamChunkBody(content: chunk))"
        } + ["data: [DONE]"]
        return (lines.joined(separator: "\n") + "\n").data(using: .utf8) ?? Data()
    }

    private static func streamChunkBody(content: String) -> String {
        let payload: [String: Any] = [
            "choices": [
                [
                    "delta": ["content": content]
                ]
            ]
        ]
        return (try? String(data: JSONSerialization.data(withJSONObject: payload), encoding: .utf8)) ?? "{}"
    }

    private struct MockResponse {
        let statusCode: Int
        let body: Data
        let error: Error?

        init(statusCode: Int, body: Data, error: Error? = nil) {
            self.statusCode = statusCode
            self.body = body
            self.error = error
        }
    }
}
