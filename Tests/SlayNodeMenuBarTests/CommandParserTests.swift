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

    func testFirstScriptTokenDetectsTypeScriptEntrypointsOutsideSrcFolders() {
        let tokens = ["node", "/Users/demo/app/scripts/dev-server.ts", "--watch"]

        XCTAssertEqual(
            CommandParser.firstScriptToken(from: tokens),
            "/Users/demo/app/scripts/dev-server.ts"
        )
    }

    func testFirstScriptTokenDetectsExtensionlessServerEntrypoints() {
        let tokens = ["node", "/Users/demo/app/scripts/dev-server", "--watch"]

        XCTAssertEqual(
            CommandParser.firstScriptToken(from: tokens),
            "/Users/demo/app/scripts/dev-server"
        )
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

    func testNodeRuntimeDoesNotMatchBundleScriptName() {
        let tokens = ["node", "/Users/demo/app/bundle.js"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: nil)
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertEqual(descriptor.displayName, "bundle.js")
        XCTAssertEqual(descriptor.runtime, "Node.js")
    }

    func testInferPortsFromFlagsAndUrls() {
        let tokens = ["node", "server.js", "--port=3000", "--inspect=127.0.0.1:9229"]
        let ports = CommandParser.inferPorts(from: tokens)
        XCTAssertEqual(ports, [3000, 9229])
    }

    func testInferPortsFromInlineFlagsWithQuotedValues() {
        let tokens = ["node", "server.js", "--port=\"3000\"", "--inspect='127.0.0.1:9229'"]
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

    func testInferPortsFromSeparateFlagURLArguments() {
        let tokens = [
            "deno",
            "serve",
            "--listen",
            "http://127.0.0.1:8080/app",
            "--inspect",
            "ws://localhost:9230/debug"
        ]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [8080, 9230])
    }

    func testInferPortsFromQuotedFlagArguments() {
        let tokens = ["vite", "--port", "\"4173\"", "--inspect", "'127.0.0.1:9230'"]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [4173, 9230])
    }

    func testInferPortsFromDefaultInspectFlags() {
        let tokens = ["node", "--inspect", "server.js", "--inspect-brk", "--inspect-wait"]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [9_229])
    }

    func testInferPortsFromInlineInspectHostWithoutPortFallsBackToDefault() {
        let tokens = ["node", "--inspect=0.0.0.0", "--inspect-brk=localhost", "--inspect-wait=::1", "server.js"]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [9_229])
    }

    func testInferPortsFromInspectWaitFlagWithExplicitPort() {
        let tokens = ["node", "--inspect-wait=127.0.0.1:9330", "server.js"]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [9_330])
    }

    func testInferPortsFromInlineInspectIPv6HostWithoutPortFallsBackToDefault() {
        let tokens = ["node", "--inspect=::1", "--inspect-brk=[::1]", "server.js"]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [9_229])
    }

    func testInferPortsFromInlineInspectIPv6HostPortValue() {
        let tokens = ["node", "--inspect=[::1]:9230", "server.js"]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [9_230])
    }

    func testInferPortsFromInlineInspectIPv4MappedIPv6HostPortValue() {
        let tokens = ["node", "--inspect=[::ffff:127.0.0.1]:9230", "server.js"]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [9_230])
    }

    func testInferPortsFromInspectPortFlag() {
        let tokens = ["node", "--inspect-port", "9230", "--inspect-port=9231", "server.js"]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [9230, 9231])
    }

    func testInferPortsFromEnvironmentAssignments() {
        let tokens = ["PORT=3000", "VITE_PORT=127.0.0.1:5173", "REPORT=1234", "npm", "run", "dev"]
        let ports = CommandParser.inferPorts(from: tokens)
        XCTAssertEqual(ports, [3000, 5173])
    }

    func testInferPortsFromEnvironmentAssignmentsWithTrailingPunctuation() {
        let tokens = ["PORT=3000,", "WEB_PORT=4173;", "npm", "run", "dev"]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [3000, 4173])
    }

    func testInferPortsFromEnvironmentAssignmentsWithQuotedValues() {
        let tokens = [
            "PORT=\"3000\"",
            "WEB_PORT='4173,'",
            "NODE_DEBUG_PORT=\"127.0.0.1:9229\"",
            "npm",
            "run",
            "dev"
        ]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [3000, 4173, 9229])
    }

    func testInferPortsFromEnvironmentAssignmentsWithURLValues() {
        let tokens = [
            "PORT=http://localhost:3000",
            "WEB_PORT=\"https://127.0.0.1:4173/app\"",
            "API_PORT='http://0.0.0.0:8080,'",
            "npm",
            "run",
            "dev"
        ]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [3000, 4173, 8080])
    }

    func testInferPortsFromURLLikeEnvironmentAssignments() {
        let tokens = [
            "PUBLIC_URL=http://localhost:3000/app",
            "API_ORIGIN=https://127.0.0.1:8443",
            "GRAPHQL_ENDPOINT='http://0.0.0.0:5050/graphql'",
            "STATIC_URL=https://example.com/assets",
            "npm",
            "run",
            "dev"
        ]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [3000, 5050, 8443])
    }

    func testInferPortsFromURLLikeEnvironmentAssignmentsWithShellDefaults() {
        let tokens = [
            "PUBLIC_URL=${PUBLIC_URL:-http://localhost:3000/app}",
            "API_ORIGIN=${API_ORIGIN:=https://127.0.0.1:8443}",
            "GRAPHQL_ENDPOINT=${GRAPHQL_ENDPOINT-'http://0.0.0.0:5050/graphql'}",
            "STATIC_URL=${STATIC_URL:-https://example.com/assets}",
            "npm",
            "run",
            "dev"
        ]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [3000, 5050, 8443])
    }

    func testInferPortsFromEnvironmentAssignmentsWithShellDefaults() {
        let tokens = [
            "PORT=${PORT:-3000}",
            "WEB_PORT=${WEB_PORT-4173}",
            "APP_PORT=${APP_PORT:-\"8080\"}",
            "ALT_PORT=${ALT_PORT:=9229}",
            "FALLBACK_PORT=${FALLBACK_PORT=9333}",
            "URL_PORT=${URL_PORT:-http://localhost:5050}",
            "GRAPH_PORT=${GRAPH_PORT:=https://127.0.0.1:6060/graphql}",
            "npm",
            "run",
            "dev"
        ]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [3000, 4173, 5050, 6060, 8080, 9229, 9333])
    }

    func testInferPortsFromEnvironmentAssignmentsWithURLShellDefaults() {
        let tokens = [
            "PORT=${PORT:-http://localhost:3000}",
            "API_PORT=${API_PORT:=https://127.0.0.1:8443/graphql}",
            "WEB_PORT=${WEB_PORT-\"http://0.0.0.0:4173\"}",
            "npm",
            "run",
            "dev"
        ]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [3000, 4173, 8443])
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

    func testInferPortsFromJVMSystemProperties() {
        let tokens = [
            "java",
            "-Dhttp.port=8080",
            "-Djetty.http.port=127.0.0.1:9000",
            "-Dmanagement.server.port=9001",
            "-Dgrpc.threads=32",
            "-jar",
            "app.jar"
        ]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [8080, 9000, 9001])
    }

    func testInferPortsFromURLJVMSystemProperties() {
        let tokens = [
            "java",
            "-Dserver.port=http://localhost:8080",
            "-Dmanagement.server.port=https://127.0.0.1:9001/actuator",
            "-Ddebug.port=${DEBUG_PORT:-9229}",
            "-Dapi.port=${API_PORT:=http://0.0.0.0:4173}",
            "-jar",
            "app.jar"
        ]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [4173, 8080, 9001, 9229])
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

    func testInferPortsFromWildcardHostToken() {
        let tokens = ["bun", "run", "dev", "--host", "*:4040"]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [4040])
    }

    func testInferPortsFromPrivateIPv4HostTokens() {
        let tokens = ["node", "server.js", "10.20.30.40:4173/graphql", "192.168.0.12:3000,"]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [3000, 4173])
    }

    func testInferPortsFromHostnameHostTokens() {
        let tokens = ["node", "server.js", "api.local:4173/graphql", "dev.internal:3000,"]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [3000, 4173])
    }

    func testInferPortsFromURLTokenWithTrailingPunctuation() {
        let tokens = ["node", "server.js", "https://localhost:5443/graphql),"]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [5443])
    }

    func testInferPortsFromURLEmbeddedInFlagValue() {
        let tokens = ["vite", "--host", "127.0.0.1", "--public-url=http://127.0.0.1:3000/app"]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [3000])
    }

    func testInferPortsFromURLTokenWithIPv4MappedIPv6Host() {
        let tokens = ["node", "server.js", "http://[::ffff:127.0.0.1]:5173/graphql"]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(ports, [5173])
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

    func testInferPortsIgnoresInvalidIPv4HostTokens() {
        let tokens = ["node", "server.js", "999.20.30.40:4173", "1.2.3:3000"]
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertTrue(ports.isEmpty)
    }

    func testInferPortsIgnoresAmbiguousTokenWithoutHostnameSignal() {
        let tokens = ["node", "server.js", "build:3000"]
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

    func testInferWorkingDirectoryTrimsTrailingPunctuationFromInlineFlags() {
        let path = CommandParser.inferWorkingDirectory(from: ["next", "--workspace=/tmp/slaynode-web,"])

        XCTAssertEqual(path, "/tmp/slaynode-web")
    }

    func testInferWorkingDirectoryTrimsTrailingPunctuationFromValueFlags() {
        let path = CommandParser.inferWorkingDirectory(from: ["npm", "--prefix", "/tmp/slaynode-api;", "run", "dev"])

        XCTAssertEqual(path, "/tmp/slaynode-api")
    }

    func testInferWorkingDirectoryIgnoresBlankFlagValues() {
        let path = CommandParser.inferWorkingDirectory(from: ["npm", "--cwd", "", "run", "dev"])

        XCTAssertNil(path)
    }

    func testInferWorkingDirectoryExpandsQuotedTildeFlagValues() {
        let path = CommandParser.inferWorkingDirectory(from: ["npm", "--prefix", "\"~/Projects/app,\"", "run", "dev"])

        XCTAssertTrue(path?.hasSuffix("Projects/app") ?? false)
    }

    func testInferWorkingDirectoryFromPrefixFlag() {
        let path = CommandParser.inferWorkingDirectory(from: ["npm", "--prefix", "~/Projects/app", "run", "dev"])

        XCTAssertTrue(path?.hasSuffix("Projects/app") ?? false)
    }

    func testInferWorkingDirectoryFromShortCFlag() {
        let path = CommandParser.inferWorkingDirectory(from: ["pnpm", "-C", "~/Projects/api", "dev"])

        XCTAssertTrue(path?.hasSuffix("Projects/api") ?? false)
    }

    func testInferWorkingDirectoryFromEscapedSpaceFlagValue() {
        let tokens = CommandParser.tokenize("npm --cwd /Users/test/My\\ App run dev")
        let path = CommandParser.inferWorkingDirectory(from: tokens)

        XCTAssertEqual(path, "/Users/test/My App")
    }

    func testInferWorkingDirectoryFromEscapedSpacePrefixFlagValue() {
        let tokens = CommandParser.tokenize("npm --prefix /Users/test/My\\ App run dev")
        let path = CommandParser.inferWorkingDirectory(from: tokens)

        XCTAssertEqual(path, "/Users/test/My App")
    }

    func testInferWorkingDirectoryFromExtensionlessServerEntrypoint() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let scriptsDirectory = tempRoot.appendingPathComponent("scripts", isDirectory: true)
        let serverPath = scriptsDirectory.appendingPathComponent("dev-server", isDirectory: false)

        try FileManager.default.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        FileManager.default.createFile(atPath: serverPath.path, contents: Data())

        let tokens = ["node", serverPath.path, "--watch"]

        XCTAssertEqual(CommandParser.inferWorkingDirectory(from: tokens), scriptsDirectory.path)
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

    func testPackageManagerWrapperSkipsProjectAndWorkingDirectoryFlagsBeforeRun() {
        let projectTokens = ["npm", "--project", "frontend", "exec", "vite"]
        let projectContext = CommandParser.makeContext(
            executable: projectTokens[0],
            tokens: projectTokens,
            workingDirectory: "/Users/test/app"
        )
        let projectDescriptor = CommandParser.descriptor(from: projectContext)

        let workingDirectoryTokens = ["yarn", "--working-dir", "frontend", "workspace", "web", "run", "dev"]
        let workingDirectoryContext = CommandParser.makeContext(
            executable: workingDirectoryTokens[0],
            tokens: workingDirectoryTokens,
            workingDirectory: "/Users/test/app"
        )
        let workingDirectoryDescriptor = CommandParser.descriptor(from: workingDirectoryContext)

        XCTAssertEqual(projectDescriptor.packageManager, "npm")
        XCTAssertEqual(projectDescriptor.displayName, "Vite")
        XCTAssertEqual(projectDescriptor.script, "vite")

        XCTAssertEqual(workingDirectoryDescriptor.packageManager, "yarn")
        XCTAssertEqual(workingDirectoryDescriptor.script, "dev")
    }

    func testPackageManagerWrapperSkipsConfigAndRegistryFlagsBeforeRun() {
        let configTokens = ["npm", "--userconfig", ".npmrc.local", "run", "dev"]
        let configContext = CommandParser.makeContext(
            executable: configTokens[0],
            tokens: configTokens,
            workingDirectory: "/Users/test/app"
        )
        let configDescriptor = CommandParser.descriptor(from: configContext)

        let registryTokens = ["pnpm", "--registry=https://registry.example.test", "exec", "vite"]
        let registryContext = CommandParser.makeContext(
            executable: registryTokens[0],
            tokens: registryTokens,
            workingDirectory: "/Users/test/app"
        )
        let registryDescriptor = CommandParser.descriptor(from: registryContext)

        XCTAssertEqual(configDescriptor.packageManager, "npm")
        XCTAssertEqual(configDescriptor.script, "dev")
        XCTAssertEqual(registryDescriptor.packageManager, "pnpm")
        XCTAssertEqual(registryDescriptor.displayName, "Vite")
        XCTAssertEqual(registryDescriptor.script, "vite")
    }

    func testPackageManagerWrapperParsesNpmPrefixExecViteCommand() {
        let tokens = ["npm", "--prefix", "app", "exec", "vite", "--", "--host", "127.0.0.1", "--port", "5173"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: "/Users/test/app")
        let descriptor = CommandParser.descriptor(from: context)
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(descriptor.packageManager, "npm")
        XCTAssertEqual(descriptor.displayName, "Vite")
        XCTAssertEqual(descriptor.script, "vite")
        XCTAssertEqual(descriptor.category, .bundler)
        XCTAssertEqual(ports, [5173])
    }

    func testPackageManagerWrapperParsesPnpmFilterRunCommand() {
        let tokens = ["pnpm", "--filter", "web", "dev", "--", "--port", "3000"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: "/Users/test/app")
        let descriptor = CommandParser.descriptor(from: context)
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(descriptor.packageManager, "pnpm")
        XCTAssertEqual(descriptor.script, "dev")
        XCTAssertEqual(ports, [3000])
    }

    func testPackageManagerWrapperParsesPnpmFilterAliasRunCommand() {
        let tokens = ["pnpm", "-F", "web", "dev", "--", "--port", "3001"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: "/Users/test/app")
        let descriptor = CommandParser.descriptor(from: context)
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(descriptor.packageManager, "pnpm")
        XCTAssertEqual(descriptor.script, "dev")
        XCTAssertEqual(ports, [3001])
    }

    func testPackageManagerWrapperParsesBunRunBunViteCommand() {
        let tokens = ["bun", "--bun", "vite", "dev", "--port", "5174"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: "/Users/test/app")
        let descriptor = CommandParser.descriptor(from: context)
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(descriptor.packageManager, "bun")
        XCTAssertEqual(descriptor.displayName, "Vite")
        XCTAssertEqual(descriptor.script, "vite")
        XCTAssertEqual(descriptor.category, .bundler)
        XCTAssertEqual(ports, [5174])
    }

    func testPackageManagerWrapperParsesBunXViteCommand() {
        let tokens = ["bun", "x", "vite", "--port", "4173"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: "/Users/test/app")
        let descriptor = CommandParser.descriptor(from: context)
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(descriptor.packageManager, "bun")
        XCTAssertEqual(descriptor.displayName, "Vite")
        XCTAssertEqual(descriptor.script, "vite")
        XCTAssertEqual(descriptor.category, .bundler)
        XCTAssertEqual(ports, [4173])
    }

    func testPackageManagerWrapperParsesBunWatchCommand() {
        let tokens = ["bun", "--watch", "src/server.ts", "--port", "4173"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: "/Users/test/app")
        let descriptor = CommandParser.descriptor(from: context)
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(descriptor.packageManager, "bun")
        XCTAssertEqual(descriptor.script, "src/server.ts")
        XCTAssertEqual(descriptor.runtime, "Bun")
        XCTAssertEqual(ports, [4173])
    }

    func testPackageManagerWrapperParsesBunHotCommand() {
        let tokens = ["bun", "--hot", "src/server.ts", "--inspect=127.0.0.1:9230"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: "/Users/test/app")
        let descriptor = CommandParser.descriptor(from: context)
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(descriptor.packageManager, "bun")
        XCTAssertEqual(descriptor.script, "src/server.ts")
        XCTAssertEqual(descriptor.runtime, "Bun")
        XCTAssertEqual(ports, [9230])
    }

    func testDenoTaskCommandWithInlinePortIsDetected() {
        let tokens = ["deno", "task", "dev", "--port", "8000"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: "/Users/test/app")
        let descriptor = CommandParser.descriptor(from: context)
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(descriptor.displayName, "Deno")
        XCTAssertEqual(descriptor.runtime, "Deno")
        XCTAssertEqual(descriptor.category, .runtime)
        XCTAssertEqual(ports, [8000])
    }

    func testDenoTaskCommandWithPassthroughPortIsDetected() {
        let tokens = ["deno", "task", "dev", "--", "--port=8080", "--host", "127.0.0.1"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: "/Users/test/app")
        let descriptor = CommandParser.descriptor(from: context)
        let ports = CommandParser.inferPorts(from: tokens)

        XCTAssertEqual(descriptor.displayName, "Deno")
        XCTAssertEqual(descriptor.runtime, "Deno")
        XCTAssertEqual(descriptor.category, .runtime)
        XCTAssertEqual(ports, [8080])
    }

    func testYarnWorkspaceScriptNameIsParsed() {
        let tokens = ["yarn", "workspace", "web", "dev"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: "/Users/test/app")
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertEqual(descriptor.packageManager, "yarn")
        XCTAssertEqual(descriptor.script, "dev")
    }

    func testYarnWorkspaceRunScriptNameIsParsed() {
        let tokens = ["yarn", "workspace", "web", "run", "dev"]
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

    func testViteModeDetectionIsCaseInsensitiveAndPunctuationTolerant() {
        let tokens = ["vite", "DEV,", "--port", "5173"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: nil)
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertEqual(descriptor.displayName, "Vite")
        XCTAssertEqual(descriptor.details, "Mode: DEV")
    }

    func testWebpackServeCommandIsDetected() {
        let tokens = ["webpack", "serve", "--mode", "development"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: nil)
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertEqual(descriptor.displayName, "Webpack Dev Server")
        XCTAssertEqual(descriptor.category, .bundler)
        XCTAssertEqual(descriptor.portHints, [8080, 3000])
    }

    func testParcelCommandIsDetected() {
        let tokens = ["parcel", "src/index.html"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: nil)
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertEqual(descriptor.displayName, "Parcel")
        XCTAssertEqual(descriptor.category, .bundler)
        XCTAssertEqual(descriptor.portHints, [1234])
    }

    func testViteClassifierDoesNotMatchInviteSubstring() {
        let tokens = ["node", "/Users/demo/app/invite-server.js"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: nil)
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertNotEqual(descriptor.displayName, "Vite")
        XCTAssertEqual(descriptor.displayName, "invite-server.js")
    }

    func testMonorepoToolCommandsAreDetected() {
        let turbo = CommandParser.descriptor(from: CommandParser.makeContext(
            executable: "turbo",
            tokens: ["turbo", "run", "dev"],
            workingDirectory: nil
        ))
        let nx = CommandParser.descriptor(from: CommandParser.makeContext(
            executable: "nx",
            tokens: ["nx", "serve", "web"],
            workingDirectory: nil
        ))

        XCTAssertEqual(turbo.displayName, "Turborepo")
        XCTAssertEqual(turbo.category, .monorepo)
        XCTAssertEqual(nx.displayName, "Nx")
        XCTAssertEqual(nx.category, .monorepo)
    }

    func testMonorepoToolClassifiersDoNotMatchSubstrings() {
        let turboTokens = ["node", "/Users/demo/app/turbofan-server.js"]
        let turboContext = CommandParser.makeContext(executable: turboTokens[0], tokens: turboTokens, workingDirectory: nil)
        let turboDescriptor = CommandParser.descriptor(from: turboContext)

        let nxTokens = ["node", "/Users/demo/app/lynx-server.js"]
        let nxContext = CommandParser.makeContext(executable: nxTokens[0], tokens: nxTokens, workingDirectory: nil)
        let nxDescriptor = CommandParser.descriptor(from: nxContext)

        XCTAssertEqual(turboDescriptor.displayName, "turbofan-server.js")
        XCTAssertEqual(nxDescriptor.displayName, "lynx-server.js")
    }

    func testNodemonClassifiedAsTool() {
        let tokens = ["nodemon", "server.js"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: nil)
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertEqual(descriptor.displayName, "Nodemon")
        XCTAssertEqual(descriptor.category, .utility)
        XCTAssertEqual(descriptor.portHints, [3000, 4000])
    }

    func testTsxRunnerIsClassifiedAsTool() {
        let tokens = ["tsx", "watch", "server.ts"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: nil)
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertEqual(descriptor.displayName, "TSX")
        XCTAssertEqual(descriptor.category, .utility)
        XCTAssertEqual(descriptor.portHints, [3000, 4000])
    }

    func testTsxSourceFileDoesNotClassifyAsRunner() {
        let tokens = ["node", "src/App.tsx"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: nil)
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertNotEqual(descriptor.displayName, "TSX")
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

    func testNitroCommandIsDetectedAsBackend() {
        let tokens = ["node", "node_modules/.bin/nitro", "dev"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: nil)
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertEqual(descriptor.displayName, "Nitro")
        XCTAssertEqual(descriptor.category, .backend)
        XCTAssertEqual(descriptor.portHints, [3000])
        XCTAssertEqual(descriptor.details, "Mode: DEV")
    }

    func testTanStackStartCommandIsDetectedAsWebFramework() {
        let tokens = ["node", "node_modules/.bin/tanstack-start", "dev"]
        let context = CommandParser.makeContext(executable: tokens[0], tokens: tokens, workingDirectory: nil)
        let descriptor = CommandParser.descriptor(from: context)

        XCTAssertEqual(descriptor.displayName, "TanStack Start")
        XCTAssertEqual(descriptor.category, .webFramework)
        XCTAssertEqual(descriptor.portHints, [3000])
        XCTAssertEqual(descriptor.details, "Mode: DEV")
    }
}
#endif
