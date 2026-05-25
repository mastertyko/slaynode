import Foundation
import SwiftData

enum WorkspaceHistoryHeuristics {
    private static let disallowedNames: Set<String> = [
        ".build",
        ".codex",
        ".git",
        ".hg",
        ".omx",
        ".swiftpm",
        ".svn",
        ".bin",
        ".cache",
        ".claude",
        ".next",
        ".nuxt",
        ".pnpm-store",
        ".svelte-kit",
        ".turbo",
        ".yarn",
        "build",
        "cache",
        "coverage",
        "dist",
        "deriveddata",
        "node_modules",
        "out",
        "storybook-static",
        "temp",
        "tmp",
        "vitest"
    ]

    static func isEligibleRecentWorkspace(
        _ workspace: WorkspaceIdentity,
        fileManager: FileManager = .default
    ) -> Bool {
        let trimmedName = workspace.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        guard !trimmedName.hasPrefix(".") else { return false }
        guard !disallowedNames.contains(trimmedName.lowercased()) else { return false }
        guard !looksOpaqueIdentifier(trimmedName) else { return false }
        guard !hasDisallowedPathComponent(workspace.rootPath) else { return false }
        guard fileManager.fileExists(atPath: workspace.rootPath) else { return false }
        return true
    }

    static func looksOpaqueIdentifier(_ value: String) -> Bool {
        let normalized = value.lowercased()
        guard normalized.count >= 12 else { return false }

        let hexOnly = normalized.allSatisfy { $0.isHexDigit }
        if hexOnly { return true }

        let components = normalized.split(separator: "-")
        if components.count == 5, components.allSatisfy({ $0.allSatisfy(\.isHexDigit) }) {
            return true
        }

        return false
    }

    private static func hasDisallowedPathComponent(_ path: String) -> Bool {
        let components = URL(fileURLWithPath: path).standardized.pathComponents.map { $0.lowercased() }
        return components.contains { disallowedNames.contains($0) }
    }
}

@MainActor
final class ServiceHistoryStore {
    let container: ModelContainer
    let modelContext: ModelContext

    init(container: ModelContainer) {
        self.container = container
        self.modelContext = container.mainContext
    }

    func record(snapshot: ServiceSnapshot) {
        for service in snapshot.services {
            upsert(service: service, seenAt: snapshot.generatedAt)
        }

        for workspace in Set(snapshot.services.compactMap(\.workspace))
            where WorkspaceHistoryHeuristics.isEligibleRecentWorkspace(workspace) {
            upsert(workspace: workspace, seenAt: snapshot.generatedAt, incrementOpenCount: true)
        }

        saveIfNeeded()
    }

    func record(action: ServiceAction, on service: ManagedService, outcome: String) {
        let now = Date()
        let actionRecord = ServiceActionRecord(
            serviceID: service.id,
            serviceName: service.name,
            actionRawValue: action.rawValue,
            outcome: outcome,
            timestamp: now
        )
        modelContext.insert(actionRecord)

        let serviceRecord = fetchServiceRecord(id: service.id) ?? {
            let record = ServiceHistoryRecord(
                id: service.id,
                name: service.name,
                kindRawValue: service.kind.rawValue,
                sourceRawValue: service.source.title,
                workspaceID: service.workspace?.id,
                workspaceName: service.workspace?.name,
                workspacePath: service.workspace?.rootPath,
                statusRawValue: service.status.rawValue,
                lastSeenAt: now
            )
            modelContext.insert(record)
            return record
        }()

        serviceRecord.lastActionRawValue = action.rawValue
        serviceRecord.lastActionAt = now
        serviceRecord.lastSeenAt = now
        serviceRecord.name = service.name
        serviceRecord.kindRawValue = service.kind.rawValue
        serviceRecord.sourceRawValue = service.source.title
        serviceRecord.workspaceID = service.workspace?.id
        serviceRecord.workspaceName = service.workspace?.name
        serviceRecord.workspacePath = service.workspace?.rootPath
        serviceRecord.statusRawValue = service.status.rawValue

        if let workspace = service.workspace,
           WorkspaceHistoryHeuristics.isEligibleRecentWorkspace(workspace) {
            upsert(workspace: workspace, seenAt: now, incrementOpenCount: false)
        }

        saveIfNeeded()
    }

