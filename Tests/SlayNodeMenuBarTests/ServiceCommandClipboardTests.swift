#if canImport(XCTest)
import XCTest
@testable import SlayNodeMenuBar

final class ServiceCommandClipboardTests: XCTestCase {
    func testServiceCommandCopyTextRedactsSensitiveValues() {
        let copied = serviceCommandCopyText(
            "curl -H 'Authorization: Bearer super-secret' 'https://example.test?token=abc123'"
        )

        XCTAssertFalse(copied.contains("super-secret"))
        XCTAssertFalse(copied.contains("abc123"))
        XCTAssertTrue(copied.contains("Authorization:"))
        XCTAssertTrue(copied.contains("token=***"))
    }
}
#endif
