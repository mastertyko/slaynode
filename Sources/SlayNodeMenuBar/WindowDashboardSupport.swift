import SwiftUI

struct RuntimeWorkspaceSection: Identifiable, Equatable {
    let id: String
    let title: String
    let path: String?
    let processes: [NodeProcessItemViewModel]
    let dominantCategory: String?
    let serviceCount: Int
    let actualPortCount: Int
    let likelyPortCount: Int
    let roleSummary: String
}

enum DetectionConfidenceKind: Equatable {
    case high
    case medium
    case review

    var tint: Color {
        switch self {
        case .high:
            return .green
        case .medium:
            return .orange
        case .review:
            return .red
        }
    }
}

struct DetectionConfidence: Equatable {
    let kind: DetectionConfidenceKind
    let label: String
    let title: String
    let detail: String
    let systemImage: String

    var tint: Color { kind.tint }
}

struct DetectionSignal: Equatable {
    let title: String
    let detail: String
    let systemImage: String
}

func makeWorkspaceSections(from processes: [NodeProcessItemViewModel]) -> [RuntimeWorkspaceSection] {
    var groups: [String: [NodeProcessItemViewModel]] = [:]
    var order: [String] = []

    for process in processes {
        let key = process.workingDirectory ?? "standalone-\(process.id)"
        if groups[key] == nil {
            groups[key] = []
            order.append(key)
        }
        groups[key, default: []].append(process)
    }

    return order.compactMap { key in
        guard let groupedProcesses = groups[key], !groupedProcesses.isEmpty else { return nil }

        let representative = groupedProcesses[0]
        let roleSummary = groupedProcesses
            .compactMap(\.categoryBadge)
            .uniqued()
            .prefix(2)
            .joined(separator: " + ")

        let title: String
        if let projectName = representative.projectName {
            title = projectName
        } else if let workingDirectory = representative.workingDirectory {
            let fallback = URL(fileURLWithPath: workingDirectory).lastPathComponent
            title = fallback.isEmpty ? representative.title : fallback
        } else {
            title = representative.title
        }

        return RuntimeWorkspaceSection(
            id: key,
            title: title,
            path: representative.workingDirectory,
            processes: groupedProcesses,
            dominantCategory: dominantCategory(in: groupedProcesses),
            serviceCount: groupedProcesses.count,
            actualPortCount: groupedProcesses.reduce(0) { $0 + $1.actualPorts.count },
            likelyPortCount: groupedProcesses.reduce(0) { $0 + $1.likelyPorts.count },
            roleSummary: roleSummary
        )
    }
}

func dominantCategory(in processes: [NodeProcessItemViewModel]) -> String? {
    var counts: [String: Int] = [:]
    var firstSeenIndex: [String: Int] = [:]

    for (index, category) in processes.compactMap(\.categoryBadge).enumerated() {
        counts[category, default: 0] += 1
        firstSeenIndex[category] = firstSeenIndex[category] ?? index
    }

    return counts.max { lhs, rhs in
        if lhs.value != rhs.value {
            return lhs.value < rhs.value
        }

        let lhsIndex = firstSeenIndex[lhs.key] ?? .max
        let rhsIndex = firstSeenIndex[rhs.key] ?? .max
        return lhsIndex > rhsIndex
    }?.key
}

