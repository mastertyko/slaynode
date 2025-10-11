import Foundation

struct NodeProcess: Identifiable, Equatable {
    let pid: Int32
    let executable: String
    let command: String
    let arguments: [String]
    let ports: [Int]
    let uptime: TimeInterval
    let startTime: Date
    let workingDirectory: String?
    let descriptor: ServerDescriptor

    var id: Int32 { pid }
}

struct ServerDescriptor: Equatable {
    let name: String
    let details: String?

    static let unknown = ServerDescriptor(name: "Node.js", details: nil)
}
