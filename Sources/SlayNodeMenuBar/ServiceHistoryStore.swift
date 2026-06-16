import Foundation
import SwiftData

enum WorkspaceHistoryHeuristics {
    private static let disallowedNames: Set<String> = [
        ".codex",
        ".git",
        ".hg",
        ".idea",
        ".omx",
        ".sisyphus",
        ".svn",
        ".vscode",
        ".zed",
        ".bin",
        ".build",
        ".angular",
        ".aws-sam",
        ".cache",
        ".claude",
        ".cursor",
        ".dart_tool",
        ".direnv",
        ".expo",
        ".gradle",
        ".mypy_cache",
        ".next",
        ".nx",
        ".npm",
        ".nuxt",
        ".output",
        ".parcel-cache",
        ".playwright",
        ".pnpm-store",
        ".pytest_cache",
        ".ruff_cache",
        ".swiftpm",
        ".svelte-kit",
        ".terraform",
        ".turbo",
        ".venv",
        ".vercel",
        ".vite",
        ".wrangler",
        ".yarn",
        ".serverless",
        ".sst",
        "build",
        "cache",
        "coverage",
        "deriveddata",
        "dist",
        "node_modules",
        "out",
        "storybook-static",
        "temp",
        "target",
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
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: workspace.rootPath, isDirectory: &isDirectory),
              isDirectory.boolValue else { return false }
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
        if containsDerivedDataComponents(components) {
            return true
        }
        return components.contains { disallowedNames.contains($0) }
    }

    private static func containsDerivedDataComponents(_ components: [String]) -> Bool {
        guard components.count >= 4 else { return false }

        for index in 0...(components.count - 4) {
            let window = Array(components[index..<(index + 4)])
            if window == ["library", "developer", "xcode", "deriveddata"] {
                return true
            }
        }

        return false
    }
}

private enum PersistedTextSanitizer {
    private static let collapsibleWhitespace = CharacterSet.whitespacesAndNewlines
    private static let disallowedIdentifierScalars = CharacterSet.newlines
        .union(.controlCharacters)
        .subtracting(CharacterSet(charactersIn: " "))
    static func identifier(_ value: String?) -> String? {
        guard let value else { return nil }
        guard value.rangeOfCharacter(from: disallowedIdentifierScalars) == nil else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func path(_ value: String?) -> String? {
        sanitize(value, separator: " ")
    }

    static func text(_ value: String?) -> String? {
        sanitize(value, separator: " ")
    }

    private static func sanitize(_ value: String?, separator: String) -> String? {
        guard let value else { return nil }

        let pieces = value.components(separatedBy: collapsibleWhitespace)
            .filter { !$0.isEmpty }
        let sanitized = pieces.joined(separator: separator)
        return sanitized.isEmpty ? nil : sanitized
    }
}

@MainActor
final class ServiceHistoryStore {
    private enum Retention {
        static let maxWorkspaceCount = 24
        static let maxWorkspaceAge: TimeInterval = 60 * 60 * 24 * 120
        static let maxActionCount = 200
        static let maxActionAge: TimeInterval = 60 * 60 * 24 * 45
        static let maxServiceCount = 400
        static let maxServiceAge: TimeInterval = 60 * 60 * 24 * 30
    }

    let container: ModelContainer
    let modelContext: ModelContext

    init(container: ModelContainer) {
        self.container = container
        self.modelContext = container.mainContext
    }

    func record(snapshot: ServiceSnapshot) {
        pruneServiceHistory(referenceDate: snapshot.generatedAt)

        for service in snapshot.services {
            upsert(service: service, seenAt: snapshot.generatedAt)
        }

        for workspace in Set(snapshot.services.compactMap(\.workspace))
            where WorkspaceHistoryHeuristics.isEligibleRecentWorkspace(workspace) {
            upsert(workspace: workspace, seenAt: snapshot.generatedAt)
        }

        pruneServiceHistory(referenceDate: snapshot.generatedAt)
        saveIfNeeded()
    }

