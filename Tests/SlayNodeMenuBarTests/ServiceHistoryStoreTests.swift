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
}
#endif
