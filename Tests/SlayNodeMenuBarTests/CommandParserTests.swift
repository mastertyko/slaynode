#if canImport(XCTest)
import XCTest
@testable import SlayNodeMenuBar

final class CommandParserTests: XCTestCase {
    func testTokenizeRespectsQuotesAndEscapes() {
        let command = "node ./server.js --name=\"My App\" --flag 'other value'"
        let tokens = CommandParser.tokenize(command)

        // Expected tokens: ["node", "./server.js", "--name=My App", "--flag", "other value"]
        XCTAssertEqual(tokens.count, 5)
        XCTAssertEqual(tokens[0], "node")
        XCTAssertEqual(tokens[1], "./server.js")
        XCTAssertEqual(tokens[2], "--name=My App")
        XCTAssertEqual(tokens[3], "--flag")
        XCTAssertEqual(tokens[4], "other value")
    }

    func testTokenizePreservesTrailingEscape() {
        let tokens = CommandParser.tokenize("node server.js path\\\\")

        XCTAssertEqual(tokens, ["node", "server.js", "path\\"])
    }

    func testDescriptorDetectsNextJS() {
        let tokens = ["node_modules/.bin/next", "dev"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: nil)
        let descriptor = CommandParser.descriptor(from: context)
        XCTAssertEqual(descriptor.displayName, "Next.js")
        XCTAssertEqual(descriptor.details, "Mode: DEV")
        XCTAssertEqual(descriptor.runtime, "Node.js")
        XCTAssertEqual(descriptor.category, .webFramework)
        XCTAssertEqual(descriptor.portHints, [3000])
    }

    func testNextClassifierDoesNotMatchSubstring() {
        let tokens = ["node", "/Users/demo/app/nextdoor-server.js"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: nil)
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertNotEqual(descriptor.displayName, "Next.js")
        XCTAssertEqual(descriptor.displayName, "nextdoor-server.js")
    }

    func testInferPortsFromFlagsAndUrls() {
        let tokens = ["node", "server.js", "--port=3000", "--inspect=127.0.0.1:9229"]
        let ports = CommandParser.inferPorts(from: tokens)
        XCTAssertEqual(ports, [3000, 9229])
    }

    func testInferPortsDeduplicatesAndSortsValues() {
        let tokens = ["node", "server.js", "--port=3000", "-p", "3000", "--inspect=127.0.0.1:9229"]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [3000, 9229])
    }

    func testInferPortsFromSeparateFlagArguments() {
        let tokens = ["vite", "--port", "4173", "--inspect", "127.0.0.1:9230"]
        let ports = CommandParser.inferPorts(from: tokens)
        XCTAssertEqual(ports, [4173, 9230])
    }

    func testInferPortsFromDefaultInspectFlags() {
        let tokens = ["node", "--inspect", "server.js", "--inspect-brk"]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [9_229])
    }

    func testInferPortsFromEnvironmentAssignments() {
        let tokens = ["PORT=3000", "VITE_PORT=127.0.0.1:5173", "REPORT=1234", "npm", "run", "dev"]
        let ports = CommandParser.inferPorts(from: tokens)
        XCTAssertEqual(ports, [3000, 5173])
    }

    func testInferPortsFromSocketAddressFlags() {
        let tokens = [
            "deno",
            "serve",
            "--listen",
            "0.0.0.0:8000",
            "--addr=127.0.0.1:9000",
            "--listen-address",
            "localhost:9100",
            "--socket=127.0.0.1:9200"
        ]
        let ports = CommandParser.inferPorts(from: tokens)
        XCTAssertEqual(ports, [8000, 9000, 9100, 9200])
    }

    func testInferPortsFromIPv6HostPortToken() {
        let tokens = ["node", "server.js", "http://[::1]:5173"]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [5173])
    }

    func testInferPortsFromBareHostPortWithSuffix() {
        let tokens = ["node", "server.js", "localhost:5173/api", "0.0.0.0:3000,"]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [3000, 5173])
    }

    func testInferPortsDoesNotTreatBareIPv6AddressAsPort() {
        let ports = CommandParser.inferPorts(from: ["node", "server.js", "[::1]"])

        XCTAssertTrue(ports.isEmpty)
    }

    func testInferPortsIgnoresBareNumericArguments() {
        let tokens = ["sleep", "2", "--retries", "28"]
        let ports = CommandParser.inferPorts(from: tokens)
        XCTAssertTrue(ports.isEmpty)
    }

    func testInferPortsIgnoresOutOfRangeValues() {
        let tokens = ["node", "server.js", "--port=0", "--inspect=127.0.0.1:65536"]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertTrue(ports.isEmpty)
    }

    func testInferWorkingDirectoryFromFlag() {
        let path = CommandParser.inferWorkingDirectory(from: ["--cwd", "~/Projects/demo"])
        XCTAssertTrue(path?.hasSuffix("Projects/demo") ?? false)
    }

    func testInferWorkingDirectoryFromProjectRootFlags() {
        let rootPath = CommandParser.inferWorkingDirectory(from: ["vite", "--root", "~/Projects/frontend"])
        let inlinePath = CommandParser.inferWorkingDirectory(from: ["next", "--workspace=/tmp/slaynode-web"])

        XCTAssertTrue(rootPath?.hasSuffix("Projects/frontend") ?? false)
        XCTAssertEqual(inlinePath, "/tmp/slaynode-web")
    }

    func testInferWorkingDirectoryFromPrefixFlag() {
        let path = CommandParser.inferWorkingDirectory(from: ["npm", "--prefix", "~/Projects/app", "run", "dev"])

        XCTAssertTrue(path?.hasSuffix("Projects/app") ?? false)
    }

    func testInferWorkingDirectoryFromShortCFlag() {
        let path = CommandParser.inferWorkingDirectory(from: ["pnpm", "-C", "~/Projects/api", "dev"])

        XCTAssertTrue(path?.hasSuffix("Projects/api") ?? false)
    }
}
extension CommandParserTests {
    func testPackageManagerWrapperAddsMetadata() {
        let tokens = ["pnpm", "exec", "next", "dev"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: "/Users/test/app")
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertEqual(descriptor.displayName, "Next.js")
        XCTAssertEqual(descriptor.packageManager, "pnpm")
        XCTAssertEqual(descriptor.script, "next")
        XCTAssertEqual(descriptor.details, "Mode: DEV")
        XCTAssertEqual(descriptor.category, .webFramework)
        XCTAssertEqual(descriptor.portHints, [3000])

        let summaries = descriptor.summaryDetails()
        XCTAssertTrue(summaries.contains("pnpm next"))
        XCTAssertTrue(summaries.contains("Node.js"))
        XCTAssertTrue(summaries.contains(ServerDescriptor.Category.webFramework.displayName))
    }

