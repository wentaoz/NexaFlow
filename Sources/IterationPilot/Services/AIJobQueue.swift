import Foundation

enum AIJobQueueError: LocalizedError {
    case pausedForUserAction(String, AIJobRecord)
    case exhaustedRetries(String, AIJobRecord)

    var errorDescription: String? {
        switch self {
        case .pausedForUserAction(let message, _):
            return "AI 作业需要用户处理：\(message)"
        case .exhaustedRetries(let message, _):
            return "AI 作业重试后仍失败：\(message)"
        }
    }

    var record: AIJobRecord {
        switch self {
        case .pausedForUserAction(_, let record), .exhaustedRetries(_, let record):
            return record
        }
    }
}

struct AIJobQueue {
    var maxAttempts: Int = 6
    var baseDelay: TimeInterval = 1.2

    func runTextJob(
        prompt: String,
        settings: AISettings,
        jobType: String,
        validation: @escaping (String) -> [String] = { _ in [] },
        correctionPrompt: @escaping (_ originalPrompt: String, _ output: String, _ warnings: [String]) -> String
    ) async throws -> (output: String, record: AIJobRecord) {
        var record = AIJobRecord(jobType: jobType, status: .waiting, maxAttempts: maxAttempts)
        var currentPrompt = prompt
        var lastError = ""

        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            record.attemptCount = attempt
            record.status = .requesting
            record.updatedAt = Date()
            record.logs.append(AIReasoningLogEntry(step: jobType, status: .requesting, detail: "第 \(attempt) 次请求 AI。"))
            record.trimLogsForStorage()

            do {
                try Task.checkCancellation()
                let output = try await AIAnalysisService().runAnalysis(prompt: currentPrompt, settings: settings)
                try Task.checkCancellation()
                record.status = .validating
                record.logs.append(AIReasoningLogEntry(step: jobType, status: .validating, detail: "AI 已返回，正在做本地校验。"))
                let warnings = validation(output)
                if warnings.isEmpty {
                    record.status = .completed
                    record.updatedAt = Date()
                    record.logs.append(AIReasoningLogEntry(step: jobType, status: .completed, detail: "AI 输出通过本地校验。"))
                    record.trimLogsForStorage()
                    return (output, record)
                }

                lastError = warnings.joined(separator: "；")
                record.lastError = lastError
                record.status = .correcting
                record.logs.append(AIReasoningLogEntry(step: jobType, status: .correcting, detail: "校验未通过：\(lastError)。已自动要求模型修正。"))
                currentPrompt = correctionPrompt(prompt, output, warnings)
            } catch {
                if error is CancellationError {
                    record.status = .cancelled
                    record.updatedAt = Date()
                    record.lastError = "任务已取消。"
                    record.logs.append(AIReasoningLogEntry(step: jobType, status: .cancelled, detail: record.lastError))
                    record.trimLogsForStorage()
                    throw error
                }
                lastError = error.localizedDescription
                record.lastError = lastError
                if !Self.isRetryable(error) {
                    record.status = .needsUserAction
                    record.updatedAt = Date()
                    record.logs.append(AIReasoningLogEntry(step: jobType, status: .needsUserAction, detail: lastError))
                    record.trimLogsForStorage()
                    throw AIJobQueueError.pausedForUserAction(lastError, record)
                }
                record.logs.append(AIReasoningLogEntry(step: jobType, status: .waiting, detail: "可恢复错误：\(lastError)，准备自动重试。"))
            }

            if attempt < maxAttempts {
                let delay = min(30, baseDelay * pow(2, Double(attempt - 1)))
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                try Task.checkCancellation()
            }
        }

