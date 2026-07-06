import Foundation
@testable import IterationPilotCore

final class ReliabilityTests: XCTestCase {
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
        defer { unsetenv("NEXAFLOW_WORKSPACE_PATH") }

        let workspace = SampleDataFactory.makeWorkspace()
        try ProductWorkflowStore.saveWorkspace(workspace)
        let loaded = try XCTUnwrap(ProductWorkflowStore.loadWorkspace())
        XCTAssert(loaded.dataPacks.count == workspace.dataPacks.count)
        XCTAssert(loaded.businessSpaces.count == workspace.businessSpaces.count)
    }

    func testWorkspaceSavePersistsAIAPIKey() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexaflow-workspace-secret-scrub-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let workspaceURL = directory.appendingPathComponent("workspace.json")
        setenv("NEXAFLOW_WORKSPACE_PATH", workspaceURL.path, 1)
        defer { unsetenv("NEXAFLOW_WORKSPACE_PATH") }

        var workspace = SampleDataFactory.makeWorkspace()
        workspace.aiSettings.apiKey = "sk-test-secret-should-not-be-on-disk"
        try ProductWorkflowStore.saveWorkspace(workspace)

        let rawText = try String(contentsOf: workspaceURL, encoding: .utf8)
        XCTAssert(rawText.contains("sk-test-secret-should-not-be-on-disk"))

        let rawJSON = try JSONSerialization.jsonObject(with: Data(rawText.utf8))
        let rawObject = try XCTUnwrap(rawJSON as? [String: Any])
        let aiSettings = try XCTUnwrap(rawObject["aiSettings"] as? [String: Any])
        XCTAssert(aiSettings["apiKey"] as? String == "sk-test-secret-should-not-be-on-disk")
    }

    func testWorkspaceAPIKeyDecodesAndResavesWithSecret() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexaflow-workspace-legacy-secret-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let workspaceURL = directory.appendingPathComponent("workspace.json")
        setenv("NEXAFLOW_WORKSPACE_PATH", workspaceURL.path, 1)
        defer { unsetenv("NEXAFLOW_WORKSPACE_PATH") }

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
        XCTAssert(savedText.contains(legacySecret))
    }

    func testCancellationErrorIsNotRetryable() {
        XCTAssert(AIJobQueue.isRetryable(CancellationError()) == false)
    }
}

private extension JSONEncoder {
    static var fixtureEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
