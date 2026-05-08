#if canImport(XCTest)
import XCTest
@testable import SlayNodeMenuBar

final class ServiceProvidersTests: XCTestCase {
    func testSanitizerRedactsDatabaseUrlAssignments() {
        let command = "DATABASE_URL=postgres://user:password@localhost/app REDIS_URL=redis://localhost:6379 npm run dev"
        let redacted = ServiceSanitizer.redactSecrets(in: command)

        XCTAssertFalse(redacted.contains("password"))
        XCTAssertFalse(redacted.contains("redis://"))
        XCTAssertEqual(redacted, "DATABASE_URL=*** REDIS_URL=*** npm run dev")
    }

    func testSanitizerRedactsSecretQueryParameters() {
        let command = "node server.js https://example.test/callback?token=secret&safe=1&api_key=abc#done"
        let redacted = ServiceSanitizer.redactSecrets(in: command)

        XCTAssertFalse(redacted.contains("secret"))
        XCTAssertFalse(redacted.contains("abc"))
        XCTAssertTrue(redacted.contains("safe=1"))
        XCTAssertTrue(redacted.contains("#done"))
    }

    func testSanitizerRedactsAccessTokenQueryParameter() {
        let command = "node server.js https://example.test/callback?access_token=secret&state=ok"
        let redacted = ServiceSanitizer.redactSecrets(in: command)

        XCTAssertFalse(redacted.contains("access_token=secret"))
        XCTAssertEqual(redacted, "node server.js https://example.test/callback?access_token=***&state=ok")
    }

    func testSanitizerRedactsURLCredentials() {
        let command = "node server.js postgres://user:password@localhost:5432/app"
        let redacted = ServiceSanitizer.redactSecrets(in: command)

        XCTAssertFalse(redacted.contains("user:password"))
        XCTAssertEqual(redacted, "node server.js postgres://***@localhost:5432/app")
    }

    func testSanitizerRedactsAuthorizationAssignments() {
        let command = "AUTHORIZATION='Bearer secret-token' node server.js --proxy-authorization proxy-secret"
        let redacted = ServiceSanitizer.redactSecrets(in: command)

        XCTAssertFalse(redacted.contains("secret-token"))
        XCTAssertFalse(redacted.contains("proxy-secret"))
        XCTAssertEqual(redacted, "AUTHORIZATION=*** node server.js --proxy-authorization ***")
    }

    func testSanitizerRedactsPrefixedApiKeyAssignments() {
        let command = "OPENAI_API_KEY=sk-secret ANTHROPIC_API_KEY=claude-secret npm run dev"
        let redacted = ServiceSanitizer.redactSecrets(in: command)

        XCTAssertFalse(redacted.contains("sk-secret"))
        XCTAssertFalse(redacted.contains("claude-secret"))
        XCTAssertEqual(redacted, "OPENAI_API_KEY=*** ANTHROPIC_API_KEY=*** npm run dev")
    }

    func testSanitizerRedactsInlineSecretFlags() {
        let command = "node server.js --password=secret --client-secret=client-secret"
        let redacted = ServiceSanitizer.redactSecrets(in: command)

        XCTAssertFalse(redacted.contains("=secret"))
        XCTAssertFalse(redacted.contains("=client-secret"))
        XCTAssertEqual(redacted, "node server.js --password=*** --client-secret=***")
    }

    func testMakeProcessServiceRedactsSensitiveArguments() {
        let process = NodeProcess(
            pid: 4242,
            ppid: 1,
            executable: "node",
            command: "node server.js --api-key secret-value --token super-secret",
            arguments: ["server.js", "--api-key", "secret-value", "--token", "super-secret"],
            ports: [3000],
            uptime: 12,
            startTime: Date(),
            workingDirectory: "/Users/test/app",
            descriptor: ServerDescriptor(
                name: "Node.js",
                displayName: "Node.js",
                category: .backend,
                runtime: "Node.js",
                packageManager: nil,
                script: nil,
                details: "Mode: DEV",
                portHints: [3000]
            ),
            commandHash: 1
        )

        let service = ServiceHeuristics.makeProcessService(
            from: process,
            ports: [3000],
            workingDirectory: "/Users/test/app"
        )

        XCTAssertNotNil(service)
        XCTAssertFalse(service?.command?.contains("secret-value") ?? true)
        XCTAssertFalse(service?.command?.contains("super-secret") ?? true)
        XCTAssertTrue(service?.command?.contains("***") ?? false)
    }

    func testRuntimeProcessWithoutServiceSignalsIsFilteredOut() {
        let process = NodeProcess(
            pid: 2121,
            ppid: 1,
            executable: "sleep",
            command: "sleep 2",
            arguments: ["2"],
            ports: [],
            uptime: 2,
            startTime: Date(),
            workingDirectory: nil,
            descriptor: ServerDescriptor(
                name: "sleep",
                displayName: "sleep",
                category: .runtime,
                runtime: nil,
                packageManager: nil,
                script: nil,
                details: nil,
                portHints: []
            ),
            commandHash: 2
        )

        let service = ServiceHeuristics.makeProcessService(from: process, ports: [], workingDirectory: nil)
        XCTAssertNil(service)
    }

