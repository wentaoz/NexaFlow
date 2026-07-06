import CryptoKit
import Foundation

enum PersistentAIJobFingerprintBuilder {
    private static let separator = "\u{1f}"

    static func fingerprint(kind: PersistentAIJobKind, payload: PersistentAIJobPayload) -> String {
        let parts = canonicalParts(kind: kind, payload: payload)
        return "v2:\(sha256Hex(parts.joined(separator: separator)))"
    }

    static func canonicalParts(kind: PersistentAIJobKind, payload: PersistentAIJobPayload) -> [String] {
        [
            "kind:\(kind.rawValue)",
            "messageID:\(optionalUUID(payload.messageID))",
            "sessionID:\(optionalUUID(payload.sessionID))",
            "packID:\(optionalUUID(payload.packID))",
            "taskID:\(optionalUUID(payload.taskID))",
            "reportID:\(optionalUUID(payload.reportID))",
            "businessSpaceID:\(optionalUUID(payload.businessSpaceID))",
            "contextMode:\(payload.contextMode?.rawValue ?? "")",
            "contextSourcePolicy:\(payload.contextSourcePolicy?.rawValue ?? "")",
            textDigest("targetName", payload.targetName),
            textDigest("prompt", payload.prompt),
            textDigest("userMessage", payload.userMessage),
            textDigest("aiOutput", payload.aiOutput),
            reportScopeSignature(payload.reportScope),
            coverageSignature(payload.coverageSnapshot)
        ]
    }

    private static func coverageSignature(_ coverage: AnalysisCoverageSnapshot?) -> String {
        guard let coverage else { return "coverage:nil" }
        let reportParts = coverage.reportSnapshots
            .sorted { lhs, rhs in lhs.reportID.uuidString < rhs.reportID.uuidString }
            .map(reportSignature)
            .joined(separator: separator)
        let parts = [
            "coverageID:\(coverage.id.uuidString)",
            "coverageCreatedAt:\(dateMilliseconds(coverage.createdAt))",
            textDigest("coverageUserRequest", coverage.userRequest),
            "coverageContextMode:\(coverage.contextMode?.rawValue ?? "")",
            textDigest("coverageStrategy", coverage.contextStrategyDescription ?? ""),
            periodIntentSignature(coverage.periodIntent),
            evidenceWindowSignature(coverage.externalEvidenceWindow),
            externalEvidenceSignature(coverage.externalEvidenceCoverage),
            "externalEvidenceMatchedCount:\(coverage.externalEvidenceMatchedCount.map(String.init) ?? "")",
            "externalEvidencePublishedOnlyCount:\(coverage.externalEvidencePublishedOnlyCount.map(String.init) ?? "")",
            "externalEvidenceCollectedOnlyCount:\(coverage.externalEvidenceCollectedOnlyCount.map(String.init) ?? "")",
            "metricLinkageAnomalyCount:\(coverage.metricLinkageAnomalies?.count ?? 0)",
            "scannedMetricCount:\(coverage.scannedMetricCount.map(String.init) ?? "")",
            "totalReports:\(coverage.totalReports)",
            "totalRows:\(coverage.totalRows)",
            "totalColumns:\(coverage.totalColumns)",
            "totalMetrics:\(coverage.totalMetrics)",
            "totalTimeColumns:\(coverage.totalTimeColumns)",
            "excludedPeriodCount:\(coverage.excludedPeriodCount)",
            "profileOnlyReportCount:\(coverage.profileOnlyReportCount)",
            "knowledgeEntryCount:\(coverage.knowledgeEntryCount)",
            "confluencePageCount:\(coverage.confluencePageCount)",
            "jiraProjectEvidenceCount:\(coverage.jiraProjectEvidenceCount.map(String.init) ?? "")",
            "referenceItemCount:\(coverage.referenceItemCount)",
            "correctionMemoryCount:\(coverage.correctionMemoryCount)",
            listDigest("coverageLimitations", coverage.limitations),
            "reports:\(sha256Hex(reportParts))"
        ]
        return "coverage:\(sha256Hex(parts.joined(separator: separator)))"
    }

    private static func reportSignature(_ report: AnalysisCoverageReportSnapshot) -> String {
        [
            "id:\(report.id.uuidString)",
            "reportID:\(report.reportID.uuidString)",
            textDigest("reportName", report.reportName),
            "sourceFormat:\(report.sourceFormat.rawValue)",
            "shape:\(report.shape.rawValue)",
            "kind:\(report.kind.rawValue)",
            "rowCount:\(report.rowCount)",
            "columnCount:\(report.columnCount)",
            "metricCount:\(report.metricCount)",
            "timeColumnCount:\(report.timeColumnCount)",
            "sentRows:\(report.sentRows)",
            "sentColumns:\(report.sentColumns)",
            "sentMetrics:\(report.sentMetrics)",
            "dataMode:\(report.dataMode)",
            "rawDataMode:\(report.rawDataMode ?? "")",
            "totalRawRows:\(report.totalRawRows.map(String.init) ?? "")",
            "sentRawRows:\(report.sentRawRows.map(String.init) ?? "")",
            textDigest("rawCoverageDescription", report.rawCoverageDescription ?? ""),
            textDigest("timeAxisSummary", report.timeAxisSummary ?? ""),
            textDigest("periodCoverageSummary", report.periodCoverageSummary ?? ""),
            "latestObservedPeriod:\(report.latestObservedPeriod ?? "")",
            "primaryComparisonPeriod:\(report.primaryComparisonPeriod ?? "")",
            "downgradedMetricCount:\(report.downgradedMetricCount)",
            "trendAnalysisVersion:\(report.trendAnalysisVersion.map(String.init) ?? "")",
            listDigest("fieldNames", report.fieldNames),
            listDigest("metricNames", report.metricNames),
            listDigest("timeColumnNames", report.timeColumnNames),
            textDigest("omittedRowsDescription", report.omittedRowsDescription),
            textDigest("omittedColumnsDescription", report.omittedColumnsDescription),
            listDigest("excludedPeriods", report.excludedPeriods),
            listDigest("coreMetricNames", report.coreMetricNames),
            listDigest("limitations", report.limitations)
        ].joined(separator: separator)
    }

