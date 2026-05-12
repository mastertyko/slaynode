#if canImport(XCTest)
import XCTest
@testable import SlayNodeMenuBar

final class ProcessToolingExclusionsTests: XCTestCase {
    func testExcludesKnownCommandFragments() {
        XCTAssertTrue(
            ProcessToolingExclusions.isExcluded(
                executable: "/opt/homebrew/bin/node",
                command: "/opt/homebrew/lib/node_modules/agent-browser/bin/agent-browser-darwin-arm64 --port=53754"
            )
        )
    }

    func testExcludesKnownExecutableName() {
        XCTAssertTrue(
            ProcessToolingExclusions.isExcluded(
                executable: "/usr/local/bin/tsserver",
                command: "/usr/local/bin/tsserver --stdio"
            )
        )
    }

    func testExcludesKnownExecutableNameFragment() {
        XCTAssertTrue(
            ProcessToolingExclusions.isExcluded(
                executable: "/tmp/agent-browser-darwin-arm64",
                command: "/tmp/agent-browser-darwin-arm64 --headless"
            )
        )
    }

    func testDoesNotExcludeTypicalDevelopmentServiceCommand() {
        XCTAssertFalse(
            ProcessToolingExclusions.isExcluded(
                executable: "node",
                command: "node /Users/test/app/node_modules/.bin/vite --port=5173"
            )
        )
    }
}
#endif
