import Darwin
import Foundation

public enum AppInternalLiveSmokeRunner {
    public static let environmentKey = "NEXAFLOW_APP_INTERNAL_LIVE_SMOKE"

    public static var isRequested: Bool {
        ProcessInfo.processInfo.environment[environmentKey] == "1"
    }

    public static func runAndExit() -> Never {
        Darwin.exit(Int32(runBlocking()))
    }

    private static func runBlocking() -> Int {
        let semaphore = DispatchSemaphore(value: 0)
        let exitCodeBox = AppInternalLiveSmokeExitCodeBox()

        Task.detached {
            let code = await run()
            exitCodeBox.set(code)
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + NetworkTimeouts.analysisIntentRequest + 15)
        guard waitResult == .success else {
            print("APP_INTERNAL_LIVE_SMOKE_FAIL timeout")
            return 1
        }

        return exitCodeBox.get()
    }

    private static func run() async -> Int {
        guard let workspace = ProductWorkflowStore.loadWorkspace() else {
            print("APP_INTERNAL_LIVE_SMOKE_SKIP workspace_missing")
            return 2
        }

        let settings = workspace.aiSettings
        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("APP_INTERNAL_LIVE_SMOKE_FAIL missing_api_key")
            return 1
        }

        do {
            let result = try await AIStreamingService().runStreamingAnalysis(
                prompt: "请只输出一句中文：NexaFlow live smoke ok。",
                settings: settings,
                timeout: NetworkTimeouts.analysisIntentRequest,
                onProgress: { _ in },
                onDelta: { _ in }
            )
            guard !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print("APP_INTERNAL_LIVE_SMOKE_FAIL empty_output")
                return 1
            }
            print("APP_INTERNAL_LIVE_SMOKE_OK chars=\(result.output.count) streamed=\(result.didReceiveStreamDeltas)")
            return 0
        } catch {
            print("APP_INTERNAL_LIVE_SMOKE_FAIL \(String(describing: error))")
            return 1
        }
    }
}

private final class AppInternalLiveSmokeExitCodeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var code = 1

    func set(_ code: Int) {
        lock.lock()
        self.code = code
        lock.unlock()
    }

    func get() -> Int {
        lock.lock()
        let code = code
        lock.unlock()
        return code
    }
}
