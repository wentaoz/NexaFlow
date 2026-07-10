import Foundation
import XCTest
@testable import IterationPilotCore

final class ReliabilityTests: XCTestCase {
    @MainActor
    func testExplicitWorkspaceFlushWaitsForDiskWrite() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexaflow-workspace-flush-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let workspaceURL = directory.appendingPathComponent("workspace.json")
        let namespace = "test-\(UUID().uuidString)"
        setenv("NEXAFLOW_WORKSPACE_PATH", workspaceURL.path, 1)
        setenv("NEXAFLOW_SECURE_STORAGE_NAMESPACE", namespace, 1)
        defer {
            unsetenv("NEXAFLOW_SECURE_STORAGE_NAMESPACE")
            unsetenv("NEXAFLOW_WORKSPACE_PATH")
        }

        var workspace = SampleDataFactory.makeWorkspace()
        let marker = "flush-\(UUID().uuidString)"
        workspace.businessSpaces[0].name = marker
        let store = ProductWorkflowStore(debugSnapshotWorkspace: workspace)

        let didFlush = await store.flushWorkspaceToDisk()
        XCTAssertTrue(didFlush)
        let loaded = try XCTUnwrap(ProductWorkflowStore.loadWorkspace())
        XCTAssertEqual(loaded.businessSpaces.first?.name, marker)
    }

    func testExternalReferenceCollectorHonorsExpiredDeadline() async throws {
        let source = try XCTUnwrap(ExternalReferenceSource.defaults.first)
        let result = try await ExternalReferenceCollector().collectDetailed(
            sources: [source],
            searchSettings: .default,
            collectionRunID: UUID(),
            deadline: .distantPast
        )

        XCTAssertTrue(result.timedOut)
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertTrue(result.sourceLogs.isEmpty)
    }

    func testWorkspaceSchemaOneMigratesToCurrentVersion() throws {
        var workspace = SampleDataFactory.makeWorkspace()
        workspace.schemaVersion = 1

        try ProductWorkflowStore.migrateWorkspaceToCurrentSchema(&workspace)

        XCTAssertEqual(workspace.schemaVersion, ProductWorkspace.currentSchemaVersion)
    }

    func testFutureWorkspaceVersionIsRejectedWithoutChangingOriginalFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexaflow-future-workspace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let workspaceURL = directory.appendingPathComponent("workspace.json")
        setenv("NEXAFLOW_WORKSPACE_PATH", workspaceURL.path, 1)
        setenv("NEXAFLOW_SECURE_STORAGE_NAMESPACE", "test-\(UUID().uuidString)", 1)
        defer {
            unsetenv("NEXAFLOW_SECURE_STORAGE_NAMESPACE")
            unsetenv("NEXAFLOW_WORKSPACE_PATH")
        }

        var workspace = SampleDataFactory.makeWorkspace()
        workspace.schemaVersion = ProductWorkspace.currentSchemaVersion + 1
        try ProductWorkflowStore.saveWorkspace(workspace)
        let originalData = try Data(contentsOf: workspaceURL)

        guard case .unsupportedVersion(let found, let supported) = ProductWorkflowStore.loadWorkspaceResult() else {
            return XCTFail("Expected unsupported workspace version result")
        }
        XCTAssertEqual(found, ProductWorkspace.currentSchemaVersion + 1)
        XCTAssertEqual(supported, ProductWorkspace.currentSchemaVersion)
        XCTAssertEqual(try Data(contentsOf: workspaceURL), originalData)
    }

    func testCorruptWorkspaceCreatesBackupAndReturnsCorruptResult() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexaflow-corrupt-workspace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let workspaceURL = directory.appendingPathComponent("workspace.json")
        try "{ invalid json".write(to: workspaceURL, atomically: true, encoding: .utf8)
        setenv("NEXAFLOW_WORKSPACE_PATH", workspaceURL.path, 1)
        defer { unsetenv("NEXAFLOW_WORKSPACE_PATH") }

        let result = ProductWorkflowStore.loadWorkspaceResult()
        guard case .corrupt(_, let backupURL) = result else {
            throw RegressionTestFailure(message: "Expected corrupt workspace result", file: #filePath, line: #line)
        }
        let backup = try XCTUnwrap(backupURL)
        XCTAssert(FileManager.default.fileExists(atPath: backup.path), "Expected corrupt workspace backup file")
        let originalText = try String(contentsOf: workspaceURL, encoding: .utf8)
        XCTAssert(originalText == "{ invalid json", "Original corrupt workspace should be preserved")
    }

    func testWorkspaceSaveAndLoadRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexaflow-workspace-roundtrip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let workspaceURL = directory.appendingPathComponent("workspace.json")
        setenv("NEXAFLOW_WORKSPACE_PATH", workspaceURL.path, 1)
        setenv("NEXAFLOW_SECURE_STORAGE_NAMESPACE", "test-\(UUID().uuidString)", 1)
        defer {
            unsetenv("NEXAFLOW_SECURE_STORAGE_NAMESPACE")
            unsetenv("NEXAFLOW_WORKSPACE_PATH")
        }

        let workspace = SampleDataFactory.makeWorkspace()
        try ProductWorkflowStore.saveWorkspace(workspace)
        let loaded = try XCTUnwrap(ProductWorkflowStore.loadWorkspace())
        XCTAssert(loaded.dataPacks.count == workspace.dataPacks.count)
        XCTAssert(loaded.businessSpaces.count == workspace.businessSpaces.count)
    }

    func testWorkspaceSaveMovesAIAPIKeyOutOfJSON() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexaflow-workspace-secret-scrub-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let workspaceURL = directory.appendingPathComponent("workspace.json")
        setenv("NEXAFLOW_WORKSPACE_PATH", workspaceURL.path, 1)
        setenv("NEXAFLOW_SECURE_STORAGE_NAMESPACE", "test-\(UUID().uuidString)", 1)
        defer {
            AppSecureStorage.deletePassword(service: "com.nexaflow.ai-settings", account: "default-api-key")
            unsetenv("NEXAFLOW_SECURE_STORAGE_NAMESPACE")
            unsetenv("NEXAFLOW_WORKSPACE_PATH")
        }

        var workspace = SampleDataFactory.makeWorkspace()
        workspace.aiSettings.apiKey = "sk-test-secret-should-not-be-on-disk"
        try ProductWorkflowStore.saveWorkspace(workspace)

        let rawText = try String(contentsOf: workspaceURL, encoding: .utf8)
        XCTAssert(!rawText.contains("sk-test-secret-should-not-be-on-disk"))

        let rawJSON = try JSONSerialization.jsonObject(with: Data(rawText.utf8))
        let rawObject = try XCTUnwrap(rawJSON as? [String: Any])
        XCTAssert(rawObject["schemaVersion"] as? Int == ProductWorkspace.currentSchemaVersion)
        let aiSettings = try XCTUnwrap(rawObject["aiSettings"] as? [String: Any])
        XCTAssert(aiSettings["apiKey"] as? String == "")

        let loaded = try XCTUnwrap(ProductWorkflowStore.loadWorkspace())
        XCTAssert(loaded.aiSettings.apiKey == "sk-test-secret-should-not-be-on-disk")
    }

    func testWorkspaceAPIKeyDecodesAndResavesWithSecret() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexaflow-workspace-legacy-secret-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let workspaceURL = directory.appendingPathComponent("workspace.json")
        setenv("NEXAFLOW_WORKSPACE_PATH", workspaceURL.path, 1)
        setenv("NEXAFLOW_SECURE_STORAGE_NAMESPACE", "test-\(UUID().uuidString)", 1)
        defer {
            AppSecureStorage.deletePassword(service: "com.nexaflow.ai-settings", account: "default-api-key")
            unsetenv("NEXAFLOW_SECURE_STORAGE_NAMESPACE")
            unsetenv("NEXAFLOW_WORKSPACE_PATH")
        }

        let legacySecret = "sk-legacy-secret-for-migration"
        var workspace = SampleDataFactory.makeWorkspace()
        let encoded = try JSONEncoder.fixtureEncoder.encode(workspace)
        let encodedJSON = try JSONSerialization.jsonObject(with: encoded)
        var rawObject = try XCTUnwrap(encodedJSON as? [String: Any])
        var aiSettings = try XCTUnwrap(rawObject["aiSettings"] as? [String: Any])
        aiSettings["apiKey"] = legacySecret
        rawObject["aiSettings"] = aiSettings
        let legacyData = try JSONSerialization.data(withJSONObject: rawObject, options: [.sortedKeys])
        try legacyData.write(to: workspaceURL)

        workspace = try XCTUnwrap(ProductWorkflowStore.loadWorkspace())
        XCTAssert(workspace.aiSettings.apiKey == legacySecret)

        try ProductWorkflowStore.saveWorkspace(workspace)
        let savedText = try String(contentsOf: workspaceURL, encoding: .utf8)
        XCTAssert(!savedText.contains(legacySecret))
        let reloaded = try XCTUnwrap(ProductWorkflowStore.loadWorkspace())
        XCTAssert(reloaded.aiSettings.apiKey == legacySecret)
    }

    func testCancellationErrorIsNotRetryable() {
        XCTAssert(AIJobQueue.isRetryable(CancellationError()) == false)
    }

    func testUnknownErrorIsNotRetryable() {
        XCTAssert(AIJobQueue.isRetryable(NSError(domain: "internal.parse", code: 1)) == false)
    }

    func testPersistentAIRetryPolicyStopsAfterFiveDelayedRetries() {
        XCTAssertTrue(PersistentAIJobRetryPolicy.shouldScheduleRetry(isRetryable: true, delayedRetryCount: 4))
        XCTAssertFalse(PersistentAIJobRetryPolicy.shouldScheduleRetry(isRetryable: true, delayedRetryCount: 5))
        XCTAssertFalse(PersistentAIJobRetryPolicy.shouldScheduleRetry(isRetryable: false, delayedRetryCount: 0))
    }

    func testCSVParserSupportsBareCarriageReturnRows() {
        let table = CSVParser.parse("name,value\rfirst,1\rsecond,2")

        XCTAssertEqual(table.rows.count, 2)
        XCTAssertEqual(table.rows.first?["name"], "first")
        XCTAssertEqual(table.rows.last?["value"], "2")
    }

    func testCSVParserRejectsExcessiveColumnCount() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexaflow-wide-csv-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("wide.csv")
        try Array(repeating: "x", count: 20_001).joined(separator: ",")
            .write(to: fileURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CSVParser.parse(fileURL: fileURL)) { error in
            guard case ImportError.tableTooLarge = error else {
                return XCTFail("Expected tableTooLarge, got \(error)")
            }
        }
    }

    func testConfluenceRequestFailedDescriptionDoesNotExposeURLOrBody() {
        let error = ConfluenceError.requestFailed(
            statusCode: 404,
            url: "https://example.atlassian.net/wiki/rest/api/content/secret-page?token=abc",
            body: #"{"message":"permission denied","token":"secret"}"#
        )
        let description = error.localizedDescription

        XCTAssert(description.contains("HTTP 404"))
        XCTAssert(!description.contains("example.atlassian.net"))
        XCTAssert(!description.contains("secret-page"))
        XCTAssert(!description.contains("permission denied"))
        XCTAssert(!description.contains("secret"))
    }

    func testJiraRequestFailedDescriptionDoesNotExposeCredentialsOrBody() {
        let username = "owner@example.com"
        let token = "jira-token-secret"
        let encodedCredential = Data("\(username):\(token)".utf8).base64EncodedString()
        let error = JiraServiceError.requestFailed(
            statusCode: 403,
            body: "Authorization Basic \(encodedCredential); user \(username); token \(token); raw response"
        )
        let description = error.localizedDescription

        XCTAssert(description.contains("HTTP 403"))
        XCTAssert(!description.contains(encodedCredential))
        XCTAssert(!description.contains(username))
        XCTAssert(!description.contains(token))
        XCTAssert(!description.contains("raw response"))
    }
}

private extension JSONEncoder {
    static var fixtureEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
