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

    func testFinalEstimatedTokensNeverExceedsConfiguredTargetAcrossAllModesAndProviders() {
        // Create an intentionally massive handoff that exceeds even comprehensive budget by 10x
        let hugeGoal = String(repeating: "This is a massive user goal describing all requirements in extreme verbosity. ", count: 300)
        let tasks = (1...150).map { i in
            TaskItem(text: "Task \(i): " + String(repeating: "Do this subtask very carefully with lots of detail. ", count: 10), source: .user)
        }
        let decisions = (1...150).map { i in
            Decision(text: "Decision \(i): " + String(repeating: "We decided this architectural direction due to performance reasons. ", count: 10), source: .user)
        }
        let files = (1...200).map { i in "Sources/Module/Component/VeryLongPathNameForFileNumber\(i).swift" }
        let commits = (1...50).map { i in
            Commit(hash: "hash\(i)", shortHash: "h\(i)", author: "Engineer", date: "2026-09-28", subject: "Detailed commit message \(i) with lots of prose")
        }
        let instructions = (1...20).map { i in
            InstructionFile(
                path: "rules/rule\(i).md",
                filename: "rule\(i).md",
                scope: "scope\(i)",
                content: String(repeating: "Instruction content line explaining formatting and rules. ", count: 50)
            )
        }
        let todos = (1...50).map { i in
            TodoItem(file: "File\(i).swift", line: i * 5, kind: "TODO", comment: "Resolve issue \(i) urgently", isInsideChangedFile: true)
        }

        let project = ProjectContext(
            name: "MegaProject",
            repositoryPath: "/Users/dev/MegaProject",
            ecosystem: "Swift",
            remoteURL: "https://github.com/mega/project.git"
        )

        let state = CanonicalRepositoryState(
            branch: "main",
            headCommit: "abcdef1234567890",
            isClean: false,
            modifiedFiles: files,
            stagedFiles: [],
            untrackedFiles: [],
            diffSummary: DiffSummary(
                filesChanged: 200,
                additions: 15000,
                deletions: 4000,
                files: files.map { FileDelta(path: $0, additions: 75, deletions: 20) },
                rawDiffSnippet: String(repeating: "+ let x = 1\n- let x = 0\n", count: 200),
                isTruncated: true
            ),
            refreshedAt: Date(),
            isStale: false,
            stalenessReason: nil
        )

        let handoff = Handoff(
            project: project,
            currentGoal: hugeGoal,
            completedWork: [ContextItem(text: "Initial bootstrapping completed")],
            currentState: state,
            importantFiles: files.map { ImportantFile(path: $0, reason: "Core component") },
            decisions: decisions,
            nextTasks: tasks,
            knownProblems: [ProblemItem(text: "High memory pressure during build")],
            recentWork: [ContextItem(text: "Refactored module structure")],
            recentCommits: commits,
            detectedInstructions: instructions,
            todos: todos,
            notes: String(repeating: "Additional developer notes with guidelines. ", count: 40)
        )

        let modes: [TokenBudgetMode] = [.compact, .standard, .comprehensive]
        let exporters: [ContextExporter] = [
            ClaudeExporter(),
            CodexExporter(),
            CursorExporter(),
            GenericExporter()
        ]

        let config = TokenBudgetConfig.default

        for mode in modes {
            let target = config.target(for: mode)
            for exporter in exporters {
                let output = exporter.export(handoff: handoff, mode: mode)
                let estimate = TokenBudgetEstimate(text: output).estimatedTokens

                // Assert that the final estimated tokens strictly fit within configured target
                XCTAssertLessThanOrEqual(
                    estimate,
                    target,
                    "Final estimated tokens (\(estimate)) must be <= configured target (\(target)) for \(exporter.providerName) in \(mode.rawValue) mode"
                )

                // Assert disclosures are emitted
                XCTAssertTrue(output.contains("## BUDGET DISCLOSURES"), "Budget disclosures must be present when content is truncated")

                // Assert core project identification is retained
                XCTAssertTrue(output.contains("# PROJECT"), "Project header must be preserved")
            }
        }
    }
}
