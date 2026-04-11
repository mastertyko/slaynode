import Combine
import Foundation
import Darwin

enum ProcessMonitorError: Error, LocalizedError {
    case commandFailed(String, Int32)
    case malformedOutput

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, status):
            return "Command \(command) failed with status \(status)."
        case .malformedOutput:
            return "Could not parse process list."
        }
    }
}

@MainActor
final class ProcessMonitor: ProcessMonitoring {
    private var interval: TimeInterval
    private var isCollecting = false
    private var hasPendingRefresh = false
    private var collectionTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private let portResolver = PortResolver()
    private let shell: ShellExecuting

    private let processesSubject = CurrentValueSubject<[NodeProcess], Never>([])
    private let errorsSubject = PassthroughSubject<Error, Never>()

    var processesPublisher: AnyPublisher<[NodeProcess], Never> {
        processesSubject.eraseToAnyPublisher()
    }

    var errorsPublisher: AnyPublisher<Error, Never> {
        errorsSubject.eraseToAnyPublisher()
    }

    init(interval: TimeInterval = Constants.Preferences.defaultRefreshInterval, shell: ShellExecuting = SystemShellExecutor()) {
        self.interval = interval
        self.shell = shell
    }

    func start() {
        Log.process.info("ProcessMonitor starting...")
        startTimer()
    }

    func stop() {
        collectionTask?.cancel()
        stopTimer()
    }

    func updateInterval(_ newInterval: TimeInterval) {
        guard abs(interval - newInterval) > 0.01 else { return }
        interval = newInterval
        restartTimer()
    }

    func refresh() async {
        await performCollect()
    }

    deinit {
        // Clean up tasks without calling MainActor methods
        timerTask?.cancel()
        timerTask = nil
        collectionTask?.cancel()
        collectionTask = nil
    }

    private func startTimer() {
        stopTimer()

        timerTask = Task { @MainActor [weak self] in
            guard let self = self else { return }

            try? await Task.sleep(nanoseconds: 1_000_000_000)

            while !Task.isCancelled {
                self.collectionTask?.cancel()

                self.collectionTask = Task {
                    await self.performCollect()
                }

                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
            }
        }
    }

    private func restartTimer() {
        collectionTask?.cancel()
        startTimer()
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
        collectionTask?.cancel()
        collectionTask = nil
    }

