import SwiftUI
import AppKit

@main
struct SlayNodeMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var preferences = PreferencesStore()
    
    var body: some Scene {
        #if os(macOS)
        Settings {
            SettingsView(preferences: preferences)
                .padding(20)
        }
        #endif
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = PreferencesStore()
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Set the app's icon from our bundled AppIcon
        if let appIcon = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = appIcon
        }
        statusController = StatusItemController(preferences: preferences)
    }
}

