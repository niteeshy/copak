import XCTest
@testable import ContextPacketCore

final class ExporterTests: XCTestCase {
    func makeSampleHandoff() -> Handoff {
        let project = ProjectContext(
            name: "Solarpunk Battery",
            repositoryPath: "/Users/dev/Solarpunk",
            ecosystem: "Swift",
            remoteURL: "https://github.com/example/solarpunk"
        )
        let state = CanonicalRepositoryState(
            branch: "feature/charging",
            headCommit: "a1b2c3d",
            isClean: false,
            modifiedFiles: ["BatteryManager.swift", "GardenView.swift"],
            stagedFiles: [],
            untrackedFiles: ["ChargingParticles.swift"],
            diffSummary: DiffSummary(
                filesChanged: 2,
                additions: 120,
                deletions: 35,
                files: [
                    FileDelta(path: "BatteryManager.swift", additions: 84, deletions: 16),
                    FileDelta(path: "GardenView.swift", additions: 36, deletions: 19)
                ]
            )
        )
        let important = [
            ImportantFile(path: "BatteryManager.swift", reason: "Core state model"),
            ImportantFile(path: "GardenView.swift", reason: "Visual rendering")
        ]
        let decisions = [
            Decision(text: "Use native SwiftUI.", source: .user),
            Decision(text: "Illustration should respond continuously to battery state.", source: .user)
        ]
        let tasks = [
            TaskItem(text: "Implement the 80–100% charging state.", source: .user)
        ]
        let problems = [
            ProblemItem(text: "Animation resets whenever menu closes.", source: .user)
        ]

        return Handoff(
            project: project,
            currentGoal: "Implement charging state animations.",
            completedWork: [ContextItem(text: "BatteryKit integration"), ContextItem(text: "Menu-bar UI")],
            currentState: state,
            importantFiles: important,
            decisions: decisions,
            nextTasks: tasks,
            knownProblems: problems,
            recentWork: [ContextItem(text: "Added initial charging animation prototype.")]
        )
    }

    func testGenericExporterOutput() {
        let handoff = makeSampleHandoff()
        let exporter = GenericExporter()
        let output = exporter.export(handoff: handoff, mode: .standard)

        XCTAssertTrue(output.contains("# PROJECT\n\nSolarpunk Battery (Swift)"))
        XCTAssertTrue(output.contains("## CURRENT GOAL\n\nImplement charging state animations."))
        XCTAssertTrue(output.contains("## WHAT EXISTS"))
        XCTAssertTrue(output.contains("- BatteryKit integration"))
        XCTAssertTrue(output.contains("Branch: feature/charging"))
        XCTAssertTrue(output.contains("- BatteryManager.swift"))
        XCTAssertTrue(output.contains("- ChargingParticles.swift"))
        XCTAssertTrue(output.contains("## IMPORTANT FILES"))
        XCTAssertTrue(output.contains("## DECISIONS"))
        XCTAssertTrue(output.contains("- Use native SwiftUI."))
        XCTAssertTrue(output.contains("## NEXT TASK"))
        XCTAssertTrue(output.contains("- Implement the 80–100% charging state."))
        XCTAssertTrue(output.contains("## KNOWN PROBLEMS"))
    }

    func testClaudeExporterIncludesDirectives() {
        let handoff = makeSampleHandoff()
        let exporter = ClaudeExporter()
        let output = exporter.export(handoff: handoff, mode: .standard)

        XCTAssertTrue(output.contains("You are continuing work on an existing project."))
        XCTAssertTrue(output.contains("Inspect the relevant files before modifying them."))
        XCTAssertTrue(output.contains("Before making changes:"))
        XCTAssertTrue(output.contains("Continue from the NEXT TASK section"))
    }

    func testCodexExporterIncludesDirectives() {
        let handoff = makeSampleHandoff()
        let exporter = CodexExporter()
        let output = exporter.export(handoff: handoff, mode: .standard)

        XCTAssertTrue(output.contains("Continue the existing implementation described below."))
        XCTAssertTrue(output.contains("Do not redo completed work."))
    }

    func testCursorExporterIncludesDirectives() {
        let handoff = makeSampleHandoff()
        let exporter = CursorExporter()
        let output = exporter.export(handoff: handoff, mode: .standard)

        XCTAssertTrue(output.contains("You are joining an in-progress coding task."))
        XCTAssertTrue(output.contains("Verify details against the codebase before modifying files."))
    }

    func testCompactModeExcludesOptionalSections() {
        let handoff = makeSampleHandoff()
        let exporter = GenericExporter()
        let output = exporter.export(handoff: handoff, mode: .compact)

        XCTAssertTrue(output.contains("CURRENT GOAL"))
        XCTAssertTrue(output.contains("CURRENT STATE"))
        XCTAssertTrue(output.contains("IMPORTANT FILES"))
        XCTAssertTrue(output.contains("NEXT TASK"))
        XCTAssertFalse(output.contains("## WHAT EXISTS"))
        XCTAssertFalse(output.contains("## KNOWN PROBLEMS"))
    }

    func testTokenBudgetEstimatesReasonably() {
        let handoff = makeSampleHandoff()
        let exporter = GenericExporter()
        let output = exporter.export(handoff: handoff, mode: .standard)

        let estimate = TokenBudgetEstimate(text: output)
        XCTAssertGreaterThan(estimate.wordCount, 30)
        XCTAssertGreaterThan(estimate.estimatedTokens, 50)
        XCTAssertEqual(estimate.estimatedTokens, Int(ceil(Double(output.count) / 4.0)))
    }
}
