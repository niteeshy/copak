# Copak

> Deterministic handoffs between coding agents and developers.

Copak is a native, lightweight macOS desktop and menu bar companion designed to eliminate context drift and tedious prompt re-explanation when collaborating with AI coding agents (Claude Code, Cursor, Codex, etc.).

Instead of committing temporary debugging notes into your git history or repeatedly re-explaining the current state of your repository, Copak pairs **developer-maintained session momentum** with **automated repository inspection** and **end-to-end secret sanitization**.

---

## Key Features

- **User-Maintained Session Context**: Keep track of your active goal, completed work, architectural decisions, next tasks, known problems & failed attempts, recent work, and freeform notes.
- **Repository Snapshotting & Stale Detection**: Inspects branch, HEAD, modified, staged, and untracked files, plus staged and unstaged diff statistics. Automatically refreshes before copy/save and warns if the working snapshot cannot be updated.
- **End-to-End Secret Sanitization**: Central sanitization pipeline redacts common API tokens (OpenAI, Anthropic, AWS, GitHub, Slack, Stripe, JWT, Bearer), credentials in URLs, private key blocks, sensitive assignments, and completely strips diff hunks for sensitive files (`.env`, `credentials.json`, `id_rsa`, etc.) before content reaches preview, clipboard, disk persistence, or `context.md`.
- **Multi-Scope Instruction Ingestion**: Discovers and ingests `AGENTS.md`, `CLAUDE.md`, `.cursorrules`, `.cursor/rules/*`, `.github/copilot-instructions.md`, and hierarchical nested `AGENTS.md` files with scope indicators.
- **Deterministic Token Budgets**:
  - **Compact** (~1,000 estimated tokens): Core goal, next tasks, git state, and instruction references.
  - **Standard** (~3,500 estimated tokens): Balanced session state, decisions, problems, and bounded instruction excerpts.
  - **Comprehensive** (~10,000 estimated tokens): In-depth context including commits, full instructions, and bounded sanitized git diff excerpts.
  - Automatically discloses omissions in a `## BUDGET DISCLOSURES` section if content is truncated to respect your target budget.
- **Provider Formats**: Prepares canonical prompt packets formatted specifically for **Claude Code**, **Cursor**, **Codex**, and generic **Markdown**.
- **Preview Preservation**: Edit the generated preview directly; edits are preserved across clipboard copies and `context.md` file saves, with draft warnings before switching providers.

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
