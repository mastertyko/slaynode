import Foundation

enum ProcessControlErrorMessages {
    static let invalidProcessID = "Invalid process ID."
    static let permissionDenied = "Permission denied to stop the process."
    static let processGroupNotFound = "Could not find process group."

    static func terminationFailed(errno status: Int32) -> String {
        "Could not stop the process (errno: \(status))."
    }
}
