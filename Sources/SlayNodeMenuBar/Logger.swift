import Foundation
import os.log

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.slaynode"
    
    static let process = Logger(subsystem: subsystem, category: "process")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let general = Logger(subsystem: subsystem, category: "general")
    static let network = Logger(subsystem: subsystem, category: "network")
}
