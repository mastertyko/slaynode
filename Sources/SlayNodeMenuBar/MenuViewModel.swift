import Combine
import Foundation

// MARK: - Error Types

enum MenuViewModelError: Error, LocalizedError {
    case processDetectionFailed(String)
    case processTerminationFailed(Int32, String)
    case invalidProcessId(Int32)
    case processNotFound(Int32)
    case timeoutWaitingForShutdown(Int32)
    case permissionDenied(Int32)
    case commandExecutionFailed(String, Int32)
    case unknownError(String)

    var errorDescription: String? {
        switch self {
        case .processDetectionFailed(let details):
            return "Process detection failed: \(details)"
        case .processTerminationFailed(let pid, let details):
            return "Failed to terminate process \(pid): \(details)"
        case .invalidProcessId(let pid):
            return "Invalid process ID: \(pid)"
        case .processNotFound(let pid):
            return "Process not found: \(pid)"
        case .timeoutWaitingForShutdown(let pid):
            return "Timeout waiting for process \(pid) to shutdown"
        case .permissionDenied(let pid):
            return "Permission denied when accessing process \(pid)"
        case .commandExecutionFailed(let command, let status):
            return "Command '\(command)' failed with status \(status)"
        case .unknownError(let message):
            return "Unknown error: \(message)"
        }
    }
}

struct NodeProcessItemViewModel: Identifiable, Equatable {
    struct PortBadge: Hashable {
        let text: String
        let isLikely: Bool
    }

    struct InfoChip: Hashable {
        let text: String
        let systemImage: String?
    }

    let id: Int32
    let pid: Int32
    let title: String
    let subtitle: String
    let categoryBadge: String?
    let portBadges: [PortBadge]
    let infoChips: [InfoChip]
    let projectName: String?
    let uptimeDescription: String
    let startTimeDescription: String
    let command: String
    let workingDirectory: String?
    let descriptor: ServerDescriptor
    let isStopping: Bool
}

// MARK: - MenuViewModel Class
@MainActor
final class MenuViewModel: ObservableObject {
    @Published var isLoading: Bool = true
    @Published var processes: [NodeProcessItemViewModel] = []
    @Published var lastError: String?
    @Published var lastUpdated: Date?

    let preferences: PreferencesStore

    private let monitor: ProcessMonitor
    private let groupKiller = ProcessGroupKiller()
    private var cancellables: Set<AnyCancellable> = []
    private var stoppingPids: Set<Int32> = []
    private var latestProcesses: [NodeProcess] = []
    
    private func writeToLogFile(_ message: String) {
        // Use simple console logging to avoid threading issues
        print("SlayNode: \(message)")
    }

    init(preferences: PreferencesStore = PreferencesStore(), monitor: ProcessMonitor = ProcessMonitor()) {
        self.preferences = preferences
        self.monitor = monitor

        isLoading = true
        processes = []
        lastError = nil
        lastUpdated = Date()

        print("🚀 MenuViewModel initialized - binding to ProcessMonitor")

        bindMonitor()
        monitor.start()
    }

