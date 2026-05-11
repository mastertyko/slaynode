import Foundation

final class PreferencesStore: ObservableObject {
    @Published private(set) var refreshInterval: TimeInterval

    private let defaults: UserDefaults
    private enum Keys {
        static let refreshInterval = "com.slaynode.preferences.refreshInterval"
    }

    private let intervalRange: ClosedRange<TimeInterval> = 2...30

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedValue = defaults.double(forKey: Keys.refreshInterval)
        let initialValue = storedValue == 0 ? 5 : storedValue
        let clampedValue = max(intervalRange.lowerBound, min(intervalRange.upperBound, initialValue))

        refreshInterval = clampedValue

        if storedValue != 0, abs(clampedValue - storedValue) > 0.01 {
            defaults.set(clampedValue, forKey: Keys.refreshInterval)
        }
    }

    func setRefreshInterval(_ value: TimeInterval) {
        let clamped = clamp(value)
        guard abs(clamped - refreshInterval) > 0.01 else { return }
        refreshInterval = clamped
        defaults.set(clamped, forKey: Keys.refreshInterval)
    }

    private func clamp(_ value: TimeInterval) -> TimeInterval {
        max(intervalRange.lowerBound, min(intervalRange.upperBound, value))
    }
}
