import AppKit
import CoreSpotlight
import Foundation
import Observation
import UniformTypeIdentifiers
import UserNotifications

@Observable
@MainActor
final class AppSettings {
    private enum Keys {
        static let refreshInterval = "com.slaynode.settings.refreshInterval"
        static let showRecentHistory = "com.slaynode.settings.showRecentHistory"
        static let showMenuBarSection = "com.slaynode.settings.showMenuBarSection"
    }

    private let defaults: UserDefaults

    var refreshInterval: Double {
        didSet {
            refreshInterval = max(3, min(refreshInterval, 60))
            defaults.set(refreshInterval, forKey: Keys.refreshInterval)
        }
    }

    var showRecentHistory: Bool {
        didSet {
            defaults.set(showRecentHistory, forKey: Keys.showRecentHistory)
        }
    }

    var showMenuBarSection: Bool {
        didSet {
            defaults.set(showMenuBarSection, forKey: Keys.showMenuBarSection)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedRefresh = defaults.object(forKey: Keys.refreshInterval) as? Double
        self.refreshInterval = max(3, min(storedRefresh ?? 8, 60))

        if defaults.object(forKey: Keys.showRecentHistory) == nil {
            self.showRecentHistory = true
        } else {
            self.showRecentHistory = defaults.bool(forKey: Keys.showRecentHistory)
        }

        if defaults.object(forKey: Keys.showMenuBarSection) == nil {
            self.showMenuBarSection = true
        } else {
            self.showMenuBarSection = defaults.bool(forKey: Keys.showMenuBarSection)
        }
    }
}

@MainActor
final class ServiceCommandBridge {
    static let shared = ServiceCommandBridge()

    private var servicesByID: [String: ManagedService] = [:]
    private var actionHandler: ((ServiceAction, String) async throws -> String)?

    func update(
        services: [ManagedService],
        actionHandler: @escaping (ServiceAction, String) async throws -> String
    ) {
        self.servicesByID = Dictionary(uniqueKeysWithValues: services.map { ($0.id, $0) })
        self.actionHandler = actionHandler
    }

    func allServices() -> [ManagedService] {
        Array(servicesByID.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func service(id: String) -> ManagedService? {
        servicesByID[id]
    }

    func perform(_ action: ServiceAction, on serviceID: String) async throws -> String {
        guard let actionHandler else {
            throw ServiceControlError.missingRequirement("The command bridge is not ready yet.")
        }
        return try await actionHandler(action, serviceID)
    }
}

@MainActor
final class NotificationCoordinator {
    private var requestedAuthorization = false

    func requestAuthorizationIfNeeded() {
        guard !requestedAuthorization else { return }
        requestedAuthorization = true

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Log.general.warning("Notification authorization failed: \(error.localizedDescription)")
            } else {
                Log.general.info("Notification authorization result: \(granted)")
            }
        }
    }

    func postFailure(for service: ManagedService, message: String) {
        requestAuthorizationIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = "\(service.name) needs attention"
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "service-failure-\(service.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func postHealthWarning(for service: ManagedService) {
        requestAuthorizationIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = "\(service.name) became unhealthy"
        content.body = service.summary
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "service-health-\(service.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}

@MainActor
final class SpotlightIndexer {
    func index(snapshot: ServiceSnapshot, recentWorkspaces: [WorkspaceIdentity]) {
        var items: [CSSearchableItem] = snapshot.services.map { service in
            let attributeSet = CSSearchableItemAttributeSet(contentType: .item)
            attributeSet.title = service.name
            attributeSet.contentDescription = service.summary
            attributeSet.keywords = service.tags + service.ports.map { "port:\($0.value)" }
            return CSSearchableItem(
                uniqueIdentifier: "service:\(service.id)",
                domainIdentifier: "se.slaynode.services",
                attributeSet: attributeSet
            )
        }

        items.append(contentsOf: recentWorkspaces.map { workspace in
            let attributeSet = CSSearchableItemAttributeSet(contentType: .folder)
            attributeSet.title = workspace.name
            attributeSet.path = workspace.rootPath
            attributeSet.contentDescription = "Recent local workspace in SlayNode"
            return CSSearchableItem(
                uniqueIdentifier: "workspace:\(workspace.id)",
                domainIdentifier: "se.slaynode.workspaces",
                attributeSet: attributeSet
            )
        })

        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error {
                Log.general.warning("Spotlight indexing failed: \(error.localizedDescription)")
            }
        }
    }
}

@Observable
@MainActor
final class ServiceCenterModel {
    var settings: AppSettings

    var services: [ManagedService] = []
    var dependencies: [ServiceDependency] = []
    var lastRefreshAt: Date?
    var isRefreshing = false
    var lastError: String?
    var recentWorkspaces: [WorkspaceIdentity] = []
    var recentActions: [ServiceActionSummary] = []

