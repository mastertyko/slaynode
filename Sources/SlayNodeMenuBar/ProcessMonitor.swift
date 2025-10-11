import Combine
import Foundation
import Darwin

enum ProcessMonitorError: Error, LocalizedError {
    case commandFailed(String, Int32)
    case malformedOutput

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, status):
            return "Kommando \(command) misslyckades med status \(status)."
        case .malformedOutput:
            return "Kunde inte tolka processlistan."
        }
    }
}

extension ProcessMonitor: @unchecked Sendable {}

final class ProcessMonitor {
    private let queue = DispatchQueue(label: "com.slaynode.monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var interval: TimeInterval
    private var isCollecting = false
    private var hasPendingRefresh = false

    private let processesSubject = CurrentValueSubject<[NodeProcess], Never>([])
    private let errorsSubject = PassthroughSubject<Error, Never>()

    var processesPublisher: AnyPublisher<[NodeProcess], Never> {
        processesSubject.eraseToAnyPublisher()
    }

    var errorsPublisher: AnyPublisher<Error, Never> {
        errorsSubject.eraseToAnyPublisher()
    }

    init(interval: TimeInterval = 5) {
        self.interval = interval
    }

    func start() {
        print("🔍 ProcessMonitor starting...")
        queue.async { [weak self] in
            guard let self else { return }
            print("🔍 ProcessMonitor timer started")
            self.startTimer()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopTimer()
        }
    }

    func updateInterval(_ newInterval: TimeInterval) {
        queue.async { [weak self] in
            guard let self else { return }
            guard abs(self.interval - newInterval) > 0.01 else { return }
            self.interval = newInterval
            self.restartTimer()
        }
    }

    func refresh() {
        queue.async { [weak self] in
            self?.performCollect()
        }
    }

    deinit {
        stopTimer()
    }

    private func startTimer() {
        stopTimer()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.performCollect()
        }
        timer.resume()
        self.timer = timer
    }

    private func restartTimer() {
        startTimer()
    }

