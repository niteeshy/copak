import XCTest
@testable import ContextPacketCore

final class TokenBudgetPriorityTests: XCTestCase {
    func testTokenBudgetTargetsAreExplicitAndConfigurable() {
        let config = TokenBudgetConfig()
        XCTAssertEqual(config.target(for: .compact), 1_000)
        XCTAssertEqual(config.target(for: .standard), 3_500)
        XCTAssertEqual(config.target(for: .comprehensive), 10_000)

        // Custom config
        let custom = TokenBudgetConfig(compactTargetTokens: 800, standardTargetTokens: 2_500, comprehensiveTargetTokens: 15_000)
        XCTAssertEqual(custom.target(for: .compact), 800)
        XCTAssertEqual(custom.target(for: .standard), 2_500)
        XCTAssertEqual(custom.target(for: .comprehensive), 15_000)
    }

    func testTokenBudgetEstimateDisplayIsClearlyLabeledEstimate() {
        let text = "This is a short prompt for an AI agent."
        let estimate = TokenBudgetEstimate(text: text)
        XCTAssertTrue(estimate.displaySummary.contains("Estimated ~"), "Must be explicitly labeled as an estimate")
        XCTAssertFalse(estimate.displaySummary.contains("exact"), "Must not claim exact count")
    }

    func testBudgetPrioritiesPreserveHighPriorityAndDiscloseOmissions() {
        // Build handoff with lots of lower priority data (many commits, todos, files, diff)
        let commits = (1...30).map { i in
            Commit(hash: "hash\(i)", shortHash: "h\(i)", author: "Dev", date: "2026-09-25", subject: "Commit message number \(i)")
        }
        let todos = (1...40).map { i in
            TodoItem(file: "File\(i).swift", line: i * 10, kind: "TODO", comment: "fix issue \(i)")
        }
        let files = (1...50).map { i in "Sources/Feature/Component\(i).swift" }

        let project = ProjectContext(
            name: "LargeProject",
            repositoryPath: "/Users/dev/LargeProject",
            ecosystem: "Swift",
            remoteURL: "https://github.com/example/largeproject"
        )

        let state = CanonicalRepositoryState(
            branch: "main",
            headCommit: "head123",
            isClean: false,
            modifiedFiles: files,
            stagedFiles: [],
            untrackedFiles: [],
            diffSummary: DiffSummary(filesChanged: 50, additions: 500, deletions: 100, files: []),
            refreshedAt: Date(),
            isStale: false,
            stalenessReason: nil
        )

        let handoff = Handoff(
            project: project,
            currentGoal: "Critical Core Goal: Must never be omitted",
            completedWork: [ContextItem(text: "Completed core setup")],
            currentState: state,
            importantFiles: files.map { ImportantFile(path: $0) },
            decisions: [Decision(text: "Decision 1: Use Swift 6", source: .user)],
            nextTasks: [TaskItem(text: "Next Task 1: Must never be omitted", source: .user)],
            knownProblems: [ProblemItem(text: "Problem 1: Known memory issue", source: .user)],
            recentWork: [ContextItem(text: "Recent work item")],
            recentCommits: commits,
            detectedInstructions: [
                InstructionFile(
                    path: "AGENTS.md",
                    scope: "Repository-wide instructions",
                    content: "Follow architecture rules.",
                    isTruncated: false
                )
            ],
            todos: todos,
            notes: "Note item"
        )

        let builder = MarkdownHandoffBuilder()

        // In Compact mode:
        let compact = builder.buildContent(handoff: handoff, mode: .compact)

        // P1 (Goal) & P2 (Next Task) must ALWAYS be present
        XCTAssertTrue(compact.contains("Critical Core Goal: Must never be omitted"))
        XCTAssertTrue(compact.contains("Next Task 1: Must never be omitted"))

        // P3 Git & repo identity present
        XCTAssertTrue(compact.contains("## CURRENT STATE"))

        // Truncation disclosure: In Compact mode, lower priority items (like todos, verbose commits) are omitted and disclosed
        XCTAssertTrue(compact.contains("## BUDGET DISCLOSURES"))
        XCTAssertTrue(compact.contains("omitted to fit Compact budget") || compact.contains("Recent commits capped at 2"))

        // In Standard mode:
        let standard = builder.buildContent(handoff: handoff, mode: .standard)
        XCTAssertTrue(standard.contains("Critical Core Goal: Must never be omitted"))
        XCTAssertTrue(standard.contains("Next Task 1: Must never be omitted"))
        XCTAssertTrue(standard.contains("## DECISIONS"))
    }
}