    private func performCollect() async {
        guard !isCollecting else {
            hasPendingRefresh = true
            return
        }

        isCollecting = true

        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 10_000_000_000)
        }

        do {
            let processes = try await collectProcesses()
            timeoutTask.cancel()

            // Check if we were cancelled during collection
            guard !Task.isCancelled else {
                isCollecting = false
                return
            }

            // Already on MainActor, send directly
            self.processesSubject.send(processes)
        } catch {
            timeoutTask.cancel()

            // Only send error if not cancelled
            guard !Task.isCancelled else {
                isCollecting = false
                return
            }

            // Already on MainActor, send directly
            self.errorsSubject.send(error)
        }

        isCollecting = false

        // Only process pending refresh if not cancelled
        if hasPendingRefresh && !Task.isCancelled {
            hasPendingRefresh = false
            await performCollect()
        }
    }

    private func collectProcesses() async throws -> [NodeProcess] {
        // Use only the safe PS-based method for now
        return try await collectProcessesUsingPS()
    }
    
    private func collectProcessesUsingNativeAPI() async throws -> [NodeProcess]? {
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytes > 0 else {
            return nil
        }

        let pidCount = Int(bytes) / MemoryLayout<pid_t>.stride
        guard pidCount > 0 else {
            return []
        }

        // Prevent excessive memory allocation
        let safePidCount = min(pidCount, 10000)
        let pids = UnsafeMutablePointer<pid_t>.allocate(capacity: safePidCount)
        defer { pids.deallocate() }

        let populatedBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, pids, Int32(safePidCount * MemoryLayout<pid_t>.stride))
        guard populatedBytes > 0 else {
            return nil
        }

        let actualCount = min(Int(populatedBytes) / MemoryLayout<pid_t>.stride, safePidCount)
        var processes: [NodeProcess] = []
        processes.reserveCapacity(actualCount)

        for index in 0..<actualCount {
            // Add bounds checking
            guard index < safePidCount else { break }
            let pid = pids[index]
            if pid <= 0 { continue }
            
            var bsdInfo = proc_bsdinfo()
            let infoSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
            let infoResult = withUnsafeMutablePointer(to: &bsdInfo) {
                proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, infoSize)
            }
            
            guard infoResult == infoSize else { continue }
            
            let executableName = withUnsafePointer(to: &bsdInfo.pbi_comm) { ptr -> String in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) { cStringPtr in
                    let string = String(cString: cStringPtr)
                    // Truncate excessively long names
                    return string.count > 256 ? String(string.prefix(256)) : string
                }
            }
            
            guard !executableName.isEmpty else { continue }
            
            let command = await fetchCommandLine(for: pid) ?? executableName
            let tokens = CommandParser.tokenize(command)
            guard let executableToken = tokens.first else { continue }
            
            let arguments = Array(tokens.dropFirst())
            let ports = CommandParser.inferPorts(from: tokens)
            let workingDirectory = CommandParser.inferWorkingDirectory(from: arguments)
            let context = CommandParser.makeContext(
                executable: executableToken,
                tokens: tokens,
                workingDirectory: workingDirectory
            )
            let descriptor = CommandParser.descriptor(from: context)
            
            let startSeconds = TimeInterval(bsdInfo.pbi_start_tvsec)
            let startMicroseconds = TimeInterval(bsdInfo.pbi_start_tvusec) / 1_000_000
            let startTime = Date(timeIntervalSince1970: startSeconds + startMicroseconds)
            let uptime = max(0, Date().timeIntervalSince(startTime))
            let ppid = Int32(bsdInfo.pbi_ppid)
            
            let process = NodeProcess(
                pid: pid,
                ppid: ppid,
                executable: executableToken,
                command: command,
                arguments: arguments,
                ports: ports,
                uptime: uptime,
                startTime: startTime,
                workingDirectory: workingDirectory,
                descriptor: descriptor,
                commandHash: command.hashValue
            )
            
            processes.append(process)
        }
        
        return try await enrichProcesses(processes)
    }
    
    private func collectProcessesUsingPS() async throws -> [NodeProcess] {
        do {
            let (psStatus, psOutput) = try await runCommand("/bin/ps", arguments: ["-axo", "pid=,ppid=,etime=,command="])
            
            guard psStatus == 0 else {
                return []
            }

            let rows = psOutput.split(whereSeparator: { $0.isNewline })

            var processes: [NodeProcess] = []
            processes.reserveCapacity(min(rows.count, 2000))

            for row in rows {
                let trimmed = row.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                guard let process = parseProcess(from: trimmed) else { continue }
                processes.append(process)
            }

            return try await enrichProcesses(processes)
        } catch {
            Log.process.error("Failed to collect processes using PS: \(error.localizedDescription)")
            return []
        }
    }

    private func parseProcess(from line: String) -> NodeProcess? {
        let components = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard components.count == 4,
              let pidValue = Int32(components[0]),
              let ppidValue = Int32(components[1]) else {
            return nil
        }
        
        // Parse elapsed time from format like "15:42" or "2:15:42"
        let elapsedSeconds = parseEtime(String(components[2]))
        guard elapsedSeconds > 0 else {
            return nil
        }

        let command = String(components[3])
        let tokens = CommandParser.tokenize(command)
        guard let executableToken = tokens.first else {
            return nil
        }

        let arguments = Array(tokens.dropFirst())
        let ports = CommandParser.inferPorts(from: tokens)
        let workingDirectory = CommandParser.inferWorkingDirectory(from: arguments)
        let context = CommandParser.makeContext(
            executable: executableToken,
            tokens: tokens,
            workingDirectory: workingDirectory
        )
        let descriptor = CommandParser.descriptor(from: context)
        let startTime = Date().addingTimeInterval(-elapsedSeconds)

        return NodeProcess(
            pid: pidValue,
            ppid: ppidValue,
            executable: executableToken,
            command: command,
            arguments: arguments,
            ports: ports,
            uptime: elapsedSeconds,
            startTime: startTime,
            workingDirectory: workingDirectory,
            descriptor: descriptor,
            commandHash: command.hashValue
        )
    }

    private func enrichProcesses(_ processes: [NodeProcess]) async throws -> [NodeProcess] {
        let candidateProcesses = processes.filter(isPotentialDevelopmentProcess(_:))
        
        guard !candidateProcesses.isEmpty else {
            return []
        }
        
        let portsByPid = await portResolver.resolvePorts(for: candidateProcesses.map { $0.pid })
        let workingDirectoriesByPid = await resolveWorkingDirectories(for: candidateProcesses.map { $0.pid })
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
                  let promotedChild = preferredPromotedChild(
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
                descriptor = promotedDescriptor(parent: process.descriptor, child: promotedChild.descriptor)
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

            guard shouldDisplayProcess(enrichedProcess) else {
                continue
            }

            result.append(enrichedProcess)
        }
        
        return result
    }

    private func preferredPromotedChild(
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

    private func promotionScore(
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

    private func promotedDescriptor(parent: ServerDescriptor, child: ServerDescriptor) -> ServerDescriptor {
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
    
    private func isPotentialDevelopmentProcess(_ process: NodeProcess) -> Bool {
        let executableLower = process.executable.lowercased()
        let commandLower = process.command.lowercased()
        
        // EXCLUSIONS: System processes and app bundles should never be shown
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

    private func shouldDisplayProcess(_ process: NodeProcess) -> Bool {
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
    
    private func isSystemOrAppBundleProcess(command: String, executable: String) -> Bool {
        // macOS system paths (command is already lowercased)
        if command.hasPrefix("/system/") ||
           command.hasPrefix("/usr/sbin/") ||
           command.hasPrefix("/usr/libexec/") ||
           command.hasPrefix("/library/") ||
           command.hasPrefix("/sbin/") {
            return true
        }
        
        // App bundle helper processes (Electron apps like VSCode, Discord, etc.)
        if command.contains(".app/contents/") {
            return true
        }
        
        // Electron/Chromium internal node services
        if command.contains("node.mojom.nodeservice") ||
           command.contains("--type=utility") ||
           command.contains("--type=renderer") ||
           command.contains("--type=gpu-process") {
            return true
        }
        
        // XPC services (system daemons)
        if executable.hasSuffix("xpc") || executable.contains("serverxpc") {
            return true
        }
        
        // Build tool child processes (not user-facing servers)
        if command.contains("esbuild --service") ||
           command.contains("esbuild --ping") ||
           executable == "esbuild" {
            return true
        }
        
        // SlayNode itself
        if executable.contains("slaynodemenuba") || command.contains("slaynodemenuba") {
            return true
        }
        
        return false
    }

    private func hasPositiveServerMode(_ details: String?) -> Bool {
        guard let details else { return false }
        let normalized = details.lowercased()
        return normalized.contains("mode: dev") ||
            normalized.contains("mode: start") ||
            normalized.contains("mode: serve") ||
            normalized.contains("mode: preview") ||
            normalized.contains("mode: web")
    }

    private func hasServerLifecycleSignal(_ command: String) -> Bool {
        serverLifecycleKeywords.contains { keyword in
            command.contains(keyword)
        }
    }

    private func hasExcludedLifecycleSignal(_ command: String) -> Bool {
        excludedLifecycleKeywords.contains { keyword in
            command.contains(keyword)
        }
    }

    private func resolveWorkingDirectories(for pids: [Int32]) async -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }

        let pidList = pids.map(String.init).joined(separator: ",")
        guard let (status, output) = try? await runCommand(
            Constants.Path.lsof,
            arguments: ["-a", "-d", "cwd", "-Fn", "-p", pidList],
            allowFailure: true
        ), status == 0 else {
            return [:]
        }

        var currentPid: Int32?
        var result: [Int32: String] = [:]

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let prefix = line.first else { continue }

            switch prefix {
            case "p":
                currentPid = Int32(line.dropFirst())
            case "n":
                guard let currentPid, !result.keys.contains(currentPid) else { continue }
                let path = String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty {
                    result[currentPid] = path
                }
            default:
                continue
            }
        }

        return result
    }

    private let serverLifecycleKeywords = [
        " dev",
        " run dev",
        " serve",
        " run serve",
        " preview",
        " run preview",
        " start-storybook",
        " storybook",
        " start:web",
        " react-scripts start"
    ]

    private let excludedLifecycleKeywords = [
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

    private let serverLifecycleScripts = Set([
        "dev",
        "serve",
        "preview",
        "storybook",
        "start-storybook",
        "start:web"
    ])

    private let directServerExecutables = Set([
        "vite",
        "webpack-dev-server",
        "storybook",
        "start-storybook"
    ])

    private let directServerScripts = Set([
        "vite",
        "webpack dev server",
        "webpack-dev-server",
        "storybook"
    ])
    
    private func fetchCommandLine(for pid: Int32) async -> String? {
        guard let (status, output) = try? await runCommand(
            "/bin/ps",
            arguments: ["-p", "\(pid)", "-o", "command="],
            allowFailure: true
        ), status == 0 else {
            return nil
        }
        
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func verifyProcess(pid: Int32, expectedHash: Int) async -> Bool {
        guard let currentCommand = await fetchCommandLine(for: pid) else {
            return false
        }
        return currentCommand.hashValue == expectedHash
    }

    private func runCommand(_ launchPath: String, arguments: [String], allowFailure: Bool = false) async throws -> (Int32, String) {
        guard !Task.isCancelled else {
            throw ProcessMonitorError.commandFailed("Task cancelled", -1)
        }

        do {
            let (status, output) = try await shell.run(launchPath, arguments: arguments, timeout: Constants.Timeout.commandTimeout)
            
            if status != 0 && !allowFailure {
                throw ProcessMonitorError.commandFailed("\(launchPath) \(arguments.joined(separator: " "))", status)
            }
            
            return (status, output)
        } catch let error as ProcessMonitorError {
            throw error
        } catch {
            throw ProcessMonitorError.commandFailed("Failed to run command: \(error)", -1)
        }
    }
    
    private func parseEtime(_ etime: String) -> TimeInterval {
        // Handle DD-HH:MM:SS format first (e.g., "01-07:45:05")
        if etime.contains("-") {
            let components = etime.split(separator: "-")
            guard components.count == 2 else { return 0 }
            
            let days = TimeInterval(components[0]) ?? 0
            let timePart = components[1]
            
            let timeComponents = timePart.split(separator: ":")
            guard timeComponents.count == 3 else { return 0 }
            
            let hours = TimeInterval(timeComponents[0]) ?? 0
            let minutes = TimeInterval(timeComponents[1]) ?? 0
            let seconds = TimeInterval(timeComponents[2]) ?? 0
            
            return days * 86400 + hours * 3600 + minutes * 60 + seconds
        }
        
        // Handle MM:SS and HH:MM:SS formats
        let parts = etime.split(separator: ":")
        
        switch parts.count {
        case 1:
            // Seconds only: "42"
            return TimeInterval(parts[0]) ?? 0
        case 2:
            // MM:SS format: "15:42" -> 15 minutes 42 seconds
            let minutes = TimeInterval(parts[0]) ?? 0
            let seconds = TimeInterval(parts[1]) ?? 0
            return minutes * 60 + seconds
        case 3:
            // HH:MM:SS format: "2:15:42" -> 2 hours 15 minutes 42 seconds
            let hours = TimeInterval(parts[0]) ?? 0
            let minutes = TimeInterval(parts[1]) ?? 0
            let seconds = TimeInterval(parts[2]) ?? 0
            return hours * 3600 + minutes * 60 + seconds
        default:
            return 0
        }
    }
}
