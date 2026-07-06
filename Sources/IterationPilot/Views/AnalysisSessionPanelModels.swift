import Foundation

enum SessionContextPanel: String, CaseIterable, Identifiable {
    case reports = "分析资料"
    case audit = "审核与口径"
    case quality = "数据质检"
    case coverage = "数据覆盖"
    case computation = "计算证据"
    case jobs = "AI 任务"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .reports: return "tray.and.arrow.down"
        case .audit: return "checklist.checked"
        case .quality: return "checkmark.seal"
        case .coverage: return "eye"
        case .computation: return "function"
        case .jobs: return "clock.arrow.circlepath"
        }
    }
}

extension String {
    func scopePreviewLine(limit: Int) -> String {
        let collapsed = replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let boundary = collapsed.index(collapsed.startIndex, offsetBy: limit, limitedBy: collapsed.endIndex) else {
            return collapsed
        }
        guard boundary < collapsed.endIndex else { return collapsed }
        return String(collapsed[..<boundary]) + "..."
    }
}

enum PendingReportGenerationKind: String, Identifiable {
    case full
    case simple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: return "生成完整汇报"
        case .simple: return "生成简洁汇报"
        }
    }

    var subtitle: String {
        switch self {
        case .full:
            return "用于正式复盘和经营汇报，会覆盖范围内的问题、数据证据、风险和建议。"
        case .simple:
            return "用于日常汇报，只保留周期内数据变化、原因分析和动作建议。"
        }
    }
}

struct SessionHeaderRenderState {
    var selectedReportCount: Int
    var hasAIReply: Bool
    var hasAnalysis: Bool
    var hasEvidence: Bool
    var hasReport: Bool
    var hasSimpleReport: Bool
    var hasOpportunities: Bool
    var activeJob: LiveAIJobSnapshot?
    var reportRequirementCount: Int
    var businessSpaceName: String
    var taskName: String
    var hasConfiguredAI: Bool

    var hasBlockingAI: Bool { activeJob != nil }
    var isAnalysisRunning: Bool { activeJob?.kind == .analysisSession }
    var isReportGenerating: Bool { activeJob?.kind == .memo }
    var isSimpleReportGenerating: Bool { activeJob?.kind == .simpleReportGeneration }
}

struct ReportSelectionPanelSnapshot {
    var task: AnalysisTask?
    var currentReports: [ImportedReport]
    var unassignedVisibleReports: [ImportedReport]
    var unassignedCount: Int
}

struct AnalysisCoveragePanelSnapshot {
    var sessionID: UUID?
    var packID: UUID?
    var reports: [ImportedReport]
    var relatedRuns: [ExternalReferenceCollectionRun]
    var requirementDigest: ReportRequirementDigest
    var scopedKnowledgeCount: Int
    var confluencePageCount: Int
    var scopedReferenceCount: Int
    var scopedCorrectionCount: Int
    var scopedCandidateCount: Int

    static let empty = AnalysisCoveragePanelSnapshot(
        sessionID: nil,
        packID: nil,
        reports: [],
        relatedRuns: [],
        requirementDigest: ReportRequirementDigest(),
        scopedKnowledgeCount: 0,
        confluencePageCount: 0,
        scopedReferenceCount: 0,
        scopedCorrectionCount: 0,
        scopedCandidateCount: 0
    )
}

struct AnalysisCoveragePanelRevision: Equatable {
    var sessionID: UUID?
    var packID: UUID?
    var selectedBusinessSpaceID: UUID?
    var sessionHash: Int
    var packHash: Int
    var referenceCollectionRunHash: Int
    var knowledgeHash: Int
    var referenceSourceHash: Int
    var referenceItemHash: Int
    var correctionMemoryHash: Int
    var smartCandidateHash: Int
    var confluencePageCount: Int
}

struct AnalysisCoveragePanelChangeKey: Equatable {
    var panel: SessionContextPanel
    var revision: AnalysisCoveragePanelRevision?
}
