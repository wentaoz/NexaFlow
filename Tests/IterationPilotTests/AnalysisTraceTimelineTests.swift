import Foundation
import XCTest
@testable import IterationPilotCore

final class AnalysisTraceTimelineTests: XCTestCase {
    func testTraceTimelineBuilderMergesJobHarnessAndNumberTraceEvents() {
        let sessionID = UUID(uuidString: "88888888-8888-8888-8888-888888888888") ?? UUID()
        let packID = UUID(uuidString: "99999999-9999-9999-9999-999999999999") ?? UUID()
        let baseDate = Date(timeIntervalSince1970: 1_800_100_000)
        let message = AnalysisSessionMessage(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA") ?? UUID(),
            createdAt: baseDate,
            role: .user,
            kind: .userRequest,
            content: "请分析交易人数为什么变化。"
        )
        let session = AnalysisSession(
            id: sessionID,
            packID: packID,
            title: "测试会话",
            messages: [message]
        )
        let audit = AuditEvent(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB") ?? UUID(),
            createdAt: baseDate.addingTimeInterval(2),
            stage: .metricExecution,
            status: .completed,
            summary: "执行本地 SUM 计算。",
            durationMilliseconds: 42
        )
        let run = AnalysisHarnessRun(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC") ?? UUID(),
            createdAt: baseDate.addingTimeInterval(1),
            finishedAt: baseDate.addingTimeInterval(3),
            status: .success,
            userQuery: "请分析交易人数为什么变化。",
            tableManifest: [],
            analysisPlan: nil,
            verifiedResults: [],
            validationIssues: [],
            auditLog: [audit],
            reportMarkdown: "## 直接回答你的问题",
            repairAttemptsPlan: 0,
            repairAttemptsReport: 0,
            durationMilliseconds: 120,
            answerNumberTraces: [
                AnswerNumberTrace(
                    rawText: "12,345",
                    normalizedValue: 12_345,
                    status: .matched,
                    matchedResultLabel: "交易人数"
                )
            ]
        )
        let evidence = AnalysisSessionEvidence(
            sourceType: "analysisHarness",
            title: "Harness 审计",
            detail: run.evidenceMarkdown,
            analysisHarnessRun: run
        )
        let job = PersistentAIJob(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD") ?? UUID(),
            createdAt: baseDate,
            updatedAt: baseDate.addingTimeInterval(4),
            kind: .analysisSession,
            status: .completed,
            payload: PersistentAIJobPayload(
                sessionID: sessionID,
                packID: packID,
                targetName: "测试会话"
            ),
            logs: [
                AIReasoningLogEntry(
                    createdAt: baseDate.addingTimeInterval(0.5),
                    step: "解析分析意图",
                    status: .requesting,
                    detail: "开始解析用户问题。"
                )
            ]
        )

        let events = AnalysisTraceTimelineBuilder.build(
            session: session,
            coverageSnapshot: nil,
            harnessEvidence: [evidence],
            notebookRuns: [],
            collectionRuns: [],
            jobs: [job]
        )

        XCTAssert(events.contains { $0.source == .conversation && $0.title == "用户提问" })
        XCTAssert(events.contains { $0.source == .harness && $0.title == "执行本地指标" })
        XCTAssert(events.contains { $0.source == .answerTrace && $0.title == "追溯回答数字" })
        XCTAssert(events.contains { $0.source == .aiJob && $0.title == "解析分析意图" })
        XCTAssert(events == events.sorted { lhs, rhs in
            if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt < rhs.occurredAt }
            return lhs.id < rhs.id
        })
    }
}
