import Foundation

public struct ClaudeExporter: ContextExporter, Sendable {
    public let providerName = "Claude Code"
    private let builder = MarkdownHandoffBuilder()

    public init() {}

    public func export(handoff: Handoff, mode: TokenBudgetMode) -> String {
        let wrapper: (String) -> String = { core in
            var header = """
            You are continuing work on an existing project.

            Read the following handoff before making changes.

            Do not assume that everything described below is correct if the repository contradicts it. Inspect the relevant files before modifying them.
            """

            if handoff.currentState.isStale {
                header += "\n\nNote: The snapshot below was captured previously and could not be refreshed immediately before export. Verify the active repository status before making edits."
            }

            let footer = """
            Before making changes:

            1. Confirm your understanding of the current state.
            2. Inspect the relevant files.
            3. Continue from the NEXT TASK section unless the repository indicates otherwise.
            """

            return "\(header)\n\n---\n\n\(core)\n\n---\n\n\(footer)"
        }

        return builder.buildContent(handoff: handoff, mode: mode, wrapper: wrapper)
    }
}
