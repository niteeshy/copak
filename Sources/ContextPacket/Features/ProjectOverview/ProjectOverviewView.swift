import SwiftUI
import AppKit
import ContextPacketCore

public enum OverviewViewMode: String, CaseIterable, Identifiable {
    case basic = "Basic"
    case advanced = "Advanced"

    public var id: String { rawValue }
}

public struct ProjectOverviewView: View {
    @EnvironmentObject private var state: AppState

    @State private var viewMode: OverviewViewMode = .basic
    @State private var newDecisionText: String = ""
    @State private var newTaskText: String = ""
    @State private var newProblemText: String = ""
    @State private var newImportantFilePath: String = ""
    @State private var newCompletedWorkText: String = ""
    @State private var newRecentWorkText: String = ""
    @State private var isShowingChangedFiles: Bool = false

    @State private var isRepositoryStateExpanded: Bool = false
    @State private var isImportantFilesExpanded: Bool = false
    @State private var isHomeHovered: Bool = false

    public init() {}

    public var body: some View {
        ZStack {
            // Dark Neutral Grey Canvas
            MacDesktopBackground()

            VStack(spacing: 0) {
                // Integrated Seamless Window App Bar
                headerBar

                // Scrollable Content Cards
                ScrollView {
                    VStack(spacing: 14) {
                        // Basic Options (Always visible)
                        currentGoalSection
                        nextTasksSection
                        completedWorkSection
                        repositoryStateSection

                        // Advanced Options (Hidden by default)
                        if viewMode == .advanced {
                            // Subheader Divider
                            HStack(spacing: 8) {
                                Text("ADVANCED OPTIONS")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Theme.tertiaryText)

                                Rectangle()
                                    .fill(Theme.subtleBorder)
                                    .frame(height: 1)
                            }
                            .padding(.top, 4)

                            decisionsSection
                            knownProblemsSection
                            recentWorkSection
                            notesSection
                            importantFilesSection

                            if let instructions = state.snapshot?.detectedInstructionFiles, !instructions.isEmpty {
                                detectedInstructionsSection(instructions)
                            }

                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    viewMode = .basic
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 9, weight: .bold))
                                    Text("Hide Advanced Options")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundStyle(Theme.secondaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.02))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(Theme.subtleBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            // Show Advanced Options Trigger Card
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    viewMode = .advanced
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Text("Show Advanced Options")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Theme.primaryText)

                                    let advancedCount = (state.session?.decisions.count ?? 0)
                                        + (state.session?.knownProblems.count ?? 0)
                                        + (state.session?.recentWork.count ?? 0)
                                        + ((state.session?.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? 1 : 0)
                                        + state.importantFiles.count
                                        + (state.snapshot?.detectedInstructionFiles.count ?? 0)
                                    if advancedCount > 0 {
                                        Text("\(advancedCount) active")
                                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(Theme.secondaryText)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.white.opacity(0.06))
                                            .clipShape(Capsule())
                                    }

                                    Spacer()

                                    Text("Decisions, Problems, Recent Work, Notes")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.secondaryText)

                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Theme.tertiaryText)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Theme.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                                        .stroke(Theme.subtleBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                }

