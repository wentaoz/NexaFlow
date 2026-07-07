import Foundation

enum NetworkTimeouts {
    static let longRequest: TimeInterval = 180
    static let aiRequest: TimeInterval = 180
    static let analysisIntentRequest: TimeInterval = 60
    static let externalReferenceRequest: TimeInterval = 30
    static let referenceIntelligenceRequest: TimeInterval = 45
    static let referenceCollectionRunBudget: TimeInterval = 180
    static let reportReferenceCollectionWaitBudget: TimeInterval = 90

    static let maxReferenceIntelligenceItemsPerRun = 30
    static let analysisFullContextSourceLimit = 12
    static let reportGenerationSourceLimit = 16
}
