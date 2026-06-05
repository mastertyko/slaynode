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

        for name in [
            "coverage",
            "out",
            "storybook-static",
            "deriveddata",
            ".build",
            ".angular",
            ".direnv",
            ".expo",
            ".next",
            ".pytest_cache",
            ".parcel-cache",
            ".swiftpm",
            ".turbo",
            ".pnpm-store",
            ".vercel",
            ".venv",
            ".vite",
            ".wrangler",
            ".omx",
            ".codex",
            ".claude"
        ] {
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
        for component in ["dist", ".output", "cache", ".parcel-cache"] {
            let generatedPath = tempRoot
                .appendingPathComponent("frontend")
                .appendingPathComponent(component)
                .appendingPathComponent("web")
            try FileManager.default.createDirectory(at: generatedPath, withIntermediateDirectories: true)

            let workspace = WorkspaceIdentity(
                id: generatedPath.path.lowercased(),
                name: "frontend",
                rootPath: generatedPath.path
            )

            XCTAssertFalse(
                WorkspaceHistoryHeuristics.isEligibleRecentWorkspace(workspace),
                "Expected \(component) paths to be ignored"
            )
        }
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

    func testEligibleRecentWorkspaceRejectsEditorAndAgentStatePaths() throws {
        let tempRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        for components in [
            ["frontend", ".vscode", "workspaceStorage"],
            ["frontend", ".cursor", "state"],
            ["frontend", ".idea", "shelf"],
            ["frontend", ".zed", "workspace"],
            ["frontend", ".sisyphus", "evidence"]
        ] {
            let statePath = components.reduce(tempRoot) { partialResult, component in
                partialResult.appendingPathComponent(component)
            }
            try FileManager.default.createDirectory(at: statePath, withIntermediateDirectories: true)

            let workspace = WorkspaceIdentity(
                id: statePath.path.lowercased(),
                name: "frontend",
                rootPath: statePath.path
            )

            XCTAssertFalse(
                WorkspaceHistoryHeuristics.isEligibleRecentWorkspace(workspace),
                statePath.path
            )
        }
    }

    func testEligibleRecentWorkspaceRejectsXcodeDerivedDataPaths() throws {
        let tempRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let derivedDataPath = tempRoot
            .appendingPathComponent("Library")
            .appendingPathComponent("Developer")
            .appendingPathComponent("Xcode")
            .appendingPathComponent("DerivedData")
            .appendingPathComponent("MyApp-abc123")
        try FileManager.default.createDirectory(at: derivedDataPath, withIntermediateDirectories: true)

        let workspace = WorkspaceIdentity(
            id: derivedDataPath.path.lowercased(),
            name: "MyApp-abc123",
            rootPath: derivedDataPath.path
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
