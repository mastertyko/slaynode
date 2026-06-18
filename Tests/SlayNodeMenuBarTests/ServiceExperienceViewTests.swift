#if canImport(XCTest)
import XCTest
@testable import SlayNodeMenuBar

final class ServiceExperienceViewTests: XCTestCase {
    func testPreferredServiceSelectionKeepsCurrentSelectionWhenStillVisible() {
        let selection = preferredServiceSelection(
            selectedServiceID: "process:200",
            previousServiceIDs: ["process:100", "process:200", "process:300"],
            currentServiceIDs: ["process:200", "process:400"]
        )

        XCTAssertEqual(selection, "process:200")
    }

    func testPreferredServiceSelectionFallsForwardToNearestVisibleNeighbor() {
        let selection = preferredServiceSelection(
            selectedServiceID: "process:200",
            previousServiceIDs: ["process:100", "process:200", "process:300", "process:400"],
            currentServiceIDs: ["process:100", "process:300", "process:500"]
        )

        XCTAssertEqual(selection, "process:300")
    }

    func testPreferredServiceSelectionFallsBackToPreviousVisibleNeighborWhenNeeded() {
        let selection = preferredServiceSelection(
            selectedServiceID: "process:300",
            previousServiceIDs: ["process:100", "process:200", "process:300"],
            currentServiceIDs: ["process:100", "process:200"]
        )

        XCTAssertEqual(selection, "process:200")
    }

    func testPreferredServiceSelectionUsesFirstVisibleServiceWithoutSelectionHistory() {
        let selection = preferredServiceSelection(
            selectedServiceID: "process:999",
            previousServiceIDs: [],
            currentServiceIDs: ["process:100", "process:200"]
        )

        XCTAssertEqual(selection, "process:100")
    }

    func testWorkspaceServiceCountsGroupsByWorkspaceID() {
        let appWorkspace = makeWorkspaceFixture()
        let apiWorkspace = makeWorkspaceFixture(id: "workspace:/api", name: "api", rootPath: "/tmp/api")
        let services = [
            makeService(id: "process:100", name: "frontend", workspace: appWorkspace),
            makeService(id: "process:101", name: "worker", workspace: appWorkspace),
            makeService(id: "process:200", name: "backend", workspace: apiWorkspace),
            makeService(id: "process:300", name: "detached", workspace: nil)
        ]

        let counts = workspaceServiceCounts(services: services)

        XCTAssertEqual(counts[appWorkspace.id], 2)
        XCTAssertEqual(counts[apiWorkspace.id], 1)
        XCTAssertNil(counts["detached"])
    }

    func testServiceListEmptyStateShowsDiscoveryErrorVariant() {
        let content = serviceListEmptyStateContent(
            searchText: "",
            lastError: "ps failed"
        )

        XCTAssertEqual(content.title, "Discovery Needs Attention")
        XCTAssertEqual(content.systemImage, "exclamationmark.triangle")
    }

    func testServiceListEmptyStateShowsSearchVariant() {
        let content = serviceListEmptyStateContent(
            searchText: "vite",
            lastError: nil
        )

        XCTAssertEqual(content.title, "No Matching Services")
        XCTAssertEqual(content.systemImage, "magnifyingglass")
    }

    func testServiceListEmptyStateShowsDiscoveryVariantWithoutSearchOrError() {
        let content = serviceListEmptyStateContent(
            searchText: "  ",
            lastError: " \n "
        )

        XCTAssertEqual(content.title, "No Services Found")
        XCTAssertEqual(content.systemImage, "bolt.slash")
    }

    func testServiceStatusAccessibilityLabelIncludesHealthContext() {
        let service = makeManagedServiceFixture(
            id: "process:101",
            name: "api",
            kind: .api,
            status: .degraded,
            health: .watch,
            source: .process(pid: 101, command: "npm run api"),
            ports: [],
            command: "npm run api"
        )

        XCTAssertEqual(serviceStatusAccessibilityLabel(for: service), "Status Degraded, Needs attention")
    }

    func testServicePortAccessibilityLabelDescribesLikelyPorts() {
        let service = makeManagedServiceFixture(
            id: "process:202",
            name: "frontend",
            source: .process(pid: 202, command: "npm run dev"),
            ports: [
                ServicePort(value: 3000, isInferred: false),
                ServicePort(value: 5173, isInferred: true)
            ],
            command: "npm run dev"
        )

        XCTAssertEqual(
            servicePortAccessibilityLabel(for: service),
            "Listening on ports port 3000, likely port 5173"
        )
    }

    private func makeService(id: String, name: String, workspace: WorkspaceIdentity?) -> ManagedService {
        makeManagedServiceFixture(
            id: id,
            name: name,
            source: .process(pid: 999, command: "npm run dev"),
            workspace: workspace,
            ports: [],
            command: "npm run dev"
        )
    }
}
#endif
