import Foundation

struct NodeProcess: Identifiable, Equatable, Sendable {
    let pid: Int32
    let ppid: Int32
    let executable: String
    let command: String
    let arguments: [String]
    let ports: [Int]
    let uptime: TimeInterval
    let startTime: Date
    let workingDirectory: String?
    let descriptor: ServerDescriptor
    let commandHash: Int

    var id: Int32 { pid }

    static func stableCommandHash(for command: String) -> Int {
        var hash: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211

        for byte in command.utf8 {
            hash ^= UInt64(byte)
            hash &*= prime
        }

        return Int(truncatingIfNeeded: hash)
    }
}

struct ServerDescriptor: Equatable, Sendable {
    enum Category: String, Sendable {
        case webFramework
        case bundler
        case componentWorkbench
        case mobile
        case backend
        case monorepo
        case utility
        case runtime

        var displayName: String {
            switch self {
            case .webFramework: return "Web framework"
            case .bundler: return "Bundler"
            case .componentWorkbench: return "Component workbench"
            case .mobile: return "Mobile"
            case .backend: return "API/Backend"
            case .monorepo: return "Monorepo tool"
            case .utility: return "Utility"
            case .runtime: return "Runtime"
            }
        }
    }

    let name: String
    let displayName: String
    let category: Category
    let runtime: String?
    let packageManager: String?
    let script: String?
    let details: String?
    let portHints: [Int]

    static let unknown = ServerDescriptor(
        name: "Node.js",
        displayName: "Node.js",
        category: .runtime,
        runtime: "Node.js",
        packageManager: nil,
        script: nil,
        details: nil,
        portHints: []
    )

    func summaryDetails() -> [String] {
        var components: [String] = [category.displayName]

        if let packageManager {
            if let script {
                components.append("\(packageManager) \(script)")
            } else {
                components.append(packageManager)
            }
        } else if let script {
            components.append(script)
        }

        if let runtime {
            components.append(runtime)
        }

        if let details {
            components.append(details)
        }

        if components.isEmpty {
            return [category.displayName]
        }

        return components
    }
}
