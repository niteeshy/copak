import Foundation

public struct GenericExporter: ContextExporter, Sendable {
    public let providerName = "Generic Markdown"
    private let builder = MarkdownHandoffBuilder()

    public init() {}

    public func export(handoff: Handoff, mode: TokenBudgetMode) -> String {
        builder.buildContent(handoff: handoff, mode: mode)
    }
}
