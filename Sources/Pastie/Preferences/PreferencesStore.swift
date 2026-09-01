import Foundation

final class PreferencesStore {
    private let defaults: UserDefaults

    private enum Keys {
        static let excludedBundleIDs = "excludedBundleIDs"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var excludedBundleIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Keys.excludedBundleIDs) ?? []) }
        set { defaults.set(Array(newValue), forKey: Keys.excludedBundleIDs) }
    }
}
