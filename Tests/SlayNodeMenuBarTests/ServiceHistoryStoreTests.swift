#if canImport(XCTest)
import SwiftData
import XCTest
@testable import SlayNodeMenuBar

@MainActor
final class ServiceHistoryStoreTests: XCTestCase {
    func testRecentWorkspacesReturnsEmptyForNonPositiveLimit() throws {
        let store = try makeStore()

        XCTAssertEqual(store.recentWorkspaces(limit: 0), [])
        XCTAssertEqual(store.recentWorkspaces(limit: -1), [])
    }

    func testRecentActionsReturnsEmptyForNonPositiveLimit() throws {
        let store = try makeStore()

        XCTAssertEqual(store.recentActions(limit: 0), [])
        XCTAssertEqual(store.recentActions(limit: -1), [])
    }

    func testWindowStateRoundTripsPersistedValues() throws {
        let store = try makeStore()

        store.saveWindowState(
            id: "dashboard",
            selectedWorkspaceID: "workspace:/demo",
            selectedServiceID: "process:123",
            searchText: "api 3000",
            inspectorVisible: false
        )

        let state = try XCTUnwrap(store.loadWindowState(id: "dashboard"))
        XCTAssertEqual(state.selectedWorkspaceID, "workspace:/demo")
        XCTAssertEqual(state.selectedServiceID, "process:123")
        XCTAssertEqual(state.searchText, "api 3000")
        XCTAssertFalse(state.inspectorVisible)
    }

    func testWindowStateSanitizesStoredIdentifiersAndSearchText() throws {
        let store = try makeStore()

        store.saveWindowState(
            id: "dashboard",
            selectedWorkspaceID: "workspace:/demo",
            selectedServiceID: "process:123",
            searchText: " api\t\n3000 ",
            inspectorVisible: true
        )

        let descriptor = FetchDescriptor<WindowStateRecord>()
        let record = try XCTUnwrap(store.modelContext.fetch(descriptor).first)
        XCTAssertEqual(record.id, "dashboard")
        XCTAssertEqual(record.selectedWorkspaceID, "workspace:/demo")
        XCTAssertEqual(record.selectedServiceID, "process:123")
        XCTAssertEqual(record.searchText, "api 3000")

        let state = try XCTUnwrap(store.loadWindowState(id: "dashboard"))
        XCTAssertEqual(state.selectedWorkspaceID, "workspace:/demo")
        XCTAssertEqual(state.selectedServiceID, "process:123")
        XCTAssertEqual(state.searchText, "api 3000")
    }

    func testWindowStateRejectsIdentifiersWithControlCharacters() throws {
        let store = try makeStore()

        store.saveWindowState(
            id: "dashboard\t",
            selectedWorkspaceID: "workspace:/demo\n",
            selectedServiceID: "process:\t123",
            searchText: "api",
            inspectorVisible: true
        )

        let records = try store.modelContext.fetch(FetchDescriptor<WindowStateRecord>())
        XCTAssertTrue(records.isEmpty)
        XCTAssertNil(store.loadWindowState(id: "dashboard\t"))
    }

