#if canImport(XCTest)
import XCTest
@testable import SlayNodeMenuBar

final class PortResolverTests: XCTestCase {

    func testNormalizedPIDsFiltersInvalidAndSortsUniqueValues() {
        XCTAssertEqual(PortResolver.normalizedPIDs([3, -1, 2, 3, 0, 1]), [1, 2, 3])
    }

    func testPidBatchesNormalizeAndChunkValues() {
        XCTAssertEqual(
            PortResolver.pidBatches(for: [4, 2, 2, -1, 3, 1], batchSize: 2),
            [[1, 2], [3, 4]]
        )
        XCTAssertEqual(PortResolver.pidBatches(for: [], batchSize: 3), [])
    }

    func testParseLsofOutputExtractsListeningPorts() {
        let output = """
        COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        node    12345 user   22u  IPv4 0x0   0t0      TCP  127.0.0.1:3000 (LISTEN)
        node    12345 user   23u  IPv6 0x0   0t0      TCP  [::1]:5173 (LISTEN)
        node    12345 user   24u  IPv4 0x0   0t0      TCP  *:3000 (LISTEN)
        node    22345 user   25u  IPv4 0x0   0t0      TCP  0.0.0.0:8080 (LISTEN)
        """

        XCTAssertEqual(PortResolver.parseLsofOutput(output), [12345: [3000, 5173], 22345: [8080]])
    }

    func testParseLsofOutputIgnoresInvalidPortBounds() {
        let output = """
        COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        node    12345 user   22u  IPv4 0x0   0t0      TCP  127.0.0.1:0 (LISTEN)
        node    12345 user   23u  IPv4 0x0   0t0      TCP  127.0.0.1:65536 (LISTEN)
        node    12345 user   24u  IPv4 0x0   0t0      TCP  *:3000 (LISTEN)
        """

        XCTAssertEqual(PortResolver.parseLsofOutput(output), [12345: [3000]])
    }

    func testParseLsofOutputResolvesNamedTcpServices() {
        let output = """
        COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        node    12345 user   22u  IPv4 0x0   0t0      TCP  *:ssh (LISTEN)
        node    12345 user   23u  IPv6 0x0   0t0      TCP  [::]:https (LISTEN)
        node    22345 user   24u  IPv4 0x0   0t0      TCP  localhost:http (LISTEN)
        """

        XCTAssertEqual(
            PortResolver.parseLsofOutput(output),
            [12345: [22, 443], 22345: [80]]
        )
    }

    func testParseLsofOutputHandlesFieldFormatRows() {
        let output = """
        p12345
        n*:3000
        n[::1]:5173
        p22345
        nlocalhost:http-alt
        """

        XCTAssertEqual(
            PortResolver.parseLsofOutput(output),
            [12345: [3000, 5173], 22345: [8080]]
        )
    }

    func testExtractPortHandlesArrowSuffixAndWhitespace() {
        XCTAssertEqual(PortResolver.extractPort(from: "127.0.0.1:3000->127.0.0.1:52341"), 3000)
        XCTAssertEqual(PortResolver.extractPort(from: "  *:8080  "), 8080)
    }

    func testExtractPortHandlesIPv6WildcardAndInvalidValues() {
        XCTAssertEqual(PortResolver.extractPort(from: "[::]:5173"), 5173)
        XCTAssertNotNil(PortResolver.extractPort(from: "*:http-alt"))
        XCTAssertEqual(PortResolver.extractPort(from: "localhost:https"), 443)
        XCTAssertNil(PortResolver.extractPort(from: "[::1]"))
        XCTAssertNil(PortResolver.extractPort(from: "localhost:not-a-real-service"))
    }
    
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
        let requestedPids: [Int32] = [1, 2, 3]
        let result = await resolver.resolvePorts(for: requestedPids)

