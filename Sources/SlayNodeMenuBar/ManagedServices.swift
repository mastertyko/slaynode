import Foundation
import SwiftData

enum ServiceSanitizer {
    private static let sensitiveFlags: Set<String> = [
        "access-token",
        "api-key",
        "apikey",
        "auth-token",
        "client-secret",
        "password",
        "passwd",
        "private-key",
        "refresh-token",
        "secret",
        "token"
    ]

    static func redactSecrets(in value: String) -> String {
        guard !value.isEmpty else { return value }

        let tokens = CommandParser.tokenize(value)
        guard !tokens.isEmpty else {
            return redactURLCredentials(in: value)
        }

        var redacted: [String] = []
        var index = 0

        while index < tokens.count {
            let token = tokens[index]

            if let inlineAssignment = redactInlineAssignment(token) {
                redacted.append(inlineAssignment)
                index += 1
                continue
            }

            if sensitiveFlagName(from: token) != nil {
                redacted.append(token)
                if index + 1 < tokens.count {
                    redacted.append("***")
                    index += 2
                } else {
                    index += 1
                }
                continue
            }

            redacted.append(redactURLCredentials(in: token))
            index += 1
        }

        return redacted.joined(separator: " ")
    }

    private static func sensitiveFlagName(from token: String) -> String? {
        let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let normalized = trimmed
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")

        return sensitiveFlags.contains(normalized) ? normalized : nil
    }

    private static func redactInlineAssignment(_ token: String) -> String? {
        guard let separator = token.firstIndex(of: "=") else { return nil }

        let flag = String(token[..<separator])
        guard sensitiveFlagName(from: flag) != nil else { return nil }

        return "\(flag)=***"
    }

    private static func redactURLCredentials(in token: String) -> String {
        guard let schemeRange = token.range(of: "://"),
              let atRange = token.range(of: "@", range: schemeRange.upperBound..<token.endIndex) else {
            return token
        }

        return "\(token[..<schemeRange.upperBound])***\(token[atRange.lowerBound...])"
    }
}

enum ServiceKind: String, CaseIterable, Sendable {
    case app
    case api
    case database
    case cache
    case queue
    case proxy
    case worker
    case container
    case runtime
    case tool
    case unknown

    var title: String {
        switch self {
        case .app: return "Application"
        case .api: return "API"
        case .database: return "Database"
        case .cache: return "Cache"
        case .queue: return "Queue"
        case .proxy: return "Proxy"
        case .worker: return "Worker"
        case .container: return "Container"
        case .runtime: return "Runtime"
        case .tool: return "Tool"
        case .unknown: return "Service"
        }
    }

    var symbolName: String {
        switch self {
        case .app: return "app.connected.to.app.below.fill"
        case .api: return "server.rack"
        case .database: return "cylinder.split.1x2.fill"
        case .cache: return "bolt.horizontal.circle.fill"
        case .queue: return "tray.full.fill"
        case .proxy: return "arrow.triangle.branch"
        case .worker: return "gearshape.2.fill"
        case .container: return "shippingbox.fill"
        case .runtime: return "terminal.fill"
        case .tool: return "wrench.and.screwdriver.fill"
        case .unknown: return "square.stack.3d.up.fill"
        }
    }
}

enum ManagedServiceStatus: String, Sendable {
    case running
    case degraded
    case stopped
    case unavailable

    var title: String {
        switch self {
        case .running: return "Running"
        case .degraded: return "Degraded"
        case .stopped: return "Stopped"
        case .unavailable: return "Unavailable"
        }
    }
}

enum ServiceHealth: String, Sendable {
    case healthy
    case watch
    case critical
    case passive

    var title: String {
        switch self {
        case .healthy: return "Healthy"
        case .watch: return "Needs attention"
        case .critical: return "Critical"
        case .passive: return "Passive"
        }
    }
}

enum ServiceAction: String, CaseIterable, Identifiable, Sendable {
    case stop
    case forceStop
    case restart
    case openLogs
    case openWorkspace
    case revealConfig

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stop: return "Stop"
        case .forceStop: return "Force Stop"
        case .restart: return "Restart"
        case .openLogs: return "Open Logs"
        case .openWorkspace: return "Open Workspace"
        case .revealConfig: return "Reveal Config"
        }
    }

    var systemImage: String {
        switch self {
        case .stop: return "stop.circle.fill"
        case .forceStop: return "xmark.circle.fill"
        case .restart: return "arrow.clockwise.circle.fill"
        case .openLogs: return "doc.text.magnifyingglass"
        case .openWorkspace: return "folder.fill"
        case .revealConfig: return "doc.badge.gearshape"
        }
    }
}

struct WorkspaceIdentity: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let rootPath: String
}

struct ServiceDependency: Identifiable, Hashable, Sendable {
    let id: String
    let sourceID: String
    let targetID: String
    let label: String
}

struct ServicePort: Identifiable, Hashable, Sendable {
    let value: Int
    let isInferred: Bool

