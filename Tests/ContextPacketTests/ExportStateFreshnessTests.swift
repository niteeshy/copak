import XCTest
@testable import ContextPacketCore

final class ExportStateFreshnessTests: XCTestCase {
    var repoURL: URL!

    override func setUp() {
        super.setUp()
        repoURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let url = repoURL {
            try? FileManager.default.removeItem(at: url)
        }
        super.tearDown()
    }

    private func makeSyntheticSnapshot(
        branch: String = "main",
        headHash: String = "abc1234",
        modifiedFiles: [ChangedFile] = [],
        refreshedAt: Date = Date(),
        refreshError: String? = nil
    ) -> RepositorySnapshot {
        RepositorySnapshot(
            name: "TestRepo",
            path: repoURL,
            branch: branch,
            remoteURL: nil,
            headCommitHash: headHash,
            modifiedFiles: modifiedFiles,
            stagedFiles: [],
            untrackedFiles: [],
            recentCommits: [],
            fileTreeSummary: "main.swift",
            readme: nil,
            projectMetadata: ProjectMetadata(ecosystem: "Swift", buildSystem: "SPM", detectedConfigFiles: ["Package.swift"]),
            detectedInstructionFiles: [],
            todos: [],
            diffSummary: nil,
            refreshedAt: refreshedAt,
            refreshError: refreshError
        )
    }

    func testChangedGitStateBeforeCopyRegeneratesUneditedPreview() {
        let service = ContextExportService()
        let oldTime = Date().addingTimeInterval(-60)
        let initialSnap = makeSyntheticSnapshot(headHash: "oldHash111", refreshedAt: oldTime)
        let newTime = Date()
        let refreshedSnap = makeSyntheticSnapshot(
            headHash: "newHash222",
            modifiedFiles: [ChangedFile(path: "Sources/Feature.swift", statusLetter: "M")],
            refreshedAt: newTime
        )

        let initialDraft = service.renderMarkdown(
            for: service.buildHandoff(from: initialSnap, session: nil, importantFiles: [], isStale: false, stalenessReason: nil),
            provider: "claude",
            mode: .standard
        )
        XCTAssertTrue(initialDraft.contains("oldHash111"))

        // When user has NOT modified the draft, copy regenerates from fresh snapshot
        let outcome = service.prepareExport(
            action: .copy(provider: "claude"),
            currentSnapshot: initialSnap,
            refreshedSnapshot: refreshedSnap,
            refreshErrorMessage: nil,
            currentDraft: initialDraft,
            isDraftModified: false,
            draftBaseSnapshotTimestamp: oldTime,
            budgetMode: .standard,
            provider: "claude",
            session: nil,
            importantFiles: [],
            allowStale: false
        )

        guard case .ready(let content, let metadata) = outcome else {
            XCTFail("Expected ready outcome")
            return
        }

        XCTAssertTrue(metadata.wasRegenerated, "Unedited draft must be regenerated on fresh state")
        XCTAssertFalse(metadata.isEditedDraft)
        XCTAssertFalse(metadata.isStale)
        XCTAssertTrue(content.contains("newHash222"), "Exported content must reflect the new commit HEAD")
        XCTAssertTrue(content.contains("Sources/Feature.swift"), "Exported content must reflect newly modified file")
        XCTAssertFalse(content.contains("oldHash111"))
    }

