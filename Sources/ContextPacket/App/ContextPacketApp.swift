import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = image
        } else if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
                  let image = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = image
        } else if let image = NSImage(contentsOfFile: "/Users/niteesh/Downloads/Copak.png") {
            NSApp.applicationIconImage = image
        }

        DispatchQueue.main.async {
            for window in NSApp.windows {
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = true
                window.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1.0)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct ContextPacketApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("Copak") {
            Group {
                switch state.currentScreen {
                case .picker:
                    ProjectPickerView()
                case .overview:
                    ProjectOverviewView()
                case .preview:
                    HandoffPreviewView()
                }
            }
            .environmentObject(state)
            .preferredColorScheme(.dark)
            .frame(minWidth: 720, idealWidth: 860, minHeight: 520, idealHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Repository...") {
                    openRepositoryDialog()
                }
                .keyboardShortcut("o", modifiers: .command)

                if state.currentScreen != .picker {
                    Button("Close Repository") {
                        state.currentScreen = .picker
                    }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                }
            }

            CommandMenu("Handoff") {
                Button("Create Handoff") {
                    state.createHandoff()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(state.currentScreen == .picker)

                Button("Refresh Repository") {
                    Task { await state.refreshRepository() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(state.currentScreen == .picker)
            }
        }
    }

    private func openRepositoryDialog() {
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
}
