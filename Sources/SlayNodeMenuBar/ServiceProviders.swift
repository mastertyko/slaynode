import AppKit
import Foundation

struct DiscoveryBatch: Sendable {
    var services: [ManagedService]
    var dependencies: [ServiceDependency] = []
}

protocol DiscoveryProvider: Sendable {
    var id: String { get }
    func discoverServices() async -> DiscoveryBatch
}

protocol ControlProvider: Sendable {
    func canControl(_ service: ManagedService) -> Bool
    func supportedActions(for service: ManagedService) -> [ServiceAction]
    func perform(_ action: ServiceAction, on service: ManagedService) async throws -> String
}

enum ServiceControlError: Error, LocalizedError {
    case unsupportedAction(ServiceAction)
    case commandFailed(String)
    case missingRequirement(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedAction(let action):
            return "\(action.title) is not available for this service."
        case .commandFailed(let detail):
            return detail
        case .missingRequirement(let detail):
            return detail
        }
    }
}

actor DiscoveryOrchestrator {
    private let discoveryProviders: [any DiscoveryProvider]
    private let controlProviders: [any ControlProvider]

    init(discoveryProviders: [any DiscoveryProvider], controlProviders: [any ControlProvider]) {
        self.discoveryProviders = discoveryProviders
        self.controlProviders = controlProviders
    }

    func refreshSnapshot() async -> ServiceSnapshot {
        let batches = await withTaskGroup(of: DiscoveryBatch.self) { group in
            for provider in discoveryProviders {
                group.addTask {
                    await provider.discoverServices()
                }
            }

            var collected: [DiscoveryBatch] = []
            for await batch in group {
                collected.append(batch)
            }
            return collected
        }

        var mergedByID: [String: ManagedService] = [:]
        var dependencies: [ServiceDependency] = []

        for batch in batches {
            for service in batch.services {
                mergedByID[service.id] = service
            }
            dependencies.append(contentsOf: batch.dependencies)
        }

        var hydrated: [ManagedService] = mergedByID.values.map { service in
            let actions = mergedAvailableActions(for: service)
            return service.replacing(availableActions: actions)
        }

        hydrated.sort { lhs, rhs in
            if lhs.status != rhs.status {
                return ServiceHeuristics.statusPriority(lhs.status) < ServiceHeuristics.statusPriority(rhs.status)
            }
            if lhs.workspace?.name != rhs.workspace?.name {
                return (lhs.workspace?.name ?? "zzz") < (rhs.workspace?.name ?? "zzz")
            }
            if lhs.kind != rhs.kind {
                return ServiceHeuristics.kindPriority(lhs.kind) < ServiceHeuristics.kindPriority(rhs.kind)
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        dependencies.append(contentsOf: ServiceHeuristics.dependencies(for: hydrated))
        let uniqueDependencies = Dictionary(uniqueKeysWithValues: dependencies.map { ($0.id, $0) }).map(\.value)

        return ServiceSnapshot(
            services: hydrated,
            dependencies: uniqueDependencies.sorted { $0.id < $1.id },
            generatedAt: Date()
        )
    }

    func perform(_ action: ServiceAction, on service: ManagedService) async throws -> String {
        guard let provider = controlProviders.first(where: { $0.canControl(service) && $0.supportedActions(for: service).contains(action) }) else {
            throw ServiceControlError.unsupportedAction(action)
        }

        return try await provider.perform(action, on: service)
    }

    private func mergedAvailableActions(for service: ManagedService) -> [ServiceAction] {
        var actions = Set(service.availableActions)

        for provider in controlProviders where provider.canControl(service) {
            actions.formUnion(provider.supportedActions(for: service))
        }

        return actions.sorted {
            ServiceHeuristics.actionPriority($0) < ServiceHeuristics.actionPriority($1)
        }
    }
}

struct ProcessServiceProvider: DiscoveryProvider, ControlProvider {
    let id = "process-services"

    private let shell: ShellExecuting
    private let portResolver: PortResolver
    private let processKiller: ProcessGroupKiller

    init(
        shell: ShellExecuting = SystemShellExecutor(),
        portResolver: PortResolver = PortResolver(),
        processKiller: ProcessGroupKiller = ProcessGroupKiller()
    ) {
        self.shell = shell
        self.portResolver = portResolver
        self.processKiller = processKiller
    }

    func discoverServices() async -> DiscoveryBatch {
        do {
            let (status, output) = try await shell.run(
                Constants.Path.ps,
                arguments: ["-axo", "pid=,ppid=,etime=,command="],
                timeout: Constants.Timeout.commandTimeout
            )
            guard status == 0 else { return DiscoveryBatch(services: []) }

            let processes = output
                .split(whereSeparator: \.isNewline)
                .compactMap { parseProcess(from: String($0)) }

            guard !processes.isEmpty else {
                return DiscoveryBatch(services: [])
            }

            let portsByPid = await portResolver.resolvePorts(for: processes.map(\.pid))
            let candidatePids = processes
                .filter { process in
                    let resolvedPorts = portsByPid[process.pid] ?? []
                    return ServiceHeuristics.isInterestingProcess(
                        executable: process.executable,
                        command: process.command,
                        descriptor: process.descriptor,
                        ports: resolvedPorts
                    )
                }
                .map(\.pid)

            let workingDirectories = await resolveWorkingDirectories(for: candidatePids)

            let services = processes.compactMap { process -> ManagedService? in
                let resolvedPorts = Set(process.ports + (portsByPid[process.pid] ?? []))
                return ServiceHeuristics.makeProcessService(
                    from: process,
                    ports: Array(resolvedPorts).sorted(),
                    workingDirectory: workingDirectories[process.pid] ?? process.workingDirectory
                )
            }

            return DiscoveryBatch(services: services)
        } catch {
            Log.process.error("Process service discovery failed: \(error.localizedDescription)")
            return DiscoveryBatch(services: [])
        }
    }

    func canControl(_ service: ManagedService) -> Bool {
        if case .process = service.source {
            return true
        }
        return false
    }

    func supportedActions(for service: ManagedService) -> [ServiceAction] {
        guard canControl(service) else { return [] }
        return service.availableActions.filter {
            [.stop, .forceStop].contains($0)
        }
    }

    func perform(_ action: ServiceAction, on service: ManagedService) async throws -> String {
        guard case .process(let pid, _) = service.source else {
            throw ServiceControlError.unsupportedAction(action)
        }

        switch action {
        case .stop:
            try await processKiller.terminateGroup(pid: pid, gracePeriod: Constants.Timeout.gracePeriod)
            return "Stopped \(service.name)."
        case .forceStop:
            try forceTerminate(pid: pid)
            return "Force stopped \(service.name)."
        default:
            throw ServiceControlError.unsupportedAction(action)
        }
    }

    private func parseProcess(from line: String) -> NodeProcess? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let components = trimmed.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard components.count == 4,
              let pidValue = Int32(components[0]),
              let ppidValue = Int32(components[1]) else {
            return nil
        }

        let elapsedSeconds = parseEtime(String(components[2]))
        guard elapsedSeconds > 0 else { return nil }

        let command = String(components[3])
        let tokens = CommandParser.tokenize(command)
        guard let executableToken = tokens.first else { return nil }

        let arguments = Array(tokens.dropFirst())
        let inferredPorts = CommandParser.inferPorts(from: tokens)
        let inferredWorkingDirectory = CommandParser.inferWorkingDirectory(from: arguments)
        let context = CommandParser.makeContext(
            executable: executableToken,
            tokens: tokens,
            workingDirectory: inferredWorkingDirectory
        )

        return NodeProcess(
            pid: pidValue,
            ppid: ppidValue,
            executable: executableToken,
            command: command,
            arguments: arguments,
            ports: inferredPorts,
            uptime: elapsedSeconds,
            startTime: Date().addingTimeInterval(-elapsedSeconds),
            workingDirectory: inferredWorkingDirectory,
            descriptor: CommandParser.descriptor(from: context),
            commandHash: command.hashValue
        )
    }

    private func resolveWorkingDirectories(for pids: [Int32]) async -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }

        let pidList = pids.map(String.init).joined(separator: ",")
        do {
            let (status, output) = try await shell.run(
                Constants.Path.lsof,
                arguments: ["-a", "-d", "cwd", "-Fn", "-p", pidList],
                timeout: Constants.Timeout.commandTimeout
            )

            guard status == 0 else { return [:] }

            var currentPid: Int32?
            var result: [Int32: String] = [:]

            for rawLine in output.split(whereSeparator: \.isNewline) {
                let line = String(rawLine)
                guard let prefix = line.first else { continue }

                switch prefix {
                case "p":
                    currentPid = Int32(line.dropFirst())
                case "n":
                    guard let currentPid, result[currentPid] == nil else { continue }
                    let path = String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !path.isEmpty {
                        result[currentPid] = path
                    }
                default:
                    continue
                }
            }

            return result
        } catch {
            Log.process.warning("Working-directory resolution failed: \(error.localizedDescription)")
            return [:]
        }
    }

    private func forceTerminate(pid: Int32) throws {
        guard pid > 0 else {
            throw ServiceControlError.commandFailed("Invalid process id.")
        }

        let processGroup = getpgid(pid)
        if processGroup > 0 {
            if kill(-processGroup, SIGKILL) != 0 && errno != ESRCH {
                throw ServiceControlError.commandFailed("Could not force stop PID \(pid) (errno: \(errno)).")
            }
        } else if kill(pid, SIGKILL) != 0 && errno != ESRCH {
            throw ServiceControlError.commandFailed("Could not force stop PID \(pid) (errno: \(errno)).")
        }
    }

    private func parseEtime(_ etime: String) -> TimeInterval {
        if etime.contains("-") {
            let components = etime.split(separator: "-")
            guard components.count == 2 else { return 0 }
            let days = TimeInterval(components[0]) ?? 0
            let parts = components[1].split(separator: ":")
            guard parts.count == 3 else { return 0 }
            return days * 86_400
                + (TimeInterval(parts[0]) ?? 0) * 3_600
                + (TimeInterval(parts[1]) ?? 0) * 60
                + (TimeInterval(parts[2]) ?? 0)
        }

        let parts = etime.split(separator: ":")
        switch parts.count {
        case 1:
            return TimeInterval(parts[0]) ?? 0
        case 2:
            return (TimeInterval(parts[0]) ?? 0) * 60 + (TimeInterval(parts[1]) ?? 0)
        case 3:
            return (TimeInterval(parts[0]) ?? 0) * 3_600
                + (TimeInterval(parts[1]) ?? 0) * 60
                + (TimeInterval(parts[2]) ?? 0)
        default:
            return 0
        }
    }
}

