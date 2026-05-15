import Foundation

final class PreferencesStore: ObservableObject {
    @Published private(set) var refreshInterval: TimeInterval

    private let defaults: UserDefaults
    private let intervalRange = Constants.Preferences.refreshIntervalRange

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedObject = defaults.object(forKey: Constants.Preferences.refreshIntervalKey)
        let initialValue: TimeInterval
        let shouldPersistSanitizedValue: Bool

        if let number = storedObject as? NSNumber {
            initialValue = number.doubleValue
            shouldPersistSanitizedValue = true
        } else if storedObject != nil {
            initialValue = Constants.Preferences.defaultRefreshInterval
            shouldPersistSanitizedValue = true
        } else {
            initialValue = Constants.Preferences.defaultRefreshInterval
            shouldPersistSanitizedValue = false
        }

        let finiteInitialValue = initialValue.isFinite ? initialValue : Constants.Preferences.defaultRefreshInterval
        let clampedValue = max(intervalRange.lowerBound, min(intervalRange.upperBound, finiteInitialValue))

        refreshInterval = clampedValue

        if shouldPersistSanitizedValue && (abs(clampedValue - initialValue) > 0.01 || !initialValue.isFinite) {
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
