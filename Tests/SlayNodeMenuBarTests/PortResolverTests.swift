#if canImport(XCTest)
import XCTest
@testable import SlayNodeMenuBar

final class PortResolverTests: XCTestCase {

    func testParseLsofOutputExtractsListeningPorts() {
        let output = """
        COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        node    12345 user   22u  IPv4 0x0   0t0      TCP  127.0.0.1:3000 (LISTEN)
        node    12345 user   23u  IPv6 0x0   0t0      TCP  [::1]:5173 (LISTEN)
        node    12345 user   24u  IPv4 0x0   0t0      TCP  *:3000 (LISTEN)
        node    22345 user   25u  IPv4 0x0   0t0      TCP  0.0.0.0:8080 (LISTEN)
        """

        XCTAssertEqual(PortResolver.parseLsofOutput(output), [12345: [3000, 5173], 22345: [8080]])
    }
    
    func testResolvesEmptyPidListReturnsEmptyDict() async {
        let resolver = PortResolver()
        let result = await resolver.resolvePorts(for: [])
        XCTAssertTrue(result.isEmpty)
    }
    
    func testResolvesInvalidPidReturnsEmptyDict() async {
        let resolver = PortResolver()
        let result = await resolver.resolvePorts(for: [-1])
        XCTAssertTrue(result.isEmpty)
    }
    
    func testResolvesNonExistentPidReturnsEmptyDict() async {
        let resolver = PortResolver()
        let result = await resolver.resolvePorts(for: [999999])
        XCTAssertTrue(result.isEmpty)
    }
    
    func testResolverHandlesMultiplePids() async {
        let resolver = PortResolver()
        let requestedPids: [Int32] = [1, 2, 3]
        let result = await resolver.resolvePorts(for: requestedPids)

        XCTAssertTrue(result.keys.allSatisfy { requestedPids.contains($0) })
    }
}
#endif
