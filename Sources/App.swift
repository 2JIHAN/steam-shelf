import AppKit
import SwiftUI

@main
struct SteamShelfApp: App {
    @StateObject private var store = Store()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Steam Shelf") {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1000, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button("Refresh") { store.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Sync Shortcuts") { store.syncShortcuts() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(store.isSyncing || !store.canSync)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
