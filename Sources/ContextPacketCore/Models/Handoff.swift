import Foundation

public struct ProjectContext: Codable, Sendable, Equatable {
    public let name: String
    public let repositoryPath: String
    public let ecosystem: String
    public let remoteURL: String?

    public init(name: String, repositoryPath: String, ecosystem: String, remoteURL: String? = nil) {
        self.name = name
        self.repositoryPath = repositoryPath
        self.ecosystem = ecosystem
        self.remoteURL = remoteURL
    }
}

public struct ContextItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String { text }
    public let text: String
    public let source: ContextSource

    public init(text: String, source: ContextSource = .user) {
        self.text = text
        self.source = source
    }
}

public struct Decision: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var text: String
    public var source: ContextSource

    public init(id: UUID = UUID(), text: String, source: ContextSource = .user) {
        self.id = id
        self.text = text
        self.source = source
    }
}

public struct TaskItem: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var text: String
    public var source: ContextSource

    public init(id: UUID = UUID(), text: String, source: ContextSource = .user) {
        self.id = id
        self.text = text
        self.source = source
    }
}

public struct ProblemItem: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var text: String
    public var source: ContextSource

    public init(id: UUID = UUID(), text: String, source: ContextSource = .user) {
        self.id = id
        self.text = text
        self.source = source
    }
}

public struct ImportantFile: Codable, Sendable, Equatable, Identifiable {
    public var id: String { path }
    public var path: String
    public var reason: String
    public var isPinned: Bool

    public init(path: String, reason: String = "Changed recently", isPinned: Bool = false) {
        self.path = path
        self.reason = reason
        self.isPinned = isPinned
    }
}

public struct CanonicalRepositoryState: Codable, Sendable, Equatable {
    public let branch: String
    public let headCommit: String?
    public let isClean: Bool
    public let modifiedFiles: [String]
    public let stagedFiles: [String]
    public let untrackedFiles: [String]
    public let diffSummary: DiffSummary?
    public let refreshedAt: Date
    public let isStale: Bool
    public let stalenessReason: String?
    public let hasOmittedSensitiveChanges: Bool
    public let hiddenSensitiveChangesCount: Int
    public let isGitDirty: Bool
    public let isEditedDraft: Bool
    public let isGitRepository: Bool

    public init(
        branch: String,
        headCommit: String? = nil,
        isClean: Bool,
        modifiedFiles: [String],
        stagedFiles: [String],
        untrackedFiles: [String],
        diffSummary: DiffSummary?,
        refreshedAt: Date = Date(),
        isStale: Bool = false,
        stalenessReason: String? = nil,
        hasOmittedSensitiveChanges: Bool = false,
        hiddenSensitiveChangesCount: Int = 0,
        isGitDirty: Bool? = nil,
        isEditedDraft: Bool = false,
        isGitRepository: Bool = true
    ) {
        self.branch = branch
        self.headCommit = headCommit
        self.hasOmittedSensitiveChanges = hasOmittedSensitiveChanges
        self.hiddenSensitiveChangesCount = hiddenSensitiveChangesCount
        let visibleCount = modifiedFiles.count + stagedFiles.count + untrackedFiles.count
        self.isGitDirty = isGitDirty ?? (visibleCount > 0 || hasOmittedSensitiveChanges || !isClean)
        // If the working tree has sensitive changes or is git dirty, it is not clean
        self.isClean = isClean && !hasOmittedSensitiveChanges && !self.isGitDirty
        self.modifiedFiles = modifiedFiles
        self.stagedFiles = stagedFiles
        self.untrackedFiles = untrackedFiles
        self.diffSummary = diffSummary
        self.refreshedAt = refreshedAt
        self.isStale = isStale
        self.stalenessReason = stalenessReason
        self.isEditedDraft = isEditedDraft
        self.isGitRepository = isGitRepository
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        branch = try container.decode(String.self, forKey: .branch)
        headCommit = try container.decodeIfPresent(String.self, forKey: .headCommit)
        modifiedFiles = try container.decodeIfPresent([String].self, forKey: .modifiedFiles) ?? []
        stagedFiles = try container.decodeIfPresent([String].self, forKey: .stagedFiles) ?? []
        untrackedFiles = try container.decodeIfPresent([String].self, forKey: .untrackedFiles) ?? []
        diffSummary = try container.decodeIfPresent(DiffSummary.self, forKey: .diffSummary)
        refreshedAt = try container.decodeIfPresent(Date.self, forKey: .refreshedAt) ?? Date()
        isStale = try container.decodeIfPresent(Bool.self, forKey: .isStale) ?? false
        stalenessReason = try container.decodeIfPresent(String.self, forKey: .stalenessReason)
        hasOmittedSensitiveChanges = try container.decodeIfPresent(Bool.self, forKey: .hasOmittedSensitiveChanges) ?? false
        hiddenSensitiveChangesCount = try container.decodeIfPresent(Int.self, forKey: .hiddenSensitiveChangesCount) ?? 0
        let visibleCount = modifiedFiles.count + stagedFiles.count + untrackedFiles.count
        let decodedIsGitDirty = try container.decodeIfPresent(Bool.self, forKey: .isGitDirty)
        isGitDirty = decodedIsGitDirty ?? (visibleCount > 0 || hasOmittedSensitiveChanges)
        let decodedIsClean = try container.decode(Bool.self, forKey: .isClean)
        isClean = decodedIsClean && !hasOmittedSensitiveChanges && !isGitDirty
        isEditedDraft = try container.decodeIfPresent(Bool.self, forKey: .isEditedDraft) ?? false
        isGitRepository = try container.decodeIfPresent(Bool.self, forKey: .isGitRepository) ?? (branch != "non-git")
    }
}

public struct Handoff: Codable, Sendable, Equatable {
    public let version: String
    public var project: ProjectContext
    public var currentGoal: String
    public var completedWork: [ContextItem]
    public var currentState: CanonicalRepositoryState
    public var importantFiles: [ImportantFile]
    public var decisions: [Decision]
    public var nextTasks: [TaskItem]
    public var knownProblems: [ProblemItem]
    public var recentWork: [ContextItem]
    public var recentCommits: [Commit]
    public var detectedInstructions: [InstructionFile]
    public var todos: [TodoItem]
    public var notes: String?
    public var generatedAt: Date

    public init(
        version: String = "1.0",
        project: ProjectContext,
        currentGoal: String,
        completedWork: [ContextItem] = [],
        currentState: CanonicalRepositoryState,
        importantFiles: [ImportantFile] = [],
        decisions: [Decision] = [],
        nextTasks: [TaskItem] = [],
        knownProblems: [ProblemItem] = [],
        recentWork: [ContextItem] = [],
        recentCommits: [Commit] = [],
        detectedInstructions: [InstructionFile] = [],
        todos: [TodoItem] = [],
        notes: String? = nil,
        generatedAt: Date = Date()
    ) {
        self.version = version
        self.project = project
        self.currentGoal = currentGoal
        self.completedWork = completedWork
        self.currentState = currentState
        self.importantFiles = importantFiles
        self.decisions = decisions
        self.nextTasks = nextTasks
        self.knownProblems = knownProblems
        self.recentWork = recentWork
        self.recentCommits = recentCommits
        self.detectedInstructions = detectedInstructions
        self.todos = todos
        self.notes = notes
        self.generatedAt = generatedAt
    }
}