                // Bottom Action Dock
                bottomBar
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Theme.cardBackground)
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundStyle(Theme.subtleBorder),
                        alignment: .top
                    )
            }
            .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            if let toast = state.toastMessage {
                ToastBanner(message: toast)
                    .padding(.bottom, 24)
            }
        }
        .alert("Git Refresh Failed", isPresented: $state.showStaleExportAlert) {
            Button("Proceed with Stale Snapshot") {
                state.pendingStaleAction?()
                state.pendingStaleAction = nil
            }
            Button("Cancel", role: .cancel) {
                state.pendingStaleAction = nil
            }
        } message: {
            Text("Copak could not refresh the repository git status (\(state.refreshErrorMessage ?? "Unknown git error")). Generating now may include stale repository state.")
        }
    }

    // MARK: - App Bar

    private var headerBar: some View {
        HStack(spacing: 0) {
            // macOS Window Traffic Lights Clearance Section (80pt)
            Color.clear
                .frame(width: 80, height: 42)

            // Left Vertical Divider
            Rectangle()
                .fill(Theme.subtleBorder)
                .frame(width: 1, height: 42)

            // Home / Repositories Button Cell (42x42)
            Button(action: { state.currentScreen = .picker }) {
                ZStack {
                    Rectangle()
                        .fill(isHomeHovered ? Color.white.opacity(0.08) : Color.clear)

                    Image(systemName: "house")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(isHomeHovered ? Color.white : Color.white.opacity(0.8))
                }
                .frame(width: 42, height: 42)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHomeHovered = $0 }
            .help("Repositories")

            // Right Vertical Divider
            Rectangle()
                .fill(Theme.subtleBorder)
                .frame(width: 1, height: 42)

            // Repository Name & Monochrome Badges
            HStack(spacing: 8) {
                Text(state.snapshot?.name ?? "Repository")
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundStyle(Theme.primaryText)

                if let branch = state.snapshot?.branch {
                    GoldenGateBadge(
                        text: branch,
                        systemImage: "arrow.triangle.branch"
                    )
                }

                if let eco = state.snapshot?.projectMetadata.ecosystem, eco != "Generic" {
                    GoldenGateBadge(text: eco)
                }
            }
            .padding(.leading, 14)

            Spacer()

            // Basic / Advanced View Mode Segmented Control
            HStack(spacing: 2) {
                ForEach(OverviewViewMode.allCases) { mode in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            viewMode = mode
                        }
                    }) {
                        Text(mode.rawValue)
                            .font(.system(size: 11, weight: viewMode == mode ? .semibold : .regular))
                            .foregroundStyle(viewMode == mode ? Color.black : Theme.secondaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background {
                                if viewMode == mode {
                                    Color.white
                                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Theme.subtleBorder, lineWidth: 1)
            )
            .padding(.trailing, 10)

            // Quick Refresh Button
            Button(action: {
                Task { await state.refreshRepository() }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Refresh")
                    KeycapBadge("⌘R")
                }
            }
            .buttonStyle(GoldenGatePillButtonStyle(isProminent: false))
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh repository status (⌘R)")
            .padding(.trailing, 16)
        }
        .frame(height: 42)
        .background(Theme.cardBackground)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Theme.subtleBorder),
            alignment: .bottom
        )
    }

    // MARK: - Sections

    private var currentGoalSection: some View {
        SectionCard(
            title: "CURRENT GOAL",
            subtitle: "What are you trying to accomplish right now?"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: Binding(
                    get: { state.session?.currentGoal ?? "" },
                    set: {
                        state.session?.currentGoal = $0
                        state.saveCurrentSession()
                    }
                ))
                .font(Theme.bodyFont)
                .foregroundStyle(Color.white.opacity(0.95))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 56, maxHeight: 90)
                .padding(10)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Theme.subtleBorder, lineWidth: 1)
                )

                if (state.session?.currentGoal ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "lightbulb")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.secondaryText)
                        Text("Stating your active goal prevents the LLM from hallucinating unintended refactors.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
    }

    private var repositoryStateSection: some View {
        SectionCard(
            title: state.snapshot?.isGitRepository == false ? "PROJECT DIRECTORY STATE" : "REPOSITORY STATE",
            subtitle: "Detected from local working directory"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                // Header Toggle Bar
                HStack(spacing: 8) {
                    if let snap = state.snapshot {
                        if !snap.isGitRepository {
                            GoldenGateBadge(text: "Non-Git Project", systemImage: "folder.fill")
                        } else if snap.isClean {
                            GoldenGateBadge(text: "Clean Tree", hasGlow: true)
                        } else {
                            if !snap.modifiedFiles.isEmpty {
                                GoldenGateBadge(text: "\(snap.modifiedFiles.count) modified", systemImage: "pencil")
                            }
                            if !snap.stagedFiles.isEmpty {
                                GoldenGateBadge(text: "\(snap.stagedFiles.count) staged", systemImage: "plus.circle")
                            }
                            if !snap.untrackedFiles.isEmpty {
                                GoldenGateBadge(text: "\(snap.untrackedFiles.count) untracked", systemImage: "questionmark.circle")
                            }
                            if snap.hasOmittedSensitiveChanges {
                                GoldenGateBadge(text: "Sensitive changes omitted", systemImage: "lock.shield")
                            }
                        }

                        if let diff = snap.diffSummary, diff.filesChanged > 0 {
                            HStack(spacing: 4) {
                                Text("+\(diff.additions)")
                                    .foregroundStyle(Color.white.opacity(0.85))
                                Text("-\(diff.deletions)")
                                    .foregroundStyle(Color.white.opacity(0.60))
                            }
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                    }

                    Spacer()

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isRepositoryStateExpanded.toggle()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text(isRepositoryStateExpanded ? "Collapse" : "Inspect details")
                            Image(systemName: isRepositoryStateExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }

                if let snap = state.snapshot, snap.hasOmittedSensitiveChanges {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.orange)
                        Text("Working tree contains sensitive changes omitted from the packet.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                    )
                }

                // Expanded changed files & commits
                if isRepositoryStateExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        if let snap = state.snapshot, !snap.isGitRepository {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.secondaryText)
                                Text("This folder is not a Git repository. Git commit history and working tree diffs are not tracked.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            .padding(8)
                            .background(Color.white.opacity(0.02))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        } else if let snap = state.snapshot, !snap.allChangedFilePaths.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(snap.modifiedFiles) { f in
                                    changedFileRow(path: f.path, status: "M")
                                }
                                ForEach(snap.stagedFiles) { f in
                                    changedFileRow(path: f.path, status: "A")
                                }
                                ForEach(snap.untrackedFiles) { f in
                                    changedFileRow(path: f.path, status: "??")
                                }
                            }
                            .padding(8)
                            .background(Color.white.opacity(0.02))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Theme.subtleBorder, lineWidth: 1)
                            )
                        }

                        if let commits = state.snapshot?.recentCommits, !commits.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Recent Commits")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.tertiaryText)

                                ForEach(commits.prefix(3)) { c in
                                    HStack(spacing: 8) {
                                        Text(c.shortHash)
                                            .font(Theme.tinyMonoFont)
                                            .foregroundStyle(Color.white.opacity(0.85))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.white.opacity(0.06))
                                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                                        Text(c.subject)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.primaryText)
                                            .lineLimit(1)

                                        Spacer()

                                        Text(c.date)
                                            .font(Theme.tinyMonoFont)
                                            .foregroundStyle(Theme.tertiaryText)
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            }
        }
    }

    private func changedFileRow(path: String, status: String) -> some View {
        HStack(spacing: 6) {
            Text(status)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .frame(width: 24, alignment: .leading)

            Text(path)
                .font(Theme.smallMonoFont)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)

            Spacer()
        }
    }

    private var importantFilesSection: some View {
        SectionCard(
            title: "IMPORTANT FILES",
            subtitle: "Files the receiving agent should inspect first"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                // Header with expand toggle
                HStack {
                    Text("\(state.importantFiles.count) files pinned for context")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)

                    Spacer()

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isImportantFilesExpanded.toggle()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text(isImportantFilesExpanded ? "Collapse" : "Manage")
                            Image(systemName: isImportantFilesExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }

                if isImportantFilesExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(state.importantFiles) { file in
                            HStack(spacing: 8) {
                                Button(action: { state.togglePin(path: file.path) }) {
                                    Image(systemName: file.isPinned ? "star.fill" : "star")
                                        .font(.system(size: 10))
                                        .foregroundStyle(file.isPinned ? Color.white : Theme.tertiaryText)
                                }
                                .buttonStyle(.plain)

                                Text(file.path)
                                    .font(Theme.smallMonoFont)
                                    .foregroundStyle(Theme.primaryText)
                                    .lineLimit(1)

                                if !file.reason.isEmpty {
                                    Text("• \(file.reason)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.secondaryText)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Button(action: { state.removeImportantFile(path: file.path) }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Theme.tertiaryText)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.02))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }

                        HStack(spacing: 8) {
                            LinearInputField("Add file path (e.g. Models/State.swift)", text: $newImportantFilePath) {
                                state.addImportantFile(path: newImportantFilePath)
                                newImportantFilePath = ""
                            }

                            Button("Add") {
                                state.addImportantFile(path: newImportantFilePath)
                                newImportantFilePath = ""
                            }
                            .buttonStyle(GoldenGatePillButtonStyle(isProminent: false))
                            .disabled(newImportantFilePath.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    private var decisionsSection: some View {
        SectionCard(
            title: "DECISIONS",
            subtitle: "Architectural choices, constraints, or rejected approaches"
        ) {
            VStack(alignment: .leading, spacing: 6) {
                if let decisions = state.session?.decisions, !decisions.isEmpty {
                    ForEach(decisions) { d in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(Color.white.opacity(0.7))
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)

                            Text(d.text)
                                .font(Theme.bodyFont)
                                .foregroundStyle(Theme.primaryText)

                            Spacer()

                            Button(action: { state.removeDecision(id: d.id) }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Theme.tertiaryText)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.02))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }

                HStack(spacing: 8) {
                    LinearInputField("Add decision (e.g. Use native SwiftUI rather than AppKit)", text: $newDecisionText) {
                        state.addDecision(newDecisionText)
                        newDecisionText = ""
                    }

                    Button("Add") {
                        state.addDecision(newDecisionText)
                        newDecisionText = ""
                    }
                    .buttonStyle(GoldenGatePillButtonStyle(isProminent: false))
                    .disabled(newDecisionText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.top, 4)
            }
        }
    }

    private var nextTasksSection: some View {
        SectionCard(
            title: "NEXT TASKS",
            subtitle: "What should the receiving agent execute next?"
        ) {
            VStack(alignment: .leading, spacing: 6) {
                if let tasks = state.session?.nextTasks, !tasks.isEmpty {
                    ForEach(tasks) { t in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .padding(.top, 2)

                            Text(t.text)
                                .font(Theme.bodyFont)
                                .foregroundStyle(Theme.primaryText)

                            Spacer()

                            Button(action: { state.removeNextTask(id: t.id) }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Theme.tertiaryText)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.02))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }

                HStack(spacing: 8) {
                    LinearInputField("Add next task (e.g. Implement the 80–100% charging state)", text: $newTaskText) {
                        state.addNextTask(newTaskText)
                        newTaskText = ""
                    }

                    Button("Add") {
                        state.addNextTask(newTaskText)
                        newTaskText = ""
                    }
                    .buttonStyle(GoldenGatePillButtonStyle(isProminent: false))
                    .disabled(newTaskText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.top, 4)
            }
        }
    }

    private var completedWorkSection: some View {
        SectionCard(
            title: "COMPLETED WORK",
            subtitle: "What features, fixes, or components have already been implemented?"
        ) {
            VStack(alignment: .leading, spacing: 6) {
                if let items = state.session?.completedWork, !items.isEmpty {
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.8))
                                .padding(.top, 2)

                            Text(item.text)
                                .font(Theme.bodyFont)
                                .foregroundStyle(Theme.primaryText)

                            Spacer()

                            Button(action: { state.removeCompletedWork(text: item.text) }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Theme.tertiaryText)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.02))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }

                HStack(spacing: 8) {
                    LinearInputField("Add completed work (e.g. Set up authentication router)", text: $newCompletedWorkText) {
                        state.addCompletedWork(newCompletedWorkText)
                        newCompletedWorkText = ""
                    }

                    Button("Add") {
                        state.addCompletedWork(newCompletedWorkText)
                        newCompletedWorkText = ""
                    }
                    .buttonStyle(GoldenGatePillButtonStyle(isProminent: false))
                    .disabled(newCompletedWorkText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.top, 4)
            }
        }
    }

    private var recentWorkSection: some View {
        SectionCard(
            title: "RECENT WORK",
            subtitle: "Specific changes made in the latest agent session"
        ) {
            VStack(alignment: .leading, spacing: 6) {
                if let items = state.session?.recentWork, !items.isEmpty {
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .padding(.top, 2)

                            Text(item.text)
                                .font(Theme.bodyFont)
                                .foregroundStyle(Theme.primaryText)

                            Spacer()

                            Button(action: { state.removeRecentWork(text: item.text) }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Theme.tertiaryText)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.02))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }

                HStack(spacing: 8) {
                    LinearInputField("Add recent work item (e.g. Fixed regex in SecretFilter)", text: $newRecentWorkText) {
                        state.addRecentWork(newRecentWorkText)
                        newRecentWorkText = ""
                    }

                    Button("Add") {
                        state.addRecentWork(newRecentWorkText)
                        newRecentWorkText = ""
                    }
                    .buttonStyle(GoldenGatePillButtonStyle(isProminent: false))
                    .disabled(newRecentWorkText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.top, 4)
            }
        }
    }

    private var notesSection: some View {
        SectionCard(
            title: "SESSION NOTES",
            subtitle: "Freeform handover notes, warnings, or environment tips"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: Binding(
                    get: { state.session?.notes ?? "" },
                    set: { state.updateNotes($0) }
                ))
                .font(Theme.bodyFont)
                .foregroundStyle(Color.white.opacity(0.95))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 56, maxHeight: 110)
                .padding(10)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Theme.subtleBorder, lineWidth: 1)
                )
            }
        }
    }

    private var knownProblemsSection: some View {
        SectionCard(
            title: "KNOWN PROBLEMS",
            subtitle: "Known bugs, gotchas, or failed attempts"
        ) {
            VStack(alignment: .leading, spacing: 6) {
                if let problems = state.session?.knownProblems, !problems.isEmpty {
                    ForEach(problems) { p in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .padding(.top, 2)

                            Text(p.text)
                                .font(Theme.bodyFont)
                                .foregroundStyle(Theme.primaryText)

                            Spacer()

                            Button(action: { state.removeKnownProblem(id: p.id) }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Theme.tertiaryText)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.02))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }

                HStack(spacing: 8) {
                    LinearInputField("Add known problem (e.g. Animation resets when menu closes)", text: $newProblemText) {
                        state.addKnownProblem(newProblemText)
                        newProblemText = ""
                    }

                    Button("Add") {
                        state.addKnownProblem(newProblemText)
                        newProblemText = ""
                    }
                    .buttonStyle(GoldenGatePillButtonStyle(isProminent: false))
                    .disabled(newProblemText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.top, 4)
            }
        }
    }

    private func detectedInstructionsSection(_ instructions: [InstructionFile]) -> some View {
        SectionCard(
            title: "PROJECT INSTRUCTIONS DETECTED"
        ) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(instructions) { inst in
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.7))

                        Text(inst.path)
                            .font(Theme.smallMonoFont)
                            .foregroundStyle(Theme.primaryText)

                        Spacer()

                        GoldenGateBadge(text: "Active")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.02))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if let snap = state.snapshot {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 5, height: 5)

                    Text("\(snap.name) • Ready for handoff")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            Spacer()

            Button(action: {
                state.createHandoff()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                    Text("Create Handoff")
                    KeycapBadge("⌘⇧H", onWhite: true)
                }
            }
            .buttonStyle(GoldenGatePillButtonStyle(isProminent: true))
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .help("Create portable handoff (⌘⇧H)")
        }
    }
}
