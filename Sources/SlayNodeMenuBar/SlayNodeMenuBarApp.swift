import AppKit
import SwiftData
import SwiftUI

enum AppWindowID {
    static let dashboard = "dashboard"
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
    @NSApplicationDelegateAdaptor(ServiceAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    @State private var center: ServiceCenterModel
    @StateObject private var updateController = UpdateController()

    init() {
        let container = try! ModelContainer(
            for: WorkspaceHistoryRecord.self,
            ServiceHistoryRecord.self,
            ServiceActionRecord.self,
            WindowStateRecord.self
        )

        let settings = AppSettings()
        let historyStore = ServiceHistoryStore(container: container)
        let processProvider = ProcessServiceProvider()
        let dockerProvider = DockerServiceProvider()
        let brewProvider = BrewServiceProvider()
        let orchestrator = DiscoveryOrchestrator(
            discoveryProviders: [processProvider, dockerProvider, brewProvider],
            controlProviders: [processProvider, dockerProvider, brewProvider]
        )

        _center = State(
            initialValue: ServiceCenterModel(
                orchestrator: orchestrator,
                historyStore: historyStore,
                settings: settings
            )
        )
    }

    var body: some Scene {
        WindowGroup(id: AppWindowID.dashboard) {
            ServiceDashboardWindowView(
                center: center,
                updateController: updateController,
                lockedWorkspaceID: nil,
                sceneStateID: "main-dashboard"
            )
        }
        .defaultWindowPlacement { _, _ in
            WindowPlacement(.center, width: 1380, height: 860)
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.automatic)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About SlayNode") {
                    openWindow(id: AppWindowID.about)
                }
            }

            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text("Settings…")
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu("Services") {
                Button("Refresh Discovery") {
                    Task { await center.refresh() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        WindowGroup("Workspace", for: String.self) { workspaceID in
            let resolvedWorkspaceID = workspaceID.wrappedValue
            ServiceDashboardWindowView(
                center: center,
                updateController: updateController,
                lockedWorkspaceID: resolvedWorkspaceID,
                sceneStateID: "workspace-\(resolvedWorkspaceID ?? "unknown")"
            )
        }
        .defaultWindowPlacement { _, _ in
            WindowPlacement(.center, width: 1280, height: 800)
        }
        .restorationBehavior(.automatic)

        Settings {
            SlayNodeSettingsView(center: center, updateController: updateController)
        }

        Window("Settings", id: AppWindowID.settings) {
            SlayNodeSettingsView(center: center, updateController: updateController)
        }
        .defaultWindowPlacement { _, _ in
            WindowPlacement(.center, width: 640, height: 460)
        }

        Window("About SlayNode", id: AppWindowID.about) {
            SlayNodeAboutView()
        }
        .defaultWindowPlacement { _, _ in
            WindowPlacement(.center, width: 760, height: 560)
        }

        MenuBarExtra {
            ServiceMenuBarView(center: center)
        } label: {
            Label("SlayNode", systemImage: "shippingbox.circle.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class ServiceAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        CrashReporter.start()

        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let appIcon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = appIcon
        }

        NSApp.setActivationPolicy(.regular)
    }
}
