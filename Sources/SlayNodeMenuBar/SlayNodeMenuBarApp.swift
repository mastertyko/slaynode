import AppKit
import SwiftUI

@main
struct SlayNodeMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(preferences: appDelegate.preferences)
                .padding(20)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = PreferencesStore()
    private lazy var viewModel = MenuViewModel(preferences: preferences)
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Set the app's icon from the bundled AppIcon
        if let appIcon = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = appIcon
        }
        statusController = StatusItemController(viewModel: viewModel)
    }
}

