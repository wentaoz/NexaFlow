import Foundation

enum NetworkRetry {
    static func data(
        for request: URLRequest,
        attempts: Int = 3,
        baseDelay: TimeInterval = 0.35
    ) async throws -> (Data, URLResponse) {
        var lastError: Error?
        let maxAttempts = max(1, attempts)

        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            do {
                let result = try await URLSession.shared.data(for: request)
                if let http = result.1 as? HTTPURLResponse,
                   isRetryableStatusCode(http.statusCode),
                   attempt < maxAttempts {
                    try await sleepBeforeRetry(attempt: attempt, baseDelay: baseDelay)
                    continue
                }
                return result
            } catch {
                if error is CancellationError {
                    throw error
                }
                guard isRetryable(error), attempt < maxAttempts else {
                    throw error
                }
                lastError = error
                try await sleepBeforeRetry(attempt: attempt, baseDelay: baseDelay)
            }
        }

        throw lastError ?? URLError(.unknown)
    }

    static func isRetryableStatusCode(_ statusCode: Int) -> Bool {
        statusCode == 408 ||
            statusCode == 409 ||
            statusCode == 425 ||
            statusCode == 429 ||
            (500..<600).contains(statusCode)
    }

    private static func isRetryable(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else {
            return false
        }
        switch urlError.code {
        case .timedOut,
             .networkConnectionLost,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed,
             .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    private static func sleepBeforeRetry(attempt: Int, baseDelay: TimeInterval) async throws {
        let delay = min(4, baseDelay * pow(2, Double(attempt - 1)))
        try Task.checkCancellation()
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}
