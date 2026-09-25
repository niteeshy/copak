import Foundation

public protocol ContextExporter: Sendable {
    var providerName: String { get }
    func export(handoff: Handoff, mode: TokenBudgetMode) -> String
}

public struct MarkdownHandoffBuilder: Sendable {
    private let config: TokenBudgetConfig

    public init(config: TokenBudgetConfig = .default) {
        self.config = config
    }

    private static let utcDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    public func buildContent(handoff rawHandoff: Handoff, mode: TokenBudgetMode) -> String {
        // 1. Sanitize the canonical handoff model before anything is built
        let handoff = SecretFilter.sanitizeHandoff(rawHandoff)
        let targetTokens = config.targetTokens(for: mode)

        var budgetDisclosures: [String] = []

        // Level 8 items inclusion flags
        var includeDiffExcerpt = (mode == .comprehensive) && (handoff.currentState.diffSummary?.rawDiffSnippet != nil)
        var includeTodos = (mode != .compact) && !handoff.todos.isEmpty
        var includeNotes = handoff.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

        // Level 7 items
        var maxCommits = (mode == .comprehensive) ? 8 : (mode == .standard ? 4 : 2)
        var includeRecentWork = (mode != .compact) && !handoff.recentWork.isEmpty

        // Level 6 items
        var includeCompletedWork = (mode != .compact) && !handoff.completedWork.isEmpty
        let maxImportantFiles = handoff.importantFiles.count

        // Level 5 items
        var instructionRenderingLevel: InstructionRenderStyle = (mode == .comprehensive ? .full : (mode == .standard ? .bounded : .references))

        enum InstructionRenderStyle {
            case full
            case bounded
            case references
        }

        func assemble() -> String {
            var sections: [String] = []

            // P1: PROJECT IDENTITY & GIT REPO INFO
            var projectLines: [String] = ["# PROJECT\n\n\(handoff.project.name)"]
            if !handoff.project.ecosystem.isEmpty && handoff.project.ecosystem != "Generic" {
                projectLines[0] += " (\(handoff.project.ecosystem))"
            }
            if let remote = handoff.project.remoteURL {
                projectLines.append("Remote: \(remote)")
            }
            let refreshStr = Self.utcDateFormatter.string(from: handoff.currentState.refreshedAt)
            projectLines.append("Snapshot captured: \(refreshStr)")
            if handoff.currentState.isStale {
                let reason = handoff.currentState.stalenessReason ?? "Refresh failed"
                projectLines.append("> [!WARNING] Stale Snapshot Notice: Git state could not be refreshed immediately (\(reason)). Verify current branch and tree before changes.")
            }
            sections.append(projectLines.joined(separator: "\n"))

            // P1: CURRENT GOAL
            let goalText = handoff.currentGoal.trimmingCharacters(in: .whitespacesAndNewlines)
            if !goalText.isEmpty {
                sections.append("## CURRENT GOAL\n\n\(goalText)")
            }

            // P2: NEXT TASK
            if !handoff.nextTasks.isEmpty {
                let tasksText = handoff.nextTasks.map { "- \($0.text)" }.joined(separator: "\n")
                sections.append("## NEXT TASK\n\n\(tasksText)")
            }

            // P3: CURRENT STATE & GIT DETAILS
            var stateLines: [String] = []
            stateLines.append("Branch: \(handoff.currentState.branch)")
            if let head = handoff.currentState.headCommit {
                stateLines.append("HEAD: \(head)")
            }

            if handoff.currentState.isClean {
                stateLines.append("Working tree: clean")
            } else {
                if !handoff.currentState.stagedFiles.isEmpty {
                    stateLines.append("\nStaged files (\(handoff.currentState.stagedFiles.count)):")
                    for f in handoff.currentState.stagedFiles {
                        stateLines.append("- \(f)")
                    }
                }
                if !handoff.currentState.modifiedFiles.isEmpty {
                    stateLines.append("\nModified files (\(handoff.currentState.modifiedFiles.count)):")
                    for f in handoff.currentState.modifiedFiles {
                        stateLines.append("- \(f)")
                    }
                }
                if !handoff.currentState.untrackedFiles.isEmpty {
                    stateLines.append("\nUntracked files (\(handoff.currentState.untrackedFiles.count)):")
                    for f in handoff.currentState.untrackedFiles {
                        stateLines.append("- \(f)")
                    }
                }
                if let diff = handoff.currentState.diffSummary, diff.filesChanged > 0 {
                    stateLines.append("\nDiff statistics: \(diff.lineSummary)")
                }
            }
            sections.append("## CURRENT STATE\n\n\(stateLines.joined(separator: "\n"))")

            // P4: KNOWN PROBLEMS & ARCHITECTURAL DECISIONS
            if mode != .compact && !handoff.knownProblems.isEmpty {
                let problemsText = handoff.knownProblems.map { "- \($0.text)" }.joined(separator: "\n")
                sections.append("## KNOWN PROBLEMS\n\n\(problemsText)")
            }
            if !handoff.decisions.isEmpty {
                let decisionsText = handoff.decisions.map { "- \($0.text)" }.joined(separator: "\n")
                sections.append("## DECISIONS\n\n\(decisionsText)")
            }

            // P5: APPLICABLE PROJECT INSTRUCTIONS
            if !handoff.detectedInstructions.isEmpty {
                var instLines: [String] = []
                switch instructionRenderingLevel {
                case .references:
                    instLines.append("Instruction sources detected:")
                    for inst in handoff.detectedInstructions {
                        instLines.append("- \(inst.path) (scope: \(inst.scope))")
                    }
                case .bounded:
                    for inst in handoff.detectedInstructions {
                        instLines.append("### \(inst.filename) (scope: \(inst.scope))")
                        let excerpt = inst.snippet ?? String(inst.content.prefix(350))
                        let truncationNotice = (inst.content.count > excerpt.count || inst.isTruncated) ? "\n... [Truncated for \(mode.rawValue) budget]" : ""
                        instLines.append("```\n\(excerpt)\(truncationNotice)\n```")
                    }
                case .full:
                    for inst in handoff.detectedInstructions {
                        instLines.append("### \(inst.filename) (path: \(inst.path), scope: \(inst.scope))")
                        let truncationNotice = inst.isTruncated ? "\n... [Explicitly truncated at ingestion limit]" : ""
                        instLines.append("```\n\(inst.content)\(truncationNotice)\n```")
                    }
                }
                sections.append("## PROJECT INSTRUCTIONS\n\n\(instLines.joined(separator: "\n"))")
            }

            // P6: IMPORTANT FILES & WHAT EXISTS / COMPLETED WORK
            if !handoff.importantFiles.isEmpty && maxImportantFiles > 0 {
                let visibleFiles = handoff.importantFiles.prefix(maxImportantFiles)
                let filesText = visibleFiles.map { file in
                    file.reason.isEmpty ? file.path : "\(file.path)  # \(file.reason)"
                }.joined(separator: "\n")
                sections.append("## IMPORTANT FILES\n\n\(filesText)")
            }

            if includeCompletedWork && !handoff.completedWork.isEmpty {
                let items = handoff.completedWork.map { "- \($0.text)" }.joined(separator: "\n")
                sections.append("## WHAT EXISTS\n\n\(items)")
            }

            // P7: RECENT COMMITS & RECENT WORK
            if !handoff.recentCommits.isEmpty && maxCommits > 0 {
                var commitLines: [String] = ["Recent commits:"]
                for c in handoff.recentCommits.prefix(maxCommits) {
                    commitLines.append("- \(c.shortHash) \(c.subject) (\(c.date))")
                }
                sections.append("## RECENT COMMITS\n\n\(commitLines.joined(separator: "\n"))")
            }

            if includeRecentWork && !handoff.recentWork.isEmpty {
                let recentLines = handoff.recentWork.map { "- \($0.text)" }.joined(separator: "\n")
                sections.append("## RECENT WORK\n\n\(recentLines)")
            }

            // P8: TODOS, DIFF EXCERPT, NOTES
            if includeTodos && !handoff.todos.isEmpty {
                let todoLines = handoff.todos.prefix(12).map { "- [\($0.kind)] \($0.displayLocation): \($0.comment)" }.joined(separator: "\n")
                sections.append("## DETECTED TODOS\n\n\(todoLines)")
            }

            if includeDiffExcerpt, let diff = handoff.currentState.diffSummary, let snippet = diff.rawDiffSnippet {
                var diffHeader = "## GIT DIFF EXCERPT"
                if diff.isTruncated {
                    diffHeader += " (Bounded excerpt)"
                }
                sections.append("\(diffHeader)\n\n```diff\n\(snippet)\n```")
            }

            if includeNotes, let notes = handoff.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                sections.append("## NOTES\n\n\(notes)")
            }

            // DISCLOSURES (if anything was omitted or truncated to fit budget)
            if !budgetDisclosures.isEmpty {
                let discText = budgetDisclosures.map { "- \($0)" }.joined(separator: "\n")
                sections.append("## BUDGET DISCLOSURES\n\n\(discText)")
            }

            return sections.joined(separator: "\n\n")
        }