    func record(action: ServiceAction, on service: ManagedService, outcome: String) {
        let now = Date()
        pruneServiceHistory(referenceDate: now)

        guard let sanitizedActionServiceID = PersistedTextSanitizer.identifier(service.id),
              let sanitizedService = sanitized(service: service) else {
            Log.general.warning("Skipping action history persistence for invalid service identifier.")
            return
        }
        let actionRecord = ServiceActionRecord(
            serviceID: sanitizedActionServiceID,
            serviceName: PersistedTextSanitizer.text(service.name) ?? service.name,
            actionRawValue: action.rawValue,
            outcome: PersistedTextSanitizer.text(outcome) ?? outcome,
            timestamp: now
        )
        modelContext.insert(actionRecord)

        let serviceRecord = fetchServiceRecord(id: sanitizedService.id) ?? {
            let record = ServiceHistoryRecord(
                id: sanitizedService.id,
                name: sanitizedService.name,
                kindRawValue: sanitizedService.kind.rawValue,
                sourceRawValue: sanitizedService.source.title,
                workspaceID: sanitizedService.workspace?.id,
                workspaceName: sanitizedService.workspace?.name,
                workspacePath: sanitizedService.workspace?.rootPath,
                statusRawValue: sanitizedService.status.rawValue,
                lastSeenAt: now
            )
            modelContext.insert(record)
            return record
        }()

        serviceRecord.lastActionRawValue = action.rawValue
        serviceRecord.lastActionAt = now
        serviceRecord.lastSeenAt = now
        serviceRecord.name = sanitizedService.name
        serviceRecord.kindRawValue = sanitizedService.kind.rawValue
        serviceRecord.sourceRawValue = sanitizedService.source.title
        serviceRecord.workspaceID = sanitizedService.workspace?.id
        serviceRecord.workspaceName = sanitizedService.workspace?.name
        serviceRecord.workspacePath = sanitizedService.workspace?.rootPath
        serviceRecord.statusRawValue = sanitizedService.status.rawValue

        if let workspace = sanitizedService.workspace,
           WorkspaceHistoryHeuristics.isEligibleRecentWorkspace(workspace) {
            upsert(workspace: workspace, seenAt: now)
        }

        pruneServiceHistory(referenceDate: now)
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

        pruneActionHistory()

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
        guard let sanitizedWindowID = PersistedTextSanitizer.identifier(id),
              let record = fetchWindowStateRecord(id: sanitizedWindowID) else { return nil }
        return PersistedWindowState(
            selectedWorkspaceID: PersistedTextSanitizer.identifier(record.selectedWorkspaceID),
            selectedServiceID: PersistedTextSanitizer.identifier(record.selectedServiceID),
            searchText: PersistedTextSanitizer.text(record.searchText) ?? "",
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
        guard let sanitizedWindowID = PersistedTextSanitizer.identifier(id) else {
            Log.general.warning("Skipping window state persistence for invalid window identifier.")
            return
        }
        let sanitizedWorkspaceID = PersistedTextSanitizer.identifier(selectedWorkspaceID)
        let sanitizedServiceID = PersistedTextSanitizer.identifier(selectedServiceID)
        let sanitizedSearchText = PersistedTextSanitizer.text(searchText) ?? ""
        let record = fetchWindowStateRecord(id: sanitizedWindowID) ?? {
            let newRecord = WindowStateRecord(
                id: sanitizedWindowID,
                selectedWorkspaceID: sanitizedWorkspaceID,
                selectedServiceID: sanitizedServiceID,
                searchText: sanitizedSearchText,
                inspectorVisible: inspectorVisible,
                updatedAt: .now
            )
            modelContext.insert(newRecord)
            return newRecord
        }()

        record.selectedWorkspaceID = sanitizedWorkspaceID
        record.selectedServiceID = sanitizedServiceID
        record.searchText = sanitizedSearchText
        record.inspectorVisible = inspectorVisible
        record.updatedAt = .now
        saveIfNeeded()
    }

    private func upsert(service: ManagedService, seenAt: Date) {
        guard let sanitizedService = sanitized(service: service) else {
            Log.general.warning("Skipping service history persistence for invalid service identifier.")
            return
        }
        let record = fetchServiceRecord(id: sanitizedService.id) ?? {
            let newRecord = ServiceHistoryRecord(
                id: sanitizedService.id,
                name: sanitizedService.name,
                kindRawValue: sanitizedService.kind.rawValue,
                sourceRawValue: sanitizedService.source.title,
                workspaceID: sanitizedService.workspace?.id,
                workspaceName: sanitizedService.workspace?.name,
                workspacePath: sanitizedService.workspace?.rootPath,
                statusRawValue: sanitizedService.status.rawValue,
                lastSeenAt: seenAt
            )
            modelContext.insert(newRecord)
            return newRecord
        }()

        record.name = sanitizedService.name
        record.kindRawValue = sanitizedService.kind.rawValue
        record.sourceRawValue = sanitizedService.source.title
        record.workspaceID = sanitizedService.workspace?.id
        record.workspaceName = sanitizedService.workspace?.name
        record.workspacePath = sanitizedService.workspace?.rootPath
        record.statusRawValue = sanitizedService.status.rawValue
        record.lastSeenAt = seenAt
    }

    private func upsert(workspace: WorkspaceIdentity, seenAt: Date) {
        guard let sanitizedWorkspace = sanitized(workspace: workspace) else {
            Log.general.warning("Skipping workspace history persistence for invalid workspace identifier.")
            return
        }
        let record: WorkspaceHistoryRecord
        if let existingRecord = fetchWorkspaceRecord(id: sanitizedWorkspace.id) {
            record = existingRecord
            record.openCount += 1
        } else {
            record = WorkspaceHistoryRecord(
                id: sanitizedWorkspace.id,
                name: sanitizedWorkspace.name,
                rootPath: sanitizedWorkspace.rootPath,
                lastSeenAt: seenAt
            )
            modelContext.insert(record)
        }

        record.name = sanitizedWorkspace.name
        record.rootPath = sanitizedWorkspace.rootPath
        record.lastSeenAt = seenAt
    }

    private func sanitized(service: ManagedService) -> ManagedService? {
        guard let sanitizedID = PersistedTextSanitizer.identifier(service.id) else { return nil }
        return ManagedService(
            id: sanitizedID,
            name: PersistedTextSanitizer.text(service.name) ?? service.name,
            kind: service.kind,
            status: service.status,
            health: service.health,
            source: service.source,
            workspace: service.workspace.flatMap(sanitized(workspace:)),
            ports: service.ports,
            runtime: service.runtime,
            summary: service.summary,
            command: service.command,
            configPath: service.configPath,
            logPath: service.logPath,
            tags: service.tags,
            availableActions: service.availableActions,
            startedAt: service.startedAt,
            lastSeenAt: service.lastSeenAt
        )
    }

    private func sanitized(workspace: WorkspaceIdentity) -> WorkspaceIdentity? {
        guard let sanitizedID = PersistedTextSanitizer.identifier(workspace.id) else { return nil }
        guard let sanitizedRootPath = PersistedTextSanitizer.path(workspace.rootPath) else { return nil }
        return WorkspaceIdentity(
            id: sanitizedID,
            name: PersistedTextSanitizer.text(workspace.name) ?? workspace.name,
            rootPath: sanitizedRootPath
        )
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
        let cutoffDate = Date().addingTimeInterval(-Retention.maxWorkspaceAge)

        for record in records {
            if record.lastSeenAt < cutoffDate {
                modelContext.delete(record)
                continue
            }

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

        let refreshedRecords = (try? modelContext.fetch(descriptor)) ?? []
        for record in refreshedRecords.dropFirst(Retention.maxWorkspaceCount) {
            modelContext.delete(record)
        }

        saveIfNeeded()
    }

    private func pruneActionHistory() {
        let descriptor = FetchDescriptor<ServiceActionRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let records = (try? modelContext.fetch(descriptor)) ?? []
        guard !records.isEmpty else { return }

        let cutoffDate = Date().addingTimeInterval(-Retention.maxActionAge)

        for record in records {
            if record.timestamp < cutoffDate || ServiceAction(rawValue: record.actionRawValue) == nil {
                modelContext.delete(record)
            }
        }

        let refreshedRecords = (try? modelContext.fetch(descriptor)) ?? []
        for record in refreshedRecords.dropFirst(Retention.maxActionCount) {
            modelContext.delete(record)
        }

        saveIfNeeded()
    }

    private func pruneServiceHistory(referenceDate: Date) {
        let descriptor = FetchDescriptor<ServiceHistoryRecord>(
            sortBy: [SortDescriptor(\.lastSeenAt, order: .reverse)]
        )
        let records = (try? modelContext.fetch(descriptor)) ?? []
        guard !records.isEmpty else { return }

        let cutoffDate = referenceDate.addingTimeInterval(-Retention.maxServiceAge)

        for record in records where record.lastSeenAt < cutoffDate {
            modelContext.delete(record)
        }

        let refreshedRecords = (try? modelContext.fetch(descriptor)) ?? []
        for record in refreshedRecords.dropFirst(Retention.maxServiceCount) {
            modelContext.delete(record)
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
