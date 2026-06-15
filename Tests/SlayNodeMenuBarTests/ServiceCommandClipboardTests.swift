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

    func testServiceCommandCopyTextRedactsCookieApiKeyAndProxyHeaders() {
        let copied = serviceCommandCopyText(
            "curl --header 'Cookie: sid=abc123' --header 'Set-Cookie: refresh=xyz' --header 'X-Api-Key: top-secret' --header 'Proxy-Authorization: Basic proxy-secret' https://example.test"
        )

        XCTAssertFalse(copied.contains("abc123"))
        XCTAssertFalse(copied.contains("xyz"))
        XCTAssertFalse(copied.contains("top-secret"))
        XCTAssertFalse(copied.contains("proxy-secret"))
        XCTAssertTrue(copied.contains("Cookie: ***"))
        XCTAssertTrue(copied.contains("Set-Cookie: ***"))
        XCTAssertTrue(copied.contains("X-Api-Key: ***"))
        XCTAssertTrue(copied.contains("Proxy-Authorization: ***"))
    }

    func testServiceCommandCopyTextRedactsSplitHeaderValues() {
        let copied = serviceCommandCopyText(
            "curl --header Authorization: bearer-secret --header X-Trace: trace-123 https://example.test"
        )

        XCTAssertFalse(copied.contains("bearer-secret"))
        XCTAssertTrue(copied.contains("Authorization: ***"))
        XCTAssertTrue(copied.contains("X-Trace:"))
        XCTAssertTrue(copied.contains("trace-123"))
    }

    func testServiceCommandCopyTextRedactsUrlCredentials() {
        let copied = serviceCommandCopyText(
            "node server.js postgres://demo:super-secret@localhost:5432/app"
        )

        XCTAssertFalse(copied.contains("demo:super-secret"))
        XCTAssertEqual(copied, "node server.js postgres://***@localhost:5432/app")
    }
}
#endif
