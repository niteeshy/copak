import SwiftUI
import AppKit
import ContextPacketCore

public enum AppScreen {
    case picker
    case overview
    case preview
}

@MainActor
public final class AppState: ObservableObject {
    @Published public var currentScreen: AppScreen = .picker
    @Published public var currentRepoURL: URL?
    @Published public var snapshot: RepositorySnapshot?
    @Published public var session: SavedProjectSession?

    @Published public var isLoading: Bool = false
    @Published public var loadingMessage: String = ""
    @Published public var errorMessage: String?
    @Published public var toastMessage: String?

    @Published public var recentProjects: [RecentProjectItem] = []
    @Published public var importantFiles: [ImportantFile] = []

    // Generated handoff view
    @Published public var generatedMarkdown: String = ""
    @Published public var budgetMode: TokenBudgetMode = .standard
    @Published public var selectedProvider: String = "claude"

    @Published public var isDraftModified: Bool = false
    @Published public var lastRefreshedAt: Date?
    @Published public var refreshErrorMessage: String?
    @Published public var showStaleExportAlert: Bool = false
    @Published public var showDiscardDraftAlert: Bool = false
    public var pendingStaleAction: (@MainActor () -> Void)?
    public var pendingDraftSwitchAction: (@MainActor () -> Void)?

    private let analyzer = RepositoryAnalyzer()
    private let recentStore = RecentProjectsStore.shared
    private let sessionStore = ProjectSessionStore.shared

    public init() {
        loadRecentProjects()
    }

    public func loadRecentProjects() {
        self.recentProjects = recentStore.getRecentProjects()
    }

