import XCTest
@testable import ContextPacketCore

final class InstructionIngestionTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("instruction-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testInstructionFileDetectorFindsRootNestedAndDirectoryRules() throws {
        // 1. Root AGENTS.md
        let rootAgents = tempDir.appendingPathComponent("AGENTS.md")
        try "Always run tests before committing.".write(to: rootAgents, atomically: true, encoding: .utf8)

        // 2. Root CLAUDE.md
        let rootClaude = tempDir.appendingPathComponent("CLAUDE.md")
        try "Build with swift build.".write(to: rootClaude, atomically: true, encoding: .utf8)

        // 3. Root .cursorrules
        let cursorRules = tempDir.appendingPathComponent(".cursorrules")
        try "Prefer SwiftUI over UIKit.".write(to: cursorRules, atomically: true, encoding: .utf8)

        // 4. .github/copilot-instructions.md
        let githubDir = tempDir.appendingPathComponent(".github")
        try FileManager.default.createDirectory(at: githubDir, withIntermediateDirectories: true)
        let copilot = githubDir.appendingPathComponent("copilot-instructions.md")
        try "Use descriptive commit messages.".write(to: copilot, atomically: true, encoding: .utf8)

        // 5. .cursor/rules/* directory rules
        let cursorRulesDir = tempDir.appendingPathComponent(".cursor/rules")
        try FileManager.default.createDirectory(at: cursorRulesDir, withIntermediateDirectories: true)
        let swiftRule = cursorRulesDir.appendingPathComponent("swift.mdc")
        try "Follow Swift 6 concurrency.".write(to: swiftRule, atomically: true, encoding: .utf8)

        // 6. Nested AGENTS.md in packages/api
        let nestedApiDir = tempDir.appendingPathComponent("packages/api")
        try FileManager.default.createDirectory(at: nestedApiDir, withIntermediateDirectories: true)
        let nestedAgents = nestedApiDir.appendingPathComponent("AGENTS.md")
        try "API secret key: sk-live-1234567890abcdef12345678. Always validate JWT.".write(to: nestedAgents, atomically: true, encoding: .utf8)

        // Detect instructions
        let detected = InstructionFileDetector.detect(at: tempDir)

        XCTAssertGreaterThanOrEqual(detected.count, 6)

        // Verify root AGENTS.md
        let rootAgentsFound = detected.first { $0.path == "AGENTS.md" }
        XCTAssertNotNil(rootAgentsFound)
        XCTAssertEqual(rootAgentsFound?.scope, "root")
        XCTAssertTrue(rootAgentsFound?.content.contains("Always run tests before committing.") == true)

        // Verify CLAUDE.md
        let claudeFound = detected.first { $0.path == "CLAUDE.md" }
        XCTAssertNotNil(claudeFound)
        XCTAssertEqual(claudeFound?.scope, "root")

        // Verify .cursorrules
        let cursorFound = detected.first { $0.path == ".cursorrules" }
        XCTAssertNotNil(cursorFound)
        XCTAssertEqual(cursorFound?.scope, "root")

        // Verify .github/copilot-instructions.md
        let copilotFound = detected.first { $0.path == ".github/copilot-instructions.md" }
        XCTAssertNotNil(copilotFound)
        XCTAssertEqual(copilotFound?.scope, "github-copilot")

        // Verify .cursor/rules/swift.mdc
        let swiftRuleFound = detected.first { $0.path == ".cursor/rules/swift.mdc" }
        XCTAssertNotNil(swiftRuleFound)
        XCTAssertEqual(swiftRuleFound?.scope, "cursor-rule: swift")

        // Verify nested AGENTS.md
        let nestedFound = detected.first { $0.path == "packages/api/AGENTS.md" }
        XCTAssertNotNil(nestedFound)
        XCTAssertEqual(nestedFound?.scope, "packages/api")

        // Outcome 1 & 3: Ensure sensitive keys inside instructions are sanitized immediately on detection
        XCTAssertFalse(nestedFound?.content.contains("sk-live-1234567890abcdef12345678") == true)
        XCTAssertTrue(nestedFound?.content.contains("[REDACTED_API_KEY]") == true)
    }

    func testInstructionRenderingAcrossBudgetModes() {
        let longText = String(repeating: "Line of important instruction context.\n", count: 50)
        let file = InstructionFile(
            path: "AGENTS.md",
            scope: "root",
            content: longText,
            isTruncated: false
        )

        let project = ProjectContext(
            name: "TestRepo",
            repositoryPath: tempDir.path,
            ecosystem: "Swift",
            remoteURL: "https://github.com/example/testrepo"
        )
        let state = CanonicalRepositoryState(
            branch: "main",
            headCommit: "abc1234",
            isClean: true,
            modifiedFiles: [],
            stagedFiles: [],
            untrackedFiles: [],
            diffSummary: DiffSummary(filesChanged: 0, additions: 0, deletions: 0, files: []),
            refreshedAt: Date(),
            isStale: false,
            stalenessReason: nil
        )

        let handoff = Handoff(
            project: project,
            currentGoal: "Test mode rendering",
            completedWork: [],
            currentState: state,
            importantFiles: [],
            decisions: [],
            nextTasks: [TaskItem(text: "Verify rendering", source: .user)],
            knownProblems: [],
            recentWork: [],
            recentCommits: [],
            detectedInstructions: [file],
            todos: [],
            notes: nil
        )

        let builder = MarkdownHandoffBuilder()

        // 1. Compact mode: file references only
        let compactOutput = builder.buildContent(handoff: handoff, mode: .compact)
        XCTAssertTrue(compactOutput.contains("## PROJECT INSTRUCTIONS"))
        XCTAssertTrue(compactOutput.contains("- AGENTS.md (scope: root)"))
        XCTAssertFalse(compactOutput.contains("```\nLine of important"))

        // 2. Standard mode: bounded content with truncation indicator
        let standardOutput = builder.buildContent(handoff: handoff, mode: .standard)
        XCTAssertTrue(standardOutput.contains("### AGENTS.md (scope: root)"))
        XCTAssertTrue(standardOutput.contains("```"))
        XCTAssertTrue(standardOutput.contains("[Truncated for Standard budget]"))

        // 3. Comprehensive mode: full content
        let compOutput = builder.buildContent(handoff: handoff, mode: .comprehensive)
        XCTAssertTrue(compOutput.contains("### AGENTS.md (path: AGENTS.md, scope: root)"))
        XCTAssertTrue(compOutput.contains("```"))
        XCTAssertTrue(compOutput.contains("Line of important instruction context."))
    }
}
