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
            
            PreferencesSectionView(preferences: viewModel.preferences)
                .padding(.top, 4)
            
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(process.title)
                            .font(.headline)
                        if let category = process.categoryBadge {
                            CapsuleLabel(text: category)
                        }
                    }

                    if !process.portBadges.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(process.portBadges, id: \.self) { badge in
                                PortBadgeView(badge: badge)
                            }
                        }
                    }
                }
                Spacer()
                if process.isStopping {
                    ProgressView()
                        .controlSize(.small)
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

            if !process.subtitle.isEmpty {
                Text(process.subtitle)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }

            if !process.infoChips.isEmpty {
                HStack(spacing: 6) {
                    ForEach(process.infoChips, id: \.self) { chip in
                        InfoChipView(chip: chip)
                    }
                }
            }

            HStack(spacing: 12) {
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

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
            .foregroundStyle(Color.secondary)
    }
}

private struct InfoChipView: View {
    let chip: NodeProcessItemViewModel.InfoChip

    var body: some View {
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

private struct PreferencesSectionView: View {
    @ObservedObject var preferences: PreferencesStore
    
    private var intervalBinding: Binding<Double> {
        Binding<Double>(
            get: { preferences.refreshInterval },
            set: { preferences.setRefreshInterval($0) }
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Refresh Interval")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(preferences.refreshInterval))s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            
            Slider(value: intervalBinding, in: 2...30, step: 1)
                .tint(.accentColor)
            
            Text("Slaynode scans for new servers on this cadence. Lower values keep the list fresher at the cost of more system I/O.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
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
