import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var updateController: UpdateController
    let openAboutAction: (() -> Void)?

    init(
        preferences: PreferencesStore,
        updateController: UpdateController,
        openAboutAction: (() -> Void)? = nil
    ) {
        self.preferences = preferences
        self.updateController = updateController
        self.openAboutAction = openAboutAction
    }

    var body: some View {
        AuxiliaryWindowShell(accent: Color.accentColor) {
            SettingsContentView(
                preferences: preferences,
                updateController: updateController,
                openAboutAction: openAboutAction
            )
        }
        .frame(minWidth: 560, idealWidth: 620, maxWidth: 680, minHeight: 420, idealHeight: 460, maxHeight: 520)
    }
}

struct SettingsContentView: View {
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var updateController: UpdateController
    @Environment(\.openWindow) private var openWindow
    private let openAboutAction: (() -> Void)?

    private let accent = Color.accentColor

    init(
        preferences: PreferencesStore,
        updateController: UpdateController,
        openAboutAction: (() -> Void)? = nil
    ) {
        self.preferences = preferences
        self.updateController = updateController
        self.openAboutAction = openAboutAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AuxiliaryHeroCard(
                title: "Settings",
                subtitle: "Adjust scan cadence and app behavior without leaving the runtime workspace.",
                systemImage: "gearshape.2.fill",
                accent: accent
            ) {
                VStack(alignment: .trailing, spacing: 8) {
                    AuxiliaryPill(text: "\(Int(preferences.refreshInterval))s refresh", systemImage: "timer", tint: .orange)
                    AuxiliaryPill(text: appVersion, systemImage: "app.badge", tint: accent)
                }
            }

            AuxiliarySectionCard(
                title: "Scan cadence",
                systemImage: "timer",
                accent: .orange
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Refresh interval")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(Int(preferences.refreshInterval)) seconds")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: Binding(
                        get: { preferences.refreshInterval },
                        set: { preferences.setRefreshInterval($0) }
                    ), in: 2...30, step: 1)
                    .tint(.orange)
                    .accessibilityLabel("Refresh interval")
                    .accessibilityValue("\(Int(preferences.refreshInterval)) seconds")

                    Text("Use a faster interval when you want tighter feedback, or a slower one to keep scanning lighter.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            AuxiliarySectionCard(
                title: "Updates",
                systemImage: "arrow.trianglehead.clockwise",
                accent: accent
            ) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Automatic updates")
                            .font(.subheadline.weight(.semibold))

                        Text(lastCheckDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !updateController.canCheckForUpdates {
                            Text("Update checks are unavailable in this local build configuration.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button("Check Now") {
                        updateController.checkForUpdates()
                    }
                    .buttonStyle(AuxiliaryPrimaryButtonStyle(tint: accent))
                    .disabled(!updateController.canCheckForUpdates)
                    .accessibilityLabel("Check for updates")
                }
            }

            AuxiliarySectionCard(
                title: "App",
                systemImage: "app.badge",
                accent: .teal
            ) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SlayNode")
                            .font(.subheadline.weight(.semibold))

                        Text("Version \(appVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Open About") {
                        if let openAboutAction {
                            openAboutAction()
                        } else {
                            openWindow(id: AppWindowID.about)
                        }
                    }
                    .buttonStyle(AuxiliaryPrimaryButtonStyle(tint: accent))
                }
            }
        }
    }
    
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var lastCheckDescription: String {
        if let lastCheck = updateController.lastUpdateCheckDate {
            return "Last checked \(lastCheck.formatted(date: .abbreviated, time: .shortened))"
        }

        return "No update checks recorded yet."
    }
}
