import Foundation
@testable import IterationPilotCore

final class PersistentAIJobFingerprintTests: XCTestCase {
    func testFingerprintIsStableAndDoesNotExposeRawPayloadText() {
        let marker = "RAW_PAYLOAD_MARKER_SHOULD_NOT_APPEAR"
        let payload = PersistentAIJobPayload(
            prompt: String(repeating: "A", count: 4_096) + marker,
            userMessage: "请分析当前任务",
            aiOutput: "回答内容 \(marker)",
            messageID: UUID(uuidString: "11111111-1111-1111-1111-111111111111"),
            sessionID: UUID(uuidString: "22222222-2222-2222-2222-222222222222"),
            packID: UUID(uuidString: "33333333-3333-3333-3333-333333333333"),
            targetName: "测试任务"
        )

        let first = PersistentAIJobFingerprintBuilder.fingerprint(kind: .analysisSession, payload: payload)
        let second = PersistentAIJobFingerprintBuilder.fingerprint(kind: .analysisSession, payload: payload)

        XCTAssert(first == second)
        XCTAssert(!first.contains(marker))
        XCTAssert(first.count <= 80)
    }

    func testFingerprintDetectsLargePromptMiddleChanges() {
        let prefix = String(repeating: "前置内容", count: 2_000)
        let suffix = String(repeating: "后置内容", count: 2_000)
        let base = PersistentAIJobPayload(
            prompt: prefix + "中间-A" + suffix,
            userMessage: "同一个问题",
            sessionID: UUID(uuidString: "44444444-4444-4444-4444-444444444444"),
            targetName: "同一任务"
        )
        let changed = PersistentAIJobPayload(
            prompt: prefix + "中间-B" + suffix,
            userMessage: "同一个问题",
            sessionID: UUID(uuidString: "44444444-4444-4444-4444-444444444444"),
            targetName: "同一任务"
        )

        let first = PersistentAIJobFingerprintBuilder.fingerprint(kind: .analysisSession, payload: base)
        let second = PersistentAIJobFingerprintBuilder.fingerprint(kind: .analysisSession, payload: changed)

        XCTAssert(first != second)
    }

    func testFingerprintDetectsCoverageScopeChangesWithoutEncodingWholeCoveragePayload() {
        let sharedID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let reportID = UUID(uuidString: "66666666-6666-6666-6666-666666666666") ?? UUID()
        let report = AnalysisCoverageReportSnapshot(
            reportID: reportID,
            reportName: "大表",
            sourceFormat: .csv,
            shape: .detail,
            kind: .generic,
            rowCount: 10_000,
            columnCount: 12,
            metricCount: 4,
            timeColumnCount: 1,
            sentRows: 500,
            sentColumns: 8,
            sentMetrics: 4,
            dataMode: "sample",
            fieldNames: ["周期", "交易人数", "交易金额"],
            metricNames: ["交易人数", "交易金额"],
            timeColumnNames: ["周期"],
            omittedRowsDescription: "仅发送样本",
            omittedColumnsDescription: "",
            excludedPeriods: [],
            coreMetricNames: ["交易人数"],
            limitations: ["样本限制"]
        )
        let coverageA = AnalysisCoverageSnapshot(
            id: sharedID ?? UUID(),
            createdAt: createdAt,
            userRequest: "分析交易人数",
            reportSnapshots: [report],
            knowledgeEntryCount: 1,
            confluencePageCount: 0,
            referenceItemCount: 0,
            correctionMemoryCount: 0
        )
        let coverageB = AnalysisCoverageSnapshot(
            id: sharedID ?? UUID(),
            createdAt: createdAt,
            userRequest: "分析交易人数",
            reportSnapshots: [report],
            knowledgeEntryCount: 2,
            confluencePageCount: 0,
            referenceItemCount: 0,
            correctionMemoryCount: 0
        )
        let payloadA = PersistentAIJobPayload(
            prompt: "同一个 prompt",
            userMessage: "同一个问题",
            sessionID: UUID(uuidString: "77777777-7777-7777-7777-777777777777"),
            targetName: "同一任务",
            coverageSnapshot: coverageA
        )
        let payloadB = PersistentAIJobPayload(
            prompt: "同一个 prompt",
            userMessage: "同一个问题",
            sessionID: UUID(uuidString: "77777777-7777-7777-7777-777777777777"),
            targetName: "同一任务",
            coverageSnapshot: coverageB
        )

        let first = PersistentAIJobFingerprintBuilder.fingerprint(kind: .analysisSession, payload: payloadA)
        let second = PersistentAIJobFingerprintBuilder.fingerprint(kind: .analysisSession, payload: payloadB)

        XCTAssert(first != second)
        XCTAssert(!first.contains("大表"))
        XCTAssert(!second.contains("大表"))
    }
}