    func testRecentActionsSkipsUnknownLegacyRows() throws {
        let store = try makeStore()
        store.modelContext.insert(ServiceActionRecord(
            serviceID: "process:1",
            serviceName: "legacy",
            actionRawValue: "obsolete",
            outcome: "Ignored",
            timestamp: Date(timeIntervalSince1970: 2)
        ))
        store.modelContext.insert(ServiceActionRecord(
            serviceID: "process:2",
            serviceName: "server",
            actionRawValue: ServiceAction.stop.rawValue,
            outcome: "Stopped",
            timestamp: Date(timeIntervalSince1970: 1)
        ))
        try store.modelContext.save()

        let actions = store.recentActions(limit: 1)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.action, .stop)
    }

    func testRecentActionsFindsValidRowsPastLegacyRows() throws {
        let store = try makeStore()
        for offset in 0..<12 {
            store.modelContext.insert(ServiceActionRecord(
                serviceID: "process:legacy-\(offset)",
                serviceName: "legacy",
                actionRawValue: "obsolete",
                outcome: "Ignored",
                timestamp: Date(timeIntervalSince1970: TimeInterval(100 + offset))
            ))
        }
        store.modelContext.insert(ServiceActionRecord(
            serviceID: "process:valid",
            serviceName: "server",
            actionRawValue: ServiceAction.restart.rawValue,
            outcome: "Restarted",
            timestamp: Date(timeIntervalSince1970: 1)
        ))
        try store.modelContext.save()

        let actions = store.recentActions(limit: 1)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.action, .restart)
    }

    func testRecordActionRefreshesExistingServiceMetadata() throws {
        let store = try makeStore()
        let oldWorkspace = WorkspaceIdentity(id: "old", name: "old", rootPath: "/tmp")
        let newWorkspace = WorkspaceIdentity(id: "new", name: "new", rootPath: NSTemporaryDirectory())

        store.record(snapshot: ServiceSnapshot(
            services: [makeService(name: "old-api", kind: .app, workspace: oldWorkspace, status: .running)],
            dependencies: [],
            generatedAt: Date(timeIntervalSince1970: 1)
        ))
        store.record(
            action: .stop,
            on: makeService(name: "new-worker", kind: .worker, workspace: newWorkspace, status: .degraded),
            outcome: "Stopped"
        )

        let descriptor = FetchDescriptor<ServiceHistoryRecord>()
        let record = try XCTUnwrap(store.modelContext.fetch(descriptor).first)
        XCTAssertEqual(record.name, "new-worker")
        XCTAssertEqual(record.kindRawValue, ServiceKind.worker.rawValue)
        XCTAssertEqual(record.workspaceID, "new")
        XCTAssertEqual(record.workspaceName, "new")
        XCTAssertEqual(record.statusRawValue, ManagedServiceStatus.degraded.rawValue)
    }

    func testRecordSnapshotSanitizesPersistedServiceAndWorkspaceFields() throws {
        let store = try makeStore()
        let workspace = WorkspaceIdentity(
            id: " workspace:/demo ",
            name: "Demo\tWorkspace\n",
            rootPath: "/tmp/demo\tworkspace\n"
        )
        let service = makeService(
            name: "demo\tapi\n",
            kind: .api,
            workspace: workspace,
            status: .running
        )

        store.record(snapshot: ServiceSnapshot(
            services: [service],
            dependencies: [],
            generatedAt: Date(timeIntervalSince1970: 1)
        ))

        let record = try XCTUnwrap(store.modelContext.fetch(FetchDescriptor<ServiceHistoryRecord>()).first)
        XCTAssertEqual(record.id, "process:999")
        XCTAssertEqual(record.name, "demo api")
        XCTAssertEqual(record.workspaceID, "workspace:/demo")
        XCTAssertEqual(record.workspaceName, "Demo Workspace")
        XCTAssertEqual(record.workspacePath, "/tmp/demo workspace")
    }

    func testRecordSnapshotSkipsInvalidServiceIdentifier() throws {
        let store = try makeStore()
        let workspace = WorkspaceIdentity(
            id: "workspace:/demo",
            name: "Demo Workspace",
            rootPath: NSTemporaryDirectory()
        )
        let service = ManagedService(
            id: "process:\t999",
            name: "demo",
            kind: .api,
            status: .running,
            health: .healthy,
            source: .process(pid: 999, command: "npm run dev"),
            workspace: workspace,
            ports: [ServicePort(value: 999, isInferred: false)],
            runtime: "Node.js",
            summary: "summary",
            command: "npm run dev",
            configPath: nil,
            logPath: nil,
            tags: [],
            availableActions: [.stop],
            startedAt: nil,
            lastSeenAt: Date()
        )

        store.record(snapshot: ServiceSnapshot(
            services: [service],
            dependencies: [],
            generatedAt: Date(timeIntervalSince1970: 1)
        ))

        XCTAssertTrue(try store.modelContext.fetch(FetchDescriptor<ServiceHistoryRecord>()).isEmpty)
        let workspaces = try store.modelContext.fetch(FetchDescriptor<WorkspaceHistoryRecord>())
        XCTAssertEqual(workspaces.map(\.id), [workspace.id])
    }

    func testRecordActionSanitizesPersistedOutcomeAndServiceName() throws {
        let store = try makeStore()

        store.record(
            action: .restart,
            on: makeService(name: "worker\tone\n", kind: .worker, workspace: nil, status: .running),
            outcome: "Restarted\tcleanly\n"
        )

        let actionRecord = try XCTUnwrap(store.modelContext.fetch(FetchDescriptor<ServiceActionRecord>()).first)
        XCTAssertEqual(actionRecord.serviceName, "worker one")
        XCTAssertEqual(actionRecord.outcome, "Restarted cleanly")
    }

    func testRecordActionSkipsInvalidServiceIdentifier() throws {
        let store = try makeStore()
        let service = ManagedService(
            id: "process:\n999",
            name: "worker",
            kind: .worker,
            status: .running,
            health: .healthy,
            source: .process(pid: 999, command: "npm run dev"),
            workspace: nil,
            ports: [],
            runtime: "Node.js",
            summary: "summary",
            command: "npm run dev",
            configPath: nil,
            logPath: nil,
            tags: [],
            availableActions: [.stop],
            startedAt: nil,
            lastSeenAt: Date()
        )

        store.record(action: .stop, on: service, outcome: "Stopped")

        XCTAssertTrue(try store.modelContext.fetch(FetchDescriptor<ServiceActionRecord>()).isEmpty)
        XCTAssertTrue(try store.modelContext.fetch(FetchDescriptor<ServiceHistoryRecord>()).isEmpty)
    }

    func testRecordSnapshotIncrementsWorkspaceOpenCount() throws {
        let store = try makeStore()
        let workspace = WorkspaceIdentity(id: "fixture", name: "fixture", rootPath: NSTemporaryDirectory())
        let service = makeService(name: "api", kind: .api, workspace: workspace, status: .running)

        store.record(snapshot: ServiceSnapshot(services: [service], dependencies: [], generatedAt: Date(timeIntervalSince1970: 1)))
        store.record(snapshot: ServiceSnapshot(services: [service], dependencies: [], generatedAt: Date(timeIntervalSince1970: 2)))

        let record = try XCTUnwrap(store.modelContext.fetch(FetchDescriptor<WorkspaceHistoryRecord>()).first)
        XCTAssertEqual(record.openCount, 2)
    }

    func testRecordSnapshotSkipsIneligibleWorkspaceHistory() throws {
        let store = try makeStore()
        let workspace = WorkspaceIdentity(
            id: "node-modules-vite",
            name: "vite",
            rootPath: "/tmp/demo/node_modules/vite"
        )
        let service = makeService(name: "vite", kind: .app, workspace: workspace, status: .running)

        store.record(snapshot: ServiceSnapshot(services: [service], dependencies: [], generatedAt: Date()))

        let records = try store.modelContext.fetch(FetchDescriptor<WorkspaceHistoryRecord>())
        XCTAssertTrue(records.isEmpty)
    }

    func testRecordActionSkipsIneligibleWorkspaceHistory() throws {
        let store = try makeStore()
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let packagePath = root
            .appendingPathComponent("node_modules")
            .appendingPathComponent("vite")
        try FileManager.default.createDirectory(at: packagePath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = WorkspaceIdentity(
            id: packagePath.path.lowercased(),
            name: "vite",
            rootPath: packagePath.path
        )

        store.record(
            action: .stop,
            on: makeService(name: "vite", kind: .app, workspace: workspace, status: .running),
            outcome: "Stopped"
        )

        let records = try store.modelContext.fetch(FetchDescriptor<WorkspaceHistoryRecord>())
        XCTAssertTrue(records.isEmpty)
    }

    func testRecordSnapshotSkipsEditorStateWorkspaceHistory() throws {
        let store = try makeStore()
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let editorStatePath = root
            .appendingPathComponent("frontend")
            .appendingPathComponent(".vscode")
            .appendingPathComponent("workspaceStorage")
        try FileManager.default.createDirectory(at: editorStatePath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = WorkspaceIdentity(
            id: editorStatePath.path.lowercased(),
            name: "frontend",
            rootPath: editorStatePath.path
        )
        let service = makeService(name: "vite", kind: .app, workspace: workspace, status: .running)

        store.record(snapshot: ServiceSnapshot(services: [service], dependencies: [], generatedAt: Date()))

        let records = try store.modelContext.fetch(FetchDescriptor<WorkspaceHistoryRecord>())
        XCTAssertTrue(records.isEmpty)
    }

    private func makeStore() throws -> ServiceHistoryStore {
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

    private func makeService(
        name: String,
        kind: ServiceKind,
        workspace: WorkspaceIdentity?,
        status: ManagedServiceStatus
    ) -> ManagedService {
        ManagedService(
            id: "process:999",
            name: name,
            kind: kind,
            status: status,
            health: status == .degraded ? .watch : .healthy,
            source: .process(pid: 999, command: "npm run dev"),
            workspace: workspace,
            ports: [ServicePort(value: 999, isInferred: false)],
            runtime: "Node.js",
            summary: "test service",
            command: "npm run dev",
            configPath: nil,
            logPath: nil,
            tags: ["test"],
            availableActions: [.stop],
            startedAt: nil,
            lastSeenAt: Date()
        )
    }
}
#endif
