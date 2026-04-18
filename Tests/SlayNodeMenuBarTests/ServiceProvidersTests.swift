#if canImport(XCTest)
import XCTest
@testable import SlayNodeMenuBar

final class ServiceProvidersTests: XCTestCase {
    func testMakeProcessServiceRedactsSensitiveArguments() {
        let process = NodeProcess(
            pid: 4242,
            ppid: 1,
            executable: "node",
            command: "node server.js --api-key secret-value --token super-secret",
            arguments: ["server.js", "--api-key", "secret-value", "--token", "super-secret"],
            ports: [3000],
            uptime: 12,
            startTime: Date(),
            workingDirectory: "/Users/test/app",
            descriptor: ServerDescriptor(
                name: "Node.js",
                displayName: "Node.js",
                category: .backend,
                runtime: "Node.js",
                packageManager: nil,
                script: nil,
                details: "Mode: DEV",
                portHints: [3000]
            ),
            commandHash: 1
        )

        let service = ServiceHeuristics.makeProcessService(
            from: process,
            ports: [3000],
            workingDirectory: "/Users/test/app"
        )

        XCTAssertNotNil(service)
        XCTAssertFalse(service?.command?.contains("secret-value") ?? true)
        XCTAssertFalse(service?.command?.contains("super-secret") ?? true)
        XCTAssertTrue(service?.command?.contains("***") ?? false)
    }

    func testRuntimeProcessWithoutServiceSignalsIsFilteredOut() {
        let process = NodeProcess(
            pid: 2121,
            ppid: 1,
            executable: "sleep",
            command: "sleep 2",
            arguments: ["2"],
            ports: [],
            uptime: 2,
            startTime: Date(),
            workingDirectory: nil,
            descriptor: ServerDescriptor(
                name: "sleep",
                displayName: "sleep",
                category: .runtime,
                runtime: nil,
                packageManager: nil,
                script: nil,
                details: nil,
                portHints: []
            ),
            commandHash: 2
        )

        let service = ServiceHeuristics.makeProcessService(from: process, ports: [], workingDirectory: nil)
        XCTAssertNil(service)
    }

    func testToolingDaemonIsFilteredOut() {
        let process = NodeProcess(
            pid: 3131,
            ppid: 1,
            executable: "node",
            command: "/opt/homebrew/bin/node /Users/test/project/node_modules/typescript/lib/tsserver.js --useNodeIpc",
            arguments: ["/Users/test/project/node_modules/typescript/lib/tsserver.js", "--useNodeIpc"],
            ports: [],
            uptime: 20,
            startTime: Date(),
            workingDirectory: "/Users/test/project",
            descriptor: ServerDescriptor(
                name: "Node.js",
                displayName: "Node.js",
                category: .runtime,
                runtime: "Node.js",
                packageManager: nil,
                script: nil,
                details: nil,
                portHints: []
            ),
            commandHash: 3
        )

        let service = ServiceHeuristics.makeProcessService(
            from: process,
            ports: [],
            workingDirectory: "/Users/test/project"
        )

        XCTAssertNil(service)
    }
}
#endif
