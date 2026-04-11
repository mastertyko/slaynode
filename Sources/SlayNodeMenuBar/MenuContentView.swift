import AppKit
import SwiftUI

struct MenuContentView: View {
    @Environment(\.openWindow) private var openWindow

    enum Presentation: Equatable {
        case menuBarPopover
        case mainWindow
    }

    @StateObject private var viewModel: MenuViewModel
    @ObservedObject var preferences: PreferencesStore
    private let presentation: Presentation
    private let updateController: UpdateController?
    private let activeAuxiliary: AuxiliarySheet?
    private let showAboutActionOverride: (() -> Void)?
    private let openSettingsActionOverride: (() -> Void)?
    private let dismissAuxiliaryActionOverride: (() -> Void)?

    private let panelCornerRadius: CGFloat = 24
    private let headerCornerRadius: CGFloat = 18

    init(
        preferences: PreferencesStore,
        monitor: any ProcessMonitoring,
        presentation: Presentation = .menuBarPopover,
        updateController: UpdateController? = nil,
        activeAuxiliary: AuxiliarySheet? = nil,
        showAboutAction: (() -> Void)? = nil,
        openSettingsAction: (() -> Void)? = nil,
        dismissAuxiliaryAction: (() -> Void)? = nil
    ) {
        self.preferences = preferences
        self.presentation = presentation
        self.updateController = updateController
        self.activeAuxiliary = activeAuxiliary
        self.showAboutActionOverride = showAboutAction
        self.openSettingsActionOverride = openSettingsAction
        self.dismissAuxiliaryActionOverride = dismissAuxiliaryAction
        self._viewModel = StateObject(wrappedValue: MenuViewModel(preferences: preferences, monitor: monitor))
    }
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            surface(currentTime: context.date)
        }
    }

    private var isWindowPresentation: Bool {
        presentation == .mainWindow
    }

    @ViewBuilder
    private func surface(currentTime: Date) -> some View {
        if isWindowPresentation {
            WindowDashboardView(
                viewModel: viewModel,
                preferences: preferences,
                updateController: updateController,
                statusText: statusText(currentTime: currentTime),
                statusIcon: statusIcon(currentTime: currentTime),
                activeAuxiliary: activeAuxiliary,
                showAboutAction: showAboutDialog,
                openSettingsAction: openSettingsLegacy,
                dismissAuxiliaryAction: dismissAuxiliary,
                quitAction: { NSApplication.shared.terminate(nil) }
            )
        } else {
            sharedContent(currentTime: currentTime)
                .padding(22)
                .frame(width: 380, alignment: .leading)
                .glassPanel(cornerRadius: panelCornerRadius)
        }
    }

    @ViewBuilder
    private func sharedContent(currentTime: Date) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            header(currentTime: currentTime)

            if let error = viewModel.lastError {
                ErrorBanner(text: error)
                    .transition(.opacity)
            }

            content
                .animation(.spring(response: 0.32, dampingFraction: 0.88), value: viewModel.processes)

            Divider()
                .padding(.horizontal, -12)
                .overlay(Color.white.opacity(0.08))

            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isLoading)
    }

    private func showAboutDialog() {
        if let showAboutActionOverride {
            showAboutActionOverride()
        } else {
            openWindow(id: AppWindowID.about)
        }
    }

    private func header(currentTime: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isWindowPresentation ? "Development Servers" : "SlayNode - The Easy Way!")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.92))

                    if isWindowPresentation {
                        Text("Monitor and stop active local Node.js servers without jumping between terminals.")
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: statusIcon(currentTime: currentTime))
                            .font(.caption2)
                            .foregroundStyle(Color.white.opacity(0.85))
                            .accessibilityHidden(true)
                        Text(statusText(currentTime: currentTime))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        showAboutDialog()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .help("About SlayNode")
                    .accessibilityLabel("About SlayNode")

                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                            .tint(.white.opacity(0.9))
                            .accessibilityLabel("Refreshing processes")
                    }
                }
            }
            
            HStack(spacing: 8) {
                if !viewModel.processes.isEmpty {
                    Text("\(viewModel.processes.count) active \(viewModel.processes.count == 1 ? "server" : "servers")")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.78))
                }

                if isWindowPresentation {
                    Text("Updates every \(Int(preferences.refreshInterval))s")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.72))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.10))
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: headerCornerRadius, style: .continuous)
                .fill(headerGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: headerCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.25))
                )
        )
        .shadow(color: headerShadow, radius: 14, y: 8)
    }
    
    private var content: some View {
        Group {
            if viewModel.isLoading && viewModel.processes.isEmpty {
                VStack(alignment: .center, spacing: 12) {
                    ProgressView()
                        .accessibilityLabel("Scanning for servers")
                    Text("Searching for development servers…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 32)
            } else if viewModel.processes.isEmpty {
                EmptyStateView(refreshAction: { viewModel.refresh() })
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(viewModel.processes) { process in
                            ProcessRowView(process: process, presentation: presentation) {
                                viewModel.stopProcess(process.pid)
                            }
                            .transition(.scale.combined(with: .opacity))
                            .animation(.easeInOut(duration: 0.4), value: viewModel.processes)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: isWindowPresentation ? .infinity : 600)
            }
        }
        .frame(minHeight: isWindowPresentation ? 420 : 300)
    }
    
    private var footer: some View {
        Group {
            if isWindowPresentation {
                HStack(spacing: 10) {
                    Button {
                        viewModel.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    settingsButton

                    Button {
                        showAboutDialog()
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Spacer()

                    Button(role: .destructive) {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Label("Quit", systemImage: "power")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            } else {
                HStack(spacing: 12) {
                    Button {
                        viewModel.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .labelStyle(.titleAndIcon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    compactSettingsButton

                    Button(role: .destructive) {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Label("Quit", systemImage: "power")
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityLabel("Quit SlayNode")
                }
            }
        }
    }
    
    private func statusText(currentTime: Date) -> String {
        guard let updated = viewModel.lastUpdated else {
            return "Waiting for first refresh"
        }

        let timeInterval = currentTime.timeIntervalSince(updated)
        let refreshInterval = max(preferences.refreshInterval, 1)

        if timeInterval < refreshInterval {
            let secondsUntilNext = max(1, Int(ceil(refreshInterval - timeInterval)))
            return "Next update in \(secondsUntilNext)s"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let relative = formatter.localizedString(for: updated, relativeTo: currentTime)
        return "Updated \(relative)"
    }

    private func statusIcon(currentTime: Date) -> String {
        guard let updated = viewModel.lastUpdated else {
            return "clock"
        }

        let timeInterval = currentTime.timeIntervalSince(updated)
        let refreshInterval = max(preferences.refreshInterval, 1)

        if timeInterval < refreshInterval {
            return "timer"
        }

        if timeInterval < 30 {
            return "checkmark.circle.fill"
        }

        return "clock"
    }

    private var settingsButton: some View {
        Button {
            openSettingsLegacy()
        } label: {
            Label("Settings", systemImage: "gearshape")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private var compactSettingsButton: some View {
        Button {
            openSettingsLegacy()
        } label: {
            Label("Settings", systemImage: "gearshape")
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityLabel("Open Settings")
    }

    private func openSettingsLegacy() {
        if let openSettingsActionOverride {
            openSettingsActionOverride()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: AppWindowID.settings)
        }
    }

    private func dismissAuxiliary() {
        dismissAuxiliaryActionOverride?()
    }
    
    private var headerGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.65),
                Color.blue.opacity(0.45)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var headerShadow: Color {
        Color.accentColor.opacity(0.35)
    }

    private var windowBackground: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color.accentColor.opacity(0.10),
                Color(nsColor: .underPageBackgroundColor)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var windowPanelBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.08))
            )
            .shadow(color: Color.black.opacity(0.16), radius: 26, y: 12)
    }
}

private struct ProcessRowView: View {
    let process: NodeProcessItemViewModel
    let presentation: MenuContentView.Presentation
    let stopAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Main info row with title, category, ports, and stop button
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    // Title and category
                    VStack(alignment: .leading, spacing: 4) {
                        Text(process.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let category = process.categoryBadge {
                            CapsuleLabel(text: category, icon: iconForCategory(category))
                        }
                    }

                    // Port badges
                    if !process.portBadges.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(process.portBadges, id: \.self) { badge in
                                PortBadgeView(badge: badge)
                            }
                        }
                    }
                }

                Spacer()

                // Stop button
                if process.isStopping {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.secondary)
                            .accessibilityLabel("Stopping \(process.title)")
                        Text("Slaying...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
                } else {
                    Button(role: .destructive) {
                        stopAction()
                    } label: {
                        Label("Slay", systemImage: "xmark.square.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Stop process \(process.title)")
                }
            }

            // Subtitle (command)
            if !process.subtitle.isEmpty {
                Text(process.subtitle)
                    .font(.caption.monospaced())
                    .lineLimit(presentation == .mainWindow ? 2 : 1)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            // Info chips (URL, Node.js, etc.)
            if !process.infoChips.isEmpty {
                HStack(spacing: 4) {
                    ForEach(process.infoChips, id: \.self) { chip in
                        InfoChipView(chip: chip)
                    }
                }
                .padding(.top, 4)
            }

            // Metadata row
            HStack(spacing: 16) {
                Label("PID \(process.pid)", systemImage: "number")
                    .font(.caption2)
                Label(process.uptimeDescription, systemImage: "timer")
                    .font(.caption2)
                Label(process.startTimeDescription, systemImage: "clock")
                    .font(.caption2)
                if let name = process.projectName {
                    Label(name, systemImage: "folder")
                        .font(.caption2)
                }
            }
            .foregroundStyle(.secondary)
            .padding(.top, 6)
        }
        .padding(16)
        .glassTile(cornerRadius: 16)
        .scaleEffect(process.isStopping ? 0.98 : 1.0)
        .opacity(process.isStopping ? 0.8 : 1.0)
        .animation(.easeInOut(duration: 0.3), value: process.isStopping)
        .contextMenu {
            Button("Copy Command") {
                copyToPasteboard(process.command)
            }
            if let directory = process.workingDirectory {
                Button("Open in Finder") {
                    openDirectory(directory)
                }
            }
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
}

private struct PortBadgeView: View {
    let badge: NodeProcessItemViewModel.PortBadge

    var body: some View {
        Text(badgeText)
            .font(.caption2.monospacedDigit())
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(portBackground)
            .foregroundStyle(portForeground)
            .clipShape(Capsule())
    }

    private var badgeText: String {
        badge.isLikely ? "≈ \(badge.text)" : badge.text
    }

    private var portBackground: Color {
        badge.isLikely ? Color.orange.opacity(0.12) : Color.accentColor.opacity(0.18)
    }

    private var portForeground: Color {
        badge.isLikely ? Color.orange : Color.accentColor
    }
}

private struct CapsuleLabel: View {
    let text: String
    let icon: String?

    init(text: String, icon: String? = nil) {
        self.text = text
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption2)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(categoryBackground)
        .clipShape(Capsule())
        .foregroundStyle(categoryForeground)
        .allowsTightening(true)
    }

    private var categoryBackground: Color {
        switch normalizedText {
        case "web framework":
            return Color.blue.opacity(0.15)
        case "bundler":
            return Color.orange.opacity(0.15)
        case "framework":
            return Color.cyan.opacity(0.15)
        case "server":
            return Color.green.opacity(0.15)
        case "utility":
            return Color.purple.opacity(0.15)
        case "dev script":
            return Color.indigo.opacity(0.15)
        case "typescript runner":
            return Color.teal.opacity(0.15)
        case "watcher":
            return Color.mint.opacity(0.15)
        case "tool":
            return Color.mint.opacity(0.15)
        case "mcp tool":
            return Color.pink.opacity(0.15)
        case "development":
            return Color.indigo.opacity(0.15)
        case "node.js", "runtime":
            return Color.green.opacity(0.1)
        case "api/backend":
            return Color.green.opacity(0.15)
        case "component workbench":
            return Color.yellow.opacity(0.15)
        case "monorepo tool":
            return Color.brown.opacity(0.15)
        case "mobile":
            return Color.cyan.opacity(0.15)
        default:
            return Color.secondary.opacity(0.15)
        }
    }

    private var categoryForeground: Color {
        switch normalizedText {
        case "web framework":
            return Color.blue
        case "bundler":
            return Color.orange
        case "framework":
            return Color.cyan
        case "server":
            return Color.green
        case "utility":
            return Color.purple
        case "dev script":
            return Color.indigo
        case "typescript runner":
            return Color.teal
        case "watcher":
            return Color.mint
        case "tool":
            return Color.mint
        case "mcp tool":
            return Color.pink
        case "development":
            return Color.indigo
        case "node.js", "runtime":
            return Color.green
        case "api/backend":
            return Color.green
        case "component workbench":
            return Color.yellow
        case "monorepo tool":
            return Color.brown
        case "mobile":
            return Color.cyan
        default:
            return Color.secondary
        }
    }

    private var normalizedText: String {
        text.lowercased()
    }
}

// Helper function to get appropriate icon for each category
private func iconForCategory(_ category: String) -> String {
    switch category.lowercased() {
    case "web framework":
        return "globe"
    case "bundler":
        return "cube.box"
    case "framework":
        return "square.stack.3d.up"
    case "server":
        return "server.rack"
    case "utility":
        return "wrench.and.screwdriver"
    case "dev script":
        return "terminal"
    case "typescript runner":
        return "curlybraces"
    case "watcher":
        return "eye"
    case "tool":
        return "hammer"
    case "mcp tool":
        return "brain.head.profile"
    case "development":
        return "hammer.circle"
    case "node.js", "runtime":
        return "hexagon"
    case "api/backend":
        return "server.rack"
    case "component workbench":
        return "square.on.square"
    case "monorepo tool":
        return "square.stack.3d.down.right"
    case "mobile":
        return "iphone"
    default:
        return "tag"
    }
}

private struct InfoChipView: View {
    let chip: NodeProcessItemViewModel.InfoChip

    var body: some View {
        Group {
            if isURL(chip.text) {
                Button(action: { openURL(chip.text) }) {
                    HStack(spacing: 4) {
                        if let systemImage = chip.systemImage {
                            Image(systemName: systemImage)
                                .font(.caption2)
                                .accessibilityHidden(true)
                        }
                        Text(chip.text)
                            .font(.caption2)
                            .underline()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.15))
                    .clipShape(Capsule())
                    .foregroundStyle(Color.blue)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens in browser")
            } else {
                HStack(spacing: 4) {
                    if let systemImage = chip.systemImage {
                        Image(systemName: systemImage)
                            .font(.caption2)
                            .accessibilityHidden(true)
                    }
                    Text(chip.text)
                        .font(.caption2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06))
                .clipShape(Capsule())
                .foregroundStyle(Color.secondary)
            }
        }
    }

    private func isURL(_ text: String) -> Bool {
        return text.hasPrefix("http://") || text.hasPrefix("https://")
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

struct EmptyStateView: View {
    let refreshAction: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "server.rack")
                .font(.system(size: 42, weight: .regular, design: .rounded))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text("No Development Servers Found")
                .font(.headline)

            Text("Start a server or refresh to scan again.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: refreshAction) {
                Label("Search Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .glassTile(cornerRadius: 16)
    }
}


struct ErrorBanner: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .accessibilityLabel("Warning")
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .glassTile(cornerRadius: 14)
    }
}

private extension View {
    func glassPanel(cornerRadius: CGFloat) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    LinearGradient(
                        colors: [Color.white.opacity(0.25), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.14))
                )
        )
        .shadow(color: Color.black.opacity(0.22), radius: 24, y: 18)
    }
    
    func glassTile(cornerRadius: CGFloat) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.08))
                )
        )
        .shadow(color: Color.black.opacity(0.12), radius: 10, y: 5)
    }
}
