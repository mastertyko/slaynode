import AppKit
import SwiftUI

struct WindowDashboardView: View {
    @ObservedObject var viewModel: MenuViewModel
    @ObservedObject var preferences: PreferencesStore
    let updateController: UpdateController?

    let statusText: String
    let statusIcon: String
    let activeAuxiliary: AuxiliarySheet?
    let showAboutAction: () -> Void
    let openSettingsAction: () -> Void
    let dismissAuxiliaryAction: () -> Void
    let quitAction: () -> Void

    @State private var selectedProcessID: Int32?
    @State private var searchText = ""

    private var filteredProcesses: [NodeProcessItemViewModel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.processes }

        return viewModel.processes.filter { process in
            let haystack = [
                process.title,
                process.subtitle,
                process.categoryBadge ?? "",
                process.projectName ?? "",
                process.command,
                process.workingDirectory ?? ""
            ]
            .joined(separator: "\n")

            return haystack.localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredProcessIDs: [Int32] {
        filteredProcesses.map(\.id)
    }

    private var selectedProcess: NodeProcessItemViewModel? {
        if let selectedProcessID {
            return filteredProcesses.first(where: { $0.id == selectedProcessID })
                ?? viewModel.processes.first(where: { $0.id == selectedProcessID })
        }

        return filteredProcesses.first ?? viewModel.processes.first
    }

    private var accent: Color {
        if let activeAuxiliary {
            switch activeAuxiliary {
            case .settings:
                return .accentColor
            case .about:
                return .teal
            }
        }

        return colorForCategory(selectedProcess?.categoryBadge)
    }

    private var dashboardSelectionLabel: String? {
        if let activeAuxiliary {
            switch activeAuxiliary {
            case .settings:
                return "Settings"
            case .about:
                return "About"
            }
        }

        return selectedProcess?.categoryBadge
    }

    private var concretePortCount: Int {
        viewModel.processes.reduce(into: 0) { count, process in
            count += process.actualPorts.count
        }
    }

    private var likelyPortCount: Int {
        viewModel.processes.reduce(into: 0) { count, process in
            count += process.likelyPorts.count
        }
    }

    private var projectCount: Int {
        Set(viewModel.processes.compactMap(\.projectName)).count
    }

    private var roleCount: Int {
        Set(viewModel.processes.compactMap(\.categoryBadge)).count
    }

    var body: some View {
        ZStack {
            WindowBackdrop(accent: accent)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                WindowHeroBanner(
                    activeCount: viewModel.processes.count,
                    concretePortCount: concretePortCount,
                    likelyPortCount: likelyPortCount,
                    projectCount: projectCount,
                    roleCount: roleCount,
                    statusText: statusText,
                    statusIcon: statusIcon,
                    refreshInterval: Int(preferences.refreshInterval.rounded()),
                    accent: accent,
                    isLoading: viewModel.isLoading,
                    selectionLabel: dashboardSelectionLabel,
                    refreshAction: viewModel.refresh,
                    showAboutAction: showAboutAction,
                    openSettingsAction: openSettingsAction,
                    quitAction: quitAction
                )

                if let error = viewModel.lastError {
                    ErrorBanner(text: error)
                        .transition(.opacity)
                }

                HStack(alignment: .top, spacing: 18) {
                    if let activeAuxiliary, let updateController {
                        WindowWorkspaceSidebarPanel(
                            activeAuxiliary: activeAuxiliary,
                            activeCount: viewModel.processes.count,
                            refreshInterval: Int(preferences.refreshInterval.rounded()),
                            openRuntimeAction: dismissAuxiliaryAction,
                            openSettingsAction: openSettingsAction,
                            openAboutAction: showAboutAction
                        )
                        .frame(width: 332)
                        .frame(maxHeight: .infinity, alignment: .top)

                        WindowWorkspaceDetailPanel(
                            activeAuxiliary: activeAuxiliary,
                            preferences: preferences,
                            updateController: updateController,
                            openRuntimeAction: dismissAuxiliaryAction,
                            openSettingsAction: openSettingsAction,
                            openAboutAction: showAboutAction
                        )
                    } else {
                        WindowSidebarPanel(
                            processes: filteredProcesses,
                            isLoading: viewModel.isLoading,
                            totalCount: viewModel.processes.count,
                            searchText: $searchText,
                            selectedProcessID: $selectedProcessID
                        )
                        .frame(width: 332)
                        .frame(maxHeight: .infinity, alignment: .top)

                        WindowProcessDetailPanel(
                            process: selectedProcess,
                            hasAnyProcesses: !viewModel.processes.isEmpty,
                            isLoading: viewModel.isLoading,
                            searchText: searchText,
                            accent: accent,
                            refreshAction: viewModel.refresh,
                            stopAction: { pid in
                                viewModel.stopProcess(pid)
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(28)
        }
        .onAppear(perform: syncSelection)
        .onChange(of: filteredProcessIDs) { _ in
            syncSelection()
        }
        .onChange(of: searchText) { _ in
            syncSelection()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: filteredProcessIDs)
        .animation(.easeInOut(duration: 0.24), value: selectedProcessID)
    }

    private func syncSelection() {
        guard !filteredProcesses.isEmpty else {
            selectedProcessID = nil
            return
        }

        if let selectedProcessID,
           filteredProcesses.contains(where: { $0.id == selectedProcessID }) {
            return
        }

        selectedProcessID = filteredProcesses.first?.id
    }
}

private struct WindowWorkspaceSidebarPanel: View {
    let activeAuxiliary: AuxiliarySheet
    let activeCount: Int
    let refreshInterval: Int
    let openRuntimeAction: () -> Void
    let openSettingsAction: () -> Void
    let openAboutAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Workspace")
                    .font(.title3.weight(.semibold))

                Text("Move between live runtime control and app surfaces without leaving the main window.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                WindowWorkspaceNavRow(
                    title: "Runtime Control",
                    detail: activeCount == 1 ? "1 active service ready to inspect" : "\(activeCount) active services ready to inspect",
                    systemImage: "server.rack",
                    tint: .orange,
                    isSelected: false,
                    action: openRuntimeAction
                )

                WindowWorkspaceNavRow(
                    title: "Settings",
                    detail: "Adjust scan cadence and update behavior",
                    systemImage: "gearshape.2.fill",
                    tint: .accentColor,
                    isSelected: activeAuxiliary == .settings,
                    action: openSettingsAction
                )

                WindowWorkspaceNavRow(
                    title: "About",
                    detail: "Version info, links and product details",
                    systemImage: "app.badge",
                    tint: .teal,
                    isSelected: activeAuxiliary == .about,
                    action: openAboutAction
                )
            }

            WindowInfoCard(
                title: "Live context",
                systemImage: "dot.radiowaves.left.and.right",
                accent: .accentColor
            ) {
                WindowMetadataLine(label: "Active services", value: "\(activeCount)")
                WindowMetadataLine(label: "Auto-refresh", value: "\(max(refreshInterval, 1)) seconds")
                WindowMetadataLine(label: "Version", value: appVersion)
            }

            Spacer()
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.10))
                )
        )
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

private struct WindowWorkspaceNavRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(isSelected ? 0.22 : 0.12))
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: systemImage)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(tint)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.16) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isSelected ? tint.opacity(0.24) : Color.white.opacity(0.04))
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct WindowWorkspaceDetailPanel: View {
    let activeAuxiliary: AuxiliarySheet
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var updateController: UpdateController
    let openRuntimeAction: () -> Void
    let openSettingsAction: () -> Void
    let openAboutAction: () -> Void

    private var accent: Color {
        switch activeAuxiliary {
        case .settings:
            return .accentColor
        case .about:
            return .teal
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 12) {
                    Button(action: openRuntimeAction) {
                        Label("Back to Runtime", systemImage: "chevron.left")
                    }
                    .buttonStyle(WindowToolbarPrimaryButtonStyle(tint: .secondary))

                    Spacer()

                    HStack(spacing: 8) {
                        workspaceModeButton(
                            title: "Settings",
                            systemImage: "gearshape.2.fill",
                            isActive: activeAuxiliary == .settings,
                            action: openSettingsAction
                        )

                        workspaceModeButton(
                            title: "About",
                            systemImage: "app.badge",
                            isActive: activeAuxiliary == .about,
                            action: openAboutAction
                        )
                    }
                }

                switch activeAuxiliary {
                case .settings:
                    SettingsContentView(
                        preferences: preferences,
                        updateController: updateController,
                        openAboutAction: openAboutAction
                    )
                case .about:
                    AboutContentView()
                }
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.08), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        )
    }

    @ViewBuilder
    private func workspaceModeButton(
        title: String,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if isActive {
            Button(action: action) {
                Label(title, systemImage: systemImage)
            }
            .buttonStyle(WindowToolbarPrimaryButtonStyle(tint: accent))
            .controlSize(.large)
        } else {
            Button(action: action) {
                Label(title, systemImage: systemImage)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

private struct WindowHeroBanner: View {
    let activeCount: Int
    let concretePortCount: Int
    let likelyPortCount: Int
    let projectCount: Int
    let roleCount: Int
    let statusText: String
    let statusIcon: String
    let refreshInterval: Int
    let accent: Color
    let isLoading: Bool
    let selectionLabel: String?
    let refreshAction: () -> Void
    let showAboutAction: () -> Void
    let openSettingsAction: () -> Void
    let quitAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Local Runtime Control")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    Text("See what is actually running, why it was identified, and take action without hunting through terminals.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        WindowStatusPill(
                            text: statusText,
                            systemImage: statusIcon,
                            tint: accent
                        )

                        WindowStatusPill(
                            text: "Auto-refresh \(max(refreshInterval, 1))s",
                            systemImage: "timer",
                            tint: .secondary
                        )

                        if let selectionLabel {
                            WindowStatusPill(
                                text: selectionLabel,
                                systemImage: windowCategoryIcon(for: selectionLabel),
                                tint: accent
                            )
                        }
                    }
                }

                Spacer(minLength: 20)

                VStack(alignment: .trailing, spacing: 10) {
                    HStack(spacing: 10) {
                        Button(action: refreshAction) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(WindowToolbarPrimaryButtonStyle(tint: accent))

                        windowSettingsButton

                        Button(action: showAboutAction) {
                            Label("About", systemImage: "info.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        Button(role: .destructive, action: quitAction) {
                            Label("Quit", systemImage: "power")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Scanning for changes…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                WindowMetricCard(
                    title: "Active services",
                    value: "\(activeCount)",
                    detail: activeCount == 1 ? "1 running process" : "\(activeCount) running processes",
                    accent: accent,
                    systemImage: "server.rack"
                )

                WindowMetricCard(
                    title: "Reachable ports",
                    value: "\(concretePortCount)",
                    detail: likelyPortCount > 0 ? "\(likelyPortCount) guessed as well" : "Confirmed from live sockets",
                    accent: .orange,
                    systemImage: "dot.radiowaves.left.and.right"
                )

                WindowMetricCard(
                    title: "Projects",
                    value: "\(projectCount)",
                    detail: projectCount == 1 ? "1 workspace detected" : "\(projectCount) workspaces detected",
                    accent: .blue,
                    systemImage: "folder.badge.gearshape"
                )

                WindowMetricCard(
                    title: "Roles in play",
                    value: "\(roleCount)",
                    detail: selectionLabel ?? "No active selection",
                    accent: .teal,
                    systemImage: "square.stack.3d.up"
                )
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accent.opacity(0.18),
                                    Color.orange.opacity(0.10),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.14))
                )
        )
        .shadow(color: accent.opacity(0.18), radius: 26, y: 10)
    }

    @ViewBuilder
    private var windowSettingsButton: some View {
        Button(action: openSettingsAction) {
            Label("Settings", systemImage: "gearshape")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}

private struct WindowSidebarPanel: View {
    let processes: [NodeProcessItemViewModel]
    let isLoading: Bool
    let totalCount: Int
    @Binding var searchText: String
    @Binding var selectedProcessID: Int32?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Runtime map")
                    .font(.title3.weight(.semibold))

                Text("Choose a service to inspect what it is, how it was identified, and which actions are available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search processes, commands or folders", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            Text(summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Group {
                if isLoading && totalCount == 0 {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Scanning for local runtimes…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if processes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "rectangle.stack.badge.magnifyingglass")
                            .font(.system(size: 28, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)

                        Text("Nothing matches that filter")
                            .font(.headline)

                        Text("Try a project name, a port, or part of the command.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 12)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(processes) { process in
                                Button {
                                    selectedProcessID = process.id
                                } label: {
                                    WindowSidebarRow(
                                        process: process,
                                        isSelected: selectedProcessID == process.id
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.10))
                )
        )
    }

    private var summaryText: String {
        if processes.count == totalCount {
            return totalCount == 1 ? "1 active process" : "\(totalCount) active processes"
        }

        return "Showing \(processes.count) of \(totalCount)"
    }
}

private struct WindowSidebarRow: View {
    let process: NodeProcessItemViewModel
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(iconTint.opacity(isSelected ? 0.22 : 0.12))
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: windowCategoryIcon(for: process.categoryBadge))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(iconTint)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(process.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if process.isStopping {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? iconTint.opacity(0.16) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isSelected ? iconTint.opacity(0.24) : Color.white.opacity(0.04))
                )
        )
    }

    private var detailLine: String {
        var parts: [String] = []

        if let category = process.categoryBadge {
            parts.append(category)
        }

        if !process.subtitle.isEmpty {
            parts.append(process.subtitle)
        }

        let visiblePorts = process.actualPorts.prefix(2).map { ":\($0)" }
        if !visiblePorts.isEmpty {
            parts.append(visiblePorts.joined(separator: ", "))
        }

        return parts.joined(separator: " · ")
    }

    private var iconTint: Color {
        colorForCategory(process.categoryBadge)
    }
}

private struct WindowProcessDetailPanel: View {
    let process: NodeProcessItemViewModel?
    let hasAnyProcesses: Bool
    let isLoading: Bool
    let searchText: String
    let accent: Color
    let refreshAction: () -> Void
    let stopAction: (Int32) -> Void

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 250), spacing: 14, alignment: .top)]
    }

    var body: some View {
        Group {
            if isLoading && !hasAnyProcesses {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Building your local runtime map…")
                        .font(.headline)
                    Text("SlayNode is checking commands, ports and child processes.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasAnyProcesses {
                EmptyStateView(refreshAction: refreshAction)
            } else if let process {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        WindowProcessHeroCard(
                            process: process,
                            accent: accent,
                            stopAction: stopAction
                        )

                        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                            WindowInfoCard(
                                title: "At a glance",
                                systemImage: "waveform.path.ecg",
                                accent: accent
                            ) {
                                WindowMetadataLine(label: "PID", value: "\(process.pid)")
                                WindowMetadataLine(label: "Uptime", value: process.uptimeDescription)
                                WindowMetadataLine(label: "Started", value: process.startTimeDescription)
                                WindowMetadataLine(label: "Role", value: process.categoryBadge ?? process.descriptor.displayName)
                            }

                            WindowInfoCard(
                                title: "Why SlayNode flagged it",
                                systemImage: "sparkles",
                                accent: .orange
                            ) {
                                Text(roleNarrative(for: process))
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Divider()

                                WindowMetadataLine(label: "Matched as", value: process.descriptor.displayName)

                                if let runtime = process.descriptor.runtime {
                                    WindowMetadataLine(label: "Runtime", value: runtime)
                                }

                                if let details = process.descriptor.details {
                                    WindowMetadataLine(label: "Signal", value: details)
                                }
                            }

                            WindowInfoCard(
                                title: "Ports and reachability",
                                systemImage: "dot.radiowaves.left.and.right",
                                accent: .teal
                            ) {
                                if process.actualPorts.isEmpty && process.likelyPorts.isEmpty {
                                    Text("No ports detected for this process right now.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(process.actualPorts, id: \.self) { port in
                                        WindowPortRow(port: port, isLikely: false)
                                    }

                                    ForEach(process.likelyPorts, id: \.self) { port in
                                        WindowPortRow(port: port, isLikely: true)
                                    }
                                }
                            }

                            WindowInfoCard(
                                title: "Workspace",
                                systemImage: "folder",
                                accent: .blue
                            ) {
                                if let projectName = process.projectName {
                                    WindowMetadataLine(label: "Project", value: projectName)
                                }

                                if let workingDirectory = process.workingDirectory {
                                    WindowPathBlock(path: workingDirectory)
                                } else {
                                    Text("No working directory could be resolved.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        WindowInfoCard(
                            title: "Command",
                            systemImage: "terminal",
                            accent: .indigo
                        ) {
                            Text(process.command)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.primary.opacity(0.05))
                                )
                        }

                        if !process.infoChips.isEmpty {
                            WindowInfoCard(
                                title: "Extra signals",
                                systemImage: "bolt.horizontal.circle",
                                accent: .mint
                            ) {
                                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                                    ForEach(process.infoChips, id: \.self) { chip in
                                        HStack(spacing: 8) {
                                            if let systemImage = chip.systemImage {
                                                Image(systemName: systemImage)
                                                    .foregroundStyle(.secondary)
                                            }

                                            Text(chip.text)
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                                .lineLimit(2)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(Color.primary.opacity(0.05))
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(24)
                }
                .scrollIndicators(.hidden)
            } else {
                WindowNoSelectionView(searchText: searchText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.12))
                )
        )
    }
}

private struct WindowProcessHeroCard: View {
    let process: NodeProcessItemViewModel
    let accent: Color
    let stopAction: (Int32) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(accent.opacity(0.18))
                    .frame(width: 64, height: 64)
                    .overlay {
                        Image(systemName: windowCategoryIcon(for: process.categoryBadge))
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(accent)
                    }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(process.title)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .lineLimit(2)

                        if let category = process.categoryBadge {
                            WindowStatusPill(
                                text: category,
                                systemImage: windowCategoryIcon(for: category),
                                tint: accent
                            )
                        }
                    }

                    Text(roleNarrative(for: process))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        WindowStatusPill(text: "PID \(process.pid)", systemImage: "number", tint: .secondary)
                        WindowStatusPill(text: process.uptimeDescription, systemImage: "timer", tint: .secondary)

                        if let projectName = process.projectName {
                            WindowStatusPill(text: projectName, systemImage: "folder", tint: .secondary)
                        }
                    }
                }

                Spacer(minLength: 16)
            }

            HStack(spacing: 10) {
                if let primaryPort = process.actualPorts.first {
                    Button {
                        openLocalhost(port: primaryPort)
                    } label: {
                        Label("Open :\(primaryPort)", systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                }

                if let directory = process.workingDirectory {
                    Button {
                        openDirectory(directory)
                    } label: {
                        Label("Open Folder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    copyToPasteboard(process.command)
                } label: {
                    Label("Copy Command", systemImage: "document.on.document")
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)

                if process.isStopping {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Slaying…")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.secondary.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.08))
                            )
                    )
                } else {
                    Button(role: .destructive) {
                        stopAction(process.pid)
                    } label: {
                        Label("Slay", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.red)
                }
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.18), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(accent.opacity(0.22))
                )
        )
    }
}

