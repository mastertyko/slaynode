import Foundation

struct ProcessDiscovery: Sendable {
    private let shell: any ShellExecuting
    private let portResolver: PortResolver
    private let pidQueryBatchSize: Int

    init(
        shell: any ShellExecuting = SystemShellExecutor(),
        portResolver: PortResolver = PortResolver(),
        pidQueryBatchSize: Int = Constants.Buffer.maxPIDQueryBatchSize
    ) {
        self.shell = shell
        self.portResolver = portResolver
        self.pidQueryBatchSize = max(1, pidQueryBatchSize)
    }

    func discoverProcesses() async -> [NodeProcess] {
        do {
            let (psStatus, psOutput) = try await runCommand(
                Constants.Path.ps,
                arguments: ["-axo", "pid=,ppid=,etime=,command="]
            )

            guard psStatus == 0 else {
                return []
            }

            let rows = psOutput.split(whereSeparator: \.isNewline)
            var processes: [NodeProcess] = []
            processes.reserveCapacity(min(rows.count, Constants.Buffer.maxProcessCount))

            for row in rows {
                guard let process = Self.parseProcessLine(String(row)) else { continue }
                processes.append(process)
            }

            return await enrichProcesses(processes)
        } catch {
            Log.process.error("Process discovery failed: \(error.localizedDescription)")
            return []
        }
    }

    func verifyProcess(pid: Int32, expectedHash: Int) async -> Bool {
        guard pid > 0,
              let currentCommand = await fetchCommandLine(for: pid) else {
            return false
        }
        return NodeProcess.stableCommandHash(for: currentCommand) == expectedHash
    }

    static func parseProcessLine(_ line: String, now: Date = Date()) -> NodeProcess? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let components = trimmed.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard components.count == 4,
              let pidValue = Int32(components[0]),
              let ppidValue = Int32(components[1]) else {
            return nil
        }

