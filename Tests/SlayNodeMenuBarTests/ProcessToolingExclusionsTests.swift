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

    func testExcludesLegacyOpenAgentCommandFragments() {
        XCTAssertTrue(
            ProcessToolingExclusions.isExcluded(
                executable: "/opt/homebrew/bin/node",
                command: "/opt/homebrew/lib/node_modules/oh-my-openagent/dist/index.js run"
            )
        )

        XCTAssertTrue(
            ProcessToolingExclusions.isExcluded(
                executable: "/opt/homebrew/bin/node",
                command: "/opt/homebrew/lib/node_modules/oh-my-opencode/dist/index.js run"
            )
        )
    }

    func testExcludesSharedToolingDaemonFragments() {
        for fixture in knownToolingProcessFixtures {
            XCTAssertTrue(
                ProcessToolingExclusions.isExcluded(
                    executable: fixture.executable,
                    command: fixture.command
                ),
                fixture.command
            )
        }
    }

    func testExcludesOMXRuntimeCommandFragments() {
        XCTAssertTrue(
            ProcessToolingExclusions.isExcluded(
                executable: "/opt/homebrew/bin/node",
                command: "/Users/test/.omx/team/daily/worktrees/worker-1/node_modules/.bin/tsx run.ts"
            )
        )

        XCTAssertTrue(
            ProcessToolingExclusions.isExcluded(
                executable: "/opt/homebrew/bin/node",
                command: "/Users/test/.omx/state/cache/process-snapshot.js"
            )
        )
    }

    func testExcludesCodexWorktreeRuntimeCommandFragments() {
        XCTAssertTrue(
            ProcessToolingExclusions.isExcluded(
                executable: "/opt/homebrew/bin/node",
                command: "/Users/test/.codex/worktrees/abcd/repo/node_modules/.bin/tsx src/dev.ts"
            )
        )
    }

    func testExcludesCodexNativeHookExecutableName() {
        XCTAssertTrue(
            ProcessToolingExclusions.isExcluded(
                executable: "/tmp/codex-native-hook",
                command: "/tmp/codex-native-hook --event post-command"
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
