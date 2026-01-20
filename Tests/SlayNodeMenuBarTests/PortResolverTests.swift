#if canImport(XCTest)
import XCTest
@testable import SlayNodeMenuBar

final class PortResolverTests: XCTestCase {
    
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
        let result = await resolver.resolvePorts(for: [1, 2, 3])
        XCTAssertNotNil(result)
    }
}
#endif
