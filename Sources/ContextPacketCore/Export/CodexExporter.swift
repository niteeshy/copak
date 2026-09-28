import Foundation

public struct CodexExporter: ContextExporter, Sendable {
    public let providerName = "Codex"
    private let builder = MarkdownHandoffBuilder()

    public init() {}

    public func export(handoff: Handoff, mode: TokenBudgetMode) -> String {
        let wrapper: (String) -> String = { core in
            var header = """
            Continue the existing implementation described below.

            First inspect the repository state and relevant files. Preserve existing architecture and decisions unless there is a clear reason not to.

            Do not redo completed work.
            """

            if handoff.currentState.isStale {
                header += "\n\nNote: The repository snapshot could not be freshly refreshed immediately before export. Inspect actual working tree state."
            }

            return "\(header)\n\n---\n\n\(core)"
        }

        return builder.buildContent(handoff: handoff, mode: mode, wrapper: wrapper)
    }
}
