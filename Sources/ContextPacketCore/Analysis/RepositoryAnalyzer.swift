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
        // 1. Resolve root Git directory
        let rootURL = try await gitClient.resolveRepositoryRoot(at: repositoryURL)
        let repoName = rootURL.lastPathComponent

        // 2. Fetch Git state asynchronously
        async let branchTask = gitClient.getCurrentBranch(at: rootURL)
        async let remoteTask = gitClient.getRemoteURL(at: rootURL)
        async let headHashTask = gitClient.getHeadCommitHash(at: rootURL)
        async let commitsTask = gitClient.getRecentCommits(at: rootURL, count: 10)
        async let diffTask = gitClient.getDiffSummary(at: rootURL)

        var statusError: String? = nil
        let status: (modified: [ChangedFile], staged: [ChangedFile], untracked: [ChangedFile])
        do {
            status = try await gitClient.getStatus(at: rootURL)
        } catch {
            statusError = error.localizedDescription
            status = (modified: [], staged: [], untracked: [])
        }

        let branch = await branchTask
        let remoteURL = await remoteTask
        let headHash = await headHashTask
        let commits = await commitsTask
        let diffSummary = await diffTask

        // 3. Filter secrets from file status
        let safeModified = status.modified.filter { !SecretFilter.isSecretFile(path: $0.path) }
        let safeStaged = status.staged.filter { !SecretFilter.isSecretFile(path: $0.path) }
        let safeUntracked = status.untracked.filter { !SecretFilter.isSecretFile(path: $0.path) }

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
            refreshError: statusError
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
