import Foundation
import Sparkle

final class UpdateController: ObservableObject {
    private let updaterController: SPUStandardUpdaterController
    
    @Published var canCheckForUpdates = false
    @Published var lastUpdateCheckDate: Date?
    
    var updater: SPUUpdater {
        updaterController.updater
    }
    
    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        
        updater.publisher(for: \.lastUpdateCheckDate)
            .assign(to: &$lastUpdateCheckDate)
    }
    
    func checkForUpdates() {
        updater.checkForUpdates()
    }
    
    func checkForUpdatesInBackground() {
        updater.checkForUpdatesInBackground()
    }
}
