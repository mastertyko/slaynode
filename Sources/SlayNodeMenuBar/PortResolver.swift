import Darwin
import Foundation

/// Resolves listening TCP ports for processes using lsof
struct PortResolver {
    private let timeoutNanoseconds: UInt64 = 2_000_000_000 // 2 seconds
    
    /// Resolves listening ports for given process IDs using lsof
    /// - Parameter pids: Array of process IDs to check
    /// - Returns: Dictionary mapping PID to array of listening ports
    /// - Note: Returns empty dictionary on timeout rather than throwing
    func resolvePorts(for pids: [Int32]) async -> [Int32: [Int]] {
        guard !pids.isEmpty else { return [:] }
        
        let pidList = pids.map(String.init).joined(separator: ",")
        
        do {
            let output = try await runLsofWithTimeout(pidList: pidList)
            return parseLsofOutput(output)
        } catch {
            return [:]
        }
    }
    
    private func runLsofWithTimeout(pidList: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
                process.arguments = ["-Pan", "-p", pidList, "-iTCP", "-sTCP:LISTEN"]
                
                let outputPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = FileHandle.nullDevice
                
                // Timeout using DispatchWorkItem (2 seconds)
                let timeoutWork = DispatchWorkItem { [weak process] in
                    process?.terminate()
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 2.0, execute: timeoutWork)
                
                do {
                    try process.run()
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    timeoutWork.cancel()
                    
                    if process.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: NSError(domain: "PortResolver", code: -1, userInfo: [NSLocalizedDescriptionKey: "Timeout"]))
                        return
                    }
                    
                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    continuation.resume(returning: output)
                } catch {
                    timeoutWork.cancel()
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func parseLsofOutput(_ output: String) -> [Int32: [Int]] {
        guard !output.isEmpty else { return [:] }
        
        var result: [Int32: [Int]] = [:]
        let lines = output.split(whereSeparator: { $0.isNewline })
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("COMMAND") else { continue }
            
            let tokens = trimmed.split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
            guard tokens.count >= 9,
                  let pid = Int32(tokens[1]) else { continue }
            
            let nameToken: String
            if tokens[tokens.count - 1] == "(LISTEN)" && tokens.count >= 10 {
                nameToken = String(tokens[tokens.count - 2])
            } else {
                nameToken = String(tokens.last ?? "")
            }
            
            guard let port = extractPort(from: nameToken) else { continue }
            result[pid, default: []].append(port)
        }
        
        for key in result.keys {
            result[key] = Array(Set(result[key]!)).sorted()
        }
        
        return result
    }
    
    private func extractPort(from token: String) -> Int? {
        var cleaned = token
        
        // Remove arrow suffix for established connections (e.g., "127.0.0.1:3000->127.0.0.1:52341")
        if let range = cleaned.range(of: "->") {
            cleaned = String(cleaned[..<range.lowerBound])
        }
        
        // Remove (LISTEN) suffix
        cleaned = cleaned.replacingOccurrences(of: "(LISTEN)", with: "")
        
        // Handle IPv6 format [::1]:3000 or [::]:3000
        if cleaned.hasPrefix("[") {
            if let bracketEnd = cleaned.lastIndex(of: "]"),
               let colonIndex = cleaned.index(bracketEnd, offsetBy: 1, limitedBy: cleaned.endIndex),
               cleaned[colonIndex] == ":" {
                let portStart = cleaned.index(after: colonIndex)
                let portString = String(cleaned[portStart...]).trimmingCharacters(in: .whitespaces)
                return Int(portString)
            }
        }
        
        // Handle wildcard *:3000
        if cleaned.hasPrefix("*:") {
            let portString = String(cleaned.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return Int(portString)
        }
        
        // Handle standard format 127.0.0.1:3000
        guard let colonIndex = cleaned.lastIndex(of: ":") else { return nil }
        let portString = String(cleaned[cleaned.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
        return Int(portString)
    }
}
