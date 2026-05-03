import Foundation

enum ProcessActionScope: String, Sendable {
    case processGroup
    case processTree
    case singleProcess
    case unavailable

    var title: String {
        switch self {
        case .processGroup: return "Process Group"
        case .processTree: return "Process Tree"
        case .singleProcess: return "Single Process"
        case .unavailable: return "Live Scope Unavailable"
        }
    }
}

enum ProcessActionPreviewRole: String, Sendable {
    case target
    case child
    case groupMember

    var title: String {
        switch self {
        case .target: return "Target"
        case .child: return "Child"
        case .groupMember: return "Group"
        }
    }
}

struct ProcessActionPreviewProcess: Identifiable, Hashable, Sendable {
    let pid: Int32
    let parentPID: Int32?
    let processGroupID: Int32?
    let command: String
    let ports: [Int]
    let role: ProcessActionPreviewRole

    var id: Int32 { pid }
}

struct ServiceActionPreview: Identifiable, Hashable, Sendable {
    let id = UUID()
    let action: ServiceAction
    let serviceID: String
    let serviceName: String
    let sourceTitle: String
    let scope: ProcessActionScope
    let targetPID: Int32
    let targetProcessGroupID: Int32?
    let processes: [ProcessActionPreviewProcess]
    let warning: String?

    var processCount: Int {
        processes.count
    }

    var portSummary: String {
        let ports = Array(Set(processes.flatMap(\.ports))).sorted()
        guard !ports.isEmpty else { return "No live ports" }
        return ports.map { ":\($0)" }.joined(separator: " ")
    }
}

struct ProcessActionPreviewer: Sendable {
    struct ProcessRow: Hashable, Sendable {
        let pid: Int32
        let parentPID: Int32
        let processGroupID: Int32
        let command: String
    }

    private let shell: any ShellExecuting
    private let portResolver: PortResolver

    init(
        shell: any ShellExecuting = SystemShellExecutor(),
        portResolver: PortResolver = PortResolver()
    ) {
        self.shell = shell
        self.portResolver = portResolver
    }

    func preview(action: ServiceAction, service: ManagedService) async -> ServiceActionPreview? {
        guard action.requiresProcessImpactPreview,
              case .process(let pid, let command) = service.source else {
            return nil
        }

        let rows = await fetchProcessRows()
        let scopedPreview = Self.makePreview(
            action: action,
            service: service,
            targetPID: pid,
            fallbackCommand: command,
            rows: rows,
            portsByPid: [:]
        )

        guard let scopedPreview else { return nil }
        let portsByPid = await portResolver.resolvePorts(for: scopedPreview.processes.map(\.pid))

        return Self.makePreview(
            action: action,
            service: service,
            targetPID: pid,
            fallbackCommand: command,
            rows: rows,
            portsByPid: portsByPid
        )
    }