struct DockerServiceProvider: DiscoveryProvider, ControlProvider {
    let id = "docker-services"

    private let shell: ShellExecuting

    init(shell: ShellExecuting = SystemShellExecutor()) {
        self.shell = shell
    }

    func discoverServices() async -> DiscoveryBatch {
        guard let rows = await dockerRows() else {
            return DiscoveryBatch(services: [])
        }

        var services: [ManagedService] = []

        for row in rows where !row.id.isEmpty {
            let inspection = await inspect(containerID: row.id)
            let mounts = inspection.mounts
            let workspace = ServiceHeuristics.workspaceIdentity(from: mounts.first(where: { $0.type == "bind" })?.source)
            let kind = ServiceHeuristics.classifyContainer(name: row.name, image: row.image)
            let hostPorts = ServiceHeuristics.parseDockerPorts(row.ports).map { ServicePort(value: $0, isInferred: false) }
            let status = row.status.lowercased().contains("up") ? (row.status.lowercased().contains("unhealthy") ? ManagedServiceStatus.degraded : .running) : .stopped
            let health: ServiceHealth = row.status.lowercased().contains("unhealthy") ? .critical : (status == .running ? .healthy : .passive)
            let summary = row.image + (row.status.isEmpty ? "" : " • \(row.status)")
            let actions: [ServiceAction] = hostPorts.isEmpty ? [.stop, .restart, .openLogs] : [.stop, .restart, .openLogs, .openWorkspace]

            services.append(
                ManagedService(
                    id: ServiceSource.docker(containerID: row.id, image: row.image).id,
                    name: row.name,
                    kind: kind,
                    status: status,
                    health: health,
                    source: .docker(containerID: row.id, image: row.image),
                    workspace: workspace,
                    ports: hostPorts,
                    runtime: row.image,
                    summary: summary,
                    command: nil,
                    configPath: mounts.first(where: { $0.type == "bind" })?.source,
                    logPath: inspection.logPath,
                    tags: ["docker", row.image],
                    availableActions: actions,
                    startedAt: nil,
                    lastSeenAt: Date()
                )
            )
        }

        return DiscoveryBatch(services: services)
    }

