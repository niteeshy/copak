import Foundation

public struct FileDelta: Codable, Sendable, Equatable, Identifiable {
    public var id: String { path }
    public let path: String
    public let additions: Int
    public let deletions: Int
    public let isStaged: Bool

    public init(path: String, additions: Int, deletions: Int, isStaged: Bool = false) {
        self.path = path
        self.additions = additions
        self.deletions = deletions
        self.isStaged = isStaged
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        additions = try container.decode(Int.self, forKey: .additions)
        deletions = try container.decode(Int.self, forKey: .deletions)
        isStaged = try container.decodeIfPresent(Bool.self, forKey: .isStaged) ?? false
    }

    public var summaryString: String {
        "+\(additions) −\(deletions)"
    }
}

public struct DiffSummary: Codable, Sendable, Equatable {
    public let filesChanged: Int
    public let additions: Int
    public let deletions: Int
    public let stagedAdditions: Int
    public let stagedDeletions: Int
    public let stagedFilesCount: Int
    public let unstagedAdditions: Int
    public let unstagedDeletions: Int
    public let unstagedFilesCount: Int
    public let files: [FileDelta]
    public let rawDiffSnippet: String?
    public let isTruncated: Bool

    public init(
        filesChanged: Int,
        additions: Int,
        deletions: Int,
        stagedAdditions: Int = 0,
        stagedDeletions: Int = 0,
        stagedFilesCount: Int = 0,
        unstagedAdditions: Int = 0,
        unstagedDeletions: Int = 0,
        unstagedFilesCount: Int = 0,
        files: [FileDelta],
        rawDiffSnippet: String? = nil,
        isTruncated: Bool = false
    ) {
        self.filesChanged = filesChanged
        self.additions = additions
        self.deletions = deletions
        self.stagedAdditions = stagedAdditions
        self.stagedDeletions = stagedDeletions
        self.stagedFilesCount = stagedFilesCount
        self.unstagedAdditions = unstagedAdditions
        self.unstagedDeletions = unstagedDeletions
        self.unstagedFilesCount = unstagedFilesCount
        self.files = files
        self.rawDiffSnippet = rawDiffSnippet
        self.isTruncated = isTruncated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filesChanged = try container.decode(Int.self, forKey: .filesChanged)
        additions = try container.decode(Int.self, forKey: .additions)
        deletions = try container.decode(Int.self, forKey: .deletions)
        stagedAdditions = try container.decodeIfPresent(Int.self, forKey: .stagedAdditions) ?? 0
        stagedDeletions = try container.decodeIfPresent(Int.self, forKey: .stagedDeletions) ?? 0
        stagedFilesCount = try container.decodeIfPresent(Int.self, forKey: .stagedFilesCount) ?? 0
        unstagedAdditions = try container.decodeIfPresent(Int.self, forKey: .unstagedAdditions) ?? 0
        unstagedDeletions = try container.decodeIfPresent(Int.self, forKey: .unstagedDeletions) ?? 0
        unstagedFilesCount = try container.decodeIfPresent(Int.self, forKey: .unstagedFilesCount) ?? 0
        files = try container.decodeIfPresent([FileDelta].self, forKey: .files) ?? []
        rawDiffSnippet = try container.decodeIfPresent(String.self, forKey: .rawDiffSnippet)
        isTruncated = try container.decodeIfPresent(Bool.self, forKey: .isTruncated) ?? false
    }

    public var lineSummary: String {
        if stagedFilesCount > 0 && unstagedFilesCount > 0 {
            return "\(filesChanged) files (staged: \(stagedFilesCount) [+\(stagedAdditions)/-\(stagedDeletions)], unstaged: \(unstagedFilesCount) [+\(unstagedAdditions)/-\(unstagedDeletions)])"
        } else if stagedFilesCount > 0 {
            return "\(stagedFilesCount) staged files (+\(stagedAdditions)/-\(stagedDeletions))"
        } else {
            return "\(filesChanged) files changed (+\(additions)/-\(deletions))"
        }
    }
}

