<p align="center">
  <img src="Resources/Copak.png" alt="Copak App Icon" width="128" height="128" />
</p>

<h1 align="center">Copak</h1>

<p align="center">
  <strong>Deterministic handoffs between coding agents and developers.</strong><br>
  <em>Carrying active session momentum and sanitized repo context into Claude Code, Cursor, and web LLMs.</em>
</p>

<p align="center">
  <a href="https://github.com/niteeshy/copak/releases/download/v1.0.0/Copak.zip"><img src="https://img.shields.io/badge/Download-Copak%20for%20macOS-17181b?style=for-the-badge&logo=apple&logoColor=white" alt="Download Copak for macOS" /></a>
  <a href="https://github.com/niteeshy/copak/releases/tag/v1.0.0"><img src="https://img.shields.io/badge/Release-v1.0.0-242529?style=for-the-badge&labelColor=17181b" alt="Latest Release" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-242529?style=for-the-badge" alt="License" /></a>
</p>

---

Copak helps developers carry active coding work between AI-agent sessions by combining developer-maintained context with a current, sanitised project snapshot. It is designed to eliminate context drift and tedious prompt re-explanation when collaborating with AI coding agents (Claude Code, Cursor, Codex, Windsurf, Copilot, etc.).

Copak is intentionally **not** autonomous agent memory. Active session momentum (goals, decisions, next tasks, and debugging notes) is maintained directly by the developer, paired with automated project inspection, multi-layer secret sanitisation, and enforced token budgeting.

---

## ⚡️ Quick Download (macOS)

