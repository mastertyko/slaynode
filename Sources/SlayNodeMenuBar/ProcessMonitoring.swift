import Combine
import Foundation

@MainActor
protocol ProcessMonitoring: AnyObject {
    var processesPublisher: AnyPublisher<[NodeProcess], Never> { get }
    var errorsPublisher: AnyPublisher<Error, Never> { get }

    func start()
    func stop()
    func updateInterval(_ newInterval: TimeInterval)
    func refresh() async
    func verifyProcess(pid: Int32, expectedHash: Int) async -> Bool
}
