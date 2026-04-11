import SwiftUI
import AppKit

enum AppWindowID {
    static let settings = "settings"
    static let about = "about"
}

enum AuxiliarySheet: String, Identifiable {
    case settings
    case about

    var id: String { rawValue }
}

@main
struct SlayNodeMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var activeSheet: AuxiliarySheet?
    
    var body: some Scene {
        WindowGroup("SlayNode") {
            MainWindowView(
                preferences: appDelegate.preferences,
                monitor: appDelegate.processMonitor,
                updateController: appDelegate.updateController,
                activeSheet: $activeSheet
            )
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About SlayNode") {
                    presentAuxiliarySheet(.about)
                }
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    presentAuxiliarySheet(.settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        Window("SlayNode Settings", id: AppWindowID.settings) {
            SettingsView(preferences: appDelegate.preferences, updateController: appDelegate.updateController)
        }

        Window("About SlayNode", id: AppWindowID.about) {
            AboutWindowView()
        }
    }

    private func presentAuxiliarySheet(_ sheet: AuxiliarySheet) {
        NSApp.activate(ignoringOtherApps: true)
        activeSheet = sheet
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = PreferencesStore()
    let processMonitor = ProcessMonitor()
    let updateController = UpdateController()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        CrashReporter.start()
        
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let appIcon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = appIcon
        }
        NSApp.setActivationPolicy(.regular)
        processMonitor.start()
        Task { await processMonitor.refresh() }
        NSApp.activate(ignoringOtherApps: true)
        closeLegacyAuxiliaryWindows()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            closeLegacyAuxiliaryWindows()
        }
        
        updateController.checkForUpdatesInBackground()
    }

    private func closeLegacyAuxiliaryWindows() {
        let auxiliaryTitles: Set<String> = ["SlayNode Settings", "About SlayNode"]

        for window in NSApp.windows where auxiliaryTitles.contains(window.title) {
            window.close()
        }
    }
}
