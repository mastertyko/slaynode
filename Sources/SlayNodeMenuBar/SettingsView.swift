import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var updateController: UpdateController

    var body: some View {
        Form {
            Section("Refresh Interval") {
                Slider(value: Binding(
                    get: { preferences.refreshInterval },
                    set: { preferences.setRefreshInterval($0) }
                ), in: 2...30, step: 1)
                .accessibilityLabel("Refresh interval")
                .accessibilityValue("\(Int(preferences.refreshInterval)) seconds")

                HStack {
                    Spacer()
                    Text("\(Int(preferences.refreshInterval)) seconds")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Updates") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Automatic Updates")
                        if let lastCheck = updateController.lastUpdateCheckDate {
                            Text("Last checked: \(lastCheck, style: .relative) ago")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button("Check Now") {
                        updateController.checkForUpdates()
                    }
                    .disabled(!updateController.canCheckForUpdates)
                    .accessibilityLabel("Check for updates")
                }
            }
            
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 320)
    }
    
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
