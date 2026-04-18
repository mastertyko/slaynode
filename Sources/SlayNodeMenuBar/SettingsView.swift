import Observation
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @ObservedObject var updateController: UpdateController
    let openAboutAction: (() -> Void)?

    init(
        settings: AppSettings,
        updateController: UpdateController,
        openAboutAction: (() -> Void)? = nil
    ) {
        self.settings = settings
        self.updateController = updateController
        self.openAboutAction = openAboutAction
    }

    var body: some View {
        AuxiliaryWindowShell(accent: Color.accentColor) {
            ScrollView {
                SettingsContentView(
                    settings: settings,
                    updateController: updateController,
                    openAboutAction: openAboutAction
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
        }
        .frame(minWidth: 520, idealWidth: 580, maxWidth: 640, minHeight: 400, idealHeight: 448, maxHeight: 520)
    }
}

struct SettingsContentView: View {
    @Bindable var settings: AppSettings
    @ObservedObject var updateController: UpdateController
    @Environment(\.openWindow) private var openWindow
    private let openAboutAction: (() -> Void)?

    private let accent = Color.accentColor

    init(
        settings: AppSettings,
        updateController: UpdateController,
        openAboutAction: (() -> Void)? = nil
    ) {
        self.settings = settings
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
                    AuxiliaryPill(text: "\(Int(settings.refreshInterval))s refresh", systemImage: "timer", tint: .orange)
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
                        Text("\(Int(settings.refreshInterval)) seconds")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $settings.refreshInterval, in: 3...60, step: 1)
                    .tint(.orange)
                    .accessibilityLabel("Refresh interval")
                    .accessibilityValue("\(Int(settings.refreshInterval)) seconds")

                    Text("Use a faster interval when you want tighter feedback, or a slower one to keep scanning lighter.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            AuxiliarySectionCard(
                title: "Experience",
                systemImage: "sparkles",
                accent: .teal
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Show recent history in the app and inspector", isOn: $settings.showRecentHistory)
                    Divider()
                    Toggle("Show expanded summary in the menu bar panel", isOn: $settings.showMenuBarSection)
                }
            }

            AuxiliarySectionCard(
                title: "Notifications",
                systemImage: "bell.badge",
                accent: .pink
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Notify when a service action fails", isOn: $settings.showFailureNotifications)
                    Divider()
                    Toggle("Notify when a service becomes critical", isOn: $settings.showHealthNotifications)

                    if settings.showFailureNotifications || settings.showHealthNotifications {
                        Divider()

                        HStack {
                            Text("Repeat cooldown")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(Int(settings.notificationCooldownMinutes)) min")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $settings.notificationCooldownMinutes, in: 1...30, step: 1)
                            .tint(.pink)
                            .accessibilityLabel("Notification cooldown")
                            .accessibilityValue("\(Int(settings.notificationCooldownMinutes)) minutes")

                        Text("Repeated failures or flapping health states stay quiet until the cooldown window passes. Notifications remain local to this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("All local notifications are currently turned off.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

                    if updateController.canCheckForUpdates {
                        Button("Check Now") {
                            updateController.checkForUpdates()
                        }
                        .buttonStyle(AuxiliaryPrimaryButtonStyle(tint: accent))
                        .accessibilityLabel("Check for updates")
                    } else {
                        AuxiliaryPill(
                            text: "Unavailable in local build",
                            systemImage: "wrench.and.screwdriver",
                            tint: .secondary
                        )
                    }
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

                        Text("The utility windows now follow the same Tahoe-native material language as the main control room.")
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

struct LegacySettingsContentView: View {
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var updateController: UpdateController
    @Environment(\.openWindow) private var openWindow
    let openAboutAction: (() -> Void)?

    private let accent = Color.accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AuxiliaryHeroCard(
                title: "Settings",
                subtitle: "Tune scan cadence and supporting app behavior from the current workspace view.",
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
                    }

                    Spacer()

                    if updateController.canCheckForUpdates {
                        Button("Check Now") {
                            updateController.checkForUpdates()
                        }
                        .buttonStyle(AuxiliaryPrimaryButtonStyle(tint: accent))
                    } else {
                        AuxiliaryPill(
                            text: "Unavailable in local build",
                            systemImage: "wrench.and.screwdriver",
                            tint: .secondary
                        )
                    }
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
