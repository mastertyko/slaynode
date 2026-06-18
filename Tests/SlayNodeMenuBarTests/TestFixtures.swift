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
#endif