    public func openRepository(at url: URL) async {
        isLoading = true
        loadingMessage = "Analyzing repository..."
        errorMessage = nil

        do {
            let snap = try await analyzer.analyze(repositoryURL: url)
            self.snapshot = snap
            self.currentRepoURL = snap.path
            self.lastRefreshedAt = snap.refreshedAt
            self.refreshErrorMessage = snap.refreshError

            // Load saved session
            let sess = sessionStore.loadSession(for: snap.path.path)
            self.session = sess
            self.budgetMode = sess.preferredBudgetMode
            self.selectedProvider = sess.preferredExportTarget

            // Record in recent projects
            recentStore.recordProject(name: snap.name, path: snap.path.path)
            loadRecentProjects()

            // Merge suggested important files with saved pinned files
            var files = analyzer.suggestImportantFiles(snapshot: snap)
            for pinned in sess.pinnedFiles {
                if !files.contains(where: { $0.path == pinned }) {
                    files.insert(ImportantFile(path: pinned, reason: "Pinned file", isPinned: true), at: 0)
                } else if let index = files.firstIndex(where: { $0.path == pinned }) {
                    files[index].isPinned = true
                }
            }
            self.importantFiles = files

            self.currentScreen = .overview
            self.isLoading = false
        } catch {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    public func refreshRepository(silent: Bool = false) async -> Bool {
        guard let url = currentRepoURL else { return false }
        if !silent {
            isLoading = true
            loadingMessage = "Refreshing Git status..."
        }

        do {
            let snap = try await analyzer.analyze(repositoryURL: url)
            self.snapshot = snap
            self.lastRefreshedAt = snap.refreshedAt
            self.refreshErrorMessage = snap.refreshError

            // Refresh suggestions without overwriting user pins
            let suggestions = analyzer.suggestImportantFiles(snapshot: snap)
            for item in suggestions {
                if !importantFiles.contains(where: { $0.path == item.path }) {
                    importantFiles.append(item)
                }
            }

            if !silent {
                self.isLoading = false
                showToast("Repository refreshed")
            }
            return snap.refreshError == nil
        } catch {
            self.refreshErrorMessage = error.localizedDescription
            if !silent {
                self.isLoading = false
                self.errorMessage = "Refresh failed: \(error.localizedDescription)"
            }
            return false
        }
    }

    public func saveCurrentSession() {
        guard currentRepoURL != nil, var sess = session else { return }
        sess.pinnedFiles = importantFiles.filter(\.isPinned).map(\.path)
        sess.preferredBudgetMode = budgetMode
        sess.preferredExportTarget = selectedProvider
        sess.lastModified = Date()
        do {
            let saved = try sessionStore.saveSession(sess)
            self.session = saved
        } catch {
            self.errorMessage = "Failed to persist session: \(error.localizedDescription)"
        }
    }

    // MARK: - List Modifications

    public func addDecision(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        session?.decisions.append(Decision(text: SecretFilter.sanitizeText(trimmed), source: .user))
        saveCurrentSession()
    }

    public func removeDecision(id: UUID) {
        session?.decisions.removeAll { $0.id == id }
        saveCurrentSession()
    }

    public func addNextTask(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        session?.nextTasks.append(TaskItem(text: SecretFilter.sanitizeText(trimmed), source: .user))
        saveCurrentSession()
    }

    public func removeNextTask(id: UUID) {
        session?.nextTasks.removeAll { $0.id == id }
        saveCurrentSession()
    }

    public func addKnownProblem(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        session?.knownProblems.append(ProblemItem(text: SecretFilter.sanitizeText(trimmed), source: .user))
        saveCurrentSession()
    }

    public func removeKnownProblem(id: UUID) {
        session?.knownProblems.removeAll { $0.id == id }
        saveCurrentSession()
    }

    public func addCompletedWork(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        session?.completedWork.append(ContextItem(text: SecretFilter.sanitizeText(trimmed), source: .user))
        saveCurrentSession()
    }

    public func removeCompletedWork(text: String) {
        session?.completedWork.removeAll { $0.text == text }
        saveCurrentSession()
    }

    public func addRecentWork(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        session?.recentWork.append(ContextItem(text: SecretFilter.sanitizeText(trimmed), source: .user))
        saveCurrentSession()
    }

    public func removeRecentWork(text: String) {
        session?.recentWork.removeAll { $0.text == text }
        saveCurrentSession()
    }

    public func updateNotes(_ text: String) {
        session?.notes = SecretFilter.sanitizeText(text)
        saveCurrentSession()
    }

    public func addImportantFile(path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !importantFiles.contains(where: { $0.path == trimmed }), !SecretFilter.isSecretFile(path: trimmed) else { return }
        importantFiles.append(ImportantFile(path: trimmed, reason: "Manually added", isPinned: true))
        saveCurrentSession()
    }

    public func removeImportantFile(path: String) {
        importantFiles.removeAll { $0.path == path }
        saveCurrentSession()
    }

    public func togglePin(path: String) {
        if let index = importantFiles.firstIndex(where: { $0.path == path }) {
            importantFiles[index].isPinned.toggle()
            saveCurrentSession()
        }
    }

    // MARK: - Handoff Generation & Preview

    public func createHandoff() {
        Task { [weak self] in
            guard let self = self else { return }
            let refreshSuccess = await self.refreshRepository(silent: true)
            if !refreshSuccess && self.refreshErrorMessage != nil {
                self.pendingStaleAction = { [weak self] in
                    self?.proceedWithCreateHandoff()
                }
                self.showStaleExportAlert = true
            } else {
                self.proceedWithCreateHandoff()
            }
        }
    }

    public func proceedWithCreateHandoff() {
        guard let snap = snapshot else { return }
        saveCurrentSession()

        let handoff = buildCanonicalHandoff(from: snap)
        let generated = renderMarkdown(for: handoff, provider: selectedProvider, mode: budgetMode)
        self.generatedMarkdown = SecretFilter.sanitizeText(generated)
        self.isDraftModified = false
        self.currentScreen = .preview
    }

    public func selectBudgetMode(_ mode: TokenBudgetMode) {
        guard mode != budgetMode else { return }
        if isDraftModified {
            pendingDraftSwitchAction = { [weak self] in
                guard let self = self else { return }
                self.budgetMode = mode
                self.regeneratePreview()
            }
            showDiscardDraftAlert = true
        } else {
            self.budgetMode = mode
            regeneratePreview()
        }
    }

    public func selectProvider(_ provider: String) {
        guard provider != selectedProvider else { return }
        if isDraftModified {
            pendingDraftSwitchAction = { [weak self] in
                guard let self = self else { return }
                self.selectedProvider = provider
                self.regeneratePreview()
            }
            showDiscardDraftAlert = true
        } else {
            self.selectedProvider = provider
            regeneratePreview()
        }
    }

    public func regeneratePreview() {
        guard let snap = snapshot else { return }
        let handoff = buildCanonicalHandoff(from: snap)
        self.generatedMarkdown = SecretFilter.sanitizeText(renderMarkdown(for: handoff, provider: selectedProvider, mode: budgetMode))
        self.isDraftModified = false
    }

    public func updatePreviewForCurrentSettings() {
        regeneratePreview()
    }

    private func buildCanonicalHandoff(from snap: RepositorySnapshot) -> Handoff {
        let project = ProjectContext(
            name: snap.name,
            repositoryPath: snap.path.path,
            ecosystem: snap.projectMetadata.ecosystem,
            remoteURL: snap.remoteURL
        )

        let isStale = snap.refreshError != nil
        let state = CanonicalRepositoryState(
            branch: snap.branch ?? "main",
            headCommit: snap.headCommitHash,
            isClean: snap.isClean,
            modifiedFiles: snap.modifiedFiles.map(\.path),
            stagedFiles: snap.stagedFiles.map(\.path),
            untrackedFiles: snap.untrackedFiles.map(\.path),
            diffSummary: snap.diffSummary,
            refreshedAt: snap.refreshedAt,
            isStale: isStale,
            stalenessReason: snap.refreshError
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

    // MARK: - Clipboard & Export (Always preserves visible edits & sanitizes)

    public func copyToClipboard(provider: String) {
        self.selectedProvider = provider
        Task { [weak self] in
            guard let self = self else { return }
            let refreshSuccess = await self.refreshRepository(silent: true)
            if !refreshSuccess && self.refreshErrorMessage != nil {
                self.pendingStaleAction = { [weak self] in
                    self?.proceedWithCopyToClipboard(provider: provider)
                }
                self.showStaleExportAlert = true
            } else {
                self.proceedWithCopyToClipboard(provider: provider)
            }
        }
    }

    public func proceedWithCopyToClipboard(provider: String) {
        // Requirement 6: Copy copies the visible preview; both paths sanitize final text immediately before output
        let contentToCopy: String
        if !generatedMarkdown.isEmpty {
            contentToCopy = generatedMarkdown
        } else if let snap = snapshot {
            let handoff = buildCanonicalHandoff(from: snap)
            contentToCopy = renderMarkdown(for: handoff, provider: provider, mode: budgetMode)
        } else {
            return
        }

        let finalSanitizedText = SecretFilter.sanitizeText(contentToCopy)

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(finalSanitizedText, forType: .string)

        let providerLabel = provider == "claude" ? "Claude Code" :
                            provider == "codex" ? "Codex" :
                            provider == "cursor" ? "Cursor" : "Generic"
        showToast("Copied for \(providerLabel)!")
    }

    public func exportContextMarkdownFile() {
        Task { [weak self] in
            guard let self = self else { return }
            let refreshSuccess = await self.refreshRepository(silent: true)
            if !refreshSuccess && self.refreshErrorMessage != nil {
                self.pendingStaleAction = { [weak self] in
                    self?.proceedWithExportContextMarkdownFile()
                }
                self.showStaleExportAlert = true
            } else {
                self.proceedWithExportContextMarkdownFile()
            }
        }
    }

    public func proceedWithExportContextMarkdownFile() {
        guard let snap = snapshot else { return }
        let destinationURL = snap.path.appendingPathComponent("context.md")

        // Requirement 6: Save writes the visible preview, sanitized immediately before output
        let rawContent: String
        if !generatedMarkdown.isEmpty {
            rawContent = generatedMarkdown
        } else {
            let handoff = buildCanonicalHandoff(from: snap)
            rawContent = renderMarkdown(for: handoff, provider: "generic", mode: budgetMode)
        }

        let finalContent = SecretFilter.sanitizeText(rawContent)

        do {
            try finalContent.write(to: destinationURL, atomically: true, encoding: .utf8)
            showToast("Saved context.md to repository root")
        } catch {
            errorMessage = "Failed to export context.md: \(error.localizedDescription)"
        }
    }

    public func showToast(_ message: String) {
        self.toastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if self.toastMessage == message {
                self.toastMessage = nil
            }
        }
    }
}

