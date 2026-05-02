#if canImport(XCTest)
import SwiftData
import XCTest
@testable import SlayNodeMenuBar

@MainActor
final class ServiceCenterModelTests: XCTestCase {
    func testPerformRejectsServiceThatDisappearedAfterRefresh() async throws {
        let staleService = makeService(id: "process:4101", name: "stale-server", pid: 4101)
        let currentService = makeService(id: "process:4102", name: "current-server", pid: 4102)
        let provider = StubServiceProvider(
            batches: [
                DiscoveryBatch(services: [staleService]),
                DiscoveryBatch(services: [currentService])
            ]
        )
        let center = try makeCenter(provider: provider)

        await center.refresh()
        XCTAssertEqual(center.services.map(\.id), [staleService.id])

        await center.refresh()
        XCTAssertEqual(center.services.map(\.id), [currentService.id])

        let result = await center.perform(.forceStop, on: staleService)
        let performedServiceIDs = await provider.performedServiceIDs()

        XCTAssertNil(result)
        XCTAssertEqual(center.lastError, "The selected service is no longer available.")
        XCTAssertEqual(performedServiceIDs, [])
    }

    func testPerformRejectsActionThatIsNoLongerAvailable() async throws {
        let service = makeService(
            id: "process:4201",
            name: "limited-server",
            pid: 4201,
            availableActions: [.openWorkspace]
        )
        let provider = StubServiceProvider(batches: [DiscoveryBatch(services: [service])])
        let center = try makeCenter(provider: provider)

        await center.refresh()

        let result = await center.perform(.forceStop, onServiceID: service.id)
        let performedServiceIDs = await provider.performedServiceIDs()

        XCTAssertNil(result)
        XCTAssertEqual(center.lastError, "Force Stop is no longer available for limited-server.")
        XCTAssertEqual(performedServiceIDs, [])
    }

    func testPerformResolvesTheCurrentServiceByID() async throws {
        let service = makeService(id: "process:4301", name: "current-server", pid: 4301)
        let provider = StubServiceProvider(batches: [DiscoveryBatch(services: [service])])
        let center = try makeCenter(provider: provider)

        await center.refresh()

        let result = await center.perform(.forceStop, onServiceID: service.id)
        let performedServiceIDs = await provider.performedServiceIDs()

        XCTAssertEqual(result, "Force Stop current-server")
        XCTAssertEqual(performedServiceIDs, [service.id])
    }

    private func makeCenter(provider: StubServiceProvider) throws -> ServiceCenterModel {
        let orchestrator = DiscoveryOrchestrator(
            discoveryProviders: [provider],
            controlProviders: [provider]
        )

        return ServiceCenterModel(
            orchestrator: orchestrator,
            historyStore: try makeHistoryStore(),
            settings: makeSettings()
        )
    }

    private func makeHistoryStore() throws -> ServiceHistoryStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WorkspaceHistoryRecord.self,
            ServiceHistoryRecord.self,
            ServiceActionRecord.self,
            WindowStateRecord.self,
            configurations: configuration
        )
        return ServiceHistoryStore(container: container)
    }

    private func makeSettings() -> AppSettings {
        let suiteName = "ServiceCenterModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppSettings(defaults: defaults)
    }

    private func makeService(
        id: String,
        name: String,
        pid: Int32,
        availableActions: [ServiceAction] = [.stop, .forceStop]
    ) -> ManagedService {
        ManagedService(
            id: id,
            name: name,
            kind: .app,
            status: .running,
            health: .healthy,
            source: .process(pid: pid, command: "npm run dev"),
            workspace: nil,
            ports: [ServicePort(value: Int(pid), isInferred: false)],
            runtime: "Node.js",
            summary: "Service listening on \(pid)",
            command: "npm run dev",
            configPath: nil,
            logPath: nil,
            tags: ["node", "test"],
            availableActions: availableActions,
            startedAt: nil,
            lastSeenAt: Date()
        )
    }
}

private actor StubServiceProvider: DiscoveryProvider, ControlProvider {
    nonisolated let id = "stub-service-provider"

    private var batches: [DiscoveryBatch]
    private var performedActions: [(action: ServiceAction, serviceID: String, serviceName: String)] = []

    init(batches: [DiscoveryBatch]) {
        self.batches = batches
    }

    func discoverServices() async -> DiscoveryBatch {
        guard !batches.isEmpty else {
            return DiscoveryBatch(services: [])
        }
        return batches.removeFirst()
    }

    nonisolated func canControl(_ service: ManagedService) -> Bool {
        if case .process = service.source {
            return true
        }
        return false
    }

    nonisolated func supportedActions(for service: ManagedService) -> [ServiceAction] {
        service.availableActions
    }

    func perform(_ action: ServiceAction, on service: ManagedService) async throws -> String {
        performedActions.append((action, service.id, service.name))
        return "\(action.title) \(service.name)"
    }

    func performedServiceIDs() -> [String] {
        performedActions.map(\.serviceID)
    }
}
#endif
