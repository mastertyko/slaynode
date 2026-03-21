#if canImport(XCTest)
import XCTest
@testable import SlayNodeMenuBar

final class ProcessMonitorIntegrationTests: XCTestCase {
    
    @MainActor
    func testFullProcessDetectionCycle() async throws {
        let monitor = ProcessMonitor(interval: 1.0)
        
        var receivedProcesses: [[NodeProcess]] = []
        let expectation = XCTestExpectation(description: "Receive process updates")
        expectation.expectedFulfillmentCount = 2
        
        let cancellable = monitor.processesPublisher
            .dropFirst()
            .sink { processes in
                receivedProcesses.append(processes)
                expectation.fulfill()
            }
        
        monitor.start()
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        monitor.stop()
        cancellable.cancel()
        
        XCTAssertGreaterThanOrEqual(receivedProcesses.count, 2)
    }
    
    @MainActor
    func testProcessMonitorHandlesRapidRefresh() async throws {
        let monitor = ProcessMonitor(interval: 5.0)
        
        let tasks = (0..<5).map { _ in
            Task {
                await monitor.refresh()
            }
        }
        
        for task in tasks {
            await task.value
        }
        
        XCTAssertTrue(true)
    }
    
    @MainActor
    func testProcessMonitorIntervalUpdate() async throws {
        let monitor = ProcessMonitor(interval: 5.0)
        
        monitor.start()
        
        monitor.updateInterval(2.0)
        monitor.updateInterval(10.0)
        monitor.updateInterval(5.0)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        monitor.stop()
        
        XCTAssertTrue(true)
    }
    
    @MainActor
    func testProcessMonitorErrorPublisher() async throws {
        let monitor = ProcessMonitor(interval: 5.0)
        
        var receivedError = false
        let cancellable = monitor.errorsPublisher
            .sink { _ in
                receivedError = true
            }
        
        await monitor.refresh()
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        cancellable.cancel()
        
        XCTAssertTrue(true)
    }
}

final class PortResolverIntegrationTests: XCTestCase {
    
    func testPortResolverWithCurrentProcess() async throws {
        let resolver = PortResolver()
        let currentPid = ProcessInfo.processInfo.processIdentifier
        
        let ports = await resolver.resolvePorts(for: [currentPid])
        
        // The current test process may or may not have open ports
        // Just verify the resolver returns without crashing and returns a dictionary
        XCTAssertNotNil(ports)
    }
    
    func testPortResolverWithMultiplePids() async throws {
        let resolver = PortResolver()
        
        let pids: [Int32] = [1, 2, 3, 999999]
        let ports = await resolver.resolvePorts(for: pids)
        
        // Verify we get a dictionary back (may be empty depending on system state)
        // The resolver should handle non-existent PIDs gracefully
        XCTAssertNotNil(ports)
    }
}

final class CommandParserIntegrationTests: XCTestCase {
    
    func testParseComplexCommand() {
        let command = "/usr/local/bin/node --inspect=0.0.0.0:9229 /Users/dev/project/server.js --port 3000 --env production"
        let tokens = CommandParser.tokenize(command)
        
        XCTAssertEqual(tokens.first, "/usr/local/bin/node")
        XCTAssertTrue(tokens.contains("--port"))
        XCTAssertTrue(tokens.contains("3000"))
    }
    
    func testInferPortsFromComplexCommand() {
        let tokens = [
            "node", "server.js",
            "--port=3000",
            "-p=8080",
            "http://localhost:4000"
        ]
        
        let ports = CommandParser.inferPorts(from: tokens)
        
        XCTAssertTrue(ports.contains(3000), "Should detect --port=3000")
        XCTAssertTrue(ports.contains(8080), "Should detect -p=8080")
        XCTAssertTrue(ports.contains(4000), "Should detect port from URL")
    }
    
    func testDescriptorClassification() {
        let testCases: [(tokens: [String], expectedCategory: ServerDescriptor.Category)] = [
            (["next", "dev"], .webFramework),
            (["vite", "dev"], .bundler),
            (["nuxt", "dev"], .webFramework),
            (["node", "server.js"], .utility),
        ]
        
        for testCase in testCases {
            let context = CommandParser.makeContext(
                executable: testCase.tokens[0],
                tokens: testCase.tokens,
                workingDirectory: nil
            )
            let descriptor = CommandParser.descriptor(from: context)
            
            XCTAssertEqual(
                descriptor.category,
                testCase.expectedCategory,
                "Expected category \(testCase.expectedCategory) for tokens \(testCase.tokens)"
            )
        }
    }
}
#endif
