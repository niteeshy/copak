import Foundation

public enum ContextSource: String, Codable, Sendable, CaseIterable {
    case git = "Git"
    case repository = "Repository"
    case readme = "README"
    case user = "User"
    case generated = "Generated"

    public var badgeLabel: String {
        self.rawValue.uppercased()
    }
}
