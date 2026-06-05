#if canImport(XCTest)
import XCTest
@testable import SlayNodeMenuBar

final class ServiceExperienceViewTests: XCTestCase {
    func testWorkspaceServiceCountsGroupsByWorkspaceID() {
        let appWorkspace = WorkspaceIdentity(id: "workspace:/app", name: "app", rootPath: "/tmp/app")
        let apiWorkspace = WorkspaceIdentity(id: "workspace:/api", name: "api", rootPath: "/tmp/api")
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

    private func makeService(id: String, name: String, workspace: WorkspaceIdentity?) -> ManagedService {
        ManagedService(
            id: id,
            name: name,
            kind: .app,
            status: .running,
            health: .healthy,
            source: .process(pid: 999, command: "npm run dev"),
            workspace: workspace,
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
    }
}
#endif
