import SwiftUI
import AppKit
import ContextPacketCore

public struct ProjectPickerView: View {
    @EnvironmentObject private var state: AppState
    @State private var isTargetedForDrop: Bool = false

    public init() {}

    public var body: some View {
        ZStack {
            // Dark Neutral Grey Canvas
            MacDesktopBackground()

            VStack(spacing: 20) {
                Spacer()

                // Hero Grey Card
                VStack(spacing: 22) {
                    // App Logo Badge
                    ZStack {
                        if let nsImg = loadAppIcon() {
                            Image(nsImage: nsImg)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                        } else {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .frame(width: 64, height: 64)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )

                            Image(systemName: "shippingbox.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(Color.white)
                        }
                    }

                    // Title & Tagline
                    VStack(spacing: 6) {
                        Text("Copak")
                            .font(Theme.bitcountPropSingle)
                            .foregroundStyle(Theme.primaryText)

                        Text("Deterministic handoffs between coding agents and developers.")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center)
                    }

                    // Action & Drop Zone
                    VStack(spacing: 12) {
                        // Solid White CTA Button
                        Button(action: selectRepositoryFolder) {
                            HStack(spacing: 8) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Open Local Repository")
                                KeycapBadge("⌘O", onWhite: true)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(GoldenGatePillButtonStyle(isProminent: true))
                        .keyboardShortcut("o", modifiers: .command)

                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.doc")
                                .font(.system(size: 10))
                            Text("or drag and drop a folder anywhere here")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(Theme.tertiaryText)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 32)
                .frame(maxWidth: 500)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.containerCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.containerCornerRadius, style: .continuous)
                        .stroke(
                            isTargetedForDrop ? Color.white.opacity(0.4) : Theme.subtleBorder,
                            lineWidth: isTargetedForDrop ? 1.5 : 1
                        )
                        .animation(.easeInOut(duration: 0.15), value: isTargetedForDrop)
                )

                // Recent Repositories Section (Monochrome Command List)
                if !state.recentProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        // Section Header
                        HStack {
                            Text("RECENT REPOSITORIES")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.tertiaryText)

                            Spacer()

                            Text("\(state.recentProjects.count)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.secondaryText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundStyle(Theme.subtleBorder),
                            alignment: .bottom
                        )

                        // Scrollable List
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(state.recentProjects) { item in
                                    RecentProjectRow(item: item) {
                                        Task {
                                            await state.openRepository(at: URL(fileURLWithPath: item.path))
                                        }
                                    } onRemove: {
                                        RecentProjectsStore.shared.removeProject(path: item.path)
                                        state.loadRecentProjects()
                                    }
                                }
                            }
                            .padding(6)
                        }
                        .frame(maxHeight: 180)
                    }
                    .frame(maxWidth: 500)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.containerCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.containerCornerRadius, style: .continuous)
                            .stroke(Theme.subtleBorder, lineWidth: 1)
                    )
                }

                Spacer()

                // Error Banner if any
                if let error = state.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.coral)

                        Text(error)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.primaryText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.coral.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Theme.coral.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.bottom, 12)
                }
            }
            .padding(.top, 36) // Window traffic lights clearance
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(minWidth: 720, minHeight: 560)
        .onDrop(of: ["public.file-url"], isTargeted: $isTargetedForDrop) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                DispatchQueue.main.async {
                    Task {
                        await state.openRepository(at: url)
                    }
                }
            }
            return true
        }
    }

    private func selectRepositoryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Select a local Git repository"

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await state.openRepository(at: url)
            }
        }
    }

    private func loadAppIcon() -> NSImage? {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: iconURL) {
            return img
        }
        if let iconURL = Bundle.module.url(forResource: "Copak", withExtension: "png"),
           let img = NSImage(contentsOf: iconURL) {
            return img
        }
        if let img = NSImage(contentsOfFile: "/Users/niteesh/Downloads/Copak.png") {
            return img
        }
        return NSApp.applicationIconImage
    }
}

// MARK: - Monochrome Recent Project Row
private struct RecentProjectRow: View {
    let item: RecentProjectItem
    let onOpen: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                // Folder Icon Tile
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(isHovered ? 0.12 : 0.06))
                        .frame(width: 26, height: 26)

                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.85))
                }

                // Name & Path
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundStyle(Theme.primaryText)

                    Text(item.path)
                        .font(Theme.smallMonoFont)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if isHovered {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(4)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Remove from recents")

                    KeycapBadge("↵")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isHovered ? Color.white.opacity(0.05) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}
