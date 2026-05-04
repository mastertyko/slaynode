#if canImport(XCTest)
import XCTest
@testable import SlayNodeMenuBar

final class ProcessActionPreviewTests: XCTestCase {
    func testParseProcessRowsKeepsFullCommand() {
        let output = """
          4100     1  4100 /usr/local/bin/npm run dev -- --port 3000
          4101  4100  4100 node /Users/test/app/node_modules/.bin/vite --host 127.0.0.1
        """

        let rows = ProcessActionPreviewer.parseProcessRows(from: output)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].pid, 4100)
        XCTAssertEqual(rows[0].parentPID, 1)
        XCTAssertEqual(rows[0].processGroupID, 4100)
        XCTAssertEqual(rows[0].command, "/usr/local/bin/npm run dev -- --port 3000")
        XCTAssertEqual(rows[1].parentPID, 4100)
    }

    func testForceStopPreviewIncludesProcessGroupMembers() throws {
        let service = makeProcessService(pid: 4100)
        let rows = [
            ProcessActionPreviewer.ProcessRow(pid: 4100, parentPID: 1, processGroupID: 4100, command: "npm run dev"),
            ProcessActionPreviewer.ProcessRow(pid: 4101, parentPID: 4100, processGroupID: 4100, command: "node vite --token secret-value"),
            ProcessActionPreviewer.ProcessRow(pid: 4110, parentPID: 1, processGroupID: 4110, command: "node other.js")
        ]

        let preview = try XCTUnwrap(
            ProcessActionPreviewer.makePreview(
                action: .forceStop,
                service: service,
                targetPID: 4100,
                fallbackCommand: "npm run dev",
                rows: rows,
                portsByPid: [4100: [3000], 4101: [5173]]
            )
        )

        XCTAssertEqual(preview.scope, .processGroup)
        XCTAssertEqual(preview.riskLevel, .high)
        XCTAssertEqual(preview.processes.map(\.pid), [4100, 4101])
        XCTAssertEqual(preview.processes.map(\.role), [.target, .child])
        XCTAssertEqual(preview.processes[0].ports, [3000])
        XCTAssertEqual(preview.processes[1].ports, [5173])
        XCTAssertFalse(preview.processes[1].command.contains("secret-value"))
        XCTAssertTrue(preview.processes[1].command.contains("***"))
        XCTAssertTrue(preview.warnings.contains { $0.contains("SIGKILL") })
    }

    func testStopPreviewForGroupLeaderIncludesRecursiveDescendants() throws {
        let service = makeProcessService(pid: 4200)
        let rows = [
            ProcessActionPreviewer.ProcessRow(pid: 4200, parentPID: 1, processGroupID: 4200, command: "npm run dev"),
            ProcessActionPreviewer.ProcessRow(pid: 4201, parentPID: 4200, processGroupID: 4200, command: "node vite"),
            ProcessActionPreviewer.ProcessRow(pid: 4202, parentPID: 4201, processGroupID: 4200, command: "node worker")
        ]

        let preview = try XCTUnwrap(
            ProcessActionPreviewer.makePreview(
                action: .stop,
                service: service,
                targetPID: 4200,
                fallbackCommand: "npm run dev",
                rows: rows,
                portsByPid: [:]
            )
        )

        XCTAssertEqual(preview.scope, .processTree)
        XCTAssertEqual(preview.riskLevel, .moderate)
        XCTAssertEqual(preview.processes.map(\.pid), [4200, 4201, 4202])
        XCTAssertEqual(preview.processes.map(\.role), [.target, .child, .descendant])
        XCTAssertEqual(preview.processes.map(\.depth), [0, 1, 2])
    }

    func testPreviewFallsBackToServiceIdentityWhenLiveRowsAreUnavailable() throws {
        let service = makeProcessService(pid: 4300)

        let preview = try XCTUnwrap(
            ProcessActionPreviewer.makePreview(
                action: .stop,
                service: service,
                targetPID: 4300,
                fallbackCommand: "npm run dev --api-key secret-value",
                rows: [],
                portsByPid: [:]
            )
        )

        XCTAssertEqual(preview.scope, .unavailable)
        XCTAssertEqual(preview.riskLevel, .unknown)
        XCTAssertEqual(preview.processes.map(\.pid), [4300])
        XCTAssertEqual(preview.processes.first?.ports, [3000])
        XCTAssertFalse(preview.processes.first?.command.contains("secret-value") ?? true)
        XCTAssertNotNil(preview.warning)
    }

    func testPreviewLimitsLargeProcessGroupsAndReportsHiddenCount() throws {
        let service = makeProcessService(pid: 4400)
        let rows = [ProcessActionPreviewer.ProcessRow(pid: 4400, parentPID: 1, processGroupID: 4400, command: "npm run dev")]
            + (1...30).map { offset in
                ProcessActionPreviewer.ProcessRow(
                    pid: Int32(4400 + offset),
                    parentPID: 4400,
                    processGroupID: 4400,
                    command: "node worker-\(offset).js"
                )
            }

        let preview = try XCTUnwrap(
            ProcessActionPreviewer.makePreview(
                action: .forceStop,
                service: service,
                targetPID: 4400,
                fallbackCommand: "npm run dev",
                rows: rows,
                portsByPid: [:]
            )
        )

        XCTAssertEqual(preview.visibleProcessCount, ProcessActionPreviewer.maxProcessCount)
        XCTAssertEqual(preview.omittedProcessCount, 31 - ProcessActionPreviewer.maxProcessCount)
        XCTAssertEqual(preview.processCount, 31)
        XCTAssertTrue(preview.hasOmittedProcesses)
        XCTAssertTrue(preview.warnings.contains { $0.contains("hidden") })
    }

    func testPreviewWarnsWhenLiveCommandDiffersFromDiscoveredCommand() throws {
        let service = makeProcessService(pid: 4500)
        let rows = [
            ProcessActionPreviewer.ProcessRow(pid: 4500, parentPID: 1, processGroupID: 4500, command: "pnpm dev")
        ]

        let preview = try XCTUnwrap(
            ProcessActionPreviewer.makePreview(
                action: .stop,
                service: service,
                targetPID: 4500,
                fallbackCommand: "npm run dev",
                rows: rows,
                portsByPid: [:]
            )
        )

        XCTAssertTrue(preview.warnings.contains { $0.contains("live command differs") })
    }

    func testPortSummaryCompactsLongPortLists() throws {
        let service = makeProcessService(pid: 4600)
        let rows = [
            ProcessActionPreviewer.ProcessRow(pid: 4600, parentPID: 1, processGroupID: 4600, command: "npm run dev")
        ]

        let preview = try XCTUnwrap(
            ProcessActionPreviewer.makePreview(
                action: .stop,
                service: service,
                targetPID: 4600,
                fallbackCommand: "npm run dev",
                rows: rows,
                portsByPid: [4600: [3000, 3001, 3002, 3003, 3004]]
            )
        )

        XCTAssertEqual(preview.portSummary, ":3000 :3001 :3002 :3003 +1")
    }

    func testDockerServiceDoesNotNeedProcessPreview() async {
        let service = ManagedService(
            id: "docker:abc123",
            name: "postgres",
            kind: .database,
            status: .running,
            health: .healthy,
            source: .docker(containerID: "abc123", image: "postgres:latest"),
            workspace: nil,
            ports: [ServicePort(value: 5432, isInferred: false)],
            runtime: "postgres:latest",
            summary: "Container listening on 5432",
            command: nil,
            configPath: nil,
            logPath: nil,
            tags: ["docker"],
            availableActions: [.stop, .restart],
            startedAt: nil,
            lastSeenAt: Date()
        )

        let previewer = ProcessActionPreviewer()
        let preview = await previewer.preview(action: .stop, service: service)

        XCTAssertNil(preview)
    }

    private func makeProcessService(pid: Int32) -> ManagedService {
        ManagedService(
            id: "process:\(pid)",
            name: "frontend",
            kind: .app,
            status: .running,
            health: .healthy,
            source: .process(pid: pid, command: "npm run dev"),
            workspace: WorkspaceIdentity(id: "/users/test/app", name: "app", rootPath: "/Users/test/app"),
            ports: [ServicePort(value: 3000, isInferred: false)],
            runtime: "Node.js",
            summary: "Application listening on 3000",
            command: "npm run dev",
            configPath: nil,
            logPath: nil,
            tags: ["node", "npm"],
            availableActions: [.stop, .forceStop],
            startedAt: Date(),
            lastSeenAt: Date()
        )
    }
}
#endif
