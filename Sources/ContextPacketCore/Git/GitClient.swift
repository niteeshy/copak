import Foundation

public final class GitClient: Sendable {
    private let runner: GitCommandRunner

    public init(runner: GitCommandRunner = GitCommandRunner()) {
        self.runner = runner
    }

    /// Verifies that directory is inside a Git repository and returns the top-level URL.
    public func resolveRepositoryRoot(at directory: URL) async throws -> URL {
        let result = try await runner.run(arguments: ["rev-parse", "--show-toplevel"], in: directory)
        guard result.isSuccess else {
            throw GitError.notAGitRepository(directory.path)
        }
        let cleanPath = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: cleanPath)
    }

    /// Fetches the current branch name, or a description of detached HEAD.
    public func getCurrentBranch(at repoURL: URL) async -> String? {
        let branchResult = try? await runner.run(arguments: ["branch", "--show-current"], in: repoURL)
        if let branch = branchResult?.stdout.trimmingCharacters(in: .whitespacesAndNewlines), !branch.isEmpty {
            return branch
        }

        // Detached HEAD fallback
        let headResult = try? await runner.run(arguments: ["rev-parse", "--short", "HEAD"], in: repoURL)
        if let head = headResult?.stdout.trimmingCharacters(in: .whitespacesAndNewlines), !head.isEmpty {
            return "detached at \(head)"
        }

        return "Initial (no commits)"
    }

    /// Fetches remote origin URL if configured, sanitized for embedded credentials.
    public func getRemoteURL(at repoURL: URL) async -> String? {
        let result = try? await runner.run(arguments: ["remote", "get-url", "origin"], in: repoURL)
        guard let trimmed = result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return SecretFilter.sanitizeText(trimmed)
    }

    /// Fetches the HEAD commit hash.
    public func getHeadCommitHash(at repoURL: URL) async -> String? {
        let result = try? await runner.run(arguments: ["rev-parse", "HEAD"], in: repoURL)
        let trimmed = result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    /// Retrieves status arrays for modified, staged, and untracked files.
    public func getStatus(at repoURL: URL) async throws -> (
        modified: [ChangedFile],
        staged: [ChangedFile],
        untracked: [ChangedFile]
    ) {
        let result = try await runner.run(arguments: ["status", "--porcelain=v1", "-uall"], in: repoURL)
        guard result.isSuccess else {
            throw GitError.commandFailed(command: "git status", exitCode: result.exitCode, message: result.stderr)
        }

        var modified: [ChangedFile] = []
        var staged: [ChangedFile] = []
        var untracked: [ChangedFile] = []

        let lines = result.stdout.components(separatedBy: .newlines)
        for line in lines where line.count >= 3 {
            let indexCode = line[line.startIndex]
            let workTreeCode = line[line.index(after: line.startIndex)]
            var filePath = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)

            // Strip quotation marks if git escaped the path
            if filePath.hasPrefix("\"") && filePath.hasSuffix("\"") && filePath.count >= 2 {
                filePath = String(filePath.dropFirst().dropLast())
            }

            // If renamed, git format is: "old -> new"
            if filePath.contains(" -> ") {
                let parts = filePath.components(separatedBy: " -> ")
                if let target = parts.last {
                    filePath = target
                }
            }

            // Untracked
            if indexCode == "?" && workTreeCode == "?" {
                untracked.append(ChangedFile(path: filePath, statusLetter: "??"))
                continue
            }

            // Staged in index
            if indexCode != " " && indexCode != "?" {
                staged.append(ChangedFile(path: filePath, statusLetter: String(indexCode)))
            }

            // Worktree modifications
            if workTreeCode != " " && workTreeCode != "?" {
                modified.append(ChangedFile(path: filePath, statusLetter: String(workTreeCode)))
            }
        }

        return (modified: modified, staged: staged, untracked: untracked)
    }

    /// Retrieves recent commits up to the specified count, sanitizing commit subjects and authors.
    public func getRecentCommits(at repoURL: URL, count: Int = 10) async -> [Commit] {
        let format = "%H%x1f%h%x1f%an%x1f%ad%x1f%s"
        let result = try? await runner.run(
            arguments: ["log", "-n", "\(count)", "--pretty=format:\(format)", "--date=short"],
            in: repoURL
        )

        guard let output = result?.stdout, !output.isEmpty else {
            return []
        }

        var commits: [Commit] = []
        for line in output.components(separatedBy: .newlines) where !line.isEmpty {
            let parts = line.components(separatedBy: "\u{1F}")
            if parts.count >= 5 {
                let author = SecretFilter.sanitizeText(parts[2])
                let subject = SecretFilter.sanitizeText(parts[4])
                commits.append(Commit(
                    hash: parts[0],
                    shortHash: parts[1],
                    author: author,
                    date: parts[3],
                    subject: subject
                ))
            }
        }
        return commits
    }

    /// Computes diff summary statistics (files changed, additions, deletions, staged vs unstaged)
    /// and generates a bounded, sanitized diff excerpt excluding secret files.
    public func getDiffSummary(at repoURL: URL, maxDiffChars: Int = 8_000) async -> DiffSummary {
        // Run git diff --numstat for unstaged and staged
        let unstagedStat = try? await runner.run(arguments: ["diff", "--numstat"], in: repoURL)
        let stagedStat = try? await runner.run(arguments: ["diff", "--cached", "--numstat"], in: repoURL)

        var deltaDict: [String: (add: Int, del: Int, isStaged: Bool)] = [:]
        var stagedAdd = 0, stagedDel = 0, stagedCount = 0
        var unstagedAdd = 0, unstagedDel = 0, unstagedCount = 0

        func parseNumstat(_ output: String?, isStaged: Bool) {
            guard let text = output else { return }
            for line in text.components(separatedBy: .newlines) where !line.isEmpty {
                let parts = line.components(separatedBy: .whitespaces)
                guard parts.count >= 3 else { continue }
                let path = parts.dropFirst(2).joined(separator: " ").trimmingCharacters(in: .whitespaces)
                // Filter out secret files from stats and diffs
                if SecretFilter.isSecretFile(path: path) {
                    continue
                }
                let add = Int(parts[0]) ?? 0
                let del = Int(parts[1]) ?? 0

                if isStaged {
                    stagedAdd += add
                    stagedDel += del
                    stagedCount += 1
                } else {
                    unstagedAdd += add
                    unstagedDel += del
                    unstagedCount += 1
                }

                let current = deltaDict[path] ?? (0, 0, isStaged)
                deltaDict[path] = (current.add + add, current.del + del, isStaged || current.isStaged)
            }
        }

        parseNumstat(stagedStat?.stdout, isStaged: true)
        parseNumstat(unstagedStat?.stdout, isStaged: false)

        let fileDeltas = deltaDict.map { path, stats in
            FileDelta(path: path, additions: stats.add, deletions: stats.del, isStaged: stats.isStaged)
        }.sorted { $0.path < $1.path }

        let totalAdditions = fileDeltas.reduce(0) { $0 + $1.additions }
        let totalDeletions = fileDeltas.reduce(0) { $0 + $1.deletions }

        // Bounded, sanitized diff excerpt combining staged and unstaged diffs
        // Never include raw secret-file diffs!
        var combinedDiff = ""
        let stagedDiffResult = try? await runner.run(arguments: ["diff", "--cached"], in: repoURL)
        let unstagedDiffResult = try? await runner.run(arguments: ["diff"], in: repoURL)

        if let s = stagedDiffResult?.stdout, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            combinedDiff += "# Staged changes:\n" + s + "\n"
        }
        if let u = unstagedDiffResult?.stdout, !u.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            combinedDiff += "# Unstaged changes:\n" + u + "\n"
        }

        var isTruncated = false
        var snippet: String? = nil
        if !combinedDiff.isEmpty {
            let sanitized = SecretFilter.sanitizeDiff(combinedDiff)
            if sanitized.count > maxDiffChars {
                isTruncated = true
                snippet = String(sanitized.prefix(maxDiffChars)) + "\n\n... [Diff excerpt truncated at \(maxDiffChars) characters for budget safety]"
            } else {
                snippet = sanitized
            }
        }

        return DiffSummary(
            filesChanged: fileDeltas.count,
            additions: totalAdditions,
            deletions: totalDeletions,
            stagedAdditions: stagedAdd,
            stagedDeletions: stagedDel,
            stagedFilesCount: stagedCount,
            unstagedAdditions: unstagedAdd,
            unstagedDeletions: unstagedDel,
            unstagedFilesCount: unstagedCount,
            files: fileDeltas,
            rawDiffSnippet: snippet,
            isTruncated: isTruncated
        )
    }
}