    static func parseProcessRows(from output: String) -> [ProcessRow] {
        output.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let components = rawLine.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard components.count == 4,
                  let pid = Int32(components[0]),
                  let parentPID = Int32(components[1]),
                  let processGroupID = Int32(components[2]) else {
                return nil
            }

            return ProcessRow(
                pid: pid,
                parentPID: parentPID,
                processGroupID: processGroupID,
                command: String(components[3])
            )
        }
    }

    static func makePreview(
        action: ServiceAction,
        service: ManagedService,
        targetPID: Int32,
        fallbackCommand: String,
        rows: [ProcessRow],
        portsByPid: [Int32: [Int]]
    ) -> ServiceActionPreview? {
        guard action.requiresProcessImpactPreview else { return nil }

        guard let target = rows.first(where: { $0.pid == targetPID }) else {
            let fallbackPorts = fallbackPorts(for: targetPID, service: service, portsByPid: portsByPid)
            return ServiceActionPreview(
                action: action,
                serviceID: service.id,
                serviceName: service.name,
                sourceTitle: service.source.title,
                scope: .unavailable,
                targetPID: targetPID,
                targetProcessGroupID: nil,
                processes: [
                    ProcessActionPreviewProcess(
                        pid: targetPID,
                        parentPID: nil,
                        processGroupID: nil,
                        command: ServiceSanitizer.redactSecrets(in: fallbackCommand),
                        ports: fallbackPorts,
                        role: .target
                    )
                ],
                warning: "Live process-group details could not be read. SlayNode will revalidate the service before acting."
            )
        }

        let scopedRows = scopedRows(for: target, action: action, rows: rows)
        let processes = scopedRows.map { row in
            ProcessActionPreviewProcess(
                pid: row.pid,
                parentPID: row.parentPID,
                processGroupID: row.processGroupID,
                command: ServiceSanitizer.redactSecrets(in: row.command),
                ports: fallbackPorts(for: row.pid, service: service, portsByPid: portsByPid),
                role: role(for: row, target: target)
            )
        }

        return ServiceActionPreview(
            action: action,
            serviceID: service.id,
            serviceName: service.name,
            sourceTitle: service.source.title,
            scope: scope(for: target, action: action, rows: scopedRows),
            targetPID: target.pid,
            targetProcessGroupID: target.processGroupID,
            processes: processes,
            warning: warning(for: processes, target: target)
        )
    }

    private func fetchProcessRows() async -> [ProcessRow] {
        do {
            let (status, output) = try await shell.run(
                Constants.Path.ps,
                arguments: ["-axo", "pid=,ppid=,pgid=,command="],
                timeout: Constants.Timeout.commandTimeout
            )
            guard status == 0 else { return [] }
            return Self.parseProcessRows(from: output)
        } catch {
            Log.process.warning("Process action preview failed: \(error.localizedDescription)")
            return []
        }
    }

    private static func scopedRows(
        for target: ProcessRow,
        action: ServiceAction,
        rows: [ProcessRow]
    ) -> [ProcessRow] {
        let selectedRows: [ProcessRow]

        if action == .forceStop, target.processGroupID > 0 {
            selectedRows = rows.filter { $0.processGroupID == target.processGroupID }
        } else if action == .stop, target.processGroupID > 0, target.processGroupID != target.pid {
            selectedRows = rows.filter { $0.processGroupID == target.processGroupID }
        } else {
            let childRows = rows.filter { $0.parentPID == target.pid }
            selectedRows = [target] + childRows
        }

        return selectedRows
            .reduce(into: [Int32: ProcessRow]()) { result, row in
                result[row.pid] = row
            }
            .values
            .sorted { lhs, rhs in
                if lhs.pid == target.pid { return true }
                if rhs.pid == target.pid { return false }
                return lhs.pid < rhs.pid
            }
    }

    private static func scope(for target: ProcessRow, action: ServiceAction, rows: [ProcessRow]) -> ProcessActionScope {
        guard rows.count > 1 else { return .singleProcess }
        if action == .forceStop, target.processGroupID > 0 { return .processGroup }
        if action == .stop, target.processGroupID > 0, target.processGroupID != target.pid { return .processGroup }
        return .processTree
    }

    private static func role(for row: ProcessRow, target: ProcessRow) -> ProcessActionPreviewRole {
        if row.pid == target.pid { return .target }
        if row.parentPID == target.pid { return .child }
        return .groupMember
    }

    private static func warning(for processes: [ProcessActionPreviewProcess], target: ProcessRow) -> String? {
        let groupMemberCount = processes.filter { $0.role == .groupMember }.count
        if groupMemberCount > 0 {
            return "This action will signal \(groupMemberCount) additional process-group member\(groupMemberCount == 1 ? "" : "s")."
        }

        let childCount = processes.filter { $0.role == .child }.count
        if childCount > 0 {
            return "This action will signal the target process and \(childCount) child process\(childCount == 1 ? "" : "es")."
        }

        if target.processGroupID == target.pid {
            return "The target is its process-group leader."
        }

        return nil
    }

    private static func fallbackPorts(
        for pid: Int32,
        service: ManagedService,
        portsByPid: [Int32: [Int]]
    ) -> [Int] {
        if let ports = portsByPid[pid], !ports.isEmpty {
            return ports
        }

        guard case .process(let servicePID, _) = service.source, servicePID == pid else {
            return []
        }

        return service.ports.map(\.value).sorted()
    }
}

extension ServiceAction {
    var requiresProcessImpactPreview: Bool {
        self == .stop || self == .forceStop
    }
}
