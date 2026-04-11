import Darwin
import Foundation

enum ProcessTerminationError: Error, LocalizedError {
    case invalidPid
    case permissionDenied
    case terminationFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidPid:
            return "Invalid process ID."
        case .permissionDenied:
            return "Missing permission to stop the process."
        case let .terminationFailed(status):
            return "Could not stop the process (errno: \(status))."
        }
    }
}

struct ProcessKiller {
    func terminate(pid: Int32, forceAfter gracePeriod: TimeInterval = 1.5) async throws {
        guard pid > 0 else { throw ProcessTerminationError.invalidPid }

        if kill(pid, SIGTERM) != 0 {
            if errno == EPERM {
                throw ProcessTerminationError.permissionDenied
            }
            throw ProcessTerminationError.terminationFailed(errno)
        }

        guard gracePeriod > 0 else { return }

        let deadline = Date().addingTimeInterval(gracePeriod)
        while Date() < deadline {
            if kill(pid, 0) == -1 && errno == ESRCH {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        if kill(pid, SIGKILL) != 0 {
            if errno == EPERM {
                throw ProcessTerminationError.permissionDenied
            }
            throw ProcessTerminationError.terminationFailed(errno)
        }
    }
}
