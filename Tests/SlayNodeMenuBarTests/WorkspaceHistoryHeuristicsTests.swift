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

        for name in ["coverage", "out", "storybook-static", ".next", ".turbo", ".pnpm-store", ".omx", ".codex", ".claude"] {
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

    func testEligibleRecentWorkspaceRejectsDisallowedGeneratedPathComponents() throws {
        let tempRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let generatedPath = tempRoot
            .appendingPathComponent("frontend")
            .appendingPathComponent("dist")
            .appendingPathComponent("web")
        try FileManager.default.createDirectory(at: generatedPath, withIntermediateDirectories: true)

        let workspace = WorkspaceIdentity(
            id: generatedPath.path.lowercased(),
            name: "frontend",
            rootPath: generatedPath.path
        )

        XCTAssertFalse(WorkspaceHistoryHeuristics.isEligibleRecentWorkspace(workspace))
    }

    func testEligibleRecentWorkspaceRejectsVersionControlMetadataPaths() throws {
        let tempRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let gitPath = tempRoot
            .appendingPathComponent(".git")
            .appendingPathComponent("worktrees")
            .appendingPathComponent("session")
        try FileManager.default.createDirectory(at: gitPath, withIntermediateDirectories: true)

        let workspace = WorkspaceIdentity(
            id: gitPath.path.lowercased(),
            name: "session",
            rootPath: gitPath.path
        )

        XCTAssertFalse(WorkspaceHistoryHeuristics.isEligibleRecentWorkspace(workspace))
    }

    func testEligibleRecentWorkspaceRejectsOMXStatePaths() throws {
        let tempRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let omxStatePath = tempRoot
            .appendingPathComponent("frontend")
            .appendingPathComponent(".omx")
            .appendingPathComponent("state")
        try FileManager.default.createDirectory(at: omxStatePath, withIntermediateDirectories: true)

        let workspace = WorkspaceIdentity(
            id: omxStatePath.path.lowercased(),
            name: "frontend",
            rootPath: omxStatePath.path
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
