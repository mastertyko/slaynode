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

    func testServiceCommandCopyTextRedactsAuthorizationSchemeWithoutSpaceAfterColon() {
        let copied = serviceCommandCopyText(
            "curl --header Authorization:Bearer bearer-secret --header Proxy-Authorization:Basic proxy-secret https://example.test"
        )

        XCTAssertFalse(copied.contains("bearer-secret"))
        XCTAssertFalse(copied.contains("proxy-secret"))
        XCTAssertTrue(copied.contains("Authorization: ***"))
        XCTAssertTrue(copied.contains("Proxy-Authorization: ***"))
    }

    func testServiceCommandCopyTextRedactsSplitCookieApiKeyAndProxyHeaders() {
        let copied = serviceCommandCopyText(
            "curl --header Cookie: sid=abc123 --header Set-Cookie: refresh=xyz --header X-Api-Key: top-secret --header Proxy-Authorization: Basic proxy-secret --header X-Trace: trace-123 https://example.test"
        )

        XCTAssertFalse(copied.contains("abc123"))
        XCTAssertFalse(copied.contains("xyz"))
        XCTAssertFalse(copied.contains("top-secret"))
        XCTAssertFalse(copied.contains("proxy-secret"))
        XCTAssertTrue(copied.contains("Cookie: ***"))
        XCTAssertTrue(copied.contains("Set-Cookie: ***"))
        XCTAssertTrue(copied.contains("X-Api-Key: ***"))
        XCTAssertTrue(copied.contains("Proxy-Authorization: ***"))
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

    func testServiceCommandCopyTextRedactsUrlFragmentSecrets() {
        let copied = serviceCommandCopyText(
            "node server.js 'https://example.test/callback?state=ok&token=query-secret#access_token=fragment-secret&tab=home'"
        )

        XCTAssertFalse(copied.contains("query-secret"))
        XCTAssertFalse(copied.contains("fragment-secret"))
        XCTAssertTrue(copied.contains("state=ok"))
        XCTAssertTrue(copied.contains("tab=home"))
        XCTAssertTrue(copied.contains("token=***"))
        XCTAssertTrue(copied.contains("access_token=***"))
    }

    func testServiceCommandCopyTextRedactsIDTokenParameters() {
        let copied = serviceCommandCopyText(
            "node server.js 'https://example.test/callback?id_token=query-secret#id_token=fragment-secret&tab=home'"
        )

        XCTAssertFalse(copied.contains("query-secret"))
        XCTAssertFalse(copied.contains("fragment-secret"))
        XCTAssertTrue(copied.contains("id_token=***"))
        XCTAssertTrue(copied.contains("tab=home"))
    }

    func testServiceCommandCopyTextRedactsCredentialEnvironmentNames() {
        let copied = serviceCommandCopyText(
            "AWS_SECRET_ACCESS_KEY=aws-secret GOOGLE_APPLICATION_CREDENTIALS=/tmp/creds.json npm run dev --secret-key local-secret"
        )

        XCTAssertFalse(copied.contains("aws-secret"))
        XCTAssertFalse(copied.contains("/tmp/creds.json"))
        XCTAssertFalse(copied.contains("local-secret"))
        XCTAssertTrue(copied.contains("AWS_SECRET_ACCESS_KEY=***"))
        XCTAssertTrue(copied.contains("GOOGLE_APPLICATION_CREDENTIALS=***"))
        XCTAssertTrue(copied.contains("--secret-key ***"))
    }

    func testServiceCommandCopyTextDoesNotConsumeNextFlagWhenSecretValueIsMissing() {
        let copied = serviceCommandCopyText(
            "node server.js --password --port 3000 --token"
        )

        XCTAssertTrue(copied.contains("--password --port 3000"))
        XCTAssertTrue(copied.hasSuffix("--token"))
        XCTAssertFalse(copied.contains("--password *** 3000"))
    }

    func testServiceCommandCopyTextRedactsURLValuesAfterSensitiveFlags() {
        let copied = serviceCommandCopyText(
            "node server.js --database-url postgres://demo:db-secret@localhost:5432/app --sentry-dsn https://public:dsn-secret@example.test/1"
        )

        XCTAssertFalse(copied.contains("db-secret"))
        XCTAssertFalse(copied.contains("dsn-secret"))
        XCTAssertEqual(copied, "node server.js --database-url *** --sentry-dsn ***")
    }
}
#endif