    private static func periodIntentSignature(_ intent: AnalysisPeriodIntent?) -> String {
        guard let intent else { return "periodIntent:nil" }
        return [
            "periodSource:\(intent.source.rawValue)",
            textDigest("periodSummary", intent.summary),
            listDigest("requestedPeriods", intent.requestedPeriods),
            listDigest("excludedPeriods", intent.excludedPeriods),
            "isUserSpecified:\(intent.isUserSpecified)",
            "allowsIncompletePeriod:\(intent.allowsIncompletePeriod)",
            listDigest("warnings", intent.warnings)
        ].joined(separator: separator)
    }

    private static func evidenceWindowSignature(_ window: ExternalEvidenceWindow?) -> String {
        guard let window else { return "externalEvidenceWindow:nil" }
        return [
            "analysisStartDate:\(optionalDate(window.analysisStartDate))",
            "analysisEndDate:\(optionalDate(window.analysisEndDate))",
            "comparisonStartDate:\(optionalDate(window.comparisonStartDate))",
            "comparisonEndDate:\(optionalDate(window.comparisonEndDate))",
            "userSpecifiedPeriod:\(window.userSpecifiedPeriod)",
            "timeZone:\(window.timeZone)"
        ].joined(separator: separator)
    }

    private static func externalEvidenceSignature(_ coverage: ExternalEvidenceCoverageSnapshot?) -> String {
        guard let coverage else { return "externalEvidenceCoverage:nil" }
        return [
            "searchTriggered:\(coverage.searchTriggered)",
            textDigest("reason", coverage.reason),
            "enabledSourceCount:\(coverage.enabledSourceCount)",
            "collectableSourceCount:\(coverage.collectableSourceCount.map(String.init) ?? "")",
            "skippedSourceCount:\(coverage.skippedSourceCount.map(String.init) ?? "")",
            listDigest("skippedSourceReasons", coverage.skippedSourceReasons ?? []),
            "candidateSourceCount:\(coverage.candidateSourceCount)",
            "tavilySourceCount:\(coverage.tavilySourceCount)",
            "cachedMatchedItemCount:\(coverage.cachedMatchedItemCount)",
            "recentCollectedItemCount:\(coverage.recentCollectedItemCount)",
            "competitorItemCount:\(coverage.competitorItemCount)",
            "newsLikeItemCount:\(coverage.newsLikeItemCount)",
            "policyItemCount:\(coverage.policyItemCount)",
            "marketItemCount:\(coverage.marketItemCount)",
            "externalEventItemCount:\(coverage.externalEventItemCount)",
            listDigest("sourceNames", coverage.sourceNames.sorted())
        ].joined(separator: separator)
    }

    private static func reportScopeSignature(_ scope: ReportGenerationScope?) -> String {
        guard let scope else { return "reportScope:nil" }
        return [
            "reportScopeKind:\(scope.kind.rawValue)",
            "selectedQuestionIDs:\(scope.selectedQuestionIDs.map(\.uuidString).sorted().joined(separator: ","))",
            listDigest("selectedQuestionTexts", scope.selectedQuestionTexts),
            "selectedQuestionID:\(optionalUUID(scope.selectedQuestionID))",
            textDigest("selectedQuestionText", scope.selectedQuestionText),
            textDigest("customPeriodText", scope.customPeriodText)
        ].joined(separator: separator)
    }

    private static func textDigest(_ label: String, _ value: String) -> String {
        "\(label):\(value.utf8.count):\(sha256Hex(value))"
    }

    private static func listDigest(_ label: String, _ values: [String]) -> String {
        "\(label):\(values.count):\(sha256Hex(values.joined(separator: separator)))"
    }

    private static func optionalUUID(_ value: UUID?) -> String {
        value?.uuidString ?? ""
    }

    private static func optionalDate(_ value: Date?) -> String {
        value.map(dateMilliseconds).map(String.init) ?? ""
    }

    private static func dateMilliseconds(_ value: Date) -> Int64 {
        Int64((value.timeIntervalSince1970 * 1_000).rounded())
    }

    private static func sha256Hex(_ value: String) -> String {
        sha256Hex(Data(value.utf8))
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
