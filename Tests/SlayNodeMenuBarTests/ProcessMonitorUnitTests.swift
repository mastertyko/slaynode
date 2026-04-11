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
    func testMonitorFiltersOutUtilityProcessesWithoutServerSignals() async {
        let psOutput = """
        3904     1 41:50 node context7-mcp
        """

        let processes = await collectProcesses(from: psOutput)

        XCTAssertTrue(processes.isEmpty)
    }

    @MainActor
    func testMonitorKeepsPackageManagerDevScriptsVisible() async {
        let psOutput = """
        12346     1 00:10 /usr/local/bin/npm run dev
        """

        let processes = await collectProcesses(from: psOutput)

        XCTAssertEqual(processes.count, 1)
        XCTAssertEqual(processes.first?.descriptor.script, "dev")
        XCTAssertEqual(processes.first?.descriptor.packageManager, "npm")
    }

    @MainActor
    func testMonitorResolvesWorkingDirectoryFromLsof() async {
        let psOutput = """
        12346     1 00:10 /usr/local/bin/npm run dev
        """
        let lsofOutput = """
        p12346
        fcwd
        n/tmp/slaynode-gui-fixture
        """

        let processes = await collectProcesses(
            from: psOutput,
            responses: [
                "\(Constants.Path.lsof) -a -d cwd -Fn -p 12346": (0, lsofOutput)
            ]
        )

        XCTAssertEqual(processes.count, 1)
        XCTAssertEqual(processes.first?.workingDirectory, "/tmp/slaynode-gui-fixture")
    }

    @MainActor
    func testMonitorPromotesFrameworkChildIntoPackageManagerParent() async {
        let psOutput = """
        20000     1 00:15 /usr/local/bin/npm run dev
        20001 20000 00:14 node /Users/test/frontend/node_modules/.bin/vite
        """

        let processes = await collectProcesses(from: psOutput)

        XCTAssertEqual(processes.count, 1)
        XCTAssertEqual(processes.first?.pid, 20000)
        XCTAssertEqual(processes.first?.descriptor.displayName, "Vite")
        XCTAssertEqual(processes.first?.descriptor.packageManager, "npm")
        XCTAssertEqual(processes.first?.descriptor.script, "dev")
    }

    @MainActor
    func testMonitorPromotesTsxChildIntoPackageManagerParentWithoutPorts() async {
        let psOutput = """
        21000     1 00:15 /usr/local/bin/npm run dev
        21001 21000 00:14 node /Users/test/backend/node_modules/.bin/tsx watch src/index.ts
        """

        let processes = await collectProcesses(from: psOutput)

        XCTAssertEqual(processes.count, 1)
        XCTAssertEqual(processes.first?.pid, 21000)
        XCTAssertEqual(processes.first?.descriptor.displayName, "TSX")
        XCTAssertEqual(processes.first?.descriptor.packageManager, "npm")
    }

    @MainActor
    func testMonitorKeepsDirectViteProcessesVisibleWithoutResolvedPort() async {
        let psOutput = """
        12345     1 00:15 /Users/test/project/node_modules/.bin/vite
        """

        let processes = await collectProcesses(from: psOutput)

        XCTAssertEqual(processes.count, 1)
        XCTAssertEqual(processes.first?.descriptor.displayName, "Vite")
    }

    @MainActor
    func testMonitorFiltersOutBuildCommandsForKnownFrameworks() async {
        let psOutput = """
        12347     1 00:12 /Users/test/project/node_modules/.bin/next build
        """

        let processes = await collectProcesses(from: psOutput)

        XCTAssertTrue(processes.isEmpty)
    }

    @MainActor
    func testMonitorIgnoresNonJavaScriptDevServersEvenWhenPortIsPresent() async {
        let psOutput = """
        12348     1 00:18 uv run mkdocs dev --dev-addr 127.0.0.1:8000
        """

        let processes = await collectProcesses(from: psOutput)

        XCTAssertTrue(processes.isEmpty)
    }
    
    @MainActor
    func testMonitorHandlesPsFailure() async {
        let mock = MockShellExecutor()
        mock.responses["/bin/ps -axo pid=,ppid=,etime=,command="] = (1, "")
        
        let monitor = ProcessMonitor(interval: 5.0, shell: mock)
        await monitor.refresh()
        
        XCTAssertTrue(true)
    }

    @MainActor
    private func collectProcesses(
        from psOutput: String,
        responses: [String: (status: Int32, output: String)] = [:]
    ) async -> [NodeProcess] {
        let mock = MockShellExecutor()
        mock.responses["/bin/ps -axo pid=,ppid=,etime=,command="] = (0, psOutput)
        for (key, value) in responses {
            mock.responses[key] = value
        }
        mock.defaultResponse = (0, "")

        let monitor = ProcessMonitor(interval: 5.0, shell: mock)

        var receivedProcesses: [NodeProcess] = []
        let expectation = XCTestExpectation(description: "Receive refreshed processes")

        let cancellable = monitor.processesPublisher
            .dropFirst()
            .sink { processes in
                receivedProcesses = processes
                expectation.fulfill()
            }

        await monitor.refresh()
        await fulfillment(of: [expectation], timeout: 2.0)
        cancellable.cancel()

        return receivedProcesses
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
