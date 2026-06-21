import Darwin
import Foundation

struct PortResolver: Sendable {
    private let shell: any ShellExecuting
    private let pidQueryBatchSize: Int

    init(
        shell: any ShellExecuting = SystemShellExecutor(),
        pidQueryBatchSize: Int = Constants.Buffer.maxPIDQueryBatchSize
    ) {
        self.shell = shell
        self.pidQueryBatchSize = max(1, pidQueryBatchSize)
    }

    func resolvePorts(for pids: [Int32]) async -> [Int32: [Int]] {
        var resolved: [Int32: [Int]] = [:]

        for pidBatch in Self.pidBatches(for: pids, batchSize: pidQueryBatchSize) {
            guard let batchResult = await resolveBatch(pidBatch) else { continue }

            for (pid, ports) in batchResult {
                resolved[pid, default: []].append(contentsOf: ports)
            }
        }

        for (pid, ports) in resolved {
            resolved[pid] = Array(Set(ports)).sorted()
        }

        return resolved
    }

    private func resolveBatch(_ pidBatch: [Int32]) async -> [Int32: [Int]]? {
        let pidList = pidBatch.map(String.init).joined(separator: ",")
        let arguments = ["-Pan", "-p", pidList, "-iTCP", "-sTCP:LISTEN"]
        let retryCount = 2

        for attempt in 1...retryCount {
            do {
                let (status, output) = try await shell.run(
                    Constants.Path.lsof,
                    arguments: arguments,
                    timeout: Constants.Timeout.lsofTimeout
                )
                let parsed = Self.parseLsofOutput(output)

                if status == 0 {
                    return parsed
                }

                let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !parsed.isEmpty || trimmedOutput.isEmpty {
                    return parsed
                }

                if attempt == retryCount {
                    Log.network.warning("Port resolution failed for pid batch \(pidList) with exit status \(status).")
                }
            } catch {
                if attempt == retryCount {
                    Log.network.warning("Port resolution failed for pid batch \(pidList): \(error.localizedDescription)")
                }
            }
        }

        return nil
    }

    static func normalizedPIDs(_ pids: [Int32]) -> [Int32] {
        Array(Set(pids.filter { $0 > 0 })).sorted()
    }

    static func pidBatches(for pids: [Int32], batchSize: Int) -> [[Int32]] {
        let normalized = normalizedPIDs(pids)
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

    static func parseLsofOutput(_ output: String) -> [Int32: [Int]] {
        guard !output.isEmpty else { return [:] }

        var result: [Int32: [Int]] = [:]
        var currentFieldPid: Int32?
        let lines = output.split(whereSeparator: { $0.isNewline })

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("COMMAND") else { continue }

            if let fieldPort = parseFieldFormatLine(trimmed, currentPid: &currentFieldPid) {
                result[fieldPort.pid, default: []].append(fieldPort.port)
                continue
            }

            let tokens = trimmed.split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
            guard tokens.count >= 9,
                  let pid = Int32(tokens[1]) else { continue }

            let nameToken: String
            if tokens[tokens.count - 1] == "(LISTEN)" && tokens.count >= 10 {
                nameToken = String(tokens[tokens.count - 2])
            } else {
                nameToken = String(tokens.last ?? "")
            }

            guard let port = Self.extractPort(from: nameToken) else { continue }
            result[pid, default: []].append(port)
        }

        for (pid, ports) in result {
            result[pid] = Array(Set(ports)).sorted()
        }

        return result
    }

    private static func parseFieldFormatLine(
        _ line: String,
        currentPid: inout Int32?
    ) -> (pid: Int32, port: Int)? {
        guard let field = line.first else { return nil }

        switch field {
        case "p":
            currentPid = Int32(line.dropFirst())
            return nil
        case "n":
            guard let pid = currentPid,
                  let port = extractPort(from: String(line.dropFirst())) else {
                return nil
            }
            return (pid, port)
        default:
            return nil
        }
    }
    
    static func extractPort(from token: String) -> Int? {
        var cleaned = token
        
        // Remove arrow suffix for established connections (e.g., "127.0.0.1:3000->127.0.0.1:52341")
        if let range = cleaned.range(of: "->") {
            cleaned = String(cleaned[..<range.lowerBound])
        }
        
        // Remove (LISTEN) suffix
        cleaned = cleaned.replacingOccurrences(of: "(LISTEN)", with: "")
        
        // Handle IPv6 format [::1]:3000 or [::]:3000
        if cleaned.hasPrefix("[") {
            guard let bracketEnd = cleaned.lastIndex(of: "]") else { return nil }
            let colonIndex = cleaned.index(after: bracketEnd)
            guard colonIndex < cleaned.endIndex, cleaned[colonIndex] == ":" else { return nil }

            let portStart = cleaned.index(after: colonIndex)
            let portString = String(cleaned[portStart...]).trimmingCharacters(in: .whitespaces)
            return validPort(from: portString)
        }
        
        // Handle wildcard *:3000
        if cleaned.hasPrefix("*:") {
            let portString = String(cleaned.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return validPort(from: portString)
        }
        
        // Handle standard format 127.0.0.1:3000
        guard let colonIndex = cleaned.lastIndex(of: ":") else { return nil }
        let portString = String(cleaned[cleaned.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
        return validPort(from: portString)
    }

    private static func validPort(from value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n,;)"))

        if let port = Int(trimmed), (1...65_535).contains(port) {
            return port
        }

        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.lowercased()
        guard let entry = normalized.withCString({ getservbyname($0, "tcp") }) else {
            return nil
        }

        let networkPort = UInt16(truncatingIfNeeded: entry.pointee.s_port)
        let resolved = Int(UInt16(bigEndian: networkPort))
        guard (1...65_535).contains(resolved) else {
            return nil
        }
        return resolved
    }
}
