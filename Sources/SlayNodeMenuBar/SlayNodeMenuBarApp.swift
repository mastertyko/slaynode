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
    let processMonitor = ProcessMonitor()
    private var statusController: StatusItemController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let appIcon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = appIcon
        }
        processMonitor.start()
        statusController = StatusItemController(preferences: preferences, monitor: processMonitor)
        NSApp.activate(ignoringOtherApps: true)
    }
}