        // Budget evaluation loop: progressively omit from lowest priority upwards
        var currentOutput = assemble()
        var estimate = TokenBudgetEstimate(text: currentOutput).estimatedTokens

        // Priority 8 step: Diff excerpt
        if estimate > targetTokens && includeDiffExcerpt {
            includeDiffExcerpt = false
            budgetDisclosures.append("Diff excerpt omitted to fit \(mode.rawValue) budget target (~\(targetTokens) tokens).")
            currentOutput = assemble()
            estimate = TokenBudgetEstimate(text: currentOutput).estimatedTokens
        }

        // Priority 8 step: TODOs
        if estimate > targetTokens && includeTodos {
            includeTodos = false
            budgetDisclosures.append("TODO items omitted to fit \(mode.rawValue) budget.")
            currentOutput = assemble()
            estimate = TokenBudgetEstimate(text: currentOutput).estimatedTokens
        }

        // Priority 8 step: Notes
        if estimate > targetTokens && includeNotes {
            includeNotes = false
            budgetDisclosures.append("Notes section omitted to fit \(mode.rawValue) budget.")
            currentOutput = assemble()
            estimate = TokenBudgetEstimate(text: currentOutput).estimatedTokens
        }

        // Priority 7 step: Recent commits
        if estimate > targetTokens && maxCommits > 2 {
            maxCommits = 2
            budgetDisclosures.append("Recent commits capped at 2 to preserve budget headroom.")
            currentOutput = assemble()
            estimate = TokenBudgetEstimate(text: currentOutput).estimatedTokens
        }

