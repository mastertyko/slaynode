import Darwin
import Foundation

enum ProcessGroupTerminationError: Error, LocalizedError {
    case invalidPid
    case permissionDenied
    case terminationFailed(Int32)
    case processGroupNotFound
    
    var errorDescription: String? {
        switch self {
        case .invalidPid:
            return "Invalid process ID."
        case .permissionDenied:
            return "Permission denied to stop process."
        case let .terminationFailed(status):
            return "Could not stop process (errno: \(status))."
        case .processGroupNotFound:
            return "Could not find process group."
        }
    }
}

struct ProcessGroupKiller {
    /// Terminates a process and all processes in its group
    /// - Parameters:
    ///   - pid: The process ID to terminate
    ///   - gracePeriod: Time to wait before SIGKILL (default 1.5s)
    func terminateGroup(
        pid: Int32,
        gracePeriod: TimeInterval = Constants.Timeout.gracePeriod
    ) async throws {
        guard pid > 0 else { throw ProcessGroupTerminationError.invalidPid }
        
        // Verify process exists
        guard kill(pid, 0) == 0 || errno != ESRCH else {
            throw ProcessGroupTerminationError.invalidPid
        }
        
        // Get process group ID
        let pgid = getpgid(pid)
        
        if pgid > 0 && pgid != pid {
            // Kill entire process group by sending signal to negative PGID
            try await terminateProcessGroup(pgid: pgid, gracePeriod: gracePeriod)
        } else {
            // Fallback: Find and kill children manually, then parent
            let children = await findDescendantProcesses(parentPid: pid)
            
            // Kill descendants deepest-first before the parent.
            for childPid in children {
                try? await terminateSingleProcess(pid: childPid, gracePeriod: Constants.Timeout.childGracePeriod)
            }
            
            // Then kill parent
            try await terminateSingleProcess(pid: pid, gracePeriod: gracePeriod)
        }
    }
    
    private func terminateProcessGroup(pgid: pid_t, gracePeriod: TimeInterval) async throws {
        // Send SIGTERM to entire group (negative PGID)
        if kill(-pgid, SIGTERM) != 0 {
            if errno == EPERM {
                throw ProcessGroupTerminationError.permissionDenied
            }
            throw ProcessGroupTerminationError.terminationFailed(errno)
        }
        
        guard gracePeriod > 0 else { return }
        
        // Wait for processes to terminate
        let deadline = Date().addingTimeInterval(gracePeriod)
        while Date() < deadline {
            // Check if group leader is gone
            if kill(-pgid, 0) == -1 && errno == ESRCH {
                return
            }
            try await Task.sleep(nanoseconds: Constants.Timeout.terminationPollingInterval)
        }
        
        // Force kill if still alive
        if kill(-pgid, SIGKILL) != 0 && errno != ESRCH {
            if errno == EPERM {
                throw ProcessGroupTerminationError.permissionDenied
            }
            throw ProcessGroupTerminationError.terminationFailed(errno)
        }
    }
    
    private func terminateSingleProcess(pid: Int32, gracePeriod: TimeInterval) async throws {
        guard pid > 0 else { return }
        
        // Check if process still exists
        guard kill(pid, 0) == 0 || errno != ESRCH else { return }
        
        if kill(pid, SIGTERM) != 0 {
            if errno == ESRCH { return } // Already gone
            if errno == EPERM {
                throw ProcessGroupTerminationError.permissionDenied
            }
            throw ProcessGroupTerminationError.terminationFailed(errno)
        }
        
        guard gracePeriod > 0 else { return }
        
        let deadline = Date().addingTimeInterval(gracePeriod)
        while Date() < deadline {
            if kill(pid, 0) == -1 && errno == ESRCH {
                return
            }
            try await Task.sleep(nanoseconds: Constants.Timeout.terminationPollingInterval)
        }
        
        // Force kill
        if kill(pid, SIGKILL) != 0 && errno != ESRCH {
            if errno == EPERM {
                throw ProcessGroupTerminationError.permissionDenied
            }
            throw ProcessGroupTerminationError.terminationFailed(errno)
        }
    }
    
    static func descendantPIDs(parentPid: Int32, childrenByParent: [Int32: [Int32]]) -> [Int32] {
        var result: [Int32] = []
        var visited: Set<Int32> = [parentPid]

        func visit(_ parent: Int32) {
            for childPid in childrenByParent[parent, default: []].sorted() {
                guard !visited.contains(childPid) else { continue }
                visited.insert(childPid)
                visit(childPid)
                result.append(childPid)
            }
        }

        visit(parentPid)
        return result
    }

    private func findDescendantProcesses(parentPid: Int32) async -> [Int32] {
        let childrenByParent = await fetchChildrenByParent()
        return Self.descendantPIDs(parentPid: parentPid, childrenByParent: childrenByParent)
    }

    private func fetchChildrenByParent() async -> [Int32: [Int32]] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: Constants.Path.ps)
                process.arguments = ["-axo", "pid=,ppid="]
                
                let outputPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = FileHandle.nullDevice
                
                do {
                    try process.run()
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    
                    guard let output = String(data: outputData, encoding: .utf8) else {
                        continuation.resume(returning: [:])
                        return
                    }
                    
                    let pairs: [(parent: Int32, child: Int32)] = output
                        .split(whereSeparator: { $0.isNewline })
                        .compactMap { line in
                            let components = line.split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
                            guard components.count == 2,
                                  let pid = Int32(components[0]),
                                  let parentPid = Int32(components[1]) else {
                                return nil
                            }
                            return (parent: parentPid, child: pid)
                        }
                    continuation.resume(returning: Dictionary(grouping: pairs, by: \.parent).mapValues { $0.map(\.child) })
                } catch {
                    Log.process.warning("Failed to find process tree: \(error.localizedDescription)")
                    continuation.resume(returning: [:])
                }
            }
        }
    }
}