func detectionConfidence(for process: NodeProcessItemViewModel) -> DetectionConfidence {
    var score = 0

    if !process.actualPorts.isEmpty {
        score += 3
    } else if !process.likelyPorts.isEmpty {
        score += 1
    }

    if process.workingDirectory != nil {
        score += 1
    }

    if process.projectName != nil {
        score += 1
    }

    if process.descriptor != .unknown {
        score += 2
    }

    if process.descriptor.details != nil {
        score += 1
    }

    if process.descriptor.packageManager != nil || process.descriptor.script != nil {
        score += 1
    }

    switch score {
    case 6...:
        return DetectionConfidence(
            kind: .high,
            label: "High confidence",
            title: "Strong runtime match",
            detail: "SlayNode has multiple live signals that agree on what this runtime is and where it belongs.",
            systemImage: "checkmark.shield.fill"
        )
    case 4...5:
        return DetectionConfidence(
            kind: .medium,
            label: "Medium confidence",
            title: "Good match with some inference",
            detail: "The runtime looks credible, but part of the identification still depends on inferred defaults or wrapper commands.",
            systemImage: "checkmark.shield"
        )
    default:
        return DetectionConfidence(
            kind: .review,
            label: "Review before slaying",
            title: "Mostly inferred",
            detail: "SlayNode sees meaningful signals, but you should double-check the command and workspace before taking action.",
            systemImage: "exclamationmark.shield"
        )
    }
}

func detectionSignals(for process: NodeProcessItemViewModel) -> [DetectionSignal] {
    var signals: [DetectionSignal] = []

    if !process.actualPorts.isEmpty {
        let ports = process.actualPorts.map(String.init).joined(separator: ", ")
        signals.append(
            DetectionSignal(
                title: "Live port evidence",
                detail: "Listening sockets were resolved on \(ports).",
                systemImage: "dot.radiowaves.left.and.right"
            )
        )
    } else if !process.likelyPorts.isEmpty {
        let ports = process.likelyPorts.map(String.init).joined(separator: ", ")
        signals.append(
            DetectionSignal(
                title: "Likely port hints",
                detail: "Ports \(ports) were inferred from the detected tooling and defaults.",
                systemImage: "questionmark.circle"
            )
        )
    }

    if let projectName = process.projectName, let workingDirectory = process.workingDirectory {
        signals.append(
            DetectionSignal(
                title: "Workspace resolved",
                detail: "\(projectName) was resolved from \(workingDirectory).",
                systemImage: "folder"
            )
        )
    } else if let workingDirectory = process.workingDirectory {
        signals.append(
            DetectionSignal(
                title: "Folder context",
                detail: "This runtime is attached to \(workingDirectory).",
                systemImage: "folder.badge.gearshape"
            )
        )
    }

    if process.descriptor != .unknown {
        let runtime = process.descriptor.runtime.map { " running on \($0)" } ?? ""
        signals.append(
            DetectionSignal(
                title: "Known runtime signature",
                detail: "Matched as \(process.descriptor.displayName)\(runtime).",
                systemImage: "sparkles"
            )
        )
    }

    if let packageManager = process.descriptor.packageManager, let script = process.descriptor.script {
        signals.append(
            DetectionSignal(
                title: "Wrapper command",
                detail: "The command looks like \(packageManager) launching the \(script) script.",
                systemImage: "terminal"
            )
        )
    } else if let details = process.descriptor.details {
        signals.append(
            DetectionSignal(
                title: "Command signal",
                detail: details,
                systemImage: "terminal"
            )
        )
    }

    return Array(signals.prefix(4))
}

func slayScopeNarrative(for process: NodeProcessItemViewModel) -> String {
    if process.descriptor.packageManager != nil {
        return "Slay stops the selected process group, so the package-manager wrapper and child runtime it launched should stop together."
    }

    if !process.actualPorts.isEmpty {
        return "Slay stops the selected process group. Any workers or child processes tied to the same runtime should stop, and live ports like \(process.actualPorts.map { ":\($0)" }.joined(separator: ", ")) should disappear."
    }

    return "Slay stops the selected process group, which can include helper workers or child processes launched together with this runtime."
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

extension NodeProcessItemViewModel {
    var actualPorts: [Int] {
        portBadges
            .filter { !$0.isLikely }
            .compactMap { parsePort(from: $0.text) }
    }

    var likelyPorts: [Int] {
        portBadges
            .filter(\.isLikely)
            .compactMap { parsePort(from: $0.text) }
    }

    private func parsePort(from text: String) -> Int? {
        let cleaned = text
            .replacingOccurrences(of: "≈ ", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Int(cleaned)
    }
}
