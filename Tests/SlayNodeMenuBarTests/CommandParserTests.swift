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
        let descriptor = CommandParser.descriptor(from: ["node_modules/.bin/next", "dev"])
        XCTAssertEqual(descriptor.name, "Next.js")
        XCTAssertEqual(descriptor.details, "Läge: DEV")
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
#endif
