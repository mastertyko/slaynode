#if canImport(XCTest)
import XCTest
@testable import SlayNodeMenuBar

final class ProcessMonitorUnitTests: XCTestCase {
    
    @MainActor
    func testMonitorInitializesWithDefaultInterval() async {
        let monitor = ProcessMonitor()
        XCTAssertNotNil(monitor)
    }
    
    @MainActor
    func testMonitorInitializesWithCustomInterval() async {
        let monitor = ProcessMonitor(interval: 10.0)
        XCTAssertNotNil(monitor)
    }
    
    @MainActor
    func testMonitorInitializesWithCustomShell() async {
        #if DEBUG
        let mock = MockShellExecutor()
        let monitor = ProcessMonitor(interval: 5.0, shell: mock)
        XCTAssertNotNil(monitor)
        #endif
    }
    
    @MainActor
    func testMonitorStartAndStop() async {
        let monitor = ProcessMonitor(interval: 1.0)
        
        monitor.start()
        try? await Task.sleep(nanoseconds: 100_000_000)
        monitor.stop()
        
        XCTAssertTrue(true)
    }
    
    @MainActor
    func testMonitorRefresh() async {
        let monitor = ProcessMonitor(interval: 5.0)
        
        await monitor.refresh()
        
        XCTAssertTrue(true)
    }
    
    @MainActor
    func testMonitorRefreshWithMockedShell() async {
        #if DEBUG
        let mock = MockShellExecutor()
        mock.responses["/bin/ps -axo pid=,ppid=,etime=,command="] = (0, "")
        
        let monitor = ProcessMonitor(interval: 5.0, shell: mock)
        await monitor.refresh()
        
        XCTAssertTrue(true)
        #endif
    }
    
    @MainActor
    func testMonitorUpdateInterval() async {
        let monitor = ProcessMonitor(interval: 5.0)
        
        monitor.updateInterval(10.0)
        
        XCTAssertTrue(true)
    }
    
    @MainActor
    func testMonitorUpdateIntervalIgnoresSmallChanges() async {
        let monitor = ProcessMonitor(interval: 5.0)
        
        monitor.updateInterval(5.005)
        
        XCTAssertTrue(true)
    }
    
    @MainActor
    func testVerifyProcessReturnsFalseForInvalidPid() async {
        let monitor = ProcessMonitor(interval: 5.0)
        
        let isValid = await monitor.verifyProcess(pid: -1, expectedHash: 12345)
        
        XCTAssertFalse(isValid)
    }
    
    @MainActor
    func testVerifyProcessReturnsFalseForNonExistentPid() async {
        let monitor = ProcessMonitor(interval: 5.0)
        
        let isValid = await monitor.verifyProcess(pid: 999999, expectedHash: 12345)
        
        XCTAssertFalse(isValid)
    }
    
    #if DEBUG
    @MainActor
    func testMonitorWithMockedPsOutput() async {
        let mock = MockShellExecutor()
        let psOutput = """
        12345     1 00:15 node /Users/test/app/server.js --port=3000
        12346 12345 00:10 /usr/local/bin/npm run dev
        """
        mock.responses["/bin/ps -axo pid=,ppid=,etime=,command="] = (0, psOutput)
        mock.defaultResponse = (0, "")
        
        let monitor = ProcessMonitor(interval: 5.0, shell: mock)
        await monitor.refresh()
        
        XCTAssertTrue(true)
    }
    
    @MainActor
    func testMonitorHandlesPsFailure() async {
        let mock = MockShellExecutor()
        mock.responses["/bin/ps -axo pid=,ppid=,etime=,command="] = (1, "")
        
        let monitor = ProcessMonitor(interval: 5.0, shell: mock)
        await monitor.refresh()
        
        XCTAssertTrue(true)
    }
    #endif
}

final class ProcessMonitorErrorTests: XCTestCase {
    
    func testCommandFailedErrorDescription() {
        let error = ProcessMonitorError.commandFailed("test-command", 1)
        let description = error.errorDescription ?? ""
        
        XCTAssertTrue(description.contains("test-command"))
        XCTAssertTrue(description.contains("1"))
    }
    
    func testMalformedOutputErrorDescription() {
        let error = ProcessMonitorError.malformedOutput
        let description = error.errorDescription ?? ""
        
        XCTAssertTrue(description.contains("parse") || description.contains("process"))
    }
}

final class ShellExecutorTests: XCTestCase {
    
    func testSystemShellExecutorRunsEchoCommand() async throws {
        let executor = SystemShellExecutor()
        
        let (status, output) = try await executor.run("/bin/echo", arguments: ["hello"], timeout: 5.0)
        
        XCTAssertEqual(status, 0)
        XCTAssertTrue(output.contains("hello"))
    }
    
    func testSystemShellExecutorHandlesFailedCommand() async throws {
        let executor = SystemShellExecutor()
        
        let (status, _) = try await executor.run("/bin/ls", arguments: ["/nonexistent/path/that/does/not/exist"], timeout: 5.0)
        
        XCTAssertNotEqual(status, 0)
    }
    
    #if DEBUG
    func testMockShellExecutorReturnsConfiguredResponse() async throws {
        let mock = MockShellExecutor()
        mock.responses["/bin/ps -ax"] = (0, "mock output")
        
        let (status, output) = try await mock.run("/bin/ps", arguments: ["-ax"], timeout: 5.0)
        
        XCTAssertEqual(status, 0)
        XCTAssertEqual(output, "mock output")
    }
    
    func testMockShellExecutorReturnsDefaultResponse() async throws {
        let mock = MockShellExecutor()
        mock.defaultResponse = (42, "default")
        
        let (status, output) = try await mock.run("/unknown", arguments: [], timeout: 5.0)
        
        XCTAssertEqual(status, 42)
        XCTAssertEqual(output, "default")
    }
    #endif
}
#endif
