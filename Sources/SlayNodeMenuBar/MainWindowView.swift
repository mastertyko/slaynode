import SwiftUI

struct MainWindowView: View {
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var updateController: UpdateController
    @Binding var activeSheet: AuxiliarySheet?

    private let monitor: any ProcessMonitoring

    init(
        preferences: PreferencesStore,
        monitor: any ProcessMonitoring,
        updateController: UpdateController,
        activeSheet: Binding<AuxiliarySheet?>
    ) {
        self.preferences = preferences
        self.monitor = monitor
        self.updateController = updateController
        self._activeSheet = activeSheet
    }

    var body: some View {
        MenuContentView(
            preferences: preferences,
            monitor: monitor,
            presentation: .mainWindow,
            updateController: updateController,
            activeAuxiliary: activeSheet,
            showAboutAction: { activeSheet = .about },
            openSettingsAction: { activeSheet = .settings },
            dismissAuxiliaryAction: { activeSheet = nil }
        )
            .frame(minWidth: 1020, idealWidth: 1240, maxWidth: 1480, minHeight: 720, idealHeight: 860, alignment: .top)
    }
}
