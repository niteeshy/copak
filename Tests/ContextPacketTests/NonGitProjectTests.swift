import XCTest
@testable import ContextPacketCore

final class NonGitProjectTests: XCTestCase {
    var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("nongit-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let temp = tempDirectory {
            try? FileManager.default.removeItem(at: temp)
        }
        super.tearDown()
    }

    func testNonGitDirectoryIsAnalyzedSuccessfully() async throws {
        // Create files in the non-git directory
        let packageJson = tempDirectory.appendingPathComponent("package.json")
        try """
        {
          "name": "my-script-project",
          "version": "1.0.0"
        }
        """.write(to: packageJson, atomically: true, encoding: .utf8)

        let agentsFile = tempDirectory.appendingPathComponent("AGENTS.md")
        try "Always run npm test before handoff.".write(to: agentsFile, atomically: true, encoding: .utf8)

        let sourceFile = tempDirectory.appendingPathComponent("index.js")
        try """
        // TODO: implement caching
        console.log("hello world");
        """.write(to: sourceFile, atomically: true, encoding: .utf8)

        let analyzer = RepositoryAnalyzer()
        let snapshot = try await analyzer.analyze(repositoryURL: tempDirectory)

        // 1. Snapshot metadata verifies non-git state
        XCTAssertFalse(snapshot.isGitRepository)
        XCTAssertEqual(snapshot.branch, "non-git")
        XCTAssertNil(snapshot.headCommitHash)
        XCTAssertNil(snapshot.diffSummary)
        XCTAssertTrue(snapshot.recentCommits.isEmpty)
        XCTAssertTrue(snapshot.modifiedFiles.isEmpty)
        XCTAssertTrue(snapshot.stagedFiles.isEmpty)
        XCTAssertTrue(snapshot.untrackedFiles.isEmpty)
        XCTAssertTrue(snapshot.isClean)
        XCTAssertNil(snapshot.refreshError)

        // 2. Filesystem features work seamlessly
        XCTAssertEqual(snapshot.projectMetadata.ecosystem, "JavaScript / Node")
        XCTAssertTrue(snapshot.fileTreeSummary.contains("index.js"))
        XCTAssertEqual(snapshot.detectedInstructionFiles.count, 1)
        XCTAssertEqual(snapshot.detectedInstructionFiles.first?.path, "AGENTS.md")
        XCTAssertTrue(snapshot.todos.contains(where: { $0.comment.contains("implement caching") }))

        // 3. Export service renders packet cleanly without Git sections
        let exportService = ContextExportService()
        let session = SavedProjectSession(
            repositoryPath: tempDirectory.path,
            currentGoal: "Add caching layer",
            nextTasks: [TaskItem(text: "Write cache tests", source: .user)]
        )

        let result = exportService.prepareExport(
            action: .copy(provider: "claude"),
            currentSnapshot: snapshot,
            refreshedSnapshot: snapshot,
            refreshErrorMessage: nil,
            currentDraft: "",
            isDraftModified: false,
            draftBaseSnapshotTimestamp: snapshot.refreshedAt,
            budgetMode: .standard,
            provider: "claude",
            session: session,
            importantFiles: [],
            allowStale: false
        )

        guard case .ready(let content, let metadata) = result else {
            XCTFail("Expected ready export result, got \(result)")
            return
        }

        XCTAssertFalse(metadata.isStale)
        XCTAssertTrue(content.contains("Local project directory (non-git)"))
        XCTAssertFalse(content.contains("## RECENT COMMITS"))
        XCTAssertFalse(content.contains("## GIT DIFF EXCERPT"))
        XCTAssertTrue(content.contains("## CURRENT GOAL\n\nAdd caching layer"))
        XCTAssertTrue(content.contains("Write cache tests"))
        XCTAssertTrue(content.contains("Always run npm test before handoff."))
    }
}