        record.status = .needsUserAction
        record.updatedAt = Date()
        record.logs.append(AIReasoningLogEntry(step: jobType, status: .needsUserAction, detail: "达到最大重试次数：\(lastError)"))
        record.trimLogsForStorage()
        throw AIJobQueueError.exhaustedRetries(lastError, record)
    }

    func runStreamingTextJob(
        prompt: String,
        settings: AISettings,
        jobType: String,
        validation: @escaping (String) -> [String] = { _ in [] },
        correctionPrompt: @escaping (_ originalPrompt: String, _ output: String, _ warnings: [String]) -> String = { originalPrompt, output, warnings in
            """
            \(originalPrompt)

            上一次流式输出未通过本地校验，请只根据下列问题重写最终回答，不要重复错误结论。
            校验问题：\(warnings.joined(separator: "；"))

            上一次输出：
            \(output)
            """
        },
        onProgress: @escaping (_ progressText: String) async -> Void = { _ in },
        onDelta: @escaping (_ accumulatedText: String) async -> Void
    ) async throws -> (output: String, record: AIJobRecord) {
        var record = AIJobRecord(jobType: jobType, status: .waiting, maxAttempts: maxAttempts)
        var currentPrompt = prompt
        var lastError = ""

        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            record.attemptCount = attempt
            record.status = .requesting
            record.updatedAt = Date()
            record.logs.append(AIReasoningLogEntry(step: jobType, status: .requesting, detail: "第 \(attempt) 次流式请求 AI。"))
            record.trimLogsForStorage()

            do {
                try Task.checkCancellation()
                let result = try await AIStreamingService().runStreamingAnalysis(
                    prompt: currentPrompt,
                    settings: settings,
                    onProgress: onProgress,
                    onDelta: onDelta
                )
                try Task.checkCancellation()
                guard result.didReceiveStreamDeltas else {
                    throw AIAnalysisError.invalidResponse("模型未返回流式 delta，准备降级为非流式请求。")
                }
                record.status = .validating
                record.logs.append(AIReasoningLogEntry(step: jobType, status: .validating, detail: "AI 流式回复已完成，正在做本地校验。"))
                let warnings = validation(result.output)
                if warnings.isEmpty {
                    record.status = .completed
                    record.updatedAt = Date()
                    record.logs.append(AIReasoningLogEntry(step: jobType, status: .completed, detail: "AI 流式输出通过本地校验。"))
                    record.trimLogsForStorage()
                    return (result.output, record)
                }

                lastError = warnings.joined(separator: "；")
                record.lastError = lastError
                record.status = .correcting
                record.logs.append(AIReasoningLogEntry(step: jobType, status: .correcting, detail: "流式输出校验未通过：\(lastError)。已自动要求模型修正。"))
                currentPrompt = correctionPrompt(prompt, result.output, warnings)
            } catch {
                if error is CancellationError {
                    record.status = .cancelled
                    record.updatedAt = Date()
                    record.lastError = "任务已取消。"
                    record.logs.append(AIReasoningLogEntry(step: jobType, status: .cancelled, detail: record.lastError))
                    record.trimLogsForStorage()
                    throw error
                }
                lastError = error.localizedDescription
                record.lastError = lastError
                if !Self.isRetryable(error) {
                    record.status = .needsUserAction
                    record.updatedAt = Date()
                    record.logs.append(AIReasoningLogEntry(step: jobType, status: .needsUserAction, detail: lastError))
                    record.trimLogsForStorage()
                    throw AIJobQueueError.pausedForUserAction(lastError, record)
                }
                record.logs.append(AIReasoningLogEntry(step: jobType, status: .waiting, detail: "流式可恢复错误：\(lastError)，准备自动重试。"))
            }

            if attempt < maxAttempts {
                let delay = min(30, baseDelay * pow(2, Double(attempt - 1)))
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                try Task.checkCancellation()
            }
        }

        record.status = .needsUserAction
        record.updatedAt = Date()
        record.logs.append(AIReasoningLogEntry(step: jobType, status: .needsUserAction, detail: "流式请求达到最大重试次数：\(lastError)"))
        record.trimLogsForStorage()
        throw AIJobQueueError.exhaustedRetries(lastError, record)
    }

    static func isRetryable(_ error: Error) -> Bool {
        if error is CancellationError {
            return false
        }
        if let queueError = error as? AIJobQueueError {
            switch queueError {
            case .pausedForUserAction: return false
            case .exhaustedRetries: return true
            }
        }
        if let aiError = error as? AIAnalysisError {
            switch aiError {
            case .missingAPIKey, .invalidEndpoint:
                return false
            case .httpError(let statusCode, _):
                if statusCode == 401 || statusCode == 403 || statusCode == 404 { return false }
                return statusCode == 408 || statusCode == 409 || statusCode == 425 || statusCode == 429 || (500..<600).contains(statusCode)
            case .invalidResponse:
                return true
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }
        return false
    }
}

private extension AIJobRecord {
    mutating func trimLogsForStorage(limit: Int = 120) {
        if logs.count > limit {
            logs = Array(logs.suffix(limit))
        }
    }
}