        XCTAssertTrue(result.keys.allSatisfy { requestedPids.contains($0) })
    }

    #if DEBUG
    func testResolvePortsMergesResultsAcrossPidBatches() async {
        let mock = MockShellExecutor()
        mock.responses["\(Constants.Path.lsof) -Pan -p 101,102 -iTCP -sTCP:LISTEN"] = (
            0,
            """
            COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
            node      101 user   22u  IPv4 0x0   0t0      TCP  *:3000 (LISTEN)
            node      102 user   23u  IPv4 0x0   0t0      TCP  *:4173 (LISTEN)
            """
        )
        mock.responses["\(Constants.Path.lsof) -Pan -p 103 -iTCP -sTCP:LISTEN"] = (
            0,
            """
            COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
            node      103 user   24u  IPv4 0x0   0t0      TCP  *:8080 (LISTEN)
            """
        )
        mock.defaultResponse = (1, "")

        let resolver = PortResolver(shell: mock, pidQueryBatchSize: 2)
        let result = await resolver.resolvePorts(for: [103, 101, 102])

        XCTAssertEqual(result, [101: [3000], 102: [4173], 103: [8080]])
    }

    func testResolvePortsRetriesNonZeroBatchWithUnparseableOutputOnceBeforeSucceeding() async {
        let mock = SequencedShellExecutor()
        mock.enqueue(
            key: "\(Constants.Path.lsof) -Pan -p 101 -iTCP -sTCP:LISTEN",
            result: .success((1, "lsof: unexpected permission warning"))
        )
        mock.enqueue(
            key: "\(Constants.Path.lsof) -Pan -p 101 -iTCP -sTCP:LISTEN",
            result: .success((
                0,
                """
                COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
                node      101 user   22u  IPv4 0x0   0t0      TCP  *:3000 (LISTEN)
                """
            ))
        )

        let resolver = PortResolver(shell: mock, pidQueryBatchSize: 1)
        let result = await resolver.resolvePorts(for: [101])

        XCTAssertEqual(result, [101: [3000]])
    }

    func testResolvePortsRetriesThrownBatchErrorOnceBeforeSucceeding() async {
        let mock = SequencedShellExecutor()
        mock.enqueue(
            key: "\(Constants.Path.lsof) -Pan -p 101 -iTCP -sTCP:LISTEN",
            result: .failure(TestShellError.transient)
        )
        mock.enqueue(
            key: "\(Constants.Path.lsof) -Pan -p 101 -iTCP -sTCP:LISTEN",
            result: .success((
                0,
                """
                COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
                node      101 user   22u  IPv4 0x0   0t0      TCP  *:3000 (LISTEN)
                """
            ))
        )

        let resolver = PortResolver(shell: mock, pidQueryBatchSize: 1)
        let result = await resolver.resolvePorts(for: [101])

        XCTAssertEqual(result, [101: [3000]])
    }

    func testResolvePortsAcceptsPartialResultsFromNonZeroLsofExit() async {
        let mock = SequencedShellExecutor()
        mock.enqueue(
            key: "\(Constants.Path.lsof) -Pan -p 101,102 -iTCP -sTCP:LISTEN",
            result: .success((
                1,
                """
                COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
                node      101 user   22u  IPv4 0x0   0t0      TCP  *:3000 (LISTEN)
                """
            ))
        )

        let resolver = PortResolver(shell: mock, pidQueryBatchSize: 2)
        let result = await resolver.resolvePorts(for: [101, 102])

        XCTAssertEqual(result, [101: [3000]])
    }

    func testResolvePortsTreatsEmptyNonZeroLsofExitAsNoListenersWithoutRetry() async {
        let mock = CountingShellExecutor(result: (1, ""))
        let resolver = PortResolver(shell: mock, pidQueryBatchSize: 1)

        let result = await resolver.resolvePorts(for: [101])
        let invocationCount = await mock.invocationCount()

        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(invocationCount, 1)
    }
    #endif
}

#if DEBUG
private enum TestShellError: Error {
    case transient
}

private final class SequencedShellExecutor: ShellExecuting, @unchecked Sendable {
    private var responses: [String: [Result<(status: Int32, output: String), Error>]] = [:]

    func enqueue(
        key: String,
        result: Result<(status: Int32, output: String), Error>
    ) {
        responses[key, default: []].append(result)
    }

    func run(
        _ launchPath: String,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> (status: Int32, output: String) {
        let key = "\(launchPath) \(arguments.joined(separator: " "))"
        guard var queued = responses[key], !queued.isEmpty else {
            return (0, "")
        }

        let next = queued.removeFirst()
        responses[key] = queued
        return try next.get()
    }
}

private actor CountingShellState {
    var count = 0

    func recordInvocation() {
        count += 1
    }
}

private final class CountingShellExecutor: ShellExecuting, @unchecked Sendable {
    private let result: (status: Int32, output: String)
    private let state = CountingShellState()

    init(result: (status: Int32, output: String)) {
        self.result = result
    }

    func run(
        _ launchPath: String,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> (status: Int32, output: String) {
        await state.recordInvocation()
        return result
    }

    func invocationCount() async -> Int {
        await state.count
    }
}
#endif
#endif