    var id: Int { value }
}

enum ServiceSource: Hashable, Sendable {
    case process(pid: Int32, command: String)
    case docker(containerID: String, image: String)
    case brewService(name: String, plistPath: String?)

    var id: String {
        switch self {
        case .process(let pid, _):
            return "process:\(pid)"
        case .docker(let containerID, _):
            return "docker:\(containerID)"
        case .brewService(let name, _):
            return "brew:\(name)"
        }
    }

    var title: String {
        switch self {
        case .process:
            return "Local process"
        case .docker:
            return "Docker"
        case .brewService:
            return "Homebrew Service"
        }
    }

    var primaryIdentifier: String {
        switch self {
        case .process(let pid, _):
            return "PID \(pid)"
        case .docker(let containerID, _):
            return String(containerID.prefix(12))
        case .brewService(let name, _):
            return name
        }
    }
}

struct ManagedService: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let kind: ServiceKind
    let status: ManagedServiceStatus
    let health: ServiceHealth
    let source: ServiceSource
    let workspace: WorkspaceIdentity?
    let ports: [ServicePort]
    let runtime: String?
    let summary: String
    let command: String?
    let configPath: String?
    let logPath: String?
    let tags: [String]
    let availableActions: [ServiceAction]
    let startedAt: Date?
    let lastSeenAt: Date

    var primaryPort: Int? {
        ports.first?.value
    }

    var searchIndex: String {
        [
            name,
            kind.title,
            status.title,
            health.title,
            workspace?.name,
            workspace?.rootPath,
            runtime,
            summary,
            command,
            source.title,
            source.primaryIdentifier,
            configPath,
            tags.joined(separator: " "),
            ports.map { String($0.value) }.joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
    }

    func supports(_ action: ServiceAction) -> Bool {
        availableActions.contains(action)
    }
}

struct ServiceSnapshot: Sendable {
    let services: [ManagedService]
    let dependencies: [ServiceDependency]
    let generatedAt: Date
}

struct ServiceActionSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let serviceID: String
    let serviceName: String
    let action: ServiceAction
    let outcome: String
    let timestamp: Date
}

struct PersistedWindowState: Sendable {
    let selectedWorkspaceID: String?
    let selectedServiceID: String?
    let searchText: String
    let inspectorVisible: Bool
}

@Model
final class WorkspaceHistoryRecord {
    @Attribute(.unique) var id: String
    var name: String
    var rootPath: String
    var lastSeenAt: Date
    var openCount: Int

    init(id: String, name: String, rootPath: String, lastSeenAt: Date, openCount: Int = 1) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.lastSeenAt = lastSeenAt
        self.openCount = openCount
    }
}

@Model
final class ServiceHistoryRecord {
    @Attribute(.unique) var id: String
    var name: String
    var kindRawValue: String
    var sourceRawValue: String
    var workspaceID: String?
    var workspaceName: String?
    var workspacePath: String?
    var statusRawValue: String
    var lastSeenAt: Date
    var lastActionRawValue: String?
    var lastActionAt: Date?

    init(
        id: String,
        name: String,
        kindRawValue: String,
        sourceRawValue: String,
        workspaceID: String?,
        workspaceName: String?,
        workspacePath: String?,
        statusRawValue: String,
        lastSeenAt: Date,
        lastActionRawValue: String? = nil,
        lastActionAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.kindRawValue = kindRawValue
        self.sourceRawValue = sourceRawValue
        self.workspaceID = workspaceID
        self.workspaceName = workspaceName
        self.workspacePath = workspacePath
        self.statusRawValue = statusRawValue
        self.lastSeenAt = lastSeenAt
        self.lastActionRawValue = lastActionRawValue
        self.lastActionAt = lastActionAt
    }
}

@Model
final class ServiceActionRecord {
    var id: UUID
    var serviceID: String
    var serviceName: String
    var actionRawValue: String
    var outcome: String
    var timestamp: Date

    init(
        id: UUID = UUID(),
        serviceID: String,
        serviceName: String,
        actionRawValue: String,
        outcome: String,
        timestamp: Date
    ) {
        self.id = id
        self.serviceID = serviceID
        self.serviceName = serviceName
        self.actionRawValue = actionRawValue
        self.outcome = outcome
        self.timestamp = timestamp
    }
}

@Model
final class WindowStateRecord {
    @Attribute(.unique) var id: String
    var selectedWorkspaceID: String?
    var selectedServiceID: String?
    var searchText: String
    var inspectorVisible: Bool
    var updatedAt: Date

    init(
        id: String,
        selectedWorkspaceID: String?,
        selectedServiceID: String?,
        searchText: String,
        inspectorVisible: Bool,
        updatedAt: Date
    ) {
        self.id = id
        self.selectedWorkspaceID = selectedWorkspaceID
        self.selectedServiceID = selectedServiceID
        self.searchText = searchText
        self.inspectorVisible = inspectorVisible
        self.updatedAt = updatedAt
    }
}
