import Foundation
import SwiftData

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

        for workspace in Set(snapshot.services.compactMap(\.workspace)) {
            upsert(workspace: workspace, seenAt: snapshot.generatedAt)
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
        serviceRecord.statusRawValue = service.status.rawValue

        if let workspace = service.workspace {
            upsert(workspace: workspace, seenAt: now)
        }

        saveIfNeeded()
    }

    func recentWorkspaces(limit: Int = 8) -> [WorkspaceIdentity] {
        var descriptor = FetchDescriptor<WorkspaceHistoryRecord>(
            sortBy: [SortDescriptor(\.lastSeenAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        let records = (try? modelContext.fetch(descriptor)) ?? []
        return records.compactMap {
            guard !$0.rootPath.isEmpty, $0.rootPath != "/" else { return nil }
            return WorkspaceIdentity(id: $0.id, name: $0.name, rootPath: $0.rootPath)
        }
    }

    func recentActions(limit: Int = 10) -> [ServiceActionSummary] {
        var descriptor = FetchDescriptor<ServiceActionRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        let records = (try? modelContext.fetch(descriptor)) ?? []
        return records.compactMap { record in
            guard let action = ServiceAction(rawValue: record.actionRawValue) else { return nil }
            return ServiceActionSummary(
                id: record.id,
                serviceID: record.serviceID,
                serviceName: record.serviceName,
                action: action,
                outcome: record.outcome,
                timestamp: record.timestamp
            )
        }
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

    private func upsert(workspace: WorkspaceIdentity, seenAt: Date) {
        let record = fetchWorkspaceRecord(id: workspace.id) ?? {
            let newRecord = WorkspaceHistoryRecord(
                id: workspace.id,
                name: workspace.name,
                rootPath: workspace.rootPath,
                lastSeenAt: seenAt
            )
            modelContext.insert(newRecord)
            return newRecord
        }()

        record.name = workspace.name
        record.rootPath = workspace.rootPath
        record.lastSeenAt = seenAt
        record.openCount += 1
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

    private func saveIfNeeded() {
        guard modelContext.hasChanges else { return }

        do {
            try modelContext.save()
        } catch {
            Log.general.error("Failed to persist service history: \(error.localizedDescription)")
        }
    }
}
