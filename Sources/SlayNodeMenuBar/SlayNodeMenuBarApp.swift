import SwiftUI
import AppKit

@main
struct SlayNodeMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView(preferences: appDelegate.preferences)
                .padding(24)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = PreferencesStore()
    private var statusController: StatusItemController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let appIcon = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = appIcon
        }
        statusController = StatusItemController(preferences: preferences)
        NSApp.activate(ignoringOtherApps: true)
    }
}