        guard let elapsedSeconds = parseValidEtime(String(components[2])) else { return nil }

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
            startTime: now.addingTimeInterval(-elapsedSeconds),
            workingDirectory: inferredWorkingDirectory,
            descriptor: CommandParser.descriptor(from: context),
            commandHash: NodeProcess.stableCommandHash(for: command)
        )
    }

    static func parseEtime(_ etime: String) -> TimeInterval {
        parseValidEtime(etime) ?? 0
    }

    private static func parseValidEtime(_ etime: String) -> TimeInterval? {
        if etime.contains("-") {
            let components = etime.split(separator: "-")
            guard components.count == 2,
                  let days = parseNonNegativeComponent(components[0]) else { return nil }

            let timeComponents = components[1].split(separator: ":")
            guard timeComponents.count == 3 else { return nil }

            guard let hours = parseNonNegativeComponent(timeComponents[0]),
                  let minutes = parseNonNegativeComponent(timeComponents[1]),
                  let seconds = parseNonNegativeComponent(timeComponents[2]) else {
                return nil
            }
            guard hours < 24, minutes < 60, seconds < 60 else { return nil }

            return days * Constants.Time.secondsPerDay
                + hours * Constants.Time.secondsPerHour
                + minutes * Constants.Time.secondsPerMinute
                + seconds
        }

        let parts = etime.split(separator: ":")
        switch parts.count {
        case 1:
            return parseNonNegativeComponent(parts[0])
        case 2:
            guard let minutes = parseNonNegativeComponent(parts[0]),
                  let seconds = parseNonNegativeComponent(parts[1]) else {
                return nil
            }
            guard seconds < 60 else { return nil }
            return minutes * Constants.Time.secondsPerMinute + seconds
        case 3:
            guard let hours = parseNonNegativeComponent(parts[0]),
                  let minutes = parseNonNegativeComponent(parts[1]),
                  let seconds = parseNonNegativeComponent(parts[2]) else {
                return nil
            }
            guard minutes < 60, seconds < 60 else { return nil }
            return hours * Constants.Time.secondsPerHour
                + minutes * Constants.Time.secondsPerMinute
                + seconds
        default:
            return nil
        }
    }

    private static func parseNonNegativeComponent(_ value: Substring) -> TimeInterval? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.allSatisfy(\.isNumber),
              let component = TimeInterval(trimmed),
              component >= 0 else {
            return nil
        }
        return component
    }

    static func parseWorkingDirectories(from output: String) -> [Int32: String] {
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
                let path = sanitizedWorkingDirectoryPath(from: String(line.dropFirst()))
                if !path.isEmpty {
                    result[currentPid] = path
                }
            default:
                continue
            }
        }

        return result
    }

    private static func sanitizedWorkingDirectoryPath(from rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let deletedSuffix = " (deleted)"
        if trimmed.hasSuffix(deletedSuffix) {
            return String(trimmed.dropLast(deletedSuffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    private func enrichProcesses(_ processes: [NodeProcess]) async -> [NodeProcess] {
        let candidateProcesses = processes.filter(Self.isPotentialDevelopmentProcess(_:))

        guard !candidateProcesses.isEmpty else {
            return []
        }

        let candidatePids = candidateProcesses.map(\.pid)
        let portsByPid = await portResolver.resolvePorts(for: candidatePids)
        let workingDirectoriesByPid = await resolveWorkingDirectories(for: candidatePids)
        let processByPid = Dictionary(uniqueKeysWithValues: candidateProcesses.map { ($0.pid, $0) })
        let childrenByParentPid = Dictionary(grouping: candidateProcesses.filter { processByPid[$0.ppid] != nil }) { $0.ppid }

        var childPortsByParentPid: [Int32: [Int]] = [:]
        var hiddenChildPids: Set<Int32> = []

        for process in candidateProcesses {
            let childPorts = portsByPid[process.pid] ?? []
            if !childPorts.isEmpty, process.ppid > 1, processByPid[process.ppid] != nil {
                childPortsByParentPid[process.ppid, default: []].append(contentsOf: childPorts)
                hiddenChildPids.insert(process.pid)
            }
        }

        var promotedChildByParentPid: [Int32: NodeProcess] = [:]

        for process in candidateProcesses {
            guard let children = childrenByParentPid[process.pid],
                  let promotedChild = Self.preferredPromotedChild(
                    for: process,
                    children: children,
                    portsByPid: portsByPid,
                    childPortsByParentPid: childPortsByParentPid
                  ) else {
                continue
            }

            promotedChildByParentPid[process.pid] = promotedChild
            hiddenChildPids.insert(promotedChild.pid)
        }

        var result: [NodeProcess] = []

        for process in candidateProcesses {
            if hiddenChildPids.contains(process.pid) {
                continue
            }

            var allPorts = Set(process.ports + (portsByPid[process.pid] ?? []))
            var descriptor = process.descriptor
            var workingDirectory = process.workingDirectory ?? workingDirectoriesByPid[process.pid]

            if let childPorts = childPortsByParentPid[process.pid] {
                allPorts.formUnion(childPorts)
            }

            if let promotedChild = promotedChildByParentPid[process.pid] {
                allPorts.formUnion(promotedChild.ports)
                if let promotedPorts = childPortsByParentPid[promotedChild.pid] {
                    allPorts.formUnion(promotedPorts)
                }
                if let resolvedChildPorts = portsByPid[promotedChild.pid] {
                    allPorts.formUnion(resolvedChildPorts)
                }
                descriptor = Self.promotedDescriptor(parent: process.descriptor, child: promotedChild.descriptor)
                workingDirectory = promotedChild.workingDirectory ?? workingDirectoriesByPid[promotedChild.pid] ?? workingDirectory
            }

            let enrichedProcess = NodeProcess(
                pid: process.pid,
                ppid: process.ppid,
                executable: process.executable,
                command: process.command,
                arguments: process.arguments,
                ports: Array(allPorts).sorted(),
                uptime: process.uptime,
                startTime: process.startTime,
                workingDirectory: workingDirectory,
                descriptor: descriptor,
                commandHash: process.commandHash
            )

            guard Self.shouldDisplayProcess(enrichedProcess) else {
                continue
            }

            result.append(enrichedProcess)
        }

        return result
    }

    private static func preferredPromotedChild(
        for parent: NodeProcess,
        children: [NodeProcess],
        portsByPid: [Int32: [Int]],
        childPortsByParentPid: [Int32: [Int]]
    ) -> NodeProcess? {
        guard parent.descriptor.packageManager != nil else {
            return nil
        }

        return children
            .map { child in
                (
                    child,
                    promotionScore(
                        for: child,
                        portsByPid: portsByPid,
                        childPortsByParentPid: childPortsByParentPid
                    )
                )
            }
            .filter { $0.1 > 0 }
            .max { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 < rhs.1
                }
                return lhs.0.pid < rhs.0.pid
            }?
            .0
    }

    private static func promotionScore(
        for process: NodeProcess,
        portsByPid: [Int32: [Int]],
        childPortsByParentPid: [Int32: [Int]]
    ) -> Int {
        let directPorts = portsByPid[process.pid] ?? []
        let descendantPorts = childPortsByParentPid[process.pid] ?? []
        let totalPorts = Set(process.ports + directPorts + descendantPorts)

        var score = 0

        if !totalPorts.isEmpty {
            score += 100
        }

        switch process.descriptor.category {
        case .webFramework:
            score += 60
        case .bundler:
            score += 55
        case .backend:
            score += 50
        case .componentWorkbench:
            score += 45
        case .mobile:
            score += 40
        case .monorepo:
            score += 30
        case .utility:
            score += 25
        case .runtime:
            score += 10
        }

        if process.descriptor.packageManager == nil {
            score += 20
        }

        if process.command.lowercased().contains("node_modules/.bin/") {
            score += 15
        }

        let normalizedName = process.descriptor.displayName.lowercased()
        if normalizedName == "node.js" || normalizedName == "node" {
            score -= 20
        }

        return score
    }

    private static func promotedDescriptor(parent: ServerDescriptor, child: ServerDescriptor) -> ServerDescriptor {
        ServerDescriptor(
            name: child.name,
            displayName: child.displayName,
            category: child.category,
            runtime: child.runtime ?? parent.runtime,
            packageManager: parent.packageManager ?? child.packageManager,
            script: child.script ?? parent.script,
            details: child.details ?? parent.details,
            portHints: child.portHints.isEmpty ? parent.portHints : child.portHints
        )
    }

    private static func isPotentialDevelopmentProcess(_ process: NodeProcess) -> Bool {
        let executableLower = process.executable.lowercased()
        let commandLower = process.command.lowercased()

        if isSystemOrAppBundleProcess(command: commandLower, executable: executableLower) {
            return false
        }

        if process.descriptor.runtime != nil {
            return true
        }

        if process.descriptor.packageManager != nil {
            return true
        }

        if executableLower.contains("node") || executableLower.contains("nodejs") {
            return true
        }

        return false
    }

    private static func shouldDisplayProcess(_ process: NodeProcess) -> Bool {
        if !process.ports.isEmpty {
            return true
        }

        if hasExcludedLifecycleSignal(process.command.lowercased()) {
            return false
        }

        if hasPositiveServerMode(process.descriptor.details) {
            return true
        }

        if let script = process.descriptor.script?.lowercased(),
           serverLifecycleScripts.contains(script) || directServerScripts.contains(script) {
            return true
        }

        if let packageManager = process.descriptor.packageManager,
           !packageManager.isEmpty,
           hasServerLifecycleSignal(process.command.lowercased()) {
            return true
        }

        let descriptorName = process.descriptor.name.lowercased()
        if directServerExecutables.contains(process.executable.lowercased()) ||
            directServerScripts.contains(descriptorName) {
            return true
        }

        return false
    }

    private static func isSystemOrAppBundleProcess(command: String, executable: String) -> Bool {
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

        if executable.hasSuffix("xpc") || executable.contains("serverxpc") {
            return true
        }

        if ProcessToolingExclusions.isExcluded(executable: executable, command: command) {
            return true
        }

        if executable.contains("slaynodemenuba") || command.contains("slaynodemenuba") {
            return true
        }

        return false
    }

    private static func hasPositiveServerMode(_ details: String?) -> Bool {
        guard let details else { return false }
        let normalized = details.lowercased()
        return normalized.contains("mode: dev") ||
            normalized.contains("mode: start") ||
            normalized.contains("mode: serve") ||
            normalized.contains("mode: preview") ||
            normalized.contains("mode: web")
    }

    private static func hasServerLifecycleSignal(_ command: String) -> Bool {
        serverLifecycleKeywords.contains { keyword in
            command.contains(keyword)
        }
    }

    private static func hasExcludedLifecycleSignal(_ command: String) -> Bool {
        excludedLifecycleKeywords.contains { keyword in
            command.contains(keyword)
        }
    }

    private func resolveWorkingDirectories(for pids: [Int32]) async -> [Int32: String] {
        var resolved: [Int32: String] = [:]

        for pidBatch in Self.pidBatches(for: pids, batchSize: pidQueryBatchSize) {
            let pidList = pidBatch.map(String.init).joined(separator: ",")
            guard let (status, output) = try? await runCommand(
                Constants.Path.lsof,
                arguments: ["-a", "-d", "cwd", "-Fn", "-p", pidList]
            ), status == 0 else {
                continue
            }

            for (pid, path) in Self.parseWorkingDirectories(from: output) {
                resolved[pid] = path
            }
        }

        return resolved
    }

    private func fetchCommandLine(for pid: Int32) async -> String? {
        guard let (status, output) = try? await runCommand(
            Constants.Path.ps,
            arguments: ["-p", "\(pid)", "-o", "command="]
        ), status == 0 else {
            return nil
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func runCommand(_ launchPath: String, arguments: [String]) async throws -> (Int32, String) {
        guard !Task.isCancelled else {
            throw ProcessMonitorError.commandFailed("Task cancelled", -1)
        }

        do {
            return try await shell.run(
                launchPath,
                arguments: arguments,
                timeout: Constants.Timeout.commandTimeout
            )
        } catch let error as ProcessMonitorError {
            throw error
        } catch {
            throw ProcessMonitorError.commandFailed("Failed to run command: \(error)", -1)
        }
    }

    private static let serverLifecycleKeywords = [
        " dev",
        " run dev",
        " serve",
        " run serve",
        " preview",
        " run preview",
        " start",
        " run start",
        " start-storybook",
        " storybook",
        " start:web",
        " react-scripts start"
    ]

    private static let excludedLifecycleKeywords = [
        " build",
        " run build",
        " lint",
        " run lint",
        " test",
        " run test",
        " typecheck",
        " run typecheck",
        " format",
        " run format",
        " install",
        " run install"
    ]

    private static let serverLifecycleScripts = Set([
        "dev",
        "serve",
        "preview",
        "start",
        "storybook",
        "start-storybook",
        "start:web"
    ])

    private static let directServerExecutables = Set([
        "vite",
        "webpack-dev-server",
        "storybook",
        "start-storybook"
    ])

    private static let directServerScripts = Set([
        "vite",
        "webpack dev server",
        "webpack-dev-server",
        "storybook"
    ])

    static func pidBatches(for pids: [Int32], batchSize: Int) -> [[Int32]] {
        let normalized = Array(Set(pids.filter { $0 > 0 })).sorted()
        guard !normalized.isEmpty else { return [] }

        let safeBatchSize = max(1, batchSize)
        var batches: [[Int32]] = []
        batches.reserveCapacity((normalized.count + safeBatchSize - 1) / safeBatchSize)

        var index = 0
        while index < normalized.count {
            let endIndex = min(index + safeBatchSize, normalized.count)
            batches.append(Array(normalized[index..<endIndex]))
            index = endIndex
        }

        return batches
    }
}
