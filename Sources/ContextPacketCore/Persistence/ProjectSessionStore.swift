import Foundation

public struct SavedProjectSession: Codable, Sendable {
    public var repositoryPath: String
    public var currentGoal: String
    public var completedWork: [ContextItem]
    public var decisions: [Decision]
    public var nextTasks: [TaskItem]
    public var knownProblems: [ProblemItem]
    public var recentWork: [ContextItem]
    public var notes: String?
    public var preferredExportTarget: String
    public var preferredBudgetMode: TokenBudgetMode
    public var pinnedFiles: [String]
    public var lastHandoffFingerprint: String?
    public var lastModified: Date

    public init(
        repositoryPath: String,
        currentGoal: String = "",
        completedWork: [ContextItem] = [],
        decisions: [Decision] = [],
        nextTasks: [TaskItem] = [],
        knownProblems: [ProblemItem] = [],
        recentWork: [ContextItem] = [],
        notes: String? = nil,
        preferredExportTarget: String = "claude",
        preferredBudgetMode: TokenBudgetMode = .standard,
        pinnedFiles: [String] = [],
        lastHandoffFingerprint: String? = nil,
        lastModified: Date = Date()
    ) {
        self.repositoryPath = repositoryPath
        self.currentGoal = currentGoal
        self.completedWork = completedWork
        self.decisions = decisions
        self.nextTasks = nextTasks
        self.knownProblems = knownProblems
        self.recentWork = recentWork
        self.notes = notes
        self.preferredExportTarget = preferredExportTarget
        self.preferredBudgetMode = preferredBudgetMode
        self.pinnedFiles = pinnedFiles
        self.lastHandoffFingerprint = lastHandoffFingerprint
        self.lastModified = lastModified
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        repositoryPath = try container.decode(String.self, forKey: .repositoryPath)
        currentGoal = try container.decodeIfPresent(String.self, forKey: .currentGoal) ?? ""
        completedWork = try container.decodeIfPresent([ContextItem].self, forKey: .completedWork) ?? []
        decisions = try container.decodeIfPresent([Decision].self, forKey: .decisions) ?? []
        nextTasks = try container.decodeIfPresent([TaskItem].self, forKey: .nextTasks) ?? []
        knownProblems = try container.decodeIfPresent([ProblemItem].self, forKey: .knownProblems) ?? []
        recentWork = try container.decodeIfPresent([ContextItem].self, forKey: .recentWork) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        preferredExportTarget = try container.decodeIfPresent(String.self, forKey: .preferredExportTarget) ?? "claude"
        preferredBudgetMode = try container.decodeIfPresent(TokenBudgetMode.self, forKey: .preferredBudgetMode) ?? .standard
        pinnedFiles = try container.decodeIfPresent([String].self, forKey: .pinnedFiles) ?? []
        lastHandoffFingerprint = try container.decodeIfPresent(String.self, forKey: .lastHandoffFingerprint)
        lastModified = try container.decodeIfPresent(Date.self, forKey: .lastModified) ?? Date()
    }
}

public final class ProjectSessionStore: @unchecked Sendable {
    public static let shared = ProjectSessionStore()

    public let storageDir: URL
    private let lock = NSLock()

    public init(storageDirectory: URL? = nil) {
        if let customDir = storageDirectory {
            self.storageDir = customDir
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            self.storageDir = appSupport.appendingPathComponent("Copak/sessions", isDirectory: true)
            let oldDir = appSupport.appendingPathComponent("ContextPacket/sessions", isDirectory: true)
            let fm = FileManager.default
            if !fm.fileExists(atPath: self.storageDir.path) && fm.fileExists(atPath: oldDir.path) {
                try? fm.copyItem(at: oldDir, to: self.storageDir)
            }
        }
        try? FileManager.default.createDirectory(at: self.storageDir, withIntermediateDirectories: true)
    }

    public func storageKey(for path: String) -> String {
        // Safe filename from base64 encoding of path
        let data = Data(path.utf8)
        let base64 = data.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return "\(base64).json"
    }

    public func loadSession(for path: String) -> SavedProjectSession {
        lock.lock()
        defer { lock.unlock() }

        let fileURL = storageDir.appendingPathComponent(storageKey(for: path))
        guard let data = try? Data(contentsOf: fileURL),
              let session = try? JSONDecoder().decode(SavedProjectSession.self, from: data) else {
            return SavedProjectSession(repositoryPath: path)
        }
        return session
    }

    @discardableResult
    public func saveSession(_ session: SavedProjectSession) throws -> SavedProjectSession {
        lock.lock()
        defer { lock.unlock() }

        // Sanitize session before persisting to disk
        let sanitized = SecretFilter.sanitizeSession(session)
        let fileURL = storageDir.appendingPathComponent(storageKey(for: sanitized.repositoryPath))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(sanitized)
        try data.write(to: fileURL, options: .atomic)
        return sanitized
    }
}
