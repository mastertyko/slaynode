import AppIntents

struct ManagedServiceEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Service")
    static let defaultQuery = ManagedServiceEntityQuery()

    let id: String
    let title: String
    let subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: title), subtitle: LocalizedStringResource(stringLiteral: subtitle))
    }

    init(service: ManagedService) {
        self.id = service.id
        self.title = service.name
        self.subtitle = service.summary
    }
}

struct ManagedServiceEntityQuery: EntityQuery {
    func entities(for identifiers: [ManagedServiceEntity.ID]) async throws -> [ManagedServiceEntity] {
        let services = await MainActor.run {
            identifiers.compactMap { id in
                ServiceCommandBridge.shared.service(id: id).map(ManagedServiceEntity.init(service:))
            }
        }
        return services
    }

    func suggestedEntities() async throws -> [ManagedServiceEntity] {
        await MainActor.run {
            ServiceCommandBridge.shared.allServices().map(ManagedServiceEntity.init(service:))
        }
    }
}

struct StopServiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Service"
    static let description = IntentDescription("Stop a local service in SlayNode.")

    @Parameter(title: "Service")
    var service: ManagedServiceEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try await ServiceCommandBridge.shared.perform(.stop, on: service.id)
        return .result(dialog: IntentDialog(stringLiteral: result))
    }
}

struct RestartServiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Restart Service"
    static let description = IntentDescription("Restart a local service in SlayNode when the provider supports it.")

    @Parameter(title: "Service")
    var service: ManagedServiceEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try await ServiceCommandBridge.shared.perform(.restart, on: service.id)
        return .result(dialog: IntentDialog(stringLiteral: result))
    }
}

struct OpenWorkspaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Workspace"
    static let description = IntentDescription("Open the owning workspace for a service in Finder.")

    @Parameter(title: "Service")
    var service: ManagedServiceEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try await ServiceCommandBridge.shared.perform(.openWorkspace, on: service.id)
        return .result(dialog: IntentDialog(stringLiteral: result))
    }
}
