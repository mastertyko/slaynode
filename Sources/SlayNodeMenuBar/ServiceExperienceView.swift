import AppKit
import Observation
import SwiftUI

struct ServiceDashboardWindowView: View {
    @Bindable var center: ServiceCenterModel
    @ObservedObject var updateController: UpdateController

    let lockedWorkspaceID: String?
    let sceneStateID: String

    @Environment(\.openWindow) private var openWindow

    @State private var selectedWorkspaceID: String?
    @State private var selectedServiceID: String?
    @State private var searchText = ""
    @State private var inspectorVisible = true
    @Namespace private var glassNamespace

    private var selectionWorkspaceID: String? {
        lockedWorkspaceID ?? selectedWorkspaceID
    }

    private var selectedWorkspace: WorkspaceIdentity? {
        guard let selectionWorkspaceID else { return nil }
        return center.workspaces.first(where: { $0.id == selectionWorkspaceID })
    }

    private var scopedServices: [ManagedService] {
        center.services.filter { service in
            guard let lockedWorkspaceID else { return true }
            return service.workspace?.id == lockedWorkspaceID
        }
    }

    private var filteredServices: [ManagedService] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return scopedServices.filter { service in
            let workspaceMatches = selectionWorkspaceID == nil || service.workspace?.id == selectionWorkspaceID
            guard workspaceMatches else { return false }
            guard !query.isEmpty else { return true }
            return service.searchIndex.contains(query)
        }
    }

    private var selectedService: ManagedService? {
        guard !filteredServices.isEmpty else { return nil }

        if let selectedServiceID {
            return filteredServices.first(where: { $0.id == selectedServiceID })
                ?? filteredServices.first
        }

        return filteredServices.first
    }

    private var dependenciesForSelection: [ServiceDependency] {
        guard let selectedService else { return [] }
        return center.dependencies.filter {
            $0.sourceID == selectedService.id || $0.targetID == selectedService.id
        }
    }

    var body: some View {
        ZStack {
            ServiceAtmosphereView(
                activeCount: center.activeServiceCount,
                unhealthyCount: center.unhealthyServiceCount
            )
            .ignoresSafeArea()

            NavigationSplitView {
                workspaceSidebar
            } content: {
                serviceList
            } detail: {
                serviceDetail
            }
            .navigationSplitViewStyle(.balanced)
            .searchable(text: $searchText, prompt: "Search services, ports, runtimes or workspaces")
            .searchToolbarBehavior(.automatic)
            .inspector(isPresented: $inspectorVisible) {
                ServiceInspectorPanel(
                    center: center,
                    selectedService: selectedService,
                    dependencies: dependenciesForSelection
                )
                .frame(minWidth: 260, idealWidth: 300)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lockedWorkspaceTitle ?? "Services")
                            .font(.headline.weight(.semibold))

                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await center.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Refresh service discovery")
                }

                ToolbarSpacer(.fixed, placement: .primaryAction)

                ToolbarItem(placement: .primaryAction) {
                    if let selectedService, selectedService.supports(.openWorkspace) {
                        Button {
                            Task { await center.perform(.openWorkspace, on: selectedService) }
                        } label: {
                            Label("Open Workspace", systemImage: "folder")
                        }
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    if let selectedWorkspace, lockedWorkspaceID == nil {
                        Button {
                            openWindow(value: selectedWorkspace.id)
                        } label: {
                            Label("Open Workspace Window", systemImage: "macwindow.on.rectangle")
                        }
                        .help("Open a dedicated window for \(selectedWorkspace.name)")
                    }
                }

                ToolbarSpacer(.flexible, placement: .primaryAction)

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        inspectorVisible.toggle()
                    } label: {
                        Label(inspectorVisible ? "Hide Inspector" : "Show Inspector", systemImage: inspectorVisible ? "sidebar.right" : "sidebar.right")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openWindow(id: AppWindowID.about)
                    } label: {
                        Label("About", systemImage: "app.badge")
                    }
                }
            }
            .task {
                restoreWindowState()
                center.start()
                syncSelection()
            }
            .onAppear {
                if !searchText.isEmpty {
                    searchText = ""
                }
            }
            .onChange(of: center.services.map(\.id)) {
                syncSelection()
            }
            .onChange(of: selectionWorkspaceID) {
                syncSelection()
                persistWindowState()
            }
            .onChange(of: selectedServiceID) {
                persistWindowState()
            }
            .onChange(of: searchText) {
                syncSelection()
                persistWindowState()
            }
            .onChange(of: inspectorVisible) {
                persistWindowState()
            }
        }
        .frame(minWidth: 1180, minHeight: 760)
        .background(.clear)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let lastError = center.lastError {
                ServiceFeedbackBanner(message: lastError) {
                    center.clearLastError()
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
            }
        }
        .userActivity("se.slaynode.window.\(sceneStateID)") { activity in
            activity.title = lockedWorkspaceTitle ?? "SlayNode Services"
            activity.userInfo = [
                "workspaceID": selectionWorkspaceID ?? "",
                "serviceID": selectedService?.id ?? ""
            ]
            activity.isEligibleForSearch = true
        }
    }

    private var workspaceSidebar: some View {
        List(selection: $selectedWorkspaceID) {
            if lockedWorkspaceID == nil {
                Section("Scope") {
                    Label("All Services", systemImage: "square.stack.3d.up")
                        .tag(Optional<String>.none)
                }

                Section("Workspaces") {
                    ForEach(availableWorkspaces, id: \.id) { workspace in
                        ServiceWorkspaceRow(
                            workspace: workspace,
                            title: workspaceDisplayName(workspace)
                        )
                            .tag(Optional(workspace.id))
                    }
                }

                if center.settings.showRecentHistory && !recentSidebarWorkspaces.isEmpty {
                    Section("Recent Workspaces") {
                        ForEach(recentSidebarWorkspaces, id: \.id) { workspace in
                            ServiceWorkspaceRow(
                                workspace: workspace,
                                title: workspaceDisplayName(workspace)
                            )
                                .tag(Optional(workspace.id))
                        }
                    }
                }
            }

            if lockedWorkspaceID != nil {
                Section("Focused Workspace") {
                    ForEach(availableWorkspaces, id: \.id) { workspace in
                        ServiceWorkspaceRow(
                            workspace: workspace,
                            title: workspaceDisplayName(workspace)
                        )
                            .tag(Optional(workspace.id))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 230, ideal: 270)
    }

    private var serviceList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ServiceColumnHeader(
                title: sectionHeaderText,
                subtitle: listSubtitleText,
                systemImage: selectedWorkspace == nil ? "square.stack.3d.up" : "folder"
            )
            .padding(.horizontal, 18)
            .padding(.top, 16)

            List(selection: $selectedServiceID) {
                if filteredServices.isEmpty {
                    ContentUnavailableView(
                        "No Services Found",
                        systemImage: "bolt.slash",
                        description: Text("Try a broader search or refresh local discovery.")
                    )
                } else {
                    ForEach(filteredServices, id: \.id) { service in
                        ServiceListRow(service: service)
                            .tag(Optional(service.id))
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 320, ideal: 420)
    }

    @ViewBuilder
    private var serviceDetail: some View {
        if let service = selectedService {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ServiceHeroCard(
                        service: service,
                        namespace: glassNamespace,
                        refreshDate: center.lastRefreshAt
                    ) {
                        primaryActions(for: service)
                    }

                    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 20) {
                        ServiceMetricCard(
                            title: "Ports",
                            value: portLabel(for: service),
                            subtitle: service.kind.title,
                            systemImage: "dot.radiowaves.left.and.right",
                            tint: serviceTint(for: service.kind)
                        )

                        ServiceMetricCard(
                            title: "Source",
                            value: service.source.title,
                            subtitle: service.source.primaryIdentifier,
                            systemImage: "shippingbox.fill",
                            tint: .blue
                        )

                        ServiceMetricCard(
                            title: "Workspace",
                            value: service.workspace?.name ?? "Detached",
                            subtitle: service.workspace?.rootPath ?? "No workspace path available",
                            systemImage: "folder.fill",
                            tint: .orange
                        )

                        ServiceMetricCard(
                            title: "Runtime",
                            value: service.runtime ?? "System",
                            subtitle: service.health.title,
                            systemImage: "cpu.fill",
                            tint: healthTint(for: service.health)
                        )
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 20) {
                            summaryPanel(for: service)
                            if let command = service.command {
                                commandPanel(command)
                            }
                        }

                        VStack(alignment: .leading, spacing: 20) {
                            summaryPanel(for: service)
                            if let command = service.command {
                                commandPanel(command)
                            }
                        }
                    }

                    if !dependenciesForSelection.isEmpty {
                        ServicePanel(title: "Dependencies", systemImage: "point.3.connected.trianglepath.dotted") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(dependenciesForSelection, id: \.id) { dependency in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(dependency.label)
                                            .font(.subheadline.weight(.semibold))
                                        Text(dependency.targetID == service.id ? "Used by another service in this workspace." : "Supports the selected service.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 920, alignment: .leading)
            }
            .userActivity("se.slaynode.service") { activity in
                activity.title = service.name
                activity.userInfo = ["serviceID": service.id]
                activity.isEligibleForSearch = true
            }
        } else {
            ContentUnavailableView(
                "Choose a Service",
                systemImage: "square.stack.3d.up.slash",
                description: Text("Select a service to inspect ports, actions and workspace details.")
            )
        }
    }

    private func primaryActions(for service: ManagedService) -> some View {
        let primaryActions = service.availableActions.filter { [.stop, .forceStop, .restart].contains($0) }

        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 132), spacing: 10, alignment: .leading)],
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(primaryActions, id: \.self) { action in
                ServiceActionButton(action: action) {
                    Task { await center.perform(action, on: service) }
                }
            }

            if service.supports(.openLogs) {
                Button {
                    Task { await center.perform(.openLogs, on: service) }
                } label: {
                    Label("Logs", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusText: String {
        let updated = center.lastRefreshAt?.formatted(date: .omitted, time: .shortened) ?? "not refreshed yet"
        return "\(center.activeServiceCount) active • \(center.unhealthyServiceCount) watch items • Updated \(updated)"
    }

    private var lockedWorkspaceTitle: String? {
        guard let lockedWorkspaceID else { return nil }
        return center.workspaces.first(where: { $0.id == lockedWorkspaceID })?.name
    }

    private var availableWorkspaces: [WorkspaceIdentity] {
        let discovered = Array(Set(center.services.compactMap(\.workspace)))
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        if let lockedWorkspaceID, let workspace = discovered.first(where: { $0.id == lockedWorkspaceID }) {
            return [workspace]
        }

        return discovered
    }

    private var recentSidebarWorkspaces: [WorkspaceIdentity] {
        center.recentWorkspaces.filter { workspace in
            !availableWorkspaces.contains(workspace)
        }
    }

    private var sectionHeaderText: String {
        if let selectedWorkspace {
            return "\(selectedWorkspace.name) • \(filteredServices.count) services"
        }

        return "All Services • \(filteredServices.count)"
    }

    private var listSubtitleText: String {
        if let selectedWorkspace {
            return "Focused on \(selectedWorkspace.name) with live local services and recent status."
        }

        return "A unified view across processes, containers and managed local runtimes."
    }

    private func syncSelection() {
        if lockedWorkspaceID != nil {
            selectedWorkspaceID = lockedWorkspaceID
        } else if let currentWorkspaceID = selectedWorkspaceID,
                  !selectableWorkspaceIDs.contains(currentWorkspaceID) {
            selectedWorkspaceID = nil
        }

        guard !filteredServices.isEmpty else {
            selectedServiceID = nil
            return
        }

        if let selectedServiceID, filteredServices.contains(where: { $0.id == selectedServiceID }) {
            return
        }

        selectedServiceID = filteredServices.first?.id
    }

    private func restoreWindowState() {
        if let state = center.restoreWindowState(id: sceneStateID) {
            if lockedWorkspaceID == nil {
                selectedWorkspaceID = state.selectedWorkspaceID
            }
            selectedServiceID = state.selectedServiceID
            searchText = ""
            inspectorVisible = state.inspectorVisible
        } else if lockedWorkspaceID == nil {
            selectedWorkspaceID = nil
        } else {
            selectedWorkspaceID = lockedWorkspaceID
        }
    }

    private func persistWindowState() {
        center.persistWindowState(
            id: sceneStateID,
            selectedWorkspaceID: selectionWorkspaceID,
            selectedServiceID: selectedServiceID,
            searchText: "",
            inspectorVisible: inspectorVisible
        )
    }

    private func portLabel(for service: ManagedService) -> String {
        if service.ports.isEmpty {
            return "No live port"
        }
        return service.ports.map { ":\($0.value)" }.joined(separator: "  ")
    }

    private var selectableWorkspaceIDs: Set<String> {
        Set((recentSidebarWorkspaces + availableWorkspaces).map(\.id))
    }

    private func workspaceDisplayName(_ workspace: WorkspaceIdentity) -> String {
        contextualWorkspaceTitle(for: workspace, within: recentSidebarWorkspaces + availableWorkspaces)
    }

    @ViewBuilder
    private func summaryPanel(for service: ManagedService) -> some View {
        ServicePanel(title: "Summary", systemImage: "text.alignleft") {
            Text(service.summary)
                .font(.body)
                .foregroundStyle(.primary)

            if !service.tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(service.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .glassEffect(in: Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func commandPanel(_ command: String) -> some View {
        ServicePanel(title: "Command", systemImage: "terminal") {
            Text(command)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ServiceMenuBarView: View {
    @Bindable var center: ServiceCenterModel
    @Environment(\.openWindow) private var openWindow

    private var menuBarPresentation: MenuBarStatusPresentation {
        center.menuBarPresentation
    }

    private var visibleServices: [ManagedService] {
        center.services
            .sorted(by: menuBarPriority)
            .prefix(6)
            .map { $0 }
    }

    private var updatedLabel: String {
        guard let lastRefreshAt = center.lastRefreshAt else {
            return "Not refreshed yet"
        }

        return "Updated \(lastRefreshAt.formatted(date: .omitted, time: .shortened))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ServiceMenuBarHeaderCard(
                presentation: menuBarPresentation,
                unhealthyCount: center.unhealthyServiceCount,
                updatedLabel: updatedLabel
            ) {
                Task { await center.refresh() }
            }

            if let lastError = center.lastError {
                ServiceFeedbackBanner(message: lastError, compact: true) {
                    center.clearLastError()
                }
            }

            if center.settings.showMenuBarSection {
                ServiceMenuBarSummaryCard(
                    activeCount: center.activeServiceCount,
                    unhealthyCount: center.unhealthyServiceCount,
                    updatedLabel: updatedLabel,
                    recentAction: center.settings.showRecentHistory ? center.recentActions.first : nil
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Top Services")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(visibleServices.count) shown")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                if visibleServices.isEmpty {
                    ServiceMenuBarEmptyState {
                        Task { await center.refresh() }
                    } openDashboard: {
                        openWindow(id: AppWindowID.dashboard)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(visibleServices, id: \.id) { service in
                                ServiceMenuBarRow(
                                    service: service,
                                    workspaceTitle: service.workspace.map {
                                        contextualWorkspaceTitle(
                                            for: $0,
                                            within: center.workspaces + center.recentWorkspaces
                                        )
                                    },
                                    isExpanded: center.settings.showMenuBarSection,
                                    primaryAction: service.supports(.stop) ? .stop : nil,
                                    quickActions: menuBarQuickActions(for: service)
                                ) { action in
                                    Task { await center.perform(action, on: service) }
                                }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                    .frame(maxHeight: center.settings.showMenuBarSection ? 292 : 236)
                }
            }

            Divider()

            HStack(spacing: 10) {
                Button("Open Dashboard") {
                    openWindow(id: AppWindowID.dashboard)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)

                Spacer()

                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
        .padding(18)
        .frame(width: center.settings.showMenuBarSection ? 448 : 380)
    }

    private func menuBarQuickActions(for service: ManagedService) -> [ServiceAction] {
        let priority: [ServiceAction] = [
            .restart,
            .openWorkspace,
            .openLogs,
            .revealConfig
        ]

        return priority.filter(service.supports).prefix(2).map { $0 }
    }
}

private struct ServiceActionButton: View {
    let action: ServiceAction
    let perform: () -> Void

    var body: some View {
        Group {
            if action == .stop {
                Button(action: perform) {
                    HStack(spacing: 8) {
                        Image(systemName: action.systemImage)
                        Text(action.title)
                    }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            } else {
                Button(action: perform) {
                    HStack(spacing: 8) {
                        Image(systemName: action.systemImage)
                        Text(action.title)
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
        .controlSize(.small)
        .tint(action == .forceStop ? .red : nil)
    }
}

private struct ServiceHeroCard<Actions: View>: View {
    let service: ManagedService
    let namespace: Namespace.ID
    let refreshDate: Date?
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: service.kind.symbolName)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(serviceTint(for: service.kind))
                    .frame(width: 64, height: 64)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .glassEffectID("service-icon-\(service.id)", in: namespace)

                VStack(alignment: .leading, spacing: 6) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            serviceTitle
                            statusBadge
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            serviceTitle
                            statusBadge
                        }
                    }

                    Text(service.summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    Text(refreshLabel)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            actions
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .glassEffectID("service-card-\(service.id)", in: namespace)
    }

    private var serviceTitle: some View {
        Text(service.name)
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .lineLimit(2)
    }

    private var statusBadge: some View {
        Text(service.status.title)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(.primary)
            .glassEffect(in: Capsule())
    }

    private var refreshLabel: String {
        if let refreshDate {
            return "Updated \(refreshDate.formatted(date: .omitted, time: .shortened))"
        }

        return "Updated recently"
    }
}

private struct ServiceMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(3)
                .minimumScaleFactor(0.82)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 136, alignment: .leading)
        .glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(tint.opacity(0.18))
                .frame(width: 34, height: 34)
                .padding(14)
        }
    }
}

private struct ServicePanel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct ServiceFeedbackBanner: View {
    let message: String
    var compact: Bool = false
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .padding(.top, 2)

            Text(message)
                .font(compact ? .caption : .subheadline)
                .foregroundStyle(.primary)
                .lineLimit(compact ? 3 : 2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 8)

            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(compact ? 12 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: RoundedRectangle(cornerRadius: compact ? 20 : 22, style: .continuous))
    }
}

private struct ServiceMenuBarSummaryCard: View {
    let activeCount: Int
    let unhealthyCount: Int
    let updatedLabel: String
    let recentAction: ServiceActionSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Now")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(updatedLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                ServiceMenuBarMetricPill(
                    title: "Active",
                    value: "\(activeCount)",
                    tint: .green
                )
                ServiceMenuBarMetricPill(
                    title: "Watch",
                    value: "\(unhealthyCount)",
                    tint: unhealthyCount > 0 ? .orange : .secondary
                )
            }

            if let recentAction {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recent action")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)

                    Text("\(recentAction.action.title) • \(recentAction.serviceName)")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct ServiceColumnHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 40, height: 40)
                .glassEffect(in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct ServiceMenuBarRow: View {
    let service: ManagedService
    let workspaceTitle: String?
    let isExpanded: Bool
    let primaryAction: ServiceAction?
    let quickActions: [ServiceAction]
    let perform: (ServiceAction) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(serviceTint(for: service.kind).opacity(0.16))

                Image(systemName: service.kind.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(serviceTint(for: service.kind))
            }
            .frame(width: isExpanded ? 30 : 24, height: isExpanded ? 30 : 24)

            VStack(alignment: .leading, spacing: isExpanded ? 4 : 2) {
                HStack(spacing: 8) {
                    Text(service.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text(service.status.title)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(healthTint(for: service.health).opacity(0.14), in: Capsule())
                        .foregroundStyle(healthTint(for: service.health))
                        .lineLimit(1)
                }

                if isExpanded {
                    Text(service.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        ServiceMenuBarMetaBadge(
                            text: service.source.title,
                            systemImage: sourceSymbol(for: service.source)
                        )

                        if let workspaceTitle {
                            ServiceMenuBarMetaBadge(
                                text: workspaceTitle,
                                systemImage: "folder.fill"
                            )
                        }

                        if !service.ports.isEmpty {
                            ServiceMenuBarMetaBadge(
                                text: service.ports.map { ":\($0.value)" }.joined(separator: "  "),
                                systemImage: "dot.radiowaves.left.and.right",
                                monospaced: true
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                if isExpanded && !quickActions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(quickActions, id: \.self) { action in
                            Button {
                                perform(action)
                            } label: {
                                Image(systemName: action.systemImage)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                            .help(action.title)
                            .accessibilityLabel(action.title)
                        }
                    }
                }

                if let primaryAction {
                    Button(primaryAction.title) {
                        perform(primaryAction)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(primaryAction == .stop ? .orange : nil)
                }
            }
        }
        .padding(isExpanded ? 12 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ServiceMenuBarHeaderCard: View {
    let presentation: MenuBarStatusPresentation
    let unhealthyCount: Int
    let updatedLabel: String
    let refresh: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))

                Image(systemName: presentation.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("SlayNode")
                        .font(.headline.weight(.semibold))

                    if let countText = presentation.countText {
                        Text(countText)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }

                Text(updatedLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(presentation.statusText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(presentation.needsAttention ? .orange : .secondary)
            }

            Spacer(minLength: 10)

            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct ServiceMenuBarEmptyState: View {
    let refresh: () -> Void
    let openDashboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ContentUnavailableView(
                "No Services Right Now",
                systemImage: "checkmark.circle",
                description: Text("When discovery finds local infrastructure, the most relevant services will show up here.")
            )

            HStack(spacing: 10) {
                Button("Refresh", action: refresh)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)

                Button("Open Dashboard", action: openDashboard)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .glassEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct ServiceMenuBarMetricPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ServiceMenuBarMetaBadge: View {
    let text: String
    let systemImage: String
    var monospaced: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2)

            Text(text)
                .font(monospaced ? .caption2.monospacedDigit() : .caption2)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(.white.opacity(0.06), in: Capsule())
    }
}

private struct ServiceWorkspaceRow: View {
    let workspace: WorkspaceIdentity
    let title: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.08))

                Image(systemName: "folder.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.cyan)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(workspace.rootPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct ServiceListRow: View {
    let service: ManagedService

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(serviceTint(for: service.kind).opacity(0.16))
                Image(systemName: service.kind.symbolName)
                    .foregroundStyle(serviceTint(for: service.kind))
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(service.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(service.status.title)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(healthTint(for: service.health).opacity(0.14), in: Capsule())
                        .foregroundStyle(healthTint(for: service.health))
                }

                Text(service.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if !service.ports.isEmpty {
                    Text(service.ports.map { ":\($0.value)" }.joined(separator: "  "))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

private struct ServiceInspectorPanel: View {
    @Bindable var center: ServiceCenterModel
    let selectedService: ManagedService?
    let dependencies: [ServiceDependency]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ServicePanel(title: "Now", systemImage: "waveform.path.ecg") {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Active") {
                            Text("\(center.activeServiceCount)")
                                .monospacedDigit()
                        }
                        LabeledContent("Needs attention") {
                            Text("\(center.unhealthyServiceCount)")
                                .monospacedDigit()
                        }
                    }
                }

                if let selectedService {
                    ServicePanel(title: "Selection", systemImage: "scope") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(selectedService.name)
                                .font(.headline)
                            Text(selectedService.source.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if !dependencies.isEmpty {
                                Text("\(dependencies.count) related services")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if center.settings.showRecentHistory && !center.recentActions.isEmpty {
                    ServicePanel(title: "Recent Actions", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(center.recentActions.prefix(5), id: \.id) { action in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(action.action.title) • \(action.serviceName)")
                                        .font(.subheadline.weight(.semibold))
                                    Text(action.timestamp.formatted(date: .omitted, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if center.settings.showRecentHistory && !center.recentWorkspaces.isEmpty {
                    ServicePanel(title: "Recent Workspaces", systemImage: "folder.badge.clock") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(center.recentWorkspaces.prefix(5), id: \.id) { workspace in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(contextualWorkspaceTitle(for: workspace, within: center.workspaces + center.recentWorkspaces))
                                        .font(.subheadline.weight(.semibold))
                                    Text(workspace.rootPath)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
    }
}

private struct ServiceAtmosphereView: View {
    let activeCount: Int
    let unhealthyCount: Int

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.11, blue: 0.16),
                    Color(red: 0.06, green: 0.08, blue: 0.12),
                    Color(red: 0.03, green: 0.05, blue: 0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.cyan.opacity(activeCount > 0 ? 0.18 : 0.10))
                .frame(width: 320, height: 320)
                .blur(radius: 110)
                .offset(x: -280, y: -180)
                .backgroundExtensionEffect()

            Circle()
                .fill(Color.orange.opacity(unhealthyCount > 0 ? 0.18 : 0.05))
                .frame(width: 260, height: 260)
                .blur(radius: 90)
                .offset(x: 320, y: -180)
                .backgroundExtensionEffect()

            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 420, height: 420)
                .blur(radius: 140)
                .offset(x: 260, y: 260)
        }
    }
}

private func contextualWorkspaceTitle(
    for workspace: WorkspaceIdentity,
    within candidates: [WorkspaceIdentity]
) -> String {
    let duplicateCount = candidates.filter { $0.name == workspace.name }.count

    guard duplicateCount > 1 else { return workspace.name }

    let parentName = URL(fileURLWithPath: workspace.rootPath)
        .deletingLastPathComponent()
        .lastPathComponent

    guard !parentName.isEmpty, parentName != workspace.name else {
        return workspace.name
    }

    return "\(workspace.name) • \(parentName)"
}

private func menuBarPriority(lhs: ManagedService, rhs: ManagedService) -> Bool {
    let lhsScore = menuBarPriorityScore(for: lhs)
    let rhsScore = menuBarPriorityScore(for: rhs)

    if lhsScore != rhsScore {
        return lhsScore > rhsScore
    }

    if lhs.lastSeenAt != rhs.lastSeenAt {
        return lhs.lastSeenAt > rhs.lastSeenAt
    }

    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
}

private func menuBarPriorityScore(for service: ManagedService) -> Int {
    let healthScore: Int
    switch service.health {
    case .critical: healthScore = 400
    case .watch: healthScore = 300
    case .healthy: healthScore = 200
    case .passive: healthScore = 100
    }

    let statusScore: Int
    switch service.status {
    case .degraded: statusScore = 40
    case .running: statusScore = 30
    case .stopped: statusScore = 20
    case .unavailable: statusScore = 10
    }

    return healthScore + statusScore
}

private func sourceSymbol(for source: ServiceSource) -> String {
    switch source {
    case .process:
        return "terminal"
    case .docker:
        return "shippingbox.fill"
    case .brewService:
        return "cup.and.saucer.fill"
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func serviceTint(for kind: ServiceKind) -> Color {
    switch kind {
    case .app: return .cyan
    case .api: return .blue
    case .database: return .mint
    case .cache: return .teal
    case .queue: return .orange
    case .proxy: return .yellow
    case .worker: return .purple
    case .container: return .pink
    case .runtime: return .indigo
    case .tool: return .gray
    case .unknown: return .secondary
    }
}

private func healthTint(for health: ServiceHealth) -> Color {
    switch health {
    case .healthy: return .green
    case .watch: return .orange
    case .critical: return .red
    case .passive: return .secondary
    }
}