    func canControl(_ service: ManagedService) -> Bool {
        if case .docker = service.source {
            return true
        }
        return false
    }

    func supportedActions(for service: ManagedService) -> [ServiceAction] {
        guard case .docker = service.source else { return [] }
        return [.stop, .forceStop, .restart, .openLogs]
    }

    func perform(_ action: ServiceAction, on service: ManagedService) async throws -> String {
        guard case .docker(let containerID, _) = service.source else {
            throw ServiceControlError.unsupportedAction(action)
        }

        switch action {
        case .stop:
            _ = try await runDocker(["stop", containerID])
            return "Stopped \(service.name)."
        case .forceStop:
            _ = try await runDocker(["kill", containerID])
            return "Force stopped \(service.name)."
        case .restart:
            _ = try await runDocker(["restart", containerID])
            return "Restarted \(service.name)."
        case .openLogs:
            let logs = try await runDocker(["logs", "--tail", "200", containerID], allowFailure: true)
            let tempURL = try writeTemporaryLog(named: service.name, content: logs)
            _ = await MainActor.run {
                NSWorkspace.shared.open(tempURL)
            }
            return "Opened logs for \(service.name)."
        default:
            throw ServiceControlError.unsupportedAction(action)
        }
    }

    private func dockerRows() async -> [DockerRow]? {
        do {
            let output = try await runDocker(["ps", "--format", "{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}"], allowFailure: true)
            return output
                .split(whereSeparator: \.isNewline)
                .map { line in
                    let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                    return DockerRow(
                        id: parts.indices.contains(0) ? parts[0] : "",
                        name: parts.indices.contains(1) ? parts[1] : "",
                        image: parts.indices.contains(2) ? parts[2] : "",
                        ports: parts.indices.contains(3) ? parts[3] : "",
                        status: parts.indices.contains(4) ? parts[4] : ""
                    )
                }
        } catch {
            Log.process.info("Docker discovery unavailable: \(error.localizedDescription)")
            return nil
        }
    }

