import Combine
import Foundation
import Sparkle

final class UpdateController: ObservableObject {
    struct Configuration {
        let feedURL: String?
        let publicEDKey: String?

        init(bundle: Bundle) {
            let info = bundle.infoDictionary ?? [:]
            self.feedURL = info["SUFeedURL"] as? String
            self.publicEDKey = info["SUPublicEDKey"] as? String
        }

        init(feedURL: String?, publicEDKey: String?) {
            self.feedURL = feedURL
            self.publicEDKey = publicEDKey
        }

        var isValid: Bool {
            guard let feedURL = trimmed(feedURL),
                  let publicEDKey = trimmed(publicEDKey) else {
                return false
            }

            return !feedURL.isEmpty && !publicEDKey.isEmpty
        }

        private func trimmed(_ value: String?) -> String? {
            value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private let updaterController: SPUStandardUpdaterController?
    private var cancellables: Set<AnyCancellable> = []
    private var pendingBackgroundCheck = false
    private let configuration: Configuration
    
    @Published var canCheckForUpdates = false
    @Published var lastUpdateCheckDate: Date?
    
    private var updater: SPUUpdater? {
        updaterController?.updater
    }
    
    init(configuration: Configuration = Configuration(bundle: .main)) {
        self.configuration = configuration

        guard configuration.isValid else {
            canCheckForUpdates = false
            lastUpdateCheckDate = nil
            updaterController = nil
            return
        }

        let updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.updaterController = updaterController
        
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheck in
                guard let self = self else { return }
                self.canCheckForUpdates = canCheck

                guard canCheck, self.pendingBackgroundCheck else { return }
                self.pendingBackgroundCheck = false
                self.updater?.checkForUpdatesInBackground()
            }
            .store(in: &cancellables)
        
        updaterController.updater.publisher(for: \.lastUpdateCheckDate)
            .assign(to: &$lastUpdateCheckDate)
    }
    
    func checkForUpdates() {
        updater?.checkForUpdates()
    }
    
    func checkForUpdatesInBackground() {
        guard configuration.isValid else {
            return
        }

        guard let updater else {
            return
        }

        guard updater.canCheckForUpdates else {
            pendingBackgroundCheck = true
            return
        }

        updater.checkForUpdatesInBackground()
    }
}
