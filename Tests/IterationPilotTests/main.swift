import Foundation

var passed = 0
var failed = 0

@MainActor
func run(_ name: String, _ body: () async throws -> Void) async {
    let failureStartIndex = TestFailureRecorder.failures.count
    do {
        try await body()
        let newFailures = Array(TestFailureRecorder.failures.dropFirst(failureStartIndex))
        if newFailures.isEmpty {
            passed += 1
            print("PASS \(name)")
        } else {
            failed += 1
            print("FAIL \(name)")
            for failure in newFailures {
                print("  \(failure)")
            }
        }
    } catch {
        failed += 1
        print("FAIL \(name): \(error)")
    }
}

let answer = AnalysisAnswerPresentationTests()
await run("AnalysisAnswerPresentationTests.testParsesDirectAnswerAndMovesSupportingSectionsOutOfChatBody") { try answer.testParsesDirectAnswerAndMovesSupportingSectionsOutOfChatBody() }
await run("AnalysisAnswerPresentationTests.testReturnsNilForLegacyMessagesWithoutDirectAnswerHeading") { answer.testReturnsNilForLegacyMessagesWithoutDirectAnswerHeading() }
await run("AnalysisAnswerPresentationTests.testAcceptsDirectAnswerSynonymHeading") { try answer.testAcceptsDirectAnswerSynonymHeading() }
await run("AnalysisAnswerPresentationTests.testHandlesReorderedSupportingSections") { try answer.testHandlesReorderedSupportingSections() }
await run("AnalysisAnswerPresentationTests.testAcceptsHeadingWithoutSpaceAfterHashes") { try answer.testAcceptsHeadingWithoutSpaceAfterHashes() }

let reliability = ReliabilityTests()
await run("ReliabilityTests.testCorruptWorkspaceCreatesBackupAndReturnsCorruptResult") { try reliability.testCorruptWorkspaceCreatesBackupAndReturnsCorruptResult() }
await run("ReliabilityTests.testWorkspaceSaveAndLoadRoundTrip") { try reliability.testWorkspaceSaveAndLoadRoundTrip() }
await run("ReliabilityTests.testWorkspaceSaveMovesAIAPIKeyOutOfJSON") { try reliability.testWorkspaceSaveMovesAIAPIKeyOutOfJSON() }
await run("ReliabilityTests.testWorkspaceAPIKeyDecodesAndResavesWithSecret") { try reliability.testWorkspaceAPIKeyDecodesAndResavesWithSecret() }
await run("ReliabilityTests.testCancellationErrorIsNotRetryable") { reliability.testCancellationErrorIsNotRetryable() }
await run("ReliabilityTests.testUnknownErrorIsNotRetryable") { reliability.testUnknownErrorIsNotRetryable() }
await run("ReliabilityTests.testConfluenceRequestFailedDescriptionDoesNotExposeURLOrBody") { reliability.testConfluenceRequestFailedDescriptionDoesNotExposeURLOrBody() }
await run("ReliabilityTests.testJiraRequestFailedDescriptionDoesNotExposeCredentialsOrBody") { reliability.testJiraRequestFailedDescriptionDoesNotExposeCredentialsOrBody() }

let aiScenarios = AIRequestScenarioTests()
await run("AIRequestScenarioTests.testAIAnalysisServiceReturnsContentFromMockEndpoint") { try await aiScenarios.testAIAnalysisServiceReturnsContentFromMockEndpoint() }
await run("AIRequestScenarioTests.testAIStreamingServiceReturnsIncrementalEvents") { try await aiScenarios.testAIStreamingServiceReturnsIncrementalEvents() }
await run("AIRequestScenarioTests.testStreamingTextJobRetriesWithCorrectionPrompt") { try await aiScenarios.testStreamingTextJobRetriesWithCorrectionPrompt() }
await run("AIRequestScenarioTests.testTextJobRetriesAfterTimeoutErrorAndEventuallySucceeds") { try await aiScenarios.testTextJobRetriesAfterTimeoutErrorAndEventuallySucceeds() }
await run("AIRequestScenarioTests.testTextJobDoesNotRetryOnNonRetryableHTTPError") { try await aiScenarios.testTextJobDoesNotRetryOnNonRetryableHTTPError() }

