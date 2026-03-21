#if canImport(XCTest)
import XCTest
import Combine
@testable import SlayNodeMenuBar

final class MenuViewModelTests: XCTestCase {
    
    private var suiteName: String!
    private var testDefaults: UserDefaults!
    private var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        suiteName = "com.slaynode.test.\(UUID().uuidString)"
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
    func testInitialState() async {
        let preferences = PreferencesStore(defaults: testDefaults)
        let monitor = ProcessMonitor(interval: 5.0)
        let viewModel = MenuViewModel(preferences: preferences, monitor: monitor)
        
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertTrue(viewModel.processes.isEmpty)
        XCTAssertNil(viewModel.lastError)
        XCTAssertNotNil(viewModel.lastUpdated)
    }
    
    @MainActor
    func testRefreshSetsLoadingState() async {
        let preferences = PreferencesStore(defaults: testDefaults)
        let monitor = ProcessMonitor(interval: 5.0)
        let viewModel = MenuViewModel(preferences: preferences, monitor: monitor)
        
        viewModel.refresh()
        
        XCTAssertTrue(viewModel.isLoading)
    }
    
    @MainActor
    func testStopProcessRejectsInvalidPid() async {
        let preferences = PreferencesStore(defaults: testDefaults)
        let monitor = ProcessMonitor(interval: 5.0)
        let viewModel = MenuViewModel(preferences: preferences, monitor: monitor)
        
        viewModel.stopProcess(-1)
        
        XCTAssertNotNil(viewModel.lastError)
        XCTAssertTrue(viewModel.lastError?.contains("invalid") == true || viewModel.lastError?.contains("no longer valid") == true)
    }
    
    @MainActor
    func testStopProcessRejectsNonExistentProcess() async {
        let preferences = PreferencesStore(defaults: testDefaults)
        let monitor = ProcessMonitor(interval: 5.0)
        let viewModel = MenuViewModel(preferences: preferences, monitor: monitor)
        
        viewModel.stopProcess(99999)
        
        XCTAssertNotNil(viewModel.lastError)
        XCTAssertTrue(viewModel.lastError?.contains("stopped") == true || viewModel.lastError?.contains("not found") == true)
    }
    
    @MainActor
    func testPreferencesAreAccessible() async {
        let preferences = PreferencesStore(defaults: testDefaults)
        preferences.setRefreshInterval(15.0)
        
        let monitor = ProcessMonitor(interval: 5.0)
        let viewModel = MenuViewModel(preferences: preferences, monitor: monitor)
        
        XCTAssertEqual(viewModel.preferences.refreshInterval, 15.0, accuracy: 0.01)
    }
}

// MARK: - MenuViewModelError Tests

final class MenuViewModelErrorTests: XCTestCase {
    
    func testProcessDetectionFailedDescription() {
        let error = MenuViewModelError.processDetectionFailed("test reason")
        XCTAssertTrue(error.localizedDescription.contains("detect"))
    }
    
    func testProcessTerminationFailedDescription() {
        let error = MenuViewModelError.processTerminationFailed(1234, "test details")
        XCTAssertTrue(error.localizedDescription.contains("1234"))
        XCTAssertTrue(error.localizedDescription.contains("test details"))
    }
    
    func testInvalidProcessIdDescription() {
        let error = MenuViewModelError.invalidProcessId(5678)
        XCTAssertTrue(error.localizedDescription.contains("5678"))
    }
    
    func testProcessNotFoundDescription() {
        let error = MenuViewModelError.processNotFound(9999)
        XCTAssertTrue(error.localizedDescription.contains("9999"))
        XCTAssertTrue(error.localizedDescription.contains("stopped"))
    }
    
    func testTimeoutDescription() {
        let error = MenuViewModelError.timeoutWaitingForShutdown(1111)
        XCTAssertTrue(error.localizedDescription.contains("1111"))
        XCTAssertTrue(error.localizedDescription.contains("longer"))
    }
    
    func testPermissionDeniedDescription() {
        let error = MenuViewModelError.permissionDenied(2222)
        XCTAssertTrue(error.localizedDescription.contains("2222"))
        XCTAssertTrue(error.localizedDescription.contains("Permission") || error.localizedDescription.contains("permission"))
    }
    
    func testUnknownErrorDescription() {
        let error = MenuViewModelError.unknownError("custom message")
        XCTAssertTrue(error.localizedDescription.contains("custom message"))
    }
}

// MARK: - NodeProcessItemViewModel Tests

final class NodeProcessItemViewModelTests: XCTestCase {
    
    func testViewModelEquality() {
        let vm1 = NodeProcessItemViewModel(
            id: 1,
            pid: 1,
            title: "Test",
            subtitle: "test",
            categoryBadge: nil,
            portBadges: [],
            infoChips: [],
            projectName: nil,
            uptimeDescription: "1m",
            startTimeDescription: "now",
            command: "node test.js",
            workingDirectory: nil,
            descriptor: .unknown,
            isStopping: false
        )
        
        let vm2 = NodeProcessItemViewModel(
            id: 1,
            pid: 1,
            title: "Test",
            subtitle: "test",
            categoryBadge: nil,
            portBadges: [],
            infoChips: [],
            projectName: nil,
            uptimeDescription: "1m",
            startTimeDescription: "now",
            command: "node test.js",
            workingDirectory: nil,
            descriptor: .unknown,
            isStopping: false
        )
        
        XCTAssertEqual(vm1, vm2)
    }
    
    func testViewModelInequalityWhenStopping() {
        let vm1 = NodeProcessItemViewModel(
            id: 1,
            pid: 1,
            title: "Test",
            subtitle: "test",
            categoryBadge: nil,
            portBadges: [],
            infoChips: [],
            projectName: nil,
            uptimeDescription: "1m",
            startTimeDescription: "now",
            command: "node test.js",
            workingDirectory: nil,
            descriptor: .unknown,
            isStopping: false
        )
        
        let vm2 = NodeProcessItemViewModel(
            id: 1,
            pid: 1,
            title: "Test",
            subtitle: "test",
            categoryBadge: nil,
            portBadges: [],
            infoChips: [],
            projectName: nil,
            uptimeDescription: "1m",
            startTimeDescription: "now",
            command: "node test.js",
            workingDirectory: nil,
            descriptor: .unknown,
            isStopping: true
        )
        
        XCTAssertNotEqual(vm1, vm2)
    }
    
    func testPortBadgeHashable() {
        let badge1 = NodeProcessItemViewModel.PortBadge(text: ":3000", isLikely: false)
        let badge2 = NodeProcessItemViewModel.PortBadge(text: ":3000", isLikely: false)
        let badge3 = NodeProcessItemViewModel.PortBadge(text: ":8080", isLikely: true)
        
        XCTAssertEqual(badge1, badge2)
        XCTAssertNotEqual(badge1, badge3)
        
        var set = Set<NodeProcessItemViewModel.PortBadge>()
        set.insert(badge1)
        set.insert(badge2)
        XCTAssertEqual(set.count, 1)
    }
    
    func testInfoChipHashable() {
        let chip1 = NodeProcessItemViewModel.InfoChip(text: "Node.js", systemImage: "cpu")
        let chip2 = NodeProcessItemViewModel.InfoChip(text: "Node.js", systemImage: "cpu")
        let chip3 = NodeProcessItemViewModel.InfoChip(text: "Python", systemImage: nil)
        
        XCTAssertEqual(chip1, chip2)
        XCTAssertNotEqual(chip1, chip3)
    }
}
#endif