    func testPackageManagerWrapperSkipsWorkspaceFlagsBeforeRun() {
        let tokens = ["npm", "--workspace", "web", "run", "dev"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: "/Users/test/app")
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertEqual(descriptor.packageManager, "npm")
        XCTAssertEqual(descriptor.script, "dev")
    }

    func testPackageManagerWrapperSkipsDirectoryFlagsBeforeRun() {
        let tokens = ["pnpm", "--dir", "frontend", "run", "dev"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: "/Users/test/app")
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertEqual(descriptor.packageManager, "pnpm")
        XCTAssertEqual(descriptor.script, "dev")
    }

    func testPackageManagerWrapperSkipsShortDirectoryFlagBeforeRun() {
        let tokens = ["pnpm", "-C", "frontend", "run", "dev"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: "/Users/test/app")
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertEqual(descriptor.packageManager, "pnpm")
        XCTAssertEqual(descriptor.script, "dev")
    }

    func testYarnWorkspaceScriptNameIsParsed() {
        let tokens = ["yarn", "workspace", "web", "dev"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: "/Users/test/app")
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertEqual(descriptor.packageManager, "yarn")
        XCTAssertEqual(descriptor.script, "dev")
    }

    func testPackageManagerWrapperSkipsWorkspaceFlagsAfterRun() {
        let tokens = ["npm", "run", "--workspace", "web", "dev"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: "/Users/test/app")
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertEqual(descriptor.packageManager, "npm")
        XCTAssertEqual(descriptor.script, "dev")
    }

    func testViteCommandIsDetected() {
        let tokens = ["node", "/Users/demo/node_modules/.bin/vite", "preview", "--port", "4173"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: nil)
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertEqual(descriptor.displayName, "Vite")
        XCTAssertEqual(descriptor.details, "Mode: PREVIEW")
        XCTAssertEqual(descriptor.category, .bundler)
        XCTAssertEqual(descriptor.portHints, [5173])
    }

    func testWebpackServeCommandIsDetected() {
        let tokens = ["webpack", "serve", "--mode", "development"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: nil)
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertEqual(descriptor.displayName, "Webpack Dev Server")
        XCTAssertEqual(descriptor.category, .bundler)
        XCTAssertEqual(descriptor.portHints, [8080, 3000])
    }

    func testViteClassifierDoesNotMatchInviteSubstring() {
        let tokens = ["node", "/Users/demo/app/invite-server.js"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: nil)
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertNotEqual(descriptor.displayName, "Vite")
        XCTAssertEqual(descriptor.displayName, "invite-server.js")
    }

    func testNodemonClassifiedAsTool() {
        let tokens = ["nodemon", "server.js"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: nil)
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertEqual(descriptor.displayName, "Nodemon")
        XCTAssertEqual(descriptor.category, .utility)
        XCTAssertEqual(descriptor.portHints, [3000, 4000])
    }

    func testHonoCommandIsDetectedAsBackend() {
        let tokens = ["node", "src/hono-server.ts"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: nil)
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertEqual(descriptor.displayName, "Hono")
        XCTAssertEqual(descriptor.category, .backend)
        XCTAssertEqual(descriptor.portHints, [3000])
    }

    func testAdonisCommandIsDetectedAsBackend() {
        let tokens = ["node", "ace", "serve", "--watch", "@adonisjs/core"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: nil)
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertEqual(descriptor.displayName, "AdonisJS")
        XCTAssertEqual(descriptor.category, .backend)
        XCTAssertEqual(descriptor.portHints, [3333])
    }
}
#endif
