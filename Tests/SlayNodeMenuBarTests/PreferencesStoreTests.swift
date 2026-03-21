#if canImport(XCTest)
import XCTest
@testable import SlayNodeMenuBar

final class PreferencesStoreTests: XCTestCase {
    
    private var suiteName: String!
    private var testDefaults: UserDefaults!
    
    override func setUp() {
        super.setUp()
        suiteName = "com.slaynode.test.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
    }
    
    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        super.tearDown()
    }
    
    func testDefaultRefreshInterval() {
        let store = PreferencesStore(defaults: testDefaults)
        XCTAssertEqual(store.refreshInterval, 5.0, accuracy: 0.01)
    }
    
    func testSetRefreshInterval() {
        let store = PreferencesStore(defaults: testDefaults)
        store.setRefreshInterval(10.0)
        XCTAssertEqual(store.refreshInterval, 10.0, accuracy: 0.01)
    }
    
    func testRefreshIntervalClampsToMinimum() {
        let store = PreferencesStore(defaults: testDefaults)
        store.setRefreshInterval(1.0)
        XCTAssertEqual(store.refreshInterval, 2.0, accuracy: 0.01)
    }
    
    func testRefreshIntervalClampsToMaximum() {
        let store = PreferencesStore(defaults: testDefaults)
        store.setRefreshInterval(60.0)
        XCTAssertEqual(store.refreshInterval, 30.0, accuracy: 0.01)
    }
    
    func testRefreshIntervalPersists() {
        let store1 = PreferencesStore(defaults: testDefaults)
        store1.setRefreshInterval(15.0)
        
        let store2 = PreferencesStore(defaults: testDefaults)
        XCTAssertEqual(store2.refreshInterval, 15.0, accuracy: 0.01)
    }
    
    func testIgnoresSmallChanges() {
        let store = PreferencesStore(defaults: testDefaults)
        store.setRefreshInterval(10.0)
        store.setRefreshInterval(10.005)
        XCTAssertEqual(store.refreshInterval, 10.0, accuracy: 0.01)
    }
}
#endif
