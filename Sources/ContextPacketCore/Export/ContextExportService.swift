import Foundation

public enum ExportTargetAction: Sendable, Equatable {
    case copy(provider: String)
    case save
}

public struct ExportMetadata: Sendable, Equatable {
    public let wasRegenerated: Bool
    public let isEditedDraft: Bool
    public let isStale: Bool
    public let snapshotRefreshedAt: Date
    public let latestRefreshedAt: Date
    public let destinationURL: URL?
    public let warningNotice: String?

    public init(
        wasRegenerated: Bool,
        isEditedDraft: Bool,
        isStale: Bool,
        snapshotRefreshedAt: Date,
        latestRefreshedAt: Date,
        destinationURL: URL? = nil,
        warningNotice: String? = nil
    ) {
        self.wasRegenerated = wasRegenerated
        self.isEditedDraft = isEditedDraft
        self.isStale = isStale
        self.snapshotRefreshedAt = snapshotRefreshedAt
        self.latestRefreshedAt = latestRefreshedAt
        self.destinationURL = destinationURL
        self.warningNotice = warningNotice
    }
}

public enum ExportResult: Sendable, Equatable {
    case ready(content: String, metadata: ExportMetadata)
    case requiresStaleConfirmation(reason: String)
    case failure(message: String)
}

public struct ContextExportService: Sendable {
    public static let shared = ContextExportService()

    private static let utcDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    public init() {}

