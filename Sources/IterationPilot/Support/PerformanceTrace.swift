import Foundation
import OSLog

enum PerformanceTrace {
    private static let logger = Logger(subsystem: "NexaFlow", category: "Performance")
    private static let isEnabled = ProcessInfo.processInfo.environment["NEXAFLOW_PERF_TRACE"] == "1"

    static func measure<T>(_ label: String, metadata: String = "", _ work: () throws -> T) rethrows -> T {
        guard isEnabled else {
            return try work()
        }

        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - start) * 1_000
            logger.debug("\(label, privacy: .public) \(metadata, privacy: .public) took \(elapsedMilliseconds, privacy: .public)ms")
        }
        return try work()
    }
}
