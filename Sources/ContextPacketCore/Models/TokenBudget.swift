import Foundation

public enum TokenBudgetMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case compact = "Compact"
    case standard = "Standard"
    case comprehensive = "Comprehensive"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .compact:
            return "Goal + Next tasks + Core Git state + File references (~1,000 estimated tokens)"
        case .standard:
            return "Balanced context for daily agent switching with instructions & problems (~3,500 estimated tokens)"
        case .comprehensive:
            return "In-depth context including commits, instruction bodies, and diff excerpts (~10,000 estimated tokens)"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw.lowercased() {
        case "compact": self = .compact
        case "standard": self = .standard
        case "detailed", "comprehensive": self = .comprehensive
        default: self = .standard
        }
    }
}

public struct TokenBudgetConfig: Sendable, Codable, Equatable {
    public static var `default` = TokenBudgetConfig()

    public var compactTargetTokens: Int
    public var standardTargetTokens: Int
    public var comprehensiveTargetTokens: Int

    public init(
        compactTargetTokens: Int = 1_000,
        standardTargetTokens: Int = 3_500,
        comprehensiveTargetTokens: Int = 10_000
    ) {
        self.compactTargetTokens = compactTargetTokens
        self.standardTargetTokens = standardTargetTokens
        self.comprehensiveTargetTokens = comprehensiveTargetTokens
    }

    public func targetTokens(for mode: TokenBudgetMode) -> Int {
        switch mode {
        case .compact: return compactTargetTokens
        case .standard: return standardTargetTokens
        case .comprehensive: return comprehensiveTargetTokens
        }
    }

    public func target(for mode: TokenBudgetMode) -> Int {
        targetTokens(for: mode)
    }
}

public struct TokenBudgetEstimate: Sendable, Equatable {
    public let wordCount: Int
    public let characterCount: Int
    public let estimatedTokens: Int

    public init(text: String) {
        let chars = text.count
        self.characterCount = chars
        let words = text.split { $0.isWhitespace || $0.isNewline }
        self.wordCount = words.count

        if chars == 0 {
            self.estimatedTokens = 0
        } else {
            self.estimatedTokens = max(1, Int(ceil(Double(chars) / 4.0)))
        }
    }

    public var displaySummary: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let wordsStr = formatter.string(from: NSNumber(value: wordCount)) ?? "\(wordCount)"
        let tokensStr = formatter.string(from: NSNumber(value: estimatedTokens)) ?? "\(estimatedTokens)"
        return "\(wordsStr) words · Estimated ~\(tokensStr) tokens"
    }
}

