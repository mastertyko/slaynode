#if canImport(XCTest)
import XCTest
@testable import SlayNodeMenuBar

final class CommandParserTests: XCTestCase {
    func testTokenizeRespectsQuotesAndEscapes() {
        let command = "node ./server.js --name=\"My App\" --flag 'other value'"
        let tokens = CommandParser.tokenize(command)

        XCTAssertEqual(tokens.count, 6)
        XCTAssertEqual(tokens[0], "node")
        XCTAssertEqual(tokens[1], "./server.js")
        XCTAssertEqual(tokens[2], "--name=My App")
        XCTAssertEqual(tokens[5], "other value")
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

    func testInferPortsFromFlagsAndUrls() {
        let tokens = ["node", "server.js", "--port=3000", "--inspect=127.0.0.1:9229"]
        let ports = CommandParser.inferPorts(from: tokens)
        XCTAssertEqual(ports, [3000, 9229])
    }

    func testInferWorkingDirectoryFromFlag() {
        let path = CommandParser.inferWorkingDirectory(from: ["--cwd", "~/Projects/demo"])
        XCTAssertTrue(path?.hasSuffix("Projects/demo") ?? false)
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

    func testViteCommandIsDetected() {
        let tokens = ["node", "/Users/demo/node_modules/.bin/vite", "preview", "--port", "4173"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: nil)
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertEqual(descriptor.displayName, "Vite")
        XCTAssertEqual(descriptor.details, "Mode: PREVIEW")
        XCTAssertEqual(descriptor.category, .bundler)
        XCTAssertEqual(descriptor.portHints, [5173])
    }

    func testNodemonClassifiedAsTool() {
        let tokens = ["nodemon", "server.js"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: nil)
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertEqual(descriptor.displayName, "Nodemon")
        XCTAssertEqual(descriptor.category, .utility)
        XCTAssertEqual(descriptor.portHints, [3000, 4000])
    }
}
#endif
