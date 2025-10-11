import AppKit
import SwiftUI

struct MenuContentView: View {
    @StateObject private var viewModel: MenuViewModel
    @ObservedObject var preferences: PreferencesStore

    private let backgroundColor = Color(nsColor: .clear)
    
    init(preferences: PreferencesStore) {
        self.preferences = preferences
        self._viewModel = StateObject(wrappedValue: MenuViewModel(preferences: preferences))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let error = viewModel.lastError {
                ErrorBanner(text: error)
            }

            content

            Divider()

            PreferencesSectionView(preferences: viewModel.preferences)

            footer
        }
        .padding(16)
        .frame(width: 360)
        .background(backgroundColor)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Node-servrar")
                    .font(.title3.weight(.semibold))
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.isLoading {
                ProgressView()
            }
        }
    }

    private var content: some View {
        Group {
            if viewModel.isLoading && viewModel.processes.isEmpty {
                VStack(alignment: .center, spacing: 12) {
                    ProgressView()
                    Text("Söker efter Node-servrar...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.processes.isEmpty {
                EmptyStateView(refreshAction: viewModel.refresh)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.processes) { process in
                            ProcessRowView(process: process) {
                                viewModel.stopProcess(process.pid)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 280)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                viewModel.refresh()
            } label: {
                Label("Uppdatera nu", systemImage: "arrow.clockwise")
            }

            Spacer()

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Avsluta")
            }
        }
        .buttonStyle(.bordered)
    }

    private var statusText: String {
        if let updated = viewModel.lastUpdated {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            let relative = formatter.localizedString(for: updated, relativeTo: Date())
            return "Senast uppdaterad " + relative
        }
        return ""
    }
}

private struct ProcessRowView: View {
    let process: NodeProcessItemViewModel
    let stopAction: () -> Void

    private let background = Color(nsColor: .windowBackgroundColor)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(process.title)
                        .font(.headline)
                    Text(process.details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if process.isStopping {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(role: .destructive) {
                        stopAction()
                    } label: {
                        Label("Stoppa", systemImage: "stop.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .controlSize(.small)
                }
            }

            if !process.portsDescription.isEmpty {
                Text(process.portsDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(process.subtitle)
                .font(.caption.monospaced())
                .lineLimit(2)

            HStack(spacing: 8) {
                Label(process.uptimeDescription, systemImage: "timer")
                    .font(.caption)
                Label(process.startTimeDescription, systemImage: "clock")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(background.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.05))
        )
        .contextMenu {
            Button("Kopiera kommando") {
                copyToPasteboard(process.command)
            }
            if let directory = process.workingDirectory {
                Button("Öppna i Finder") {
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

private struct EmptyStateView: View {
    let refreshAction: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Inga Node-servrar hittades")
                .font(.headline)
            Text("Starta en server eller uppdatera manuellt.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(action: refreshAction) {
                Label("Sök igen", systemImage: "arrow.clockwise")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                .foregroundStyle(Color.secondary.opacity(0.3))
        )
    }
}

private struct ErrorBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(text)
                .font(.caption)
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.red.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.red.opacity(0.2))
        )
    }
}

private struct PreferencesSectionView: View {
    @ObservedObject var preferences: PreferencesStore

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { preferences.refreshInterval },
            set: { preferences.setRefreshInterval($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Uppdateringsintervall")
                .font(.subheadline.weight(.medium))
            HStack {
                Slider(value: sliderBinding, in: 2...30, step: 1) {
                    Text("Intervall")
                }
                .frame(maxWidth: 200)

                Text("\(Int(preferences.refreshInterval)) s")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
