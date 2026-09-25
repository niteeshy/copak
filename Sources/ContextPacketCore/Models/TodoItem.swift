import Foundation

public struct TodoItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(file):\(line):\(kind)" }
    public let file: String
    public let line: Int
    public let kind: String
    public let comment: String
    public let isInsideChangedFile: Bool

    public init(
        file: String,
        line: Int,
        kind: String,
        comment: String,
        isInsideChangedFile: Bool = false
    ) {
        self.file = file
        self.line = line
        self.kind = kind
        self.comment = comment
        self.isInsideChangedFile = isInsideChangedFile
    }

    public var displayLocation: String {
        "\(file):\(line)"
    }
}