    /// Core business logic for determining whether to regenerate, preserve draft, warn,
    /// require stale confirmation, and sanitize output.
    public func prepareExport(
        action: ExportTargetAction,
        currentSnapshot: RepositorySnapshot?,
        refreshedSnapshot: RepositorySnapshot?,
        refreshErrorMessage: String?,
        currentDraft: String,
        isDraftModified: Bool,
        draftBaseSnapshotTimestamp: Date?,
        budgetMode: TokenBudgetMode,
        provider: String,
        session: SavedProjectSession?,
        importantFiles: [ImportantFile],
        allowStale: Bool
    ) -> ExportResult {
        // 1. Check if refresh failed and stale confirmation is required
        if let err = refreshErrorMessage, refreshedSnapshot == nil {
            if !allowStale {
                return .requiresStaleConfirmation(reason: err)
            }
        }

        // 2. Select the most current available snapshot
        guard let activeSnapshot = refreshedSnapshot ?? currentSnapshot else {
            return .failure(message: "No repository snapshot available.")
        }

        let isStale = (refreshErrorMessage != nil)
        let activeTimestamp = activeSnapshot.refreshedAt
        let draftTimestamp = draftBaseSnapshotTimestamp ?? activeTimestamp
        let targetProvider: String
        switch action {
        case .copy(let p):
            targetProvider = p
        case .save:
            targetProvider = "generic"
        }

        let destinationURL = (action == .save) ? activeSnapshot.path.appendingPathComponent("context.md") : nil

        // 3. Draft handling:
        // An edited preview is never silently overwritten.
        // A successful refresh regenerates an unedited preview before copy or save.
        if isDraftModified && !currentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var content = currentDraft
            var warning: String? = nil

            let isOlderSnapshot = activeTimestamp > draftTimestamp
            let activeTimeStr = Self.utcDateFormatter.string(from: activeTimestamp)
            let draftTimeStr = Self.utcDateFormatter.string(from: draftTimestamp)

            if isOlderSnapshot {
                warning = "Warning: Edited preview contains an older snapshot (\(draftTimeStr)). Repository was refreshed at \(activeTimeStr)."
                if !content.contains("Edited Draft Notice") {
                    content = "> [!WARNING] Edited Draft Notice: Manual edits preserved from snapshot captured at \(draftTimeStr). (Repository refreshed: \(activeTimeStr)).\n\n" + content
                }
            } else {
                if !content.contains("Edited Draft Notice") {
                    content = "> [!NOTE] Edited Draft Notice: Manual edits preserved from snapshot captured at \(draftTimeStr).\n\n" + content
                }
            }

            if isStale && !content.contains("Stale Snapshot Notice") {
                let errReason = refreshErrorMessage ?? "Git state refresh failed"
                content = "> [!WARNING] Stale Snapshot Notice: Refresh failed (\(errReason)). Content exported with stale snapshot captured at \(draftTimeStr).\n\n" + content
            }

            let finalSanitized = SecretFilter.sanitizeText(content)
            return .ready(
                content: finalSanitized,
                metadata: ExportMetadata(
                    wasRegenerated: false,
                    isEditedDraft: true,
                    isStale: isStale,
                    snapshotRefreshedAt: draftTimestamp,
                    latestRefreshedAt: activeTimestamp,
                    destinationURL: destinationURL,
                    warningNotice: warning
                )
            )
        } else {
            // Unedited preview or empty: regenerate using activeSnapshot!
            let handoff = buildHandoff(
                from: activeSnapshot,
                session: session,
                importantFiles: importantFiles,
                isStale: isStale,
                stalenessReason: refreshErrorMessage
            )
            let rendered = renderMarkdown(for: handoff, provider: targetProvider, mode: budgetMode)
            let finalSanitized = SecretFilter.sanitizeText(rendered)

            return .ready(
                content: finalSanitized,
                metadata: ExportMetadata(
                    wasRegenerated: true,
                    isEditedDraft: false,
                    isStale: isStale,
                    snapshotRefreshedAt: activeSnapshot.refreshedAt,
                    latestRefreshedAt: activeTimestamp,
                    destinationURL: destinationURL,
                    warningNotice: isStale ? "Stale repository snapshot exported." : nil
                )
            )
        }
    }

    public func buildHandoff(
        from snap: RepositorySnapshot,
        session: SavedProjectSession?,
        importantFiles: [ImportantFile],
        isStale: Bool,
        stalenessReason: String?
    ) -> Handoff {
        let project = ProjectContext(
            name: snap.name,
            repositoryPath: snap.path.path,
            ecosystem: snap.projectMetadata.ecosystem,
            remoteURL: snap.remoteURL
        )

        let state = CanonicalRepositoryState(
            branch: snap.branch ?? (snap.isGitRepository ? "main" : "non-git"),
            headCommit: snap.headCommitHash,
            isClean: snap.isClean,
            modifiedFiles: snap.modifiedFiles.map(\.path),
            stagedFiles: snap.stagedFiles.map(\.path),
            untrackedFiles: snap.untrackedFiles.map(\.path),
            diffSummary: snap.diffSummary,
            refreshedAt: snap.refreshedAt,
            isStale: isStale,
            stalenessReason: stalenessReason,
            hasOmittedSensitiveChanges: snap.hasOmittedSensitiveChanges,
            hiddenSensitiveChangesCount: snap.hiddenSensitiveChangesCount,
            isGitDirty: snap.isGitDirty,
            isEditedDraft: false,
            isGitRepository: snap.isGitRepository
        )

        return Handoff(
            version: "1.0",
            project: project,
            currentGoal: session?.currentGoal ?? "",
            completedWork: session?.completedWork ?? [],
            currentState: state,
            importantFiles: importantFiles,
            decisions: session?.decisions ?? [],
            nextTasks: session?.nextTasks ?? [],
            knownProblems: session?.knownProblems ?? [],
            recentWork: session?.recentWork ?? [],
            recentCommits: snap.recentCommits,
            detectedInstructions: snap.detectedInstructionFiles,
            todos: snap.todos,
            notes: session?.notes,
            generatedAt: Date()
        )
    }

    public func renderMarkdown(for handoff: Handoff, provider: String, mode: TokenBudgetMode) -> String {
        let exporter: ContextExporter
        switch provider.lowercased() {
        case "claude":
            exporter = ClaudeExporter()
        case "codex":
            exporter = CodexExporter()
        case "cursor":
            exporter = CursorExporter()
        default:
            exporter = GenericExporter()
        }
        return exporter.export(handoff: handoff, mode: mode)
    }

    /// Atomically writes sanitized content to file.
    public func writeExportFile(content: String, to destinationURL: URL) throws {
        let sanitized = SecretFilter.sanitizeText(content)
        try sanitized.write(to: destinationURL, atomically: true, encoding: .utf8)
    }
}
