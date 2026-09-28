import Foundation

public final class RepositoryAnalyzer: Sendable {
    private let gitClient: GitClient
    private let projectDetector: ProjectDetector
    private let treeGenerator: TreeGenerator
    private let todoScanner: TodoScanner
    private let instructionDetector: InstructionFileDetector

    public init(
        gitClient: GitClient = GitClient(),
        projectDetector: ProjectDetector = ProjectDetector(),
        treeGenerator: TreeGenerator = TreeGenerator(),
        todoScanner: TodoScanner = TodoScanner(),
        instructionDetector: InstructionFileDetector = InstructionFileDetector()
    ) {
        self.gitClient = gitClient
        self.projectDetector = projectDetector
        self.treeGenerator = treeGenerator
        self.todoScanner = todoScanner
        self.instructionDetector = instructionDetector
    }

    public func analyze(repositoryURL: URL) async throws -> RepositorySnapshot {
        // 0. Verify directory exists
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: repositoryURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw CocoaError(.fileNoSuchFile)
        }

        // 1. Resolve root Git directory or fallback to local directory
        let isGitRepo: Bool
        let rootURL: URL
        do {
            rootURL = try await gitClient.resolveRepositoryRoot(at: repositoryURL)
            isGitRepo = true
        } catch {
            rootURL = repositoryURL
            isGitRepo = false
        }
        let repoName = rootURL.lastPathComponent

        // 2. Fetch Git state asynchronously if inside Git repository
        let branch: String?
        let remoteURL: String?
        let headHash: String?
        let commits: [Commit]
        let diffSummary: DiffSummary?
        var statusError: String? = nil
        let safeModified: [ChangedFile]
        let safeStaged: [ChangedFile]
        let safeUntracked: [ChangedFile]
        let hiddenSensitiveCount: Int
        let hasOmittedSensitive: Bool
        let isGitDirty: Bool

        if isGitRepo {
            async let branchTask = gitClient.getCurrentBranch(at: rootURL)
            async let remoteTask = gitClient.getRemoteURL(at: rootURL)
            async let headHashTask = gitClient.getHeadCommitHash(at: rootURL)
            async let commitsTask = gitClient.getRecentCommits(at: rootURL, count: 10)
            async let diffTask = gitClient.getDiffSummary(at: rootURL)

            let status: (modified: [ChangedFile], staged: [ChangedFile], untracked: [ChangedFile])
            do {
                status = try await gitClient.getStatus(at: rootURL)
            } catch {
                statusError = error.localizedDescription
                status = (modified: [], staged: [], untracked: [])
            }

            branch = await branchTask
            remoteURL = await remoteTask
            headHash = await headHashTask
            commits = await commitsTask
            diffSummary = await diffTask

            // 3. Filter secrets from file status and track hidden sensitive changes
            let allModified = status.modified
            let allStaged = status.staged
            let allUntracked = status.untracked

            safeModified = allModified.filter { !SecretFilter.isSecretFile(path: $0.path) }
            safeStaged = allStaged.filter { !SecretFilter.isSecretFile(path: $0.path) }
            safeUntracked = allUntracked.filter { !SecretFilter.isSecretFile(path: $0.path) }

            let totalGitChanges = allModified.count + allStaged.count + allUntracked.count
            let visibleSafeChanges = safeModified.count + safeStaged.count + safeUntracked.count
            hiddenSensitiveCount = totalGitChanges - visibleSafeChanges
            hasOmittedSensitive = hiddenSensitiveCount > 0
            isGitDirty = totalGitChanges > 0
        } else {
            branch = "non-git"
            remoteURL = nil
            headHash = nil
            commits = []
            diffSummary = nil
            safeModified = []
            safeStaged = []
            safeUntracked = []
            hiddenSensitiveCount = 0
            hasOmittedSensitive = false
            isGitDirty = false
        }

        // 4. Inspect README (sanitized)
        let readmeContent = readReadme(at: rootURL).map { SecretFilter.sanitizeText($0) }

        // 5. Detect project metadata
        let metadata = projectDetector.detect(at: rootURL)

        // 6. Generate compact tree
        let treeSummary = treeGenerator.generateCompactTree(at: rootURL)

        // 7. Detect instruction files (already sanitized in detector)
        let instructions = instructionDetector.detect(at: rootURL)

        // 8. Scan for TODOs (sanitized)
        let allChangedPaths = safeModified.map(\.path) + safeStaged.map(\.path) + safeUntracked.map(\.path)
        let rawTodos = todoScanner.scan(at: rootURL, changedFiles: allChangedPaths, maxCount: 25)
        let todos = rawTodos.map {
            TodoItem(file: $0.file, line: $0.line, kind: $0.kind, comment: SecretFilter.sanitizeText($0.comment), isInsideChangedFile: $0.isInsideChangedFile)
        }

        return RepositorySnapshot(
            name: repoName,
            path: rootURL,
            branch: branch,
            remoteURL: remoteURL,
            headCommitHash: headHash,
            modifiedFiles: safeModified,
            stagedFiles: safeStaged,
            untrackedFiles: safeUntracked,
            recentCommits: commits,
            fileTreeSummary: treeSummary,
            readme: readmeContent,
            projectMetadata: metadata,
            detectedInstructionFiles: instructions,
            todos: todos,
            diffSummary: diffSummary,
            refreshedAt: Date(),
            refreshError: statusError,
            isGitDirty: isGitDirty,
            hiddenSensitiveChangesCount: hiddenSensitiveCount,
            hasOmittedSensitiveChanges: hasOmittedSensitive,
            isGitRepository: isGitRepo
        )
    }

    /// Intelligently suggests important files using deterministic rules
    public func suggestImportantFiles(snapshot: RepositorySnapshot) -> [ImportantFile] {
        var results: [ImportantFile] = []
        var seenPaths: Set<String> = []

        func addFile(_ path: String, reason: String) {
            guard !seenPaths.contains(path), !SecretFilter.isSecretFile(path: path) else { return }
            seenPaths.insert(path)
            results.append(ImportantFile(path: path, reason: reason))
        }

        // 1. Files modified in current git status
        for file in snapshot.modifiedFiles.prefix(4) {
            addFile(file.path, reason: "Modified in working tree")
        }
        for file in snapshot.stagedFiles.prefix(2) {
            addFile(file.path, reason: "Staged for commit")
        }
        for file in snapshot.untrackedFiles.prefix(2) {
            addFile(file.path, reason: "Untracked new file")
        }

        // 2. Detected instruction files
        for instruction in snapshot.detectedInstructionFiles {
            addFile(instruction.path, reason: "Project instruction source")
        }

        // 3. Config / manifest files
        for config in snapshot.projectMetadata.detectedConfigFiles {
            addFile(config, reason: "Project configuration")
        }

        // 4. README
        if snapshot.readme != nil {
            addFile("README.md", reason: "Project overview")
        }

        return Array(results.prefix(8))
    }

    private func readReadme(at rootURL: URL) -> String? {
        let possibleNames = ["README.md", "readme.md", "README", "Readme.md"]
        for name in possibleNames {
            let fileURL = rootURL.appendingPathComponent(name)
            if let content = try? String(contentsOf: fileURL, encoding: .utf8), !content.isEmpty {
                // Return trimmed first portion
                let lines = content.components(separatedBy: .newlines)
                return lines.prefix(30).joined(separator: "\n")
            }
        }
        return nil
    }
}
