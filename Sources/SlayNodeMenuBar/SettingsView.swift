import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: PreferencesStore

    var body: some View {
        Form {
            Section("Uppdateringsintervall") {
                Slider(value: Binding(
                    get: { preferences.refreshInterval },
                    set: { preferences.setRefreshInterval($0) }
                ), in: 2...30, step: 1)

                HStack {
                    Spacer()
                    Text("\(Int(preferences.refreshInterval)) sekunder")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 320)
    }
}
