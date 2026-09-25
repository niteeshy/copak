import Foundation

public struct RecentProjectItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let lastOpened: Date

    public init(name: String, path: String, lastOpened: Date = Date()) {
        self.name = name
        self.path = path
        self.lastOpened = lastOpened
    }
}

public final class RecentProjectsStore: @unchecked Sendable {
    public static let shared = RecentProjectsStore()

    private let fileURL: URL
    private let lock = NSLock()

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("Copak", isDirectory: true)
        let oldDir = appSupport.appendingPathComponent("ContextPacket", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) && fm.fileExists(atPath: oldDir.path) {
            try? fm.copyItem(at: oldDir, to: dir)
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("recent_projects.json")
    }

    public func getRecentProjects() -> [RecentProjectItem] {
        lock.lock()
        defer { lock.unlock() }

        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([RecentProjectItem].self, from: data) else {
            return []
        }
        return items.sorted { $0.lastOpened > $1.lastOpened }
    }

    public func recordProject(name: String, path: String) {
        lock.lock()
        defer { lock.unlock() }

        var current = getRecentProjectsInternal()
        current.removeAll { $0.path == path }
        current.insert(RecentProjectItem(name: name, path: path, lastOpened: Date()), at: 0)

        // Keep up to 20 recent projects
        let trimmed = Array(current.prefix(20))
        saveInternal(trimmed)
    }

    public func removeProject(path: String) {
        lock.lock()
        defer { lock.unlock() }

        var current = getRecentProjectsInternal()
        current.removeAll { $0.path == path }
        saveInternal(current)
    }

    private func getRecentProjectsInternal() -> [RecentProjectItem] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([RecentProjectItem].self, from: data) else {
            return []
        }
        return items
    }

    private func saveInternal(_ items: [RecentProjectItem]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
