#if canImport(XCTest)
import Foundation
@testable import SlayNodeMenuBar

func makeWorkspaceFixture(
    id: String = "workspace:/app",
    name: String = "app",
    rootPath: String = "/tmp/app"
) -> WorkspaceIdentity {
    WorkspaceIdentity(id: id, name: name, rootPath: rootPath)
}

func makeManagedServiceFixture(
    id: String = "process:999",
    name: String = "frontend",
    kind: ServiceKind = .app,
    status: ManagedServiceStatus = .running,
    health: ServiceHealth = .healthy,
    source: ServiceSource = .process(pid: 999, command: "npm run dev"),
    workspace: WorkspaceIdentity? = nil,
    ports: [ServicePort] = [],
    runtime: String? = "Node.js",
    summary: String = "summary",
    command: String? = "npm run dev",
    configPath: String? = nil,
    logPath: String? = nil,
    tags: [String] = [],
    availableActions: [ServiceAction] = [.stop],
    startedAt: Date? = nil,
    lastSeenAt: Date = Date()
) -> ManagedService {
    ManagedService(
        id: id,
        name: name,
        kind: kind,
        status: status,
        health: health,
        source: source,
        workspace: workspace,
        ports: ports,
        runtime: runtime,
        summary: summary,
        command: command,
        configPath: configPath,
        logPath: logPath,
        tags: tags,
        availableActions: availableActions,
        startedAt: startedAt,
        lastSeenAt: lastSeenAt
    )
}

struct ToolingProcessFixture {
    let executable: String
    let command: String
}

let knownToolingProcessFixtures: [ToolingProcessFixture] = [
    ToolingProcessFixture(
        executable: "/opt/homebrew/bin/node",
        command: "/opt/homebrew/lib/node_modules/typescript/lib/typingsinstaller.js --globalTypingsCacheLocation /tmp/cache"
    ),
    ToolingProcessFixture(
        executable: "/opt/homebrew/bin/node",
        command: "/opt/homebrew/bin/browser_use.skill_cli.daemon --transport pipe"
    ),
    ToolingProcessFixture(
        executable: "/opt/homebrew/bin/esbuild",
        command: "/opt/homebrew/bin/esbuild --service=0.25.1 --ping"
    ),
    ToolingProcessFixture(
        executable: "/usr/bin/sourcekit-lsp",
        command: "/usr/bin/sourcekit-lsp"
    ),
    ToolingProcessFixture(
        executable: "/opt/homebrew/bin/node",
        command: "/Users/test/.codex/worktrees/abcd/repo/node_modules/.bin/tsx src/dev.ts"
    ),
    ToolingProcessFixture(
        executable: "/tmp/codex-native-hook",
        command: "/tmp/codex-native-hook --event post-command"
    )
]
#endif