    private func inspect(containerID: String) async -> DockerInspection {
        do {
            let output = try await runDocker(
                ["inspect", "--format", "{{json .Mounts}}@@{{.LogPath}}", containerID],
                allowFailure: true
            )
            let parts = output.components(separatedBy: "@@")
            let mountsData = Data((parts.first ?? "[]").utf8)
            let mounts = (try? JSONDecoder().decode([DockerMount].self, from: mountsData)) ?? []
            let logPath = parts.indices.contains(1) ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil
            return DockerInspection(mounts: mounts, logPath: logPath?.isEmpty == true ? nil : logPath)
        } catch {
            return DockerInspection(mounts: [], logPath: nil)
        }
    }

    private func runDocker(_ arguments: [String], allowFailure: Bool = false) async throws -> String {
        let (status, output) = try await shell.run(
            "/usr/bin/env",
            arguments: ["docker"] + arguments,
            timeout: Constants.Timeout.commandTimeout
        )
        if status != 0 && !allowFailure {
            throw ServiceControlError.commandFailed("Docker command failed: docker \(arguments.joined(separator: " "))")
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func writeTemporaryLog(named name: String, content: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let filename = "slaynode-\(name.replacingOccurrences(of: " ", with: "-").lowercased())-logs.txt"
        let fileURL = directory.appendingPathComponent(filename)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private struct DockerRow: Sendable {
        let id: String
        let name: String
        let image: String
        let ports: String
        let status: String
    }

    private struct DockerMount: Codable, Sendable {
        let type: String
        let source: String?

        enum CodingKeys: String, CodingKey {
            case type = "Type"
            case source = "Source"
        }
    }

    private struct DockerInspection: Sendable {
        let mounts: [DockerMount]
        let logPath: String?
    }
}

struct BrewServiceProvider: DiscoveryProvider, ControlProvider {
    let id = "brew-services"

    private let shell: ShellExecuting

    init(shell: ShellExecuting = SystemShellExecutor()) {
        self.shell = shell
    }

    func discoverServices() async -> DiscoveryBatch {
        do {
            let output = try await runBrew(["services", "list", "--json"], allowFailure: true)
            guard !output.isEmpty else { return DiscoveryBatch(services: []) }

            let services = try JSONDecoder().decode([BrewRow].self, from: Data(output.utf8))
                .compactMap { row -> ManagedService? in
                    guard row.status.lowercased() != "none" else { return nil }

                    let kind = ServiceHeuristics.classifyBrewService(name: row.name)
                    let status: ManagedServiceStatus
                    let health: ServiceHealth

                    switch row.status.lowercased() {
                    case "started", "running", "scheduled":
                        status = .running
                        health = .healthy
                    case "error":
                        status = .degraded
                        health = .critical
                    default:
                        status = .stopped
                        health = .passive
                    }

                    return ManagedService(
                        id: ServiceSource.brewService(name: row.name, plistPath: row.file).id,
                        name: row.name,
                        kind: kind,
                        status: status,
                        health: health,
                        source: .brewService(name: row.name, plistPath: row.file),
                        workspace: nil,
                        ports: [],
                        runtime: "Homebrew Services",
                        summary: "Managed by Homebrew Services",
                        command: nil,
                        configPath: row.file,
                        logPath: nil,
                        tags: ["brew", row.status],
                        availableActions: [.stop, .restart, .revealConfig],
                        startedAt: nil,
                        lastSeenAt: Date()
                    )
                }

            return DiscoveryBatch(services: services)
        } catch {
            Log.process.info("Homebrew service discovery unavailable: \(error.localizedDescription)")
            return DiscoveryBatch(services: [])
        }
    }

    func canControl(_ service: ManagedService) -> Bool {
        if case .brewService = service.source {
            return true
        }
        return false
    }

    func supportedActions(for service: ManagedService) -> [ServiceAction] {
        guard case .brewService = service.source else { return [] }
        return [.stop, .restart]
    }

    func perform(_ action: ServiceAction, on service: ManagedService) async throws -> String {
        guard case .brewService(let name, _) = service.source else {
            throw ServiceControlError.unsupportedAction(action)
        }

        switch action {
        case .stop:
            _ = try await runBrew(["services", "stop", name])
            return "Stopped \(service.name)."
        case .restart:
            _ = try await runBrew(["services", "restart", name])
            return "Restarted \(service.name)."
        default:
            throw ServiceControlError.unsupportedAction(action)
        }
    }

    private func runBrew(_ arguments: [String], allowFailure: Bool = false) async throws -> String {
        let (status, output) = try await shell.run(
            "/usr/bin/env",
            arguments: ["brew"] + arguments,
            timeout: Constants.Timeout.commandTimeout
        )

        if status != 0 && !allowFailure {
            throw ServiceControlError.commandFailed("brew \(arguments.joined(separator: " ")) failed.")
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct BrewRow: Codable, Sendable {
        let name: String
        let status: String
        let user: String?
        let file: String?
    }
}

enum ServiceHeuristics {
    static func statusPriority(_ status: ManagedServiceStatus) -> Int {
        switch status {
        case .degraded: return 0
        case .running: return 1
        case .stopped: return 2
        case .unavailable: return 3
        }
    }

    static func kindPriority(_ kind: ServiceKind) -> Int {
        switch kind {
        case .app: return 0
        case .api: return 1
        case .database: return 2
        case .cache: return 3
        case .queue: return 4
        case .proxy: return 5
        case .worker: return 6
        case .container: return 7
        case .runtime: return 8
        case .tool: return 9
        case .unknown: return 10
        }
    }

    static func actionPriority(_ action: ServiceAction) -> Int {
        switch action {
        case .stop: return 0
        case .forceStop: return 1
        case .restart: return 2
        case .openWorkspace: return 3
        case .openLogs: return 4
        case .revealConfig: return 5
        }
    }

    static func isInterestingProcess(
        executable: String,
        command: String,
        descriptor: ServerDescriptor,
        ports: [Int]
    ) -> Bool {
        let executableLower = executable.lowercased()
        let commandLower = command.lowercased()

        if isSystemOrBundleProcess(executable: executableLower, command: commandLower) {
            return false
        }

        if !ports.isEmpty {
            return true
        }

        if !descriptor.portHints.isEmpty {
            return true
        }

        switch descriptor.category {
        case .webFramework, .bundler, .componentWorkbench, .mobile, .backend, .monorepo:
            return true
        case .utility:
            return containsServiceSignals(command: commandLower, executable: executableLower)
        case .runtime:
            return containsServiceRuntimeSignals(command: commandLower, executable: executableLower)
        }
    }

    static func makeProcessService(
        from process: NodeProcess,
        ports: [Int],
        workingDirectory: String?
    ) -> ManagedService? {
        guard isInterestingProcess(
            executable: process.executable,
            command: process.command,
            descriptor: process.descriptor,
            ports: ports
        ) else {
            return nil
        }

        let workspace = workspaceIdentity(from: workingDirectory)
        let kind = classifyProcessKind(process: process, ports: ports)
        let status: ManagedServiceStatus = ports.isEmpty ? .degraded : .running
        let health: ServiceHealth = ports.isEmpty ? .watch : .healthy
        let runtime = process.descriptor.runtime ?? inferRuntime(from: process.command)
        let configPath = configPath(for: process, workingDirectory: workingDirectory)
        var actions: [ServiceAction] = [.stop, .forceStop]

        if workspace != nil {
            actions.append(.openWorkspace)
        }

        if configPath != nil {
            actions.append(.revealConfig)
        }

        let sanitizedCommand = ServiceSanitizer.redactSecrets(in: process.command)
        let summary = ServiceSanitizer.redactSecrets(in: summaryForProcess(process, kind: kind, ports: ports))
        let displayName = serviceDisplayName(for: process, kind: kind, workspace: workspace)

        return ManagedService(
            id: ServiceSource.process(pid: process.pid, command: process.command).id,
            name: displayName,
            kind: kind,
            status: status,
            health: health,
            source: .process(pid: process.pid, command: sanitizedCommand),
            workspace: workspace,
            ports: ports.map { ServicePort(value: $0, isInferred: false) },
            runtime: runtime,
            summary: summary,
            command: sanitizedCommand,
            configPath: configPath,
            logPath: nil,
            tags: tags(for: process, kind: kind, runtime: runtime),
            availableActions: actions,
            startedAt: process.startTime,
            lastSeenAt: Date()
        )
    }

    static func workspaceIdentity(from path: String?) -> WorkspaceIdentity? {
        guard let canonicalPath = canonicalWorkspaceRoot(from: path) else { return nil }
        let name = URL(fileURLWithPath: canonicalPath).lastPathComponent
        let title = name.isEmpty ? canonicalPath : name
        return WorkspaceIdentity(id: canonicalPath.lowercased(), name: title, rootPath: canonicalPath)
    }

    static func classifyContainer(name: String, image: String) -> ServiceKind {
        classifyTokens([name.lowercased(), image.lowercased()])
    }

    static func classifyBrewService(name: String) -> ServiceKind {
        classifyTokens([name.lowercased()])
    }

    static func parseDockerPorts(_ value: String) -> [Int] {
        guard !value.isEmpty else { return [] }
        let pattern = #"[:](\d+)->"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: value.utf16.count)
        let matches = regex?.matches(in: value, range: range) ?? []
        let ports = matches.compactMap { match -> Int? in
            guard let range = Range(match.range(at: 1), in: value) else { return nil }
            return Int(value[range])
        }
        return Array(Set(ports)).sorted()
    }

    static func dependencies(for services: [ManagedService]) -> [ServiceDependency] {
        let grouped = Dictionary(grouping: services.compactMap { service -> (WorkspaceIdentity, ManagedService)? in
            guard let workspace = service.workspace else { return nil }
            return (workspace, service)
        }) { $0.0 }

        var dependencies: [ServiceDependency] = []

        for (workspace, pairs) in grouped {
            let services = pairs.map(\.1)
            let applicationServices = services.filter { [.app, .api, .worker].contains($0.kind) }
            let infraServices = services.filter { [.database, .cache, .queue, .proxy].contains($0.kind) }

            for application in applicationServices {
                for infra in infraServices where infra.id != application.id {
                    dependencies.append(
                        ServiceDependency(
                            id: "\(application.id)->\(infra.id)",
                            sourceID: application.id,
                            targetID: infra.id,
                            label: "Shares \(workspace.name)"
                        )
                    )
                }
            }
        }

        return dependencies
    }

    private static func classifyProcessKind(process: NodeProcess, ports: [Int]) -> ServiceKind {
        switch process.descriptor.category {
        case .webFramework, .bundler, .componentWorkbench, .mobile:
            return .app
        case .backend:
            return .api
        case .monorepo:
            return .tool
        case .utility:
            return classifyTokens([process.executable.lowercased(), process.command.lowercased()])
        case .runtime:
            if !ports.isEmpty {
                let tokenKind = classifyTokens([process.executable.lowercased(), process.command.lowercased()])
                return tokenKind == .unknown ? .runtime : tokenKind
            }
            return .runtime
        }
    }

    private static func canonicalWorkspaceRoot(from path: String?) -> String? {
        guard let path, !path.isEmpty, path != "/" else { return nil }

        var normalized = URL(fileURLWithPath: path).standardized.path
        if normalized.hasSuffix("/") {
            normalized.removeLast()
        }

        if let nodeModulesRange = normalized.range(of: "/node_modules/") {
            normalized = String(normalized[..<nodeModulesRange.lowerBound])
        }

        guard !normalized.isEmpty, normalized != "/" else { return nil }
        return normalized
    }

    private static func classifyTokens(_ values: [String]) -> ServiceKind {
        let haystack = values.joined(separator: " ")

        if databaseKeywords.contains(where: haystack.contains) { return .database }
        if cacheKeywords.contains(where: haystack.contains) { return .cache }
        if queueKeywords.contains(where: haystack.contains) { return .queue }
        if proxyKeywords.contains(where: haystack.contains) { return .proxy }
        if workerKeywords.contains(where: haystack.contains) { return .worker }
        if runtimeKeywords.contains(where: haystack.contains) { return .runtime }

        if haystack.contains("api") || haystack.contains("backend") || haystack.contains("server") {
            return .api
        }

        if haystack.contains("web") || haystack.contains("frontend") || haystack.contains("vite") || haystack.contains("next") {
            return .app
        }

        if haystack.contains("docker") {
            return .container
        }

        return .unknown
    }

    private static func serviceDisplayName(
        for process: NodeProcess,
        kind: ServiceKind,
        workspace: WorkspaceIdentity?
    ) -> String {
        if let script = process.descriptor.script, !script.isEmpty {
            if let workspace,
               genericScriptNames.contains(script.lowercased()),
               workspace.name != "/" {
                return workspace.name
            }

            return script
        }

        if process.descriptor.displayName != "Node.js" {
            return process.descriptor.displayName
        }

        let executable = process.executable
        if kind == .database, executable.lowercased().contains("postgres") {
            return "PostgreSQL"
        }
        if kind == .cache, executable.lowercased().contains("redis") {
            return "Redis"
        }

        if let workspace,
           genericProcessNames.contains(executable.lowercased()),
           workspace.name != "/" {
            return workspace.name
        }

        return executable
    }

    private static func summaryForProcess(_ process: NodeProcess, kind: ServiceKind, ports: [Int]) -> String {
        if !ports.isEmpty {
            let portsLabel = ports.map(String.init).joined(separator: ", ")
            return "\(kind.title) listening on \(portsLabel)"
        }

        if let details = process.descriptor.details, !details.isEmpty {
            return details
        }

        return process.command
    }

    private static func configPath(for process: NodeProcess, workingDirectory: String?) -> String? {
        if let script = CommandParser.firstScriptToken(from: [process.executable] + process.arguments) {
            let expanded = (script as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                return expanded
            }
        }

        guard let workingDirectory else { return nil }
        let packagePath = URL(fileURLWithPath: workingDirectory).appendingPathComponent("package.json").path
        if FileManager.default.fileExists(atPath: packagePath) {
            return packagePath
        }
        return nil
    }

    private static func tags(for process: NodeProcess, kind: ServiceKind, runtime: String?) -> [String] {
        var tags = [kind.title, "process"]
        if let runtime {
            tags.append(runtime)
        }
        if let packageManager = process.descriptor.packageManager {
            tags.append(packageManager)
        }
        return Array(Set(tags)).sorted()
    }

    private static func inferRuntime(from command: String) -> String? {
        let lowered = command.lowercased()
        if lowered.contains("bun") { return "Bun" }
        if lowered.contains("deno") { return "Deno" }
        if lowered.contains("python") || lowered.contains("uvicorn") || lowered.contains("gunicorn") {
            return "Python"
        }
        if lowered.contains("ruby") || lowered.contains("rails") || lowered.contains("puma") {
            return "Ruby"
        }
        if lowered.contains("go ") || lowered.contains("/go") || lowered.contains("air ") {
            return "Go"
        }
        if lowered.contains("node") || lowered.contains("vite") || lowered.contains("next") {
            return "Node.js"
        }
        return nil
    }

    private static func containsServiceSignals(command: String, executable: String) -> Bool {
        let keywords = databaseKeywords + cacheKeywords + queueKeywords + proxyKeywords + workerKeywords + serviceRuntimeKeywords
        return keywords.contains { command.contains($0) || executable.contains($0) }
    }

    private static func containsServiceRuntimeSignals(command: String, executable: String) -> Bool {
        let keywords = serviceRuntimeKeywords + databaseKeywords + cacheKeywords + queueKeywords + proxyKeywords + workerKeywords
        return keywords.contains { command.contains($0) || executable.contains($0) }
    }

    private static func isSystemOrBundleProcess(executable: String, command: String) -> Bool {
        if command.hasPrefix("/system/") ||
            command.hasPrefix("/usr/sbin/") ||
            command.hasPrefix("/usr/libexec/") ||
            command.hasPrefix("/library/") ||
            command.hasPrefix("/sbin/") {
            return true
        }

        if command.contains(".app/contents/") {
            return true
        }

        if command.contains("node.mojom.nodeservice") ||
            command.contains("--type=utility") ||
            command.contains("--type=renderer") ||
            command.contains("--type=gpu-process") {
            return true
        }

        if command.contains("/typescript/lib/tsserver.js") ||
            command.contains("/typescript/lib/typingsinstaller.js") ||
            command.contains("typescript-language-server") ||
            command.contains("esbuild --service=") ||
            command.contains("browser_use.skill_cli.daemon") ||
            command.contains("gitstatusd") ||
            command.contains("sourcekit-lsp") ||
            executable.contains("tsserver") {
            return true
        }

        if executable.contains("slaynodemenuba") || command.contains("slaynodemenuba") {
            return true
        }

        return false
    }

    private static let runtimeKeywords = [
        "node", "bun", "deno", "python", "uvicorn", "gunicorn", "flask", "django",
        "rails", "puma", "go ", "air ", "vite", "next", "nuxt", "astro", "remix"
    ]

    private static let serviceRuntimeKeywords = [
        "air ",
        "astro",
        "backend",
        "django",
        "flask",
        "gunicorn",
        "http.server",
        "next",
        "nuxt",
        "puma",
        "rails",
        "remix",
        "server.js",
        "storybook",
        "uvicorn",
        "vite"
    ]

    private static let genericScriptNames: Set<String> = [
        "dev",
        "preview",
        "serve",
        "start",
        "watch"
    ]

    private static let genericProcessNames: Set<String> = [
        "bash",
        "bun",
        "deno",
        "node",
        "npm",
        "pnpm",
        "python",
        "python3",
        "ruby",
        "sh",
        "yarn",
        "zsh"
    ]

    private static let databaseKeywords = [
        "postgres", "postmaster", "mysql", "mariadb", "redis", "valkey", "mongo",
        "mongodb", "surrealdb", "clickhouse", "elasticsearch"
    ]

    private static let cacheKeywords = [
        "redis", "valkey", "memcached", "dragonfly"
    ]

    private static let queueKeywords = [
        "rabbitmq", "kafka", "nats", "bullmq", "sidekiq"
    ]

    private static let proxyKeywords = [
        "nginx", "caddy", "traefik", "haproxy", "envoy"
    ]

    private static let workerKeywords = [
        "sidekiq", "celery", "worker", "resque", "rq", "job"
    ]
}

private extension ManagedService {
    func replacing(availableActions: [ServiceAction]) -> ManagedService {
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
}
