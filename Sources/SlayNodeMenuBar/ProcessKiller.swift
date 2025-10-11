import Darwin
import Foundation

enum ProcessTerminationError: Error, LocalizedError {
    case invalidPid
    case permissionDenied
    case terminationFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidPid:
            return "Ogiltigt process-id."
        case .permissionDenied:
            return "Saknar behörighet att stoppa processen."
        case let .terminationFailed(status):
            return "Kunde inte stoppa processen (errno: \(status))."
        }
    }
}

struct ProcessKiller {
    func terminate(pid: Int32, forceAfter gracePeriod: TimeInterval = 1.5) throws {
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
            Thread.sleep(forTimeInterval: 0.1)
        }

        if kill(pid, SIGKILL) != 0 {
            if errno == EPERM {
                throw ProcessTerminationError.permissionDenied
            }
            throw ProcessTerminationError.terminationFailed(errno)
        }
    }
}
