import AppKit
import SwiftUI

struct MenuContentView: View {
    @StateObject private var viewModel: MenuViewModel
    @ObservedObject var preferences: PreferencesStore
    
    private let panelCornerRadius: CGFloat = 24
    private let headerCornerRadius: CGFloat = 18
    
    init(preferences: PreferencesStore) {
        self.preferences = preferences
        self._viewModel = StateObject(wrappedValue: MenuViewModel(preferences: preferences))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            
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
        .padding(22)
        .frame(width: 380, alignment: .leading)
        .glassPanel(cornerRadius: panelCornerRadius)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isLoading)
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Development Servers")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                    Text(statusText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                
                Spacer()
                
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(.white.opacity(0.9))
                }
            }
            
            if !viewModel.processes.isEmpty {
                Text("\(viewModel.processes.count) active \(viewModel.processes.count == 1 ? "server" : "servers")")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.78))
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
                    Text("Searching for development servers…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 32)
            } else if viewModel.processes.isEmpty {
                EmptyStateView(refreshAction: viewModel.refresh)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(viewModel.processes) { process in
                            ProcessRowView(process: process) {
                                viewModel.stopProcess(process.pid)
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 600)
            }
        }
        .frame(minHeight: 300) // Ensure minimum height even when empty
    }
    
    private var footer: some View {
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
            
            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
    
    private var statusText: String {
        guard let updated = viewModel.lastUpdated else {
            return "Waiting for first refresh"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: updated, relativeTo: Date())
        return "Updated \(relative)"
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
}

private struct ProcessRowView: View {
    let process: NodeProcessItemViewModel
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
                    ProgressView()
                        .controlSize(.small)
                        .tint(.secondary)
                } else {
                    Button(role: .destructive) {
                        stopAction()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                }
            }

            // Subtitle (command)
            if !process.subtitle.isEmpty {
                Text(process.subtitle)
                    .font(.caption.monospaced())
                    .lineLimit(1)
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
        switch text {
        case "Web Framework":
            return Color.blue.opacity(0.15)
        case "Bundler":
            return Color.orange.opacity(0.15)
        case "Framework":
            return Color.cyan.opacity(0.15)
        case "Server":
            return Color.green.opacity(0.15)
        case "Utility":
            return Color.purple.opacity(0.15)
        case "Tool":
            return Color.mint.opacity(0.15)
        case "MCP Tool":
            return Color.pink.opacity(0.15)
        case "Development":
            return Color.indigo.opacity(0.15)
        case "Node.js":
            return Color.green.opacity(0.1)
        default:
            return Color.secondary.opacity(0.15)
        }
    }

    private var categoryForeground: Color {
        switch text {
        case "Web Framework":
            return Color.blue
        case "Bundler":
            return Color.orange
        case "Framework":
            return Color.cyan
        case "Server":
            return Color.green
        case "Utility":
            return Color.purple
        case "Tool":
            return Color.mint
        case "MCP Tool":
            return Color.pink
        case "Development":
            return Color.indigo
        case "Node.js":
            return Color.green
        default:
            return Color.secondary
        }
    }
}

// Helper function to get appropriate icon for each category
private func iconForCategory(_ category: String) -> String {
    switch category {
    case "Web Framework":
        return "globe"
    case "Bundler":
        return "cube.box"
    case "Framework":
        return "square.stack.3d.up"
    case "Server":
        return "server.rack"
    case "Utility":
        return "wrench.and.screwdriver"
    case "Tool":
        return "hammer"
    case "MCP Tool":
        return "brain.head.profile"
    case "Development":
        return "hammer.circle"
    case "Node.js":
        return "hexagon"
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
            } else {
                HStack(spacing: 4) {
                    if let systemImage = chip.systemImage {
                        Image(systemName: systemImage)
                            .font(.caption2)
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

private struct EmptyStateView: View {
    let refreshAction: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "server.rack")
                .font(.system(size: 42, weight: .regular, design: .rounded))
                .foregroundStyle(.tertiary)

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


private struct ErrorBanner: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
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
