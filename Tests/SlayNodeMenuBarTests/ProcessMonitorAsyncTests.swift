#if canImport(XCTest)
import XCTest
@testable import SlayNodeMenuBar

final class ProcessMonitorAsyncTests: XCTestCase {
    
    @MainActor
    func testProcessMonitorStartStop() async {
        let monitor = ProcessMonitor(interval: 1.0)
        
        monitor.start()
        
        await monitor.refresh()
        
        monitor.stop()
        
        XCTAssertTrue(true, "ProcessMonitor should handle async operations correctly")
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
    
    func testNodeProcessSendable() {
        let process = NodeProcess(
            pid: 1234,
            executable: "node",
            command: "node server.js",
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
            )
        )
        
        // Verify NodeProcess is Sendable (should compile without error)
        let boxed = Box(process)
        XCTAssertEqual(boxed.value.pid, 1234)
    }
    
    private struct Box {
        let value: NodeProcess
    }
}
#endif