private struct WindowInfoCard<Content: View>: View {
    let title: String
    let systemImage: String
    let accent: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(accent)

                Text(title)
                    .font(.headline)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.08))
                )
        )
    }
}

private struct WindowToolbarPrimaryButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tint.opacity(configuration.isPressed ? 0.16 : 0.24),
                                        tint.opacity(configuration.isPressed ? 0.04 : 0.10)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(tint.opacity(configuration.isPressed ? 0.18 : 0.26))
                    )
            )
            .shadow(
                color: tint.opacity(configuration.isPressed ? 0.08 : 0.16),
                radius: configuration.isPressed ? 6 : 14,
                y: configuration.isPressed ? 2 : 5
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct WindowMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let accent: Color
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(accent.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(accent.opacity(0.12))
                )
        )
    }
}

private struct WindowStatusPill: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .accessibilityHidden(true)

            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.12))
        )
        .foregroundStyle(tint)
    }
}

private struct WindowMetadataLine: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WindowPortRow: View {
    let port: Int
    let isLikely: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isLikely ? Color.orange : Color.teal)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(isLikely ? "Likely port :\(port)" : "Live port :\(port)")
                    .font(.subheadline.weight(.semibold))

                Text(isLikely ? "Inferred from tooling and defaults." : "Resolved from an active listening socket.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isLikely {
                Button("Open") {
                    openLocalhost(port: port)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

private struct WindowPathBlock: View {
    let path: String

    var body: some View {
        Text(path)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
    }
}

private struct WindowNoSelectionView: View {
    let searchText: String

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: searchText.isEmpty ? "sparkles.rectangle.stack" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 42, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)

            Text(searchText.isEmpty ? "Pick a process to inspect it" : "No result for that search")
                .font(.headline)

            Text(searchText.isEmpty
                 ? "The window layout gives you more context here: role, signals, ports, workspace, and quick actions."
                 : "Clear or adjust the sidebar filter to see more processes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct WindowBackdrop: View {
    let accent: Color

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(accent.opacity(0.18))
                .frame(width: 420, height: 420)
                .blur(radius: 110)
                .offset(x: -260, y: -180)

            Circle()
                .fill(Color.orange.opacity(0.14))
                .frame(width: 360, height: 360)
                .blur(radius: 120)
                .offset(x: 320, y: 180)

            Circle()
                .fill(Color.teal.opacity(0.10))
                .frame(width: 300, height: 300)
                .blur(radius: 100)
                .offset(x: 120, y: -220)
        }
    }
}