let productExperience = ProductExperienceTests()
await run("ProductExperienceTests.testDemoWorkspaceContainsSelectedAnalyzableReports") { try productExperience.testDemoWorkspaceContainsSelectedAnalyzableReports() }
await run("ProductExperienceTests.testLegacyWorkspaceDefaultsExperienceFieldsWithoutShowingOnboarding") { try productExperience.testLegacyWorkspaceDefaultsExperienceFieldsWithoutShowingOnboarding() }
await run("ProductExperienceTests.testOpportunityLegacyDecodeInfersWorkflowStatus") { try productExperience.testOpportunityLegacyDecodeInfersWorkflowStatus() }
await run("ProductExperienceTests.testOpportunityActionFieldsRoundTrip") { try productExperience.testOpportunityActionFieldsRoundTrip() }
await run("ProductExperienceTests.testReportPreflightBlocksEmptyAndPlaceholderContent") { productExperience.testReportPreflightBlocksEmptyAndPlaceholderContent() }
await run("ProductExperienceTests.testReportPreflightAcceptsStructuredEvidenceReport") { productExperience.testReportPreflightAcceptsStructuredEvidenceReport() }
await run("ProductExperienceTests.testReportTemplateRendererAddsTitleAndOrganization") { productExperience.testReportTemplateRendererAddsTitleAndOrganization() }
await run("ProductExperienceTests.testReportTemplateRendererKeepsOrganizationBelowExistingTitle") { productExperience.testReportTemplateRendererKeepsOrganizationBelowExistingTitle() }
await run("ProductExperienceTests.testReportTemplateRendererAppliesSectionOrderAndVisibility") { try productExperience.testReportTemplateRendererAppliesSectionOrderAndVisibility() }
await run("ProductExperienceTests.testVersionComparisonHandlesReleaseSuffixes") { productExperience.testVersionComparisonHandlesReleaseSuffixes() }
await run("ProductExperienceTests.testWorkspaceTransferRoundTripPreservesExperienceData") { try productExperience.testWorkspaceTransferRoundTripPreservesExperienceData() }
await run("ProductExperienceTests.testReportPDFExporterCreatesReadablePDF") { try productExperience.testReportPDFExporterCreatesReadablePDF() }
await run("ProductExperienceTests.testDiagnosticBundleExporterCreatesZIP") { try productExperience.testDiagnosticBundleExporterCreatesZIP() }

let persistentFingerprint = PersistentAIJobFingerprintTests()
await run("PersistentAIJobFingerprintTests.testFingerprintIsStableAndDoesNotExposeRawPayloadText") { persistentFingerprint.testFingerprintIsStableAndDoesNotExposeRawPayloadText() }
await run("PersistentAIJobFingerprintTests.testFingerprintDetectsLargePromptMiddleChanges") { persistentFingerprint.testFingerprintDetectsLargePromptMiddleChanges() }
await run("PersistentAIJobFingerprintTests.testFingerprintDetectsCoverageScopeChangesWithoutEncodingWholeCoveragePayload") { persistentFingerprint.testFingerprintDetectsCoverageScopeChangesWithoutEncodingWholeCoveragePayload() }

let traceTimeline = AnalysisTraceTimelineTests()
await run("AnalysisTraceTimelineTests.testTraceTimelineBuilderMergesJobHarnessAndNumberTraceEvents") { traceTimeline.testTraceTimelineBuilderMergesJobHarnessAndNumberTraceEvents() }

