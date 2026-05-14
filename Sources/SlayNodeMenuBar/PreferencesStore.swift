import Foundation

final class PreferencesStore: ObservableObject {
    @Published private(set) var refreshInterval: TimeInterval

    private let defaults: UserDefaults
    private let intervalRange = Constants.Preferences.refreshIntervalRange

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedValue = defaults.double(forKey: Constants.Preferences.refreshIntervalKey)
        let initialValue = storedValue == 0 ? Constants.Preferences.defaultRefreshInterval : storedValue
        let clampedValue = max(intervalRange.lowerBound, min(intervalRange.upperBound, initialValue))

        refreshInterval = clampedValue

        if storedValue != 0, abs(clampedValue - storedValue) > 0.01 {
            defaults.set(clampedValue, forKey: Constants.Preferences.refreshIntervalKey)
        }
    }

    func setRefreshInterval(_ value: TimeInterval) {
        let clamped = clamp(value)
        guard abs(clamped - refreshInterval) > 0.01 else { return }
        refreshInterval = clamped
        defaults.set(clamped, forKey: Constants.Preferences.refreshIntervalKey)
    }

    private func clamp(_ value: TimeInterval) -> TimeInterval {
        max(intervalRange.lowerBound, min(intervalRange.upperBound, value))
    }
}
