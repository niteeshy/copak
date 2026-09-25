import XCTest
@testable import ContextPacketCore

final class GitParsingTests: XCTestCase {
    var tempRepoURL: URL!

    override func setUpWithError() throws {
        tempRepoURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_repo_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRepoURL, withIntermediateDirectories: true)

        // Initialize a real minimal git repo in temp dir
        let runner = GitCommandRunner()
        let exp = expectation(description: "git init")
        Task {
            _ = try? await runner.run(arguments: ["init", "-b", "main"], in: self.tempRepoURL)
            _ = try? await runner.run(arguments: ["config", "user.name", "Test Agent"], in: self.tempRepoURL)
            _ = try? await runner.run(arguments: ["config", "user.email", "agent@test.com"], in: self.tempRepoURL)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5.0)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRepoURL)
    }

    func testGitClientWithRealRepository() async throws {
        let client = GitClient()
        let runner = GitCommandRunner()

        // 1. Resolve root
        let root = try await client.resolveRepositoryRoot(at: tempRepoURL)
        XCTAssertEqual(root.standardizedFileURL.path, tempRepoURL.standardizedFileURL.path)

        // 2. Initial branch
        let branch = await client.getCurrentBranch(at: tempRepoURL)
        XCTAssertTrue(branch == "main" || branch?.contains("Initial") == true)

        // 3. Create a file with spaces and check untracked status
        let spaceFile = tempRepoURL.appendingPathComponent("My Feature File.swift")
        try "print(\"space file\")\n".write(to: spaceFile, atomically: true, encoding: .utf8)

        let status1 = try await client.getStatus(at: tempRepoURL)
        XCTAssertEqual(status1.untracked.count, 1)
        XCTAssertEqual(status1.untracked.first?.path, "My Feature File.swift")

        // 4. Commit file and check commit history
        _ = try await runner.run(arguments: ["add", "My Feature File.swift"], in: tempRepoURL)
        _ = try await runner.run(arguments: ["commit", "-m", "Initial commit"], in: tempRepoURL)

        let commits = await client.getRecentCommits(at: tempRepoURL, count: 5)
        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits.first?.subject, "Initial commit")

        // 5. Clean state
        let status2 = try await client.getStatus(at: tempRepoURL)
        XCTAssertTrue(status2.modified.isEmpty)
        XCTAssertTrue(status2.staged.isEmpty)
        XCTAssertTrue(status2.untracked.isEmpty)

        // 6. Modify file and check diff summary
        try "print(\"modified space file\")\nprint(\"line 2\")\n".write(to: spaceFile, atomically: true, encoding: .utf8)
        let diffSummary = await client.getDiffSummary(at: tempRepoURL)
        XCTAssertEqual(diffSummary.filesChanged, 1)
        XCTAssertGreaterThan(diffSummary.additions, 0)

        // 7. Detached HEAD handling
        let commitHash = commits.first!.hash
        _ = try await runner.run(arguments: ["checkout", commitHash], in: tempRepoURL)
        let detachedBranch = await client.getCurrentBranch(at: tempRepoURL)
        XCTAssertTrue(detachedBranch?.contains("detached") == true)
    }

    func testNonGitDirectoryThrowsExpectedError() async {
        let nonGitDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: nonGitDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: nonGitDir) }

        let client = GitClient()
        do {
            _ = try await client.resolveRepositoryRoot(at: nonGitDir)
            XCTFail("Should have thrown notAGitRepository")
        } catch GitError.notAGitRepository {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
