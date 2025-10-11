import Combine
import Foundation

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
        queue.async { [weak self] in
            guard let self else { return }
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
        guard !isCollecting else {
            hasPendingRefresh = true
            return
        }
        isCollecting = true

        do {
            let processes = try collectProcesses()
            DispatchQueue.main.async { [weak self] in
                self?.processesSubject.send(processes)
            }
        } catch {
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
        let (psStatus, psOutput) = try runCommand("/bin/ps", arguments: ["-axo", "pid=,etimes=,command="])
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

        let nodeProcesses = processes.filter { $0.executable.contains("node") || $0.executable.contains("nodejs") }

        let portsByPid = try collectPorts(for: nodeProcesses.map { $0.pid })

        let enriched = nodeProcesses.map { process -> NodeProcess in
            let ports = Array(Set(process.ports + (portsByPid[process.pid] ?? []))).sorted()
            return NodeProcess(
                pid: process.pid,
                executable: process.executable,
                command: process.command,
                arguments: process.arguments,
                ports: ports,
                uptime: process.uptime,
                startTime: process.startTime,
                workingDirectory: process.workingDirectory,
                descriptor: process.descriptor
            )
        }

        return enriched
    }

    private func parseProcess(from line: String) -> NodeProcess? {
        let components = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard components.count == 3,
              let pidValue = Int32(components[0]),
              let elapsedSeconds = Double(components[1]) else {
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
}
