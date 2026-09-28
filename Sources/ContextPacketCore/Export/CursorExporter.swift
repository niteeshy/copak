import Foundation

public struct CursorExporter: ContextExporter, Sendable {
    public let providerName = "Cursor"
    private let builder = MarkdownHandoffBuilder()

    public init() {}

    public func export(handoff: Handoff, mode: TokenBudgetMode) -> String {
        let wrapper: (String) -> String = { core in
            var header = """
            You are joining an in-progress coding task.

            Use the following handoff as working context. Verify details against the codebase before modifying files.
            """

            if handoff.currentState.isStale {
                header += "\n\nNote: The repository snapshot could not be freshly refreshed immediately before export. Confirm actual branch and working tree state."
            }

            return "\(header)\n\n---\n\n\(core)"
        }

        return builder.buildContent(handoff: handoff, mode: mode, wrapper: wrapper)
    }
}
