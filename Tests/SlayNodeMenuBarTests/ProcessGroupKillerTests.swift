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
        XCTAssertNotNil(ProcessGroupTerminationError.invalidPid.errorDescription)
        XCTAssertNotNil(ProcessGroupTerminationError.permissionDenied.errorDescription)
        XCTAssertNotNil(ProcessGroupTerminationError.terminationFailed(1).errorDescription)
        XCTAssertNotNil(ProcessGroupTerminationError.processGroupNotFound.errorDescription)
    }
}
#endif
