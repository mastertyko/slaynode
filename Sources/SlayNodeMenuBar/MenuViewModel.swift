import Combine
import Foundation

struct NodeProcessItemViewModel: Identifiable, Equatable {
    let id: Int32
    let pid: Int32
    let title: String
    let subtitle: String
    let details: String
    let portsDescription: String
    let uptimeDescription: String
    let startTimeDescription: String
    let command: String
    let workingDirectory: String?
    let descriptor: ServerDescriptor
    let isStopping: Bool
}

@MainActor
final class MenuViewModel: ObservableObject {
    @Published var isLoading: Bool = true
    @Published var processes: [NodeProcessItemViewModel] = []
    @Published var lastError: String?
    @Published var lastUpdated: Date?

    let preferences: PreferencesStore

    private let monitor: ProcessMonitor
    private let killer = ProcessKiller()
    private var cancellables: Set<AnyCancellable> = []
    private var stoppingPids: Set<Int32> = []
    private var latestProcesses: [NodeProcess] = []

    init(preferences: PreferencesStore = PreferencesStore(), monitor: ProcessMonitor = ProcessMonitor()) {
        self.preferences = preferences
        self.monitor = monitor

        bindMonitor()
        bindPreferences()

        monitor.updateInterval(preferences.refreshInterval)
        monitor.start()
        monitor.refresh()
    }

    func refresh() {
        isLoading = true
        monitor.refresh()
    }

    func stopProcess(_ pid: Int32) {
        guard pid > 0 else { return }
        guard !stoppingPids.contains(pid) else { return }

        stoppingPids.insert(pid)
        publishLatest()

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try self.killer.terminate(pid: pid)
                await MainActor.run {
                    self.stoppingPids.remove(pid)
                    self.monitor.refresh()
                }
            } catch {
                await MainActor.run {
                    self.stoppingPids.remove(pid)
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    private func bindMonitor() {
        monitor.processesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] processes in
                guard let self else { return }
                self.latestProcesses = processes
                self.lastUpdated = Date()
                self.isLoading = false
                self.publishLatest()
            }
            .store(in: &cancellables)

        monitor.errorsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.lastError = error.localizedDescription
            }
            .store(in: &cancellables)
    }

    private func bindPreferences() {
        preferences.$refreshInterval
            .removeDuplicates()
            .sink { [weak self] newValue in
                self?.monitor.updateInterval(newValue)
            }
            .store(in: &cancellables)
    }

    private func publishLatest() {
        processes = buildViewModels(from: latestProcesses)
    }

    private func buildViewModels(from processes: [NodeProcess]) -> [NodeProcessItemViewModel] {
        let sorted = processes.sorted { lhs, rhs in
            let lhsPort = lhs.ports.min() ?? Int.max
            let rhsPort = rhs.ports.min() ?? Int.max
            if lhsPort != rhsPort {
                return lhsPort < rhsPort
            }
            if lhs.descriptor.name != rhs.descriptor.name {
                return lhs.descriptor.name.localizedCaseInsensitiveCompare(rhs.descriptor.name) == .orderedAscending
            }
            return lhs.pid < rhs.pid
        }

        return sorted.map { process in
            let title = makeTitle(for: process)
            let subtitle = process.command
            let portText = makePortText(for: process)
            let uptimeText = Self.durationFormatter.string(from: process.uptime) ?? "-"
            let startText = Self.relativeFormatter.localizedString(for: process.startTime, relativeTo: Date())
            let details = makeDetails(for: process, uptimeText: uptimeText)
            let isStopping = stoppingPids.contains(process.pid)

            return NodeProcessItemViewModel(
                id: process.pid,
                pid: process.pid,
                title: title,
                subtitle: subtitle,
                details: details,
                portsDescription: portText,
                uptimeDescription: uptimeText,
                startTimeDescription: startText,
                command: process.command,
                workingDirectory: process.workingDirectory,
                descriptor: process.descriptor,
                isStopping: isStopping
            )
        }
    }

    private func makeTitle(for process: NodeProcess) -> String {
        let base = process.descriptor.name
        guard !process.ports.isEmpty else { return base }
        let ports = process.ports.map(String.init).joined(separator: ", ")
        return "\(base) • :\(ports)"
    }

    private func makePortText(for process: NodeProcess) -> String {
        guard !process.ports.isEmpty else { return "Port: okänd" }
        if process.ports.count == 1 {
            return "Port: \(process.ports[0])"
        }
        return "Portar: \(process.ports.map(String.init).joined(separator: ", "))"
    }

    private func makeDetails(for process: NodeProcess, uptimeText: String) -> String {
        var chips: [String] = ["PID \(process.pid)", "Uptime \(uptimeText)"]
        if let dir = process.workingDirectory {
            chips.append(dir)
        }
        if let details = process.descriptor.details {
            chips.append(details)
        }
        return chips.joined(separator: " · ")
    }

    @MainActor private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()

    @MainActor private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
