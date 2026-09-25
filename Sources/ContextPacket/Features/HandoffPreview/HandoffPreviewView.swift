import SwiftUI
import AppKit
import ContextPacketCore

public struct HandoffPreviewView: View {
    @EnvironmentObject private var state: AppState
    @State private var isBackHovered: Bool = false

    public init() {}

    private var tokenEstimate: TokenBudgetEstimate {
        TokenBudgetEstimate(text: state.generatedMarkdown)
    }

    public var body: some View {
        ZStack {
            Theme.canvas
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Integrated Seamless Window App Bar
                topBar

                // Dark Markdown Code Canvas
                ZStack(alignment: .topTrailing) {
                    TextEditor(text: Binding(
                        get: { state.generatedMarkdown },
                        set: {
                            state.generatedMarkdown = $0
                            state.isDraftModified = true
                        }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .lineSpacing(5)
                    .padding(20)
                    .scrollContentBackground(.hidden)
                    .background(Theme.canvas)
                    .foregroundStyle(Color.white.opacity(0.92))

                    // Floating Quick Copy Button
                    Button(action: {
                        state.copyToClipboard(provider: state.selectedProvider)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.doc.fill")
                                .font(.system(size: 10))
                            Text("Copy")
                            KeycapBadge("⌘C")
                        }
                    }
                    .buttonStyle(GoldenGatePillButtonStyle(isProminent: false))
                    .padding(14)
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
        .alert("Discard Manual Edits?", isPresented: $state.showDiscardDraftAlert) {
            Button("Discard & Switch", role: .destructive) {
                state.isDraftModified = false
                state.pendingDraftSwitchAction?()
                state.pendingDraftSwitchAction = nil
            }
            Button("Keep Editing", role: .cancel) {
                state.pendingDraftSwitchAction = nil
            }
        } message: {
            Text("You have made custom edits to this packet. Changing the target model or token budget will regenerate the handoff and overwrite your changes.")
        }
        .alert("Git Refresh Failed", isPresented: $state.showStaleExportAlert) {
            Button("Export Snapshot Anyway") {
                state.pendingStaleAction?()
                state.pendingStaleAction = nil
            }
            Button("Cancel", role: .cancel) {
                state.pendingStaleAction = nil
            }
        } message: {
            Text("Copak could not refresh the repository git status (\(state.refreshErrorMessage ?? "Unknown git error")). Exporting now may include stale repository state.")
        }
    }

    // MARK: - Top Toolbar

    private var topBar: some View {
        HStack(spacing: 0) {
            // macOS Window Traffic Lights Clearance Section (80pt)
            Color.clear
                .frame(width: 80, height: 42)

            // Left Vertical Divider
            Rectangle()
                .fill(Theme.subtleBorder)
                .frame(width: 1, height: 42)

            // Back to Overview Button Cell (42x42)
            Button(action: { state.currentScreen = .overview }) {
                ZStack {
                    Rectangle()
                        .fill(isBackHovered ? Color.white.opacity(0.08) : Color.clear)

                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isBackHovered ? Color.white : Color.white.opacity(0.8))
                }
                .frame(width: 42, height: 42)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isBackHovered = $0 }
            .help("Back to Overview")

            // Right Vertical Divider
            Rectangle()
                .fill(Theme.subtleBorder)
                .frame(width: 1, height: 42)

            // Repository Name & Breadcrumb
            HStack(spacing: 8) {
                Text(state.snapshot?.name ?? "Repository")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)

                Text("/")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiaryText)

                Text("Handoff Packet")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)

                if state.isDraftModified {
                    GoldenGateBadge(text: "Edited", systemImage: "pencil")
                }
            }
            .padding(.leading, 14)

            Spacer()

            // Token Budget Segmented Control (Monochrome Grey Style)
            HStack(spacing: 2) {
                ForEach(TokenBudgetMode.allCases) { mode in
                    Button(action: {
                        state.selectBudgetMode(mode)
                    }) {
                        Text(mode.rawValue)
                            .font(.system(size: 11, weight: state.budgetMode == mode ? .semibold : .regular))
                            .foregroundStyle(state.budgetMode == mode ? Color.black : Theme.secondaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background {
                                if state.budgetMode == mode {
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

            // Token Estimate Gauge Badge
            GoldenGateBadge(
                text: tokenEstimate.displaySummary,
                systemImage: "gauge.with.needle"
            )
            .padding(.leading, 10)
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

    // MARK: - Bottom Action Dock

    private var bottomBar: some View {
        HStack(spacing: 12) {
            // Save context.md button
            Button(action: {
                state.exportContextMarkdownFile()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 11))
                    Text("Save context.md")
                    KeycapBadge("⌘S")
                }
            }
            .buttonStyle(GoldenGatePillButtonStyle(isProminent: false))
            .help("Save context.md into repository root")

            Spacer()

            // Target Model Chips
            HStack(spacing: 4) {
                Text("Target:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.trailing, 2)

                modelChip(id: "claude", name: "Claude")
                modelChip(id: "cursor", name: "Cursor")
                modelChip(id: "codex", name: "Codex")
                modelChip(id: "generic", name: "Markdown")
            }

            // Primary Solid White Copy CTA
            Button(action: {
                state.copyToClipboard(provider: state.selectedProvider)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                    Text("Copy for \(providerDisplayName(state.selectedProvider))")
                    KeycapBadge("⌘↵", onWhite: true)
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(GoldenGatePillButtonStyle(isProminent: true))
        }
    }

    private func modelChip(id: String, name: String) -> some View {
        let isSelected = state.selectedProvider == id
        return Button(action: {
            state.selectProvider(id)
        }) {
            Text(name)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.white : Theme.secondaryText)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background {
                    if isSelected {
                        Color.white.opacity(0.12)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    } else {
                        Color.white.opacity(0.03)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(isSelected ? Color.white.opacity(0.25) : Theme.subtleBorder, lineWidth: 0.75)
                )
        }
        .buttonStyle(.plain)
    }

    private func providerDisplayName(_ provider: String) -> String {
        switch provider {
        case "claude": return "Claude"
        case "cursor": return "Cursor"
        case "codex": return "Codex"
        default: return "Markdown"
        }
    }
}
