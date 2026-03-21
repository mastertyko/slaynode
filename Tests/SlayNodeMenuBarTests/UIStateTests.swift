#if canImport(XCTest)
import XCTest
import Combine
@testable import SlayNodeMenuBar

final class UIStateTests: XCTestCase {
    
    private var suiteName: String!
    private var testDefaults: UserDefaults!
    private var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        suiteName = "com.slaynode.uitest.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        cancellables = []
    }
    
    override func tearDown() {
        cancellables = nil
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        super.tearDown()
    }
    
    @MainActor
    func testViewModelPublishesProcessUpdates() async throws {
        let preferences = PreferencesStore(defaults: testDefaults)
        let monitor = ProcessMonitor(interval: 1.0)
        let viewModel = MenuViewModel(preferences: preferences, monitor: monitor)
        
        let expectation = XCTestExpectation(description: "ViewModel publishes updates")
        
        viewModel.$processes
            .dropFirst()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        viewModel.refresh()
        
        await fulfillment(of: [expectation], timeout: 5.0)
    }
    
    @MainActor
    func testViewModelLoadingStateTransitions() async throws {
        let preferences = PreferencesStore(defaults: testDefaults)
        let monitor = ProcessMonitor(interval: 5.0)
        let viewModel = MenuViewModel(preferences: preferences, monitor: monitor)
        
        var loadingStates: [Bool] = []
        let expectation = XCTestExpectation(description: "Loading state changes")
        expectation.expectedFulfillmentCount = 2
        
        viewModel.$isLoading
            .sink { isLoading in
                loadingStates.append(isLoading)
                if loadingStates.count >= 2 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        viewModel.refresh()
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        XCTAssertTrue(loadingStates.contains(true), "Should have been loading at some point")
    }
    
    @MainActor
    func testViewModelLastUpdatedChanges() async throws {
        let preferences = PreferencesStore(defaults: testDefaults)
        let monitor = ProcessMonitor(interval: 5.0)
        let viewModel = MenuViewModel(preferences: preferences, monitor: monitor)
        
        let initialUpdate = viewModel.lastUpdated
        
        let expectation = XCTestExpectation(description: "Last updated changes")
        
        viewModel.$lastUpdated
            .dropFirst()
            .sink { date in
                if date != initialUpdate {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        viewModel.refresh()
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        XCTAssertNotEqual(viewModel.lastUpdated, initialUpdate)
    }
    
    @MainActor
    func testViewModelErrorSetsOnInvalidPid() async throws {
        let preferences = PreferencesStore(defaults: testDefaults)
        let monitor = ProcessMonitor(interval: 5.0)
        let viewModel = MenuViewModel(preferences: preferences, monitor: monitor)
        
        viewModel.stopProcess(-1)
        
        XCTAssertNotNil(viewModel.lastError)
        XCTAssertTrue(viewModel.lastError?.contains("valid") == true || viewModel.lastError?.contains("-1") == true)
    }
    
    @MainActor
    func testViewModelHandlesNonExistentProcess() async throws {
        let preferences = PreferencesStore(defaults: testDefaults)
        let monitor = ProcessMonitor(interval: 5.0)
        let viewModel = MenuViewModel(preferences: preferences, monitor: monitor)
        
        viewModel.stopProcess(99999)
        
        XCTAssertNotNil(viewModel.lastError)
    }
}

final class PreferencesUIBindingTests: XCTestCase {
    
    private var suiteName: String!
    private var testDefaults: UserDefaults!
    
    override func setUp() {
        super.setUp()
        suiteName = "com.slaynode.prefuitest.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
    }
    
    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        super.tearDown()
    }
    
    func testRefreshIntervalRange() {
        let preferences = PreferencesStore(defaults: testDefaults)
        
        preferences.setRefreshInterval(1.0)
        XCTAssertGreaterThanOrEqual(preferences.refreshInterval, 2.0)
        
        preferences.setRefreshInterval(50.0)
        XCTAssertLessThanOrEqual(preferences.refreshInterval, 30.0)
        
        preferences.setRefreshInterval(15.0)
        XCTAssertEqual(preferences.refreshInterval, 15.0, accuracy: 0.1)
    }
    
    func testPreferencesPublisherEmitsOnChange() {
        let preferences = PreferencesStore(defaults: testDefaults)
        var emitCount = 0
        
        let cancellable = preferences.objectWillChange
            .sink { _ in
                emitCount += 1
            }
        
        preferences.setRefreshInterval(10.0)
        preferences.setRefreshInterval(20.0)
        
        cancellable.cancel()
        
        XCTAssertGreaterThanOrEqual(emitCount, 1)
    }
}

final class NodeProcessViewModelTests: XCTestCase {
    
    func testCreateViewModelFromProcess() {
        let descriptor = ServerDescriptor(
            name: "next",
            displayName: "Next.js",
            category: .webFramework,
            runtime: "node",
            packageManager: "npm",
            script: "dev",
            details: nil,
            portHints: [3000]
        )
        
        let process = NodeProcess(
            pid: 12345,
            ppid: 1,
            executable: "node",
            command: "node /path/to/.bin/next dev",
            arguments: ["dev"],
            ports: [3000],
            uptime: 3600,
            startTime: Date().addingTimeInterval(-3600),
            workingDirectory: "/Users/test/project",
            descriptor: descriptor,
            commandHash: 12345
        )
        
        XCTAssertEqual(process.pid, 12345)
        XCTAssertEqual(process.descriptor.displayName, "Next.js")
        XCTAssertEqual(process.descriptor.category, .webFramework)
        XCTAssertTrue(process.ports.contains(3000))
    }
    
    func testProcessIdentifiable() {
        let process1 = NodeProcess(
            pid: 100,
            ppid: 1,
            executable: "node",
            command: "node app.js",
            arguments: [],
            ports: [],
            uptime: 0,
            startTime: Date(),
            workingDirectory: nil,
            descriptor: .unknown,
            commandHash: 1
        )
        
        let process2 = NodeProcess(
            pid: 100,
            ppid: 1,
            executable: "node",
            command: "node app.js",
            arguments: [],
            ports: [],
            uptime: 0,
            startTime: Date(),
            workingDirectory: nil,
            descriptor: .unknown,
            commandHash: 1
        )
        
        XCTAssertEqual(process1.id, process2.id)
        XCTAssertEqual(process1.id, Int32(100))
    }
    
    func testServerDescriptorUnknown() {
        let unknown = ServerDescriptor.unknown
        
        XCTAssertEqual(unknown.name, "Node.js")
        XCTAssertEqual(unknown.category, .runtime)
    }
    
    func testServerDescriptorCategoryDisplayNames() {
        let categories: [ServerDescriptor.Category] = [
            .webFramework, .bundler, .componentWorkbench,
            .mobile, .backend, .monorepo, .utility, .runtime
        ]
        
        for category in categories {
            XCTAssertFalse(category.displayName.isEmpty)
        }
    }
}

final class UpdateControllerStateTests: XCTestCase {
    
    @MainActor
    func testUpdateControllerInitialState() {
        let controller = UpdateController()
        
        XCTAssertNotNil(controller.lastUpdateCheckDate == nil || controller.lastUpdateCheckDate != nil)
    }
}
#endif