    func refresh() {
        print("🔄 Refreshing process list via ProcessMonitor")
        isLoading = true

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.monitor.refresh()
        }
    }

    func stopProcess(_ pid: Int32) {
        // Input validation
        guard pid > 0 else {
            handleError(MenuViewModelError.invalidProcessId(pid))
            return
        }

        guard !stoppingPids.contains(pid) else {
            print("⚠️ Process \(pid) is already being stopped")
            return
        }

        guard processes.contains(where: { $0.pid == pid }) else {
            handleError(MenuViewModelError.processNotFound(pid))
            return
        }

        stoppingPids.insert(pid)
        print("🛑 Attempting to slay process \(pid)")

        // Mark as stopping in UI immediately
        if let index = processes.firstIndex(where: { $0.pid == pid }) {
            processes[index] = NodeProcessItemViewModel(
                id: processes[index].id,
                pid: processes[index].pid,
                title: processes[index].title,
                subtitle: processes[index].subtitle,
                categoryBadge: processes[index].categoryBadge,
                portBadges: processes[index].portBadges,
                infoChips: processes[index].infoChips,
                projectName: processes[index].projectName,
                uptimeDescription: processes[index].uptimeDescription,
                startTimeDescription: processes[index].startTimeDescription,
                command: processes[index].command,
                workingDirectory: processes[index].workingDirectory,
                descriptor: processes[index].descriptor,
                isStopping: true
            )
        }

        // Enhanced process termination with verification
        // Capture ports before UI potentially changes
        let portsToMonitor = getPortsForProcess(pid: pid)

        Task { [weak self] in
            await self?.waitForCompleteShutdown(pid: pid, portsToMonitor: portsToMonitor)
        }
    }

    private func handleError(_ error: Error) {
        let errorMessage: String
        if let menuError = error as? MenuViewModelError {
            errorMessage = menuError.localizedDescription
        } else {
            errorMessage = MenuViewModelError.unknownError(error.localizedDescription).localizedDescription
        }

        lastError = errorMessage
        print("❌ Error: \(errorMessage)")
    }

    private func waitForCompleteShutdown(pid: Int32, portsToMonitor: [Int]) async {
        do {
            // Get expected command hash for verification
            let expectedHash = latestProcesses.first(where: { $0.pid == pid })?.commandHash
            
            // Verify process identity before termination
            if let expectedHash = expectedHash {
                let isVerified = await monitor.verifyProcess(pid: pid, expectedHash: expectedHash)
                if !isVerified {
                    throw MenuViewModelError.processTerminationFailed(pid, "Process has changed since detection")
                }
            }
            
            // Use ProcessGroupKiller for complete termination (parent + children)
            try await groupKiller.terminateGroup(pid: pid, gracePeriod: 1.5)
            print("✅ Process group \(pid) termination command sent")

            // Wait for complete shutdown (process + ports)
            let shutdownComplete = await waitForProcessAndPortsShutdown(pid: pid, portsToMonitor: portsToMonitor)

            // Update UI state on main actor
            self.stoppingPids.remove(pid)

            if shutdownComplete {
                // Add a small delay for visual feedback before removing
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                self.processes.removeAll { $0.pid == pid }
                self.lastUpdated = Date()
                print("🎉 Process \(pid) and ports fully shutdown - removing from UI")
            } else {
                // Timeout reached, remove anyway but show warning
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                self.processes.removeAll { $0.pid == pid }
                self.lastUpdated = Date()
                handleError(MenuViewModelError.timeoutWaitingForShutdown(pid))
                print("⚠️ Process \(pid) removal after timeout")
            }

        } catch {
            // Convert ProcessGroupTerminationError to our error type
            let errorToHandle: MenuViewModelError
            if let processError = error as? ProcessGroupTerminationError {
                switch processError {
                case .invalidPid:
                    errorToHandle = .invalidProcessId(pid)
                case .permissionDenied:
                    errorToHandle = .permissionDenied(pid)
                case .terminationFailed(let status):
                    errorToHandle = .processTerminationFailed(pid, "errno: \(status)")
                case .processGroupNotFound:
                    errorToHandle = .processTerminationFailed(pid, "Process group not found")
                }
            } else if let menuError = error as? MenuViewModelError {
                errorToHandle = menuError
            } else {
                errorToHandle = .processTerminationFailed(pid, error.localizedDescription)
            }

            // Update UI state on main actor
            self.stoppingPids.remove(pid)
            handleError(errorToHandle)

            // Reset stopping state on failure
            if let index = self.processes.firstIndex(where: { $0.pid == pid }) {
                self.processes[index] = NodeProcessItemViewModel(
                    id: self.processes[index].id,
                    pid: self.processes[index].pid,
                    title: self.processes[index].title,
                    subtitle: self.processes[index].subtitle,
                    categoryBadge: self.processes[index].categoryBadge,
                    portBadges: self.processes[index].portBadges,
                    infoChips: self.processes[index].infoChips,
                    projectName: self.processes[index].projectName,
                    uptimeDescription: self.processes[index].uptimeDescription,
                    startTimeDescription: self.processes[index].startTimeDescription,
                    command: self.processes[index].command,
                    workingDirectory: self.processes[index].workingDirectory,
                    descriptor: self.processes[index].descriptor,
                    isStopping: false
                )
            }
        }
    }

    private func waitForProcessAndPortsShutdown(pid: Int32, portsToMonitor: [Int], timeoutSeconds: TimeInterval = 10.0) async -> Bool {
        let startTime = Date()
        let timeout = Date().addingTimeInterval(timeoutSeconds)

        while Date() < timeout {
            // Check if process is still running
            let processIsRunning = isProcessRunning(pid: pid)

            // Check if all ports are free
            var allPortsFree = true
            for port in portsToMonitor {
                if !isPortFree(port: port) {
                    allPortsFree = false
                    break
                }
            }

            // If both process and ports are down, we're done!
            if !processIsRunning && allPortsFree {
                let elapsed = Date().timeIntervalSince(startTime)
                print("🎯 Process \(pid) and ports fully shutdown in \(String(format: "%.2f", elapsed))s")
                return true
            }

            // Poll every 500ms
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        print("⏰ Timeout waiting for process \(pid) shutdown")
        return false
    }

    private func isProcessRunning(pid: Int32) -> Bool {
        // Use kill(pid, 0) to check if process exists
        let result = kill(pid, 0)
        return result == 0
    }

    private func isPortFree(port: Int) -> Bool {
        // Input validation
        guard port > 0 && port <= 65535 else {
            print("⚠️ Invalid port number: \(port)")
            return true // Consider invalid ports as "free"
        }

        let task = Process()
        task.launchPath = "/usr/sbin/lsof"
        task.arguments = ["-i", ":\(port)"]

        let pipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = pipe
        task.standardError = errorPipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // If output is empty, port is free
            let isFree = output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            // Log port status for debugging
            if !isFree {
                print("🔌 Port \(port) is in use")
            }

            return isFree
        } catch {
            // Log the error but assume port is free for safety
            print("⚠️ Failed to check port \(port): \(error)")
            return true
        }
    }

    private func getPortsForProcess(pid: Int32) -> [Int] {
        guard let process = processes.first(where: { $0.pid == pid }) else { return [] }

        // Extract ports from port badges
        let portStrings = process.portBadges.map { $0.text }
        var ports: [Int] = []

        for portString in portStrings {
            // Remove ":" prefix and convert to Int
            let cleanPort = portString.replacingOccurrences(of: ":", with: "")
            if let port = Int(cleanPort) {
                ports.append(port)
            }
        }

        return ports
    }

    
    private func bindMonitor() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            // Observe process changes
            for await processes in self.monitor.processesPublisher.values {
                self.latestProcesses = processes
                self.lastUpdated = Date()
                self.isLoading = false
                self.publishLatest()
            }
        }

        Task { @MainActor [weak self] in
            guard let self = self else { return }

            // Observe errors
            for await error in self.monitor.errorsPublisher.values {
                self.lastError = error.localizedDescription
            }
        }
    }

    
    private func publishLatest() {
        processes = buildViewModels(from: latestProcesses)
    }

    private func buildViewModels(from processes: [NodeProcess]) -> [NodeProcessItemViewModel] {
        let sorted = processes.sorted { lhs, rhs in
            let startInterval = lhs.startTime.timeIntervalSince1970
            let rhsInterval = rhs.startTime.timeIntervalSince1970
            if abs(startInterval - rhsInterval) > 0.001 {
                return startInterval > rhsInterval
            }
            if lhs.uptime != rhs.uptime {
                return lhs.uptime < rhs.uptime
            }
            let lhsPort = lhs.ports.min() ?? Int.max
            let rhsPort = rhs.ports.min() ?? Int.max
            if lhsPort != rhsPort {
                return lhsPort < rhsPort
            }
            if lhs.descriptor.name != rhs.descriptor.name {
                return lhs.descriptor.name.localizedCaseInsensitiveCompare(rhs.descriptor.name) == .orderedAscending
            }
            return lhs.pid < rhs.pid
        }

        return sorted.map { process in
            let title = makeTitle(for: process)
            let commandSummary = makeCommandSummary(for: process)
            let uptimeText = Self.durationFormatter.string(from: process.uptime) ?? "-"
            let startText = Self.relativeFormatter.localizedString(for: process.startTime, relativeTo: Date())
            let isStopping = stoppingPids.contains(process.pid)
            let portBadges = makePortBadges(for: process)
            let infoChips = makeInfoChips(for: process, commandSummary: commandSummary)
            let projectName = makeProjectName(for: process)
            let categoryBadge = process.descriptor == .unknown ? nil : process.descriptor.category.displayName

            return NodeProcessItemViewModel(
                id: process.pid,
                pid: process.pid,
                title: title,
                subtitle: commandSummary,
                categoryBadge: categoryBadge,
                portBadges: portBadges,
                infoChips: infoChips,
                projectName: projectName,
                uptimeDescription: uptimeText,
                startTimeDescription: startText,
                command: process.command,
                workingDirectory: process.workingDirectory,
                descriptor: process.descriptor,
                isStopping: isStopping
            )
        }
    }

    private func makeTitle(for process: NodeProcess) -> String {
        process.descriptor.displayName
    }

    private func makePortBadges(for process: NodeProcess) -> [NodeProcessItemViewModel.PortBadge] {
        var badges = process.ports.map { NodeProcessItemViewModel.PortBadge(text: ":\($0)", isLikely: false) }
        if badges.isEmpty {
            badges = process.descriptor.portHints.map { NodeProcessItemViewModel.PortBadge(text: ":\($0)", isLikely: true) }
        }
        return badges
    }

    private func makeCommandSummary(for process: NodeProcess) -> String {
        if let packageManager = process.descriptor.packageManager, let script = process.descriptor.script {
            return "\(packageManager) \(script)"
        }

        if let script = process.descriptor.script {
            return prettifyToken(script)
        }

        let tokens = CommandParser.tokenize(process.command)
        guard !tokens.isEmpty else { return process.command }

        let prettified = tokens.map { prettifyToken($0) }
        let prefix = prettified.prefix(3)
        return prefix.joined(separator: " ")
    }

    private func makeInfoChips(for process: NodeProcess, commandSummary: String) -> [NodeProcessItemViewModel.InfoChip] {
        var chips: [NodeProcessItemViewModel.InfoChip] = []

        if let runtime = process.descriptor.runtime {
            chips.append(.init(text: runtime, systemImage: "cpu"))
        }

        if let packageManager = process.descriptor.packageManager, let script = process.descriptor.script {
            let text = "\(packageManager) \(script)"
            if text != commandSummary {
                chips.append(.init(text: text, systemImage: "terminal"))
            }
        } else if let script = process.descriptor.script {
            let pretty = prettifyToken(script)
            if pretty != commandSummary {
                chips.append(.init(text: pretty, systemImage: "terminal"))
            }
        }

        if let details = process.descriptor.details {
            chips.append(.init(text: details, systemImage: "info.circle"))
        }

        return Array(chips.prefix(3))
    }

    private func makeProjectName(for process: NodeProcess) -> String? {
        guard let path = process.workingDirectory else { return nil }
        let url = URL(fileURLWithPath: path)
        let lastComponent = url.lastPathComponent
        if !lastComponent.isEmpty {
            return lastComponent
        }
        return url.path
    }

    private func prettifyToken(_ token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return token }

        // common path expansions
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            let expanded = (trimmed as NSString).expandingTildeInPath
            let lastComponent = URL(fileURLWithPath: expanded).lastPathComponent
            return lastComponent.isEmpty ? trimmed : lastComponent
        }

        if trimmed.contains("\\") || trimmed.contains("/") {
            return (trimmed as NSString).lastPathComponent
        }

        if trimmed.hasPrefix("node_modules/.bin/") {
            return String(trimmed.split(separator: "/").last ?? Substring(trimmed))
        }

        return trimmed
    }

    @MainActor private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()

    @MainActor private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

  }