    func recentWorkspaces(limit: Int = 8) -> [WorkspaceIdentity] {
        guard limit > 0 else { return [] }

        pruneWorkspaceHistory()

        var descriptor = FetchDescriptor<WorkspaceHistoryRecord>(
            sortBy: [SortDescriptor(\.lastSeenAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit * 4

        let records = (try? modelContext.fetch(descriptor)) ?? []
        var seenIDs = Set<String>()
        var resolved: [WorkspaceIdentity] = []

        for record in records {
            guard let workspace = ServiceHeuristics.workspaceIdentity(from: record.rootPath) else { continue }
            guard seenIDs.insert(workspace.id).inserted else { continue }
            resolved.append(workspace)

            if resolved.count == limit {
                break
            }
        }

        return resolved
    }

    func recentActions(limit: Int = 10) -> [ServiceActionSummary] {
        guard limit > 0 else { return [] }

        var descriptor = FetchDescriptor<ServiceActionRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = max(limit * 8, limit + 32)

        let records = (try? modelContext.fetch(descriptor)) ?? []
        var summaries: [ServiceActionSummary] = []

        for record in records {
            guard let action = ServiceAction(rawValue: record.actionRawValue) else { continue }
            summaries.append(ServiceActionSummary(
                id: record.id,
                serviceID: record.serviceID,
                serviceName: record.serviceName,
                action: action,
                outcome: record.outcome,
                timestamp: record.timestamp
            ))

            if summaries.count == limit {
                break
            }
        }

        return summaries
    }

    func loadWindowState(id: String) -> PersistedWindowState? {
        guard let record = fetchWindowStateRecord(id: id) else { return nil }
        return PersistedWindowState(
            selectedWorkspaceID: record.selectedWorkspaceID,
            selectedServiceID: record.selectedServiceID,
            searchText: record.searchText,
            inspectorVisible: record.inspectorVisible
        )
    }

    func saveWindowState(
        id: String,
        selectedWorkspaceID: String?,
        selectedServiceID: String?,
        searchText: String,
        inspectorVisible: Bool
    ) {
        let record = fetchWindowStateRecord(id: id) ?? {
            let newRecord = WindowStateRecord(
                id: id,
                selectedWorkspaceID: selectedWorkspaceID,
                selectedServiceID: selectedServiceID,
                searchText: searchText,
                inspectorVisible: inspectorVisible,
                updatedAt: .now
            )
            modelContext.insert(newRecord)
            return newRecord
        }()

        record.selectedWorkspaceID = selectedWorkspaceID
        record.selectedServiceID = selectedServiceID
        record.searchText = searchText
        record.inspectorVisible = inspectorVisible
        record.updatedAt = .now
        saveIfNeeded()
    }

    private func upsert(service: ManagedService, seenAt: Date) {
        let record = fetchServiceRecord(id: service.id) ?? {
            let newRecord = ServiceHistoryRecord(
                id: service.id,
                name: service.name,
                kindRawValue: service.kind.rawValue,
                sourceRawValue: service.source.title,
                workspaceID: service.workspace?.id,
                workspaceName: service.workspace?.name,
                workspacePath: service.workspace?.rootPath,
                statusRawValue: service.status.rawValue,
                lastSeenAt: seenAt
            )
            modelContext.insert(newRecord)
            return newRecord
        }()

        record.name = service.name
        record.kindRawValue = service.kind.rawValue
        record.sourceRawValue = service.source.title
        record.workspaceID = service.workspace?.id
        record.workspaceName = service.workspace?.name
        record.workspacePath = service.workspace?.rootPath
        record.statusRawValue = service.status.rawValue
        record.lastSeenAt = seenAt
    }

    private func upsert(workspace: WorkspaceIdentity, seenAt: Date, incrementOpenCount: Bool) {
        let record: WorkspaceHistoryRecord
        if let existingRecord = fetchWorkspaceRecord(id: workspace.id) {
            record = existingRecord
            if incrementOpenCount {
                record.openCount += 1
            }
        } else {
            record = WorkspaceHistoryRecord(
                id: workspace.id,
                name: workspace.name,
                rootPath: workspace.rootPath,
                lastSeenAt: seenAt,
                openCount: incrementOpenCount ? 1 : 0
            )
            modelContext.insert(record)
        }

        record.name = workspace.name
        record.rootPath = workspace.rootPath
        record.lastSeenAt = seenAt
    }

    private func fetchWorkspaceRecord(id: String) -> WorkspaceHistoryRecord? {
        let predicate = #Predicate<WorkspaceHistoryRecord> { $0.id == id }
        let descriptor = FetchDescriptor<WorkspaceHistoryRecord>(predicate: predicate)
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchServiceRecord(id: String) -> ServiceHistoryRecord? {
        let predicate = #Predicate<ServiceHistoryRecord> { $0.id == id }
        let descriptor = FetchDescriptor<ServiceHistoryRecord>(predicate: predicate)
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchWindowStateRecord(id: String) -> WindowStateRecord? {
        let predicate = #Predicate<WindowStateRecord> { $0.id == id }
        let descriptor = FetchDescriptor<WindowStateRecord>(predicate: predicate)
        return try? modelContext.fetch(descriptor).first
    }

    private func pruneWorkspaceHistory() {
        let descriptor = FetchDescriptor<WorkspaceHistoryRecord>(
            sortBy: [SortDescriptor(\.lastSeenAt, order: .reverse)]
        )
        let records = (try? modelContext.fetch(descriptor)) ?? []
        guard !records.isEmpty else { return }

        var keptCanonicalIDs = Set<String>()

        for record in records {
            guard let canonicalWorkspace = ServiceHeuristics.workspaceIdentity(from: record.rootPath),
                  WorkspaceHistoryHeuristics.isEligibleRecentWorkspace(canonicalWorkspace) else {
                modelContext.delete(record)
                continue
            }

            guard keptCanonicalIDs.insert(canonicalWorkspace.id).inserted else {
                modelContext.delete(record)
                continue
            }

            record.name = canonicalWorkspace.name
            record.rootPath = canonicalWorkspace.rootPath
        }

        saveIfNeeded()
    }

    private func saveIfNeeded() {
        guard modelContext.hasChanges else { return }

        do {
            try modelContext.save()
        } catch {
            Log.general.error("Failed to persist service history: \(error.localizedDescription)")
        }
    }
}
