#if canImport(XCTest)
import XCTest
@testable import SlayNodeMenuBar

final class ProcessDiscoveryTests: XCTestCase {
    func testParseEtimeSupportsCommonPsFormats() {
        XCTAssertEqual(ProcessDiscovery.parseEtime("00:00"), 0)
        XCTAssertEqual(ProcessDiscovery.parseEtime("42"), 42)
        XCTAssertEqual(ProcessDiscovery.parseEtime("15:42"), 942)
        XCTAssertEqual(ProcessDiscovery.parseEtime("2:15:42"), 8_142)
        XCTAssertEqual(ProcessDiscovery.parseEtime("1-02:03:04"), 93_784)
    }

    func testParseProcessLineBuildsNodeProcess() throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let process = try XCTUnwrap(
            ProcessDiscovery.parseProcessLine(
                "12345     1 00:15 node /Users/test/app/server.js --port=3000",
                now: now
            )
        )

        XCTAssertEqual(process.pid, 12_345)
        XCTAssertEqual(process.ppid, 1)
        XCTAssertEqual(process.executable, "node")
        XCTAssertEqual(process.ports, [3000])
        XCTAssertEqual(process.uptime, 15)
        XCTAssertEqual(process.startTime, now.addingTimeInterval(-15))
    }

    func testParseProcessLineKeepsFreshlyStartedProcess() throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let process = try XCTUnwrap(
            ProcessDiscovery.parseProcessLine(
                "12345     1 00:00 node /Users/test/app/server.js --port=3000",
                now: now
            )
        )

        XCTAssertEqual(process.uptime, 0)
        XCTAssertEqual(process.startTime, now)
    }

    func testParseProcessLineRejectsNegativeElapsedTime() {
        let process = ProcessDiscovery.parseProcessLine(
            "12345     1 -1 node /Users/test/app/server.js --port=3000"
        )

        XCTAssertNil(process)
    }

    func testParseProcessLineRejectsInvalidElapsedClockFields() {
        let invalidRows = [
            "12345     1 00:75 node /Users/test/app/server.js --port=3000",
            "12345     1 1:99:00 node /Users/test/app/server.js --port=3000",
            "12345     1 1-24:00:00 node /Users/test/app/server.js --port=3000"
        ]

        for row in invalidRows {
            XCTAssertNil(ProcessDiscovery.parseProcessLine(row), row)
        }
    }

    func testParseProcessLineRejectsNonIntegerElapsedClockFields() {
        let invalidRows = [
            "12345     1 1.5 node /Users/test/app/server.js --port=3000",
            "12345     1 00:1.5 node /Users/test/app/server.js --port=3000",
            "12345     1 1-02:03:4.5 node /Users/test/app/server.js --port=3000"
        ]

        for row in invalidRows {
            XCTAssertNil(ProcessDiscovery.parseProcessLine(row), row)
        }
    }

    func testParseWorkingDirectoriesKeepsFirstPathForPid() {
        let output = """
        p100
        fcwd
        n/Users/test/frontend
        p100
        fcwd
        n/Users/test/other
        p101
        fcwd
        n/Users/test/api
        """

        let directories = ProcessDiscovery.parseWorkingDirectories(from: output)

        XCTAssertEqual(directories[100], "/Users/test/frontend")
        XCTAssertEqual(directories[101], "/Users/test/api")
    }

    #if DEBUG
    func testDiscoveryAndProcessProviderUsePromotedProcessShape() async throws {
        let psOutput = """
        20000     1 00:15 /usr/local/bin/npm run dev
        20001 20000 00:14 node /Users/test/frontend/node_modules/.bin/vite
        """
        let cwdOutput = """
        p20000
        fcwd
        n/Users/test/frontend
        p20001
        fcwd
        n/Users/test/frontend
        """
        let mock = MockShellExecutor()
        mock.responses["\(Constants.Path.ps) -axo pid=,ppid=,etime=,command="] = (0, psOutput)
        mock.responses["\(Constants.Path.lsof) -a -d cwd -Fn -p 20000,20001"] = (0, cwdOutput)
        mock.defaultResponse = (0, "")

        let discovery = ProcessDiscovery(shell: mock)
        let processes = await discovery.discoverProcesses()

        XCTAssertEqual(processes.count, 1)
        let process = try XCTUnwrap(processes.first)
        XCTAssertEqual(process.pid, 20_000)
        XCTAssertEqual(process.descriptor.displayName, "Vite")
        XCTAssertEqual(process.descriptor.packageManager, "npm")
        XCTAssertEqual(process.descriptor.script, "dev")
        XCTAssertEqual(process.workingDirectory, "/Users/test/frontend")

        let provider = ProcessServiceProvider(shell: mock)
        let batch = await provider.discoverServices()
        let service = try XCTUnwrap(batch.services.first)

        XCTAssertEqual(batch.services.count, 1)
        XCTAssertEqual(service.id, "process:20000")
        XCTAssertEqual(service.name, "frontend")
        XCTAssertEqual(service.kind, .app)
    }

    func testDiscoveryFiltersAgentBrowserToolingEvenWhenPortIsPresent() async throws {
        let psOutput = """
        21000     1 00:20 /opt/homebrew/Cellar/agent-browser/0.26.0/libexec/lib/node_modules/agent-browser/bin/agent-browser-darwin-arm64 --port=53754
        21010     1 00:20 /usr/local/bin/npm run dev
        21011 21010 00:19 node /Users/test/frontend/node_modules/.bin/vite --port=5173
        """
        let cwdOutput = """
        p21010
        fcwd
        n/Users/test/frontend
        p21011
        fcwd
        n/Users/test/frontend
        """
        let mock = MockShellExecutor()
        mock.responses["\(Constants.Path.ps) -axo pid=,ppid=,etime=,command="] = (0, psOutput)
        mock.responses["\(Constants.Path.lsof) -a -d cwd -Fn -p 21010,21011"] = (0, cwdOutput)
        mock.defaultResponse = (0, "")

        let discovery = ProcessDiscovery(shell: mock)
        let processes = await discovery.discoverProcesses()

        XCTAssertEqual(processes.map(\.pid), [21_010])
        XCTAssertEqual(processes.first?.descriptor.displayName, "Vite")
        XCTAssertEqual(processes.first?.ports, [5_173])
        XCTAssertEqual(processes.first?.workingDirectory, "/Users/test/frontend")
    }
    #endif
}
#endif