        // Priority 7 step: Recent work
        if estimate > targetTokens && includeRecentWork {
            includeRecentWork = false
            budgetDisclosures.append("Recent work list omitted to fit \(mode.rawValue) budget.")
            currentOutput = assemble()
            estimate = TokenBudgetEstimate(text: currentOutput).estimatedTokens
        }

        // Priority 6 step: Completed work
        if estimate > targetTokens && includeCompletedWork {
            includeCompletedWork = false
            budgetDisclosures.append("Completed work section omitted to fit \(mode.rawValue) budget.")
            currentOutput = assemble()
            estimate = TokenBudgetEstimate(text: currentOutput).estimatedTokens
        }

        // Priority 5 step: Instructions downgrade (full -> bounded -> references)
        if estimate > targetTokens && instructionRenderingLevel == .full {
            instructionRenderingLevel = .bounded
            budgetDisclosures.append("Instruction files bounded to excerpts to fit \(mode.rawValue) budget.")
            currentOutput = assemble()
            estimate = TokenBudgetEstimate(text: currentOutput).estimatedTokens
        }

        if estimate > targetTokens && instructionRenderingLevel == .bounded {
            instructionRenderingLevel = .references
            budgetDisclosures.append("Instruction files reduced to path references to fit \(mode.rawValue) budget.")
            currentOutput = assemble()
            estimate = TokenBudgetEstimate(text: currentOutput).estimatedTokens
        }

        // Final sanity check through secret sanitizer
        return SecretFilter.sanitizeText(currentOutput)
    }
}