    func testChangedGitStateBeforeSaveRegeneratesUneditedPreview() throws {
        let service = ContextExportService()
        let oldTime = Date().addingTimeInterval(-120)
        let initialSnap = makeSyntheticSnapshot(branch: "main", refreshedAt: oldTime)
        let newTime = Date()
        let refreshedSnap = makeSyntheticSnapshot(
            branch: "feature/fresh-work",
            refreshedAt: newTime
        )

        let initialDraft = "Initial unedited preview"

        let outcome = service.prepareExport(
            action: .save,
            currentSnapshot: initialSnap,
            refreshedSnapshot: refreshedSnap,
            refreshErrorMessage: nil,
            currentDraft: initialDraft,
            isDraftModified: false,
            draftBaseSnapshotTimestamp: oldTime,
            budgetMode: .standard,
            provider: "generic",
            session: nil,
            importantFiles: [],
            allowStale: false
        )

        guard case .ready(let content, let metadata) = outcome else {
            XCTFail("Expected ready outcome")
            return
        }

        XCTAssertTrue(metadata.wasRegenerated)
        XCTAssertTrue(content.contains("Branch: feature/fresh-work"))
        guard let dest = metadata.destinationURL else {
            XCTFail("Expected destination URL")
            return
        }

        // Test writing file atomically through service
        try service.writeExportFile(content: content, to: dest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        let written = try String(contentsOf: dest, encoding: .utf8)
        XCTAssertTrue(written.contains("Branch: feature/fresh-work"))
    }

    func testEditedPreviewPlusSuccessfulRefreshNeverOverwritesDraftAndEmitsWarning() {
        let service = ContextExportService()
        let draftBaseTime = Date().addingTimeInterval(-100)
        let initialSnap = makeSyntheticSnapshot(branch: "feature/old", refreshedAt: draftBaseTime)
        let refreshedTime = Date()
        let refreshedSnap = makeSyntheticSnapshot(branch: "feature/new", refreshedAt: refreshedTime)

        let customEditedDraft = "## CURRENT GOAL\n\nCustom manual user developer edits here."

        let outcome = service.prepareExport(
            action: .copy(provider: "claude"),
            currentSnapshot: initialSnap,
            refreshedSnapshot: refreshedSnap,
            refreshErrorMessage: nil,
            currentDraft: customEditedDraft,
            isDraftModified: true,
            draftBaseSnapshotTimestamp: draftBaseTime,
            budgetMode: .standard,
            provider: "claude",
            session: nil,
            importantFiles: [],
            allowStale: false
        )

        guard case .ready(let content, let metadata) = outcome else {
            XCTFail("Expected ready outcome")
            return
        }

        XCTAssertFalse(metadata.wasRegenerated, "Edited draft must never be silently overwritten")
        XCTAssertTrue(metadata.isEditedDraft)
        XCTAssertNotNil(metadata.warningNotice, "Must show warning when draft contains older snapshot")
        XCTAssertTrue(content.contains("Custom manual user developer edits here."), "Manual edits must be preserved")
        XCTAssertTrue(content.contains("Edited Draft Notice"), "Notice must be injected")
        XCTAssertEqual(metadata.snapshotRefreshedAt, draftBaseTime)
    }

    func testFailedRefreshRequiresExplicitConfirmation() {
        let service = ContextExportService()
        let initialSnap = makeSyntheticSnapshot(branch: "main", refreshedAt: Date().addingTimeInterval(-300))

        // When refresh fails and allowStale is false
        let outcome = service.prepareExport(
            action: .copy(provider: "claude"),
            currentSnapshot: initialSnap,
            refreshedSnapshot: nil,
            refreshErrorMessage: "Git lock active: could not inspect working tree",
            currentDraft: "Some existing markdown",
            isDraftModified: false,
            draftBaseSnapshotTimestamp: initialSnap.refreshedAt,
            budgetMode: .standard,
            provider: "claude",
            session: nil,
            importantFiles: [],
            allowStale: false
        )

        guard case .requiresStaleConfirmation(let reason) = outcome else {
            XCTFail("Expected requiresStaleConfirmation")
            return
        }
        XCTAssertTrue(reason.contains("Git lock active"))
    }

    func testExplicitStaleExportSucceedsWithStaleNoticeAndExactTimestamp() {
        let service = ContextExportService()
        let snapTimestamp = Date().addingTimeInterval(-600)
        let initialSnap = makeSyntheticSnapshot(branch: "main", refreshedAt: snapTimestamp)

        // When user explicitly confirms stale export (allowStale = true)
        let outcome = service.prepareExport(
            action: .copy(provider: "claude"),
            currentSnapshot: initialSnap,
            refreshedSnapshot: nil,
            refreshErrorMessage: "Repository detached or remote unavailable",
            currentDraft: "",
            isDraftModified: false,
            draftBaseSnapshotTimestamp: snapTimestamp,
            budgetMode: .standard,
            provider: "claude",
            session: nil,
            importantFiles: [],
            allowStale: true
        )

        guard case .ready(let content, let metadata) = outcome else {
            XCTFail("Expected ready outcome")
            return
        }

        XCTAssertTrue(metadata.isStale)
        XCTAssertEqual(metadata.snapshotRefreshedAt, snapTimestamp)
        XCTAssertTrue(content.contains("Stale Snapshot Notice"))
        XCTAssertTrue(content.contains("Repository detached or remote unavailable"))
    }
}