[![Download Copak v1.0.0](https://img.shields.io/badge/Download-Copak%20v1.0.0%20(macOS)-17181b?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/niteeshy/copak/releases/download/v1.0.0/Copak.zip)

1. **[Download `Copak.zip` (v1.0.0)](https://github.com/niteeshy/copak/releases/download/v1.0.0/Copak.zip)** (or view [Release v1.0.0](https://github.com/niteeshy/copak/releases/tag/v1.0.0)).
2. Unzip and drag `Copak.app` into `/Applications`.
3. Open `Copak.app` and press `⌘O` to load any Git repository or project folder.

> **Tip for first launch:** Since Copak is an open-source indie app, if macOS displays an unidentified developer prompt on first launch, simply right-click `Copak.app` and select **Open**, or run:
> ```bash
> xattr -cr /Applications/Copak.app
> ```

---

## How It Works

```
┌────────────────────────────────┐     ┌────────────────────────────────┐
│      Developer Momentum        │  +  │      Repository Snapshot       │
│  Goal • Tasks • Decisions •    │     │  Branch • Tree • Commits •     │
│  Important Files • Notes       │     │  Diff • Instructions (AGENTS)  │
└───────────────┬────────────────┘     └───────────────┬────────────────┘
                │                                      │
                └──────────────────┬───────────────────┘
                                   │
                                   ▼
                 ┌───────────────────────────────────┐
                 │  Multi-Layer Secret Sanitisation  │
                 │  Tokens • PEM Keys • Assignments  │
                 └─────────────────┬─────────────────┘
                                   │
                                   ▼
                 ┌───────────────────────────────────┐
                 │    Token Budget Ceiling Engine    │
                 │  Compact (~1k) • Standard (~3.5k) │
                 │        Comprehensive (~10k)       │
                 └─────────────────┬─────────────────┘
                                   │
                                   ▼
                 ┌───────────────────────────────────┐
                 │     Targeted Provider Export      │
                 │  Claude Code • Cursor • Codex •   │
                 │       Markdown / context.md       │
                 └───────────────────────────────────┘
```

---

## Key Features

### 1. Developer-Maintained Session Context
- **Active Goal**: Keep receiving agents strictly aligned on your immediate objective, preventing hallucinated refactors.
- **Next Tasks**: A prioritized queue of pending implementation items.
- **Completed Work**: Explicit milestones accomplished in previous turns.
- **Decisions**: Architectural decisions, rejected alternatives, and constraints.
- **Known Problems**: Edge cases, active regressions, or failed attempts.
- **Recent Work**: Fine-grained notes on changes from the latest session.
- **Important Files**: Pinned file paths with developer-annotated rationale.
- **Session Notes**: Freeform handover notes, warnings, or environment tips.
- **Atomic Local Persistence**: Saved atomically to `~/Library/Application Support/Copak/sessions/<base64>.json` with automatic sanitization on read and write.

### 2. Git & Non-Git Project Support
- **Git Repositories**: Inspects active branch, HEAD commit hash, modified, staged, and untracked files, plus staged/unstaged diff statistics.
- **Non-Git Projects**: Works cleanly with local directories outside Git, analyzing file trees, TODOs, and instructions while gracefully omitting Git-specific diffs and commit sections.

### 3. Current Snapshotting & Freshness Controls
- **Freshness on Export**: Copy and Save operations refresh the underlying repository state and automatically regenerate unedited previews.
- **No Silent Overwrites**: If you customize the generated markdown, your edits are never silently overwritten. A warning badge is displayed if the draft reflects an older snapshot.
- **Stale State Disclosures**: If a Git refresh fails (e.g. locks or missing index), exporting requires explicit confirmation, and the generated packet discloses its staleness state.
- **Hidden Sensitive Changes**: If sensitive files (such as `.env` or certificates) are modified, the working tree is flagged as dirty while sensitive filenames are hidden, disclosing that sensitive modifications were omitted.

### 4. Multi-Layer Secret Sanitisation
- **API Keys & Credentials**: Redacts common API tokens (OpenAI, Anthropic, AWS, GitHub, Slack, Stripe, JWT, Bearer tokens).
- **URLs**: Automatically scrubs credentials embedded in URLs (`https://user:password@host`).
- **Private Keys**: Redacts multiline PEM private key blocks.
- **Environment Assignments**: Cleans both quoted (including strings with spaces) and unquoted sensitive variable assignments.
- **Prose Tokens**: Redacts high-entropy keys embedded inside developer notes and descriptions.
- **Diff & Tree Cleansing**: Completely excludes secret-bearing files and sensitive diff hunks before reaching clipboard, preview, or disk.

### 5. Bounded Multi-Scope Instruction Ingestion
- Automatically detects and ingests rule and instruction files across your project:
  - `AGENTS.md` (including hierarchical subfolder files)
  - `CLAUDE.md`
  - `.cursorrules` and `.cursor/rules/*`
  - `.windsurfrules`
  - `.clinerules`
  - `.github/copilot-instructions.md`
- **Bounded Ingestion**: Caps file lengths to prevent context exhaustion in token-constrained sessions.

### 6. Enforced Estimated Token Budgets
- Three standard budget tiers calibrated for AI coding agents:
  - **Compact (~1,000 estimated tokens)**: Core goal, next tasks, git state, and instruction references.
  - **Standard (~3,500 estimated tokens)**: Balanced session state, decisions, problems, and bounded instruction excerpts.
  - **Comprehensive (~10,000 estimated tokens)**: In-depth context including commits, full instructions, and bounded sanitized git diff excerpts.
- **Deterministic Ceiling Pass**: Progressively trims lower-priority sections and long fields so the exported packet is guaranteed not to exceed the configured target across all providers.
- **Budget Disclosures**: When content is omitted to satisfy budget limits, disclosures are logged under `## BUDGET DISCLOSURES`.

### 7. Provider-Optimized Formats
- Generates tailored markdown prompt packets optimized for:
  - **Claude Code** (`claude`)
  - **Cursor** (`cursor`)
  - **Codex** (`codex`)
  - **Generic Markdown** (`markdown` / `context.md`)

---

## Keyboard Shortcuts

| Shortcut | Action | Scope |
| :--- | :--- | :--- |
| <kbd>⌘</kbd> + <kbd>O</kbd> | Open Project Folder | Project Picker |
| <kbd>⌘</kbd> + <kbd>R</kbd> | Refresh Repository State | Project Overview |
| <kbd>⌘</kbd> + <kbd>⇧</kbd> + <kbd>H</kbd> | Create Handoff Packet | Project Overview |
| <kbd>⌘</kbd> + <kbd>S</kbd> | Save `context.md` to Project Root | Handoff Preview |
| <kbd>⌘</kbd> + <kbd>↵</kbd> | Copy Packet to Clipboard | Handoff Preview |

---

## Requirements & Building

- **OS**: macOS 14.0 or later (Apple Silicon or Intel)
- **Toolchain**: Swift 5.9 or later (Xcode 15+)

### Build Application Bundle

Build the release application bundle `Copak.app`:

```bash
# Build for host architecture (e.g. Apple Silicon)
./build_app.sh

# Or build universal binary (arm64 + x86_64)
./build_app.sh --universal
```

Open the application:

```bash
open Copak.app
```

### Run Directly from CLI

You can also launch Copak directly via Swift Package Manager:

```bash
swift run Copak
```

### Running Tests

Run the automated test suite (45+ unit, integration, and secret sanitization tests):

```bash
swift test
```

---

## Privacy & Security

- **100% Local**: Copak performs all repository analysis, secret filtering, and packet generation locally on your machine.
- **Zero Telemetry**: No network analytics, tracking, or remote API calls.
- **Local State Location**: Developer session momentum is stored locally in `~/Library/Application Support/Copak/sessions/` with safe base64-encoded directory keys.

---

## License

MIT License. See [LICENSE](LICENSE) for details.
