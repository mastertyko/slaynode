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
        if let selectedServiceID {
            return filteredServices.first(where: { $0.id == selectedServiceID })
                ?? scopedServices.first(where: { $0.id == selectedServiceID })
        }

        return filteredServices.first ?? scopedServices.first
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

                if center.settings.showRecentHistory && !center.recentWorkspaces.isEmpty {
                    Section("Recent Workspaces") {
                        ForEach(center.recentWorkspaces, id: \.id) { workspace in
                            ServiceWorkspaceRow(workspace: workspace)
                                .tag(Optional(workspace.id))
                        }
                    }
                }
            }

            Section(lockedWorkspaceID == nil ? "Workspaces" : "Focused Workspace") {
                ForEach(availableWorkspaces, id: \.id) { workspace in
                    ServiceWorkspaceRow(workspace: workspace)
                        .tag(Optional(workspace.id))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 230, ideal: 270)
    }

    private var serviceList: some View {
        List(selection: $selectedServiceID) {
            if filteredServices.isEmpty {
                ContentUnavailableView(
                    "No Services Found",
                    systemImage: "bolt.slash",
                    description: Text("Try a broader search or refresh local discovery.")
                )
            } else {
                Section(sectionHeaderText) {
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
                GlassEffectContainer(spacing: 18) {
                    ServiceHeroCard(
                        service: service,
                        namespace: glassNamespace,
                        refreshDate: center.lastRefreshAt
                    ) {
                        primaryActions(for: service)
                    }

                    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 16) {
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

                    if let command = service.command {
                        ServicePanel(title: "Command", systemImage: "terminal") {
                            Text(command)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
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

        return HStack(spacing: 10) {
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
            }
        }
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

    private var sectionHeaderText: String {
        if let selectedWorkspace {
            return "\(selectedWorkspace.name) • \(filteredServices.count) services"
        }

        return "All Services • \(filteredServices.count)"
    }

    private func syncSelection() {
        if lockedWorkspaceID != nil {
            selectedWorkspaceID = lockedWorkspaceID
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
            searchText = state.searchText
            inspectorVisible = state.inspectorVisible
        } else if lockedWorkspaceID == nil {
            selectedWorkspaceID = center.workspaces.first?.id
        } else {
            selectedWorkspaceID = lockedWorkspaceID
        }
    }

    private func persistWindowState() {
        center.persistWindowState(
            id: sceneStateID,
            selectedWorkspaceID: selectionWorkspaceID,
            selectedServiceID: selectedServiceID,
            searchText: searchText,
            inspectorVisible: inspectorVisible
        )
    }

    private func portLabel(for service: ManagedService) -> String {
        if service.ports.isEmpty {
            return "No live port"
        }
        return service.ports.map { ":\($0.value)" }.joined(separator: "  ")
    }
}

struct ServiceMenuBarView: View {
    @Bindable var center: ServiceCenterModel
    @Environment(\.openWindow) private var openWindow

    private var visibleServices: [ManagedService] {
        center.services.prefix(6).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SlayNode")
                        .font(.headline.weight(.semibold))

                    Text("\(center.activeServiceCount) active • \(center.unhealthyServiceCount) watch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await center.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }

            if visibleServices.isEmpty {
                ContentUnavailableView(
                    "No Active Services",
                    systemImage: "checkmark.circle",
                    description: Text("Local infra will appear here when discovery finds something running.")
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(visibleServices, id: \.id) { service in
                        HStack(spacing: 10) {
                            Image(systemName: service.kind.symbolName)
                                .foregroundStyle(serviceTint(for: service.kind))
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(service.name)
                                    .font(.subheadline.weight(.semibold))

                                Text(service.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if service.supports(.stop) {
                                Button("Stop") {
                                    Task { await center.perform(.stop, on: service) }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button("Open Dashboard") {
                    openWindow(id: AppWindowID.dashboard)
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .padding(18)
        .frame(width: 420)
    }
}

struct SlayNodeSettingsView: View {
    @Bindable var center: ServiceCenterModel
    @ObservedObject var updateController: UpdateController

    var body: some View {
        Form {
            Section("Scanning") {
                LabeledContent("Refresh cadence") {
                    Text("\(Int(center.settings.refreshInterval)) seconds")
                        .monospacedDigit()
                }

                Slider(value: $center.settings.refreshInterval, in: 3...60, step: 1)

                Text("A lower cadence feels more live, while a higher cadence keeps the app lighter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Experience") {
                Toggle("Show recent history in the app and inspector", isOn: $center.settings.showRecentHistory)
                Toggle("Show richer menu bar summary surface", isOn: $center.settings.showMenuBarSection)
            }

            Section("Updates") {
                if updateController.canCheckForUpdates {
                    Button("Check for Updates") {
                        updateController.checkForUpdates()
                    }
                } else {
                    Text("Update checks are unavailable in this local build configuration.")
                        .foregroundStyle(.secondary)
                }

                Text("SlayNode now targets the latest macOS stack and is tuned for Tahoe-native windowing, search and glass effects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .frame(minWidth: 560, minHeight: 420)
    }
}

struct SlayNodeAboutView: View {
    var body: some View {
        ZStack {
            ServiceAtmosphereView(activeCount: 4, unhealthyCount: 1)
                .ignoresSafeArea()

            ScrollView {
                GlassEffectContainer(spacing: 18) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .center, spacing: 18) {
                            aboutMark
                            .frame(width: 82, height: 82)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .glassEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                            VStack(alignment: .leading, spacing: 6) {
                                Text("SlayNode")
                                    .font(.system(size: 34, weight: .bold, design: .rounded))

                                Text("A native control room for local services on modern macOS.")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)

                                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        ServicePanel(title: "What Changed", systemImage: "sparkles") {
                            Text("The new SlayNode experience is built around Tahoe-native windowing, Liquid Glass surfaces, local service orchestration, and faster control over Docker, Homebrew Services and live development runtimes.")
                        }

                        ServicePanel(title: "Links", systemImage: "link") {
                            VStack(alignment: .leading, spacing: 10) {
                                Link("GitHub Repository", destination: URL(string: "https://github.com/mastertyko/slaynode")!)
                                Link("Issue Tracker", destination: URL(string: "https://github.com/mastertyko/slaynode/issues")!)
                            }
                        }
                    }
                    .padding(28)
                }
                .padding(24)
            }
        }
        .frame(minWidth: 640, minHeight: 460)
    }

    @ViewBuilder
    private var aboutMark: some View {
        if let icon = slayNodeAppIcon() {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
        } else {
            Image(systemName: "shippingbox.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.accentColor)
        }
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
            } else {
                Button(action: perform) {
                    HStack(spacing: 8) {
                        Image(systemName: action.systemImage)
                        Text(action.title)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
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
                    HStack(spacing: 10) {
                        Text(service.name)
                            .font(.system(size: 30, weight: .bold, design: .rounded))

                        Text(service.status.title)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundStyle(.primary)
                            .glassEffect(in: Capsule())
                    }

                    Text(service.summary)
                        .font(.body)
                        .foregroundStyle(.secondary)

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

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(tint.opacity(0.18))
                .frame(width: 42, height: 42)
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

private struct ServiceWorkspaceRow: View {
    let workspace: WorkspaceIdentity

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                Text(workspace.rootPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: "folder")
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
                    Text(service.status.title)
                        .font(.caption2.weight(.bold))
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
                                    Text(workspace.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text(workspace.rootPath)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
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
