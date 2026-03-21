import Foundation

protocol ShellExecuting: Sendable {
    func run(
        _ launchPath: String,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> (status: Int32, output: String)
}

struct SystemShellExecutor: ShellExecuting {
    func run(
        _ launchPath: String,
        arguments: [String],
        timeout: TimeInterval = Constants.Timeout.commandTimeout
    ) async throws -> (status: Int32, output: String) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: launchPath)
                process.arguments = arguments
                
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                
                let timeoutWork = DispatchWorkItem { [weak process] in
                    process?.terminate()
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
                
                do {
                    try process.run()
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    timeoutWork.cancel()
                    
                    let status = process.terminationStatus
                    let maxSize = Constants.Buffer.maxOutputSize
                    let trimmedData = outputData.count > maxSize ? outputData.subdata(in: 0..<maxSize) : outputData
                    let outputString = String(data: trimmedData, encoding: .utf8) ?? ""
                    
                    continuation.resume(returning: (status, outputString))
                } catch {
                    timeoutWork.cancel()
                    process.terminate()
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

#if DEBUG
final class MockShellExecutor: ShellExecuting, @unchecked Sendable {
    var responses: [String: (status: Int32, output: String)] = [:]
    var defaultResponse: (status: Int32, output: String) = (0, "")
    
    func run(
        _ launchPath: String,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> (status: Int32, output: String) {
        let key = "\(launchPath) \(arguments.joined(separator: " "))"
        return responses[key] ?? defaultResponse
    }
}
#endif
