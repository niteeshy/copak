# Copak

> Deterministic handoffs between coding agents and developers.

Copak helps developers carry active coding work between AI-agent sessions by combining developer-maintained context with a current, sanitised project snapshot. It is designed to eliminate context drift and tedious prompt re-explanation when collaborating with AI coding agents (Claude Code, Cursor, Codex, etc.).

Copak is intentionally **not** autonomous agent memory. Active session momentum (goals, decisions, next tasks, and debugging notes) is maintained directly by the developer, paired with automated project inspection, multi-layer secret sanitisation, and enforced token budgeting.

---

## Key Features

- **Developer-Maintained Session Context**: Keep track of your active goal, completed work, architectural decisions, next tasks, known problems & failed attempts, recent work, and freeform notes without relying on external agent memory.
- **Git & Non-Git Project Support**: Works seamlessly with local Git repositories (inspecting branch, HEAD, working tree dirty status, and diff statistics) as well as standalone non-Git project folders (cleanly omitting commit and diff sections while maintaining full project file trees, instruction detection, and TODO scanning).
- **Current Snapshotting & Freshness Controls**: Inspects branch, HEAD, modified, staged, and untracked files, plus staged and unstaged diff statistics when available.
  - **Freshness on Export**: Copy and Save operations refresh repository state and automatically regenerate unedited previews.
  - **No Silent Overwrites**: Edited draft previews are never silently overwritten. If an edited draft reflects an older repository snapshot, a warning is displayed along with the refreshed timestamp.
  - **Explicit Confirmation for Stale Exports**: If a repository refresh fails, exporting a stale packet requires explicit confirmation, and the exported packet explicitly records whether it is a fresh snapshot, stale packet, or edited draft.
- **Hidden Sensitive Changes Tracking**: Repositories containing sensitive file modifications (e.g. `.env`, private keys) are recognized as dirty while hiding the sensitive file paths, disclosing that the working tree contains sensitive changes omitted from the packet.
- **Multi-Layer Secret Sanitisation**: Verified sanitisation pipeline redacts common API tokens (OpenAI, Anthropic, AWS, GitHub, Slack, Stripe, JWT, Bearer), credentials in URLs, multiline PEM private key blocks, quoted (including values with spaces) and unquoted variable assignments, and prose tokens. Strips sensitive files and diff hunks before reaching preview, clipboard, disk persistence, or `context.md`. Migrates and sanitises legacy session files on load.
- **Bounded Multi-Scope Instruction Ingestion**: Discovers and ingests `AGENTS.md`, `CLAUDE.md`, `.cursorrules`, `.cursor/rules/*`, `.windsurfrules`, `.clinerules`, `.github/copilot-instructions.md`, and hierarchical nested `AGENTS.md` files with scope indicators. Ingestion is bounded and truncates large or deeply nested files to prevent context exhaustion.
- **Enforced Estimated Token Budgets**:
  - **Compact** (~1,000 estimated tokens): Core goal, next tasks, git state, and instruction references.
  - **Standard** (~3,500 estimated tokens): Balanced session state, decisions, problems, and bounded instruction excerpts.
  - **Comprehensive** (~10,000 estimated tokens): In-depth context including commits, full instructions, and bounded sanitized git diff excerpts.
  - **Deterministic Final Budget Pass**: Estimates include provider wrapper overhead and progressively reduce lower-priority sections and long fields so that the final estimated tokens are guaranteed not to exceed the configured target across all modes and provider formats. Content omissions are always disclosed in `## BUDGET DISCLOSURES`.
- **Provider Formats**: Prepares canonical prompt packets formatted specifically for **Claude Code**, **Cursor**, **Codex**, and generic **Markdown**.
- **Draft & Preview Preservation**: Edit the generated preview directly; edits are preserved across clipboard copies and `context.md` file saves, with draft warnings before switching providers.

---

## Requirements & Building

- macOS 14.0 or later
- Swift 5.9 or later (Xcode 15+)

### Build Application Bundle

To build the release application bundle `Copak.app`:

```bash
./build_app.sh
```

Then open the application:

```bash
open Copak.app
```

### Running Tests

Run the full automated test suite (including end-to-end integration tests and secret filter verification):

```bash
swift test
```

---

## License

MIT License. See LICENSE for details.