    private func stopTimer() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }

    private func performCollect() {
        print("🔄 ProcessMonitor performCollect called")
        guard !isCollecting else {
            print("⏳ Already collecting, setting pending flag")
            hasPendingRefresh = true
            return
        }
        isCollecting = true

        do {
            print("📊 Collecting processes...")
            let processes = try collectProcesses()
            print("✅ Collected \(processes.count) processes")
            DispatchQueue.main.async { [weak self] in
                self?.processesSubject.send(processes)
            }
        } catch {
            print("❌ Process collection failed: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.errorsSubject.send(error)
            }
        }

        isCollecting = false

        if hasPendingRefresh {
            hasPendingRefresh = false
            performCollect()
        }
    }

    private func collectProcesses() throws -> [NodeProcess] {
        if let nativeProcesses = try collectProcessesUsingNativeAPI() {
            return nativeProcesses
        }
        return try collectProcessesUsingPS()
    }
    
    private func collectProcessesUsingNativeAPI() throws -> [NodeProcess]? {
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytes > 0 else {
            return nil
        }
        
        let pidCount = Int(bytes) / MemoryLayout<pid_t>.stride
        guard pidCount > 0 else {
            return []
        }
        
        let pids = UnsafeMutablePointer<pid_t>.allocate(capacity: pidCount)
        defer { pids.deallocate() }
        
        let populatedBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, pids, Int32(pidCount * MemoryLayout<pid_t>.stride))
        guard populatedBytes > 0 else {
            return nil
        }
        
        let actualCount = Int(populatedBytes) / MemoryLayout<pid_t>.stride
        var processes: [NodeProcess] = []
        processes.reserveCapacity(actualCount)
        
        for index in 0..<actualCount {
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
                    String(cString: cStringPtr)
                }
            }
            
            guard !executableName.isEmpty else { continue }
            
            let command = fetchCommandLine(for: pid) ?? executableName
            let tokens = CommandParser.tokenize(command)
            guard let executableToken = tokens.first else { continue }
            
            let arguments = Array(tokens.dropFirst())
            let descriptor = CommandParser.descriptor(from: arguments)
            let ports = CommandParser.inferPorts(from: tokens)
            let workingDirectory = CommandParser.inferWorkingDirectory(from: arguments)
            
            let startSeconds = TimeInterval(bsdInfo.pbi_start_tvsec)
            let startMicroseconds = TimeInterval(bsdInfo.pbi_start_tvusec) / 1_000_000
            let startTime = Date(timeIntervalSince1970: startSeconds + startMicroseconds)
            let uptime = max(0, Date().timeIntervalSince(startTime))
            
            let process = NodeProcess(
                pid: pid,
                executable: executableToken,
                command: command,
                arguments: arguments,
                ports: ports,
                uptime: uptime,
                startTime: startTime,
                workingDirectory: workingDirectory,
                descriptor: descriptor
            )
            
            processes.append(process)
        }
        
        return try enrichProcesses(processes)
    }
    
    private func collectProcessesUsingPS() throws -> [NodeProcess] {
        let (psStatus, psOutput) = try runCommand("/bin/ps", arguments: ["-axo", "pid=,etime=,command="])
        guard psStatus == 0 else {
            throw ProcessMonitorError.commandFailed("ps", psStatus)
        }

        let rows = psOutput.split(whereSeparator: { $0.isNewline })
        

        var processes: [NodeProcess] = []
        processes.reserveCapacity(rows.count)

        for row in rows {
            let trimmed = row.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let process = parseProcess(from: trimmed) else { continue }
            processes.append(process)
        }
        
        return try enrichProcesses(processes)
    }

    private func parseProcess(from line: String) -> NodeProcess? {
        let components = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard components.count == 3,
              let pidValue = Int32(components[0]) else {
            return nil
        }
        
        // Parse elapsed time from format like "15:42" or "2:15:42"
        let elapsedSeconds = parseEtime(String(components[1]))
        guard elapsedSeconds > 0 else {
            return nil
        }

        let command = String(components[2])
        let tokens = CommandParser.tokenize(command)
        guard let executableToken = tokens.first else {
            return nil
        }

        let arguments = Array(tokens.dropFirst())
        let descriptor = CommandParser.descriptor(from: arguments)
        let ports = CommandParser.inferPorts(from: tokens)
        let workingDirectory = CommandParser.inferWorkingDirectory(from: arguments)
        let startTime = Date().addingTimeInterval(-elapsedSeconds)

        return NodeProcess(
            pid: pidValue,
            executable: executableToken,
            command: command,
            arguments: arguments,
            ports: ports,
            uptime: elapsedSeconds,
            startTime: startTime,
            workingDirectory: workingDirectory,
            descriptor: descriptor
        )
    }

    private func enrichProcesses(_ processes: [NodeProcess]) throws -> [NodeProcess] {
        let developmentServers = processes.filter(isLikelyDevelopmentProcess(_:))
        guard !developmentServers.isEmpty else {
            return []
        }
        
        let portsByPid = try collectPorts(for: developmentServers.map { $0.pid })
        
        return developmentServers.map { process in
            let combinedPorts = Array(Set(process.ports + (portsByPid[process.pid] ?? []))).sorted()
            return NodeProcess(
                pid: process.pid,
                executable: process.executable,
                command: process.command,
                arguments: process.arguments,
                ports: combinedPorts,
                uptime: process.uptime,
                startTime: process.startTime,
                workingDirectory: process.workingDirectory,
                descriptor: process.descriptor
            )
        }
    }
    
    private func isLikelyDevelopmentProcess(_ process: NodeProcess) -> Bool {
        let executableLower = process.executable.lowercased()
        
        if executableLower.contains("node") || executableLower.contains("nodejs") {
            return true
        }
        
        if executableLower.contains("npm") || executableLower.contains("yarn") || executableLower.contains("pnpm") {
            return true
        }
        
        if executableLower.contains("npx") || executableLower.contains("yarnx") || executableLower.contains("pnpx") {
            return true
        }
        
        if executableLower.contains("next") || executableLower.contains("vite") ||
            executableLower.contains("nuxt") || executableLower.contains("svelte") ||
            executableLower.contains("remix") || executableLower.contains("astro") ||
            executableLower.contains("webpack") || executableLower.contains("serve") {
            return true
        }
        
        let commandLower = process.command.lowercased()
        if commandLower.contains(" dev ") || commandLower.contains(" start ") ||
            commandLower.contains(" serve ") || commandLower.contains(" run dev") ||
            commandLower.contains("run start") || commandLower.contains("run serve") {
            return true
        }
        
        if commandLower.contains("node_modules/.bin/") {
            return true
        }
        
        return false
    }
    
    private func fetchCommandLine(for pid: Int32) -> String? {
        guard let (status, output) = try? runCommand(
            "/bin/ps",
            arguments: ["-p", "\(pid)", "-o", "command="],
            allowFailure: true
        ), status == 0 else {
            return nil
        }
        
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func collectPorts(for pids: [Int32]) throws -> [Int32: [Int]] {
        guard !pids.isEmpty else { return [:] }
        let pidList = pids.map(String.init).joined(separator: ",")
        let (status, output) = try runCommand(
            "/usr/sbin/lsof",
            arguments: ["-Pan", "-p", pidList, "-iTCP", "-sTCP:LISTEN"],
            allowFailure: true
        )

        guard status == 0 || status == 1 else {
            throw ProcessMonitorError.commandFailed("lsof", status)
        }

        guard !output.isEmpty else { return [:] }

        var result: [Int32: [Int]] = [:]
        let lines = output.split(whereSeparator: { $0.isNewline })

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("COMMAND") { continue }

            let tokens = trimmed.split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
            guard tokens.count >= 8,
                  let pid = Int32(tokens[1]) else { continue }

            guard let port = extractPort(from: tokens.last.map(String.init) ?? "") else { continue }
            result[pid, default: []].append(port)
        }

        for key in result.keys {
            result[key] = Array(Set(result[key]!)).sorted()
        }

        return result
    }

    private func extractPort(from token: String) -> Int? {
        let cleaned: String
        if let range = token.range(of: "->") {
            cleaned = String(token[..<range.lowerBound])
        } else {
            cleaned = token
        }

        let withoutSuffix = cleaned.replacingOccurrences(of: "(LISTEN)", with: "")
        guard let colonIndex = withoutSuffix.lastIndex(of: ":") else { return nil }
        let portSubstring = withoutSuffix[withoutSuffix.index(after: colonIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(portSubstring)
    }

    private func runCommand(_ launchPath: String, arguments: [String], allowFailure: Bool = false) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let outputString = String(data: outputData, encoding: .utf8) ?? ""
        let errorString = String(data: errorData, encoding: .utf8) ?? ""

        let status = process.terminationStatus

        if status != 0 && !allowFailure {
            throw ProcessMonitorError.commandFailed("\(launchPath) \(arguments.joined(separator: " "))", status)
        }

        #if DEBUG
        if status != 0 && allowFailure && !errorString.isEmpty {
            // Provide context to caller while still allowing execution to continue
            print("[ProcessMonitor] \(launchPath) returned status \(status): \(errorString)")
        }
        #endif

        return (status, outputString)
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
    
    private func createProcessFromPID(_ pid: Int32) -> NodeProcess? {
        // Use ps to get details for specific PID
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-p", "\(pid)", "-o", "pid=,etime=,command="]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            let lines = output.split(whereSeparator: { $0.isNewline })
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                return parseProcess(from: trimmed)
            }
        } catch {
            print("❌ Failed to get process details for PID \(pid): \(error)")
        }
        
        return nil
    }
}
