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
    case descendant
    case groupMember

    var title: String {
        switch self {
        case .target: return "Target"
        case .child: return "Child"
        case .descendant: return "Descendant"
        case .groupMember: return "Group"
        }
    }
}

enum ProcessActionRiskLevel: String, Sendable {
    case low
    case moderate
    case elevated
    case high
    case unknown

    var title: String {
        switch self {
        case .low: return "Low Risk"
        case .moderate: return "Moderate Risk"
        case .elevated: return "Elevated Risk"
        case .high: return "High Risk"
        case .unknown: return "Unknown Risk"
        }
    }

    var systemImage: String {
        switch self {
        case .low: return "checkmark.shield.fill"
        case .moderate: return "exclamationmark.shield.fill"
        case .elevated: return "exclamationmark.triangle.fill"
        case .high: return "exclamationmark.octagon.fill"
        case .unknown: return "questionmark.diamond.fill"
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
    let depth: Int

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
    let omittedProcessCount: Int
    let riskLevel: ProcessActionRiskLevel
    let warnings: [String]

    var processCount: Int {
        processes.count + omittedProcessCount
    }

    var visibleProcessCount: Int {
        processes.count
    }

    var hasOmittedProcesses: Bool {
        omittedProcessCount > 0
    }

    var warning: String? {
        warnings.first
    }

    var portSummary: String {
        let ports = Array(Set(processes.flatMap(\.ports))).sorted()
        guard !ports.isEmpty else { return "No live ports" }

        if ports.count <= 4 {
            return ports.map { ":\($0)" }.joined(separator: " ")
        }

        let visiblePorts = ports.prefix(4).map { ":\($0)" }.joined(separator: " ")
        return "\(visiblePorts) +\(ports.count - 4)"
    }
}

private struct ScopedProcessRows: Sendable {
    let rows: [ProcessActionPreviewer.ProcessRow]
    let omittedProcessCount: Int
}

private struct ProcessActionPreviewTree: Sendable {
    let childrenByParent: [Int32: [ProcessActionPreviewer.ProcessRow]]
    private let rowByPID: [Int32: ProcessActionPreviewer.ProcessRow]

    init(rows: [ProcessActionPreviewer.ProcessRow]) {
        self.childrenByParent = Dictionary(grouping: rows) { $0.parentPID }
        self.rowByPID = rows.reduce(into: [:]) { result, row in
            result[row.pid] = row
        }
    }

    func descendants(of parentPID: Int32) -> [ProcessActionPreviewer.ProcessRow] {
        var result: [ProcessActionPreviewer.ProcessRow] = []
        var visited: Set<Int32> = [parentPID]
        var queue = childrenByParent[parentPID, default: []].sorted { $0.pid < $1.pid }

        while !queue.isEmpty {
            let row = queue.removeFirst()
            guard !visited.contains(row.pid) else { continue }
            visited.insert(row.pid)
            result.append(row)
            queue.append(contentsOf: childrenByParent[row.pid, default: []].sorted { $0.pid < $1.pid })
        }

        return result
    }

    func isDescendant(_ pid: Int32, of parentPID: Int32) -> Bool {
        descendants(of: parentPID).contains { $0.pid == pid }
    }

    func depth(of pid: Int32, targetPID: Int32) -> Int {
        guard pid != targetPID else { return 0 }

        var depth = 0
        var currentPID = pid
        var visited: Set<Int32> = []

        while let row = rowByPID[currentPID], !visited.contains(currentPID) {
            visited.insert(currentPID)
            depth += 1
            if row.parentPID == targetPID {
                return depth
            }
            currentPID = row.parentPID
        }

        return 0
    }
}

struct ProcessActionPreviewer: Sendable {
    static let maxProcessCount = 24

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
                        role: .target,
                        depth: 0
                    )
                ],
                omittedProcessCount: 0,
                riskLevel: .unknown,
                warnings: ["Live process-group details could not be read. SlayNode will revalidate the service before acting."]
            )
        }

        let tree = ProcessActionPreviewTree(rows: rows)
        let scopedRows = scopedRows(for: target, action: action, rows: rows, tree: tree)
        let processes = scopedRows.rows.map { row in
            ProcessActionPreviewProcess(
                pid: row.pid,
                parentPID: row.parentPID,
                processGroupID: row.processGroupID,
                command: ServiceSanitizer.redactSecrets(in: row.command),
                ports: fallbackPorts(for: row.pid, service: service, portsByPid: portsByPid),
                role: role(for: row, target: target, tree: tree),
                depth: tree.depth(of: row.pid, targetPID: target.pid)
            )
        }
        let scope = scope(for: target, action: action, rows: scopedRows.rows)
        let riskLevel = riskLevel(
            action: action,
            scope: scope,
            processes: processes,
            omittedProcessCount: scopedRows.omittedProcessCount
        )

        return ServiceActionPreview(
            action: action,
            serviceID: service.id,
            serviceName: service.name,
            sourceTitle: service.source.title,
            scope: scope,
            targetPID: target.pid,
            targetProcessGroupID: target.processGroupID,
            processes: processes,
            omittedProcessCount: scopedRows.omittedProcessCount,
            riskLevel: riskLevel,
            warnings: warnings(
                action: action,
                scope: scope,
                processes: processes,
                target: target,
                fallbackCommand: fallbackCommand,
                omittedProcessCount: scopedRows.omittedProcessCount
            )
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
        rows: [ProcessRow],
        tree: ProcessActionPreviewTree
    ) -> ScopedProcessRows {
        let selectedRows: [ProcessRow]

        if action == .forceStop, target.processGroupID > 0 {
            selectedRows = rows.filter { $0.processGroupID == target.processGroupID }
        } else if action == .stop, target.processGroupID > 0, target.processGroupID != target.pid {
            selectedRows = rows.filter { $0.processGroupID == target.processGroupID }
        } else {
            selectedRows = [target] + tree.descendants(of: target.pid)
        }

        let uniqueRows = selectedRows
            .reduce(into: [Int32: ProcessRow]()) { result, row in
                result[row.pid] = row
            }
            .values
            .sorted { lhs, rhs in
                if lhs.pid == target.pid { return true }
                if rhs.pid == target.pid { return false }
                let lhsDepth = tree.depth(of: lhs.pid, targetPID: target.pid)
                let rhsDepth = tree.depth(of: rhs.pid, targetPID: target.pid)
                if lhsDepth != rhsDepth {
                    return lhsDepth < rhsDepth
                }
                return lhs.pid < rhs.pid
            }

        guard uniqueRows.count > maxProcessCount else {
            return ScopedProcessRows(rows: uniqueRows, omittedProcessCount: 0)
        }

        let visibleRows = Array(uniqueRows.prefix(maxProcessCount))
        return ScopedProcessRows(
            rows: visibleRows,
            omittedProcessCount: uniqueRows.count - visibleRows.count
        )
    }

    private static func scope(for target: ProcessRow, action: ServiceAction, rows: [ProcessRow]) -> ProcessActionScope {
        guard rows.count > 1 else { return .singleProcess }
        if action == .forceStop, target.processGroupID > 0 { return .processGroup }
        if action == .stop, target.processGroupID > 0, target.processGroupID != target.pid { return .processGroup }
        return .processTree
    }

    private static func role(
        for row: ProcessRow,
        target: ProcessRow,
        tree: ProcessActionPreviewTree
    ) -> ProcessActionPreviewRole {
        if row.pid == target.pid { return .target }
        if row.parentPID == target.pid { return .child }
        if tree.isDescendant(row.pid, of: target.pid) { return .descendant }
        return .groupMember
    }

    private static func warnings(
        action: ServiceAction,
        scope: ProcessActionScope,
        processes: [ProcessActionPreviewProcess],
        target: ProcessRow,
        fallbackCommand: String,
        omittedProcessCount: Int
    ) -> [String] {
        var warnings: [String] = []

        if action == .forceStop {
            warnings.append("Force Stop sends SIGKILL and skips graceful shutdown if the process is still alive.")
        }

        let groupMemberCount = processes.filter { $0.role == .groupMember }.count
        if groupMemberCount > 0 {
            warnings.append("This action will signal \(groupMemberCount) additional process-group member\(groupMemberCount == 1 ? "" : "s").")
        }

        let descendantCount = processes.filter { [.child, .descendant].contains($0.role) }.count
        if descendantCount > 0 {
            warnings.append("This action will signal the target process and \(descendantCount) descendant process\(descendantCount == 1 ? "" : "es").")
        }

        if omittedProcessCount > 0 {
            warnings.append("\(omittedProcessCount) additional process\(omittedProcessCount == 1 ? "" : "es") are hidden from this preview.")
        }

        if sanitizedCommand(target.command) != sanitizedCommand(fallbackCommand) {
            warnings.append("The live command differs from the last discovered command; SlayNode will still revalidate before acting.")
        }

        if scope == .singleProcess, target.processGroupID == target.pid {
            warnings.append("The target is its process-group leader.")
        }

        return warnings
    }

    private static func riskLevel(
        action: ServiceAction,
        scope: ProcessActionScope,
        processes: [ProcessActionPreviewProcess],
        omittedProcessCount: Int
    ) -> ProcessActionRiskLevel {
        if scope == .unavailable { return .unknown }
        if action == .forceStop { return .high }
        if omittedProcessCount > 0 { return .elevated }
        if processes.contains(where: { $0.role == .groupMember }) { return .elevated }
        if processes.count > 1 { return .moderate }
        return .low
    }

    private static func sanitizedCommand(_ command: String) -> String {
        ServiceSanitizer.redactSecrets(in: command)
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