    private let orchestrator: DiscoveryOrchestrator
    private let historyStore: ServiceHistoryStore
    private let notifications = NotificationCoordinator()
    private let spotlight = SpotlightIndexer()
    private var refreshLoopTask: Task<Void, Never>?
    private var knownHealth: [String: ServiceHealth] = [:]

    init(
        orchestrator: DiscoveryOrchestrator,
        historyStore: ServiceHistoryStore,
        settings: AppSettings
    ) {
        self.orchestrator = orchestrator
        self.historyStore = historyStore
        self.settings = settings
    }

    var activeServiceCount: Int {
        services.filter { $0.status == .running || $0.status == .degraded }.count
    }

    var unhealthyServiceCount: Int {
        services.filter { $0.health == .critical || $0.status == .degraded }.count
    }

    var workspaces: [WorkspaceIdentity] {
        let discovered = Set(services.compactMap(\.workspace))
        let orderedDiscovered = Array(discovered).sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        let remembered = recentWorkspaces.filter { !discovered.contains($0) }
        return orderedDiscovered + remembered
    }

    func start() {
        if refreshLoopTask == nil {
            refreshLoopTask = Task { [weak self] in
                guard let self else { return }
                await self.refresh()

                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(self.settings.refreshInterval * 1_000_000_000))
                    await self.refresh()
                }
            }
        }
    }

    func stop() {
        refreshLoopTask?.cancel()
        refreshLoopTask = nil
    }

    func restoreWindowState(id: String) -> PersistedWindowState? {
        historyStore.loadWindowState(id: id)
    }

    func persistWindowState(
        id: String,
        selectedWorkspaceID: String?,
        selectedServiceID: String?,
        searchText: String,
        inspectorVisible: Bool
    ) {
        historyStore.saveWindowState(
            id: id,
            selectedWorkspaceID: selectedWorkspaceID,
            selectedServiceID: selectedServiceID,
            searchText: searchText,
            inspectorVisible: inspectorVisible
        )
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let snapshot = await orchestrator.refreshSnapshot()

        services = snapshot.services
        dependencies = snapshot.dependencies
        lastRefreshAt = snapshot.generatedAt
        lastError = nil

        historyStore.record(snapshot: snapshot)
        recentWorkspaces = historyStore.recentWorkspaces()
        recentActions = historyStore.recentActions()
        spotlight.index(snapshot: snapshot, recentWorkspaces: recentWorkspaces)
        updateBridge()
        detectHealthTransitions(with: snapshot.services)
    }

    @discardableResult
    func perform(_ action: ServiceAction, on service: ManagedService) async -> String? {
        lastError = nil

        do {
            let outcome = try await performInternal(action, on: service)
            historyStore.record(action: action, on: service, outcome: outcome)
            recentActions = historyStore.recentActions()

            if [.stop, .forceStop, .restart].contains(action) {
                await refresh()
            }

            return outcome
        } catch {
            let message = error.localizedDescription
            lastError = message
            notifications.postFailure(for: service, message: message)
            historyStore.record(action: action, on: service, outcome: "Failed: \(message)")
            recentActions = historyStore.recentActions()
            return nil
        }
    }

    func clearLastError() {
        lastError = nil
    }

    private func performInternal(_ action: ServiceAction, on service: ManagedService) async throws -> String {
        switch action {
        case .openWorkspace:
            guard let workspace = service.workspace else {
                throw ServiceControlError.missingRequirement("No workspace is available for \(service.name).")
            }

            let url = URL(fileURLWithPath: workspace.rootPath)
            NSWorkspace.shared.open(url)
            return "Opened \(workspace.name)."

        case .revealConfig:
            guard let configPath = service.configPath else {
                throw ServiceControlError.missingRequirement("No config file is available for \(service.name).")
            }

            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: configPath)])
            return "Revealed config for \(service.name)."

        default:
            return try await orchestrator.perform(action, on: service)
        }
    }

    private func updateBridge() {
        ServiceCommandBridge.shared.update(services: services) { [weak self] action, serviceID in
            guard let self else {
                throw ServiceControlError.missingRequirement("SlayNode is not ready yet.")
            }
            guard let service = self.services.first(where: { $0.id == serviceID }) else {
                throw ServiceControlError.missingRequirement("The selected service is no longer available.")
            }
            return try await self.performInternal(action, on: service)
        }
    }

    private func detectHealthTransitions(with services: [ManagedService]) {
        let newHealth = Dictionary(uniqueKeysWithValues: services.map { ($0.id, $0.health) })

        for service in services where service.health == .critical {
            if knownHealth[service.id] != .critical {
                notifications.postHealthWarning(for: service)
            }
        }

        knownHealth = newHealth
    }
}
