#if canImport(XCTest)
import XCTest
@testable import SlayNodeMenuBar

final class ProcessGroupKillerTests: XCTestCase {
    
    func testTerminateInvalidPidThrowsError() async {
        let killer = ProcessGroupKiller()
        
        do {
            try await killer.terminateGroup(pid: -1)
            XCTFail("Should have thrown invalidPid error")
        } catch ProcessGroupTerminationError.invalidPid {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testTerminateZeroPidThrowsError() async {
        let killer = ProcessGroupKiller()
        
        do {
            try await killer.terminateGroup(pid: 0)
            XCTFail("Should have thrown invalidPid error")
        } catch ProcessGroupTerminationError.invalidPid {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testTerminateNonExistentPidThrowsError() async {
        let killer = ProcessGroupKiller()
        
        do {
            try await killer.terminateGroup(pid: 999999)
            XCTFail("Should have thrown invalidPid error")
        } catch ProcessGroupTerminationError.invalidPid {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testErrorDescriptions() {
        XCTAssertEqual(ProcessGroupTerminationError.invalidPid.errorDescription, "Invalid process ID.")
        XCTAssertEqual(ProcessGroupTerminationError.permissionDenied.errorDescription, "Permission denied to stop the process.")
        XCTAssertEqual(ProcessGroupTerminationError.terminationFailed(1).errorDescription, "Could not stop the process (errno: 1).")
        XCTAssertEqual(ProcessGroupTerminationError.processGroupNotFound.errorDescription, "Could not find process group.")
    }

    func testDescendantPIDsReturnsDeepestChildrenFirst() throws {
        let descendants = ProcessGroupKiller.descendantPIDs(
            parentPid: 100,
            childrenByParent: [
                100: [101, 102],
                101: [201],
                201: [301],
                102: [202]
            ]
        )

        XCTAssertEqual(Set(descendants), [101, 102, 201, 202, 301])
        let index301 = try XCTUnwrap(descendants.firstIndex(of: 301))
        let index201 = try XCTUnwrap(descendants.firstIndex(of: 201))
        let index101 = try XCTUnwrap(descendants.firstIndex(of: 101))
        let index202 = try XCTUnwrap(descendants.firstIndex(of: 202))
        let index102 = try XCTUnwrap(descendants.firstIndex(of: 102))

        XCTAssertLessThan(index301, index201)
        XCTAssertLessThan(index201, index101)
        XCTAssertLessThan(index202, index102)
    }

    func testDescendantPIDsHandlesCycles() {
        let descendants = ProcessGroupKiller.descendantPIDs(
            parentPid: 100,
            childrenByParent: [
                100: [101],
                101: [100, 102]
            ]
        )

        XCTAssertEqual(descendants, [102, 101])
    }

    func testDescendantPIDsSortsSiblingsDeterministically() {
        let descendants = ProcessGroupKiller.descendantPIDs(
            parentPid: 100,
            childrenByParent: [
                100: [105, 101],
                101: [204, 203],
                105: [302, 301]
            ]
        )

        XCTAssertEqual(descendants, [203, 204, 101, 301, 302, 105])
    }
}
#endif
