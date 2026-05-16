import Combine
import Foundation

enum ProcessMonitorError: Error, LocalizedError {
    case commandFailed(String, Int32)
    case malformedOutput

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, status):
            return "Command \(command) failed with status \(status)."
        case .malformedOutput:
            return "Could not parse process list."
        }
    }
}

@MainActor
final class ProcessMonitor: ProcessMonitoring {
    private var interval: TimeInterval
    private var isCollecting = false
    private var hasPendingRefresh = false
    private var collectionTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private let discovery: ProcessDiscovery

    private let processesSubject = CurrentValueSubject<[NodeProcess], Never>([])
    private let errorsSubject = PassthroughSubject<Error, Never>()

    var processesPublisher: AnyPublisher<[NodeProcess], Never> {
        processesSubject.eraseToAnyPublisher()
    }

    var errorsPublisher: AnyPublisher<Error, Never> {
        errorsSubject.eraseToAnyPublisher()
    }

    init(
        interval: TimeInterval = Constants.Preferences.defaultRefreshInterval,
        shell: any ShellExecuting = SystemShellExecutor()
    ) {
        self.interval = Self.normalizedRefreshInterval(interval)
        self.discovery = ProcessDiscovery(shell: shell)
    }

    func start() {
        Log.process.info("ProcessMonitor starting...")
        startTimer()
    }

    func stop() {
        collectionTask?.cancel()
        stopTimer()
    }

    func updateInterval(_ newInterval: TimeInterval) {
        let normalized = Self.normalizedRefreshInterval(newInterval)
        guard abs(interval - normalized) > 0.01 else { return }
        interval = normalized
        restartTimer()
    }

    func refresh() async {
        await performCollect()
    }

    func verifyProcess(pid: Int32, expectedHash: Int) async -> Bool {
        await discovery.verifyProcess(pid: pid, expectedHash: expectedHash)
    }

    deinit {
        timerTask?.cancel()
        timerTask = nil
        collectionTask?.cancel()
        collectionTask = nil
    }

    static func normalizedRefreshInterval(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else {
            return Constants.Preferences.defaultRefreshInterval
        }

        let range = Constants.Preferences.refreshIntervalRange
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private func startTimer() {
        stopTimer()

        timerTask = Task { @MainActor [weak self] in
            guard let self = self else { return }

            try? await Task.sleep(nanoseconds: Constants.Timeout.initialScanDelay)

            while !Task.isCancelled {
                self.collectionTask?.cancel()

                self.collectionTask = Task {
                    await self.performCollect()
                }

                try? await Task.sleep(nanoseconds: UInt64(self.interval * Double(Constants.Time.nanosecondsPerSecond)))
            }
        }
    }

    private func restartTimer() {
        collectionTask?.cancel()
        startTimer()
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
        collectionTask?.cancel()
        collectionTask = nil
    }

    private func performCollect() async {
        guard !isCollecting else {
            hasPendingRefresh = true
            return
        }

        isCollecting = true

        let processes = await discovery.discoverProcesses()

        guard !Task.isCancelled else {
            isCollecting = false
            return
        }

        processesSubject.send(processes)
        isCollecting = false

        if hasPendingRefresh && !Task.isCancelled {
            hasPendingRefresh = false
            await performCollect()
        }
    }
}