let harness = AnalysisHarnessTests()
await run("AnalysisHarnessTests.testTableManifestBuilderDetectsMetricAndRateColumns") { try harness.testTableManifestBuilderDetectsMetricAndRateColumns() }
await run("AnalysisHarnessTests.testPlanValidatorBlocksMissingFieldAndRateSum") { try harness.testPlanValidatorBlocksMissingFieldAndRateSum() }
await run("AnalysisHarnessTests.testMetricExecutorComputesSumAndGroupedLongTable") { try harness.testMetricExecutorComputesSumAndGroupedLongTable() }
await run("AnalysisHarnessTests.testMetricExecutorDoesNotCrashWhenDerivedMetricReferencesGroupedResults") { try harness.testMetricExecutorDoesNotCrashWhenDerivedMetricReferencesGroupedResults() }
await run("AnalysisHarnessTests.testNormalizedFactTableHandlesSemiPivotMetricPeriodValueSheets") { try harness.testNormalizedFactTableHandlesSemiPivotMetricPeriodValueSheets() }
await run("AnalysisHarnessTests.testNormalizedFactAnalyzerComputesH1H2BaseDerivedAndGrowth") { try harness.testNormalizedFactAnalyzerComputesH1H2BaseDerivedAndGrowth() }
await run("AnalysisHarnessTests.testDerivedOnlyQuestionKeepsSupportingMetricsOutOfMainAnswer") { try harness.testDerivedOnlyQuestionKeepsSupportingMetricsOutOfMainAnswer() }
await run("AnalysisHarnessTests.testAIIntentForPeopleAndCountQuestionComputesBothMetricsWithoutLocalCauseGuess") { try harness.testAIIntentForPeopleAndCountQuestionComputesBothMetricsWithoutLocalCauseGuess() }
await run("AnalysisHarnessTests.testOrchestratorBlocksIntentParsingWithoutAISettings") { try await harness.testOrchestratorBlocksIntentParsingWithoutAISettings() }
await run("AnalysisHarnessTests.testAnalysisIntentParserRequiresAPIKeyBeforeLocalCalculation") { try await harness.testAnalysisIntentParserRequiresAPIKeyBeforeLocalCalculation() }
await run("AnalysisHarnessTests.testAnalysisIntentParserBlocksUnmappedAIMetrics") { try await harness.testAnalysisIntentParserBlocksUnmappedAIMetrics() }
await run("AnalysisHarnessTests.testNormalizedFactAnalyzerDoesNotMergeOtherPeopleMetricsIntoTradePeople") { try harness.testNormalizedFactAnalyzerDoesNotMergeOtherPeopleMetricsIntoTradePeople() }
await run("AnalysisHarnessTests.testNormalizedFactAnalyzerUsesMetricIdentitySystemAcrossBusinessDomains") { try harness.testNormalizedFactAnalyzerUsesMetricIdentitySystemAcrossBusinessDomains() }
await run("AnalysisHarnessTests.testNormalizedFactAnalyzerRequiresAIIntentInsteadOfLocalGenericGuess") { try harness.testNormalizedFactAnalyzerRequiresAIIntentInsteadOfLocalGenericGuess() }
await run("AnalysisHarnessTests.testNormalizedFactTableForwardFillsBlankPeriodsFromRealLocalLifeShape") { try harness.testNormalizedFactTableForwardFillsBlankPeriodsFromRealLocalLifeShape() }
await run("AnalysisHarnessTests.testNormalizedFactAnalyzerChoosesTableWithRequestedTradeMetrics") { try harness.testNormalizedFactAnalyzerChoosesTableWithRequestedTradeMetrics() }
await run("AnalysisHarnessTests.testBlockedOutputHidesRawValidationCodesFromPrimaryAnswer") { harness.testBlockedOutputHidesRawValidationCodesFromPrimaryAnswer() }
await run("AnalysisHarnessTests.testOrchestratorBlocksIntentParsingWithoutLocalTradeMetricFallback") { try await harness.testOrchestratorBlocksIntentParsingWithoutLocalTradeMetricFallback() }
await run("AnalysisHarnessTests.testOrchestratorBlocksAmbiguousMetricPeriodTablesInsteadOfGuessing") { try await harness.testOrchestratorBlocksAmbiguousMetricPeriodTablesInsteadOfGuessing() }
await run("AnalysisHarnessTests.testHarnessConfirmationDoesNotTreatAIIntentTimeoutAsTableStructureIssue") { harness.testHarnessConfirmationDoesNotTreatAIIntentTimeoutAsTableStructureIssue() }
await run("AnalysisHarnessTests.testHarnessConfirmationStillPresentsForTableUnderstandingIssue") { harness.testHarnessConfirmationStillPresentsForTableUnderstandingIssue() }
await run("AnalysisHarnessTests.testReportValidatorBlocksPlaceholderOutput") { harness.testReportValidatorBlocksPlaceholderOutput() }
await run("AnalysisHarnessTests.testReportValidatorRequiresCitationForContextEvidenceClaims") { harness.testReportValidatorRequiresCitationForContextEvidenceClaims() }
await run("AnalysisHarnessTests.testValidationDecisionKeepsRepairableReportIssuesOutOfFatalBlock") { harness.testValidationDecisionKeepsRepairableReportIssuesOutOfFatalBlock() }
await run("AnalysisHarnessTests.testValidationDisplaySummaryKeepsAuditOnlyWarningsOffMainStatus") { harness.testValidationDisplaySummaryKeepsAuditOnlyWarningsOffMainStatus() }
await run("AnalysisHarnessTests.testAnalysisOutputRepairerNormalizesHeadingAddsCitationAndDowngradesCausalClaim") { harness.testAnalysisOutputRepairerNormalizesHeadingAddsCitationAndDowngradesCausalClaim() }
await run("AnalysisHarnessTests.testReportValidatorIgnoresPlaceholderInsideUserQuestionSection") { harness.testReportValidatorIgnoresPlaceholderInsideUserQuestionSection() }
await run("AnalysisHarnessTests.testDeterministicReportIncludesContextEvidenceCitations") { harness.testDeterministicReportIncludesContextEvidenceCitations() }
await run("AnalysisHarnessTests.testOrchestratorBlocksWithoutTables") { try await harness.testOrchestratorBlocksWithoutTables() }
await run("AnalysisHarnessTests.testRouterDetectsQuickComputationButNotPureExplanation") { harness.testRouterDetectsQuickComputationButNotPureExplanation() }
await run("AnalysisHarnessTests.testRouterDetectsContextEvidenceQuestions") { harness.testRouterDetectsContextEvidenceQuestions() }
await run("AnalysisHarnessTests.testSQLLikePatternEscapesWildcardsAndStringLiterals") { harness.testSQLLikePatternEscapesWildcardsAndStringLiterals() }
await run("AnalysisHarnessTests.testReadOnlySQLValidatorBlocksDuckDBFileReaders") { harness.testReadOnlySQLValidatorBlocksDuckDBFileReaders() }
await run("AnalysisHarnessTests.testNotebookRequestedMetricSQLUsesLikeEscapeAndRuns") { try harness.testNotebookRequestedMetricSQLUsesLikeEscapeAndRuns() }
await run("AnalysisHarnessTests.testRouterDowngradesSimpleTasksButKeepsComputationsVerified") { harness.testRouterDowngradesSimpleTasksButKeepsComputationsVerified() }
await run("AnalysisHarnessTests.testPeriodIntentUsesLatestPeriodRequestBeforeStaleTaskGoal") { harness.testPeriodIntentUsesLatestPeriodRequestBeforeStaleTaskGoal() }
await run("AnalysisHarnessTests.testPeriodIntentLatestRequestDoesNotFallbackToStaleTaskGoalWhenPeriodIsUnresolved") { harness.testPeriodIntentLatestRequestDoesNotFallbackToStaleTaskGoalWhenPeriodIsUnresolved() }
await run("AnalysisHarnessTests.testMessageRenderSnapshotTracksVisibleMessageChanges") { harness.testMessageRenderSnapshotTracksVisibleMessageChanges() }
await run("AnalysisHarnessTests.testMessageCollapseThresholdsAvoidFullLengthCounting") { harness.testMessageCollapseThresholdsAvoidFullLengthCounting() }
await run("AnalysisHarnessTests.testShouldUseAnalysisHarnessSkipsSimpleFullReanalysisTasks") { harness.testShouldUseAnalysisHarnessSkipsSimpleFullReanalysisTasks() }
await run("AnalysisHarnessTests.testAnswerNumberTracerMatchesChineseCompactApproximateAndPercentNumbers") { try harness.testAnswerNumberTracerMatchesChineseCompactApproximateAndPercentNumbers() }
await run("AnalysisHarnessTests.testAnswerNumberTracerMatchesRoundedDerivedValuesAndNormalizedUnits") { try harness.testAnswerNumberTracerMatchesRoundedDerivedValuesAndNormalizedUnits() }
await run("AnalysisHarnessTests.testAnswerNumberTracerIgnoresClearlyCitedEvidenceNumbers") { try harness.testAnswerNumberTracerIgnoresClearlyCitedEvidenceNumbers() }
await run("AnalysisHarnessTests.testAnswerNumberTracerDoesNotLinkUnitConflictingAmountToPerTransactionValue") { try harness.testAnswerNumberTracerDoesNotLinkUnitConflictingAmountToPerTransactionValue() }
await run("AnalysisHarnessTests.testAnswerNumberTracerMarksCloseMultipleCandidatesAsAmbiguous") { try harness.testAnswerNumberTracerMarksCloseMultipleCandidatesAsAmbiguous() }
await run("AnalysisHarnessTests.testReportValidatorBlocksUnmatchedMainAnswerNumbers") { harness.testReportValidatorBlocksUnmatchedMainAnswerNumbers() }
await run("AnalysisHarnessTests.testReportRepairRewritesFromVerifiedResultsAndRevalidates") { harness.testReportRepairRewritesFromVerifiedResultsAndRevalidates() }
await run("AnalysisHarnessTests.testDataContractValidatorWarnsButDoesNotBlockNormalWideTableWithoutDates") { try harness.testDataContractValidatorWarnsButDoesNotBlockNormalWideTableWithoutDates() }
await run("AnalysisHarnessTests.testRootCauseInvestigatorDoesNotEmitCausalConclusionWithoutDimensions") { try harness.testRootCauseInvestigatorDoesNotEmitCausalConclusionWithoutDimensions() }
await run("AnalysisHarnessTests.testConfirmedTableUnderstandingTemplateBuildsFactsForUnusualHeaders") { try harness.testConfirmedTableUnderstandingTemplateBuildsFactsForUnusualHeaders() }
await run("AnalysisHarnessTests.testMetricAliasTemplateLetsRequestedMetricUseActualMetricName") { try harness.testMetricAliasTemplateLetsRequestedMetricUseActualMetricName() }
await run("AnalysisHarnessTests.testRootCauseInvestigatorRecordsMultiStepContributionAudit") { try harness.testRootCauseInvestigatorRecordsMultiStepContributionAudit() }
await run("AnalysisHarnessTests.testRealLocalLifeXLSXImportAndLocalHarnessAlgorithms") { try harness.testRealLocalLifeXLSXImportAndLocalHarnessAlgorithms() }

if ProcessInfo.processInfo.environment["NEXAFLOW_LIVE_AI_SMOKE"] == "1" {
    await run("AnalysisHarnessTests.testLiveAIStreamingServiceSmoke") { try await harness.testLiveAIStreamingServiceSmoke() }
    await run("AnalysisHarnessTests.testLiveHarnessAnalysisSmoke") { try await harness.testLiveHarnessAnalysisSmoke() }
}

print("Regression tests: \(passed) passed, \(failed) failed")
if failed > 0 {
    exit(1)
}
