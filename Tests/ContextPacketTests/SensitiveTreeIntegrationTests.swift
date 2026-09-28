import XCTest
@testable import ContextPacketCore

final class SensitiveTreeIntegrationTests: XCTestCase {
    var repoURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        repoURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)

        // Initialize a real git repo
        _ = try await runProcess(executable: "/usr/bin/git", arguments: ["init"], at: repoURL)
        _ = try await runProcess(executable: "/usr/bin/git", arguments: ["config", "user.name", "Test Runner"], at: repoURL)
        _ = try await runProcess(executable: "/usr/bin/git", arguments: ["config", "user.email", "test@example.com"], at: repoURL)

        // Initial clean commit
        let readme = repoURL.appendingPathComponent("README.md")
        try "# Test Project".write(to: readme, atomically: true, encoding: .utf8)
        _ = try await runProcess(executable: "/usr/bin/git", arguments: ["add", "README.md"], at: repoURL)
        _ = try await runProcess(executable: "/usr/bin/git", arguments: ["commit", "-m", "Initial commit"], at: repoURL)
    }

    override func tearDown() async throws {
        if let url = repoURL {
            try? FileManager.default.removeItem(at: url)
        }
        try await super.tearDown()
    }

    func testRepositoryWithOnlyEnvChangesIsNotCleanAndDisclosesOmissionWithoutLeakingPaths() async throws {
        // Create only a sensitive file change (.env)
        let envFile = repoURL.appendingPathComponent(".env")
        try "DATABASE_PASSWORD=secret123".write(to: envFile, atomically: true, encoding: .utf8)

        let analyzer = RepositoryAnalyzer()
        let snapshot = try await analyzer.analyze(repositoryURL: repoURL)

        // 1. Separate state verification
        XCTAssertTrue(snapshot.isGitDirty, "Actual Git dirty state must be true")
        XCTAssertEqual(snapshot.visibleSafeChangesCount, 0, "No safe visible changes should be listed")
        XCTAssertEqual(snapshot.visibleSafeChanges.count, 0)
        XCTAssertEqual(snapshot.hiddenSensitiveChangesCount, 1, "Should record 1 hidden sensitive change")
        XCTAssertTrue(snapshot.hasOmittedSensitiveChanges, "Should mark that sensitive changes were omitted")

        // 2. Must NEVER appear clean
        XCTAssertFalse(snapshot.isClean, "Repository with .env changes must NOT appear clean")

        // 3. Sensitive paths must NEVER be revealed
        XCTAssertFalse(snapshot.allChangedFilePaths.contains(".env"))
        XCTAssertFalse(snapshot.allChangedFilePaths.contains(envFile.path))

        // 4. Exporter rendering verification
        let exportService = ContextExportService()
        let handoff = exportService.buildHandoff(
            from: snapshot,
            session: nil,
            importantFiles: [],
            isStale: false,
            stalenessReason: nil
        )

        let exportedMarkdown = exportService.renderMarkdown(for: handoff, provider: "generic", mode: .standard)

        // Must render clear disclosure
        XCTAssertTrue(exportedMarkdown.contains("> Working tree contains sensitive changes omitted from the packet."))
        // Must NEVER claim working tree is clean
        XCTAssertFalse(exportedMarkdown.contains("Working tree: clean"))
        // Must NEVER expose the sensitive path or secret value
        XCTAssertFalse(exportedMarkdown.contains(".env"))
        XCTAssertFalse(exportedMarkdown.contains("DATABASE_PASSWORD"))
        XCTAssertFalse(exportedMarkdown.contains("secret123"))
    }

    private func runProcess(executable: String, arguments: [String], at directory: URL) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
