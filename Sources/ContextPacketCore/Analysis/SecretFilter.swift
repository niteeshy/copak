import Foundation

public struct SecretFilter: Sendable {
    private static let ignoredFilePatterns: [String] = [
        ".env",
        ".env.",
        ".pem",
        "id_rsa",
        "id_ed25519",
        "id_dsa",
        "id_ecdsa",
        "credentials.",
        ".p12",
        ".key",
        ".keystore",
        ".pkcs12",
        ".secret",
        "secrets.",
        "secret.",
        "-secret.",
        "_secret.",
        "service-account.",
        "client_secret."
    ]

    // Quoted sensitive assignment regex: matches key = "secret with spaces" or 'secret with spaces'
    // Handles quoted keys (JSON) or bare keys, e.g. PASSWORD="correct horse battery staple"
    private static let quotedAssignmentRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: "(?i)([\"']?)([a-z0-9_]*(?:api_?key|secret|password|passwd|pwd|token|credentials?|private_?key)[a-z0-9_]*)\\1(\\s*[:=]\\s*)([\"'])([^\"'\\r\\n]*)\\4",
            options: []
        )
    }()

    // Unquoted sensitive assignment regex: matches key = secret_value
    private static let unquotedAssignmentRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: "(?i)([\"']?)([a-z0-9_]*(?:api_?key|secret|password|passwd|pwd|token|credentials?|private_?key)[a-z0-9_]*)\\1(\\s*[:=]\\s*)([^\r\n\\s\"';,]+)",
            options: []
        )
    }()

    // Embedded URL credentials: scheme://user:pass@host (http, https, postgres, redis, git, etc.)
    private static let urlCredentialsRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: "([a-zA-Z][a-zA-Z0-9+.-]*://)([^/\\s:@]+):([^@/\\s]+)@",
            options: [.caseInsensitive]
        )
    }()

    // PEM / Private Key block regex
    private static let privateKeyBlockRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: "-----BEGIN (?:[A-Z0-9_-]+ )?PRIVATE KEY-----[\\s\\S]*?-----END (?:[A-Z0-9_-]+ )?PRIVATE KEY-----",
            options: [.caseInsensitive]
        )
    }()

    // Common API keys and tokens
    private static let tokenPatterns: [(regex: NSRegularExpression?, placeholder: String)] = [
        (try? NSRegularExpression(pattern: "\\b(sk-(?:proj-|live-)?[a-zA-Z0-9_\\-]{20,})\\b"), "[REDACTED_API_KEY]"),
        (try? NSRegularExpression(pattern: "\\b(sk-ant-[a-zA-Z0-9_\\-]{20,})\\b"), "[REDACTED_API_KEY]"),
        (try? NSRegularExpression(pattern: "\\b(AKIA[0-9A-Z]{16})\\b"), "[REDACTED_AWS_KEY]"),
        (try? NSRegularExpression(pattern: "\\b(gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})\\b"), "[REDACTED_GITHUB_TOKEN]"),
        (try? NSRegularExpression(pattern: "\\b(xox[baprs]-[0-9A-Za-z]{10,48})\\b"), "[REDACTED_SLACK_TOKEN]"),
        (try? NSRegularExpression(pattern: "\\b([sr]k_live_[0-9a-zA-Z]{24,})\\b"), "[REDACTED_STRIPE_KEY]"),
        (try? NSRegularExpression(pattern: "\\b(eyJ[a-zA-Z0-9_\\-]{10,}\\.eyJ[a-zA-Z0-9_\\-]{10,}\\.[a-zA-Z0-9_\\-]+)\\b"), "[REDACTED_JWT_TOKEN]"),
        (try? NSRegularExpression(pattern: "(?i)\\b(Bearer\\s+)([a-zA-Z0-9_.\\-~+/=]{20,})\\b"), "$1[REDACTED_TOKEN]")
    ]

    public init() {}

    /// Returns true if the file or path is considered sensitive and must be excluded.
    public static func isSecretFile(path: String) -> Bool {
        // If this represents a git rename (e.g., "old.txt -> .env"), check both parts
        if path.contains(" -> ") {
            let parts = path.components(separatedBy: " -> ")
            for part in parts {
                if isSecretFile(path: part.trimmingCharacters(in: .whitespaces)) {
                    return true
                }
            }
        }

        let filename = (path as NSString).lastPathComponent.lowercased()
        let lowercasedPath = path.lowercased()

        for pattern in ignoredFilePatterns {
            if filename == pattern || filename.hasPrefix(pattern) || filename.hasSuffix(pattern) || lowercasedPath.contains("/" + pattern) {
                return true
            }
        }
        return false
    }

    /// Filters out secret files from any list of file paths.
    public static func filterPaths(_ paths: [String]) -> [String] {
        paths.filter { !isSecretFile(path: $0) }
    }

    /// Sanitizes arbitrary text by redacting API keys, assignments, URL credentials, and PEM private keys.
    public static func sanitizeText(_ text: String) -> String {
        var result = text

        // 1. Redact Private Key blocks (multiline)
        if let regex = privateKeyBlockRegex {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "[REDACTED_PRIVATE_KEY_BLOCK]"
            )
        }

        // 2. Redact URL credentials (https://user:password@host -> https://user:[REDACTED_CREDENTIAL]@host)
        if let regex = urlCredentialsRegex {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "$1$2:[REDACTED_CREDENTIAL]@"
            )
        }

        // 3. Redact quoted sensitive variable assignments (including spaces inside quotes)
        if let regex = quotedAssignmentRegex {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "$1$2$1$3$4[REDACTED_SECRET]$4"
            )
        }

        // 4. Redact unquoted sensitive variable assignments
        if let regex = unquotedAssignmentRegex {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "$1$2$1$3[REDACTED_SECRET]"
            )
        }

        // 5. Redact known token signatures
        for item in tokenPatterns {
            guard let regex = item.regex else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: item.placeholder
            )
        }

        return result
    }

    /// Sanitizes git diff output by completely excluding hunks of secret files and redacting remaining text.
    public static func sanitizeDiff(_ diff: String) -> String {
        let diffSections = diff.components(separatedBy: "diff --git ")
        var sanitizedSections: [String] = []

        for (index, section) in diffSections.enumerated() {
            if index == 0 && section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }

            // Extract file path from header: a/path b/path
            let firstLine = section.components(separatedBy: .newlines).first ?? ""
            var isSecret = false
            let parts = firstLine.components(separatedBy: " ")
            for part in parts {
                let cleanPart = part.hasPrefix("a/") || part.hasPrefix("b/") ? String(part.dropFirst(2)) : part
                if isSecretFile(path: cleanPart) {
                    isSecret = true
                    break
                }
            }

            if !isSecret {
                // Check rename from / rename to headers
                for line in section.components(separatedBy: .newlines) {
                    if line.hasPrefix("rename from ") {
                        let path = String(line.dropFirst("rename from ".count)).trimmingCharacters(in: .whitespaces)
                        if isSecretFile(path: path) {
                            isSecret = true
                            break
                        }
                    } else if line.hasPrefix("rename to ") {
                        let path = String(line.dropFirst("rename to ".count)).trimmingCharacters(in: .whitespaces)
                        if isSecretFile(path: path) {
                            isSecret = true
                            break
                        }
                    }
                }
            }

            if isSecret {
                sanitizedSections.append("[EXCLUDED: Secret file diff omitted for safety]")
            } else {
                sanitizedSections.append("diff --git " + sanitizeText(section))
            }
        }

        return sanitizedSections.joined(separator: "\n")
    }

    /// Central pipeline: sanitizes an entire Handoff model before export or preview.
    /// Sanitizes every textual field and preserves all DiffSummary metadata.
    public static func sanitizeHandoff(_ handoff: Handoff) -> Handoff {
        var copy = handoff
        copy.currentGoal = sanitizeText(copy.currentGoal)

        copy.completedWork = copy.completedWork.map {
            ContextItem(text: sanitizeText($0.text), source: $0.source)
        }

        copy.decisions = copy.decisions.map {
            Decision(id: $0.id, text: sanitizeText($0.text), source: $0.source)
        }

        copy.nextTasks = copy.nextTasks.map {
            TaskItem(id: $0.id, text: sanitizeText($0.text), source: $0.source)
        }

        copy.knownProblems = copy.knownProblems.map {
            ProblemItem(id: $0.id, text: sanitizeText($0.text), source: $0.source)
        }

        copy.recentWork = copy.recentWork.map {
            ContextItem(text: sanitizeText($0.text), source: $0.source)
        }

        copy.recentCommits = copy.recentCommits.map {
            Commit(
                hash: $0.hash,
                shortHash: $0.shortHash,
                author: sanitizeText($0.author),
                date: $0.date,
                subject: sanitizeText($0.subject)
            )
        }

        copy.todos = copy.todos.map {
            TodoItem(
                file: sanitizeText($0.file),
                line: $0.line,
                kind: $0.kind,
                comment: sanitizeText($0.comment),
                isInsideChangedFile: $0.isInsideChangedFile
            )
        }

        if let notes = copy.notes {
            copy.notes = sanitizeText(notes)
        }

        // Sanitize project metadata
        copy.project = ProjectContext(
            name: sanitizeText(copy.project.name),
            repositoryPath: sanitizeText(copy.project.repositoryPath),
            ecosystem: copy.project.ecosystem,
            remoteURL: copy.project.remoteURL.map { sanitizeText($0) }
        )

        // Filter and sanitize important files
        copy.importantFiles = copy.importantFiles
            .filter { !isSecretFile(path: $0.path) }
            .map { ImportantFile(path: sanitizeText($0.path), reason: sanitizeText($0.reason), isPinned: $0.isPinned) }

        // Sanitize instruction files
        copy.detectedInstructions = copy.detectedInstructions.map {
            InstructionFile(
                path: sanitizeText($0.path),
                filename: sanitizeText($0.filename),
                scope: sanitizeText($0.scope),
                content: sanitizeText($0.content),
                isTruncated: $0.isTruncated,
                snippet: $0.snippet.map { sanitizeText($0) }
            )
        }

        // Filter state files and sanitize diff summary while preserving all metadata
        let filteredModified = filterPaths(copy.currentState.modifiedFiles).map { sanitizeText($0) }
        let filteredStaged = filterPaths(copy.currentState.stagedFiles).map { sanitizeText($0) }
        let filteredUntracked = filterPaths(copy.currentState.untrackedFiles).map { sanitizeText($0) }

        var sanitizedDiff: DiffSummary? = nil
        if let diff = copy.currentState.diffSummary {
            let filteredFiles = diff.files
                .filter { !isSecretFile(path: $0.path) }
                .map { FileDelta(path: sanitizeText($0.path), additions: $0.additions, deletions: $0.deletions, isStaged: $0.isStaged) }
            let sanitizedSnippet = diff.rawDiffSnippet.map { sanitizeDiff($0) }
            sanitizedDiff = DiffSummary(
                filesChanged: filteredFiles.count,
                additions: diff.additions,
                deletions: diff.deletions,
                stagedAdditions: diff.stagedAdditions,
                stagedDeletions: diff.stagedDeletions,
                stagedFilesCount: diff.stagedFilesCount,
                unstagedAdditions: diff.unstagedAdditions,
                unstagedDeletions: diff.unstagedDeletions,
                unstagedFilesCount: diff.unstagedFilesCount,
                files: filteredFiles,
                rawDiffSnippet: sanitizedSnippet,
                isTruncated: diff.isTruncated
            )
        }

        copy.currentState = CanonicalRepositoryState(
            branch: sanitizeText(copy.currentState.branch),
            headCommit: copy.currentState.headCommit.map { sanitizeText($0) },
            isClean: copy.currentState.isClean,
            modifiedFiles: filteredModified,
            stagedFiles: filteredStaged,
            untrackedFiles: filteredUntracked,
            diffSummary: sanitizedDiff,
            refreshedAt: copy.currentState.refreshedAt,
            isStale: copy.currentState.isStale,
            stalenessReason: copy.currentState.stalenessReason.map { sanitizeText($0) },
            hasOmittedSensitiveChanges: copy.currentState.hasOmittedSensitiveChanges,
            hiddenSensitiveChangesCount: copy.currentState.hiddenSensitiveChangesCount,
            isGitDirty: copy.currentState.isGitDirty,
            isEditedDraft: copy.currentState.isEditedDraft,
            isGitRepository: copy.currentState.isGitRepository
        )

        return copy
    }

    /// Central pipeline: sanitizes SavedProjectSession before persistence.
    public static func sanitizeSession(_ session: SavedProjectSession) -> SavedProjectSession {
        var copy = session
        copy.currentGoal = sanitizeText(copy.currentGoal)
        copy.decisions = copy.decisions.map {
            Decision(id: $0.id, text: sanitizeText($0.text), source: $0.source)
        }
        copy.nextTasks = copy.nextTasks.map {
            TaskItem(id: $0.id, text: sanitizeText($0.text), source: $0.source)
        }
        copy.knownProblems = copy.knownProblems.map {
            ProblemItem(id: $0.id, text: sanitizeText($0.text), source: $0.source)
        }
        copy.completedWork = copy.completedWork.map {
            ContextItem(text: sanitizeText($0.text), source: $0.source)
        }
        copy.recentWork = copy.recentWork.map {
            ContextItem(text: sanitizeText($0.text), source: $0.source)
        }
        if let notes = copy.notes {
            copy.notes = sanitizeText(notes)
        }
        copy.pinnedFiles = filterPaths(copy.pinnedFiles).map { sanitizeText($0) }
        return copy
    }
}

