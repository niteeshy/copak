import Foundation

public struct ChangedFile: Codable, Sendable, Equatable, Identifiable {
    public var id: String { path }
    public let path: String
    public let statusLetter: String // "M", "A", "D", "R", "??"
    
    public init(path: String, statusLetter: String) {
        self.path = path
        self.statusLetter = statusLetter
    }
}

public struct Commit: Codable, Sendable, Equatable, Identifiable {
    public var id: String { hash }
    public let hash: String
    public let shortHash: String
    public let author: String
    public let date: String
    public let subject: String

    public init(
        hash: String,
        shortHash: String,
        author: String,
        date: String,
        subject: String
    ) {
        self.hash = hash
        self.shortHash = shortHash
        self.author = author
        self.date = date
        self.subject = subject
    }
}

public struct InstructionFile: Codable, Sendable, Equatable, Identifiable {
    public var id: String { path }
    public let path: String
    public let filename: String
    public let scope: String
    public let content: String
    public let isTruncated: Bool
    public let snippet: String?

    public init(
        path: String,
        filename: String,
        scope: String = "root",
        content: String = "",
        isTruncated: Bool = false,
        snippet: String? = nil
    ) {
        self.path = path
        self.filename = filename
        self.scope = scope
        self.content = content
        self.isTruncated = isTruncated
        self.snippet = snippet ?? (content.isEmpty ? nil : String(content.prefix(300)))
    }

    public init(
        path: String,
        scope: String = "root",
        content: String = "",
        isTruncated: Bool = false,
        snippet: String? = nil
    ) {
        let filename = (path as NSString).lastPathComponent
        self.init(
            path: path,
            filename: filename,
            scope: scope,
            content: content,
            isTruncated: isTruncated,
            snippet: snippet
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        filename = try container.decode(String.self, forKey: .filename)
        scope = try container.decodeIfPresent(String.self, forKey: .scope) ?? "root"
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        isTruncated = try container.decodeIfPresent(Bool.self, forKey: .isTruncated) ?? false
        snippet = try container.decodeIfPresent(String.self, forKey: .snippet)
    }
}

public struct RepositorySnapshot: Codable, Sendable, Equatable {
    public let name: String
    public let path: URL
    public let branch: String?
    public let remoteURL: String?
    public let headCommitHash: String?
    public let modifiedFiles: [ChangedFile]
    public let stagedFiles: [ChangedFile]
    public let untrackedFiles: [ChangedFile]
    public let recentCommits: [Commit]
    public let fileTreeSummary: String
    public let readme: String?
    public let projectMetadata: ProjectMetadata
    public let detectedInstructionFiles: [InstructionFile]
    public let todos: [TodoItem]
    public let diffSummary: DiffSummary?
    public let refreshedAt: Date
    public let refreshError: String?

    public init(
        name: String,
        path: URL,
        branch: String?,
        remoteURL: String?,
        headCommitHash: String?,
        modifiedFiles: [ChangedFile],
        stagedFiles: [ChangedFile],
        untrackedFiles: [ChangedFile],
        recentCommits: [Commit],
        fileTreeSummary: String,
        readme: String?,
        projectMetadata: ProjectMetadata,
        detectedInstructionFiles: [InstructionFile],
        todos: [TodoItem],
        diffSummary: DiffSummary?,
        refreshedAt: Date = Date(),
        refreshError: String? = nil
    ) {
        self.name = name
        self.path = path
        self.branch = branch
        self.remoteURL = remoteURL
        self.headCommitHash = headCommitHash
        self.modifiedFiles = modifiedFiles
        self.stagedFiles = stagedFiles
        self.untrackedFiles = untrackedFiles
        self.recentCommits = recentCommits
        self.fileTreeSummary = fileTreeSummary
        self.readme = readme
        self.projectMetadata = projectMetadata
        self.detectedInstructionFiles = detectedInstructionFiles
        self.todos = todos
        self.diffSummary = diffSummary
        self.refreshedAt = refreshedAt
        self.refreshError = refreshError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(URL.self, forKey: .path)
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        remoteURL = try container.decodeIfPresent(String.self, forKey: .remoteURL)
        headCommitHash = try container.decodeIfPresent(String.self, forKey: .headCommitHash)
        modifiedFiles = try container.decodeIfPresent([ChangedFile].self, forKey: .modifiedFiles) ?? []
        stagedFiles = try container.decodeIfPresent([ChangedFile].self, forKey: .stagedFiles) ?? []
        untrackedFiles = try container.decodeIfPresent([ChangedFile].self, forKey: .untrackedFiles) ?? []
        recentCommits = try container.decodeIfPresent([Commit].self, forKey: .recentCommits) ?? []
        fileTreeSummary = try container.decodeIfPresent(String.self, forKey: .fileTreeSummary) ?? ""
        readme = try container.decodeIfPresent(String.self, forKey: .readme)
        projectMetadata = try container.decode(ProjectMetadata.self, forKey: .projectMetadata)
        detectedInstructionFiles = try container.decodeIfPresent([InstructionFile].self, forKey: .detectedInstructionFiles) ?? []
        todos = try container.decodeIfPresent([TodoItem].self, forKey: .todos) ?? []
        diffSummary = try container.decodeIfPresent(DiffSummary.self, forKey: .diffSummary)
        refreshedAt = try container.decodeIfPresent(Date.self, forKey: .refreshedAt) ?? Date()
        refreshError = try container.decodeIfPresent(String.self, forKey: .refreshError)
    }

    public var isClean: Bool {
        modifiedFiles.isEmpty && stagedFiles.isEmpty && untrackedFiles.isEmpty
    }

    public var allChangedFilePaths: [String] {
        var paths = [String]()
        paths.append(contentsOf: stagedFiles.map(\.path))
        paths.append(contentsOf: modifiedFiles.map(\.path))
        paths.append(contentsOf: untrackedFiles.map(\.path))
        return (NSOrderedSet(array: paths).array as? [String]) ?? paths
    }

    public var fingerprint: String {
        "\(branch ?? "none"):\(headCommitHash ?? "initial"):\(modifiedFiles.count):\(stagedFiles.count):\(untrackedFiles.count)"
    }
}