private func roleNarrative(for process: NodeProcessItemViewModel) -> String {
    switch process.categoryBadge?.lowercased() {
    case "bundler":
        return "This looks like a frontend bundler that builds assets and drives hot reload for a client project."
    case "web framework":
        return "This behaves like a full framework dev server that often serves both the UI and local development APIs."
    case "api/backend":
        return "This looks like a backend or API process that handles local server-side requests or worker jobs."
    case "typescript runner":
        return "This is likely a TypeScript entry point running directly through tsx or similar tooling."
    case "watcher":
        return "This is primarily a file watcher that keeps an underlying development process up to date as code changes."
    case "component workbench":
        return "This resembles a component or design workbench where UI is built and previewed in isolation."
    case "monorepo tool":
        return "This comes from tooling that coordinates multiple packages or apps at once in a monorepo."
    case "mobile":
        return "This appears to be a local mobile or device-oriented development process."
    case "utility":
        return "This is a supporting process that SlayNode still tracks because it affects your local development environment."
    default:
        return "SlayNode combined command, runtime, child processes, and ports to understand what this process is doing."
    }
}

private func colorForCategory(_ category: String?) -> Color {
    switch category?.lowercased() {
    case "web framework":
        return .blue
    case "bundler":
        return .orange
    case "api/backend":
        return .green
    case "typescript runner":
        return .teal
    case "watcher":
        return .mint
    case "component workbench":
        return .yellow
    case "monorepo tool":
        return .brown
    case "mobile":
        return .cyan
    case "dev script":
        return .indigo
    case "utility":
        return .purple
    default:
        return .accentColor
    }
}

private func windowCategoryIcon(for category: String?) -> String {
    switch category?.lowercased() {
    case "settings":
        return "gearshape.2.fill"
    case "about":
        return "app.badge"
    case "web framework":
        return "globe"
    case "bundler":
        return "cube.box"
    case "api/backend":
        return "server.rack"
    case "typescript runner":
        return "curlybraces"
    case "watcher":
        return "eye"
    case "component workbench":
        return "square.on.square"
    case "monorepo tool":
        return "square.stack.3d.down.right"
    case "mobile":
        return "iphone"
    case "dev script":
        return "terminal"
    case "utility":
        return "wrench.and.screwdriver"
    default:
        return "sparkles"
    }
}

private func copyToPasteboard(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
}

private func openDirectory(_ path: String) {
    let url = URL(fileURLWithPath: path)
    NSWorkspace.shared.open(url)
}

private func openLocalhost(port: Int) {
    guard let url = URL(string: "http://127.0.0.1:\(port)") else { return }
    NSWorkspace.shared.open(url)
}

private extension NodeProcessItemViewModel {
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
