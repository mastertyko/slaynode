#if canImport(XCTest)
import XCTest
@testable import SlayNodeMenuBar

final class ProcessMonitorAsyncTests: XCTestCase {
    
    @MainActor
    func testProcessMonitorStartStop() async {
        #if DEBUG
        let mock = MockShellExecutor()
        mock.responses["/bin/ps -axo pid=,ppid=,etime=,command="] = (0, "")
        let monitor = ProcessMonitor(interval: 1.0, shell: mock)
        let expectation = XCTestExpectation(description: "Receive refresh update")
        var updateCount = 0
        let cancellable = monitor.processesPublisher
            .dropFirst()
            .sink { processes in
                updateCount += 1
                XCTAssertTrue(processes.isEmpty)
                expectation.fulfill()
            }

        monitor.start()
        await monitor.refresh()
        monitor.stop()
        await fulfillment(of: [expectation], timeout: 2.0)
        cancellable.cancel()

        XCTAssertGreaterThanOrEqual(updateCount, 1)
        #endif
    }
    
    @MainActor
    func testProcessKillerAsyncTermination() async throws {
        let killer = ProcessKiller()
        
        do {
            // Test with invalid PID to ensure error handling works
            try await killer.terminate(pid: -1)
            XCTFail("Should have thrown invalidPid error")
        } catch ProcessTerminationError.invalidPid {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProcessKillerTreatsMissingPidAsAlreadyStopped() async throws {
        let killer = ProcessKiller()

        try await killer.terminate(pid: 999_999, forceAfter: 0)
    }
    
    func testNodeProcessSendable() {
        let command = "node server.js"
        let process = NodeProcess(
            pid: 1234,
            ppid: 1,
            executable: "node",
            command: command,
            arguments: ["server.js"],
            ports: [3000],
            uptime: 60.0,
            startTime: Date(),
            workingDirectory: "/Users/test/app",
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
            commandHash: command.hashValue
        )
        
        // Verify NodeProcess is Sendable (should compile without error)
        let boxed = Box(value: process)
        XCTAssertEqual(boxed.value.pid, 1234)
    }
    
    private struct Box {
        let value: NodeProcess
    }
}
#endif
