import AppKit
import SwiftUI

struct AboutWindowView: View {
    var body: some View {
        AuxiliaryWindowShell(accent: Color.accentColor) {
            ScrollView {
                AboutContentView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
        }
        .frame(minWidth: 540, idealWidth: 620, maxWidth: 700, minHeight: 400, idealHeight: 460, maxHeight: 560)
    }
}

struct AboutContentView: View {
    private let accent = Color.accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AuxiliaryHeroCard(
                title: "About SlayNode",
                subtitle: "Product details, version information, and project links without leaving the main workflow.",
                systemImage: "app.badge",
                accent: accent
            ) {
                if let appIcon = slayNodeAppIcon() {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: accent.opacity(0.22), radius: 16, y: 6)
                }
            }

            HStack(spacing: 8) {
                AuxiliaryPill(text: shortVersion, systemImage: "app.badge", tint: accent)
                AuxiliaryPill(text: buildNumber, systemImage: "number", tint: .orange)
                AuxiliaryPill(text: "macOS 26+", systemImage: "laptopcomputer", tint: .secondary)
            }

            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 18) {
                AuxiliarySectionCard(
                    title: "Built native",
                    systemImage: "macwindow.on.rectangle",
                    accent: accent
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        aboutBullet("NavigationSplitView with inspector-first workflows")
                        aboutBullet("Workspace-aware restoration and focused windows")
                        aboutBullet("Shared service model across dashboard and menu bar")
                    }
                }

                AuxiliarySectionCard(
                    title: "Baseline",
                    systemImage: "checkmark.shield",
                    accent: .orange
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        aboutFact(label: "Minimum macOS", value: "26")
                        aboutFact(label: "Control sources", value: "Process, Docker, Brew")
                        aboutFact(label: "Design system", value: "Tahoe-native Liquid Glass")
                    }
                }
            }

            AuxiliarySectionCard(
                title: "What it gives you",
                systemImage: "waveform.path.ecg",
                accent: accent
            ) {
                Text("SlayNode brings detection, context, and safe stop actions into one place so you can manage local development services without jumping between terminals.")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            AuxiliarySectionCard(
                title: "Links",
                systemImage: "link",
                accent: .orange
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    WindowLinkRow(label: "GitHub", value: "github.com/mastertyko/slaynode") {
                        openExternalURL("https://github.com/mastertyko/slaynode")
                    }

                    WindowLinkRow(label: "Issues", value: "github.com/mastertyko/slaynode/issues") {
                        openExternalURL("https://github.com/mastertyko/slaynode/issues")
                    }
                }
            }

            Text("All process detection stays on your Mac. Use the GitHub links above for source, releases and issue reporting.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        "Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")"
    }

    @ViewBuilder
    private func aboutBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(accent)
                .padding(.top, 2)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func aboutFact(label: String, value: String) -> some View {
        LabeledContent(label) {
            Text(value)
        }
    }
}

private struct WindowLinkRow: View {
    let label: String
    let value: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 62, alignment: .leading)

            Button(action: action) {
                HStack(spacing: 6) {
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

private func openExternalURL(_ urlString: String) {
    guard let url = URL(string: urlString) else { return }
    NSWorkspace.shared.open(url)
}
