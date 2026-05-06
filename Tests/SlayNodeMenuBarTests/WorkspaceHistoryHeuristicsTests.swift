#if canImport(XCTest)
import Foundation
import XCTest
@testable import SlayNodeMenuBar

final class WorkspaceHistoryHeuristicsTests: XCTestCase {
    func testEligibleRecentWorkspaceAcceptsNormalProjectFolder() throws {
        let tempRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let workspace = WorkspaceIdentity(
            id: tempRoot.path.lowercased(),
            name: "frontend",
            rootPath: tempRoot.path
        )

        XCTAssertTrue(WorkspaceHistoryHeuristics.isEligibleRecentWorkspace(workspace))
    }

    func testEligibleRecentWorkspaceRejectsOpaqueIdentifierName() throws {
        let tempRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let workspace = WorkspaceIdentity(
            id: tempRoot.path.lowercased(),
            name: "69c381f8ad94b576",
            rootPath: tempRoot.path
        )

        XCTAssertFalse(WorkspaceHistoryHeuristics.isEligibleRecentWorkspace(workspace))
    }

    func testEligibleRecentWorkspaceRejectsDisallowedFolderName() throws {
        let tempRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let workspace = WorkspaceIdentity(
            id: tempRoot.path.lowercased(),
            name: ".bin",
            rootPath: tempRoot.path
        )

        XCTAssertFalse(WorkspaceHistoryHeuristics.isEligibleRecentWorkspace(workspace))
    }

    func testEligibleRecentWorkspaceRejectsGeneratedOutputFolderNames() throws {
        let tempRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        for name in ["coverage", "out", "storybook-static"] {
            let workspace = WorkspaceIdentity(
                id: tempRoot.appendingPathComponent(name).path.lowercased(),
                name: name,
                rootPath: tempRoot.path
            )

            XCTAssertFalse(WorkspaceHistoryHeuristics.isEligibleRecentWorkspace(workspace))
        }
    }

    func testEligibleRecentWorkspaceRejectsNodeModulesPaths() throws {
        let tempRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let packagePath = tempRoot
            .appendingPathComponent("node_modules")
            .appendingPathComponent("vite")
        try FileManager.default.createDirectory(at: packagePath, withIntermediateDirectories: true)

        let workspace = WorkspaceIdentity(
            id: packagePath.path.lowercased(),
            name: "vite",
            rootPath: packagePath.path
        )

        XCTAssertFalse(WorkspaceHistoryHeuristics.isEligibleRecentWorkspace(workspace))
    }

    private func makeTempDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
#endif
