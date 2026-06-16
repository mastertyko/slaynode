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

    func testSanitizerRedactsConnectionStringAssignments() {
        let command = "MONGODB_URL=mongodb://user:password@localhost/app --connection-string postgres://secret@localhost/app"
        let redacted = ServiceSanitizer.redactSecrets(in: command)

        XCTAssertFalse(redacted.contains("password"))
        XCTAssertFalse(redacted.contains("postgres://secret"))
        XCTAssertEqual(redacted, "MONGODB_URL=*** --connection-string ***")
    }

    func testSanitizerRedactsAuthorizationHeaders() {
        let command = "node server.js --header 'Authorization: Bearer secret-token' --header 'X-Safe: value'"
        let redacted = ServiceSanitizer.redactSecrets(in: command)

        XCTAssertFalse(redacted.contains("secret-token"))
        XCTAssertTrue(redacted.contains("Authorization: ***"))
        XCTAssertTrue(redacted.contains("X-Safe: value"))
    }

    func testSanitizerRedactsSplitAuthorizationHeaderValue() {
        let command = "node server.js --header Authorization: secret-token --header X-Safe: value"
        let redacted = ServiceSanitizer.redactSecrets(in: command)

        XCTAssertFalse(redacted.contains("secret-token"))
        XCTAssertTrue(redacted.contains("Authorization: ***"))
        XCTAssertTrue(redacted.contains("X-Safe:"))
        XCTAssertTrue(redacted.contains("value"))
    }

    func testSanitizerRedactsSplitSensitiveHeaderValues() {
        let command = """
        node server.js --header Cookie: sid=abc123 --header Set-Cookie: refresh=xyz --header X-Api-Key: top-secret --header Proxy-Authorization: Basic proxy-secret --header X-Safe: value
        """
        let redacted = ServiceSanitizer.redactSecrets(in: command)

        XCTAssertFalse(redacted.contains("abc123"))
        XCTAssertFalse(redacted.contains("xyz"))
        XCTAssertFalse(redacted.contains("top-secret"))
        XCTAssertFalse(redacted.contains("proxy-secret"))
        XCTAssertTrue(redacted.contains("Cookie: ***"))
        XCTAssertTrue(redacted.contains("Set-Cookie: ***"))
        XCTAssertTrue(redacted.contains("X-Api-Key: ***"))
        XCTAssertTrue(redacted.contains("Proxy-Authorization: ***"))
        XCTAssertTrue(redacted.contains("X-Safe:"))
        XCTAssertTrue(redacted.contains("value"))
    }

    func testSanitizerRedactsCookieAndApiKeyHeaders() {
        let command = "node server.js --header 'Cookie: sid=abc123' --header 'Set-Cookie: refresh=xyz' --header 'X-Api-Key: top-secret' --header 'X-Safe: value'"
        let redacted = ServiceSanitizer.redactSecrets(in: command)

        XCTAssertFalse(redacted.contains("abc123"))
        XCTAssertFalse(redacted.contains("xyz"))
        XCTAssertFalse(redacted.contains("top-secret"))
        XCTAssertTrue(redacted.contains("Cookie: ***"))
        XCTAssertTrue(redacted.contains("Set-Cookie: ***"))
        XCTAssertTrue(redacted.contains("X-Api-Key: ***"))
        XCTAssertTrue(redacted.contains("X-Safe: value"))
    }

    func testSanitizerRedactsProxyAuthorizationHeader() {
        let command = "node server.js --header 'Proxy-Authorization: Basic abc123' --header 'X-Safe: value'"
        let redacted = ServiceSanitizer.redactSecrets(in: command)

        XCTAssertFalse(redacted.contains("abc123"))
        XCTAssertTrue(redacted.contains("Proxy-Authorization: ***"))
        XCTAssertTrue(redacted.contains("X-Safe: value"))
    }

    func testSanitizerRedactsNpmAuthTokenArguments() {
        let command = "npm config set //registry.npmjs.org/:_authToken npm-secret"
        let redacted = ServiceSanitizer.redactSecrets(in: command)

        XCTAssertFalse(redacted.contains("npm-secret"))
        XCTAssertEqual(redacted, "npm config set //registry.npmjs.org/:_authToken ***")
    }

    func testSanitizerRedactsInlineSecretFlags() {
        let command = "node server.js --password=secret --client-secret=client-secret"
        let redacted = ServiceSanitizer.redactSecrets(in: command)

        XCTAssertFalse(redacted.contains("=secret"))
        XCTAssertFalse(redacted.contains("=client-secret"))
        XCTAssertEqual(redacted, "node server.js --password=*** --client-secret=***")
    }

    func testSanitizerRemovesKnownSecretFixturesFromOutput() {
        let fixtures: [(command: String, leaked: [String])] = [
            (
                "node api.js --token abc123 --password hunter2",
                ["abc123", "hunter2"]
            ),
            (
                "curl https://user:pw@example.test/path?api_key=sk-live-123&safe=1",
                ["user:pw", "sk-live-123"]
            ),
            (
                "npm config set //registry.npmjs.org/:_authToken npm-secret-value",
                ["npm-secret-value"]
            ),
            (
                "node server.js --header 'Authorization: Bearer top-secret-token'",
                ["top-secret-token"]
            )
        ]

        for fixture in fixtures {
            let redacted = ServiceSanitizer.redactSecrets(in: fixture.command)
            for leakedValue in fixture.leaked {
                XCTAssertFalse(
                    redacted.contains(leakedValue),
                    "Expected sanitizer to remove secret fixture value '\(leakedValue)' from: \(redacted)"
                )
            }
            XCTAssertTrue(redacted.contains("***"), "Expected sanitized output marker in: \(redacted)")
        }
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

    func testRuntimeInferenceAvoidsBundleSubstringMatch() {
        let process = NodeProcess(
            pid: 4343,
            ppid: 1,
            executable: "bundle",
            command: "bundle exec puma -p 3000",
            arguments: ["exec", "puma", "-p", "3000"],
            ports: [3000],
            uptime: 12,
            startTime: Date(),
            workingDirectory: "/Users/test/app",
            descriptor: ServerDescriptor(
                name: "bundle",
                displayName: "bundle",
                category: .runtime,
                runtime: nil,
                packageManager: nil,
                script: nil,
                details: nil,
                portHints: []
            ),
            commandHash: 9
        )

        let service = ServiceHeuristics.makeProcessService(
            from: process,
            ports: [3000],
            workingDirectory: "/Users/test/app"
        )

        XCTAssertEqual(service?.runtime, "Ruby")
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

    func testWorkspaceIdentityNormalizesTerminalNodeModulesPath() {
        let workspace = ServiceHeuristics.workspaceIdentity(
            from: "/Volumes/ExtraDisk/Dev/julia-live/frontend/node_modules"
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

    func testDependenciesAreSortedDeterministically() {
        let workspace = WorkspaceIdentity(id: "workspace:/demo", name: "demo", rootPath: "/tmp/demo")
        let services = [
            makeDependencyService(id: "process:worker", kind: .worker, workspace: workspace),
            makeDependencyService(id: "process:redis", kind: .cache, workspace: workspace),
            makeDependencyService(id: "process:api", kind: .api, workspace: workspace),
            makeDependencyService(id: "process:postgres", kind: .database, workspace: workspace)
        ]

        let dependencies = ServiceHeuristics.dependencies(for: services)

        XCTAssertEqual(
            dependencies.map(\.id),
            [
                "process:api->process:postgres",
                "process:api->process:redis",
                "process:worker->process:postgres",
                "process:worker->process:redis"
            ]
        )
    }

    func testDockerPortParserExpandsHostPortRanges() {
        let ports = ServiceHeuristics.parseDockerPorts(
            "0.0.0.0:3000-3002->3000-3002/tcp, :::8080->80/tcp"
        )

        XCTAssertEqual(ports, [3000, 3001, 3002, 8080])
    }

    func testDockerPortParserIgnoresInvalidHostPorts() {
        let ports = ServiceHeuristics.parseDockerPorts(
            "0.0.0.0:0->3000/tcp, 0.0.0.0:65536->3000/tcp, :::8080->80/tcp"
        )

        XCTAssertEqual(ports, [8080])
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

    func testDockerServiceFileBindMountDoesNotOfferOpenWorkspace() async throws {
        let mock = MockShellExecutor()
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let socketPath = root.appendingPathComponent("docker.sock")
        try Data().write(to: socketPath)

        mock.responses["/usr/bin/env docker ps --format {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}"] = (
            0,
            "abc123\tweb\tnginx:latest\t0.0.0.0:8080->80/tcp\tUp 2 minutes"
        )
        mock.responses["/usr/bin/env docker inspect --format {{json .Mounts}}@@{{.LogPath}} abc123"] = (
            0,
            #" [{"Type":"bind","Source":"\#(socketPath.path)"}] @@/tmp/web.log "#
        )
        let provider = DockerServiceProvider(shell: mock)

        let service = await provider.discoverServices().services.first

        XCTAssertFalse(service?.supports(.openWorkspace) ?? true)
        XCTAssertEqual(service?.configPath, socketPath.path)
    }

    func testDockerServicePrefersDirectoryBindMountForWorkspace() async throws {
        let mock = MockShellExecutor()
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let workspacePath = root.appendingPathComponent("demo-app")
        try FileManager.default.createDirectory(at: workspacePath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let socketPath = root.appendingPathComponent("docker.sock")
        try Data().write(to: socketPath)

        mock.responses["/usr/bin/env docker ps --format {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}"] = (
            0,
            "abc123\tweb\tnginx:latest\t0.0.0.0:8080->80/tcp\tUp 2 minutes"
        )
        mock.responses["/usr/bin/env docker inspect --format {{json .Mounts}}@@{{.LogPath}} abc123"] = (
            0,
            #" [{"Type":"bind","Source":"\#(socketPath.path)"},{"Type":"bind","Source":"\#(workspacePath.path)"}] @@/tmp/web.log "#
        )
        let provider = DockerServiceProvider(shell: mock)
        let discoveredServices = await provider.discoverServices().services

        let service = try XCTUnwrap(discoveredServices.first)

        XCTAssertTrue(service.supports(.openWorkspace))
        XCTAssertEqual(service.workspace?.rootPath, workspacePath.path)
        XCTAssertEqual(service.configPath, workspacePath.path)
    }

    func testDockerServiceOffersForceStopBeforeOrchestration() async {
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

        XCTAssertEqual(batch.services.first?.availableActions, [.stop, .forceStop, .restart, .openLogs])
    }

    func testPausedAndStartingDockerContainersNeedAttention() async {
        let mock = MockShellExecutor()
        mock.responses["/usr/bin/env docker ps --format {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}"] = (
            0,
            """
            abc123\tpaused-web\tnginx:latest\t0.0.0.0:8080->80/tcp\tUp 2 minutes (Paused)
            def456\tstarting-api\tnginx:latest\t0.0.0.0:3000->80/tcp\tUp 10 seconds (health: starting)
            """
        )
        mock.responses["/usr/bin/env docker inspect --format {{json .Mounts}}@@{{.LogPath}} abc123"] = (0, "[]@@")
        mock.responses["/usr/bin/env docker inspect --format {{json .Mounts}}@@{{.LogPath}} def456"] = (0, "[]@@")
        let provider = DockerServiceProvider(shell: mock)

        let services = await provider.discoverServices().services

        XCTAssertEqual(services.map(\.status), [.degraded, .degraded])
        XCTAssertEqual(services.map(\.health), [.watch, .watch])
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

    func testDockerDiscoverySkipsMalformedRows() async {
        let mock = MockShellExecutor()
        mock.responses["/usr/bin/env docker ps --format {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}"] = (
            0,
            """
            abc123\t\tnginx:latest\t0.0.0.0:8080->80/tcp\tUp 2 minutes
            def456\tapi\t\t0.0.0.0:3000->3000/tcp\tUp 2 minutes
            ghi789\tworker\tredis:7\t\tUp 2 minutes
            """
        )
        mock.responses["/usr/bin/env docker inspect --format {{json .Mounts}}@@{{.LogPath}} ghi789"] = (
            0,
            "[]@@"
        )
        let provider = DockerServiceProvider(shell: mock)

        let batch = await provider.discoverServices()

        XCTAssertEqual(batch.services.map(\.name), ["worker"])
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

    func testBrewServiceWithBlankFileDoesNotOfferRevealConfig() async {
        let mock = MockShellExecutor()
        mock.responses["/usr/bin/env brew services list --json"] = (
            0,
            #"[{"name":"postgresql@16","status":"started","user":"tyko","file":"   "}]"#
        )
        let provider = BrewServiceProvider(shell: mock)

        let service = await provider.discoverServices().services.first

        XCTAssertFalse(service?.supports(.revealConfig) ?? true)
        XCTAssertNil(service?.configPath)
    }

    func testBrewServiceWithMissingFileDoesNotOfferRevealConfig() async {
        let mock = MockShellExecutor()
        mock.responses["/usr/bin/env brew services list --json"] = (
            0,
            #"[{"name":"postgresql@16","status":"started","user":"tyko","file":"/tmp/slaynode-missing.plist"}]"#
        )
        let provider = BrewServiceProvider(shell: mock)

        let service = await provider.discoverServices().services.first

        XCTAssertFalse(service?.supports(.revealConfig) ?? true)
        XCTAssertNil(service?.configPath)
    }

    func testBrewServiceWithExistingFileOffersRevealConfig() async throws {
        let mock = MockShellExecutor()
        let plistURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("slaynode-\(UUID().uuidString).plist")
        try Data("plist".utf8).write(to: plistURL)
        defer { try? FileManager.default.removeItem(at: plistURL) }

        mock.responses["/usr/bin/env brew services list --json"] = (
            0,
            #"[{"name":"postgresql@16","status":"started","user":"tyko","file":"\#(plistURL.path)"}]"#
        )
        let provider = BrewServiceProvider(shell: mock)
        let discoveredServices = await provider.discoverServices().services

        let service = try XCTUnwrap(discoveredServices.first)

        XCTAssertTrue(service.supports(.revealConfig))
        XCTAssertEqual(service.configPath, plistURL.path)
    }

    func testBrewServiceWithNonPlistFileDoesNotOfferRevealConfig() async throws {
        let mock = MockShellExecutor()
        let textURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("slaynode-\(UUID().uuidString).txt")
        try Data("not a plist".utf8).write(to: textURL)
        defer { try? FileManager.default.removeItem(at: textURL) }

        mock.responses["/usr/bin/env brew services list --json"] = (
            0,
            #"[{"name":"postgresql@16","status":"started","user":"tyko","file":"\#(textURL.path)"}]"#
        )
        let provider = BrewServiceProvider(shell: mock)

        let service = await provider.discoverServices().services.first

        XCTAssertFalse(service?.supports(.revealConfig) ?? true)
        XCTAssertNil(service?.configPath)
    }

    func testBrewServiceWithDirectoryPathDoesNotOfferRevealConfig() async throws {
        let mock = MockShellExecutor()
        let directoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("slaynode-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        mock.responses["/usr/bin/env brew services list --json"] = (
            0,
            #"[{"name":"postgresql@16","status":"started","user":"tyko","file":"\#(directoryURL.path)"}]"#
        )
        let provider = BrewServiceProvider(shell: mock)

        let service = await provider.discoverServices().services.first

        XCTAssertFalse(service?.supports(.revealConfig) ?? true)
        XCTAssertNil(service?.configPath)
    }

    func testBrewServiceWithUnreadableFileDoesNotOfferRevealConfig() async throws {
        let mock = MockShellExecutor()
        let plistURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("slaynode-\(UUID().uuidString).plist")
        try Data("plist".utf8).write(to: plistURL)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plistURL.path)
            try? FileManager.default.removeItem(at: plistURL)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: plistURL.path)

        mock.responses["/usr/bin/env brew services list --json"] = (
            0,
            #"[{"name":"postgresql@16","status":"started","user":"tyko","file":"\#(plistURL.path)"}]"#
        )
        let provider = BrewServiceProvider(shell: mock)

        let service = await provider.discoverServices().services.first

        XCTAssertFalse(service?.supports(.revealConfig) ?? true)
        XCTAssertNil(service?.configPath)
    }

    func testBrewErrorStatusWithCodeIsCritical() async {
        let mock = MockShellExecutor()
        mock.responses["/usr/bin/env brew services list --json"] = (
            0,
            #"[{"name":"redis","status":"error 256","user":"tyko","file":"/tmp/redis.plist"}]"#
        )
        let provider = BrewServiceProvider(shell: mock)

        let service = await provider.discoverServices().services.first

        XCTAssertEqual(service?.status, .degraded)
        XCTAssertEqual(service?.health, .critical)
    }
}

private extension ServiceProvidersTests {
    func makeDependencyService(id: String, kind: ServiceKind, workspace: WorkspaceIdentity) -> ManagedService {
        ManagedService(
            id: id,
            name: id,
            kind: kind,
            status: .running,
            health: .healthy,
            source: .process(pid: 1, command: "npm run dev"),
            workspace: workspace,
            ports: [],
            runtime: "Node.js",
            summary: "fixture",
            command: "npm run dev",
            configPath: nil,
            logPath: nil,
            tags: [],
            availableActions: [.stop],
            startedAt: nil,
            lastSeenAt: Date()
        )
    }
}
#endif