    func testToolingDaemonIsFilteredOut() {
        let process = NodeProcess(
            pid: 3131,
            ppid: 1,
            executable: "node",
            command: "/opt/homebrew/bin/node /Users/test/project/node_modules/typescript/lib/tsserver.js --useNodeIpc",
            arguments: ["/Users/test/project/node_modules/typescript/lib/tsserver.js", "--useNodeIpc"],
            ports: [],
            uptime: 20,
            startTime: Date(),
            workingDirectory: "/Users/test/project",
            descriptor: ServerDescriptor(
                name: "Node.js",
                displayName: "Node.js",
                category: .runtime,
                runtime: "Node.js",
                packageManager: nil,
                script: nil,
                details: nil,
                portHints: []
            ),
            commandHash: 3
        )

        let service = ServiceHeuristics.makeProcessService(
            from: process,
            ports: [],
            workingDirectory: "/Users/test/project"
        )

        XCTAssertNil(service)
    }

    func testAgentBrowserToolingDaemonIsFilteredOutEvenWithPort() {
        let process = NodeProcess(
            pid: 4141,
            ppid: 1,
            executable: "/opt/homebrew/Cellar/agent-browser/0.26.0/libexec/lib/node_modules/agent-browser/bin/agent-browser-darwin-arm64",
            command: "/opt/homebrew/Cellar/agent-browser/0.26.0/libexec/lib/node_modules/agent-browser/bin/agent-browser-darwin-arm64 --port=53754",
            arguments: ["--port=53754"],
            ports: [53754],
            uptime: 20,
            startTime: Date(),
            workingDirectory: nil,
            descriptor: ServerDescriptor(
                name: "Node.js",
                displayName: "Node.js",
                category: .runtime,
                runtime: "Node.js",
                packageManager: nil,
                script: nil,
                details: nil,
                portHints: [53754]
            ),
            commandHash: 4
        )

        let service = ServiceHeuristics.makeProcessService(
            from: process,
            ports: [53754],
            workingDirectory: nil
        )

        XCTAssertNil(service)
    }

    func testWorkspaceIdentityNormalizesNodeModulesPaths() {
        let workspace = ServiceHeuristics.workspaceIdentity(
            from: "/Volumes/ExtraDisk/Dev/julia-live/frontend/node_modules/.bin"
        )

        XCTAssertEqual(workspace?.name, "frontend")
        XCTAssertEqual(workspace?.rootPath, "/Volumes/ExtraDisk/Dev/julia-live/frontend")
    }

    func testWorkspaceIdentityNormalizesPackageDirectories() {
        let workspace = ServiceHeuristics.workspaceIdentity(
            from: "/Volumes/ExtraDisk/Dev/julia-live/backend/node_modules/vitest"
        )

        XCTAssertEqual(workspace?.name, "backend")
        XCTAssertEqual(workspace?.rootPath, "/Volumes/ExtraDisk/Dev/julia-live/backend")
    }

    func testDockerPortParserExpandsHostPortRanges() {
        let ports = ServiceHeuristics.parseDockerPorts(
            "0.0.0.0:3000-3002->3000-3002/tcp, :::8080->80/tcp"
        )

        XCTAssertEqual(ports, [3000, 3001, 3002, 8080])
    }

    func testRedisContainerIsClassifiedAsCache() {
        let kind = ServiceHeuristics.classifyContainer(name: "redis", image: "redis:7")

        XCTAssertEqual(kind, .cache)
    }

    func testPostgresContainerRemainsDatabase() {
        let kind = ServiceHeuristics.classifyContainer(name: "db", image: "postgres:16")

        XCTAssertEqual(kind, .database)
    }

    func testDockerServiceWithoutBindMountDoesNotOfferOpenWorkspace() async {
        let mock = MockShellExecutor()
        mock.responses["/usr/bin/env docker ps --format {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}"] = (
            0,
            "abc123\tweb\tnginx:latest\t0.0.0.0:8080->80/tcp\tUp 2 minutes"
        )
        mock.responses["/usr/bin/env docker inspect --format {{json .Mounts}}@@{{.LogPath}} abc123"] = (
            0,
            "[]@@/tmp/web.log"
        )
        let provider = DockerServiceProvider(shell: mock)

        let batch = await provider.discoverServices()

        XCTAssertEqual(batch.services.count, 1)
        XCTAssertFalse(batch.services.first?.supports(.openWorkspace) ?? true)
    }

    func testDockerDiscoveryIgnoresFailedPsOutput() async {
        let mock = MockShellExecutor()
        mock.responses["/usr/bin/env docker ps --format {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}"] = (
            1,
            "abc123\tweb\tnginx:latest\t0.0.0.0:8080->80/tcp\tUp 2 minutes"
        )
        let provider = DockerServiceProvider(shell: mock)

        let batch = await provider.discoverServices()

        XCTAssertTrue(batch.services.isEmpty)
    }

    func testBrewServiceWithoutFileDoesNotOfferRevealConfig() async {
        let mock = MockShellExecutor()
        mock.responses["/usr/bin/env brew services list --json"] = (
            0,
            #"[{"name":"postgresql@16","status":"started","user":"tyko","file":null}]"#
        )
        let provider = BrewServiceProvider(shell: mock)

        let batch = await provider.discoverServices()

        XCTAssertEqual(batch.services.count, 1)
        XCTAssertFalse(batch.services.first?.supports(.revealConfig) ?? true)
    }
}
#endif
